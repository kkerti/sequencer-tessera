# CV+Gate engine: sampled-state refactor brief

Decision date: 2026-04-28.
Status: **complete.** All 13 steps shipped in one session. See "Outcome" at the bottom for the post-refactor file layout, file sizes, and test results.

This brief replaces an earlier draft of the same name that predated the
boolean-ratchet decision and the death of the compile pipeline. It is the
working spec for the cutover.

---

## ER-101 reference (the one source of truth for behaviour)

From `docs/manuals/er-101-user-manual-f2.09/er-101-user-manual-f2.09.md`:

- A track has three outputs: **CV-A**, **CV-B**, **GATE** (line 45).
- CV-A and CV-B are 14-bit voltages held for the duration of a step.
- GATE is binary (0 V / 9 V), edge-triggered by clock pulses.
- Outputs refresh at ~3 kHz; clock pulses are the meaningful event grid.
- Step parameters: `DURATION` (0–99 pulses), `GATE` (0–99 pulses).
- `GATE = 0` → rest (gate stays low whole step).
- `GATE >= DURATION` → legato (gate stays high whole step).
- **Ratcheting** is a per-step boolean (line 641). When enabled, the gate
  cycles HIGH for `gate` pulses, LOW for `gate` pulses, repeated until
  `duration` is reached. The example in the manual: `dur=8 gate=2` → two
  on/off pairs (lines 643–647).

Smoothing (line 635), trigger mode (line 760), CV-B as a separate
modulation source — out of scope. We ship MIDI only; CV-B carries velocity.

## The model

Each clock pulse, every track is a function

```
(cursor, pulseCounter) → (cvA, cvB, gate)
```

- `cvA = step.pitch`        held for the step
- `cvB = step.velocity`     held for the step
- `gate = boolean`          high/low according to ratchet rule below

MIDI (`NOTE_ON` / `NOTE_OFF`) is a downstream effect of gate edges.
Pitch changes mid-gate trigger a `NOTE_OFF` then `NOTE_ON` (re-trigger).

## Ratchet rule (boolean ratch, ER-101)

```
let dur  = step.duration
let gate = step.gate

if not step.active        : false
if dur  == 0              : false           -- skip step
if gate == 0              : false           -- rest
if gate >= dur            : true            -- legato

if not step.ratch         :
    return pulseCounter < gate              -- HIGH for first `gate` pulses

else                      :                 -- ER-101 ratchet
    if pulseCounter >= dur : false          -- final low tail
    period = gate * 2
    phase  = pulseCounter mod period
    return phase < gate                     -- HIGH on [0, gate)
```

This is a direct rewrite of the existing `Step.getPulseEvent` truth table
into a level predicate. No semantic change.

## Probability

Rolled **on step entry** (when the cursor lands on a step and
`pulseCounter` resets to 0). Result stored on the track as
`currentStepGateEnabled : boolean`. `Track.sample` returns
`gate AND currentStepGateEnabled`. Skipped steps (`duration=0`) do not
roll. Match Blackbox semantics: one chance per pass.

## Files added

| Path | Role |
|---|---|
| `sequencer/midi_translate.lua` | gate stream → NOTE_ON/OFF + retrigger; per-track state `{prevGate, lastPitch}` |
| `sequencer/patch_loader.lua`   | descriptor table (patches/<name>.lua) → built `Engine` |

## Files deleted (dead pipeline)

```
tools/song_compile.lua
compiled/
sequencer/song_writer.lua
live/edit.lua
song_loader.lua
main_lite.lua
tests/song_writer.lua
tests/live_edit.lua
```

`live/edit.lua` ops were O(1) edits on the compiled event arrays. With the
engine on device, mutating `step` records via the existing `Step.setPitch`
/ `Step.setVelocity` / `Step.setActive` setters is the live edit story.
No separate module needed.

## Files reshaped

| Path | Change |
|---|---|
| `sequencer/step.lua`           | add `Step.sampleCv`, `Step.sampleGate`; remove `Step.getPulseEvent` |
| `sequencer/track.lua`          | `Track.advance` returns nothing; add `Track.sample`; roll probability on step entry |
| `sequencer/engine.lua`         | `Engine.advanceTrack` returns nothing; add `Engine.sampleTrack` |
| `sequencer_lite/*.lua`         | mirror sequencer/ (lite is byte-equivalent for shared modules) |
| `player/player.lua`            | rewritten as engine driver: per pulse, advance all tracks, sample, translate, emit |
| `main.lua`                     | load descriptor → patch_loader → engine → driver player |
| `grid_module.lua`              | INIT loads descriptor + sequencer_lite engine + player |

## API summary (post-refactor)

```lua
-- Step
local cvA, cvB = Step.sampleCv(step)            -- pitch, velocity
local high     = Step.sampleGate(step, pulseCounter)

-- Track (no event return value)
Track.advance(track)                             -- bumps cursor / pulseCounter; rolls prob on entry
local cvA, cvB, gate = Track.sample(track)

-- Engine
Engine.advanceTrack(eng, i)
local cvA, cvB, gate = Engine.sampleTrack(eng, i)

-- MIDI translator (host-owned per-track state)
MidiTranslate.new()                              -- → { prevGate=false, lastPitch=nil }
MidiTranslate.step(state, cvA, cvB, gate, channel, emit)
MidiTranslate.panic(state, channel, emit)

-- Patch
local engine = PatchLoader.build(descriptor)

-- Player (driver)
local player = Player.new(engine, clockFn)
Player.start(player)
Player.tick(player, emit)                        -- internal-clock mode
Player.externalPulse(player, emit)               -- 1 pulse, external-clock mode
Player.allNotesOff(player, emit)                 -- panic on stop
```

## Order of work

1. Brief (this file).
2. `Step.sampleCv` / `Step.sampleGate` + tests; delete `getPulseEvent`.
3. `Track.advance` no-return + `Track.sample` + probability roll on entry; tests.
4. `Engine.sampleTrack`; tests.
5. `sequencer/midi_translate.lua`; tests.
6. `sequencer/patch_loader.lua`; tests.
7. Rewrite `player/player.lua` + tests.
8. Mirror sequencer_lite/*.lua + smoke test.
9. Rewrite scenarios (`tests/sequences/*.lua`) and `tests/sequence_runner.lua` to use samplers + translator.
10. Rewrite `main.lua`.
11. Delete dead pipeline files.
12. Rebuild `grid/` and rewrite `grid_module.lua`.
13. Update README, AGENTS, ARCHITECTURE.

Each numbered step is independently testable. Run the full suite at the
end of each step.

---

## Outcome

All 13 steps landed in a single session.

### Final file layout

```
main.lua                       -- PatchLoader → Driver → libuv timer → bridge.py
sequencer/                     -- full engine + midi_translate + patch_loader
sequencer_lite/                -- on-device engine carve
driver/driver.lua              -- per-pulse sample → translate → advance loop
patches/{dark_groove,four_on_floor,empty}.lua
grid/{sequencer,dark_groove,four_on_floor,empty}.lua
tools/{build_grid,bundle,strip,charcheck,memprofile}.lua
tests/{utils,step,pattern,track,engine,mathops,snapshot,scene,tui,
       probability,midi_translate,patch_loader,driver,sequencer_lite,
       grid_bundle_smoke,sequence_runner}.lua
```

### Deleted

- `tools/song_compile.lua` — compile pipeline (no longer needed: engine runs on device).
- `sequencer/song_writer.lua` — per-loop probability re-roll (replaced by `track.lua`'s `trackRollEntryProbability`).
- `live/edit.lua` — in-place compiled-song editor (replaced by direct `Step.set*` / `Track.set*` on the live engine).
- `player/player.lua` + `tests/player.lua` — tape-deck player (replaced by `driver/driver.lua`, samples engine instead of walking events).
- `compiled/` — output of the compile pipeline.
- `song_loader.lua` — bridged compiled song to player.
- `main_lite.lua` — ship-mirror harness for compiled songs.
- `tests/song_writer.lua`, `tests/live_edit.lua` — tests for deleted modules.

### Key API renames

- `Player` → `Driver` (it drives the engine; the engine is the music source).
- `Engine.tick(emit)` → `Engine.sampleTrack(eng, i) → cvA, cvB, gate` + `Engine.advanceTrack(eng, i)` (no return).
- `Step.getPulseEvent(s, p) → event` → `Step.sampleCv(s) → pitch, vel` + `Step.sampleGate(s, p) → bool`.
- `Track.advance(t) → step` → `Track.sample(t) → cvA, cvB, gate` + `Track.advance(t)` (no return).

### Bundle size

`grid/sequencer.lua`: 40.4 KB raw → 20.9 KB stripped (48.2% delta). Single file containing lite engine + MidiTranslate + PatchLoader + Driver.

### Test results

- 15 unit-test files: all pass.
- 9 sequence scenarios: all pass via real `Driver` (no scenario file changes — the abstraction held cleanly).
- 1 grid-bundle smoke test: loads `grid/sequencer.lua` exactly as device would; drives 96 pulses; asserts 48 emit calls for `four_on_floor`.

### Next

Hardware verification of the new bundle on a real Grid module. After that, on-device authoring UI work (button-driven start/stop, knob-driven mathops, patch selector).
