#!/usr/bin/env python3
"""bridge.py — macOS MIDI <-> stdio bridge for the Lua sequencer harness.

Full duplex:
  - Receives MIDI clock + Start/Stop on a virtual input port.
  - Emits one stdin line per event to the Lua process: START / STOP / CLK
  - Reads NOTE events from the Lua process stdout and forwards to a virtual
    output port.

Usage:
    python3 tools/bridge.py | lua main.lua
or, for full duplex:
    mkfifo /tmp/seqin /tmp/seqout
    python3 tools/bridge.py < /tmp/seqout > /tmp/seqin &
    lua main.lua < /tmp/seqin > /tmp/seqout

Simpler: run as a coprocess and have Lua read stdin / write stdout while
this script connects to MIDI via mido.

Stdout protocol from Lua (consumed here):
    ON  <pitch> <vel> <ch>
    OFF <pitch>      <ch>
"""

import sys
import threading

try:
    import mido
except ImportError:
    sys.stderr.write("mido not installed. pip3 install mido python-rtmidi\n")
    sys.exit(1)

CLOCK = 0xF8
START = 0xFA
STOP  = 0xFC
CONT  = 0xFB

# --- MIDI -> stdout (drives Lua) -----------------------------------------
def midi_in_loop(port_name="SequencerClockIn"):
    in_port = mido.open_input(port_name, virtual=True)
    sys.stderr.write(f"[bridge] virtual MIDI input open: {port_name}\n")
    for msg in in_port:
        if msg.type == 'clock':
            sys.stdout.write("CLK\n"); sys.stdout.flush()
        elif msg.type == 'start':
            sys.stdout.write("START\n"); sys.stdout.flush()
        elif msg.type in ('stop',):
            sys.stdout.write("STOP\n"); sys.stdout.flush()
        elif msg.type == 'continue':
            sys.stdout.write("START\n"); sys.stdout.flush()

# --- stdin -> MIDI (forwards Lua's notes) --------------------------------
def stdin_to_midi_loop(port_name="SequencerNotesOut"):
    out_port = mido.open_output(port_name, virtual=True)
    sys.stderr.write(f"[bridge] virtual MIDI output open: {port_name}\n")
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        parts = line.split()
        try:
            if parts[0] == "ON":
                pitch, vel, ch = int(parts[1]), int(parts[2]), int(parts[3])
                msg = mido.Message('note_on', note=pitch, velocity=vel, channel=ch-1)
                sys.stderr.write(f"[bridge>] {msg}\n"); sys.stderr.flush()
                out_port.send(msg)
            elif parts[0] == "OFF":
                pitch, ch = int(parts[1]), int(parts[2])
                msg = mido.Message('note_off', note=pitch, velocity=0, channel=ch-1)
                sys.stderr.write(f"[bridge>] {msg}\n"); sys.stderr.flush()
                out_port.send(msg)
        except (ValueError, IndexError):
            sys.stderr.write(f"[bridge] bad line: {line}\n")

if __name__ == "__main__":
    # Run MIDI input in a thread; main thread does stdin->MIDI.
    t = threading.Thread(target=midi_in_loop, daemon=True)
    t.start()
    stdin_to_midi_loop()
