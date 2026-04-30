# 2026-04-28 — Step packed-integer refactor (A1)

## Summary

Step is now a packed Lua integer (37 bits) instead of a 7-field table. Cuts per-step memory from ~80 B (table) to ~8 B (integer-in-array-part). Setters became pure (return new value, caller rebinds) since integers are value types in Lua.

## Bit layout (LSB-first)

```
bits  0- 6  pitch       (7 bits)
bits  7-13  velocity    (7 bits)
bits 14-20  duration    (7 bits)
bits 21-27  gate        (7 bits)
bits 28-34  probability (7 bits)
bit  35     ratch
bit  36     active
```

## Why arithmetic, not bitwise

LuaSrcDiet's parser is Lua 5.1-era and rejects the 5.3+ bitwise operators (`<<`, `>>`, `&`, `|`, `~`). Since the diet pass cuts the device bundle ~50% (21 KB → 10 KB) we can't lose it. Step.lua therefore uses `math.floor(step / pow) % 128` and `step + (newValue - oldValue) * pow` instead of `(step >> shift) & M7` and bit insertion. Pre-computed `2^shift` constants (`P_PITCH=1, P_VEL=128, …, P_ACT=68719476736`) keep it readable. Behaviour is identical; on Lua 5.4 the VM is fast enough that the overhead is irrelevant for our tick rate.

## Setter contract change

`Step.setX(step, value)` is **pure**: returns a new packed integer. Callers must rebind:

```lua
-- correct
s = Step.setPitch(s, 60)
Track.setStep(t, i, Step.setPitch(Track.getStep(t, i), 60))

-- wrong (silently discards the new value)
Step.setPitch(s, 60)
```

Updated call sites: `patch_loader.lua` (build via `Step.new` + `Pattern.setStep`), `mathops.lua` (every mutation wrapped with `Track.setStep`), `snapshot.lua:122`, `tests/sequences/10_*.lua`, `tests/sequences/11_*.lua`, `tests/{step,pattern,probability,sequencer_lite,track}.lua`.

`Track.copyPattern` / `duplicatePattern` / `pastePattern` now plain-assign step slots (was `Utils.tableCopy`) — integers are values, no deep copy needed.

## Test status

All 15 unit suites green:

```
utils step pattern track engine mathops snapshot scene tui
probability sequencer_lite midi_translate patch_loader driver grid_bundle_smoke
```

All 11 sequence scenarios green (`lua tests/sequence_runner.lua all`).

## Memory profile (macOS Lua 5.5, `lua tools/memprofile.lua`)

| Patch | Pre-A1 total | Post-A1 total | Δ |
|---|---|---|---|
| four_on_floor (1t/1p/4s) | 44.85 KB | 44.82 KB | −0.03 KB |
| dark_groove   (4t/5p/36s) | 53.78 KB | 51.49 KB | −2.29 KB |
| empty         (1t/1p/1s) | 43.61 KB | 43.59 KB | −0.02 KB |

The win scales with step count, as expected. dark_groove (36 steps) saves 2.3 KB on macOS; on-device savings (where strings are larger and tables proportionally heavier) should be larger. Per-step delta: ~63 B (~80 B table → ~17 B integer-in-array, including small per-pattern bookkeeping).

## Bundle size (`grid/sequencer.lua`)

| Stage | Bytes |
|---|---|
| Bundled raw | 45 519 |
| Stripped (comments + asserts) | 21 789 |
| Diet (`--maximum --noopt-binequiv`) | 10 602 |

Pre-A1 was 10 167 bytes (10.2 KB); post-A1 is 10 602 bytes (10.6 KB). +435 bytes for the larger Step.lua (arithmetic helpers, pre-computed constants, doc comments). Net memory still wins on patches with many steps.

## Files touched

- `sequencer/step.lua`, `sequencer_lite/step.lua` — packed-integer rewrite (arithmetic).
- `sequencer/pattern.lua`, `sequencer_lite/pattern.lua` — `setStep` asserts `type=="number"`.
- `sequencer/track.lua`, `sequencer_lite/track.lua` — `setStep` asserts `type=="number"`; pattern-copy ops drop `Utils.tableCopy`.
- `sequencer/patch_loader.lua` — `patchLoaderBuildStep` constructs via `Step.new`.
- `sequencer/mathops.lua` — every mutation wrapped with `Track.setStep`.
- `sequencer/snapshot.lua` — rebind `step = Step.setActive(step, …)`.
- `tests/{step,pattern,probability,sequencer_lite,track}.lua` — updated for new contract.
- `tests/sequences/10_four_track_polyrhythm_showcase.lua`, `tests/sequences/11_four_track_dark_polyrhythm.lua` — updated for new contract.
- `docs/2026-04-28-step-packed-integer.md` — this note.

## Next steps

- Upload `grid/` to device, measure RAM on dark_groove + four_on_floor for the on-device delta.
- If still tight: inline getters/setters into hot call sites (B1, ~3-4 KB) or audit `--expose` (B2).
- Hardware verification on real Grid module.
