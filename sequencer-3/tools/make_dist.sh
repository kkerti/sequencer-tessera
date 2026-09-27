#!/bin/sh
# make_dist.sh — assemble sequencer-3/dist.
#
# v6 SEQ-2 SHAPE: the 13-file FS-module dist cold-boot-dead while seq-2's 5
# pre-linked bundles cold-boot fine. So the dist is now TWO pre-linked text
# bundles (require resolves inside the bundle) + the eager profile, exactly
# the shape of seq-2's working cold boot:
#   dist/seq3.lua     core chain (~26 KB, the single resident chunk)
#   dist/seq3ui.lua   boot + midi_rx + screen + menu (~10.5 KB)
set -e
cd "$(dirname "$0")/.."

# Bundles (comment-stripped, pre-linked by build_bundles.py)
python3 tools/build_bundles.py
luac -p dist/seq3.lua dist/seq3ui.lua

# Profile
python3 tools/gen_profile.py "$@"

echo
echo "dist (upload both bundles + load the profile):"
ls -la dist/seq3.lua dist/seq3ui.lua "dist/seq3 core.json"
