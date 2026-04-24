# MIDI clock sync — external pulse driver

**Status: working on hardware.** User confirmed Ableton-driven playback on the Grid module.

## What changed

`player_lite/player.lua` refactored to make `p.pulseCount` (integer) the source of truth.

- `Player.externalPulse(p, emit)` — new public API. Advances the player by exactly one pulse. Use this when an external clock (e.g. MIDI 0xF8) drives the player.
- `Player.tick(p, emit)` — kept as the internal-clock entry point; now a thin shim that derives the target pulse from `clockFn()` and calls `externalPulse` until caught up. Public behaviour unchanged.
- `Player.start` — also resets `pulseCount` to 0.
- `Player.setBpm` — only meaningful in internal-clock mode; rebases `startMs` against `pulseCount`.
- `clockFn` is now optional in `Player.new` (pass `nil` for external-clock mode).

## Tests

- `tests/player_lite.lua` (new) — covers both modes, transport, loop wrap, NOTE_OFF flush, allNotesOff, setBpm-preserves-position. All pass.
- `tests/player.lua` (legacy full-engine player, unchanged) — still passes.

## On-device wiring

`grid_module.lua` extended with a "MIDI CLOCK SYNC" section showing:

- a replacement INIT block (no `clockFn`, no timer)
- the `self.rtmrx_cb` handler that translates MIDI clock bytes:
  - `0xF8` — count down 24 ppq → `song.pulsesPerBeat` ppq, then call `externalPulse`
  - `0xFA` — Start (rewind to 0)
  - `0xFB` — Continue (resume from current pulse)
  - `0xFC` — Stop (flush all sounding notes)

## Constraints respected

- Grid file size unchanged: largest chunk in `grid/player/` after rebuild is 677 chars (limit 800).
- No new dependencies.
- Works on Lua 5.4 (device) and 5.5 (dev macOS).

## Known caveats

- `song.pulsesPerBeat` must divide 24 evenly (1, 2, 3, 4, 6, 8, 12, 24). All current songs use 4 → ratio 6.
- BPM is set by the master (Ableton); `song.bpm` is ignored in MIDI-sync mode for timing purposes — but match it in Ableton if you want any internal pulse-derived calculations to make sense.
- Do NOT run both `element_timer_start` and the rtmidi clock callback simultaneously.

## Next steps (optional)

- Measure inter-clock interval to derive Ableton's BPM at runtime, and call `Player.setBpm` so any pulse-vs-time ratios stay accurate.
- Add an SPP (Song Position Pointer) handler if jumping mid-song from Ableton matters.
- Mode toggle on a button: switch between internal and external clock without re-uploading.

## Verified deployment recipe

1. Upload `grid/player/*.lua` → `/player/`, `grid/dark_groove/*.lua` → `/dark_groove/` (only when changed).
2. Paste the MIDI-sync INIT block into element 0 init (no `Player.start`, no `element_timer_start`).
3. Paste the `self.rtmrx_cb` handler into the element's rtmidi receive event.
4. In Ableton: enable Sync on the MIDI output going to Grid; press Play.

Both copy-paste blocks live in `grid_module.lua` under the "MIDI CLOCK SYNC" section.
