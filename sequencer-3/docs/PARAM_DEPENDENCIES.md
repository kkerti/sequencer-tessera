# PARAM_DEPENDENCIES.md — sequencer-3

Which settings only make sense under which `dims` or lane type. This exists so
that (a) the engine validates/rejects nonsensical config, and (b) the future GUI
can hide or grey out inapplicable controls. Keep this in sync whenever a
parameter is added.

Legend: `—` = not available, `✓` = available.

## 1. `dims` (step layout)

A lane's `dims` sets the number of used steps and which navigation settings
exist.

| `dims` | used steps | Advance | XAdvance / YAdvance | Previous | Address | XAddress / YAddress | Length | Shift |
|---|---|---|---|---|---|---|---|---|
| `16x1` | 16 | ✓ | — | ✓ | ✓ | — | ✓ | ✓ |
| `8x2`  | 16 | — | ✓ / ✓ | — | — | ✓ / ✓ | — | ✓ |
| `5x3`  | 15 | — | ✓ / ✓ | — | — | ✓ / ✓ | — | ✓ |
| `4x3`  | 12 | — | ✓ / ✓ | — | — | ✓ / ✓ | — | ✓ |
| `4x4`  | 16 | — | ✓ / ✓ | — | — | ✓ / ✓ | — | ✓ |

Index mapping is row-major: `index = y * width + x` (0-based), stored linearly
in the 16-slot arrays. Unused slots (e.g. `5x3` slot 16) are ignored.

Notes:

- `16x1` is the default and the only mode with **Previous** and a free sequence
  **length** (1..16).
- Multi-dim modes derive their length from `dims` (fixed `width * height`); no
  separate length setting.
- **X and Y wrap independently**: X advance wraps within the row, Y advance
  wraps within the column.
- **Division** applies to all advance sources and is available in every mode.
- **Address** uses a *value source* (`external.N` or `lane.N`); a
  `transport.*` source is not meaningful for addressing.

## 2. Lane type

Which per-step fields and per-lane settings apply to each type.

| Setting | Note | Mod | Trig | Gate |
|---|---|---|---|---|
| `pitch[16]` (0..127) | ✓ | — | — | — |
| `velocity[16]` (1..127) | ✓ | — | — | — |
| `stepLength[16]` (ticks) | ✓ | — | — | — |
| `value[16]` (0..127) | — | ✓ | — | — |
| `gate[16]` (0/1) | — | — | ✓ | ✓ |
| `scaleMask` + `root` | ✓ | — | — | — |
| `minNote` / `maxNote` | ✓ | — | — | — |
| `minValue` / `maxValue` | — | ✓ | — | — |
| `controller` (output CC number) | — | ✓ | — | — |
| `channel` (MIDI channel) | ✓ | ✓ | ✓ | ✓ |
| MIDI note number | — | — | ✓ | ✓ |
| MIDI note length | ✓ | — | ✓ | — |
| `mode` (edit/hold/time/toggle) | ✓ | — | — | — |
| advance / reset / random / previous / shift sources | ✓ | ✓ | ✓ | ✓ |
| address value sources | ✓ | ✓ | ✓ | ✓ |
| `division` | ✓ | ✓ | ✓ | ✓ |

Notes:

- **Note** is the only melodic/quantized type; everything scale-related lives
  here.
- **Mod** output is a raw value (CC), so it uses `minValue`/`maxValue`, not notes
  or a scale.
- **Trig** vs **Gate** differ only in output timing: Trig = short pulse on an
  active step; Gate = held note across a run of active steps. Their storage is
  identical.
- `Qtiz` is intentionally absent (dropped; needs CV inputs).

## 3. Cross-type rules

- A lane is **monophonic**: exactly one note/CC value is emitted per active step.
- Only one lane **type** exists per lane at a time; changing type keeps the
  underlying arrays but only the relevant fields are read/written.
- `channel` is common to all types.
- Source routing (advance, xAdvance, yAdvance, reset, random, previous, shift)
  is common to all types and all `dims` (with the single-advance/single-address
  /`previous` exceptions for `16x1`).

## 4. Deferred / not-yet-applicable

| Feature | Blocked on |
|---|---|
| Parameter modulation (value source -> division/length/scale/root/range) | Deferred decision; not in the v1 API. |
| 14-bit CC | Mod lane stays 7-bit for now. |
| Slew (smooth Mod/Note transitions) | Not in v1. |
| Microtonal scales (`Equal`, `Ratio`) | Dropped for now (12-TET only). |
| `Symmet` scale editor | Deferred. |
| MPE expression targets (bend, aftertouch) | Output-layer flag; per-lane expression source TBD. |
| Polyphony | FH-2 + expanders; MPE member-channel path only. |
| Trig pulse micro-timing | Pulse length is quantized to the 24-PPQN pulse path. |
