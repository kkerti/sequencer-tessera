# CV+Gate engine: reframing the sequencer as a sampled-state library

Decision date: 2026-04-28
Status: design accepted, implementation deferred. This document is the migration plan; no code has changed yet.

---

## Summary

The sequencer engine is being reframed from an **event-emitting** model (`"NOTE_ON" / "NOTE_OFF"` strings flowing out of `Step.getPulseEvent`) into a **sampled-state** model that mirrors the ER-101's CV-A / CV-B / GATE outputs. Each track exposes three values per clock pulse: a held pitch (CV-A), a held velocity (CV-B), and a boolean gate level. MIDI emission becomes a separate, ~15-line edge-detector stage applied to the gate stream.

In tandem, the **tape-deck player and the song compilation pipeline are being retired**. The lite engine now fits on device (17.8 KB stripped) and runs per-pulse on the Grid module directly; pre-rendered event arrays, schema v2, and the song writer all go away. One engine drives both authoring and playback.

This is the largest architectural change since the project began. It is being captured as a design doc first; no source files are being modified in this pass.

---

## Why now

Three things align:

1. **The 880-char per-file limit is gone** (see `2026-04-27-drop-char-limit-tooling.md`). This was the original justification for compiling songs to flat arrays.
2. **The lite engine is small enough to ship** (`2026-04-27-sequencer-lite-carve.md`). Per-pulse engine evaluation on device is now a practical option, not a luxury.
3. **The user has now seen the ER-101 manual end to end** and identified the CV+gate framing as conceptually simpler than NOTE_ON/NOTE_OFF pairing. The earlier event model was carried over from MIDI thinking; nothing in the engine actually requires it internally.

The compile pipeline was a workaround for a constraint that no longer exists. Removing it collapses two parallel mental models (engine emits events / player walks events) into one (engine exposes outputs / translator emits MIDI).

---

## The model in one sentence

> Each clock pulse, every track is a function `(cursor, pulseCounter) → (cvA, cvB, gate)`. MIDI is a downstream side effect of the gate stream's rising and falling edges.

---

## Per-pulse semantics

```
external CLOCK pulses :  | | | | | | | | | | | | | | | |
                         ^                 ^
                         step N starts     step N+1 starts
                                           (after duration ticks)

step N: pitch=60, velocity=100, duration=8, gate=3, ratchet=1
                         |---------------- 8 pulses ----------------|
CV-A (pitch)             [============= held at 60 =================][step N+1's pitch...
CV-B (velocity)          [============= held at 100 ================][step N+1's velocity...
GATE                     |‾‾‾3‾‾‾|________ 5 low ________|
```

Per-pulse algorithm (per track):

1. `Engine.onPulse` advances the scene chain on beat boundaries (unchanged).
2. `Track.advance` increments `pulseCounter`. When `pulseCounter >= step.duration`, it rolls the cursor to the next step (respecting loop points, direction mode, clock div/mult, probability) and resets `pulseCounter` to 0.
3. The host calls `Track.sample(track) → cvA, cvB, gate`, which composes:
   - `Step.sampleCv(step) → pitch, velocity` (constants for the current step)
   - `Step.sampleGate(step, pulseCounter) → boolean`
4. The host runs the **MIDI translator** (per track) over the gate stream's edges.

No event objects. No event queue. No edge detection inside the engine.

---

## Revised data model

### Step (semantics shift; record shape unchanged)

```
Step = {
    pitch       : 0-127    -- CV-A target while this step is current
    velocity    : 0-127    -- CV-B target while this step is current
    duration    : 0-99     -- length of this step in clock pulses (0 = skip step)
    gate        : 0-99     -- pulses the gate stays HIGH from each ratchet sub-window start
                            --   0              = gate stays low all step (rest)
                            --   gate >= duration = gate stays high all step (legato/tie)
    ratchet     : 1-4      -- number of equal-width gate pulses inside duration
    probability : 0-100    -- chance the step's gate is enabled this pass (rolled on entry)
    active      : boolean  -- mute switch; when false, gate stays low
}
```

The record fields don't change. What changes is what reads them.

#### New samplers (replace `Step.getPulseEvent`)

```lua
-- Constant for the duration of the step.
function Step.sampleCv(step)
    return step.pitch, step.velocity
end

-- True when the gate is HIGH at pulseCounter pulses into this step.
function Step.sampleGate(step, pulseCounter)
    if not step.active        then return false end
    if step.duration == 0     then return false end
    if step.gate     == 0     then return false end

    if step.ratchet == 1 then
        return pulseCounter < step.gate
    end

    -- ratchet > 1: split duration into N equal sub-windows.
    -- Spread integer remainder across the first windows so the math stays exact.
    local subLen   = math.floor(step.duration / step.ratchet)
    local subIdx   = math.floor(pulseCounter / subLen)
    if subIdx >= step.ratchet then subIdx = step.ratchet - 1 end
    local subStart = subIdx * subLen
    local subGate  = step.gate
    if subGate > subLen then subGate = subLen end
    return pulseCounter < subStart + subGate
end
```

`Step.getPulseEvent`, `stepIsRatchetOnPulse`, `stepIsRatchetOffPulse`, the "NOTE_ON wins on collision" rule — all gone. The behaviour they encoded is now implicit in the gate predicate.

### Track (mostly unchanged)

Same shape: `patterns[]`, `cursor`, `pulseCounter`, `loopStart/loopEnd`, `clockDiv/Mult`, `direction`, `midiChannel`. API changes:

| Before | After |
|---|---|
| `Track.advance(track) → "NOTE_ON" / "NOTE_OFF" / nil` | `Track.advance(track) → step` (just bumps state) |
| n/a | `Track.sample(track) → cvA, cvB, gate` |

`Track.advance` now contains the **probability roll on step entry**: when `pulseCounter` rolls back to 0 and the cursor lands on a new step, roll once against `step.probability` and stash the result in a per-track `currentStepGateEnabled` flag. `Track.sample` AND-combines this flag with `Step.sampleGate`. This makes probability free per-pulse and consistent with Blackbox-style "one chance per pass".

### Engine (one new sampler)

Same shape. New API:

| Before | After |
|---|---|
| `Engine.advanceTrack(eng, i) → step, event` | `Engine.advanceTrack(eng, i) → step` |
| n/a | `Engine.sampleTrack(eng, i) → cvA, cvB, gate` |

`Engine.onPulse` is unchanged.

### MIDI translator (new, ~15 lines per track)

Owned by the host (the player or test harness). Per-track state: `prevGate`, `lastPitch`.

```lua
-- Re-trigger on pitch change is the chosen behaviour:
-- always emit a NOTE_OFF for the old pitch before NOTE_ON for the new.
function midiTranslate(state, cvA, cvB, gate, channel, emit)
    if gate and not state.prevGate then
        emit("NOTE_ON", cvA, cvB, channel)
        state.lastPitch = cvA
    elseif not gate and state.prevGate then
        emit("NOTE_OFF", state.lastPitch, 0, channel)
        state.lastPitch = nil
    elseif gate and state.prevGate and cvA ~= state.lastPitch then
        emit("NOTE_OFF", state.lastPitch, 0, channel)
        emit("NOTE_ON",  cvA,             cvB, channel)
        state.lastPitch = cvA
    end
    state.prevGate = gate
end

-- Panic / all-notes-off:
function midiPanic(state, channel, emit)
    if state.prevGate and state.lastPitch then
        emit("NOTE_OFF", state.lastPitch, 0, channel)
    end
    state.prevGate  = false
    state.lastPitch = nil
end
```

This is the **only** place MIDI semantics live. Re-trigger-on-pitch-change is one branch. All-notes-off is two checks per track instead of an O(cursor) scan with linear pair-search.

---

## Player reshape: tape deck → driver

### What goes away

| File / concept | Reason |
|---|---|
| `tools/song_compile.lua` | No precompilation; songs are just descriptors. |
| `compiled/` directory | Same. |
| Schema v2 (`atPulse[]`, `kind[]`, `pairOff[]`, `srcStepProb[]`, `srcVelocity[]`) | Engine state is the source of truth. |
| `sequencer/song_writer.lua` | Probability rolls inside the engine on step entry. |
| `live/edit.lua` | All edits are live by definition — they go straight to step records. |
| `kind[]` codes 0/1/2/3 | No events to encode. |
| `Player.allNotesOff` linear pair-search | Replaced by per-track `midiPanic`. |
| `main.lua` vs `main_lite.lua` distinction | One engine, one harness. |

### What stays / changes

- `sequencer_lite/` becomes the canonical runtime engine on device. Bundled per current pipeline.
- `player/player.lua` shrinks to a **per-pulse driver**: advance engine, sample each track, translate, emit. ~50 lines.
- The two clock modes (internal firmware timer / external MIDI 0xF8) are unchanged conceptually — same shim around `Player.externalPulse(p, emit)`.
- Scenes, mathops, snapshots, probability all "just work" on device because they live inside the engine.

### New player skeleton (illustrative, not yet implemented)

```lua
function Player.externalPulse(p, emit)
    if not p.running then return end
    p.pulseCount = p.pulseCount + 1

    Engine.onPulse(p.engine, p.pulseCount)         -- scene chain etc.
    for t = 1, p.engine.trackCount do
        Engine.advanceTrack(p.engine, t)            -- bump cursor / pulseCounter / probability roll
        local cvA, cvB, gate = Engine.sampleTrack(p.engine, t)
        local channel = Track.getMidiChannel(p.engine.tracks[t]) or t
        midiTranslate(p.midiState[t], cvA, cvB, gate, channel, emit)
    end

    -- Loop boundary: the engine handles its own loop points per track.
    -- The "song-level loop boundary" hook is gone; nothing reruns at loop end.
end
```

`Engine.reset` plus a per-track `midiPanic` covers RESET / STOP behaviour.

---

## Migration plan (when implementation begins)

This document is the spec. When code work starts, the order is:

1. **Spec the sampler in tests first.** Add `tests/step_sample.lua` with cases that mirror the existing `Step.getPulseEvent` truth table — same inputs, but asserting `(cvA, cvB, gate)` per pulse. Cover ratchet 1–4, rest, legato, mute, duration=0.
2. **Add `Step.sampleCv` / `Step.sampleGate`** alongside `Step.getPulseEvent`. Keep the old function for now. Get tests green.
3. **Add `Track.sample`** and the in-engine probability-on-entry roll. Update `Track.advance` to drop its event return value. Update tests/track.lua and tests/engine.lua.
4. **Write the MIDI translator** as a standalone module (e.g. `sequencer/midi_translate.lua`). Test it in isolation with hand-crafted gate sequences.
5. **Rewrite `player/player.lua`** as the driver shim above. Update `tests/player.lua` to drive an engine instead of a compiled song.
6. **Rewrite `main.lua` / `main_lite.lua`** to use the new player. Remove the `compiled/` / `song_writer` paths from the live-edit harness.
7. **Delete the dead pipeline:** `tools/song_compile.lua`, `compiled/`, `sequencer/song_writer.lua`, `live/edit.lua`, `tests/song_writer.lua`, `tests/live_edit.lua`, schema-v2 references in `ARCHITECTURE.md`. Update the build commands in `README.md`.
8. **Update `sequencer_lite/`** to mirror the new `sequencer/` shape. Re-bundle `grid/sequencer_lite.lua`.
9. **Update `grid_module.lua`** INIT/TIMER/rtmidi-callback blocks to load a song descriptor, build an engine from it, and feed the new driver player.
10. **Update `docs/ARCHITECTURE.md`** to describe the single-engine pipeline; mark the compile pipeline as historical.

Each step is independently testable. The branch can stay green throughout.

---

## Open questions deferred to implementation time

- **Patches as descriptors:** the existing `patches/<name>.lua` are already pure-data tables. They likely need a small loader (`Patch.build(descriptor) → engine`) that today is implicit in `tools/song_compile.lua`. This is the only piece of the compile pipeline that survives — under a different name.
- **Per-pulse cost on the ESP32:** estimated to be fine (integer-only, no allocation, ~8 tracks × a few ns each). Worth measuring with `tools/memprofile.lua` (and a CPU equivalent) before fully retiring the tape-deck path.
- **Snapshot / scene revival on device:** these were dropped from `sequencer_lite/` (see `docs/dropped-features.md`). They become more interesting again under this model because they're useful runtime features, not just authoring tools. Bringing them back is now mostly a size-budget question.

---

## Decisions captured (2026-04-28)

| Question | Answer |
|---|---|
| Player architecture | **Engine runs on device.** Drop `song_compile`, `compiled/`, `song_writer`, `live/edit`. Single engine source of truth. |
| Pitch change mid-gate | **Re-trigger.** Emit NOTE_OFF (old pitch) then NOTE_ON (new pitch) when gate stays high but `cvA` changes between steps. |
| Probability roll timing | **On step entry.** When the cursor advances onto a step, roll once against `step.probability`; gate predicate ANDs with the roll result. Matches Blackbox. |
| Implementation now? | **No.** This document is the spec. Implementation begins in a later session. |
