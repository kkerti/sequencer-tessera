#!/bin/sh
# make_dist.sh — assemble sequencer-3/dist.
#
# Bundles are pre-linked plain text (require resolves through a name->bundle
# map in each bundle's shim). The profile's setup requires NOTHING; the chain
# compiles on the first MIDI byte or key press.
#
#   dist/seq3.lua     sources/scales/transport/lane   (~7.8 KB)
#   dist/seq3e.lua    engine                          (~12.2 KB)
#   dist/seq3h.lua    HEADLESS: 3-lane sequence + clock->MIDI + lane report
#   dist/seq3ui.lua   GUI start: device_boot/midi_rx (no screen)
#   dist/seq3s.lua    GUI screen: screen+menu, or text_screen (--gui=text);
#                     compiled on the first control press, never at start
#   dist/seq3x.lua    LAZY editing: setters + shred/randomize/zero/rotate
#   dist/seq3p.lua    LAZY save: persist + source names
#   dist/seq3l.lua    LAZY load: preset (loadPreset / copy)
#
# Two targets:
#   sh tools/make_dist.sh --headless [--install]   -> "seq3 headless" profile
#        upload seq3.lua + seq3e.lua + seq3h.lua        (3 files, ~23 KB)
#   sh tools/make_dist.sh [--install]              -> "seq3 core" profile (GUI)
#        upload seq3.lua + seq3e.lua + seq3ui.lua + seq3s.lua + seq3x.lua
#               + seq3p.lua + seq3l.lua
#   add --gui=text to bundle the text-only key/value screen into seq3s.lua
#        (src/device/text_screen.lua) instead of the colour screen + menu
set -e
cd "$(dirname "$0")/.."

python3 tools/build_bundles.py "$@"
luac -p dist/seq3.lua dist/seq3e.lua dist/seq3h.lua dist/seq3ui.lua dist/seq3s.lua \
        dist/seq3x.lua dist/seq3p.lua dist/seq3l.lua

python3 tools/gen_profile.py "$@"

echo
case "$*" in
*--headless*)
    echo "HEADLESS — upload these three, then load the 'seq3 headless' profile:"
    ls -la dist/seq3.lua dist/seq3e.lua dist/seq3h.lua "dist/seq3 headless.json"
    ;;
*)
    echo "GUI — upload these seven, then load the 'seq3 core' profile:"
    ls -la dist/seq3.lua dist/seq3e.lua dist/seq3ui.lua dist/seq3s.lua dist/seq3x.lua \
           dist/seq3p.lua dist/seq3l.lua "dist/seq3 core.json"
    ;;
esac
