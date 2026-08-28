# sequencer

4-track, externally-clocked, MIDI step sequencer in Lua 5.4 for Intech Studio
Grid VSN1 hardware.

See `AGENTS.md` for design rules and project layout.

## Naming scheme

Product line uses a **stellar-clock series** — each generation is named after a
pulsing celestial source, so they stay differentiable as the line grows:

| Generation | Name | Why |
|---|---|---|
| sequencer-1 (this repo) | **Pulsar** | rotating neutron star; the most precise pulse train in nature — the literal step/pulse machine |
| sequencer-2 | **Magnetar** | dense, high-energy, generative |
| _future_ | Quasar, Blazar, Cepheid, Tachyon | reserved rungs on the same ladder |

Names are profile/product labels only for now; no files, bundle names, or
require-paths are renamed.

## Quick start (macOS)

```sh
lua tests/run.lua          # run the test suite
lua main.lua               # run the engine against a test patch, log to sequencer.log
python3 tools/bridge.py    # MIDI clock in, MIDI notes out (virtual port)
lua tools/build_dist.lua   # build dist/sequencer.lua for the Grid module
```

## Status

Greenfield rebuild in progress.
