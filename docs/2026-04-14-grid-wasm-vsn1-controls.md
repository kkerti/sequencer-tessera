# 2026-04-14 Grid WASM VSN1 Controls

## Purpose

Extend `grid-wasm/index.html` to simulate VSN1 physical controls for screen testing:

- Keyswitches: indexes `0..7`
- Endless encoder: index `8`
- Small buttons: indexes `9..12`

All controls are rendered vertically under the canvas: encoder row, small-button row, then 2x4 keyswitch grid.

## Lua variables injected by the web page

Before every `loadScript(init, loop)` call, the web page prepends these globals into `init`:

- `sliderValue` (`0..255`) - compatibility value for existing screens
- `uiEncoderIndex` (`8`)
- `uiEncoderDelta` (`-1|0|1`) - relative encoder step for current event
- `uiEncoderTicks` (integer) - accumulated encoder movement since page load
- `uiLastEventIndex` (`-1` if none, else `0..12`)
- `uiLastEventDelta` (`-1|0|1`)
- `uiControlDown` (table indexed `0..12`) - held state (`1` down, `0` up)
- `uiControlPressed` (table indexed `0..12`) - edge flag for this event

Example (Lua side):

```lua
if uiEncoderDelta ~= 0 then
  -- relative edit (+1/-1)
end

if uiControlPressed[9] == 1 then
  -- small button 9 was pressed
end

if uiControlDown[0] == 1 then
  -- keyswitch 0 is currently held
end
```

## Event lifecycle

- Encoder input is HTML `input[type=number]` and emits one relative step (`+1` or `-1`) per value change.
- Buttons are momentary (`pointerdown` sets `down+pressed`; `pointerup/cancel/leave` only clears `down`).
- To avoid double-trigger behavior, release does not dispatch a second `loadScript` event.
- `uiControlPressed` and `uiEncoderDelta` are transient and are cleared immediately after each `loadScript` call.
- `uiControlDown` and `uiEncoderTicks` persist until changed by user input.

## Compatibility note

Existing screen scripts that only read `sliderValue` continue to work unchanged.
