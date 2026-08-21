# 2026-04-28 — VSN1 profile + on-device editing UI

End-of-day note. Pick up here tomorrow.

## What landed today

- **`sequencer/profile.lua`** (new module): owns selection state, value
  reads, edit dispatch, active-flag toggle, and surgical screen redraws
  for the VSN1 4×2 cell grid. Bundled into `grid/sequencer.lua`, exposed
  as `Driver.Profile`.
- **`profile.lua`** (root): per-event paste blocks for the Grid Editor —
  utility setup, 8 button events, endless rotate, endless click, screen
  init, screen draw, **rtmidi callback** (clock + start/continue/stop).
  All event blocks fit the 880-char paste budget.
- **Single-char param codes** (`s/t/p/n/b/a/d/g`) used everywhere to
  keep paste blocks short.
- **`tests/profile.lua`**: covers init, value reads, select (incl.
  no-op), edit clamps for every param, track-change side effects, toggle,
  draw dispatch (one-swap-when-dirty / no-swap-when-clean / focus-only).
- **Bundle size**: 10 602 → **13 235 bytes diet'd** (+2.6 KB for
  Profile). On-device estimate ~129 KB engine RAM; ceiling ≈ 140 KB so
  we have ~10 KB headroom only.
- All 16 unit suites + scenario runner green.

## Verified working musically

- NOTE / VEL / DUR / GATE editing via endless feels good.
- 4×2 cell grid + red focus highlight is readable.
- Endless click → toggle step active = correct UX.
- External MIDI clock drives playback; transport via 0xFA/0xFC.

## Known limitations / hard truths

- **Only 1 track × 1 pattern × 4 steps** is comfortable to drive from
  the current UI. The state model supports more, but there's no way to
  see step 5+ on the cell grid (the cells are param selectors, not step
  selectors).
- **Snapshot is UI-only** — `n` selector cycles 1..16 but does nothing.
  Lite engine has no `snapshot.lua`.
- **`Profile` is a poor name** for the on-device control utility module.
  It collides with the broader notion of "Grid module profile". Pick a
  better name tomorrow (candidates: `Edit`, `UI`, `Console`, `Panel`,
  `Editor`, `Surface`).
- **Memory budget is tight** (~10 KB free). Any new on-device feature
  has to fit. No room to bring snapshot.lua or scene.lua across as-is.
- **VSN1 is hardware-constrained** for the goal. ER-101-class control
  needs more buttons (track/pattern/step page nav) and ideally a wider
  screen or paged views.

## Tomorrow's plan

### 1. Rename `Profile` → something better
- Consider: `Edit`, `Surface`, `Panel`. Touches:
  `sequencer/profile.lua` → `sequencer/<new>.lua`,
  `tools/build_grid.lua` (`--as` + `--expose`),
  `tests/profile.lua` → `tests/<new>.lua`,
  `profile.lua` BLOCK 1 (`P = Driver.<New>`),
  this doc.

### 2. Scale up sequence capacity in the UI
The engine already supports 8 tracks × 100 patterns × 2000 steps; the
**editor** is what's limited. Goals for tomorrow:
- **Step paging**: when `Track.getStepCount(t) > 1`, the `s` selector
  needs to scroll through all of them. Already does (clamped to step
  count) — verify on device with a longer pattern.
- **Pattern paging**: `p` selector scrolls 1..N — already works,
  verify.
- **Loop point editing**: per-track `loopStart` / `loopEnd` are first-
  class in ER-101 and not yet in the UI. Add two more param codes? Or
  enter a sub-mode?
- **Direction mode**: forward / reverse / ping-pong / random / Brownian
  is per-track, not in the UI.
- **Step-list view**: a second screen mode that draws all N steps of
  the current pattern as a horizontal strip with the current step
  highlighted, instead of the 4×2 cell grid. Bound to one of the 4
  small screen buttons.
- **Pattern visibility**: show pattern boundaries within a track's flat
  step list.

### 3. Math ops evaluation
- The `mathops` module is in `sequencer/` but **not bundled** into
  `grid/sequencer.lua`. Decide tomorrow:
  - bundle it (cost: a few hundred bytes),
  - add a UI affordance (long-press a param-cell to apply jitter /
    transpose / random to the focused param at the focused step),
  - test musically against the `dark_groove` patch.

### 4. Re-evaluate quantization
- Originally dropped (`docs/2026-04-28-drop-swing-and-scales.md`) on
  the rationale that downstream MIDI processors handle it. After
  hands-on testing, reconsider:
  - Live scale quantizer (Metropolis-style 30-scale list) is genuinely
    convenient when you don't have a downstream quantizer wired in.
  - Cost: ~1-2 KB if minimal.
  - Decision tomorrow.

### 5. Hardware re-evaluation
- VSN1 (8 buttons + 4 small + 1 endless + screen) is too few controls
  for ER-101-class playability.
- **Other Grid candidates** to investigate:
  - **PBF4** — 4 potentiometers + 12 buttons (no screen). Pots could
    be live cvA/cvB/dur/gate per step.
  - **EN16** — 16 endless encoders. One per step? Per pattern? Direct
    parameter access without paging.
  - **BU16** — 16 buttons, no screen. Step grid-style.
  - **Combo modules** (multiple snapped together) probably the right
    answer: BU16 for step grid + EN16 for per-step CV + PO16 for
    per-track parameters.
- Action: read hardware module reference, sketch a multi-module layout
  that maps to the engine's data model.

## Files touched today

- `sequencer/profile.lua` (NEW)
- `tests/profile.lua` (NEW)
- `tools/build_grid.lua` (added `--as Profile=...` + `--expose Profile`)
- `profile.lua` (rewritten as paste blocks + rtmidi callback)
- `docs/2026-04-28-vsn1-profile-ui.md` (this file)

## Open files / state

- `grid/sequencer.lua` — 13 235 bytes diet'd (current upload target)
- `grid/four_on_floor.lua` — default patch
- `grid_module.lua` — older bundle pasting reference; **redundant now**
  that `profile.lua` includes the rtmidi callback. Decide tomorrow
  whether to delete or keep as an internal-clock fallback example.

## Test command

```sh
for t in utils step pattern track engine mathops snapshot scene tui \
         probability sequencer_lite midi_translate patch_loader \
         driver grid_bundle_smoke profile; do
  lua tests/$t.lua || break
done
lua tests/sequence_runner.lua all
lua tools/build_grid.lua
```
