# How to start the sequencer?
lua main.lua | python3 bridge.py

# Run feature showcase sequence scenarios (listenable + assertable):
lua tests/sequence_runner.lua all`

# Start the python server
python3 -m http.server 8080

# Dry run — validates all chunks fit in 880 chars, prints report, writes nothing
lua tools/gridsplit.lua --dry

# Full run — writes all chunk files to grid/
lua tools/gridsplit.lua

# write the player for copy to grid
lua tools/gridsplit.lua player/player.lua song_loader.lua --outdir grid/player

# compile song and the player to upload for grid
rm -rf grid/dark_groove
lua tools/song_compile.lua --require-prefix /dark_groove --outdir grid/dark_groove songs/dark_groove.lua

## compile song BUT direct upload
lua tools/song_compile.lua --no-split --outdir grid/dark_groove_single songs/dark_groove.lua
