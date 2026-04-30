# Sequencer Features & Grid Controller Tutorial

**Session:** 2026-04-11 | **Topic:** Comprehensive feature reference, Lua code examples for Grid controllers, step-by-step demo tutorial

---

## Table of contents

1. [Architecture overview](#1-architecture-overview)
2. [Data model diagram](#2-data-model-diagram)
3. [Feature reference](#3-feature-reference)
4. [API quick reference](#4-api-quick-reference)
5. [Tutorial: building a sequence from scratch](#5-tutorial-building-a-sequence-from-scratch)
6. [Grid controller integration patterns](#6-grid-controller-integration-patterns)
7. [Complete Grid controller example](#7-complete-grid-controller-example)
8. [Signal flow diagrams](#8-signal-flow-diagrams)

---

## 1. Architecture overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          Grid Controller (ESP32)                        │
│                                                                         │
│  ┌──────────┐   ┌──────────────┐   ┌──────────────┐   ┌─────────────┐  │
│  │ Encoders │──▶│              │──▶│              │──▶│   MIDI TX    │  │
│  │ Keys     │   │  Controller  │   │   Engine     │   │  (NOTE_ON /  │  │
│  │ Faders   │──▶│  (your Lua)  │──▶│  .tick()     │──▶│   NOTE_OFF)  │  │
│  │ Buttons  │   │              │   │              │   │             │  │
│  └──────────┘   └──────┬───────┘   └──────────────┘   └─────────────┘  │
│                        │                                                │
│                        ▼                                                │
│                 ┌──────────────┐                                        │
│                 │   Screen     │                                        │
│                 │  (320×240)   │                                        │
│                 └──────────────┘                                        │
└──────────────────────────────────────────────────────────────────────────┘
```

The sequencer is a **library** — it has no opinions about input or display. Your controller code calls the public API functions to build sequences, mutate them live, and read back state for screen rendering. A single timer drives `Engine.tick()` which returns MIDI events to emit.

---

## 2. Data model diagram

```
SNAPSHOT (up to 16 save slots)
 │
 └─── ENGINE
       ├── bpm: 120              (20–300)
       ├── pulsesPerBeat: 4      (clock resolution)
       ├── swingPercent: 50      (50–72, 50 = straight)
       ├── scaleName: "major"    (or nil = no quantize)
       ├── rootNote: 0           (0–11, C=0 D=2 E=4 ...)
       ├── running: true/false
       │
       ├── TRACK 1 ──────────────────────────────────────────
       │    ├── clockDiv: 1       (1–99, slows playback)
       │    ├── clockMult: 1      (1–99, speeds playback)
       │    ├── direction: "forward"  (forward/reverse/pingpong/random/brownian)
       │    ├── midiChannel: 1    (1–16)
       │    ├── loopStart: nil    (flat step index or nil)
       │    ├── loopEnd: nil      (flat step index or nil)
       │    ├── cursor: 1         (current playhead position)
       │    │
       │    ├── PATTERN 1 "intro" ────────────────────────
       │    │    ├── Step 1  { pitch=60, vel=100, dur=4, gate=3, ratchet=1, active=true }
       │    │    ├── Step 2  { pitch=62, vel= 90, dur=4, gate=2, ratchet=1, active=true }
       │    │    ├── ...
       │    │    └── Step 8
       │    │
       │    └── PATTERN 2 "groove" ───────────────────────
       │         ├── Step 9   (flat index continues across patterns)
       │         ├── Step 10
       │         ├── ...
       │         └── Step 16
       │
       ├── TRACK 2 ──────────────────────────────────────────
       │    └── (same structure, independent clock/loop/direction)
       │
       ├── TRACK 3
       └── TRACK 4
```

### Step parameter reference

```
┌─────────────────────────────────────────────────────────────────────────┐
│  STEP                                                                   │
│                                                                         │
│  pitch     0–127   MIDI note number (60 = C4)                          │
│  velocity  0–127   MIDI velocity                                        │
│  duration  0–99    Step length in clock pulses (0 = skip entirely)      │
│  gate      0–99    Note-on length in pulses (0 = rest / silent step)   │
│  ratchet   1–4     Repeat count within the step (Metropolis-style)     │
│  active    bool    Mute toggle (false = skip without deleting)         │
│                                                                         │
│  Playable = active AND duration > 0 AND gate > 0                       │
│  Legato   = gate >= duration (note sustains into next step)            │
│  Rest     = gate == 0 (step plays its duration silently)               │
│  Skip     = duration == 0 (step is jumped over entirely)               │
└─────────────────────────────────────────────────────────────────────────┘
```

### Flat indexing across patterns

```
Pattern 1 (8 steps)          Pattern 2 (8 steps)
┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
│ 1 │ 2 │ 3 │ 4 │ 5 │ 6 │ 7 │ 8 │ 9 │10 │11 │12 │13 │14 │15 │16 │  ← flat index
└───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
                                ▲                           ▲
                            loopStart=9                 loopEnd=16
```

Steps are always addressed by **flat 1-based index** across the entire track. `Track.patternStartIndex()` and `Track.patternEndIndex()` convert between pattern number and flat index.

---

## 3. Feature reference

### 3.1 Clock division & multiplication

Each track has its own clock divider and multiplier. The engine uses an accumulator — no drift, any integer ratio.

```
┌────────────────────────────────────────────────────────────────┐
│  Engine pulse  │ 1 │ 2 │ 3 │ 4 │ 5 │ 6 │ 7 │ 8 │ 9 │10 │    │
│────────────────┼───┼───┼───┼───┼───┼───┼───┼───┼───┼───┤    │
│  div=1 mult=1  │ ● │ ● │ ● │ ● │ ● │ ● │ ● │ ● │ ● │ ● │    │
│  div=2 mult=1  │ ● │   │ ● │   │ ● │   │ ● │   │ ● │   │    │
│  div=1 mult=2  │ ●●│ ●●│ ●●│ ●●│ ●●│ ●●│ ●●│ ●●│ ●●│ ●●│    │
│  div=3 mult=1  │ ● │   │   │ ● │   │   │ ● │   │   │ ● │    │
│  div=1 mult=3  │●●●│●●●│●●●│●●●│●●●│●●●│●●●│●●●│●●●│●●●│    │
└────────────────────────────────────────────────────────────────┘
  ● = track advances on this engine pulse
```

```lua
-- Half-speed: track advances every 2nd engine pulse
Track.setClockDiv(track, 2)

-- Double-speed: track advances twice per engine pulse
Track.setClockMult(track, 2)

-- Polyrhythm: 3 against 4
Track.setClockDiv(trackA, 1)   -- normal speed
Track.setClockDiv(trackB, 3)
Track.setClockMult(trackB, 4)  -- 4 advances per 3 engine pulses
```

### 3.2 Direction modes

```
Forward:    1 → 2 → 3 → 4 → 1 → 2 → 3 → 4 → ...
Reverse:    4 → 3 → 2 → 1 → 4 → 3 → 2 → 1 → ...
Ping-Pong:  1 → 2 → 3 → 4 → 3 → 2 → 1 → 2 → 3 → 4 → ...
Random:     3 → 1 → 4 → 2 → 4 → 3 → 1 → 1 → ...  (uniform random)
Brownian:   1 → 2 → 3 → 2 → 3 → 4 → 3 → 4 → ...  (random walk ±1)
```

```lua
Track.setDirection(track, "forward")
Track.setDirection(track, "reverse")
Track.setDirection(track, "pingpong")
Track.setDirection(track, "random")
Track.setDirection(track, "brownian")
```

### 3.3 Ratcheting (Metropolis-style)

Each step can repeat 1–4 times within its duration window. The step's gate time is subdivided equally.

```
ratchet=1 (default):  ┌────────────┐
                      │  NOTE_ON   │          (one note for full gate)

ratchet=2:            ┌─────┐ ┌─────┐
                      │ ON  │ │ ON  │         (two hits, each half gate)

ratchet=3:            ┌───┐ ┌───┐ ┌───┐
                      │ON │ │ON │ │ON │       (three hits)

ratchet=4:            ┌──┐ ┌──┐ ┌──┐ ┌──┐
                      │ON│ │ON│ │ON│ │ON│     (four hits)
```

```lua
local step = Step.new(60, 100, 4, 3, 2)  -- pitch=C4, vel=100, dur=4, gate=3, ratchet=2
Step.setRatchet(step, 4)                  -- change to 4 ratchets
```

### 3.4 Loop points

Loop points are **per-track**, expressed as flat step indices. The playhead wraps within the loop boundaries. `RESET` always ignores loop points and rewinds to step 1.

```
Full track:   [  1  2  3  4  5  6  7  8  9  10  11  12  13  14  15  16  ]
                                     ▲                              ▲
                                loopStart=5                    loopEnd=16

Playback:     1 → 2 → 3 → 4 → 5 → 6 → ... → 16 → 5 → 6 → ... → 16 → 5 → ...
                  intro (plays once)     └── loops forever ──┘
```

```lua
-- Loop over pattern 2 only
Track.setLoopStart(track, Track.patternStartIndex(track, 2))
Track.setLoopEnd(track, Track.patternEndIndex(track, 2))

-- Clear loop (play full track linearly, then wrap from end to start)
Track.clearLoopStart(track)
Track.clearLoopEnd(track)
```

### 3.5 Live scale quantizer

30 built-in scales. Pitch stored as raw MIDI note; quantization happens at output time in `Engine.tick()` via `Step.resolvePitch()`. Change the scale mid-performance and all notes adapt instantly.

```lua
-- Set scale: all output pitches quantized to C major
Engine.setScale(engine, "major", 0)     -- rootNote 0 = C

-- Switch to D minor pentatonic
Engine.setScale(engine, "minorPentatonic", 2)  -- rootNote 2 = D

-- Disable quantization (raw MIDI values pass through)
Engine.clearScale(engine)
```

**Available scales (30):** chromatic, major, naturalMinor, harmonicMinor, melodicMinor, dorian, phrygian, lydian, mixolydian, locrian, majorPentatonic, minorPentatonic, blues, wholeTone, diminished, arabic, hungarianMinor, persian, japanese, egyptian, spanish, iwato, hirajoshi, inSen, pelog, prometheus, neapolitanMajor, neapolitanMinor, enigmatic, leadingWholeTone

### 3.6 Swing

Global swing percentage (50–72). 50 = straight time. Higher values delay off-beat pulses, creating shuffle/swing feel. In the current pulse-driven engine, this is implemented as a fractional hold on selected off-beat pulses.

```
Swing 50% (straight):    ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐
                          │ │ │ │ │ │ │ │ │ │ │ │ │ │ │ │
                          ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼ ▼
                          evenly spaced

Swing 66% (shuffle):     ┌─┐   ┌─┐ ┌─┐   ┌─┐ ┌─┐   ┌─┐ ┌─┐   ┌─┐
                          │ │   │ │ │ │   │ │ │ │   │ │ │ │   │ │
                          ▼     ▼ ▼     ▼ ▼     ▼ ▼     ▼
                          long-short-long-short pattern (triplet feel)
```

```lua
Engine.setSwing(engine, 50)   -- straight
Engine.setSwing(engine, 56)   -- light swing
Engine.setSwing(engine, 66)   -- heavy shuffle (triplet feel)
Engine.setSwing(engine, 72)   -- maximum swing
```

### 3.7 Math operations

Transform step parameters across ranges. Scoped to any contiguous range of steps (defaults to entire track).

```lua
-- Transpose all steps up an octave
MathOps.transpose(track, 12)

-- Transpose only pattern 2 down a fifth
local s = Track.patternStartIndex(track, 2)
local e = Track.patternEndIndex(track, 2)
MathOps.transpose(track, -7, s, e)

-- Add random variation to velocity (±15)
MathOps.jitter(track, "velocity", 15)

-- Randomize gate lengths for steps 1–8
MathOps.randomize(track, "gate", 1, 4, 1, 8)

-- Randomize ratchet counts
MathOps.randomize(track, "ratchet", 1, 4)
```

### 3.8 Snapshots

Save and load the entire engine state (all tracks, patterns, steps, clock settings, loop points, scale, swing).

```lua
-- Save to file
Snapshot.saveToFile(engine, "snapshots/my_sequence.lua")

-- Load from file
local restored = Snapshot.loadFromFile("snapshots/my_sequence.lua")

-- Serialize to table (for custom storage)
local data = Snapshot.toTable(engine)

-- Restore from table
local engine2 = Snapshot.fromTable(data)
```

---

## 4. API quick reference

### Module loading

```lua
local Engine  = require("sequencer/engine")
local Track   = require("sequencer/track")
local Step    = require("sequencer/step")
local Pattern = require("sequencer/pattern")
local MathOps = require("sequencer/mathops")
local Snapshot = require("sequencer/snapshot")
local Utils   = require("utils")
```

### Cheat sheet

```
ENGINE                              TRACK
──────                              ─────
Engine.new(bpm, ppb, tracks, steps) Track.new()
Engine.setBpm(eng, bpm)             Track.addPattern(trk, stepCount)
Engine.setSwing(eng, percent)       Track.getPattern(trk, index)
Engine.setScale(eng, name, root)    Track.getStep(trk, flatIndex)
Engine.clearScale(eng)              Track.setStep(trk, flatIndex, step)
Engine.getTrack(eng, index)         Track.getCurrentStep(trk)
Engine.tick(eng) → events           Track.setLoopStart(trk, index)
Engine.reset(eng) → off_events      Track.setLoopEnd(trk, index)
Engine.stop(eng) → off_events       Track.clearLoopStart(trk)
Engine.start(eng)                   Track.clearLoopEnd(trk)
Engine.allNotesOff(eng) → events    Track.setClockDiv(trk, value)
                                    Track.setClockMult(trk, value)
STEP                                Track.setDirection(trk, dir)
────                                Track.setMidiChannel(trk, ch)
Step.new(pitch, vel, dur, gate, r)  Track.advance(trk) → event
Step.getPitch / setPitch             Track.reset(trk)
Step.getVelocity / setVelocity       Track.getStepCount(trk)
Step.getDuration / setDuration       Track.patternStartIndex(trk, pi)
Step.getGate / setGate               Track.patternEndIndex(trk, pi)
Step.getRatchet / setRatchet
Step.getActive / setActive          MATHOPS
Step.isPlayable(step)               ───────
Step.resolvePitch(step, scale, root) MathOps.transpose(trk, semi, s, e)
Step.getPulseEvent(step, pulse)     MathOps.jitter(trk, param, amt, s, e)
                                    MathOps.randomize(trk, param, min, max, s, e)
PATTERN
───────                             SNAPSHOT
Pattern.new(stepCount, name)        ────────
Pattern.getStepCount(pat)           Snapshot.toTable(eng)
Pattern.getStep(pat, index)         Snapshot.fromTable(data)
Pattern.setStep(pat, index, step)   Snapshot.saveToFile(eng, path)
Pattern.getName / setName            Snapshot.loadFromFile(path)
```

---

## 5. Tutorial: building a sequence from scratch

This is a complete walkthrough. Each section builds on the previous one.

### Step 1: Create the engine

```lua
local Engine = require("sequencer/engine")
local Track  = require("sequencer/track")
local Step   = require("sequencer/step")

-- 120 BPM, 4 pulses per beat (16th note resolution), 2 tracks, 0 initial steps
local engine = Engine.new(120, 4, 2, 0)
```

### Step 2: Set up Track 1 — a bass line

```lua
local bass = Engine.getTrack(engine, 1)
Track.setMidiChannel(bass, 1)

-- Add two 8-step patterns
local patternA = Track.addPattern(bass, 8)   -- "intro" phrase
local patternB = Track.addPattern(bass, 8)   -- "groove" phrase

-- Pattern A: melodic intro (flat indices 1–8)
-- Step.new(pitch, velocity, duration, gate, ratchet)
Track.setStep(bass, 1, Step.new(48, 100, 4, 3))    -- C3, quarter note, gate 3 pulses
Track.setStep(bass, 2, Step.new(51,  90, 4, 3))    -- Eb3
Track.setStep(bass, 3, Step.new(53,  95, 4, 3))    -- F3
Track.setStep(bass, 4, Step.new(55,  85, 4, 3))    -- G3
Track.setStep(bass, 5, Step.new(58, 100, 4, 3))    -- Bb3
Track.setStep(bass, 6, Step.new(55,  80, 4, 2))    -- G3, shorter gate
Track.setStep(bass, 7, Step.new(53,  90, 4, 3))    -- F3
Track.setStep(bass, 8, Step.new(48,  70, 4, 0))    -- C3, rest (gate=0)

-- Pattern B: syncopated groove (flat indices 9–16)
Track.setStep(bass,  9, Step.new(48, 100, 2, 2))      -- C3, eighth note
Track.setStep(bass, 10, Step.new(48,  80, 2, 1, 2))   -- C3, ratchet=2 (double hit)
Track.setStep(bass, 11, Step.new(55, 100, 4, 3))      -- G3, quarter
Track.setStep(bass, 12, Step.new(53,  90, 2, 2))      -- F3, eighth
Track.setStep(bass, 13, Step.new(51,  85, 2, 1, 2))   -- Eb3, ratchet=2
Track.setStep(bass, 14, Step.new(53,  95, 4, 3))      -- F3, quarter
Track.setStep(bass, 15, Step.new(48,  75, 2, 2))      -- C3, eighth
Track.setStep(bass, 16, Step.new(48, 100, 2, 0))      -- C3, rest
```

### Step 3: Set loop points

```lua
-- After the intro plays once, loop over the groove pattern
Track.setLoopStart(bass, Track.patternStartIndex(bass, 2))  -- flat index 9
Track.setLoopEnd(bass, Track.patternEndIndex(bass, 2))      -- flat index 16
```

```
Playback flow:

  Pattern A (intro)              Pattern B (groove — loops)
  ┌───┬───┬───┬───┬───┬───┬───┬───╥───┬───┬───┬───┬───┬───┬───┬───┐
  │ 1 │ 2 │ 3 │ 4 │ 5 │ 6 │ 7 │ 8 ║ 9 │10 │11 │12 │13 │14 │15 │16 │
  └───┴───┴───┴───┴───┴───┴───┴───╨───┴───┴───┴───┴───┴───┴───┴───┘
  plays once ──────────────────────▶ ◀──── loops forever ──────────▶
```

### Step 4: Set up Track 2 — chords at half speed

```lua
local chords = Engine.getTrack(engine, 2)
Track.setMidiChannel(chords, 2)
Track.setClockDiv(chords, 2)              -- half-speed
Track.setDirection(chords, "pingpong")    -- bounce back and forth

local patChords = Track.addPattern(chords, 4)
Track.setStep(chords, 1, Step.new(60, 80, 4, 3))   -- C4
Track.setStep(chords, 2, Step.new(63, 75, 4, 3))   -- Eb4
Track.setStep(chords, 3, Step.new(67, 80, 4, 3))   -- G4
Track.setStep(chords, 4, Step.new(70, 70, 4, 2))   -- Bb4
```

### Step 5: Configure global engine settings

```lua
Engine.setSwing(engine, 56)                       -- light swing
Engine.setScale(engine, "minorPentatonic", 0)     -- C minor pentatonic
```

### Step 6: Run the engine (timer loop)

```lua
-- On Grid this is the single device timer.
-- On macOS dev, use luv:
local uv = require("luv")

local intervalMs = math.floor(engine.pulseIntervalMs)

local timer = uv.new_timer()
uv.timer_start(timer, 0, intervalMs, function()
    local events = Engine.tick(engine)

    for _, event in ipairs(events) do
        if event.type == "NOTE_ON" then
            -- emit MIDI note on: event.pitch, event.velocity, event.channel
        elseif event.type == "NOTE_OFF" then
            -- emit MIDI note off: event.pitch, event.channel
        end
    end
end)

uv.run()
```

### Step 7: Live mutations during playback

```lua
-- Change BPM on the fly
Engine.setBpm(engine, 140)

-- Switch scale
Engine.setScale(engine, "dorian", 0)

-- Transpose pattern B up a minor third
local s = Track.patternStartIndex(bass, 2)
local e = Track.patternEndIndex(bass, 2)
MathOps.transpose(bass, 3, s, e)

-- Add velocity variation
MathOps.jitter(bass, "velocity", 10)

-- Change direction of chord track
Track.setDirection(chords, "random")

-- Mute a step
Step.setActive(Track.getStep(bass, 10), false)

-- Stop playback (sends all-notes-off)
local offEvents = Engine.stop(engine)

-- Resume
Engine.start(engine)

-- Full reset (rewinds all tracks to step 1, ignores loop points)
Engine.reset(engine)
```

---

## 6. Grid controller integration patterns

These examples show how Grid controller inputs (encoders, keys, buttons) map to sequencer API calls. On Grid, your Lua code runs in event callbacks triggered by hardware interactions.

### 6.1 Encoder: BPM control

```lua
-- Called when the jog wheel is turned
-- delta = +1 (clockwise) or -1 (counter-clockwise)
function onEncoderBpm(delta)
    local currentBpm = engine.bpm
    local newBpm = Utils.clamp(currentBpm + delta, 20, 300)
    Engine.setBpm(engine, newBpm)
end
```

### 6.2 Encoder: step pitch editing

```lua
-- Edit the pitch of the currently selected step
-- selectedTrack, selectedStep are state variables managed by your UI
function onEncoderPitch(delta)
    local track = Engine.getTrack(engine, selectedTrack)
    local step = Track.getStep(track, selectedStep)
    local currentPitch = Step.getPitch(step)
    Step.setPitch(step, Utils.clamp(currentPitch + delta, 0, 127))
end
```

### 6.3 Encoder: parameter cycling

```lua
-- A single encoder that edits whichever parameter is currently focused.
-- focusedParam is cycled by a button press (see 6.5 below).

local PARAMS = { "pitch", "velocity", "duration", "gate", "ratchet" }
local PARAM_DELTAS = { pitch = 1, velocity = 5, duration = 1, gate = 1, ratchet = 1 }

function onEncoderParam(delta)
    local track = Engine.getTrack(engine, selectedTrack)
    local step = Track.getStep(track, selectedStep)
    local param = PARAMS[focusedParamIndex]
    local d = PARAM_DELTAS[param] * delta

    if param == "pitch" then
        Step.setPitch(step, Step.getPitch(step) + d)
    elseif param == "velocity" then
        Step.setVelocity(step, Step.getVelocity(step) + d)
    elseif param == "duration" then
        Step.setDuration(step, Step.getDuration(step) + d)
    elseif param == "gate" then
        Step.setGate(step, Step.getGate(step) + d)
    elseif param == "ratchet" then
        Step.setRatchet(step, Step.getRatchet(step) + d)
    end
end
```

### 6.4 Keys: step selection (8 keys = 8 visible steps)

```lua
-- VSN1 has 8 key switches. Map them to steps within the visible page.
-- pageOffset tracks which page of 8 steps is currently displayed.

local pageOffset = 0   -- 0 = steps 1–8, 1 = steps 9–16, etc.

function onKeyPress(keyIndex)
    -- keyIndex is 1–8
    selectedStep = pageOffset * 8 + keyIndex
end

-- Scroll pages with jog wheel when in pattern view
function onEncoderPage(delta)
    local track = Engine.getTrack(engine, selectedTrack)
    local maxPage = math.ceil(Track.getStepCount(track) / 8) - 1
    pageOffset = Utils.clamp(pageOffset + delta, 0, maxPage)
end
```

### 6.5 Button: cycle focused parameter

```lua
function onParamButton()
    focusedParamIndex = (focusedParamIndex % #PARAMS) + 1
end
```

### 6.6 Button: toggle step active/mute

```lua
function onMuteButton()
    local track = Engine.getTrack(engine, selectedTrack)
    local step = Track.getStep(track, selectedStep)
    Step.setActive(step, not Step.getActive(step))
end
```

### 6.7 Button: cycle direction mode

```lua
local DIRECTIONS = { "forward", "reverse", "pingpong", "random", "brownian" }
local directionIndex = 1

function onDirectionButton()
    directionIndex = (directionIndex % #DIRECTIONS) + 1
    local track = Engine.getTrack(engine, selectedTrack)
    Track.setDirection(track, DIRECTIONS[directionIndex])
end
```

### 6.8 Button: transport controls

```lua
function onPlayButton()
    if engine.running then
        Engine.stop(engine)    -- returns NOTE_OFF events — emit them
    else
        Engine.start(engine)
    end
end

function onResetButton()
    local offEvents = Engine.reset(engine)
    -- Emit all NOTE_OFF events to avoid hanging notes
    for _, event in ipairs(offEvents) do
        emitNoteOff(event.pitch, event.channel)
    end
end
```

### 6.9 USB MIDI clock + transport integration (device mode)

For the Grid sequencer as a USB MIDI device, treat incoming MIDI realtime messages as transport/clock authority when external sync is enabled.

```lua
-- MIDI realtime bytes:
-- 0xF8 Clock, 0xFA Start, 0xFB Continue, 0xFC Stop

settings.clockSource = "usb"         -- "internal" | "usb"
settings.runMode = "transport"       -- "free" | "transport"
settings.onStart = "resetAndRun"     -- "run" | "resetAndRun"
settings.onStop = "stopAndAllNotesOff" -- "pause" | "stopAndAllNotesOff"
settings.onContinue = "run"          -- "run" | "resetAndRun"
settings.resetMode = "immediate"     -- "immediate" | "nextPulse"
settings.clockLoss = "stopAndAllNotesOff" -- "hold" | "stopAndAllNotesOff" | "fallbackInternal"

function onMidiRealtime(byte)
    if byte == 0xF8 then
        -- external clock tick: drive engine pulse scheduler
        -- (host integration layer decides whether to tick immediately or phase-align)
    elseif byte == 0xFA then
        -- MIDI Start
        if settings.onStart == "resetAndRun" then
            local offEvents = Engine.reset(engine)
            emitOffEvents(offEvents)
        else
            Engine.start(engine)
        end
    elseif byte == 0xFB then
        -- MIDI Continue
        Engine.start(engine)
    elseif byte == 0xFC then
        -- MIDI Stop
        local offEvents = Engine.stop(engine)
        emitOffEvents(offEvents)
    end
end
```

This plan intentionally targets USB MIDI sync only (no CV/gate or analog trigger inputs).

### 6.10 Encoder: scale and root selection

```lua
local SCALE_NAMES = {
    "chromatic", "major", "naturalMinor", "harmonicMinor", "melodicMinor",
    "dorian", "phrygian", "lydian", "mixolydian", "locrian",
    "majorPentatonic", "minorPentatonic", "blues", "wholeTone", "diminished",
    "arabic", "hungarianMinor", "persian", "japanese", "egyptian",
    "spanish", "iwato", "hirajoshi", "inSen", "pelog",
    "prometheus", "neapolitanMajor", "neapolitanMinor", "enigmatic", "leadingWholeTone",
}
local scaleIndex = 1

function onEncoderScale(delta)
    scaleIndex = Utils.clamp(scaleIndex + delta, 1, #SCALE_NAMES)
    Engine.setScale(engine, SCALE_NAMES[scaleIndex], engine.rootNote)
end

function onEncoderRoot(delta)
    local newRoot = (engine.rootNote + delta) % 12
    if engine.scaleName then
        Engine.setScale(engine, engine.scaleName, newRoot)
    end
end
```

### 6.11 Loop point management

```lua
-- Set loop start to the current step
function onSetLoopStart()
    local track = Engine.getTrack(engine, selectedTrack)
    Track.setLoopStart(track, selectedStep)
end

-- Set loop end to the current step
function onSetLoopEnd()
    local track = Engine.getTrack(engine, selectedTrack)
    Track.setLoopEnd(track, selectedStep)
end

-- Loop over a specific pattern
function onLoopPattern(patternIndex)
    local track = Engine.getTrack(engine, selectedTrack)
    Track.setLoopStart(track, Track.patternStartIndex(track, patternIndex))
    Track.setLoopEnd(track, Track.patternEndIndex(track, patternIndex))
end

-- Clear loop (full track playback)
function onClearLoop()
    local track = Engine.getTrack(engine, selectedTrack)
    Track.clearLoopStart(track)
    Track.clearLoopEnd(track)
end
```

### 6.12 Snapshot save/load

```lua
local SNAPSHOT_DIR = "snapshots/"
local currentSlot = 1

function onSaveSnapshot()
    local path = SNAPSHOT_DIR .. "slot_" .. currentSlot .. ".lua"
    Snapshot.saveToFile(engine, path)
end

function onLoadSnapshot()
    local path = SNAPSHOT_DIR .. "slot_" .. currentSlot .. ".lua"
    -- Stop and flush before loading
    local offEvents = Engine.stop(engine)
    for _, event in ipairs(offEvents) do
        emitNoteOff(event.pitch, event.channel)
    end

    engine = Snapshot.loadFromFile(path)
    Engine.start(engine)
end

function onEncoderSlot(delta)
    currentSlot = Utils.clamp(currentSlot + delta, 1, 16)
end
```

### 6.13 Live performance: jitter and randomize

```lua
-- One-shot: humanize velocities across current track
function onHumanizeButton()
    local track = Engine.getTrack(engine, selectedTrack)
    MathOps.jitter(track, "velocity", 12)
end

-- One-shot: randomize ratchet pattern
function onRandomRatchetButton()
    local track = Engine.getTrack(engine, selectedTrack)
    MathOps.randomize(track, "ratchet", 1, 3)
end

-- Transpose the current track up/down via encoder
function onEncoderTranspose(delta)
    local track = Engine.getTrack(engine, selectedTrack)
    MathOps.transpose(track, delta)  -- +1/-1 semitone per click
end
```

---

## 7. Complete Grid controller example

This ties everything together into a single controller module that could run on a Grid VSN1.

```lua
-- grid_controller.lua
-- Complete controller mapping for Grid VSN1 (1 jog wheel, 8 keys, 4 buttons)
--
-- Layout:
--   JOG WHEEL: context-dependent encoder (BPM / pitch / param / page scroll)
--   KEYS 1–8:  step selection (mapped to current page of 8 steps)
--   BUTTON 1:  play / stop toggle
--   BUTTON 2:  reset (rewind all tracks to step 1)
--   BUTTON 3:  cycle focused parameter (pitch → vel → dur → gate → ratchet)
--   BUTTON 4:  cycle screen (pattern → overview → step edit → track config)

local Engine   = require("sequencer/engine")
local Track    = require("sequencer/track")
local Step     = require("sequencer/step")
local MathOps  = require("sequencer/mathops")
local Snapshot = require("sequencer/snapshot")
local Utils    = require("utils")

-- ── State ──────────────────────────────────────────────────────────────────

local engine          = nil   -- set during init
local selectedTrack   = 1
local selectedStep    = 1
local pageOffset      = 0
local focusedParamIdx = 1
local screenIndex     = 1

local PARAMS      = { "pitch", "velocity", "duration", "gate", "ratchet" }
local PARAM_DELTA = { pitch = 1, velocity = 5, duration = 1, gate = 1, ratchet = 1 }
local DIRECTIONS  = { "forward", "reverse", "pingpong", "random", "brownian" }
local SCREENS     = { "pattern", "overview", "stepedit", "trackconfig" }

-- ── Init ───────────────────────────────────────────────────────────────────

local function init()
    engine = Engine.new(120, 4, 2, 0)

    -- Track 1: 16-step bass line (2 patterns × 8 steps)
    local bass = Engine.getTrack(engine, 1)
    Track.setMidiChannel(bass, 1)
    Track.addPattern(bass, 8)
    Track.addPattern(bass, 8)

    -- Populate with a default C minor pentatonic bass line
    local pitches = { 48, 51, 53, 55, 58, 55, 53, 48,    -- pattern A
                      48, 48, 55, 53, 51, 53, 48, 48 }   -- pattern B
    local gates   = {  3,  3,  3,  3,  3,  2,  3,  0,
                       2,  1,  3,  2,  1,  3,  2,  0 }
    for i = 1, 16 do
        Track.setStep(bass, i, Step.new(pitches[i], 100, 4, gates[i]))
    end

    -- Loop over pattern B
    Track.setLoopStart(bass, Track.patternStartIndex(bass, 2))
    Track.setLoopEnd(bass, Track.patternEndIndex(bass, 2))

    -- Track 2: 4-step chord pad at half speed
    local chords = Engine.getTrack(engine, 2)
    Track.setMidiChannel(chords, 2)
    Track.setClockDiv(chords, 2)
    Track.setDirection(chords, "pingpong")
    Track.addPattern(chords, 4)
    Track.setStep(chords, 1, Step.new(60, 80, 4, 3))
    Track.setStep(chords, 2, Step.new(63, 75, 4, 3))
    Track.setStep(chords, 3, Step.new(67, 80, 4, 3))
    Track.setStep(chords, 4, Step.new(70, 70, 4, 2))

    -- Global settings
    Engine.setSwing(engine, 56)
    Engine.setScale(engine, "minorPentatonic", 0)
end

-- ── Encoder handler ────────────────────────────────────────────────────────

local function onEncoder(delta)
    local screen = SCREENS[screenIndex]

    if screen == "pattern" then
        -- Scroll through pages of 8 steps
        local track = Engine.getTrack(engine, selectedTrack)
        local maxPage = math.ceil(Track.getStepCount(track) / 8) - 1
        pageOffset = Utils.clamp(pageOffset + delta, 0, maxPage)

    elseif screen == "stepedit" then
        -- Edit the focused parameter on the selected step
        local track = Engine.getTrack(engine, selectedTrack)
        local step = Track.getStep(track, selectedStep)
        local param = PARAMS[focusedParamIdx]
        local d = PARAM_DELTA[param] * delta

        if param == "pitch" then
            Step.setPitch(step, Step.getPitch(step) + d)
        elseif param == "velocity" then
            Step.setVelocity(step, Step.getVelocity(step) + d)
        elseif param == "duration" then
            Step.setDuration(step, Step.getDuration(step) + d)
        elseif param == "gate" then
            Step.setGate(step, Step.getGate(step) + d)
        elseif param == "ratchet" then
            Step.setRatchet(step, Step.getRatchet(step) + d)
        end

    elseif screen == "trackconfig" then
        -- Adjust BPM
        Engine.setBpm(engine, Utils.clamp(engine.bpm + delta, 20, 300))

    elseif screen == "overview" then
        -- Switch selected track
        selectedTrack = Utils.clamp(selectedTrack + delta, 1, engine.trackCount)
        pageOffset = 0
        selectedStep = 1
    end
end

-- ── Key handler (keys 1–8) ─────────────────────────────────────────────────

local function onKey(keyIndex)
    -- Map key 1–8 to flat step index based on current page
    selectedStep = pageOffset * 8 + keyIndex

    -- Validate the step exists
    local track = Engine.getTrack(engine, selectedTrack)
    if selectedStep > Track.getStepCount(track) then
        selectedStep = Track.getStepCount(track)
    end
end

-- ── Button handlers ────────────────────────────────────────────────────────

local function onButton1()  -- Play / Stop
    if engine.running then
        local offEvents = Engine.stop(engine)
        -- emit NOTE_OFF for each event in offEvents
        return offEvents
    else
        Engine.start(engine)
        return {}
    end
end

local function onButton2()  -- Reset
    local offEvents = Engine.reset(engine)
    pageOffset = 0
    selectedStep = 1
    -- emit NOTE_OFF for each event in offEvents
    return offEvents
end

local function onButton3()  -- Cycle parameter focus
    focusedParamIdx = (focusedParamIdx % #PARAMS) + 1
end

local function onButton4()  -- Cycle screen
    screenIndex = (screenIndex % #SCREENS) + 1
end

-- ── Timer tick ─────────────────────────────────────────────────────────────

local function onTick()
    local events = Engine.tick(engine)
    -- Each event: { type="NOTE_ON"|"NOTE_OFF", pitch=N, velocity=N, channel=N }
    return events
end

-- ── Exported interface ─────────────────────────────────────────────────────

return {
    init     = init,
    onEncoder = onEncoder,
    onKey    = onKey,
    onButton1 = onButton1,
    onButton2 = onButton2,
    onButton3 = onButton3,
    onButton4 = onButton4,
    onTick   = onTick,
}
```

---

## 8. Signal flow diagrams

### 8.1 Engine tick — what happens on each pulse

```
                          Engine.tick(engine)
                                 │
                    ┌────────────┴────────────┐
                    │  engine.running == false? │
                    │  YES → return {}          │
                    └────────────┬─────────────┘
                                 │ NO
                    ┌────────────┴────────────┐
                    │  Apply swing hold?       │
                    │  (Performance module)    │
                    │  YES → return {} (delay) │
                    └────────────┬─────────────┘
                                 │ NO (pulse fires)
                                 │
              ┌──────────────────┼──────────────────┐
              ▼                  ▼                   ▼
         Track 1            Track 2             Track N
              │                  │                   │
     ┌────────┴────────┐  ┌─────┴──────┐      ┌─────┴──────┐
     │ Clock div/mult  │  │ Clock      │      │ Clock      │
     │ accumulator     │  │ accumulator│      │ accumulator│
     │ check           │  │ check      │      │ check      │
     └────────┬────────┘  └─────┬──────┘      └─────┴──────┘
              │                  │                   │
     ┌────────┴────────┐        │                   │
     │ Track.advance() │        │                   │
     │ → get current   │        ...                ...
     │   step          │
     │ → check pulse   │
     │   within step   │
     │ → getPulseEvent │
     │   (ratchet      │
     │    subdivisions)│
     └────────┬────────┘
              │
     ┌────────┴────────────────────┐
     │ Event type?                 │
     │                             │
     │ NOTE_ON:                    │
     │   pitch = resolvePitch(     │
     │     step, scaleTable, root) │
     │   → quantize to scale      │
     │   → emit {NOTE_ON, pitch,   │
     │           velocity, channel}│
     │                             │
     │ NOTE_OFF:                   │
     │   → emit {NOTE_OFF, pitch,  │
     │           channel}          │
     │                             │
     │ nil:                        │
     │   → no event                │
     └────────────────────────────-┘
              │
              ▼
      Collect all events from all tracks
              │
              ▼
      Return events array to caller
```

### 8.2 Grid controller event flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                         GRID HARDWARE                              │
│                                                                     │
│  ┌─────────┐  ┌──────────┐  ┌────────────┐  ┌──────────────────┐  │
│  │Jog Wheel│  │ 8 Keys   │  │ 4 Buttons  │  │  Timer (single)  │  │
│  │ (delta) │  │ (1–8)    │  │ (press)    │  │  (pulse interval)│  │
│  └────┬────┘  └────┬─────┘  └─────┬──────┘  └────────┬─────────┘  │
│       │            │              │                   │            │
└───────┼────────────┼──────────────┼───────────────────┼────────────┘
        │            │              │                   │
        ▼            ▼              ▼                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       CONTROLLER LUA CODE                          │
│                                                                     │
│  onEncoder(delta) ──┐                                              │
│  onKey(keyIndex) ───┤                                              │
│  onButton1–4() ─────┤──▶ Sequencer API calls                      │
│  onTick() ──────────┘    (Engine / Track / Step / MathOps)         │
│                              │                                      │
│                              ▼                                      │
│                     ┌────────────────┐     ┌────────────────┐      │
│                     │  Engine state  │────▶│  Screen render  │      │
│                     │  (tracks,      │     │  (Pattern /     │      │
│                     │   steps,       │     │   Overview /    │      │
│                     │   cursor,      │     │   StepEdit /    │      │
│                     │   loop points) │     │   TrackConfig)  │      │
│                     └───────┬────────┘     └────────────────┘      │
│                             │                                       │
│                             ▼                                       │
│                     ┌────────────────┐                              │
│                     │  MIDI events   │                              │
│                     │  NOTE_ON       │                              │
│                     │  NOTE_OFF      │                              │
│                     └───────┬────────┘                              │
│                             │                                       │
└─────────────────────────────┼───────────────────────────────────────┘
                              │
                              ▼
                     ┌────────────────┐
                     │  MIDI OUT      │
                     │  (to Ableton / │
                     │   synth /      │
                     │   drum machine)│
                     └────────────────┘
```

### 8.3 Screen navigation state machine

```
                    Button 4 (cycle)
            ┌───────────────────────────────┐
            │                               │
            ▼                               │
     ┌─────────────┐  Btn4  ┌───────────┐  Btn4  ┌──────────┐  Btn4  ┌─────────────┐
     │   PATTERN   │──────▶│  OVERVIEW  │──────▶│ STEP EDIT │──────▶│TRACK CONFIG │──┐
     │             │       │            │       │           │       │             │  │
     │ Encoder:    │       │ Encoder:   │       │ Encoder:  │       │ Encoder:    │  │
     │  page scroll│       │  track sel │       │  edit     │       │  BPM adj    │  │
     │ Keys:       │       │ Keys:      │       │  focused  │       │ Keys:       │  │
     │  step select│       │  step sel  │       │  param    │       │  step sel   │  │
     │ Btn3:       │       │ Btn3:      │       │ Btn3:     │       │ Btn3:       │  │
     │  param focus│       │  param foc │       │  cycle    │       │  direction  │  │
     └─────────────┘       └───────────┘       │  param    │       │  cycle      │  │
            ▲                                   └──────────┘       └─────────────┘  │
            │                                                                       │
            └───────────────────────────────────────────────────────────────────────┘
                                         Btn4 (wraps around)
```

### 8.4 Step lifecycle within a pulse window

```
Step: pitch=60, velocity=100, duration=4, gate=3, ratchet=2

Pulse:     0        1        2        3
           │        │        │        │
           ▼        ▼        ▼        ▼
         ┌─────────────────────────────────┐
Duration │  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │  4 pulses total
         └─────────────────────────────────┘

Gate     ┌──────────────────────────┐
(3 pls)  │  ████████████████████████│          3 pulses of gate
         └──────────────────────────┘

Ratchet  ┌───────────┐  ┌───────────┐
(2 hits) │  NOTE_ON 1 │  │ NOTE_ON 2 │          gate÷ratchet = 1.5 pulses each
         └─────┬──────┘  └─────┬─────┘
               │               │
            NOTE_OFF         NOTE_OFF

Pulse events:
  pulse 0 → NOTE_ON   (ratchet hit 1 starts)
  pulse 1 → NOTE_OFF  (ratchet hit 1 ends, before hit 2)
            NOTE_ON    (ratchet hit 2 starts — simultaneous, ON wins)
  pulse 2 → NOTE_OFF  (ratchet hit 2 ends)
  pulse 3 → nil       (duration continues, gate finished, silence)
```

---

## Appendix: scale intervals quick reference

```
Scale               Intervals (semitones from root)
────────────────    ──────────────────────────────────
chromatic           0 1 2 3 4 5 6 7 8 9 10 11
major               0 2 4 5 7 9 11
naturalMinor        0 2 3 5 7 8 10
harmonicMinor       0 2 3 5 7 8 11
melodicMinor        0 2 3 5 7 9 11
dorian              0 2 3 5 7 9 10
phrygian            0 1 3 5 7 8 10
lydian              0 2 4 6 7 9 11
mixolydian          0 2 4 5 7 9 10
locrian             0 1 3 5 6 8 10
majorPentatonic     0 2 4 7 9
minorPentatonic     0 3 5 7 10
blues               0 3 5 6 7 10
wholeTone           0 2 4 6 8 10
diminished          0 2 3 5 6 8 9 11
arabic              0 1 4 5 7 8 11
hungarianMinor      0 2 3 6 7 8 11
persian             0 1 4 5 6 8 11
japanese            0 1 5 7 8
egyptian            0 2 5 7 10
spanish             0 1 3 4 5 6 8 10
iwato               0 1 5 6 10
hirajoshi           0 2 3 7 8
inSen               0 1 5 7 10
pelog               0 1 3 7 8
prometheus          0 2 4 6 9 10
neapolitanMajor     0 1 3 5 7 9 11
neapolitanMinor     0 1 3 5 7 8 11
enigmatic           0 1 4 6 8 10 11
leadingWholeTone    0 2 4 6 8 10 11
```
