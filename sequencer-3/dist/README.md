# dist/ — seq-3 on the Grid VSN1

**v11: the draw API was wrong.** `draw_area_filled` does not exist on the
device. v9 fixed the cold boot, v10 the lazy-load OOM, v11 the screen crash.

## v11: the screen crash

With v10 the chain loaded cleanly and then the screen crashed and rebooted the
module. Cause: the device modules called **`lcd:draw_area_filled(...)` 11
times** — a method that appears **nowhere** in seq-1's cold-boot-proven
`dist/sequencer_ui.lua`. The real primitive is `draw_rectangle_filled`, and the
five full-screen clears also passed `(0, 0, 320, 240)` when the framebuffer
corners are inclusive `0..319 x 0..239` — one pixel past each edge.

Both fixed. The proven set, and the only calls we now make:

```
scr:draw_rectangle_filled(x0, y0, x1, y1, {r,g,b})   -- CORNERS, not w/h
scr:draw_text_fast(text, x, y, size, {r,g,b})
scr:draw_swap()
```

**Why 46 headless checks missed it:** the test's LCD stand-in was an `__index`
that returned a function for *any* method name, so a nonexistent call looked
fine. `tests/lcd_mock.lua` now whitelists the four real primitives and
bounds-checks every coordinate — reintroducing the bug fails the suite.

## Status: the cold boot is SOLVED (v9), confirmed on device

v9's bare setup booted and the whole chain loaded:

```
seq3: loading engine -> engine ok -> demo ok -> loading screen -> screen ok
```

The `--probe` profile also booted (blank screen + `probe alive`), so the
element skeleton and our event wiring are both innocent. What failed next was a
different problem:

```
LUA not OK! error loading module 'seq3x' from file '/seq3x.lua': not enough memory
```

**v10 fixes that.** `seq3x` bundled all five periphery modules, so pressing
Shred — 843 B of code — forced an **11.2 KB** compile with the core already
resident. It is now split by what actually triggers it:

| bundle | size | pulled by |
|---|---|---|
| `seq3x.lua` | **4902 B** | Shred / Zero / rotate, Gamut / Euclid, X-Y addressing |
| `seq3p.lua` | **6947 B** | slot save / load, `loadPreset`, lane copy |

Peak lazy compile drops 11.2 KB → 6.9 KB, and the most-used live feature needs
only 4.9 KB. The bundle shim was also rewritten: it now resolves a missing
module through a **name → bundle map**, so requiring `ops` compiles `seq3x` and
nothing else. (The old shim tried each fallback in turn, so one miss could
compile a bundle that was never needed — exactly the RAM we are trying not to
spend.)

## Why v8 died, and what v9 changed

v8 required `seq3` + `seq3ui` at setup **and** ran the demo there. The measured
ladder in `AGENTS.md` already said this cannot work:

| shape | result |
|---|---|
| full GUI at setup | 183 KB, dead |
| **eager core-only at setup** | 149 KB, **refused to start** |
| **requires NOTHING at setup**, chain compiles on first MIDI byte | 150 KB, **runs** |

Runtime RAM was almost identical in the last two rows — so the killer is not
how much RAM the sequencer eventually uses, it is **doing the work during the
cold-boot sequence**. v8 shrank the eager load (122 KB → 98 KB) but kept it
eager, which was the wrong axis. No eager-at-setup build has ever booted.

**v9's setup does zero requires.** It only defines a global loader and assigns
the MIDI callback:

```lua
function L() if not RX then UI=require("seq3ui") RX=UI.midi_rx RX.ensure() end return RX end
self.rtmrx_cb = function(self,t) L().handle(t, midi_send) end
```

Nothing compiles until a trigger fires. The draw and timer events — which *do*
fire during the cold boot — deliberately never call `L()`, so the screen stays
dark until the chain loads. Requiring `seq3ui` pulls `seq3` through its own
shim, so one require does it.

## Two real bugs fixed on the way

1. **`rtmrx_cb` had the wrong signature.** v7/v8 emitted
   `function(self,h,t)RX.handle(t,...)`, so `h` received the status byte and
   `t` was `nil` — **MIDI clock could never have worked**, quite apart from the
   boot failure. seq-1's proven wiring is `function(self, t)`.
2. **14 timer events.** The element skeleton is cloned from **seq-2** (the dead
   project) and puts `print("tick")` on the timer of all 14 elements; seq-1's
   working profile has 2. v9 blanks all but el 255's RAM diagnostic.

## Bisection ladder — upload in this order, stop at the first that boots

The Mac cannot answer which of these it is; each step is one upload.

| step | command | if it BOOTS | if it DIES |
|---|---|---|---|
| 1 | `python3 tools/gen_profile.py --probe --install` | skeleton + event wiring are innocent → go to step 2 | the **seq-2 template itself** is the killer; rebuild it from a working seq-1 profile (`lib seq 4`) |
| 2 | `sh tools/make_dist.sh --install` (v9 default) | **done** — press a key or send clock to load | go to step 3 |
| 3 | `sh tools/make_dist.sh --setup=press --install` | MIDI is ignored until the first key press; that is the v5 shape | the load itself is too big → step 4 |
| 4 | split `seq3.lua` (19.4 KB) into `seq3.lua` + `seq3b.lua` (~7 + 12 KB) | — | seq-1's max chunk is 10.3 KB; ours is the outlier |

### If a lazy bundle still reports "not enough memory"

The next lever is measured and does not cost a single feature: **28 one-line
`M.set*` functions in `engine.lua` at ~435 B each ≈ 12 KB**, collapsible into a
table-driven dispatcher (`M.set(lane, field, v)` already exists). That frees
resident core RAM permanently, which is what a lazy compile needs. See the
"Measured RAM" section of `AGENTS.md`.

`seq3 probe.json` is already generated and installed: every event blank except
a timer printing `probe alive`. No require, no module code. It isolates the
element skeleton from our Lua in a single boot.

## Recovering a module that will not start

Load a known-good profile from the editor — e.g. the installed
`lib seq 4 (vsn1 only, fully working)`, or `seq3 probe`. The previous v7
profile is kept as `seq3 core.json.v7-backup` in the configs folder.

## Bundle sizes

| file | bytes | contents | when it loads |
|---|---|---|---|
| `seq3.lua` | 19428 | sources, scales, transport, lane, engine | first trigger |
| `seq3ui.lua` | 11444 | device_boot, midi_rx, screen, menu | first trigger |
| `seq3x.lua` | 4902 | ops, generate, ext | first Shred / Zero / generate |
| `seq3p.lua` | 6947 | preset, persist | first save / load |

Nothing at all loads at setup.

## Upload (Grid editor)

1. Delete ALL previously uploaded per-file modules (`engine`, `sources`,
   `screen`, `menu`, …) from the module's file storage.
2. Upload the **four** bundles under these **exact** names:
   - `dist/seq3.lua`
   - `dist/seq3ui.lua`
   - `dist/seq3x.lua`  (lazy — must be present for Shred / Zero / generate)
   - `dist/seq3p.lua`  (lazy — must be present for slot save / load)
3. Load the refreshed **seq3 core** profile (`dist/seq3 core.json`).
   Setup is now **zero requires** — just the loader + `rtmrx_cb`.
   The screen stays dark until the first MIDI byte or key press: that is
   expected, not a failure.
4. Route MIDI clock in (Ableton), module MIDI out to the DAW.

## Using save/load on the module

`Config` (keyswitch 0) > page **GLOBALS**:

```
run     on/off
reset   -
slot    1..24        <- encoder: press to edit, turn to choose
save    ok/err/-     <- press to edit, turn to fire
load    ok/err/-     <- press to edit, turn to fire
```

The first save or load compiles `persist` (and pulls `seq3x` if no action has
yet). Slots land in the module's file storage as `s01.lua` … `s24.lua`, in the
same preset-shaped Lua-chunk format the Mac harness writes — a slot saved on
the Mac in `presets/` can be uploaded as `sNN.lua` and loaded on the module,
and vice versa.

## What works (verified headlessly through the real bundles)

`tests/dist_smoke.lua` — 37 checks — asserts through the actual bundle files:

- 2-lane demo (note + trig), clock → notes out, stop → note-offs,
  Overview/Focus/Config, param editing, Zero/Shred, lane select.
- **`seq3x` is NOT pulled by boot, demo, clock, nav or draw** (the cold path
  stays clean), and resolves exactly once on the first action that needs it.
- **Slot save → load round-trips through the bundles** with the device's flat
  `sNN.lua` naming.
- No banned call (`collectgarbage`, `package.loaded`, `string.format`,
  `math.type`) appears in any bundle.

`seq3 mem KB: <n>` prints from the timer event — report it at boot, after the
first Shred (when `seq3x` lands), and per screen.

## Regenerate

```
sh tools/make_dist.sh [--install]        # v9: nothing required at setup
sh tools/make_dist.sh --setup=press …    # load on first key press, not MIDI
sh tools/make_dist.sh --setup=eager …    # v8 shape (known to fail cold boot)
python3 tools/gen_profile.py --probe --install   # the boot probe
lua tests/dist_smoke.lua                 # 37 checks through the real bundles
lua tests/boot_sim.lua                   # 15 checks: the v9 cold-boot contract
```

## Verified headlessly

- `tests/boot_sim.lua` (15 checks) simulates the v9 profile order against the
  real bundles: setup loads no bundle, draw/timer load nothing, the first MIDI
  byte loads the chain and emits notes, `seq3x` stays lazy, and the corrected
  `(self,t)` signature is pinned.
- `tests/dist_smoke.lua` (37 checks) drives clock, controls, draw, lazy
  resolution and slot save/load through the actual bundle files.
