# Layout system — spec (v1)

A reusable, selective-rendering **layout system** for **Intech Grid** modules,
written in Lua. The deliverable is the **`Layout` engine**: it owns the root
logic — cell placement, the render lifecycle, selective/dirty draw, the
conditional swap, and the widget data channel. **Widgets are thin extension
points that hook into that engine**, and — apart from the reference set we ship —
they are authored by the *consumers* of this system, not by us.

Its job is narrow on purpose:

1. **Selective rendering** — only redraw what changed, so the ≤20 fps device
   draw loop stays cheap.
2. **Self-bounded widgets** — a widget knows its own `x/y/w/h` and draws only
   within those bounds. Bounds are also the handle a host uses to decide what a
   control action targets.
3. **Engine-owned mechanics** — merge/dirty/clear/indicator are the engine's job
   (§5). A consumer's widget implements *hooks* (`render`, optional `on_set` /
   `midirx_cb`), never framework bookkeeping. There is almost no convention to
   get wrong, which matters because untyped Lua widgets are written by others.

It is a general-purpose primitive, **not** sequencer-specific. `sequencer-3`
(and other projects) `require` it and compose their own widgets on top; the
shipped `widget_std` primitives are reference implementations, not the point.

Derived from two field profiles: `Copy of suku_widget_4` (midi-rx fan-out
variant) and `AbletonJS selected track control v1.3` (explicit-`set` variant).
This spec reconciles the two.

---

## 1. Runtime model

Two runtimes, one widget contract.

| | Device (VSN1R) — canonical | grid-wasm harness — preview |
|---|---|---|
| Code loading | `require`-able TEXT bundles, ≤ ~10 KB each | flat script, **no `require`**, ~2 KB init |
| Draw API | `self.lcd:draw_*(...)` — methods on the LCD control element | same names as globals, with a leading screen index |
| Status | real target | best-effort; harness code to be brought up to real names |

**There is only one draw API, not two.** The element method call and the
low-level global call are the *same functions*; the global form just takes a
leading screen-index argument (`self:screen_index()`) that the method form
supplies implicitly. So widget code calls the documented element methods
directly (§3) — no abstraction layer. The harness bridges the index difference
with a small shim that is **harness-only scaffolding** and never appears in
widget code (§3.1).

On device the system lives under the profile's element-255 setup
(`require` the core there) and is driven from the screen element's draw event
(`event 8`).

---

## 2. Files

All under `widget-system/`. Split so a project always requires a small core and
picks only the primitives it needs.

| File | Contents |
|---|---|
| `widget_core.lua` | the **`Layout` engine** + the base `Widget` (owns `set`/merge/dirty/indicator lifecycle, §5) |
| `widget_std.lua`  | reference primitives built on the base: `label`, `toggle`, `range` |
| `SPEC.md`         | this document |

`widget_core` is the product. `widget_std` is a set of examples showing how a
consumer hooks a widget into the engine; a project may use them, subclass them,
or ignore them and write its own.

There is **no** `gfx_device` / `gfx_harness` backend pair — widgets call the LCD
element methods directly. The only harness-specific code is the `lcd` shim of
§3.1, which lives in the grid-wasm preview scaffolding, not in this system.

Project-specific and consumer widgets (e.g. seq-3 lanes, the 16-step matrix
cell) live in the consuming project and build on `widget_core` — they are **not**
in `widget_std`.

Each bundle is plain TEXT ≤ ~10 KB (the module watchdog reboots on oversized
chunks). No `collectgarbage`, no `package.loaded` manipulation, no
`string.format` (absent from the Grid Lua build).

---

## 3. Draw handle (`self.lcd`)

Widgets draw through **`self.lcd`**, the LCD control element, using the
documented element methods directly — no wrapper. The handle is **injected at
`Layout:initialize`** and propagated to every widget as `self.lcd` (assigned by
`addWidget`, alongside bounds). Widgets never reach for a global draw API.

The primitives a widget uses (all take **absolute pixel corners**, 320×240;
colors are `{r,g,b}` 0..255):

```
self.lcd:draw_area_filled(x1, y1, x2, y2, {r,g,b})   -- filled rectangle (no alpha blend)
self.lcd:draw_text(str, x, y, size, {r,g,b})         -- truetype text (scalable)
self.lcd:draw_text_fast(str, x, y, size, {r,g,b})    -- bitmap text (cheaper)
self.lcd:draw_line(x1, y1, x2, y2, {r,g,b})          -- line
self.lcd:draw_swap()                                 -- flush/swap buffer (once per drawn frame)
```

Other documented methods (`draw_rectangle`, `draw_rectangle_rounded_filled`,
`draw_polygon_filled`, `draw_pixel`, `screen_width/height`, …) are available on
the same handle; the list above is just the common set the std primitives use.

Note: these are the **current** names. The two source profiles used the old
abbreviated forms (`lcd:ldaf` → `draw_area_filled`, `lcd:ldft` → `draw_text`,
`lcd:ldsw` → `draw_swap`); new code uses the full names.

LED calls (`glp` / `glc`) are **out of scope** — they are not screen draw and
stay with the host.

### 3.1 Harness scaffolding — the `lcd` shim (grid-wasm only)

This subsection exists to keep the harness detail **out of the widget code**.
grid-wasm has no LCD element; it exposes the draw functions as globals that take
a leading screen index. Since that index is the *only* difference from the
element methods, the harness supplies a stand-in `lcd` whose methods forward to
the globals with the index prepended:

```lua
-- grid-wasm preview scaffolding — NOT part of widget-system, NOT shipped to device.
local idx = 0                          -- screen index the harness globals expect
lcd = setmetatable({}, {
  __index = function(_, name)
    return function(_, ...) return _G[name](idx, ...) end   -- self:draw_x(a) -> draw_x(idx, a)
  end,
})
```

Rules that keep this from polluting the end result:

- Widget and Layout code **must not** reference this shim, the index, or any
  global draw name. It only ever calls `self.lcd:draw_*`. The shim is transparent.
- The shim lives in the grid-wasm init block, not in `widget_core`/`widget_std`.
  Device builds never load it (the device's `self.lcd` is the real element).
- Prerequisite: grid-wasm must expose its draw globals under the **real names**
  (`draw_area_filled`, `draw_text`, `draw_swap`, `draw_line`, …), replacing the
  current `ggd*` aliases. Once renamed, the shim needs no name map — only the
  index prefix. (Tracked separately from the widget-system work.)

---

## 4. Layout API

```
Layout:new()
Layout:initialize(lcd, cols, rows, x, y, w, h)
Layout:addWidget(cx, cy, widget)   -- places widget in cell (cx,cy); returns widget
Layout:render(frame)               -- draw pass; `frame` is a monotonic counter
```

- `cols` = horizontal cell count, `rows` = vertical cell count. A cell is
  `w/cols` × `h/rows`. (Explicit names — the source profiles used misleading
  `r/c`.)
- **Cell index** is row-major: `index = cy * cols + cx`.
- `addWidget` computes and assigns the widget's **absolute** bounds once:
  `widget.x = self.x + cx*cellW`, `widget.y = self.y + cy*cellH`,
  `widget.w = cellW`, `widget.h = cellH`; and sets `widget.lcd = self.lcd`,
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

`Layout:render(frame)` is the **root logic** — the whole per-cell lifecycle lives
here, not in the widgets:

1. Iterate cells in index order (a cheap flag-check loop — no upward dirty
   propagation).
2. For each cell, consult its `update` descriptor (§5) to decide whether to
   render. Only cells that render issue `lcd:draw_*` calls — this is where the
   perf win lives (draw calls are the expensive part, not the loop).
3. For a cell that renders, the engine does, in order:
   `cell:render()` (consumer hook — draws content) →
   `cell:renderIndicator()` (base overlay — active/focus affordance from
   `props`, §5) → `cell.change = false` (engine clears the dirty flag).
   The consumer's `render` therefore never touches `change` and never draws the
   indicator itself.
4. Track whether **anything** drew this frame.
5. Call `lcd:draw_swap()` **only if** something drew (skip the flush on
   fully-static frames). Only the top-level render owns the swap; nested renders
   draw but do not swap.

---

## 5. Widget contract

A widget is a table with **data in `self.props`** and a few methods. The split
that matters: the **engine provides the mechanics**; the **consumer implements
the hooks**. Because consumers write widgets in untyped Lua, the mechanics are
code the consumer never writes and so cannot get wrong.

### What the consumer implements (hooks)

```
Widget:new(...)                 -- constructor. Seed self.props (and optional
                                --   self.defaults). NO bounds here — Layout:addWidget assigns them.
Widget:render(self)             -- MANDATORY: draw content within self.x/y/w/h via self.lcd,
                                --   reading from self.props. Do NOT touch change or draw the indicator.
Widget:on_set(self, t)          -- OPTIONAL: react after a set (e.g. derive a value). t = the keys just set.
Widget:midirx_cb(self, hdr, ev) -- OPTIONAL: reactive MIDI-in hook (see below).
```

### What the engine provides (do not reimplement)

```
core.Widget:extend()            -- derive a new widget type that inherits the base methods below.
Widget:set(self, t)             -- merges t into self.props, sets change=true, then calls on_set.
                                --   MERGE, not replace: set{focused=true} never clears other props.
Widget:renderIndicator(self)    -- base overlay drawn by the Layout after render(): reads props
                                --   (e.g. props.focused) + self.indicator style; consumer never calls it.
-- change-flag clearing         -- the Layout clears change after rendering the cell (§4).
-- bounds + lcd injection       -- assigned by Layout:addWidget (§4).
```

`set` is the single write path. Data comes in through it; `props` is the only
thing it touches, so a `set` can never clobber framework fields (`x/y/w/h`,
`lcd`, `change`, `parent`). Optionally a widget declares `self.defaults` (the
prop names it understands) and the engine can warn on unknown keys — the nearest
thing to a type check in this Lua build.

Fields the system reads/writes:

| field | owner | meaning |
|---|---|---|
| `props` | consumer data, engine-merged | all widget data; `set` merges into it, `render` reads from it |
| `defaults` | consumer | optional prop-name allowlist for the unknown-key guard |
| `indicator` | consumer | active-affordance style, e.g. `{style="bar-top", color={0,120,255}, thick=2}` |
| `update` | consumer | update-cadence descriptor (below); default `{mode="dirty"}` |
| `change` | engine | dirty flag; `set` sets it, the Layout clears it after render |
| `x,y,w,h` | engine | absolute bounds, assigned by `addWidget` |
| `lcd` | engine | injected draw handle (the LCD element) |
| `parent` | engine | owning Layout |

### State & focus are just data

There is **no separate focus subsystem**. "Active/focused" is a prop like any
other — `w:set({focused=true})` — and the only thing that makes it visible is the
base `renderIndicator`, which the Layout calls after `render` and which draws the
style in `self.indicator` when the relevant prop is set. Consequences:

- **Multiple active at once** is automatic: each widget carries its own
  `props.focused` and draws its own indicator; no coordination needed.
- **Selective render is preserved**: `set` flips `change`, so selecting *or*
  deselecting redraws exactly that cell — content **and** indicator together
  (the indicator is an overlay, so the content beneath is repainted by the
  full-cell redraw; never try to erase just the border).
- Adding a second state later (e.g. `props.error`) is just another prop + another
  branch in `renderIndicator` — no contract change.

### Two reactivity paths (both first-class)

- **`set` (explicit push):** the host computes data and calls `widget:set(t)`.
  Used when data comes from a package or app logic (AbletonJS `RT_*`
  dispatcher → `wg:set`).
- **`midirx_cb` (reactive):** the Layout fans a MIDI-in event out to every
  cell's `midirx_cb`; the widget writes its own `props` from the raw event (and
  should set `change`). Used when MIDI-rx reactivity is available (suku variant).

A widget may implement either, both, or neither (a purely static/animated widget
needs only `render`).

### Why this shape (rejected alternatives)

- A **positional `set(nv, focused)`** was rejected: focus and data change at
  different times, so a positional call forces every caller to re-pass both or
  clobber one. Table + merge lets each call touch only the keys it names.
- A **metatable `__newindex` reactive proxy** (`w.props.x = v` auto-dirties) was
  rejected for this runtime: `__newindex` fires only for absent keys, forcing a
  per-widget backing-table proxy with `rawget/rawset` on every access — needless
  allocation and overhead under the ≤20 fps, GC-sensitive, small-bundle limits.
- The **one irreducible convention**: `render` must stay within `self.x/y/w/h`.
  The LCD API has no scissor/clip, so it can't be enforced — a debug mode can
  outline bounds, but that is a check, not enforcement.

### Update cadence

The `update` descriptor is the widget's declaration of **when** it re-renders —
the core of selective rendering:

| `update` | behavior |
|---|---|
| `{mode="dirty"}` (default) | render only when `change==true` (then clear it). The 16-step matrix's per-cell selective render. |
| `{mode="always"}` | render every frame. Live animation (e.g. a moving playhead). |
| `{mode="frames", n=N}` | render when `frame % N == 0`. Throttled animation (e.g. a blink). |

---

## 6. Selection & input routing = host policy

The engine provides the **mechanism** to *show* selection (a `focused` prop +
`renderIndicator`, §5) and to *find* a widget (bounds; optional
`Layout:hitTest(px,py)` walking cells and recursing into sub-Layouts). It does
**not** decide *what is selected* or *which control edits which widget* — that is
host policy.

The typical device pattern (the reason this stays host-side): a fixed set of
physical controls — say **4 encoders** — drives the *currently selected row* of
widgets; changing the selection re-targets the same 4 controls at the next row.
The host owns this trivially by holding an array of widget refs per bank:

```lua
-- host state; no widget or engine change needed
local bank = { rowA_w1, rowA_w2, rowA_w3, rowA_w4 }   -- what the 4 encoders drive now
-- encoder i moved -> edit the i-th widget of the current bank
bank[i]:set({ nv = newValue })
-- selection moved to the next row -> clear old focus, set new, re-point the bank
for _,w in ipairs(bank) do w:set({ focused = false }) end
bank = { rowB_w1, rowB_w2, rowB_w3, rowB_w4 }
for _,w in ipairs(bank) do w:set({ focused = true }) end
```

Because the host already holds these refs, device navigation usually needs no
`id`/`hitTest` at all; reach for `hitTest` only for the grid-wasm pointer.

Still out of scope:

- **Seq-3 lane / step widgets.** Project-level, built on `widget_core`.
- **LED rendering.** Host concern (`glp/glc`).

---

## 7. Minimal end-to-end example

A consumer widget is just `new` + `render` reading `self.props`; `set`,
`renderIndicator`, and the dirty flag come from the base:

```lua
local core = require("widget_core")

-- a consumer-authored widget: a horizontal value bar
local bar = core.Widget:extend()
function bar:new(color)
  local w = core.Widget.new(self)
  w.props     = { nv = 0, focused = false }
  w.defaults  = { nv = true, focused = true } -- optional unknown-key guard (own table, not props)
  w.color     = color
  w.indicator = { style = "bar-top", color = {0,120,255}, thick = 2 }
  return w
end
function bar:render()                        -- content only; no change/indicator here
  local fw = self.x + math.floor(self.props.nv * self.w)
  self.lcd:draw_area_filled(self.x, self.y, fw, self.y + self.h, self.color)
end
```

Wiring and driving it:

```lua
local std = require("widget_std")
-- `self` is the LCD control element on device; in grid-wasm it is the shim of §3.1.

local top = core.Layout:new()
top:initialize(self, 2, 1, 0, 0, 320, 24)    -- 2×1 region; pass the LCD element

local nameW = top:addWidget(0, 0, std.label:new("VOL", {40,40,40}))
local volW  = top:addWidget(1, 0, bar:new({255,255,0}))

volW:set({ nv = 0.6 })        -- data;  merges into props, flips change
volW:set({ focused = true })  -- focus; independent set, still just this cell redraws

-- draw event (device element 13, event 8): engine renders content + indicator, clears change, swaps
top:render(frame)
```

For a nested grid, an addWidget target is itself a Layout:

```lua
local matrix = core.Layout:new()
matrix:initialize(self, 4, 4, 0, 24, 320, 168)  -- 4×4, its own selective render
grid:addWidget(0, 1, matrix)                     -- a cell of an outer layout
```
