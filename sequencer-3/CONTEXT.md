# sequencer-3

A simple, live-performance, 16-step, 4-lane MIDI sequencer inspired by Noise
Engineering's Mimetic Digitwolis. The engine is headless; host adapters (Mac,
later Grid VSN1) drive it through one action API.

## Language

### Structure

**lane**:
One of four independent sequences. Holds up to 16 steps, one output semantic,
and one config block.
_Avoid_: track, channel, voice

**step**:
One sequence position in a lane (1..16). A storage slot, not a fixed grid cell.
_Avoid_: cell, slot, position

**dims**:
A lane's step layout: `16x1`, `8x2`, `5x3`, `4x3`, `4x4`. Determines how steps
are navigated in X/Y.
_Avoid_: shape, grid, layout

**matrix navigation**:
Navigating a lane's steps as a 2-D grid: X advances one axis, Y the other, so
playback order is performable.

**mono lane**:
A Note lane plays one note at a time, retriggering. The current model.
_Avoid_: unison, monophonic voice

**generator**:
A routine that fills a lane's steps (e.g. Euclidean, Gamut-style random). Not a
live effect.
_Avoid_: effect, transformer, modifier

### Lane types

**lane type**:
What a lane emits: `Note`, `Mod`, `Trig`, `Gate`, and later `Gamut`.
_Avoid_: output mode, algorithm

**Note lane**:
Melodic lane; emits MIDI notes with per-step pitch, velocity, and length.

**Mod lane**:
Modulation lane; emits MIDI CC.
_Avoid_: CV lane

**Trig lane**:
Binary lane; active steps emit short MIDI note pulses.

**Gate lane**:
Binary lane; active steps hold a MIDI note until the next inactive step.

**Gamut lane**:
A Note lane whose steps are generated (root/spread/range/scale/seed) rather than
hand-entered. Named after Gamut Repetitor.

### Timing

**transport**:
Global timing that produces pulses, a reset, and named subdivisions. Driven by
external MIDI clock or an internal timer.
_Avoid_: clock (when the global layer is meant)

**advance source**:
The event that moves a lane to its next step: a transport tap, an external MIDI
event, or another lane.

**tap**:
A transport subdivision (whole / half / quarter / eighth / sixteenth) usable as
a trigger source. MD2 labels it `Tprt`.

**trigger source**:
A routable source that fires on an event: advance, xAdvance, yAdvance, reset,
random, previous, or shift.

**value source**:
A routable source that carries a value: address, xAddress, or yAddress (and,
later, parameter modulation).

**external source / EXT**:
An incoming MIDI event exposed as a routable source. As a trigger it is a
note-on or a thresholded CC; as a value it is the CC value.

**note-off scheduler**:
The fixed, preallocated list of pending note-offs the engine drains each pulse.

**member channel**:
The per-lane MIDI channel used for MPE per-note expression. One lane = one
member channel.

### Boundary

**Core**:
The pure, headless Lua engine. No drawing, no MIDI, no device knowledge.

**action API**:
The named Core commands both the Lua shell and the future Grid GUI call.

**host adapter**:
Non-core code that moves data in/out. Stdio→MIDI on Mac now; Grid VSN1 later.

**preset / slot**:
A saved full engine state. Lua-chunk format, 24 slots.

## Rejected

**track / pattern / sequence**: seq-2's multi-layer composition model, simplified
away. Lanes only.

**rack / effect chain**: Live per-pulse effects; too much complexity for seq-3.

**step as grid slot**: Steps are sequence positions, not a fixed quantize grid.

**Qtiz lane**: External-CV quantizer; meaningless without CV inputs.
