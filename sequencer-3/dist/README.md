# dist/ — seq-3 on the Grid VSN1

## v15 (2026-10-04): lane GUI — Overview + Focus

`sh tools/make_dist.sh --gui=lanes` puts `src/device/lane_screen.lua` in
`seq3s` (same seven files, same profile).

- **Overview:** one 16-cell strip per lane, with a `1 N` / `/div` label.
  Note cells are pitch bars scaled to the lane's own pitch span; trig cells
  are filled on active steps. The white bar marks the playhead and the
  outline marks the selected step. The encoder selects the lane, press opens
  Focus.
- **Focus:** the selected lane's steps as a grid in its own dims (16x1 ..
  4x4), plus the text screen's key/value rows in two columns. The encoder
  moves the cursor; press toggles edit (run/save/load fire directly).
- **Keys:** 1 Overview <-> Focus · 0 run/stop · 4/5 prev/next step ·
  3 Random · 6/7 Zero/Shred · 2 partial/full redraw · btns 9-12 lane.
- **Redraw:** a full repaint on edits and view changes. A playhead move
  repaints only the two cells involved (partial), which assumes `draw_swap`
  keeps the framebuffer (unconfirmed on the device). **If moving playheads
  flicker, press key 2** for full repaints, and tell me which mode works.
- The press that loads the screen only loads it (no action).
- **Editing compiles nothing:** the screens write lane fields directly and
  clamp them themselves. The engine's setters (`edit.lua`) moved to `seq3l`,
  next to `preset`, since applying a slot is their only device caller.
  `seq3x` is back to Shred/Random/Zero (1.4 KB).

**v15.1 (after the first device run):**
- **Buttons acted twice:** the device fires the button event on press AND
  release, and `set_event` had replaced the template's mode setup. Every
  button event now sets momentary mode (`bmo(0)`) and acts only on
  `bst()==127`. `boot_sim` drives press + release and checks a single action.
- **Four lanes at start:** melody (quarters), 4x4 trig (quarters/4), 8-step
  bass (eighths) and hats (16ths, note 42). Costs 3.5 KB (wasm start 92.0 KB).
- **Draw-call budget:** a 4-lane Overview was 126 calls, and the harness
  dropped the frame's tail past ~110, so the device may queue draws the same
  way. Now there is one background strip per lane and only active cells are
  painted: Overview 66 calls, Focus 48 (`lane_sim` asserts <= 90).

**v15.2: Overview = general settings, Focus = lane settings.** The
Overview has a settings bar (`run`, `slot`, `save`, `load`, `draw`). Keys
4/5 step through it, the encoder press edits `slot` or fires the others, and
turning changes the value while editing (otherwise it selects the lane). In
Focus, keys 4/5 stay prev/next step. Key 2's redraw toggle became the `draw`
setting (P partial / F full), and key 1 alone switches views. Focus keeps
only lane rows (type, dims, div, ch, step + the step's values), which leaves
room for more lane settings.

wasm ladder (lane GUI): start 88.5 · screen 104.8 · edit 104.9 · Shred
106.8 · 96 pulses 107.3 · **save 114.6 KB, PASS**: the first build whose save
passes in the wasm. `node grid-wasm/seq3mem.mjs --shot <prefix>` also renders
the real screen to PNGs.

## v14 (2026-10-04): app start compiles only what start needs

v13 still blinked and restarted the module when it started. On the first
MIDI byte or key press, one callback compiled `seq3` + `seq3e` + `seq3ui`,
and `seq3ui` still contained the screen. A bundle runs every module body
when it is required, so the screen compiled at start too. v14:

- **The screen is its own bundle, `seq3s`.** It compiles on the first control
  press, never at start.
- **The setters are lazy:** `edit.lua` sits in the editing bundle `seq3x` and
  resolves through the engine's `__index`. The start demo (`device_boot`) and
  the headless sequence (`seq_data`) write lane fields directly.
- **Staged loader:** each `L()` call compiles at most ONE bundle (core, then
  engine, then midi + demo). The timer finishes a load that a MIDI byte or key
  press started; it never starts one, so cold boot stays bare. The console
  prints `seq3: start 1/3 core`, `2/3 engine`, `3/3 midi`.
- **Idle status view** repaints only when a playhead moves, not on every draw
  tick.
- Unused start-path code removed: the scale-name table, `Scales.step`,
  `device_boot.pulse`, `PPQN` and `DIMS` exports.

| | v13 | v14 |
|---|---|---|
| source compiled at app start | 17.1 KB (seq3 + seq3e + seq3ui incl. screen) | **13.7 KB** (5.6 + 5.1 + 3.0), at most 5.6 KB per callback |
| wasm resident after start + demo | 106.1 KB (screen included) | **88.4 KB** |
| wasm after first press (screen) | — | 100.3 KB |
| wasm after first edit / Shred (seq3x) | 108.7 KB | 108.7 KB |
| headless after 96 pulses | 97.3 KB | **90.3 KB** (~31 KB free) |

GUI upload is now SEVEN files: `seq3.lua`, `seq3e.lua`, `seq3ui.lua`,
`seq3s.lua`, `seq3x.lua`, `seq3p.lua`, `seq3l.lua`, plus the `seq3 core`
profile.

## v13 (2026-10-04): features cut until the text GUI fits

The `--gui=text` build died partway through its boot ladder on the device. The
core was cut, one feature at a time, measured each time with the wasm memory
ladder (`node grid-wasm/seq3mem.mjs [--headless]`, the server on 8080 running
from the repo root). It streams the real bundles into grid-wasm in device
order and prints the live heap after each stage.

**Calibration:** the wasm has at least ~20 KB less than the device. It even
failed a seq3ui that reached `screen ok` on hardware. A wasm PASS is strong
evidence a build fits; a FAIL proves nothing. The VM prints "Out of memory"
near 130 KB, but its real ceiling is about **117 KB**: the `free` stage
(1 KB allocations until refusal) found only ~8 KB free at 109 KB resident.

| step | cut | wasm: seq3e run | wasm: text GUI after key+draw | GUI ladder |
|---|---|---|---|---|
| baseline | — | 92.3 KB | — | **OOM running seq3ui** |
| 1 | dead code; source-name strings moved to lazy `seq3p` | 91.5 KB | 116.0 KB | OOM streaming seq3x |
| 2+3 | lane->lane routing; external MIDI sources; X/Y/value addressing | 86.5 KB | 110.8 KB | OOM at Shred |
| 4 | Mod -> Note, Gate -> Trig (Trig holds for its stepLength) | 85.3 KB | 109.0 KB | **PASS** |
| 5 | Gamut / Euclid / live generator -> one `randomize` (key 3) | 83.8 KB | 106.1 KB | **PASS** |

Headless ladder (seq3 + seq3e + seq3h): 108.8 KB -> **97.3 KB** resident after
96 pulses, ~24 KB free.

**Still open: save.** In the wasm, compiling the 3.6 KB save bundle (`seq3p`)
with the text GUI resident fails. A compile peaks at about resident + 3.5x the
source size. On the device this may well fit (see calibration). If it fails
there too, the next levers are trimming the random/previous/shift trigger
sources (~3 KB) or slimming `text_screen.lua`, which costs 22 KB resident
once running.

Device check: upload `--gui=text`, then report the last boot-ladder line and
the `seq3 mem KB` print at boot, after a key press, after Shred, and after a
save.

**v12: a HEADLESS target.** No GUI at all — the smallest thing that proves the
sequencer: sequence data loaded into the runtime, played back from MIDI clock,
with the lanes shown as text on the console.

## Two targets

```
sh tools/make_dist.sh --headless --install   -> profile "seq3 headless"
sh tools/make_dist.sh --install              -> profile "seq3 core"  (GUI)
python3 tools/gen_profile.py --probe --install -> profile "seq3 probe"
```

| target | upload | bytes | resident (host Lua) |
|---|---|---|---|
| **headless** | `seq3.lua` + `seq3e.lua` + `seq3h.lua` | **23069** | **79.1 KB** |
| GUI | + `seq3ui.lua` + `seq3x.lua` + `seq3p.lua` | 31547 (eager three) | 99.4 KB |

The GUI target ran out of memory initialising its modules. `screen.lua` +
`menu.lua` are **8.6 KB of stripped source** and the headless path never
compiles either.

**Why the "lazy screen" never helped:** a bundle runs *every* module body when
it is required (`R["screen"]=(function() … end)()`), so packing screen+menu
into `seq3ui` meant they compiled as soon as anything in that bundle was
needed — `midi_rx`'s `loadSCR()` laziness was defeated by bundle granularity.
Measured: `screen.lua` costs ~0 KB on the first key press because it was
already paid for. If the GUI target is revived, screen+menu need their own
bundle.

`engine.lua` also got its own bundle (`seq3e.lua`, 12.2 KB) so the largest
single compile drops from 19.4 KB to 12.2 KB — close to seq-1's proven 10.3 KB
maximum. The peak matters as much as the total when a compile is what fails.

## The headless build

Three lanes, one clock, different divisions — installed through the action API
by `src/device/seq_data.lua` (not a preset table: applying one needs
`preset.lua`, and the point is to compile as little as possible):

| lane | type | ch | advance | steps |
|---|---|---|---|---|
| L1 | note | 1 | 16ths | 16 (A-minor melody) |
| L2 | note | 2 | 8ths | 8 (bass) |
| L3 | trig | 10 | 16ths | 16 (drum pattern) |

Console output — the boot ladder once, then one line per lane on every timer
tick:

```
seq3h: engine
seq3h: engine ok
seq3h: sequence ok
seq3h: running
L1 note ch1 step 7/16 -
L2 note ch2 step 4/8 n45
L3 trig ch10 step 7/16 -
seq3 mem KB: <n>
```

The lanes advance at different rates against one clock, so the step numbers
drift apart — that is the proof they are independently sequencing.
`report()` runs only from the timer event, never from the pulse path, so
`Engine.onPulse` stays allocation-free (measured: **-0.12 KB drift over 500
pulses** through the real bundles).

Upload the three files, load **seq3 headless**, route MIDI clock in and the
module's MIDI out to the DAW. Press any key to arm without a DAW attached.

Verified by `tests/headless_sim.lua` (20 checks) against the real bundles: the
sequence installs 3 lanes, clock produces notes on ch1/ch2/ch10, L1 fires more
often than L2, note-ons are matched by note-offs, the report prints exactly one
line per lane — and **`seq3ui` is never loaded**.

## Why v8 died, and what v9 changed## Why v8 died, and what v9 changed

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

The setter collapse is done: it saved 3.3 KB, not the 12 KB once estimated
(see "Measured RAM" in `AGENTS.md`). The next lever is the **text-only GUI**:
`sh tools/make_dist.sh --gui=text` bundles `src/device/text_screen.lua` in
place of `screen.lua` + `menu.lua` (same `seq3ui.lua` name, same profile). One
page of key/value rows for the selected lane; resident after the screen loads
is ~85 KB vs ~95 KB for the colour GUI (host Lua, ratios not device truth).

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
| `seq3.lua` | 5581 | sources, scales, transport, lane | app start, stage 1 |
| `seq3e.lua` | 5144 | engine (pulse path, no setters) | app start, stage 2 |
| `seq3ui.lua` | 3069 | device_boot (demo), midi_rx | app start, stage 3 |
| `seq3s.lua` | 7432 (`--gui=lanes`) | the screen: lane_screen / text_screen / screen+menu | first control press |
| `seq3h.lua` | ~2900 | headless: seq_data, headless (instead of seq3ui) | headless start |
| `seq3x.lua` | 1452 | ops (shred / randomize / zero / rotate) | first Shred / Random / Zero |
| `seq3p.lua` | 3637 | source_names, persist | first save / load |
| `seq3l.lua` | 5511 | edit (setters), preset (loadPreset / copy) | first load (or any Engine.set*) |

Nothing at all loads at setup.

## Upload (Grid editor)

1. Delete ALL previously uploaded per-file modules (`engine`, `sources`,
   `screen`, `menu`, …) from the module's file storage.
2. Upload the **seven** GUI bundles under these **exact** names (delete any
   old `seq3*.lua` first):
   - `dist/seq3.lua`
   - `dist/seq3e.lua`
   - `dist/seq3ui.lua`
   - `dist/seq3s.lua`  (lazy — the screen, on the first control press)
   - `dist/seq3x.lua`  (lazy — must be present for Shred / Random / Zero)
   - `dist/seq3p.lua`  (lazy — must be present for slot save / load)
   - `dist/seq3l.lua`  (lazy — must be present for slot load: setters + preset)
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

The first save or load compiles `seq3p` (persist); a load also compiles
`seq3l` (preset). Slots land in the module's file storage as `s01.lua` … `s24.lua`, in the
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
