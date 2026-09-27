# dist/ — seq-3 on the Grid VSN1

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
