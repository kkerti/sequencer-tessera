#!/usr/bin/env python3
# bridge.py
# Reads MIDI events from stdin (written by main.lua) and forwards them
# to a virtual MIDI port that appears in Ableton as "Sequencer".
#
# Line format from Lua:  NOTE_ON <pitch> <velocity> <channel>
#                         NOTE_OFF <pitch> <channel>
#
# Usage:
#   lua main.lua | python3 bridge.py

import sys
import rtmidi

midiOut = rtmidi.MidiOut()
midiOut.open_virtual_port("Sequencer")
print("[bridge] Virtual MIDI port 'Sequencer' open. Waiting for events...", flush=True)

try:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        parts = line.split()

        if parts[0] == "NOTE_ON" and len(parts) == 4:
            pitch    = int(parts[1])
            velocity = int(parts[2])
            channel  = int(parts[3]) - 1  # Lua channels are 1-based; MIDI is 0-based
            status   = 0x90 | (channel & 0x0F)
            midiOut.send_message([status, pitch, velocity])

        elif parts[0] == "NOTE_OFF" and len(parts) == 3:
            pitch   = int(parts[1])
            channel = int(parts[2]) - 1
            status  = 0x80 | (channel & 0x0F)
            midiOut.send_message([status, pitch, 0])

except KeyboardInterrupt:
    pass
finally:
    # Send CC#123 (All Notes Off) on all 16 MIDI channels as a safety net.
    # This catches any notes the Lua side failed to turn off (race conditions,
    # short-gate timers that didn't fire before exit, etc.).
    for ch in range(16):
        midiOut.send_message([0xB0 | ch, 123, 0])  # CC#123 All Notes Off
    del midiOut
