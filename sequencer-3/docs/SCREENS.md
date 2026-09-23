# SCREENS.md — sequencer-3 Grid GUI plan

Status: planned (e2e first, then complete and pretty).

The Grid VSN1 control interface, built on the **layout engine**
(`../layout-system/`): `layout_core.lua` is unchanged; every widget here is a
consumer widget per `layout-system/SPEC.md` §5–6 (plain table, mandatory
`render`, self-dirtying `set`, engine-injected `x/y/w/h/lcd`).

Vocabulary: `CONTEXT.md` — screen, Overview, Focus, Config, step cell, playhead
marker, selected step, GUI host.

## 1. Architecture: the GUI host

The Core emits no events, but the adapter sees every moment state can change.
So the GUI is **push-only, no polling, no diffing**:

```
device:  midirx_cb (clock 0xF8) ─┐
harness: loop frame (timer)   ───┤
                                 ▼
                 host.onPulse() ── seq3.onPulse() / seq3.tick()
                        │
                        ├─ push playhead markers into step cells
                        └─ (note-offs drained; nothing to render)

host.action(name, ...) ── seq3.<action>(...)
        │
        └─ push affected widgets (edited cell, selection move, labels, menus)
```

- The host owns **all widget references** in lookup arrays
  (`lane_views[lane][step]` → step cell, plus screen-level widgets). Targeting
  an update is an array lookup, not a search — the validated pattern of SPEC §6
  and layout-system commit 93cf1fe.
- Controls (keys/buttons/encoder) are host policy: direct widget refs + `set{}`
  + action calls. `Layout:dispatch` is reserved for genuinely broadcast input
  events; nothing in v1 needs it.
- Widgets never touch `seq3.*`. The host is the facade; a mock state source can
  replace the Core for pure-widget work.

See ADR-0007 for the trade-off (vs polling/diffing).

## 2. Screens

| Screen | Entered by | Contents |
|---|---|---|
| **Overview** | View key (or default) | 4 lane strips, all playheads |
| **Focus** | View key from Overview | one lane's step matrix, always 4×4 |
| **Config** | Config key (lane menu from Focus, globals from Overview) | menu widget |

Deferred follow-on screens: Scale editor, Save/Load pages, Generator pages
(Gamut/Euclid), preset slots UI. They are Config-menu pages, so the menu
widget's contract below must cover them.

### 2.1 Overview — all four lanes

```
320×240, four strips of 320×60
┌──────────────────────────────────────────┐  strip 1
│ [1 NOTE] ▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪ (16 cells)      │
├──────────────────────────────────────────┤  strip 2
│ [2 TRIG] ▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪                 │
├──────────────────────────────────────────┤  strip 3
│ [3 MOD ] ▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪                 │
├──────────────────────────────────────────┤  strip 4
│ [4 GATE] ▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪                 │
└──────────────────────────────────────────┘
```

- Strips are **linear 1×16** (max 16 cells); `dims` is ignored — steps render
  in storage order (`index = y*width + x` from PARAM_DEPENDENCIES).
- Each strip is **one** `lane_strip` widget: a ~42px label gutter plus 16 mini
  cells (~17px each). The host pokes `values/pos/kind/label` directly (an
  element-wise array diff would cost per element) and sets `change`.
- The playhead runs on **every** strip (all lanes advance independently).
- Selected lane = white bar down the strip's left edge.
- Unused steps (e.g. 5x3 slot 16, 4x3 slots 13–16) render as empty slots.

### 2.2 Focus — one lane, 4×4

```
320×240, one big matrix, no nav band
┌───────────────────────────────┬──────────┐
│                               │  value   │
│      4×4 step matrix          │ readout  │
│      cells ~70×55             │ (selected│
│      (280×220)                │  param)  │
│                               │ + spare  │
└───────────────────────────────┴──────────┘
        leftover pixels: TBD (per-region indicators, later)
```

- The matrix is **always 4×4** regardless of `dims` (chosen for readability).
  Step index maps row-major onto screen cells; playback order follows the
  lane's `dims` navigation.
- **Known trade-off**: for `dims` wider than 4 (`16x1`, `8x2`, `5x3`) the
  screen's visual X-wrap (4) differs from the playback X-wrap (dims width). The
  playhead reads like wrapped text: correct order, axes not mirrored. E.g.
  `5x3`: X wraps every 5 within a playback row; on screen that path breaks
  across display rows. Accepted for v1. Possible later refinement: an optional
  per-`dims` display shape (a 5x3 lane could show its true 5×3 grid).
- The matrix is **four** `lane_strip` widgets (`big=true`, 4 cells each) plus a
  `value_readout` — 5 widget instances, not 16 per-cell widgets. One strip
  class for all lanes; `kind` switches render; colour per lane type. Note
  lanes: pitch as fill height; Mod: value bar; Trig/Gate: filled/empty block.
- Cells carry both markers: playhead = white bar down the playing cell's left
  edge, selected step = white bar across the cell's top. Only the row holding
  the playhead/selection shows its marker.
- The selected step's focused parameter drives the value readout
  (`value_readout`, display string pushed by host). Encoder press cycles the
  focused param (Note: pitch → velocity → length; Mod/Trig/Gate: single param).

### 2.3 Config — menu screen

```
320×240, one menu widget, viewport of ~9 rows (24px each)
┌──────────────────────────────┐
│ page title                   │
│ ▶ type        Note           │  ← cursor
│   dims        16x1           │
│   division    2              │
│   scale       major (root C) │
│   ...                        │
└──────────────────────────────┘
```

- Data-in: `set{ items = { {label, value}, ... }, title = "..." }`;
  `cursor` and edit-mode are widget-local display state.
- Encoder turn = move cursor; press = toggle edit (turn edits the value; press
  returns to cursor mode). Value edits call the action API through the host.
- Pages built: **Lane** (type, dims, division, channel, length), **Globals**
  (run, reset). Deferred follow-on pages: scale/range/source routing on the
  Lane page, **Copy** (`copy(from, to)` — demoted from a physical key),
  **Save/Load** (24 slots). Source-routing pages (advance/x/y/reset/random/
  shift, address) follow the same menu once e2e is proven.

## 3. Control map (device; harness mirrors via INPUT_SPEC indices)

| Control | Role |
|---|---|
| Screen btns 9–12 | Lane select (Focus target) |
| Key 0 | Config: toggle menu (lane menu from Focus, globals from Overview) |
| Key 1 | View: Overview ⇄ Focus; also backs out of Config |
| Key 2 / 3 | Save / Load — deferred (pages not built; no-op in v1) |
| Key 4 / 5 | Prev / Next: move the selected step along the playback path (X wrap); playhead untouched |
| Key 6 / 7 | Zero / Shred: the **playhead** step (engine semantics, `src/core/engine.lua` — not the selected step) |
| Encoder turn | Focus: edit focused param of the selected step; Config: cursor / edit value |
| Encoder press | Focus: cycle focused param; Config: toggle select/edit |

Deferred (MD2 combos, accepted loss for v1): Save+lane combos, Next+Prev =
reset, hold+turn gestures, Copy key (→ menu).

## 4. Widget inventory & data contracts

All widgets are consumer modules under `sequencer-3/gui/`, built on
`layout_core`. Contracts follow the mixed rule: **geometry widgets take raw
numbers, text widgets take display strings** (host formats; widgets stay dumb).
All setters are change-detecting (`set` marks dirty only on real change).

| Widget | Data-in (pushed via `set`) | Local (host pokes directly) | Notes |
|---|---|---|---|
| `lane_strip` | `{label}` (string) — change-detecting | `values[]`, `pos`, `selStep`, `kind`, `color`, `selected`, `change` | one class for Overview mini-strips (16 cells) and Focus matrix rows (`big`, 4 cells); renders value fill + both markers |
| `value_readout` | `{label="C#3"}` (string, pre-formatted by host) | — | Focus; auto-fit centred (value_writer pattern) |
| `menu` | `{title=, items={{label, value},...}}` | `cursor`, `edit_mode` | viewport of rows; encoder is host-driven, widget just displays |
| screen state | — | host swaps layouts | Overview/Focus/Config are three top-level Layouts; the host renders the active one (Config built lazily) |

Push triggers (exhaustive for v1):

- **onPulse**: for each lane whose position changed, poke the strip's `pos`
  and set `change` (≤4 pokes per pulse; render cadence capped by the draw
  loop, dirty flags absorb the rest).
- **action-out**: step edit → the lane's overview strip + its Focus row
  strips; selection move → same; lane select → all strips; config change →
  menu; screen switch → only the active layout renders.

## 5. Dirty-flag & render rules

- Standard engine semantics: `update={mode="dirty"}` everywhere; nothing
  animates in v1 (playhead moves are state changes, not animation).
- Change-detecting `set` (make_set pattern) keeps repeated pushes (clock at
  24 PPQN, held buttons) free when nothing changed.
- Only the active top-level Layout renders; screen switch = one layout's
  `render` replaces the other's, full repaint of the new screen via dirty flags
  (the host dirties every child of the target layout and clears the full
  screen once, so no pixels of the old screen survive).
- Open device question: `draw_swap` buffer semantics. If the back buffer is
  not persistent, a partially redrawn frame composites against a stale one and
  flickers between two states. Confirm at port time; the clear-on-switch above
  is independent of this.

## 6. Harness (grid-wasm) — BUILT (mock engine)

Status: the full screen flow is built and verified in the harness with a mock
engine. Runners (in `grid-wasm/`): `seq3run.mjs` (headless screenshot),
`seq3test.mjs` (drives the faceplate controls and screenshots each state),
`seq3live.mjs` (headed, interactive).

- Screen file: `sequencer-3/screens/seq3_gui.lua` (`-- INIT START/END` +
  `-- LOOP START/END`). Init is guarded (`if HOST then return end`) because the
  harness re-runs the whole script on every control event; state lives in
  globals and the engine. The same guard is device-compatible.
- GUI modules live in `sequencer-3/gui/`: `boot.lua` (require/lcd shims,
  engine + host construction, per-frame STEP), `host.lua` (GUI host),
  `widgets.lua` (`lane_strip`, `value_readout`, `menu`), `mock_engine.lua`
  (action-API-shaped state provider, `init{demo=true}` fills a demo pattern).
- The harness cannot `require` filesystem modules (no FS) and its VM heap is
  tiny: measured **~47 KB firmware baseline**, **~120 KB ceiling**, OOM aborts
  when live memory exceeds it. The **real Core's bytecode does not fit** next
  to the GUI (engine.lua alone ~17 KB stripped). Hence `mock_engine.lua`
  implements the action-API surface with the same lane shape, so the host code
  is identical on device. The full core loads via `--real` for experiments;
  expect OOM aborts.
- Module loading mechanics (validated): `loadScript(init, loop)` takes ~2 KB
  strings, only stores a script (executed on the next frame), and the VM
  persists globals across calls. So module sources are pushed as escaped
  string chunks (comments stripped, ~1.6 KB/call, each call awaited via a
  print handshake), then installed with `load(reader)` — the reader hands out
  one piece per call so the full source never exists as a single Lua string
  (the `#`-border/`table.remove` trap bites here). `collectgarbage()` after
  every compile and every frame.
- Heap discipline that made it fit: shared methods via metatables (one closure
  per class, not per instance), menu pages as plain data, the Focus matrix as
  4 row-strips of 4 big cells (not 16 per-cell widgets), Config layout built
  lazily on first open. ~9 widget instances total instead of ~85.
- Harness additions: index 13 = encoder press (the real VSN1 encoder is
  clickable); `resumeMainLoop()` after script loads (a bare-ccall loadScript
  leaves the main loop paused).

## 7. Build log

1. Harness plumbing: chunk loader (`seq3run.mjs`), require-vs-concat verified
   (`require` exists but the wasm VM has no FS → chunked strings + reader
   compile).
2. Overview: 4 labelled strips, playheads via loop-driven `host.onPulse()`,
   lane select via btns 9–12 — verified by screenshot.
3. Focus: 4 row-strips + value readout, encoder press cycles params
   (pitch → velocity → length), encoder turn edits (pitch/velocity/value/gate),
   Prev/Next/Zero/Shred — verified (readout showed the edit land).
4. Config: `menu` widget + Lane/Globals pages, cursor/edit encoder
   interaction — verified.
5. Device port: pending (real require; the engine may need splitting — see the
   heap notes above; `mock_engine.lua` is harness-only).

Known harness instability: at the heap ceiling the VM emits recoverable "Out of
memory" warnings and eventually aborts ("Stack overflow") — screenshots after
that are frozen frames. Observed ceiling: **~5–7 control events per session**
(each control event re-runs the init/loop scripts; the leak is cumulative and
per-frame `collectgarbage()` does not stop it). `seq3test.mjs` detects the
abort and reports later states as `SKIPPED` (exit 1) instead of claiming
success; a full 10-state run needs either a bigger harness heap (firmware build
flag — unverified) or per-scenario sessions. `seq3live.mjs` gives a headed
interactive browser with the same ceiling.

Steps 2–4 harden the widget set; only then "make it complete and pretty"
(remaining Config pages, leftover-pixel indicators in Focus, per-dims display
shape if wanted).