-- 2026-04-11 Grid Screen UI Setup

## What was done

Set up a local test environment for designing Grid VSN1 LCD screens (320x240px) using the grid-fw WASM build. Built a working Pattern screen prototype.

## Key discovery: init script size limit

The WASM `loadScript` function has a **~2048 byte limit on the init section**. The loop section has no practical limit (tested to 4000+ bytes). All heavy drawing code must live in the loop.

## Drawing API confirmed

Global functions in the WASM test environment (screen_index is always `0`):

| Function | Signature | Purpose |
|---|---|---|
| `ggdrf` | `(si, x1, y1, x2, y2, {r,g,b})` | Filled rectangle |
| `ggdr` | `(si, x1, y1, x2, y2, {r,g,b})` | Rectangle outline |
| `ggdrrf` | `(si, x1, y1, x2, y2, radius, {r,g,b})` | Filled rounded rect |
| `ggdrr` | `(si, x1, y1, x2, y2, radius, {r,g,b})` | Rounded rect outline |
| `ggdft` | `(si, text, x, y, size, {r,g,b})` | Fast text (bitmap) |
| `ggdt` | `(si, text, x, y, size, {r,g,b})` | Text (vector) |
| `ggdl` | `(si, x1, y1, x2, y2, {r,g,b})` | Line |
| `ggdpx` | `(si, x, y, {r,g,b})` | Pixel |
| `ggdaf` | `(si, x1, y1, x2, y2, {r,g,b})` | Area fill |
| `ggdpo` | `(si, {xs}, {ys}, {r,g,b})` | Polygon outline |
| `ggdpof` | `(si, {xs}, {ys}, {r,g,b})` | Filled polygon |
| `ggdsw` | `(si)` | Swap buffer to screen |
| `ggdd` | `(si, n)` | Demo pattern |

On actual device, these are LCD element methods with `ld` prefix (`self:ldrf(...)` etc.).

## File structure

```
grid-wasm/
  index.html          -- modified test page (file loader, dark theme, slider display)
  index.js            -- emscripten glue (downloaded, gitignored)
  index.wasm          -- WASM binary (downloaded, gitignored)
  screenshot.mjs      -- Playwright script to screenshot a screen .lua file
  package.json        -- npm package for playwright dependency
screens/
  pattern.lua         -- Pattern screen prototype (working)
  manifest.json       -- file list for the browser file loader
```

## Screen file format

Lua files use section markers. Init must be under 2KB.

```lua
-- INIT START
-- variables, data, short helper setup
-- INIT END

-- LOOP START
-- all drawing code (runs every frame at ~30fps)
-- LOOP END
```

## How to test

### Manual browser testing
```bash
# From project root:
python3 -m http.server 8080
# Open http://localhost:8080/grid-wasm/index.html
# Select screen file from dropdown, or paste code into textareas
# Use slider to simulate encoder input (0-255 as sliderValue)
```

### Automated screenshots
```bash
# From project root:
python3 -m http.server 8080 &
cd grid-wasm && node screenshot.mjs ../screens/pattern.lua 128 pattern.png
```

## Pattern screen design

Shows 8 steps at a time from a track's step list. Layout:

- **Header** (24px): TRK name, direction, BPM, swing%, scale, step position
- **Step columns** (8 x 38px): pitch bar (height=pitch), velocity highlight, pitch label
- **Gate bar** (8px): green fill proportional to gate/duration ratio
- **Ratchet dots**: yellow squares for ratchet count > 1
- **Loop markers**: orange vertical bars at loop start/end
- **Cursor**: white bar under the playback position
- **Footer** (20px): selected step detail (pitch, velocity, duration, gate, ratchet, mute)
- **Scrollbar**: right edge, when total steps > 8

## Next steps

- Build remaining screens: Overview, Step Edit, Track Config, Performance
- Define screen manager / navigation model for encoder-driven switching
- Connect to actual sequencer engine state instead of mock data
- Set up Playwright automation for visual regression testing
