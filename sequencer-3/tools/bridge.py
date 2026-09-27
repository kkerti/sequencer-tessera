#!/usr/bin/env python3
"""bridge.py — macOS MIDI <-> Lua sequencer bridge (full duplex, one command).

Spawns the Lua sequencer as a coprocess and wires it to virtual MIDI ports:
  - MIDI clock/start/stop IN  -> the Lua process's stdin  (CLK / START / STOP)
  - the Lua process's stdout  -> MIDI notes/CC OUT        (ON / OFF / CC lines)

Usage:
    python3 tools/bridge.py --lua "lua proto/term/main.lua"

Lines typed into this terminal are forwarded to the sequencer, so you can
`SAVE 20` / `LOAD 20` a slot mid-session.

Then in Ableton: enable the "Sequencer3ClockIn" output (send MIDI clock to it),
and record/monitor from "Sequencer3NotesOut". Set each Ableton track's channel
to match the sequencer lane's channel.

Deps: pip3 install mido python-rtmidi
"""

import sys
import shlex
import argparse
import threading
import subprocess

try:
    import mido
except ImportError:
    sys.stderr.write("mido not installed. pip3 install mido python-rtmidi\n")
    sys.exit(1)


def midi_in_to_proc(proc, port_name):
    """MIDI clock/transport -> the Lua process's stdin."""
    in_port = mido.open_input(port_name, virtual=True)
    sys.stderr.write(f"[bridge] virtual MIDI input open: {port_name}\n")
    for msg in in_port:
        if proc.poll() is not None:
            break
        line = None
        if msg.type == 'clock':
            line = "CLK"
        elif msg.type == 'start':
            line = "START"
        elif msg.type == 'stop':
            line = "STOP"
        elif msg.type == 'continue':
            line = "START"
        elif msg.type == 'note_on':
            line = f"NOTE {msg.note} {msg.velocity} {msg.channel + 1}"
        elif msg.type == 'control_change':
            line = f"CC {msg.control} {msg.value} {msg.channel + 1}"
        if line:
            try:
                proc.stdin.write(line + "\n")
                proc.stdin.flush()
            except BrokenPipeError:
                break


def proc_to_midi_out(proc, port_name):
    """The Lua process's stdout (ON/OFF/CC lines) -> MIDI out."""
    out_port = mido.open_output(port_name, virtual=True)
    sys.stderr.write(f"[bridge] virtual MIDI output open: {port_name}\n")
    for raw in proc.stdout:
        line = raw.strip()
        if not line:
            continue
        parts = line.split()
        try:
            if parts[0] == "ON":
                pitch, vel, ch = int(parts[1]), int(parts[2]), int(parts[3])
                out_port.send(mido.Message('note_on', note=pitch,
                                           velocity=vel, channel=ch - 1))
            elif parts[0] == "OFF":
                pitch, ch = int(parts[1]), int(parts[2])
                out_port.send(mido.Message('note_off', note=pitch,
                                           velocity=0, channel=ch - 1))
            elif parts[0] == "CC":
                cc, val, ch = int(parts[1]), int(parts[2]), int(parts[3])
                out_port.send(mido.Message('control_change', control=cc,
                                           value=val, channel=ch - 1))
            else:
                sys.stderr.write(f"[lua] {line}\n")   # passthrough / logs
        except (ValueError, IndexError):
            sys.stderr.write(f"[bridge] bad line: {line}\n")


def console_to_proc(proc):
    """Lines typed in this terminal -> the Lua process's stdin.

    This is how SAVE/LOAD reach the sequencer while a session is running:
    type `SAVE 20` or `LOAD 20` here. Also accepts START/STOP/QUIT.
    """
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        if proc.poll() is not None:
            break
        try:
            proc.stdin.write(line + "\n")
            proc.stdin.flush()
        except (BrokenPipeError, ValueError):
            break


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lua", required=True,
                    help='command to launch the sequencer, e.g. "lua proto/term/main.lua"')
    ap.add_argument("--in-port", default="Sequencer3ClockIn")
    ap.add_argument("--out-port", default="Sequencer3NotesOut")
    args = ap.parse_args()

    proc = subprocess.Popen(shlex.split(args.lua),
                            stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE,
                            text=True, bufsize=1)
    sys.stderr.write(f"[bridge] spawned: {args.lua}\n")

    threading.Thread(target=midi_in_to_proc,
                     args=(proc, args.in_port), daemon=True).start()
    threading.Thread(target=console_to_proc, args=(proc,), daemon=True).start()
    sys.stderr.write("[bridge] type SAVE <slot> / LOAD <slot> here "
                     "(also START / STOP / QUIT)\n")
    try:
        proc_to_midi_out(proc, args.out_port)   # blocks until Lua exits
    except KeyboardInterrupt:
        pass
    finally:
        if proc.poll() is None:
            proc.terminate()


if __name__ == "__main__":
    main()
