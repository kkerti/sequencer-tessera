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
#   dist/seq3f.lua    --gui=lanes only: the Focus rows, on the first Focus
#   dist/seq3x.lua    LAZY ops: shred/randomize/zero/rotate
#   dist/seq3p.lua    LAZY save: persist + source names
#   dist/seq3l.lua    LAZY load: setters (edit) + preset (loadPreset / copy)
#
# Two targets:
#   sh tools/make_dist.sh --headless [--install]   -> "seq3 headless" profile
#        upload seq3.lua + seq3e.lua + seq3h.lua        (3 files, ~23 KB)
#   sh tools/make_dist.sh [--install]              -> "seq3 core" profile (GUI)
#        upload seq3.lua + seq3e.lua + seq3ui.lua + seq3s.lua + seq3x.lua
#               + seq3p.lua + seq3l.lua
#   add --gui=text to bundle the text-only key/value screen into seq3s.lua,
#   or --gui=lanes for the lane GUI (Overview + Focus, lane_screen.lua)
#        (src/device/text_screen.lua) instead of the colour screen + menu
set -e
cd "$(dirname "$0")/.."

python3 tools/build_bundles.py "$@"
FOCUS=""; [ -f dist/seq3f.lua ] && FOCUS=dist/seq3f.lua
luac -p dist/seq3.lua dist/seq3e.lua dist/seq3h.lua dist/seq3ui.lua dist/seq3s.lua \
        dist/seq3x.lua dist/seq3p.lua dist/seq3l.lua $FOCUS

python3 tools/gen_profile.py "$@"

# The editor loads profiles from its configs folder, NOT from dist/. A build
# without --install leaves the editor on the old profile (this cost a device
# cycle: v13-v15 ran on a stale v12 profile — double-firing buttons, the old
# all-at-once loader). Warn loudly whenever the installed copy differs.
CFG="$HOME/Documents/grid-userdata/configs"
case "$*" in *--headless*) PROF="seq3 headless.json" ;; *) PROF="seq3 core.json" ;; esac
# Compare the event scripts only: every build stamps a new id + timestamps.
if [ -f "$CFG/$PROF" ] && ! python3 -c 'import json,sys; a,b=(json.load(open(f))["configs"] for f in sys.argv[1:]); sys.exit(a!=b)' "dist/$PROF" "$CFG/$PROF"; then
    echo
    echo "WARNING: the editor's '$PROF' differs from dist/ — the module will run"
    echo "         the OLD profile. Re-run with --install, then load it in the editor."
fi

echo
case "$*" in
*--headless*)
    echo "HEADLESS — upload these three, then load the 'seq3 headless' profile:"
    ls -la dist/seq3.lua dist/seq3e.lua dist/seq3h.lua "dist/seq3 headless.json"
    ;;
*)
    echo "GUI — upload these files, then load the 'seq3 core' profile:"
    ls -la dist/seq3.lua dist/seq3e.lua dist/seq3ui.lua dist/seq3s.lua dist/seq3x.lua \
           dist/seq3p.lua dist/seq3l.lua $FOCUS "dist/seq3 core.json"
    ;;
esac
