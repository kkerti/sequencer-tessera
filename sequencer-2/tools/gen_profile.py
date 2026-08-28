#!/usr/bin/env python3
"""gen_profile.py — generate a loadable Grid VSN1R profile for seq-2.

Clones the proven "Note Step Sequencer" element skeleton (tools/vsn1r_template.json)
so the editor sees a COMPLETE module (a partial profile makes it throw
"Cannot read properties of undefined (reading 'events')"). Overrides only the
elements seq-2 uses; every control element stays in its PLAINEST event mode —
plain bst()/epva() callbacks, no bmo/toggle/momentary element setup. LED
lighting is decoupled: a dedicated render pass (src/hal/leds.lua) runs from the
draw event and drives each element's LED via led_color() from CTL/engine state.
For control elements it PRESERVES the template's non-behaviour setup prefix
(the --[[@s..]] LEDs prev config) and swaps just the --[[@cb]] callback.

Control map (see docs/DEPLOY.md):
  el 255 ev0  system setup: require Core (seq2+seq2b), init 2 tracks, arm MIDI
               rx, lazy UI (seq2_ctl/seq2_ui/seq2_gen on first input/draw)
  el 13  ev8  screen draw (text-only views) + throttled LED render pass
  el 8   ev7/ev3  encoder turn (stage/slot) / click (reroll/field)
  el 0-7 ev3  keyswitches: mode-specific direct actions, 7 = MODE cycle
  el 9-12 ev3 small buttons: 9 = BACK, 10 = ENTER, 11 = NAP, 12 = COMMIT

Module Lua bundles (dist/seq2.lua, seq2b, seq2_ctl, seq2_ui, seq2_gen — all
PLAIN TEXT) upload SEPARATELY under those exact require names.
Run:  python3 tools/gen_profile.py [--install]
"""
import json, os, sys, time, uuid, copy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TEMPLATE = os.path.join(HERE, "vsn1r_template.json")

# --- element 255, event 0: system setup (<= 900 chars) ---------------------
# LEAN layout (see docs/DEPLOY.md): 5 text bundles, each small enough not to
# trip the module watchdog on load. Core (seq2 + seq2b) at setup; control /
# draw lazy on first input/draw. Demo patterns are generated HERE (not only in
# lazy control.bind) so pure playback never depends on the UI bundles loading.
# Device-code rules: NO collectgarbage, NO package.loaded, NO string.format.
SETUP = (
    '--[[@cb]] CTL=nil DRAW=nil LEDS=nil '
    'SEQ=require("seq2")SEQB=require("seq2b")ENGINE=SEQB.engine MIDIRX=SEQB.midirx '
    'NOOP=setmetatable({},{__index=function()return function()end end})'
    'function loadAPP()return NOOP end function vsn1_p()end function vsn1_t()end function paint()end '
    'function loadUI()if not CTL then CTL=require("seq2_ctl").control local U=require("seq2_ui")DRAW=U.draw LEDS=U.leds CTL.bind(ENGINE,SEQ)end return CTL end '
    'ENGINE.init({trackCount=2})'
    'G=require("seq2_gen").generate '
    'G.run(ENGINE.tracks[1].pattern,{scaleIndex=3,root=9,hits=7,seed=1,pitchRoot=60,pitchSpread=6,velRoot=100,velSpread=20,gateRoot=6})'
    'G.run(ENGINE.tracks[2].pattern,{scaleIndex=8,root=9,hits=4,seed=2,pitchRoot=40,pitchSpread=4,velRoot=110,velSpread=15,gateRoot=18})'
    'grxm(2,3)self.rtmrx_cb=function(self,h,t)MIDIRX.handle(t,gms)end'
)

# Encoder turn keeps its --[[@sen]] relative-mode setup (epmo(1)) — needed for
# the epva() delta. Prefix-preserving: only the callback is swapped.
CB = {
    (8, 7): "local d=self:epva()-64 if d~=0 then loadUI().turn(d)end",  # encoder turn (relative)
}
# Everything else is callback-only (set_event drops the template's bmo/glc/glp/
# momentary element setup): plain bst()/epva() callbacks. LEDs are driven only
# by the LED render pass (src/hal/leds.lua) from the draw event, never by
# firmware element behaviour.
CB_FULL = { (_k, 3): f"loadUI().key({_k},self:bst()==127)" for _k in range(8) }           # keyswitches 0-7
CB_FULL.update({ (_b, 3): f"loadUI().button({_b},self:bst()==127)" for _b in range(9, 13) })  # small buttons 9-12
CB_FULL[(8, 3)]  = "loadUI().click(self:bst()==127)"                                        # encoder click
# draw every frame; LED pass throttled to every 4th frame (cheap on the heap)
CB_FULL[(13, 8)] = "loadUI() DRAW(self,ENGINE,CTL) C=(C or 0)+1 if C%4==0 then LEDS(ENGINE,CTL)end"

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
        "name": "Sequencer Magnetar",
        "description": "seq-2: 4 tracks, staged generative euclid + sequence/song",
        "fileName": "Sequencer Magnetar.json",
        "createdAt": now, "modifiedAt": now,
        "isEditable": True, "syncStatus": "local",
    })

    data = json.dumps(prof)
    out = os.path.join(ROOT, "dist", "Sequencer Magnetar.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w").write(data)
    print(f"wrote {out}  ({len(data)} B)")

    if "--install" in sys.argv:
        dst = os.path.expanduser("~/Documents/grid-userdata/configs/Sequencer Magnetar.json")
        open(dst, "w").write(data)
        print(f"wrote {dst}")

    print(f"elements: {sorted(by)} | setup {len(SETUP)}/900 chars | control events: {len(CB)+len(CB_FULL)}")


if __name__ == "__main__":
    main()
