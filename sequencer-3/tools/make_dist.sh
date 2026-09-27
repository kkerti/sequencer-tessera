#!/bin/sh
# make_dist.sh — assemble sequencer-3/dist.
#
# v6 SEQ-2 SHAPE: the 13-file FS-module dist cold-boot-dead while seq-2's 5
# pre-linked bundles cold-boot fine. So the dist is now TWO pre-linked text
# bundles (require resolves inside the bundle) + the eager profile, exactly
# the shape of seq-2's working cold boot:
#   dist/seq3.lua     core chain (sources/scales/transport/lane/engine)
#   dist/seq3ui.lua   boot + midi_rx + screen + menu
#   dist/seq3x.lua    LAZY ops: shred/zero/rotate + gamut/euclid + addressing
#   dist/seq3p.lua    LAZY persist: preset + slot save/load
set -e
cd "$(dirname "$0")/.."

# Bundles (comment-stripped, pre-linked by build_bundles.py)
python3 tools/build_bundles.py
luac -p dist/seq3.lua dist/seq3ui.lua dist/seq3x.lua dist/seq3p.lua

# Profile
python3 tools/gen_profile.py "$@"

echo
echo "dist (upload all four bundles + load the profile):"
ls -la dist/seq3.lua dist/seq3ui.lua dist/seq3x.lua dist/seq3p.lua "dist/seq3 core.json"
