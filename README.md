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
