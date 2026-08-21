# AGENTS.md — sequencer-2

Guidance for AI coding agents (and humans). Read `CLAUDE.md` first for the
locked contract; this file is the working architecture. `docs/ARCHITECTURE.md`
has the deep engineering detail.

## Project in one sentence

A polyphonic, externally-clocked MIDI sequencer in Lua 5.4, modelled on the
Squarp Hermod+ (tracks → patterns + effect rack), targeting Intech Studio Grid
VSN1 hardware, where notes are transformed into the played sequence by a live
per-pulse effect chain — under a hard RAM and zero-lag-playback budget.

## Reference material

- `docs/manual/HERMODPLUS_manual*.pdf` — **the** design reference. Key sections:
  §1.1 Sequencer workflow (p7), §1.2 architecture (p9), §2 Step mode (p16+,
  note events = pitch/length/velocity, polyphonic, grid-free), §3 Effects mode
  (p29+, 8-slot rack, non-destructive, order matters), §3.5 Pattern values
  (p34, per-param global-vs-pattern override), §5 Sequence mode (p72, a sequence
  = a set of one pattern per track; chain sequences into songs).
- `../sequencer-1/` — the previous sequencer. **Infra to reuse**, model to reject.
  - `tools/bridge.py` — macOS MIDI ⇄ stdio bridge. Port nearly verbatim.
  - `docs/GRID_HARDWARE_API.md` — VSN1 screen + button API. Authoritative.
  - `src/persist.lua` — Lua-chunk `return{...}` save/load. The RAM-swap seed.
  - `src/scale.lua`, `src/driver_stdio.lua` — reusable with light edits.
  - `AGENTS.md` — the zero-alloc discipline and draw model we inherit.
  - Do **not** copy `src/step.lua`, `src/track.lua`, `src/engine.lua` — those
    are the mono packed-int model we are replacing.

## Hard rules

1. **RAM is the primary constraint.** Every feature is costed for allocation and
   per-pulse runtime first, musicality second.
2. **Zero allocations on the pulse hot path.** `engine.onPulse()`, the effect
   chain, and note emission allocate nothing: no table literals, no closures, no
   string concat. Locked by a `test_no_alloc` (port seq-1's).
3. **No internal clock.** The engine consumes external pulses; it has no BPM.
4. **Polyphonic, structure-of-arrays.** Patterns store notes as parallel numeric
   arrays, never array-of-tables. See `docs/ARCHITECTURE.md#event-store`.
5. **Effects are live and non-destructive.** The chain reads pattern events and a
   reusable scratch buffer; it never rewrites stored notes. Effect *order* in the
   rack is semantically significant (Hermod §3.1).
6. **Three layers: HAL → Core → App.** Core returns events, never touches a
   screen/driver. App reads Core tables and calls Core setters.
7. **Greenfield.** Re-derive from these docs. If you want to port seq-1's engine,
   stop — that's the mono model we rejected.
8. **Start at 2 tracks.** Do not scale to 8 until the architecture is proven and
   the RAM-swap path works.

## Layer model

```
HAL   screens (love / vsn1), drivers (stdio / grid midi), input decoders.
      Knows hardware. Knows nothing about musical meaning.
Core  event store, pattern, effect rack, engine, scales, persist.
      Pure Lua. Returns events. Never does IO except persist (explicit swap).
App   UI (menu system, screen layout), input mapping (fn buttons/encoder/8 btns),
      transport wiring. Reads Core, drives HAL. The only layer that knows both.
```

## Proposed layout (to be built)

```
src/
  core/
    event.lua     structure-of-arrays note store + codec + iteration helpers
    pattern.lua   pattern = event store + length + zoom + per-pattern fx values
    rack.lua      effect chain: alloc-free per-pulse runner over a scratch buffer
    track.lua     patterns[] + rack + midi channel + playhead + record buffer
    engine.lua    tracks[], transport (onStart/onStop/onPulse), sequence swap
    scales.lua    pitch-class masks (port seq-1)
    persist.lua   Lua-chunk save/load; RAM swap of inactive tracks/patterns
  fx/
    scale.lua     quantize to scale
    range.lua     RANGE performance limiter: clamp pitch/vel/gate to min..max
                  around a root, with per-pattern value overrides
    random.lua    RANDOM/CHANCE: probabilistic skip + pitch/vel/octave variation
  core/ (cont.)
    generate.lua  one-shot Euclidean pattern generator (root±spread)       [built]
    midi_rx.lua   device MIDI-clock rx: 0xF8->onPulse->notes out via gms    [built]
  app/
    control.lua   input + pattern param model; PLAY/SETUP modes (UI bundle) [built]
  hal/
    driver_stdio.lua  terminal → bridge.py (port seq-1)                     [built]
    draw_vsn1.lua     on-device screen, PLAY split + SETUP full grid        [built]
    driver_grid.lua   Grid midi.send (later)
    input.lua         decode 4 fn buttons + encoder + 8 buttons (+ handoff)
screens/
  seq2_screen.lua   flat Grid VM screen, static+encoder-swept (reliable)   [built]
  seq2_live.lua     AUTO-GEN: thin data-only preview, baked variants        [built]
  manifest.json     screen list for the grid-wasm page dropdown
dist/                (all AUTO-GEN; upload to module / load as profile)
  seq2.lua          Core+midi_rx bundle (require "seq2")                    [built]
  seq2_ui.lua       screen bundle (require "seq2_ui", lazy)                 [built]
  Sequencer 2.json  VSN1R profile (event scripts)                          [built]
proto/
  term/main.lua   headless harness: stdin clock protocol → stdout notes    [built]
tools/
  build.lua          bundle src → dist/seq2.lua + seq2_ui.lua + preview    [built]
  gen_profile.py     VSN1R profile: clone skeleton, override el255/el13     [built]
  vsn1r_template.json  proven element skeleton (all 15 elements)            [built]
  bridge.py          MIDI ⇄ stdio, spawns Lua coprocess (port seq-1)        [built]
tests/
  run.lua  (27 checks: scales, fx, playback, no-alloc, generator)
docs/
  ARCHITECTURE.md, DEPLOY.md, manual/
```

## Glossary (agree names before coding)

| Term | Meaning |
|------|---------|
| **event** | One note: `pitch, start, len, vel`. Stored across parallel arrays, not as a table. |
| **pattern** | A polyphonic, grid-free collection of events + a length + per-pattern fx values. Hermod P1..P16 per track (start with fewer). |
| **track** | One musical voice-group: its patterns, one effect rack, one MIDI channel, one playhead, one record buffer. |
| **rack** | The ≤8-slot ordered effect chain of a track. Runs live every pulse. |
| **sequence** | One selected pattern per track played together. Sequences chain into songs (later milestone). |
| **pattern value** | A per-effect-parameter override: global (shared) vs pattern-local. The performance-effect knobs live here. |
| **scratch buffer** | Fixed preallocated event array the rack reuses each pulse. No per-pulse allocation. |
| **RAM swap** | Loading/unloading inactive tracks/patterns to Grid FS as Lua chunks. Never on the hot path. |
| ~~step~~ | seq-1's fixed grid slot. **We are event-based** — a step here is only a UI/quantize grid line, not storage. |

## Milestones

**M1 — Prove the spine (2 tracks). ✅ BUILT.** Event store + one pattern per
track + rack{RANGE, RANDOM, SCALE} + engine `onPulse` (zero-alloc, guarded by
`tests/run.lua` test 6) + `driver_stdio` + full-duplex `bridge.py` (spawns the
Lua process) → notes into Ableton, per-track channel. Terminal + `--bpm` test
clock. `persist.lua` deferred to M4 (single resident pattern needs no swap yet).
Run: `python3 tools/bridge.py --lua "lua proto/term/main.lua"`.

**M2 — See it. ✅ BUILT (grid-wasm).** `screens/seq2_screen.lua` — a flat Grid
VM screen (VSN1 `ggd*` primitives, global state, ~2 KB init) rendered on the
REAL Grid renderer headlessly to PNG via `../grid-wasm/screenshot.mjs`
(Playwright/chromium). Top 320×120 = piano-roll + playhead + ghosted 2nd track;
bottom 320×120 = mode tabs + status + params. Encoder (`sliderValue`) sweeps the
playhead; notes light as it crosses them — verified across encoder positions.
LÖVE path was dropped (no game engine). **View it:** serve from the `sequencer`
dir (`cd .. && python3 -m http.server 8080`), open
`http://localhost:8080/grid-wasm/index.html`, pick `seq2_screen` in the Screen
file dropdown. The page finds screens via `screens/manifest.json` at the server
root — a repo-root symlink `sequencer/screens -> sequencer-2/screens` exposes our
canonical `sequencer-2/screens/` there (add new screens to the manifest).
Headless PNG: `cd grid-wasm && node screenshot.mjs
../sequencer-2/screens/seq2_screen.lua <0-255> out.png`.

**Note — two screen dialects.** The live engine (`src/`) uses OO modules and
`require`. The Grid screen (`screens/`) is a *flat* script: no `require`, all
globals, `ggd*` draw calls, tight size budget. On real hardware the engine lives
in the module's other event scripts and the screen script reads shared globals;
the grid-wasm harness previews one screen script in isolation with a static data
snapshot. Keep screen scripts self-contained and small.

**Feasibility spike (grid-wasm). ✅ DONE.** `tools/build.lua` → `dist/seq2.lua`
(9.2 KB) loads and runs in the real Grid VM. Per-pulse ~1.3 µs, zero-alloc.
RAM is the ceiling: fixed a pattern pre-sizing OOM (27→9.6 KB), and found that
embedding the whole engine in one screen chunk is memory-marginal (2 tracks OOM
at full scrub, 1 track fine). See `docs/ARCHITECTURE.md §10`. Conclusion: engine
runs; keep patterns sparse + screen scripts thin + load engine once.

**Pattern generator. ✅ BUILT.** `src/core/generate.lua` — a one-shot command
(not a live effect) that overwrites a pattern with a **Euclidean** rhythm whose
notes are drawn **root ± spread** for pitch (in scale degrees, in key), velocity,
and gate. **Seeded** (deterministic; reroll = seed++). Params: `scaleIndex,
root, hits, rotate, pitchRoot/Spread, velRoot/Spread, gateRoot/Spread, seed`.
Scale-degree walker in `scales.lua` (`Scales.step`). Hear it:
`lua proto/term/main.lua --gen --seed N --bpm 120`. See it: the `seq2_live`
screen bakes 4 generated variants at build time (data-only, ~1.7 KB, init
484 B) — encoder scrubs, KEY 0–3 select a variant. Not yet: chord-per-hit,
random-walk pitch, live EUCLID effect — all deferred (see grilling decisions).

**Hardware deploy (VSN1R). ✅ BUILT — pending on-device test.** `tools/build.lua`
emits two module bundles (`dist/seq2.lua` Core+midi_rx, `dist/seq2_ui.lua`
screen) — split to avoid the watchdog reboot seq-1 hit. `tools/gen_profile.py`
CLONES the proven element skeleton (`tools/vsn1r_template.json`, all 15 elements
— a partial profile makes the editor throw `undefined … 'events'`) and overrides
only element 255 (setup arms MIDI rx + init + generate) and element 13 (draw);
leftover button callbacks are no-op stubs. `--install` copies to
`grid-userdata/configs`. The full
device path (require → init → generate → MIDI clock → notes out → draw) is
verified in plain Lua. Upload steps + the Grid config/hook model live in
`docs/DEPLOY.md`. Confirmed playing on hardware, synced to Ableton.

**Controls + SETUP mode. ✅ BUILT.** `src/app/control.lua` (UI bundle): a
13-param model over the generator/fx, two view modes. **All control on
keyswitches 0-7 + encoder** — small buttons 9-12 are dead on the hardware.
PLAY: KS0-5 select HITS/KEY/SCALE/SPREAD/VEL/CHANCE, KS6 track, KS7 → SETUP;
encoder turn edits live (re-generates), click = REROLL. SETUP: KS0/1 nav,
KS5 reroll, KS7 exit — full-screen param grid (`draw_vsn1.lua` two modes).
Encoder is relative (`epmo(1)`, `epva()-64`). Verified headless. Map in
`docs/DEPLOY.md`.

**M3 — Record.** Quantized MIDI-in recording from a 16-button Grid module;
edit recorded events (add/delete/nudge).

**M4 — Patterns + swap.** Multiple patterns per track, pattern values, the
RAM file-swap path, sequence selection. Then revisit scaling past 2 tracks.

## When in doubt

Ask. We would rather pause and confirm than calcify an assumption. Names are
cheap to change now and expensive later — settle the glossary before coding.
