# 2026-04-28 — Grid VSN1 screen + button reference

Sources (all under `https://docs.intech.studio/`):
- `/wiki/events/draw/draw-basic`
- `/wiki/events/draw/shapes`
- `/wiki/events/draw/text`
- `/wiki/events/ui-events/button-event`
- `/category/ui-events` (index of all UI events)

This is a snippet reference for building the on-device UI on the Grid module's **VSN1 screen** (320 × 240 px, up to 20 fps refresh). Distilled from the Intech Studio docs as of April 2026.

---

## 1. Drawing model

### Buffered draw + manual swap

Every `draw_*` call writes to a background buffer. **Nothing appears on the screen until you call:**

```lua
self:draw_swap()
```

`draw_swap()` is what costs frame time. Doing it once per frame after batching all draws is critical — the docs explicitly warn that high-frequency redraws cause buffering lag, which matches our `AGENTS.md` note ("simultaneous high-frequency updates cause buffering lag — batch screen redraws"). One `draw_swap` per "render frame" in our timer; never per-shape.

### `self:` is mandatory

Every draw call must be `self:draw_xxx(...)` so the runtime knows which screen element to target. Forgetting `self:` silently no-ops. This is set up for future multi-screen support.

### Coordinates and colours

- Coordinates are pixel-based, integer, top-left origin: `x ∈ [0, 319]`, `y ∈ [0, 239]`.
- Colours are 8-bit RGB Lua tables: `{r, g, b}` with each channel `0–255`. Examples: red `{255,0,0}`, white `{255,255,255}`, black `{0,0,0}`, orange `{249,150,0}`.

### Clearing

There is **no `draw_clear`**. To clear before redrawing, paint a filled rectangle covering the dirty area:

```lua
self:draw_rectangle_filled(0, 0, 320, 240, {0, 0, 0})  -- full-screen wipe
```

For partial updates (which we want for performance) clear only the region you'll redraw.

---

## 2. Shape API

All draw shapes; outline + filled variants; final argument always `{r, g, b}`.

| Function | Signature | Notes |
|---|---|---|
| Pixel | `self:draw_pixel(x, y, {r,g,b})` | Single dot. |
| Line | `self:draw_line(x1, y1, x2, y2, {r,g,b})` | Straight segment, two endpoints. |
| Rectangle outline | `self:draw_rectangle(x1, y1, x2, y2, {r,g,b})` | **Two-corner** signature, not x/y/w/h. |
| Rectangle filled | `self:draw_rectangle_filled(x1, y1, x2, y2, {r,g,b})` | Two-corner. The Draw Basics example also passes width/height — docs are inconsistent; treat the official signature as two corners and verify on device. |
| Rounded rectangle | `self:draw_rectangle_rounded(x1, y1, x2, y2, radius, {r,g,b})` | `radius` 0–30 px. |
| Rounded filled | `self:draw_rectangle_rounded_filled(x1, y1, x2, y2, radius, {r,g,b})` | Same. |
| Polygon outline | `self:draw_polygon({x1,x2,…}, {y1,y2,…}, {r,g,b})` | Two parallel coord arrays. |
| Polygon filled | `self:draw_polygon_filled({x1,x2,…}, {y1,y2,…}, {r,g,b})` | Same. Closes the polygon automatically. |

Polygon example (filled triangle):

```lua
local x = {30, 50, 10}
local y = {10, 40, 40}
self:draw_polygon_filled(x, y, {255, 255, 0})
```

Polygon example (filled star):

```lua
local x = {40, 48, 60, 50, 52, 40, 28, 30, 20, 32}
local y = {20, 35, 35, 45, 60, 50, 60, 45, 35, 35}
self:draw_polygon_filled(x, y, {255, 215, 0})
```

---

## 3. Text API

Two functions, both render a string at `(x, y)` with a numeric font size in pixels and an RGB colour:

```lua
self:draw_text_fast('text', x, y, size, {r, g, b})  -- recommended for value updates
self:draw_text('text',      x, y, size, {r, g, b})  -- higher-quality variant
```

- The docs describe `draw_text_fast` as the right call for "real-time" updates (BPM display, encoder values, etc.) — it's the cheaper renderer.
- `draw_text` is presumably the antialiased / higher-quality variant; the docs do not specify the trade-off explicitly. Default to `draw_text_fast` for our sequencer UI.
- The text-page docs once write `lcd:draw_text_fast(...)` (with a `lcd:` prefix) — that appears to be a documentation typo. **Use `self:` consistently** as everywhere else in the Draw section.

**Centring text**: the docs do not expose a "measure text width" function. Centring requires either fixing a known character width per font size empirically or pre-rendering to a known box.

---

## 4. Render-loop pattern (for our UI)

Distilled idiom for our sequencer's screen update — call once per UI tick (e.g. inside the same timer that drives the engine, gated to ~50 ms / 20 fps):

```lua
-- Clear only the regions we'll redraw, then redraw, then swap.
self:draw_rectangle_filled(0, 0, 320, 22,  {0, 0, 0})       -- header strip
self:draw_text_fast("BPM "..bpm,        4,  2,  18, {255,255,255})
self:draw_text_fast("STEP "..stepIdx, 120,  2,  18, {200,200,200})

-- Track strip
self:draw_rectangle_filled(0, 24, 320, 60, {0,0,0})
for i = 1, 16 do
    local lit = isStepActive(i)
    self:draw_rectangle_filled(
        4 + (i-1)*19, 30,
        4 + (i-1)*19 + 16, 50,
        lit and {249,150,0} or {40,40,40})
end

self:draw_swap()  -- ONE swap per frame
```

Performance rules:
- **Batch all draws between swaps.** One `draw_swap` per frame.
- **Clear only what you redraw.** Full-screen wipes cost; per-region wipes are fine.
- Treat the screen refresh as ≤ 20 fps. Don't try to redraw on every engine pulse.

---

## 5. Button events

The Button Event fires on **press** AND **release**. The event handler runs in the BUTTON block of the Grid module — see `grid_module.lua` for our project's stub.

### Available `self:button_*()` functions

All of these are getter/setter pairs: call with no argument to read, call with an argument to set.

| Function | Shortname | Range / type | Purpose |
|---|---|---|---|
| `self:button_number([n])` | `bnu` | signed int | The element's logical index. On 16-button modules: `0..15`, top-left to bottom-right, row-major. PBF4: `0..11`. |
| `self:button_value([v])` | `bva` | int `0..127` | Current MIDI-style value associated with the button. Default: `127` on press, `0` on release. Multi-step modes spread values evenly. |
| `self:button_min([v])` | `bmi` | int `0..127` | The "released" value. Default `0`. |
| `self:button_max([v])` | `bma` | int `0..127` | The "pressed" value. Default `127`. Set both to `0`/`1` to make a clean boolean. |
| `self:button_mode([m])` | `bmo` | int `0..127` | Step count between min and max. `0` = standard 2-state. `2` = 3-state switch (`0`, `63`, `127`). `3` = 4-state, etc. |
| `self:button_elapsed_time()` | `bel` | (read-only) | Frames since last button trigger. Useful for long-press / double-press detection. |
| `self:button_state()` | `bst` | `0` or `127` | Raw "pressed" / "released" state — **independent of `min`/`max`/`mode` overrides**. Use this when you want the physical state, not the mapped value. |

### Detecting press vs release in the BUTTON handler

The Button Event fires on both edges. To distinguish:

```lua
-- Inside the BUTTON event block
if self:button_state() == 127 then
    -- Press edge
else
    -- Release edge
end
```

`button_state()` is preferable to `button_value()` here because it ignores any `button_min` / `button_max` / `button_mode` configuration the user (or our patch) may have set.

### Long-press / hold detection

`button_elapsed_time()` returns time since the last trigger in **frames** (not ms). On the release edge, that's the held duration. Suggested use for our UI:

```lua
-- On release:
if self:button_state() == 0 then
    local held = self:button_elapsed_time()
    if held > LONG_PRESS_FRAMES then
        -- treat as long-press
    else
        -- short tap
    end
end
```

The exact frame rate is not documented; calibrate empirically. (The docs mention "frames" — likely 1 frame ≈ 5 ms based on the 200 Hz internal control loop, but verify on device.)

### Buttons we'll need for the sequencer UI

Mapping ideas (16-button BU16 layout, indices `0..15`):

| Index | Function (proposal) |
|---|---|
| 0 | START / STOP (`button_state` toggles transport) |
| 1 | RESET (rewind all tracks to step 1) |
| 2 | PANIC (all-notes-off) |
| 3 | TAP TEMPO (use `button_elapsed_time` between taps) |
| 4-7 | Track 1-4 select / mute |
| 8-15 | Pattern slot select within current track |

Encoders / pots (separate event types — see the Encoder Event and Potentiometer Event pages, not covered here) handle continuous editing (BPM, mathops parameters).

### Caveat: the utility button is separate

The hardware utility button does **not** fire Button Events. It uses the Utility Event (see `/wiki/events/system-events/utility-event`). Don't repurpose it.

---

## 6. What's missing from the docs

Worth confirming on hardware before relying on these:
- **Rectangle signature inconsistency**: Draw Basics shows `draw_rectangle_filled(10, 5, 40, 20, ...)` interpreted as `(x, y, w, h)`, while Shapes documents `(x1, y1, x2, y2, ...)`. The Shapes page is more recent / consistent — assume two-corner everywhere and verify.
- **Text metrics**: no API to measure rendered text width or font height. Right-aligning or centring requires empirical sizing per font size.
- **Clipping / scissor regions**: not documented. Assume none — clear and draw within your intended bounds manually.
- **Image / bitmap drawing**: not documented in the Draw section.
- **Frame rate of `button_elapsed_time`**: unit is "frames" but the exact frame period isn't given. Measure on device.
- **Multi-screen handling**: docs hint at future "two screens in one module" support — that's why `self:` matters.

---

## 7. Quick-reference card (for in-code comments)

```lua
-- VSN1 screen: 320 x 240, ≤20 fps. RGB tables {r,g,b}, 0-255.
-- ALL draws into a back buffer; call self:draw_swap() ONCE per frame.

-- Shapes ----------------------------------------------------------------
self:draw_pixel(x, y, c)
self:draw_line(x1, y1, x2, y2, c)
self:draw_rectangle(x1, y1, x2, y2, c)
self:draw_rectangle_filled(x1, y1, x2, y2, c)
self:draw_rectangle_rounded(x1, y1, x2, y2, r, c)        -- r 0-30
self:draw_rectangle_rounded_filled(x1, y1, x2, y2, r, c)
self:draw_polygon({xs}, {ys}, c)
self:draw_polygon_filled({xs}, {ys}, c)

-- Text ------------------------------------------------------------------
self:draw_text_fast(str, x, y, size, c)   -- prefer for live values
self:draw_text(str, x, y, size, c)        -- higher quality, slower

-- Commit ----------------------------------------------------------------
self:draw_swap()

-- Buttons (in BUTTON event handler) -------------------------------------
self:button_state()         -- 127 pressed, 0 released  (raw, ignore min/max)
self:button_value()         -- mapped value through min/max/mode
self:button_number()        -- 0..15 (BU16/EN16) or 0..11 (PBF4)
self:button_elapsed_time()  -- frames since previous trigger
self:button_min(v) / button_max(v) / button_mode(steps)  -- configure
```
