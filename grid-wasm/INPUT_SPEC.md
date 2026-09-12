# Grid screen harness — input spec (v1)

The `grid-wasm` demo page simulates a **Grid VSN1** module so screen code can be
tested in the browser. The only channel from JS into the Lua VM is
`loadScript(init, loop)`: `init` runs once, `loop` runs every frame. A control
event (button press/release, encoder turn) is delivered by re-running the script
with a fresh block of globals prepended to `init`.

This file is the **contract** those globals honour. Screen code written against
it keeps working across runs and across page rewrites. The names mirror the real
Grid Lua API (`button_value`, `button_state`) so logic transfers to a device.

## Controls

| index | role              | kind      | value                         |
|-------|-------------------|-----------|-------------------------------|
| 0–7   | keyswitches       | momentary | `0` released / `127` pressed  |
| 8     | endless encoder   | rotary    | accumulated `0..127`          |
| 9–12  | buttons under screen | momentary | `0` released / `127` pressed |

All buttons are **momentary** (Grid default): held = `127`, released = `0`.
The encoder has no press value; it reports an accumulated position and a per-turn
delta. In the harness it is driven by **ENC −** / **ENC +** (one increment each).

## Globals injected before every run

```lua
SCREEN_W = 320            -- screen width  (px)
SCREEN_H = 240            -- screen height (px)
ENCODER  = 8              -- index of the encoder control

grid = {
  -- per-control value, indexed 0..12
  button_value = { [0]=0, ... [12]=0 },   -- 0 / 127 for buttons; position for encoder(8)
  button_state = { [0]=0, ... [12]=0 },   -- 0 = released, 1 = pressed (buttons only)

  encoder       = 8,      -- same as ENCODER, for convenience
  encoder_value = 0,      -- encoder accumulator, clamped 0..127
  encoder_delta = 0,      -- last encoder move: -1, 0, or +1 (reset to 0 on the next event)

  -- most recent control event, so a screen can react to "what just happened"
  event_index = -1,       -- control index of the latest event (-1 if none yet)
  event_value = 0,        -- value that event carried (button 0/127, or encoder position)
}
```

### Notes on timing / edges

- There is no per-frame callback into Lua. Between events the `loop` keeps
  rendering with the **last injected** globals, so values persist until the next
  event. Treat `grid.button_value` / `button_state` as level signals.
- `encoder_delta` is a one-shot: it carries the direction on the run triggered by
  an encoder turn, then is injected as `0` on the next (unrelated) event.
- `event_index` / `event_value` persist (they are not cleared), so they always
  describe the most recent interaction.

## Legacy aliases (sequencer-2 screens)

Kept for backward compatibility; prefer the `grid` table in new code.

```lua
sliderValue        -- 0..255, = encoder_value * 2 (old screens sweep 0..255)
uiControlDown[i]   -- 0/1, = button_state[i]
uiControlPressed[i]
uiControlReleased[i]
uiEncoderDelta     -- = encoder_delta
uiEncoderTicks     -- signed running total of encoder increments
uiLastEventIndex   -- = event_index
uiLastEventDelta
```

## Drawing API (baked into the wasm)

Layer is the first arg (`0`). Colors are `{r,g,b}` 0..255. Screen is 320×240.

| call | effect |
|------|--------|
| `ggdrf(0, x1, y1, x2, y2, {r,g,b})` | filled rectangle (also used full-screen to clear) |
| `ggdl(0, x1, y1, x2, y2, {r,g,b})`  | line |
| `ggdft(0, text, x, y, size, {r,g,b})` | bitmap text (use `size` 8) |
| `ggdt(0, text, x, y, size, {r,g,b})`  | truetype text (scalable) |
| `ggdsw()` | swap/flush — call once at the end of `loop` |
