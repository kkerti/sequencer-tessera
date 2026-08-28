# CLAUDE.md — sequencer-2

Claude Code init for this repo. Read `AGENTS.md` next (full guidance), then
`docs/ARCHITECTURE.md` (deep design). This file is the short contract.

## What this is

A polyphonic, externally-clocked MIDI step sequencer written in **Lua 5.4**,
designed to run on **Intech Studio Grid VSN1** hardware. Modelled on the
**Squarp Hermod+** workflow (`docs/manual/HERMODPLUS_manual*.pdf`): tracks hold
patterns and an effect rack; effects transform recorded/incoming notes into the
played sequence in real time.

This is a **greenfield successor** to `../sequencer-1` (mono, packed-int,
fixed-grid). We reuse its *proven infrastructure* (the `bridge.py` MIDI relay,
the VSN1 draw model, the Lua-chunk persistence idea, the HAL→Core→App layering)
but **not** its data model — seq-2 is polyphonic and event-based.

## Locked decisions (do not relitigate without asking)

1. **Language: Lua 5.4.** Pure Lua Core, no C, no external deps at runtime.
2. **Data model: polyphonic event list, stored structure-of-arrays.** A pattern
   is parallel numeric arrays (`pitch[] start[] len[] vel[]`), NOT array-of-tables.
   This gives chords + off-grid recording with bounded RAM and no per-note GC.
3. **Effects run LIVE, per pulse.** Note events flow through the track's effect
   chain every clock pulse. The chain must be **allocation-free** and reuse a
   fixed scratch event buffer.
4. **Playback is the hot path and has absolute priority.** `onPulse()` allocates
   nothing and never blocks on IO, edits, or file swaps. Everything else is
   secondary and must yield to it.
5. **RAM is the primary constraint.** Only the active sequence's patterns live in
   RAM. Inactive tracks/patterns are Lua-chunk files on the Grid FS, swapped on
   selection (Hermod "synchronized project swap"). See `persist` + `docs`.
6. **Start with 2 tracks**, not 8. Enough to prove the architecture without
   overloading the controller.
7. **Layers: HAL → Core → App.** Core never knows a screen exists and never
   calls a driver — it returns events. App reads Core tables and calls setters.
8. **First effect rack: SCALE, RANGE (performance limiter), RANDOM/CHANCE.**
   No generator (EUCLID/ARP) in milestone 1 — patterns come from recording +
   randomize.

## Prototyping stack

One Lua Core, two frontends:
- `proto/term/` — **headless terminal harness**. Runs the live engine; feeds
  `tools/bridge.py` → Ableton over a virtual MIDI port. Per-track MIDI channel
  configurable. This is the audio/playback path.
- `screens/` — **grid-wasm screen scripts**. Flat Grid VM Lua (no `require`,
  global state, `ggd*` draw primitives, ~2 KB init budget) rendered headlessly
  to PNG via `../grid-wasm/screenshot.mjs` (Playwright). This is the on-device
  screen path — most hardware-faithful, no game engine. (LÖVE was evaluated and
  dropped: no game-engine dependency.)

## Commands (as they come online)

```
python3 tools/bridge.py --lua "lua proto/term/main.lua"   # terminal → Ableton (external clock)
lua proto/term/main.lua --bpm 120                          # internal test clock → stdout
lua tests/run.lua                                           # Core unit tests
lua5.4 tools/build.lua                                       # → 5 lean TEXT bundles in dist/ + preview
lua5.4 tests/dist_smoke.lua                                  # dist-bundle smoke (load order + device-code rules)
python3 tools/gen_profile.py --install                      # → dist/Sequencer Magnetar.json + grid-userdata (see docs/DEPLOY.md)

# screen proto (grid-wasm) — serve from the `sequencer` dir (has grid-wasm/ + screens symlink):
cd .. && python3 -m http.server 8080
#   interactive: open http://localhost:8080/grid-wasm/index.html, pick "seq2_screen" in the dropdown
#   headless PNG: cd grid-wasm && node screenshot.mjs ../sequencer-2/screens/seq2_screen.lua 128 shot.png
```

Dev machine runs Lua 5.5 (compatible superset of the 5.4 Grid target).

## Hardware target (Grid VSN1)

320×240 screen, ≤20 fps, buffered draw + manual `draw_swap()` (one swap/frame).
Control surface: **4 function buttons + 1 large push encoder + 8 buttons**.
Control can be handed to other Grid controllers (e.g. a 16-button module as a
step keyboard for quantized recording). Screen splits into two 320×120 halves:
top = note/playhead view, bottom = menu/parameter context.

## When in doubt

Ask. Greenfield: pause and confirm rather than calcify an assumption into the
architecture. Never port seq-1's packed-int mono model — re-derive from here.
