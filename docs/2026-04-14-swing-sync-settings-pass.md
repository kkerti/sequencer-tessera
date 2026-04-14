## Session notes

- Clarified swing behavior and aligned implementation + tests: swing now applies fractional hold on off-beat pulses (pulse-driven engine model).
- Updated swing-related tests (`tests/performance.lua`, `tests/engine.lua`, `tests/sequences/04_swing_showcase.lua`) to match current playback model.
- Added VSN1 settings screen prototype in `screens/settings.lua` and registered it in `screens/manifest.json`.
- Added USB MIDI focused sync/transport integration guidance to docs (clock source, start/stop/continue/reset/loss policy options).

## Why this direction

- Project target is USB MIDI device sequencing, so sync plan now prioritizes MIDI realtime transport/clock rather than analog CV/gate semantics.
- Swing remains modular in `sequencer/performance.lua` so timing logic can be replaced later without touching track/step/engine structure.

## Next

- Implement runtime settings state that the new settings screen reflects (instead of static mock values).
- Add engine/host APIs for incoming MIDI realtime (`F8`, `FA`, `FB`, `FC`) and clock-loss policy handling.
