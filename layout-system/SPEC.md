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
3. **Lean by omission** — the engine owns only the render lifecycle (when to
   draw, clearing the dirty flag, the swap) and a generic event fan-out. A widget
   is just a table with a `render`; how its data arrives (`set` / `midirx_cb` /
   `sysexrx_cb` / …) is the author's open choice (§5). No base class, no
   prescribed setter — which matters because untyped Lua widgets are written by
   others and should carry no machinery they don't use.

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

All under `layout-system/`. A project requires the small core and writes (or
copies) whatever widgets it needs.

| File | Contents |
|---|---|
| `layout_core.lua` | the **`Layout` engine** (render lifecycle, selective draw, swap, `dispatch` fan-out, bounds/`lcd` injection) + the optional free `drawIndicator` helper (§5) — **built** |
| `my_own_widgets.lua` | example consumer widget module: `draw_arc` (an arc-potmeter indicator) — **built**, demo reference |
| `widget_std.lua`  | planned reference widgets (`label`, `toggle`, `range`) — not yet built |
| `SPEC.md`         | this document |

These are **filesystem modules**, written with the long, human-readable LCD
names (`draw_area_filled`, `draw_swap`, …); the Grid editor minifies them to the
short names on upload. Inline profile-event code (the config JSON) is the
opposite — it must already use the short names (`ldaf`, `ldsw`, …).

`layout_core` is the product — and it is small: there is **no base `Widget`
class**. A widget is any table with a `render` method (§5); the engine renders it
when dirty. `widget_std`/`my_own_widgets` are just examples of how a consumer
writes a widget; a project may use them, copy them, or ignore them.

There is **no** `gfx_device` / `gfx_harness` backend pair — widgets call the LCD
element methods directly. The only harness-specific code is the `lcd` shim of
§3.1, which lives in the grid-wasm preview scaffolding, not in this system.

Project-specific and consumer widgets (e.g. seq-3 lanes, the 16-step matrix
cell) live in the consuming project and build on `layout_core` — they are **not**
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
- The shim lives in the grid-wasm init block, not in `layout_core`/`widget_std`.
  Device builds never load it (the device's `self.lcd` is the real element).
- Prerequisite: grid-wasm must expose its draw globals under the **real names**
  (`draw_area_filled`, `draw_text`, `draw_swap`, `draw_line`, …), replacing the
  current `ggd*` aliases. Once renamed, the shim needs no name map — only the
  index prefix. (Tracked separately from the widget-system work.)

---

## 4. Layout API

```
Layout:new()
Layout:initialize(lcd, cols, rows, x, y, w, h)   -- cols/rows may be nil for placement-only
Layout:addWidget(cx, cy, widget)      -- GRID: place in uniform cell (cx,cy); returns widget
Layout:place(x, y, w, h, widget)      -- EXPLICIT: place at an arbitrary rect (rel. to origin)
Layout:render(frame)                  -- draw pass; `frame` is a monotonic counter
Layout:dispatch(cbName, ...)          -- fan an event to children implementing cbName (§5)
```

Two placement modes, both appending to the same child list:

- **`addWidget` (uniform grid)** — for even sub-divisions (a 4×1 button row, a
  4×4 matrix). `cols`/`rows` are the cell counts; a cell is `w/cols` × `h/rows`.
- **`place` (explicit rect)** — for **variable-size screen regions** (a real UI:
  a 3-line nav band, a value line, a big arc, a slim button row have different
  heights a uniform grid can't express). Composes with the grid: `place` a slim
  bottom band, then fill it with a nested `4×1` grid Layout.

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
3. For a cell that renders, the engine calls `cell:render()` (the widget draws
   its content **and** any active/focus indicator) and then clears the dirty flag
   with `cell.change = false`. Clearing `change` is the one bookkeeping step the
   engine still does for the widget; setting it is the widget's job (§5).
4. Track whether **anything** drew this frame.
5. Call `lcd:draw_swap()` **only if** something drew (skip the flush on
   fully-static frames). Only the top-level render owns the swap; nested renders
   draw but do not swap.

### Event fan-out (`dispatch`)

Data reaches widgets through an **open, optional set** of author-written
callbacks (`set`, `midirx_cb`, `sysexrx_cb`, …; §5). The engine does not know or
care which — it offers one generic fan-out:

```
Layout:dispatch(cbName, ...)   -- for each cell that has cell[cbName], call it; recurse into sub-Layouts
```

The host wires each Grid event to it — e.g. `layout:dispatch("midirx_cb", header, event)`
from the MIDI-rx handler, `layout:dispatch("sysexrx_cb", header, sysex)` from the
system/sysex handler. A new event type later needs no engine change: pick a
callback name and dispatch it.

---

## 5. Widget contract

Kept deliberately thin. **`render` is the only method every widget has.**
Everything else — including how data arrives — is optional and author-chosen.
There is **no base `Widget` class, no prescribed `set`, no `props` container.** A
widget is just a table the engine renders when it is dirty.

### The only thing the engine requires

```
Widget:render(self, frame)  -- MANDATORY: draw content (and any active/focus indicator)
                      --   within self.x/y/w/h via self.lcd. Reads whatever fields the
                      --   widget chose to store. `frame` (the monotonic counter) is
                      --   passed for frame-based animation/polling; most widgets ignore it.
                      --   This is the sole universal method.
```

Fields the engine reads (everything else on the table is the widget's own):

| field | owner | meaning |
|---|---|---|
| `update` | widget | update-cadence descriptor (below); default treated as `{mode="dirty"}` |
| `change` | widget sets, engine clears | dirty flag; the widget sets it when its data changes, the Layout clears it after render (§4) |
| `x,y,w,h` | engine | absolute bounds, assigned by `addWidget` |
| `lcd` | engine | injected draw handle (the LCD element) |
| `parent` | engine | owning Layout |

### Data-in is the widget's choice (an open set of callbacks)

How a widget's data changes is not the engine's concern. The profiles show three
different paths, and there will be more:

```
Widget:set(self, ...)            -- OPTIONAL: explicit push from app logic (AbletonJS variant).
Widget:midirx_cb(self, hdr, ev)  -- OPTIONAL: reactive MIDI-in (suku variant).
Widget:sysexrx_cb(self, hdr, sx) -- OPTIONAL: reactive SysEx-in (VSN1 Master Control variant).
--  …any other event callback the host chooses to dispatch (§4 `Layout:dispatch`).
```

These are **peers**, all optional, none special:

- `set` has **no** privileged status, no mandated merge semantics, no `props`
  requirement. It is simply one name a host may call. A widget fed only by
  `midirx_cb`/`sysexrx_cb` does not define `set` at all.
- Whatever callback mutates the widget's data is **author-written**, so it also
  **sets `self.change = true`** at the end. That is the one rule — and it lives
  inside a handler the author is already writing by hand, not as machinery
  imposed on every widget. (`change` is cheap and universal; the engine reads it
  to skip clean cells.)
- The host routes Grid events to these callbacks with `Layout:dispatch(cbName, ...)`
  (§4). Widgets that lack the named callback are simply skipped.

Because the widget writes its own fields directly (`self.value = ev[3]`), there
is nothing to clobber and no merge to get wrong — the concerns that a base `set`
would have introduced don't exist.

### State & focus are just data (with an optional draw helper)

There is **no focus subsystem**. "Active/focused" is an ordinary field the widget
stores (however it likes) and an `if` branch in its own `render` that draws the
affordance. Consequences:

- **Multiple active at once** is automatic — each widget renders its own
  indicator from its own field; no coordination.
- **Selective render is preserved** — the callback that changes focus sets
  `change`, so selecting *or* deselecting redraws exactly that cell, content and
  indicator together (the indicator is an overlay, so the content beneath is
  repainted by the full-cell redraw; never try to erase just the border).

To avoid every widget re-coding the same border/dot/bar, `layout_core` offers an
**optional free helper** (not a base method, no inheritance):

```
core.drawIndicator(lcd, x, y, w, h, style)   -- style e.g. {kind="bar-top", color={0,120,255}, thick=2}
```

A widget MAY call it from `render`; a widget that wants a bespoke indicator just
draws its own. It is a convenience, not part of the contract.

### Text helpers (also free functions)

`draw_text_fast`'s glyph advance is ~= `size` px/char (sizes are multiples of 8).
Fitting and centring text within a widget's bounds recurs across widgets (value
readouts, buttons, labels), so `layout_core` exposes three tiny free helpers —
again, functions, not a base class:

```
core.textWidth(text, size)                 -- #text * size (an upper bound; never overflows)
core.fitSize(text, maxW, maxSize, minSize) -- largest multiple-of-8 size that fits maxW
core.centerX(text, size, x, w)             -- left x to centre the text in [x, x+w]
```

Verified against the reference: "Hovr" in an 80 px slot → `fitSize` = 16
(`4×16=64≤80`, `4×24=96>80`), matching the hand-tuned original.

### Why this shape (rejected alternatives)

- A **base `Widget` with a canonical `set`/`props`** was rejected as too heavy
  and a poor fit: the three field profiles use `set`, `midirx_cb`, and
  `sysexrx_cb` respectively (VSN1 uses two at once), so there is no universal
  setter — only `render` is shared. Baking in `set`+`props` taxes every widget,
  including the majority that never call `set`, and solves clobber/merge problems
  that only exist *because* of a base `set`.
- A **metatable `__newindex` reactive proxy** (auto-dirty on field write) was
  rejected for this runtime: `__newindex` fires only for absent keys, forcing a
  per-widget backing-table proxy with `rawget/rawset` on every access — needless
  allocation and overhead under the ≤20 fps, GC-sensitive, small-bundle limits.
- The **irreducible conventions** are just two, both minimal: set `change` in
  your own data callback, and keep `render` within `self.x/y/w/h` (the LCD API
  has no scissor/clip to enforce the latter; a debug mode can outline bounds).

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

The engine provides the **mechanism** to *find* a widget (bounds; optional
`Layout:hitTest(px,py)` walking cells and recursing into sub-Layouts) and to
*reach* widgets (`dispatch`, §4). It does **not** decide *what is selected* or
*which control edits which widget* — that is host policy, and showing selection
is just the widget drawing its own indicator from its own field (§5).

The typical device pattern (the reason this stays host-side): a fixed set of
physical controls — say **4 encoders** — drives the *currently selected row* of
widgets; changing the selection re-targets the same 4 controls at the next row.
The host owns this trivially by holding an array of widget refs per bank, and
pokes each widget however that widget takes data (its own field, or a `set` if it
has one):

```lua
-- host state; no widget or engine change needed
local bank = { rowA_w1, rowA_w2, rowA_w3, rowA_w4 }   -- what the 4 encoders drive now
-- encoder i moved -> update the i-th widget of the current bank, then mark it dirty
local w = bank[i]; w.nv = newValue; w.change = true
-- selection moved -> clear old focus, set new, re-point the bank
for _,x in ipairs(bank) do x.focused = false; x.change = true end
bank = { rowB_w1, rowB_w2, rowB_w3, rowB_w4 }
for _,x in ipairs(bank) do x.focused = true;  x.change = true end
```

Because the host already holds these refs, device navigation usually needs no
`id`/`hitTest` at all; reach for `hitTest` only for the grid-wasm pointer.

Still out of scope:

- **Seq-3 lane / step widgets.** Project-level, built on `layout_core`.
- **LED rendering.** Host concern (`glp/glc`).

---

## 7. Minimal end-to-end example

A widget is a plain table with a `render` and whatever data-in callback it wants.
No base class, no `props` container — it stores its own fields and marks itself
dirty in its own callback:

```lua
local core = require("layout_core")

-- a consumer-authored widget: a horizontal value bar, fed by MIDI-in
local function newBar(color)
  return {
    nv = 0, focused = false, color = color,

    render = function(self)                     -- content + indicator, in bounds
      local fw = self.x + math.floor(self.nv * self.w)
      self.lcd:draw_area_filled(self.x, self.y, fw, self.y + self.h, self.color)
      if self.focused then                      -- indicator is just an if-branch
        core.drawIndicator(self.lcd, self.x, self.y, self.w, self.h,
                           { kind = "bar-top", color = {0,120,255}, thick = 2 })
      end
    end,

    midirx_cb = function(self, header, event)   -- data-in of this widget's choosing
      self.nv = event[3] / 127
      self.change = true                        -- the one rule: flag dirty in your own callback
    end,
    -- a different widget might use set(...) or sysexrx_cb(...) instead — all optional peers.
  }
end
```

Wiring and driving it:

```lua
local std = require("widget_std")
-- `self` is the LCD control element on device; in grid-wasm it is the shim of §3.1.

local top = core.Layout:new()
top:initialize(self, 2, 1, 0, 0, 320, 24)    -- 2×1 region; pass the LCD element

local nameW = top:addWidget(0, 0, std.label:new("VOL", {40,40,40}))
local volW  = top:addWidget(1, 0, newBar({255,255,0}))

-- host drives it: fan MIDI-in to every widget's midirx_cb, or poke fields directly
top:dispatch("midirx_cb", header, event)     -- volW.midirx_cb runs, sets nv + change
volW.focused = true; volW.change = true      -- focus is just a field + dirty flag

-- draw event (device element 13, event 8): engine renders dirty cells, clears change, swaps
top:render(frame)
```

For a nested grid, an addWidget target is itself a Layout:

```lua
local matrix = core.Layout:new()
matrix:initialize(self, 4, 4, 0, 24, 320, 168)  -- 4×4, its own selective render
grid:addWidget(0, 1, matrix)                     -- a cell of an outer layout
```
