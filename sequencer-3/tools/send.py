#!/usr/bin/env python3
"""send.py — poke the running bridge's virtual MIDI input from a second terminal.

The bridge owns the virtual port `Sequencer3ClockIn`. This tool connects to it
and sends notes, CCs, or a short clock burst, so you can drive a MIDI-reactive
preset with no DAW. Leave the bridge running in terminal 1; use this in
terminal 2.

Examples:
    python3 tools/send.py list
    python3 tools/send.py note 36 100           # note 36 -> external.0
    python3 tools/send.py cc 23 64              # CC 23   -> external.3 value
    python3 tools/send.py clock --bpm 120 --seconds 8

Deps: pip3 install mido python-rtmidi
"""

import sys
import time
import argparse

try:
    import mido
except ImportError:
    sys.stderr.write("mido not installed. pip3 install mido python-rtmidi\n")
    sys.exit(1)


def open_out(port):
    try:
        return mido.open_output(port)
    except Exception as err:
        sys.stderr.write(f"could not open '{port}': {err}\n")
        names = ", ".join(mido.get_output_names()) or "(none)"
        sys.stderr.write(f"Is the bridge running? Output ports: {names}\n")
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser(description="Send MIDI to the seq3 bridge port.")
    ap.add_argument("--port", default="Sequencer3ClockIn")
    ap.add_argument("--channel", type=int, default=1)
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list")

    p_note = sub.add_parser("note")
    p_note.add_argument("note", type=int)
    p_note.add_argument("velocity", nargs="?", type=int, default=100)
    p_note.add_argument("--hold", type=float, default=0.05)

    p_cc = sub.add_parser("cc")
    p_cc.add_argument("cc", type=int)
    p_cc.add_argument("value", type=int)

    p_clk = sub.add_parser("clock")
    p_clk.add_argument("--bpm", type=float, default=120)
    p_clk.add_argument("--seconds", type=float, default=8)

    args = ap.parse_args()

    if args.cmd == "list":
        sys.stderr.write("output ports:\n")
        for name in mido.get_output_names():
            sys.stderr.write("  " + name + "\n")
        return

    out = open_out(args.port)
    ch = args.channel - 1

    if args.cmd == "note":
        out.send(mido.Message("note_on", note=args.note, velocity=args.velocity, channel=ch))
        time.sleep(args.hold)
        out.send(mido.Message("note_off", note=args.note, velocity=0, channel=ch))
    elif args.cmd == "cc":
        out.send(mido.Message("control_change", control=args.cc, value=args.value, channel=ch))
    elif args.cmd == "clock":
        interval = 60.0 / (args.bpm * 24.0)
        out.send(mido.Message("start"))
        end = time.time() + args.seconds
        while time.time() < end:
            out.send(mido.Message("clock"))
            time.sleep(interval)
        out.send(mido.Message("stop"))
    sys.stderr.write(f"[send] {args.cmd} on {args.port} ch{args.channel}\n")


if __name__ == "__main__":
    main()
