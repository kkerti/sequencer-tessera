# CODEBOOK

Live mapping of every short name, packed encoding, and aliasing decision
in the project. Source of truth — when you abbreviate or pack, add an
entry here. Date entries when introduced. See AGENTS.md → "Style: zones,
abbreviations, and the codebook" for the rules.

---

## Step packed integer (37 bits, Lua 5.4 number)

Introduced **2026-04-28**. See `docs/2026-04-28-step-packed-integer.md`
for the rationale and arithmetic-not-bitwise constraint (LuaSrcDiet 5.1
parser rejects `<<`/`>>`/`&`/`|`/`~`).

### Bit layout

| Bits  | Width | Field        | Range  |
|-------|-------|--------------|--------|
| 0–6   | 7     | pitch        | 0–127  |
| 7–13  | 7     | velocity     | 0–127  |
| 14–20 | 7     | duration     | 0–99   |
| 21–27 | 7     | gate         | 0–99   |
| 28–34 | 7     | probability  | 0–100  |
| 35    | 1     | ratch        | bool   |
| 36    | 1     | active       | bool   |

### Power-of-two constants (2^shift)

| Name         | Value           |
|--------------|-----------------|
| `P_PITCH`    | 1               |
| `P_VEL`      | 128             |
| `P_DUR`      | 16384           |
| `P_GATE`     | 2097152         |
| `P_PROB`     | 268435456       |
| `P_RATCH`    | 34359738368     |
| `P_ACT`      | 68719476736     |

### Helpers (in `sequencer/step.lua` and `sequencer_lite/step.lua`)

- `get7(s, P)`  → `math.floor(s / P) % 128`
- `getBit(s, P)` → `math.floor(s / P) % 2`
- `pack7(s, v, P)` → `s + (v - cur) * P` (pure: returns new int)

### Setter contract

Setters are **pure**: they return the new packed integer and the caller
must rebind. Integers are value types in Lua — no in-place mutation.

```lua
local s = Track.getStep(track, idx)
s = Step.setPitch(s, 60)
Track.setStep(track, idx, s)
```

---

## Controls module — paste-block param codes

Single-character codes used in `controls.lua` (paste-glue file) and
`sequencer/controls.lua` (bundled module). Driven by the 880-char
per-event paste budget on the Grid Editor. Introduced **2026-04-28**
(under the previous module name `Profile`); renamed to `Controls`
**2026-04-29**.

### Selector codes

| Code | Meaning       | Range                                   | Where             |
|------|---------------|-----------------------------------------|-------------------|
| `s`  | step          | 1 .. `Track.getStepCount(t)`            | keyswitch 0       |
| `t`  | track         | 1 .. `engine.trackCount`                | keyswitch 1       |
| `p`  | pattern       | 1 .. `Track.getPatternCount(t)`         | keyswitch 2       |
| `m`  | direction     | forward/reverse/pingpong/random/brownian | keyswitch 3       |
| `b`  | cvB / pitch   | 0 .. 127 (MIDI note)                    | keyswitch 4       |
| `a`  | cvA / velocity| 0 .. 127                                | keyswitch 5       |
| `d`  | duration      | 0 .. 99 (clock pulses)                  | keyswitch 6       |
| `g`  | gate          | 0 .. 99 (clock pulses)                  | keyswitch 7       |
| `l`  | loopStart     | 1 .. loopEnd (or `nil` = off)           | small button 0    |
| `e`  | loopEnd       | loopStart .. stepCount (or `nil`= off)  | small button 1    |

`m` cycles modes on rotation (wraps); endless click is no-op when `m` is
selected. `l`/`e` rotation initialises from nil to the current edit cursor
on first click; subsequent rotations move the boundary by ±1. Endless click
clears the boundary back to nil ("off"). Added **2026-04-29** (replaced `n`
SNAP, which was a UI-only no-op).

Display labels (`LB` table in `sequencer/controls.lua`):

```
s=STEP   t=TRK    p=PAT    m=DIR
b=NOTE   a=VEL    d=DUR    g=GATE
l=LSTRT  e=LEND   (shown on timeline status line, no top cell)
```

Cell layout (`PO` array): `{"s","t","p","m", "b","a","d","g"}` — top
row 0–3, bottom row 4–7. `l` and `e` are reached only via the small
under-LCD buttons (no top cell).

Direction-mode short labels (`DIR_LB` table):

```
forward=FWD  reverse=REV  pingpong=P-P  random=RND  brownian=BRN
```

### Paste-block globals (`controls.lua`)

| Global | Meaning                                |
|--------|----------------------------------------|
| `D`    | Driver instance                        |
| `E`    | Engine                                 |
| `P`    | `Driver.Controls` module (was Profile) |
| `EM`   | midi-emit closure                      |
| `MC`   | MIDI clock pulse counter               |
| `MP`   | MIDI clock pulses per engine pulse     |
| `DR`   | Driver module ref (avoid per-pulse `require`) |

### State table (`S` inside `sequencer/controls.lua`)

| Field        | Meaning                              |
|--------------|--------------------------------------|
| `S.engine`   | engine reference                     |
| `S.sel`      | current param code (one of the 10)   |
| `S.prev`     | previous param code (focus-swap)     |
| `S.tr`       | track index                          |
| `S.pa`       | pattern index                        |
| `S.st`       | flat step index (edit cursor)        |
| `S.cur`      | last-seen engine cursor (timeline)   |
| `S.dirty`    | `{ s,t,p,m,b,a,d,g }` repaint flags  |
| `S.focusDirty` | red-highlight needs swap           |
| `S.timelineDirty` | bottom strip needs repaint      |

### Endless rotation values (intech-mode-dependent)

`controls.lua` BLOCK 10 reads `self:endless_value()`:
- value `65` → `+1` step
- value `63` → `−1` step

If a different VSN1 firmware mode is used (intech docs mention
`8146/8247` or `127/1`), recalibrate these constants.

---

## Bundle aliases (`tools/build_grid.lua` `--as`)

The `bundle.lua` `--as` flag rewrites cross-module `require()` paths so
the lite engine modules satisfy authoring-side imports without source
edits.

Current aliases (verify in `tools/build_grid.lua`):

| Source `require`         | Bundled-as path / module |
|--------------------------|--------------------------|
| `sequencer/step`         | lite Step                |
| `sequencer/track`        | lite Track               |
| `sequencer/pattern`      | lite Pattern             |
| `sequencer/engine`       | lite Engine              |
| `sequencer/controls`     | `Driver.Controls` (was Profile) |

Exposed as `Driver.<Name>` via `--expose`. Update entries here when
adding/removing modules.

---

## Conventions for new entries

- Date the change at the top of the relevant subsection.
- Quote the byte-saving justification (diet'd bundle delta, paste-block
  char count, on-device allocation count) — never abbreviate without a
  number.
- If a short name is replaced or removed, **strike through** the old
  entry and add the new one below; do not delete history.
