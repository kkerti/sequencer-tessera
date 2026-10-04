# AGENTS.md — sequencer-3

Status: **building.** M1–M4 are built and tested. Next is the Grid VSN1 control
interface (out of scope until then). Settled decisions are locked; deferred work
is listed at the end.

## Project in one sentence

A simple, live-performance, 16-step, 4-lane MIDI sequencer inspired by Noise
Engineering's Mimetic Digitwolis, with a **headless Core** and pluggable host
adapters (Mac first, Grid VSN1 later).

## Reference material

- `docs/reference/noise-engineering.md` — distilled Mimetic Digitwolis + Gamut
  Repetitor. **The design reference.**
- `../sequencer-1/`, `../sequencer-2/` — reuse **critical infra only**:
  - `tools/bridge.py` — virtual MIDI ⇄ stdio, spawns the Lua process. Port
    nearly verbatim, rename ports.
  - `src/core/scales.lua` (seq-2) / `src/scale.lua` (seq-1) — 12-bit scale
    masks with `rotate` / `step` / `quantize`.
  - `src/persist.lua` (seq-1) — Lua-chunk `return{...}` save/load, applied in
    place to preserve table identity.
  - `tests/run.lua` no-alloc test pattern.
  - **Do not** port seq-2's tracks / patterns / rack / sequences / control
    modes, or seq-1's mono packed-int engine.

## Hard rules

1. **RAM first.** Every feature is costed for allocation and per-pulse runtime.
2. **Zero allocations on the pulse hot path.** `transport.onPulse()`, advance,
   and note emission allocate nothing: no table literals, closures, or string
   concat. Guarded by a `test_no_alloc`.
3. **No clock is internal-only.** The engine consumes pulses from either
   external MIDI clock (24 PPQN) or an internal timer; both call the same
   `onPulse`. It has no baked-in BPM.
4. **≤16 steps per lane**, fixed storage. No dynamic event store.
5. **Lanes only.** Four lanes, flat. No tracks, patterns, sequences, or racks.
6. **Core is pure and headless.** No drawing, no MIDI, no `ggd*`, no device
   knowledge. Core returns events / state; adapters do IO.
7. **The action API is the boundary.** The Lua shell and the future Grid GUI
   both call the same named actions. No logic lives in a UI.
8. **Reuse only what is proven.** Simpler is the point. When in doubt, leave it
   out.

## Layer model

```
Core   lanes, transport, scales, generators, persist, action API.
       Pure Lua. No IO except explicit persist. Returns events/state.
Adapters
       stdio bridge -> MIDI (Mac) ; Grid VSN1 widget/button map (later).
       Thin: move data, bind inputs, render state. No musical logic.
```

## Settled foundations

### Shape

- **Headless first.** No screen/GUI in seq-3. The Grid VSN1 control interface
  comes later, built against the action API, out of scope for now.
- **Lanes-only**, 4 lanes. Matrix navigation with X/Y advance sources mapped to
  transport taps or other lanes (e.g. `lane.1` on X, `transport.quarterTriplet`
  on Y).
- **Action API** for all control; adapters are thin.
- **4 lanes**, implement `Note` first, then Mod/Trig/Gate/Gamut.
- **M1 "Mac loop":** Ableton sends MIDI clock -> engine advances a lane -> Note
  lane emits MIDI notes back to Ableton; the Lua shell changes settings.

### Storage (the contract)

- Each lane is a fixed record built once at init; per-step values live in
  preallocated arrays of exactly 16.
- Note lane: `pitch[16]` 0..127, `velocity[16]` 1..127, `stepLength[16]` in
  24-PPQN ticks. Mod: `value[16]`. Trig/Gate: `gate[16]`.
- Per-lane config is scalars only. Values are stored linearly 0..15;
  `dims` maps (x,y) -> index.

### Timing

- Internal resolution is 24 PPQN; one `onPulse` per pulse. External MIDI clock
  (default when present) and the internal timer share it.
- The transport derives taps from a position counter: `transport.whole` = 96
  pulses, `.half` = 48, `.quarter` = 24, `.eighth` = 12, `.sixteenth` = 6;
  triplets `.quarterTriplet` 16, `.eighthTriplet` 8, `.sixteenthTriplet` 4;
  dotted `.dottedQuarter` 36, `.dottedEighth` 18.
- Per-lane `advanceSource` + `division`; multi-dim lanes use separate
  `xAdvanceSource`/`yAdvanceSource`. X and Y wrap independently. Reset is
  deferred to the next advance. Stop freezes position.

### Musical model

- **Scales:** 12-TET only. Per-lane 12-bit mask + root; `Keys` + `Diaton`
  editors. Notes are stored absolute and quantized at output.
- **Output:** a Note lane is monophonic (retrigger) with a fixed preallocated
  note-off scheduler. MPE is an output-layer flag: one member channel per lane.
  Polyphony is deferred; FH-2 plus FHX expanders are the eventual path.
- **Lane types (cut 2026-10-04):** Note and Trig only. Trig plays `midiNote` on
  active steps for the step's `stepLength` (long = a gate). Mod and Gate were
  folded in; modulation is a chromatic Note lane that an FH-2 turns into CV.
- **Sources (cut 2026-10-04, partly restored the same day):** transport taps
  (straight, triplet, dotted) and lane->lane triggers (`lane.N`: the lane
  played a note). External MIDI sources (`external.N`), value addressing and
  the Mac `io/midi_in` mapping stay cut; they are in git history. With only
  even clock taps, division duplicated the tap choice and a power-of-two
  matrix collapsed to linear playback; lane triggers are the irregular input
  that X/Y and division were designed for (MD2's `Out 1-4`, its Voice preset).
- **Lane record = exactly 32 fields, all set in `Lane.new`.** Past 32 the hash
  part doubles (~750 B a lane), and a key inserted at runtime into a full hash
  part rehashes on the pulse path. So `activeNote` is `false` when idle, never
  `nil`, and lane fire flags live in `engine.fired[]`, not on the lane.
- **Random generation (cut 2026-10-04):** Shred (one step) and `randomize`
  (every step, key 3) replace the Gamut / Euclid / live generators.
- **Presets:** 24 Lua-chunk files under `presets/`, loaded on demand. Saving
  writes the same shape, losslessly (see `docs/ACTION_API.md` > Slots).

## Bundle granularity defeats in-module laziness (measured 2026-09-27)

A pre-linked bundle **runs every module body when it is required**
(`R["screen"]=(function() ... end)()`). So `midi_rx`'s `loadSCR()` — "the screen
compiles on the first control press" — bought nothing: `screen.lua` and
`menu.lua` were in the same bundle as `midi_rx`, so they were paid for the
moment anything in `seq3ui` was needed. Measured: `screen.lua` adds ~0 KB on the
first key press because it is already resident.

**Laziness is per BUNDLE, never per module.** To defer something, give it its
own bundle. This is why `dist/` is now six bundles, and why the headless target
(`seq3.lua` + `seq3e.lua` + `seq3h.lua`, **79.1 KB resident**) fits where the
GUI one (**99.4 KB**) did not.

## Corrections to earlier notes (found 2026-09-27, verified against a working profile)

Two claims in this file were wrong and cost a device cycle. Both are fixed in
`tools/gen_profile.py`:

1. **`rtmrx_cb` signature.** This file said "seq-1 uses `function(self, t)`; we
   use the same" — we did **not**. v7/v8 generated
   `function(self,h,t)RX.handle(t,...)`, so `h` took the status byte and `t` was
   `nil`: **MIDI clock could never have worked**, independently of the boot
   failure. seq-1's authoritative wiring (`sequencer-1/configs/VSN1.lua:95`) is
   `function(self, t)`. `tests/boot_sim.lua` now pins this.
2. **"seq-1 never used gms."** The installed, cold-boot-proven profile
   `lib seq 4 (vsn1 only, fully working)` calls `gms(e.ch,0x90,...)` directly.
   seq-1's *newer* `configs/VSN1.lua` uses `midi_send`, so both worked — `gms`
   was never demonstrated to be the crash cause. The grxm/gms theory that drove
   v7's rewiring rested on this.

Also: the element skeleton in `tools/vsn1r_template.json` is cloned from
**seq-2** (the dead project), not from seq-1. It carries `print("tick")` on the
timer of all 14 elements; seq-1's working profile has 2. v9 blanks all but el
255's RAM diagnostic. `--probe` emits a profile with every event blank to test
whether the skeleton itself is the killer.

## Device-code reality (measured on VSN1R)

- The ~10 KB text-chunk watchdog limit applies to **element event scripts**
  (inline profile scripts ≤ 900 chars), **not** to FS modules. FS modules are
  plain text, compiled at load — comments are ballast; `tools/strip_lua.py`
  strips them in the dist.
- **RAM is the ceiling again (measured):** full GUI at setup = 183 KB →
  module dead; eager core-only at setup = 149 KB → refused to start; lazy
  core-only (requires nothing at setup, `midi_rx` compiles on the first MIDI
  byte) = **150 KB runtime, runs**. The kill threshold is the load/setup
  **peak**, so every added piece must compile lazily and be measured alone.
- Profile generation: `tools/gen_profile.py` clones the proven 15-element
  skeleton; event configs are compiled with `luac -p` before the profile is
  written (a glued `endself` token once made the editor call it corrupt).
- **Device draw API — the complete proven set.** Taken from seq-1's
  cold-boot-proven `dist/sequencer_ui.lua`; nothing else is known to exist:
  ```
  scr:draw_rectangle_filled(x0, y0, x1, y1, {r,g,b})   -- CORNERS, not w/h
  scr:draw_rectangle(x0, y0, x1, y1, {r,g,b})
  scr:draw_text_fast(text, x, y, size, {r,g,b})
  scr:draw_swap()
  ```
  **Corners are inclusive: 0..319 x 0..239.** A full-screen clear is
  `(0, 0, 319, 239)` — `(0, 0, 320, 240)` writes one pixel past each edge.
  Long names in FS modules, short names (`ldaf/ldft/ldsw`) in inline event
  scripts only.
- **`draw_area_filled` DOES NOT EXIST.** seq-3's device modules called it 11
  times; it appears nowhere in seq-1's proven code. On device the chain loaded
  fine and then the screen crashed and rebooted the module. Fixed, and
  `tests/lcd_mock.lua` now whitelists the four real primitives and bounds-checks
  every coordinate, so this fails on the Mac instead. The old mock returned a
  function for *any* method name, which is exactly how it reached hardware.

## Proposed layout (to be built)

```
sequencer-3/
  AGENTS.md  CONTEXT.md
  docs/reference/noise-engineering.md
  docs/adr/                 -- created as decisions warrant
  src/
    core/   lane.lua transport.lua engine.lua scales.lua persist.lua
    midi/   out.lua in.lua
    io/     stdio.lua
  proto/term/main.lua       -- headless harness / stdin command protocol
  presets/                  -- Lua-chunk slots
  tools/bridge.py
  tests/run.lua
```

## Milestones

- **M1 — Mac loop. ✅ BUILT.** 1 Note lane, external MIDI clock from Ableton,
  notes out, action API, no-alloc test. `presets/01.lua`.
- **M2 — Four lanes + matrix nav. ✅ BUILT.** `dims` layouts, X/Y advance,
  X/Y address value sources, shift/rotate, per-step velocity/length,
  same-pulse lane→lane, external MIDI mapping. `presets/02.lua` (matrix),
  `presets/03.lua` (MIDI-reactive). Tests: 57 checks, no-alloc green.
- **M3 — Lane types + four-lane performance. ✅ BUILT.** Lane `fire` now reflects
  output (Trig = active step, Gate = rising edge, Mod = at/above threshold);
  start no longer cascades. `presets/04.lua` (Voice: trig drives note + 2×mod)
  and `presets/05.lua` (4-lane polyrhythm) exercise all types. Tests: 65 checks.
- **M4 — Gamut generator. ✅ BUILT.** `src/core/generate.lua`: seeded, alloc-free
  Gamut (root/base, spread, downUp, velocity/gate spread) with one-shot fill and
  `live` playhead regeneration, plus a Euclidean rhythm fill for Trig/Gate
  lanes. `presets/06.lua` (live gamut + euclid). Tests: 73 checks, no-alloc
  green with a live generator on the pulse path.
- **Later — Grid VSN1 control interface** (widget system, buttons, minimal
  screen) against the action API. **In progress:** core-only device build
  runs at 150 KB; engine ops + generators split into lazy `ops.lua`/lazy
  `generate` (engine `__index`, cached on first use) to bank RAM — see
  `dist/README.md` for the measured ladder. GUI pieces (`layout_core`,
  `widgets`, `host`) re-add one measurement at a time.

## Deferred / future

- **Parameter modulation** — a value source driving division/length/scale/root/
  range. Deliberately deferred; not in the v1 API.
- **Gamut UI mapping** — parameters exist in the Core; the control surface is
  part of the later Grid work.
- **Polyphony via MPE** — FH-2 + FHX expanders; member-channel path only.
- **14-bit CC** — Mod lane stays 7-bit for now.
- **Grid VSN1 control interface** — buttons + minimal screen, built against the
  action API.

## Build log (M1–M4 done)

M1: full Core (`scales` -> `lane` -> `transport` -> `engine` -> `midi/out`),
no-alloc test, `bridge.py`, preset. M2: X/Y advance and address, shift/rotate,
same-pulse lane→lane, `io/midi_in` external mapping, presets 02/03. M3: lane
fire semantics per type, four-lane presets 04/05. M4: `generate.lua` Gamut +
Euclid, live generation, preset 06. Tests: 73 checks.

## M5 — save/recall + lane monitor (BUILT)

- `src/core/persist.lua` writes the live state as a preset-shaped Lua chunk,
  **lossless against `loadPreset`** and idempotent (`load` then `save` is
  byte-identical). Sources are written as names; derived and live-playback
  fields are not stored. `saveSlot`/`loadSlot` address `presets/NN.lua`.
- `src/io/monitor.lua` — Mac-only host adapter: a four-line live view, one line
  per lane, on **stderr** (stdout is the MIDI line protocol). `--monitor`.
- Device trigger: **Config > GLOBALS > slot / save / load**, added to
  `src/device/menu.lua`; `persist` is required on the first save or load only.
  Module file storage is flat, so `Persist.prefix` is set to `"s"` there and
  slots are `s01.lua`..`s24.lua` (seq-1 ships `d0.lua` the same way).
- **`persist.lua` obeys the device rules**: no `string.format`, `table.concat`,
  `math.type` or `collectgarbage` on any path the module can reach. Values go
  straight into `file:write`, as seq-1's proven on-device persist does, so no
  whole-file string is held in RAM. `tests/dist_smoke.lua` asserts all four
  bans against the built bundles.
- Harness: `SAVE <slot>` / `LOAD <slot>` on the stdin protocol; `bridge.py`
  forwards lines typed in its terminal, so slots work mid-session.
- Verified on the Ableton code path (START/CLK on stdin, exactly what
  `bridge.py` sends): preset 05's four-lane polyrhythm emits 17/9/7/5 note-ons
  per bar for divisions 1/2/3/4, each lane on its own channel with its own
  pitches, every note-on matched by a note-off; a saved four-type slot recalls
  in a fresh process and plays deterministically.
- **`dist/` regenerated as v9.** v8 (bundles required at setup) **cold-boot
  died on device**, confirming the ladder above: *no* eager-at-setup build has
  ever booted, and shrinking the eager load is not enough. v9's setup does
  **zero requires** — it only defines a global loader `L()` and assigns
  `rtmrx_cb`; the chain compiles on the first MIDI byte (`--setup=press`
  defers it to the first control press instead; `--setup=eager` restores v8).
  See `dist/README.md` for the bisection ladder.

## App start compiles only what start needs (v14, 2026-10-04)

Start (first MIDI byte or key) compiles `seq3` + `seq3e` + `seq3ui` =
midi_rx + demo, at most one bundle per callback (staged `L()`, the timer
finishes a started load). The screen (`seq3s`) compiles on the first control
press. The setters (`edit.lua`) live in the load bundle `seq3l`: the
screens, the start demo and the headless sequence all write lane fields
directly (clamping themselves), so only applying a slot/preset calls a
setter on the device. Device code must not call `Engine.set*` on a hot or
start path. `tests/boot_sim.lua` runs
the real profile scripts from the JSON and pins all of this.

## Feature cut, measured in the wasm (2026-10-04)

The text GUI died partway through its boot on the device. Features were cut in
value order, each measured with `grid-wasm/seq3mem.mjs` (the real bundles,
streamed into grid-wasm stage by stage). Engine stage 92.3 -> 83.8 KB; text
GUI after key+draw 116.0 -> 106.1 KB; headless after 96 pulses 108.8 -> 97.3
KB. The full text-GUI ladder (boot, key, draw, Shred, Random, 96 pulses) now
passes in the wasm. Only the save stage still fails there. Table and
calibration in `dist/README.md` > v13.

**Use the wasm ladder before every device upload.** Its PASS is strong
evidence; its FAIL proves nothing (the VM has at least ~20 KB less than the
device). Its real ceiling is ~117 KB, not the ~130 KB where "Out of memory"
first prints: read the `free` stage.

## Measured RAM: seq-3 vs seq-1 (host Lua, ratios not device truth)

| | seq-1 (4 trk x 64 steps) | seq-3 (4 lanes x 16 steps) |
|---|---|---|
| core resident above baseline | **27.4 KB** | **67.6 KB** |
| of which module code | ~23 KB | **55.1 KB** |
| of which lane data | ~4.3 KB | 12.5 KB (2.5 KB/lane) |

seq-3 is ~2.5x seq-1's core RAM while storing 4x fewer steps, and the cost is
**code, not data**: `engine.lua` alone is 30.9 KB of the 55.1 KB. Levers, in
value order:

1. ~~28 one-line `M.set*` functions ≈ 12 KB~~ — **done, and it was
   overestimated**: collapsing 17 of them into loop-built closures (one shared
   prototype each group) saved **3.3 KB** (engine 32.3 -> 29.1 KB resident).
   Tiny functions are cheap; the engine's cost is spread across 39 protos,
   1.3 k instructions and 316 constants with no single hotspot.
2. **RAM tracks shipped source at ~2.5x** for every module. The only real
   levers are shipping less code (e.g. the text GUI, `--gui=text`: resident
   ~85 KB after the screen loads vs ~95 KB for the colour GUI) or stripped
   bytecode (debug info is ~1/3 of module cost) if the device can load it.
3. Lane data is already cheap; cutting features to save step storage would be
   aimed at the wrong 12.5 KB.

## Cross-cutting references

- `docs/ACTION_API.md` — the full named control surface.
- `docs/NAMING.md` — naming policy + source vocabulary + abbreviation lookup.
- `docs/PARAM_DEPENDENCIES.md` — which settings apply under which `dims` or
  lane type. The GUI will hide inapplicable controls from this.
- `docs/adr/` — the hard-to-reverse decisions and their rationale.
- `tools/bridge.py` — MIDI ⇄ stdio; `tools/send.py` — send notes/CC/clock to the
  bridge's virtual input from a second terminal (no DAW needed).

## When in doubt

Ask. Names and formats are cheap to change now and expensive later. Settle the
glossary before coding.
