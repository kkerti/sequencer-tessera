# 2026-04-11 Screen UI Session 2

## What was done

Built and tested all 4 screen designs for the Grid VSN1 LCD (320x240):

### 1. Pattern Screen (`screens/pattern.lua`) — TESTED OK
- Piano-roll style: compact rectangular note blocks at pitch height
- Auto-scaling pitch range based on visible steps
- Features: velocity brightness, ratchet dots (yellow), rest/skip/mute markers
- Loop markers (orange vertical lines), scrollbar, playback cursor
- Slider scrolls through steps (8 visible at a time)
- Init: 616b, Loop: 5221b

### 2. Overview Screen (`screens/overview.lua`) — TESTED OK
- Bird's eye view of all 4 tracks as horizontal lanes
- Mini piano-roll blocks per track, pitch-scaled per track
- Per-track labels: name, channel, direction, clock div/mult, mute
- Loop markers, playback cursors, selected track highlight
- Slider selects active track
- Init: 845b, Loop: 3812b

### 3. Step Edit Screen (`screens/stepedit.lua`) — TESTED OK
- Single-step parameter editor: PITCH, VEL, DUR, GATE, RATCH, ACTIVE
- Horizontal bars with value labels (note name for pitch, discrete blocks for ratchet, toggle for active)
- Piano keyboard visualization at bottom showing current note
- Slider selects active parameter
- Init: 388b, Loop: 4135b

### 4. Track Config Screen (`screens/trackconfig.lua`) — TESTED OK
- Per-track settings: direction, clock div/mult, loop start/end, MIDI channel, mute
- Track selector tabs at top (TRK1-4)
- Discrete blocks for direction (5 modes), toggle for mute
- Loop region indicator line
- Slider selects active parameter
- Init: 439b, Loop: 3759b

## All init sections well under 2KB limit

## Updated files
- `screens/manifest.json` — now lists all 4 screens
- `screens/pattern.lua` — piano-roll v2 (verified working)
- `screens/overview.lua` — new
- `screens/stepedit.lua` — new
- `screens/trackconfig.lua` — new

## Next steps
- Connect screens to real sequencer engine data (replace mock data with engine state)
- Implement encoder-driven parameter editing (currently slider is read-only display)
- Add screen switching mechanism (e.g., button to cycle Overview → Pattern → StepEdit → TrackConfig)
- Polish: add pattern boundary markers to pattern screen, refine piano keyboard in step edit
- Test on actual Grid hardware via WASM → device code path
