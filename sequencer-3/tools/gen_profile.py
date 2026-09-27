#!/usr/bin/env python3
"""gen_profile.py — generate a loadable Grid VSN1R profile for seq-3.

v6 EAGER, SEQ-2 SHAPE: the 13-file FS-module dist cold-boot-dead while
seq-2's 5 pre-linked bundles cold-boot fine on the same module. So v6 drops
the FS-module approach: tools/build_bundles.py packs everything into TWO
pre-linked text bundles (require resolves inside the bundle), and setup
requires + inits + fills the demo eagerly — byte-for-byte the shape of
seq-2's proven setup (14.8 KB at setup, cold boots).

Wiring (element skeleton = seq-2's proven clone, tools/vsn1r_template.json):
  el 255 ev0   setup: require seq3 + seq3ui, demo, grxm + rtmrx_cb
  el 255 ev6   timer: mem diagnostic print
  el 13  ev8   draw: RX.ui(self) (dirty-flag draw from the bundle)
  el 8   ev7   encoder: relative-mode setup + RX.turn(delta)
  el 0-12 ev3  keyswitches/buttons -> RX.key/btn/press

Bundles (dist/seq3.lua, dist/seq3ui.lua) upload SEPARATELY under those exact
names (see dist/README.md).
Run:  python3 tools/build_bundles.py && python3 tools/gen_profile.py [--install]
"""
import json, os, sys, time, uuid, copy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TEMPLATE = os.path.join(HERE, "vsn1r_template.json")

# --- element 255, event 0: system setup (<= 900 chars) ----------------------
# v7, SEQ-1 WIRING (the project with a proven cold boot):
#   - midi_send(ch, st, p1, p2) — NOT gms() (seq-1 never used gms)
#   - rtmrx_cb assigned directly, NO grxm() arming call (seq-1 arms nothing;
#     grxm at setup is our prime crash suspect)
#   - requires all three bundles eagerly (seq3 core, seq3ui screen, seq3x
#     lazy periphery so the engine's lazy loaders resolve). seq-1's proven
#     setup loaded ~10 KB eagerly; ours is ~37 KB across three chunks —
#     if this still dies cold, the next cut is requiring seq3x on first use.
SETUP = (
    '--[[@cb]] SEQ3=require("seq3")'
    'UI=require("seq3ui")'
    'X=require("seq3x")'
    'RX=UI.midi_rx '
    'RX.ensure() '
    'self.rtmrx_cb=function(self,h,t)RX.handle(t,midi_send)end'
)


def press_cb(call):
    return f"--[[@cb]] if RX then {call} end"


# --- element 255, event 6: timer — RAM diagnostic ---------------------------
# Reading collectgarbage("count") is passive (seq-2's poison was
# collectgarbage("collect") and package.loaded manipulation, not the count).
MEM = '--[[@cb]] print("seq3 mem KB: " .. collectgarbage("count"))'

# --- element 13, event 8: screen draw (<= 900 chars) ------------------------
# The adapter (inside the pre-linked bundle) draws the live view when dirty.
DRAW = "--[[@cb]] if RX then RX.ui(self) end"

# Encoder turn keeps its --[[@sen]] relative-mode setup (epmo(1)) — the only
# way epva() yields a ±1 delta on device (seq-2 hardware finding).
ENCODER_TURN = (
    '--[[@sen]] self:epmo(1)self:epv0(64)self:epmi(0)self:epma(127)self:epse(1)'
    '--[[@cb]] if RX then RX.turn(self:epva()-64) end'
)

# Control elements: keyswitches 0-7 -> RX.key(i), encoder click -> RX.press(),
# small buttons 9-12 -> RX.btn(i). Everything is already loaded at setup.
CB_FULL = {}
for _k in range(0, 8):
    CB_FULL[(_k, 3)] = press_cb(f"RX.key({_k})")
CB_FULL[(8, 3)] = press_cb("RX.press()")
for _b in range(9, 13):
    CB_FULL[(_b, 3)] = press_cb(f"RX.btn({_b})")

assert len(SETUP) <= 900, f"setup event {len(SETUP)} > 900 chars"
assert len(MEM) <= 900, f"mem event {len(MEM)} > 900 chars"
assert len(DRAW) <= 900, f"draw event {len(DRAW)} > 900 chars"
assert len(ENCODER_TURN) <= 900, f"encoder turn {len(ENCODER_TURN)} > 900 chars"
for k, v in CB_FULL.items():
    assert len(v) <= 900, f"event {k} callback too long"


def validate_events(profile):
    """Compile every event config with luac -p before writing the profile.

    The @-markers (--[[@cb]], --[[@sen]], ...) are plain Lua block comments,
    so each config IS compilable Lua source. This catches glued-keyword bugs
    (adjacent Python literals turned 'end'+'self' into 'endself' — the module
    rejected that profile as corrupt).
    """
    import subprocess, tempfile
    for c in profile["configs"]:
        for e in c["events"]:
            cfg = e.get("config", "")
            if not cfg.strip():
                continue
            with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False) as f:
                f.write(cfg)
                path = f.name
            r = subprocess.run(["luac", "-p", path], capture_output=True, text=True)
            os.unlink(path)
            if r.returncode != 0:
                el = c.get("controlElementNumber")
                raise SystemExit(
                    f"event el {el} ev {e['event']} is not valid Lua:\n"
                    f"{r.stderr.strip()}\nconfig: {cfg!r}"
                )
    print("all event configs compile (luac -p)")


def set_event(element, event_id, config):
    for e in element["events"]:
        if e["event"] == event_id:
            e["config"] = config
            return
    element["events"].append({"event": event_id, "config": config})


def main():
    prof = copy.deepcopy(json.load(open(TEMPLATE)))
    by = {c["controlElementNumber"]: c for c in prof["configs"]}

    set_event(by[255], 0, SETUP)
    set_event(by[255], 6, MEM)
    set_event(by[13], 8, DRAW)
    set_event(by[8], 7, ENCODER_TURN)
    for (el, ev), cb in CB_FULL.items():
        set_event(by[el], ev, cb)

    validate_events(prof)

    now = int(time.time() * 1000)
    prof.update({
        "id": str(uuid.uuid4()),
        "name": "seq3 core",
        "description": ("seq-3 v6: seq-2-shaped pre-linked bundles (seq3.lua core, "
                        "seq3ui.lua boot+screen) loaded eagerly at setup like the "
                        "proven working profile; 2-lane demo; mem prints."),
        "fileName": "seq3 core.json",
        "createdAt": now, "modifiedAt": now,
        "isEditable": True, "syncStatus": "local",
    })

    data = json.dumps(prof)
    out = os.path.join(ROOT, "dist", "seq3 core.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w").write(data)
    print(f"wrote {out}  ({len(data)} B)")

    if "--install" in sys.argv:
        dst = os.path.expanduser("~/Documents/grid-userdata/configs/seq3 core.json")
        open(dst, "w").write(data)
        print(f"wrote {dst}")

    print(f"elements: {sorted(by)} | setup {len(SETUP)}/900 | draw {len(DRAW)}/900")


if __name__ == "__main__":
    main()
