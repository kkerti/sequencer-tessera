# 2026-04-28 — LuaSrcDiet limitation: bitwise operators

## The limitation

LuaSrcDiet 1.0.0 (latest on LuaRocks) was authored against the Lua 5.1 grammar. Its lexer and parser (`/opt/homebrew/share/lua/5.5/luasrcdiet/llex.lua` and `lparser.lua`) do **not** recognise the bitwise operators introduced in Lua 5.3:

- `<<`  (shift left)
- `>>`  (shift right)
- `&`   (bitwise AND)
- `|`   (bitwise OR)
- `~`   (bitwise XOR / unary NOT)
- `//`  (integer division — also 5.3+; not currently a problem for us but the same parser hole)

Any source file that uses these operators is rejected at parse time, with a stack trace through `lparser.lua:expr` / `subexpr`. `--noopt-binequiv` does not help; the failure is in the front-end before any optimisation runs.

Verified: stripping all bitwise ops from a file makes diet succeed on the same file. The lexer also lacks tokens for `<<` etc.; they are not just unhandled, they are unknown.

## Current workaround

`sequencer/step.lua` and `sequencer_lite/step.lua` use arithmetic equivalents:

| Bitwise            | Arithmetic                              |
|--------------------|-----------------------------------------|
| `(x >> s) & 0x7F`  | `math.floor(x / 2^s) % 128`             |
| `(x >> s) & 1`     | `math.floor(x / 2^s) % 2`               |
| `x & ~(M << s) \| (v << s)` (replace 7-bit field) | `x + (v - cur) * 2^s` where `cur = floor(x/2^s)%128` |
| `x \| (1 << s)` / `x & ~(1 << s)` (set bit) | `x + (newBit - cur) * 2^s` |

`2^s` is pre-computed at module load (`P_PITCH=1, P_VEL=128, …, P_ACT=68719476736`). Behaviour is identical; on Lua 5.4 the VM is fast enough that the integer-divide overhead is irrelevant for our tick rate (≤ a few hundred Hz worst case).

## Cost of the workaround

- Step.lua is ~50 lines longer (arithmetic helpers, doc, pre-computed constants).
- Bundle grew +435 B (from 10.2 KB to 10.6 KB diet'd).
- Slight runtime overhead per get/set: `floor` + `/` + `%` instead of one shift + AND. Not measurable at our pulse rate.

## The invasive option (if needed later)

If we want to use native `<<` / `>>` / `&` / `|` / `~` (because we add more bit-packing — e.g. packing Pattern or Track state, or want minimal Step.lua), we have to **patch LuaSrcDiet**. Two routes:

### Route A — patch the rocks-installed lparser/llex in place

Files to modify (on this machine):

```
/opt/homebrew/share/lua/5.5/luasrcdiet/llex.lua    -- add bitwise tokens
/opt/homebrew/share/lua/5.5/luasrcdiet/lparser.lua -- add bitwise expression rules + precedence
```

Lua 5.3 reference grammar additions (Lua reference manual §3.4.3):

```
exp ::= exp `|` exp        -- precedence  4 (left-assoc)
exp ::= exp `~` exp        -- precedence  5 (left-assoc)   -- BXOR
exp ::= exp `&` exp        -- precedence  6 (left-assoc)
exp ::= exp `<<` exp       -- precedence  7 (left-assoc)
exp ::= exp `>>` exp       -- precedence  7 (left-assoc)
exp ::= `~` exp            -- unary BNOT, same priority as other unary
exp ::= exp `//` exp       -- integer division, same priority as `*` / `/` / `%`
```

Lua 5.3 binary operator priority table (from `lparser.c` upstream):

```
{ left=10, right=10, op="^" },     -- right-assoc
{ left=9,  right=9 },              -- unary
{ left=7,  right=7, op="*" },
{ left=7,  right=7, op="/" },
{ left=7,  right=7, op="//" },
{ left=7,  right=7, op="%" },
{ left=6,  right=6, op="+" },
{ left=6,  right=6, op="-" },
{ left=9,  right=8, op=".." },     -- right-assoc
{ left=7,  right=7, op="<<" },
{ left=7,  right=7, op=">>" },
{ left=6,  right=6, op="&" },
{ left=5,  right=5, op="~" },      -- BXOR
{ left=4,  right=4, op="|" },
...comparisons & logical follow...
```

In `llex.lua` (LuaSrcDiet's lexer) the new tokens need entries in:
- `TKEYWORD` / `TK_*` table — add `TK_SHL`, `TK_SHR`, `TK_DBSLASH` (or the names diet uses; check existing single-char ops for the convention).
- `lex()` switch — `<` and `>` already exist for comparison and `<=`/`>=`; extend to consume `<<` / `>>`. `&`, `|`, `//` are simpler one/two-char additions. `~` exists for `~=` — extend so a lone `~` is BNOT/BXOR.

In `lparser.lua`:
- Update the `binopr_left[]` / `binopr_right[]` priority arrays (or whatever diet calls them) with the entries above.
- Update the `getbinopr(op)` (token → opcode mapper) to map the new tokens.
- `unary_op()` must accept lone `~`.

In `lopt.lua` / `loptlex.lua` (the lexer-stream optimiser) the new tokens must be considered when deciding whether two adjacent tokens need a separating space. `<<`, `>>`, `&`, `|`, `~`, `//` are all symbols — they don't need word-boundary handling.

Source-equivalence check (`opt-srcequiv`) re-runs the lexer on the output and compares streams; once the lexer knows the tokens this passes automatically.

Binary-equivalence check (`opt-binequiv`) compiles input + output with the bundled LuaJIT-style bytecode emitter and compares bytecode. **This will not work** for bitwise ops because the bundled emitter is also Lua 5.1; we'd have to keep `--noopt-binequiv`.

### Route B — fork

Vendor `tools/luasrcdiet/` into the repo with the patches above and call it instead of the system binary. More work to maintain but isolates the project from rock upgrades that might break the patch.

### Route C — pre-process

Replace bitwise ops in source with placeholder function calls (`_bsh(x,s)`, `_band(x,m)`) before diet, then post-process the diet output to inline them back. Fragile (diet renames locals, including any helper name we inject), don't recommend.

## Recommendation

Stick with arithmetic for now. Revisit only if:

1. We add more packed structures (Pattern flags, Track state) and the arithmetic boilerplate becomes burdensome to read.
2. On-device profiling shows the arithmetic overhead matters (it won't at < 1 kHz).
3. We hit a different LuaSrcDiet limitation that already requires us to fork it.

If we do fork, Route A in-place patch is enough — diet's parser is small (~1300 lines) and the changes are mechanical.

## Pointers

- LuaSrcDiet source on the machine: `/opt/homebrew/share/lua/5.5/luasrcdiet/`
- Upstream (unmaintained): https://github.com/jirutka/luasrcdiet
- Lua 5.3 reference manual §3.4.3 (operators + precedence): https://www.lua.org/manual/5.3/manual.html#3.4.3
- Reference C parser: `lua-5.3.x/src/lparser.c` — function `simpleexp`, `subexpr`, table `priority[]`.
