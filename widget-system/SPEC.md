# Widget system — spec (v1)

A reusable, selective-rendering widget system for **Intech Grid** modules,
written in Lua. Its job is narrow on purpose:

1. **Selective rendering** — only redraw what changed, so the ≤20 fps device
   draw loop stays cheap.
2. **Reusable, self-bounded widgets** — a widget knows its own `x/y/w/h` and
   draws only within those bounds. Bounds are also the handle a host uses to
   decide what a control action targets.

It is a general-purpose primitive, **not** sequencer-specific. `sequencer-3`
(and other projects) `require` it and compose their own widgets on top.

Derived from two field profiles: `Copy of suku_widget_4` (midi-rx fan-out
variant) and `AbletonJS selected track control v1.3` (explicit-`set` variant).
This spec reconciles the two.

---

## 1. Runtime model

Two runtimes, one widget contract.

| | Device (VSN1R) — canonical | grid-wasm harness — preview |
|---|---|---|
| Code loading | `require`-able TEXT bundles, ≤ ~10 KB each | flat script, **no `require`**, ~2 KB init |
| Draw API | `lcd:ldaf / ldft / ldsw` (methods on the control element) | `ggdrf / ggdt / ggdl / ggdsw` (globals, layer 0) |
| Status | real target | best-effort; harness code is outdated/minified |

Widget `render` code never calls either API directly. It calls the **`gfx`**
abstraction (§3), and a backend maps `gfx` onto the runtime. Keep-light rule:
the reusable part is the contract, not the backend.

On device the system lives under the profile's element-255 setup
(`require` the core there) and is driven from the screen element's draw event
(`event 8`).

---

## 2. Files

All under `widget-system/`. Split so a project always requires a small core and
picks only the primitives it needs.

| File | Contents |
|---|---|
| `widget_core.lua` | `Layout` + the base `Widget` contract |
| `widget_std.lua`  | standard primitives: `label`, `toggle`, `range` |
| `gfx_device.lua`  | backend wrapping `lcd:ldaf/ldft/ldsw` (canonical) |
| `gfx_harness.lua` | backend wrapping `ggd*` — **written to contract, untested** |
| `SPEC.md`         | this document |

Project-specific widgets (e.g. seq-3 lanes, the 16-step matrix cell) live in the
consuming project and build on `widget_core` — they are **not** in `widget_std`.

Each bundle is plain TEXT ≤ ~10 KB (the module watchdog reboots on oversized
chunks). No `collectgarbage`, no `package.loaded` manipulation, no
`string.format` (absent from the Grid Lua build).

---

## 3. `gfx` contract

A backend-neutral draw handle. **Four calls only**; add more only when a widget
genuinely needs one.

```
gfx:rect(x, y, w, h, {r,g,b})          -- filled rectangle
gfx:text(str, x, y, size, {r,g,b})     -- text
gfx:line(x1, y1, x2, y2, {r,g,b})      -- line
gfx:swap()                             -- flush/swap buffer (once per drawn frame)
```

- Coordinates are absolute screen pixels (320×240). Colors are `{r,g,b}` 0..255.
- `gfx` is **injected at `Layout:initialize`** and propagated to every widget as
  `self.gfx`. Widgets never reach for a global draw API.
- **Backend mapping:**
  - device: `rect` → `lcd:ldaf(x, y, x+w, y+h, c)` (note: `ldaf` takes
    *corners*, so w/h are converted); `text` → `lcd:ldft`; `swap` → `lcd:ldsw`.
  - harness: `rect` → `ggdrf(0, x, y, x+w, y+h, c)`; `text` → `ggdt`;
    `line` → `ggdl`; `swap` → `ggdsw`.
- LED calls (`glp` / `glc`) are **out of scope** — they are not screen draw and
  stay with the host.

---

## 4. Layout API

```
Layout:new()
Layout:initialize(gfx, cols, rows, x, y, w, h)
Layout:addWidget(cx, cy, widget)   -- places widget in cell (cx,cy); returns widget
Layout:render(frame)               -- draw pass; `frame` is a monotonic counter
```

- `cols` = horizontal cell count, `rows` = vertical cell count. A cell is
  `w/cols` × `h/rows`. (Explicit names — the source profiles used misleading
  `r/c`.)
- **Cell index** is row-major: `index = cy * cols + cx`.
- `addWidget` computes and assigns the widget's **absolute** bounds once:
  `widget.x = self.x + cx*cellW`, `widget.y = self.y + cy*cellH`,
  `widget.w = cellW`, `widget.h = cellH`; and sets `widget.gfx = self.gfx`,
  `widget.parent = self`. No per-frame coordinate recompute.
- No auto-fill of empty cells (the suku `DW_Dummy` fill is dropped). An empty
  cell is simply skipped.

### Recursive nesting

A `Layout` **is** a widget — it exposes `render`, bounds, and a `change` flag —
so a cell may hold a sub-`Layout`. This unifies "screen regions" and grids:

- Multiple top-level regions = several Layouts (as the AbletonJS `cnv1/2/3`).
- The seq-3 4×4 step matrix = one cell holding a 4×4 sub-Layout; each step is a
  leaf widget with its own dirty flag.
- Selective render composes at every level: a dirty leaf redraws alone; a clean
  leaf issues no draw calls.

### Render pass, selective draw, conditional swap

`Layout:render(frame)`:

1. Iterate cells in index order (a cheap flag-check loop — no upward dirty
   propagation).
2. For each cell, consult its `update` descriptor (§5) to decide whether to
   render. Only cells that render issue `gfx` draw calls — this is where the
   perf win lives (draw calls are the expensive part, not the loop).
3. Track whether **anything** drew this frame.
4. Call `gfx:swap()` **only if** something drew (skip the flush on fully-static
   frames). Only the top-level render owns the swap; nested renders draw but do
   not swap.

---

## 5. Widget contract

```
Widget:new(...)                 -- constructor. NO separate init:
                                --   bounds are assigned by Layout:addWidget.
Widget:render(self)             -- draw within self.x/y/w/h via self.gfx
Widget:set(self, ...)           -- OPTIONAL: push new data; marks change=true
Widget:midirx_cb(self, hdr, ev) -- OPTIONAL: reactive MIDI-in hook
```

Fields the system reads/writes:

| field | meaning |
|---|---|
| `update` | update-cadence descriptor (below); default `{mode="dirty"}` |
| `change` | dirty flag; `set` sets it true, `render` clears it |
| `x,y,w,h` | absolute bounds, assigned by `addWidget` |
| `gfx` | injected draw handle |
| `parent` | owning Layout |
| `focusable` | reserved, default **false**. Inert in v1 (no focus system); kept as a zero-cost hook so a project can layer focus later without a contract change |

### Two reactivity paths (both first-class)

- **`set` (explicit push):** the host computes data and calls `widget:set(...)`,
  which stores it and marks `change=true`. Used when data comes from a package
  or app logic (AbletonJS `RT_*` dispatcher → `wg:set`).
- **`midirx_cb` (reactive):** the Layout fans a MIDI-in event out to every
  cell's `midirx_cb`; the widget writes its own state from the raw event. Used
  when MIDI-rx reactivity is available (suku variant).

A widget may implement either, both, or neither (a purely static/animated
widget needs only `render`).

### Update cadence

The `update` descriptor is the widget's declaration of **when** it re-renders —
the core of selective rendering:

| `update` | behavior |
|---|---|
| `{mode="dirty"}` (default) | render only when `change==true` (then clear it). The 16-step matrix's per-cell selective render. |
| `{mode="always"}` | render every frame. Live animation (e.g. a moving playhead). |
| `{mode="frames", n=N}` | render when `frame % N == 0`. Throttled animation (e.g. a blink). |

---

## 6. Out of scope (v1)

- **Focus / cursor / input routing.** The system exposes bounds; *which control
  edits which widget* and *what is selected* are host policy. (`focusable` is
  reserved but inert.)
- **Seq-3 lane / step widgets.** Project-level, built on `widget_core`.
- **LED rendering.** Host concern (`glp/glc`).

---

## 7. Minimal end-to-end example

```lua
local core = require("widget_core")
local std  = require("widget_std")
local gfx  = require("gfx_device").new(self)   -- self = control element on device

-- one 2×1 region across the top strip
local top = core.Layout:new()
top:initialize(gfx, 2, 1, 0, 0, 320, 24)

local nameW = top:addWidget(0, 0, std.label:new("TRACK", {40,40,40}))
local volW  = top:addWidget(1, 0, std.range:new("VOL", {255,255,0}))  -- H bar

-- host pushes data (explicit-set path)
volW:set({ nv = 0.6 })      -- marks change; next render redraws only this cell

-- draw event (device element 13, event 8): render + conditional swap
top:render(frame)
```

For a nested grid, an addWidget target is itself a Layout:

```lua
local matrix = core.Layout:new()
matrix:initialize(gfx, 4, 4, 0, 24, 320, 168)   -- 4×4, its own selective render
grid:addWidget(0, 1, matrix)                     -- a cell of an outer layout
```
