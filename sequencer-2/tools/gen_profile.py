#!/usr/bin/env python3
"""gen_profile.py — generate a loadable Grid VSN1R profile for seq-2.

Clones the proven "Note Step Sequencer" element skeleton (tools/vsn1r_template.json)
so the editor sees a COMPLETE module (a partial profile makes it throw
"Cannot read properties of undefined (reading 'events')"). Overrides only the
elements seq-2 uses; for control elements it PRESERVES each event's hardware
setup prefix (the --[[@s..]] markers) and swaps just the --[[@cb]] callback, so
LED/encoder config still applies.

Control map (see docs/DEPLOY.md):
  el 255 ev0  system setup: require Core, init 4 tracks, arm MIDI rx, lazy UI
  el 13  ev8  screen draw (PLAY / STEP / SEQ)
  el 8   ev7/ev3  encoder turn (stage/slot/cursor) / click (reroll/field/jump)
  el 0-7 ev3  keyswitches: 0 = SHIFT, 1-6 = mode actions, 7 = MODE cycle

Module Lua bundles (dist/seq2.lua, dist/seq2_ui.lua) upload SEPARATELY as
`seq2` / `seq2_ui`. Run:  python3 tools/gen_profile.py [--install]
"""
import json, os, sys, time, uuid, copy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TEMPLATE = os.path.join(HERE, "vsn1r_template.json")

# --- element 255, event 0: system setup (<= 900 chars) ---------------------
SETUP = (
    '--[[@cb]] if package and package.loaded then package.loaded.seq2=nil package.loaded.seq2_ui=nil end CTL=nil DRAW=nil '
    'SEQ=require("seq2")ENGINE=SEQ.engine MIDIRX=SEQ.midirx '
    'NOOP=setmetatable({},{__index=function()return function()end end})'
    'function loadAPP()return NOOP end function vsn1_p()end function vsn1_t()end function paint()end '
    'function loadUI()if not CTL then local U=require("seq2_ui")CTL=U.control DRAW=U.draw CTL.bind(ENGINE,SEQ)end return CTL end '
    'ENGINE.init({trackCount=4})'
    'grxm(2,3)self.rtmrx_cb=function(self,h,t)MIDIRX.handle(t,gms)end'
)

# control-element callbacks: (element, event) -> callback body (after --[[@cb]]).
# Prefix-preserving (keeps the element's --[[@s..]] hardware setup).
# ALL control is on keyswitches 0-7 + the encoder; small buttons 9-12 are dead
# on the hardware, so we don't wire them at all.
CB = {
    (13, 8): "loadUI() DRAW(self,ENGINE,CTL)",                        # screen draw
    (8, 7):  "local d=self:epva()-64 if d~=0 then loadUI().turn(d)end",  # encoder turn
    (8, 3):  "loadUI().click(self:bst()==127)",                       # encoder click = reroll
}
for _k in range(8):                                                   # keyswitches 0-7
    CB[(_k, 3)] = f"loadUI().key({_k},self:bst()==127)"
CB_FULL = {}

assert len(SETUP) <= 900, f"setup event {len(SETUP)} > 900 chars"
for k, v in {**CB, **CB_FULL}.items():
    assert len(v) + 10 <= 900, f"event {k} callback too long"


def set_event(element, event_id, config):
    for e in element["events"]:
        if e["event"] == event_id:
            e["config"] = config
            return
    element["events"].append({"event": event_id, "config": config})


def set_cb(element, event_id, cb):
    """Replace only the --[[@cb]] callback; keep the setup prefix."""
    for e in element["events"]:
        if e["event"] == event_id:
            i = e["config"].find("--[[@cb]]")
            prefix = e["config"][:i] if i >= 0 else ""
            e["config"] = prefix + "--[[@cb]] " + cb
            return
    element["events"].append({"event": event_id, "config": "--[[@cb]] " + cb})


def main():
    prof = copy.deepcopy(json.load(open(TEMPLATE)))
    by = {c["controlElementNumber"]: c for c in prof["configs"]}

    set_event(by[255], 0, SETUP)                    # full system setup
    for (el, ev), cb in CB.items():
        set_cb(by[el], ev, cb)                      # keep hardware setup prefix
    for (el, ev), cb in CB_FULL.items():
        set_event(by[el], ev, "--[[@cb]] " + cb)    # drop setup (small buttons)

    now = int(time.time() * 1000)
    prof.update({
        "id": str(uuid.uuid4()),
        "name": "Sequencer 2",
        "description": "seq-2: 4 tracks, staged generative euclid + sequence/song",
        "fileName": "Sequencer 2.json",
        "createdAt": now, "modifiedAt": now,
        "isEditable": True, "syncStatus": "local",
    })

    data = json.dumps(prof)
    out = os.path.join(ROOT, "dist", "Sequencer 2.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w").write(data)
    print(f"wrote {out}  ({len(data)} B)")

    if "--install" in sys.argv:
        dst = os.path.expanduser("~/Documents/grid-userdata/configs/Sequencer 2.json")
        open(dst, "w").write(data)
        print(f"wrote {dst}")

    print(f"elements: {sorted(by)} | setup {len(SETUP)}/900 chars | control events: {len(CB)+len(CB_FULL)}")


if __name__ == "__main__":
    main()
