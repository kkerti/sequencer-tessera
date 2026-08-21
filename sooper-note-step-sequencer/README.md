# sequencer

4-track, externally-clocked, MIDI step sequencer in Lua 5.4 for Intech Studio
Grid VSN1 hardware.

See `AGENTS.md` for design rules and project layout.

## Quick start (macOS)

```sh
lua tests/run.lua          # run the test suite
lua main.lua               # run the engine against a test patch, log to sequencer.log
python3 tools/bridge.py    # MIDI clock in, MIDI notes out (virtual port)
lua tools/build_dist.lua   # build dist/sequencer.lua for the Grid module
```

## Status

Greenfield rebuild in progress.
