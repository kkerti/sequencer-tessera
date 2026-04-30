# 2026-04-24 — Grid prefix-aware require, end-to-end working

> **SUPERSEDED (2026-04-27).** `tools/gridsplit.lua` and the `--require-prefix` flag have been removed. Compiled songs ship as one file; literal-path requires (e.g. `require("/player/player")`) are still hand-written into the INIT block (Grid's `require()` still doesn't do `?` substitution). See `docs/ARCHITECTURE.md`.


## Status: WORKING ON DEVICE ✅

The lite-player + compiled-song stack is playing on the Grid module. MIDI
output verified.

## What was fixed

Grid firmware's `require()` does NOT do standard `package.path` `?` substitution
(diagnosed by user: error log showed `no file '/tt/.lua'` literally). Module
names must be passed as full literal paths, e.g. `require("/player/seq_player")`.

Both build tools now bake the prefix into every internal require so a chunk
can self-load and resolve its dependencies.

### `tools/gridsplit.lua`
- New flag: `--require-prefix <prefix>` (e.g. `/player`).
- Threads through 4 require emission sites:
  1. Root file's `package.loaded[...] = Module` registration key.
  2. Root file's `require("<prefix>/<name>_N")` calls to sub-chunks.
  3. Each chunk's `local Module = require("<prefix>/<name>")` self-require.
  4. Each chunk's cross-module dep requires (e.g. `local Utils = require(...)`).

### `tools/song_compile.lua`
- Same `--require-prefix` flag.
- Sidecar requires inside compiled song file use the prefix:
  `s.atPulse = require("/dark_groove/dark_groove_atpulse_1")`.

### `grid_module.lua`
- INIT/TIMER blocks updated to use `/player/seq_player` and
  `/dark_groove/dark_groove`.

## Folder-per-library layout

User chose this layout because it matches how libraries are uploaded /
removed on Grid (whole folder at a time):

```
/player/         ← grid/player/*  (6 files: seq_player + 5 chunks)
/dark_groove/    ← grid/dark_groove/*  (6 files: song + 5 sidecars)
```

## Build commands (Grid)

```sh
rm -rf grid
lua tools/gridsplit.lua  --require-prefix /player       --outdir grid/player        player_lite/player.lua
lua tools/song_compile.lua --require-prefix /dark_groove --outdir grid/dark_groove   songs/dark_groove.lua
```

Then upload `grid/player/*` to `/player/` and `grid/dark_groove/*` to
`/dark_groove/` on the module. Paste INIT and TIMER blocks from
`grid_module.lua`.

## Run commands (macOS dev)

For local dev with the Python MIDI bridge:

```sh
# 1. Compile song WITHOUT prefix (so sidecars resolve via local package.path)
lua tools/song_compile.lua songs/dark_groove.lua

# 2. Run the lite stack piped to the bridge
lua main_lite.lua | python3 bridge.py
```

`main_lite.lua` adds `compiled/?.lua` to `package.path` so the song's
sidecar requires resolve. In Ableton enable "Sequencer" as a MIDI input.

## Verification

- `/tmp/gridsim/` simulation with a custom literal-path searcher: player +
  song loaded, 4s of playback → 43 NOTE_ON / 41 NOTE_OFF.
- macOS `main_lite.lua`: emits NOTE_ON/OFF on the bridge protocol; tick
  interval 63ms (BPM 118, ppb 4).
- Grid module: user confirmed playing.

## INIT / TIMER (current pasted version)

INIT (element 0):
```lua
local Player = require("/player/seq_player")
local song   = require("/dark_groove/dark_groove")

SEQ_CLOCK_MS = 0
SEQ_PLAYER   = Player.new(song, function() return SEQ_CLOCK_MS end)
SEQ_INTERVAL = math.floor(SEQ_PLAYER.pulseMs / 2)

function SEQ_EMIT(eventType, pitch, velocity, channel)
    if eventType == "NOTE_ON" then
        midi_send(channel, 0x90, pitch, velocity)
    else
        midi_send(channel, 0x80, pitch, 0)
    end
end

Player.start(SEQ_PLAYER)
element_timer_start(0, SEQ_INTERVAL)
```

TIMER (element 0):
```lua
local Player = require("/player/seq_player")
SEQ_CLOCK_MS = SEQ_CLOCK_MS + SEQ_INTERVAL
Player.tick(SEQ_PLAYER, SEQ_EMIT)
element_timer_start(self:element_index(), SEQ_INTERVAL)
```

## Files added / changed this session

- `tools/gridsplit.lua` — `--require-prefix` flag, `gridRequireName()` helper.
- `tools/song_compile.lua` — `--require-prefix` flag for sidecars.
- `grid_module.lua` — uses prefixed require paths.
- `main_lite.lua` — NEW. Dev harness for lite-player + compiled-song stack.

## Next steps (optional)

- Add button-mapped controls (start/stop/BPM knob).
- Multi-song selection (require by song name from a button bank).
- Identifier-shortening minifier pass for headroom.
- Compile-time scale/transpose baking if more songs prove the workflow.
