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


def iso_now():
    """createdAt / modifiedAt are ISO 8601 UTC strings in every real profile
    (the template's own, and the cold-boot-proven seq-1 one). We used to write
    integer epoch milliseconds here, which profile-cloud refused to load."""
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime()) + ".000Z"


def check_schema(prof):
    """Every top-level field must have the same JSON type as the template's.

    The template IS a real profile the editor produced, so a type mismatch
    means we have written something the editor/profile-cloud will not parse.
    This is what caught createdAt/modifiedAt being ints.
    """
    tmpl = json.load(open(TEMPLATE))
    for k, tv in tmpl.items():
        if k == "configs":
            continue
        if k not in prof:
            raise SystemExit(f"profile schema: missing top-level field {k!r}")
        if type(prof[k]) is not type(tv):
            raise SystemExit(
                f"profile schema: {k!r} is {type(prof[k]).__name__}, "
                f"template has {type(tv).__name__} ({tv!r})")
    extra = set(prof) - set(tmpl)
    if extra:
        raise SystemExit(f"profile schema: fields absent from the template: {sorted(extra)}")

# --- element 255, event 0: system setup (<= 900 chars) ----------------------
# v7, SEQ-1 WIRING (the project with a proven cold boot):
#   - midi_send(ch, st, p1, p2) — NOT gms() (seq-1 never used gms)
#   - rtmrx_cb assigned directly, NO grxm() arming call (seq-1 arms nothing;
#     grxm at setup is our prime crash suspect)
#   - requires all three bundles eagerly (seq3 core, seq3ui screen, seq3x
#     lazy periphery so the engine's lazy loaders resolve). seq-1's proven
#     setup loaded ~10 KB eagerly; ours is ~37 KB across three chunks —
#     if this still dies cold, the next cut is requiring seq3x on first use.
# v9 SETUP MODES. The project's own measured ladder (AGENTS.md) says the ONE
# shape that ever cold-booted "requires NOTHING at setup"; every eager-at-setup
# build died, v8 included (it required seq3 + seq3ui AND ran the demo there).
# So setup now does no requires at all: it defines a global lazy loader and
# assigns rtmrx_cb. Nothing compiles until a trigger fires.
#
#   --setup=none   (DEFAULT) chain loads on the first MIDI byte
#   --setup=press            chain loads only on the first CONTROL PRESS;
#                            MIDI is ignored until then (the v5 shape)
#   --setup=eager            v8 shape: require both bundles at setup
#
# rtmrx_cb SIGNATURE: seq-1's authoritative wiring (configs/VSN1.lua) is
# function(self, t) — TWO params. v7/v8 used function(self, h, t), so `t` was
# nil and RX.handle never saw a status byte: MIDI clock could not work at all.
# Fixed here.
SETUP_MODE = "eager"
for _a in sys.argv:
    if _a.startswith("--setup="):
        SETUP_MODE = _a.split("=", 1)[1]
if "--eager-x" in sys.argv and SETUP_MODE == "eager":
    pass
if not any(a.startswith("--setup=") for a in sys.argv):
    SETUP_MODE = "none"
assert SETUP_MODE in ("none", "press", "eager"), f"bad --setup={SETUP_MODE}"

# The lazy loader, defined (not run) at setup. Global so every event can call
# it. STAGED (v13): each call compiles at most ONE bundle and returns nil until
# the chain is complete, so no single event callback has to compile the whole
# start chain (seq3 + seq3e + seq3ui, ~15 KB of source) at once:
#   call 1 -> seq3 (core)   call 2 -> seq3e (engine)   call 3 -> seq3ui + demo
# The screen (seq3s) is not part of start at all: midi_rx compiles it on the
# first control press after the chain is up. LS counts stages; it is nil until
# a MIDI byte or key press calls L(), which is what lets the timer finish a
# started load without ever starting one during cold boot.
LOADER = (
    'function L()'
    'if RX then return RX end '
    'LS=(LS or 0)+1 '
    'if LS==1 then print("seq3: start 1/3 core") require("seq3") '
    'elseif LS==2 then print("seq3: start 2/3 engine") require("seq3e") '
    'else print("seq3: start 3/3 midi") UI=require("seq3ui") RX=UI.midi_rx RX.ensure() end '
    'return RX '
    'end '
)

if SETUP_MODE == "eager":
    SETUP = (
        '--[[@cb]] SEQ3=require("seq3")'
        'UI=require("seq3ui")'
        'RX=UI.midi_rx '
        'RX.ensure() '
        'self.rtmrx_cb=function(self,t)RX.handle(t,midi_send)end'
    )
elif SETUP_MODE == "press":
    # MIDI does not load the chain; only a control press does.
    SETUP = ('--[[@cb]] ' + LOADER
             + 'self.rtmrx_cb=function(self,t)if RX then RX.handle(t,midi_send)end end')
else:
    # Default: the first MIDI byte loads the chain.
    SETUP = ('--[[@cb]] ' + LOADER
             + 'self.rtmrx_cb=function(self,t)local r=L() if r then r.handle(t,midi_send)end end')

EAGER_X = "--eager-x" in sys.argv

# --- HEADLESS target -------------------------------------------------------
# No GUI at all: clock -> lanes -> MIDI out, with a console report of the lanes
# from the timer event. screen.lua + menu.lua (8.6 KB stripped) are never
# compiled, which is the point — the module ran out of memory initialising them.
HEADLESS = "--headless" in sys.argv

HL_SETUP = (
    '--[[@cb]] function L()'
    'if not RX then RX=require("seq3h").headless end '
    'return RX '
    'end '
    'self.rtmrx_cb=function(self,t)L().handle(t,midi_send)end'
)
# The timer is the whole "show me the lanes" surface, and it keeps report()
# off the pulse path so Engine.onPulse stays allocation-free.
HL_TIMER = ('--[[@cb]] if RX then RX.report() end '
            'print("seq3 mem KB: " .. collectgarbage("count"))')
# Button events fire on press AND release (seen on device, v15: every action
# ran twice). Each button event therefore sets momentary 0/127 mode itself
# (set_event replaces the template's @sbc setup; key 7's was TOGGLE mode) and
# acts only when the state is 127 = pressed — seq-1/seq-2's proven guard.
BTN = '--[[@sbc]] self:bmo(0)self:bmi(0)self:bma(127)'
PRESSED = 'if self:bst()==127 then '

# A key press arms the sequence with no DAW attached.
HL_KEY = BTN + "--[[@cb]] " + PRESSED + "L().key() end"


def press_cb(call):
    """A control press. With a lazy setup the press is also a load trigger, so
    it goes through L(); with the eager setup RX already exists."""
    if SETUP_MODE == "eager":
        return f"{BTN}--[[@cb]] {PRESSED}if RX then {call} end end"
    return f"{BTN}--[[@cb]] {PRESSED}L() if RX then {call} end end"


# --- element 255, event 6: timer — RAM diagnostic ---------------------------
# Reading collectgarbage("count") is passive (seq-2's poison was
# collectgarbage("collect") and package.loaded manipulation, not the count).
MEM = '--[[@cb]] print("seq3 mem KB: " .. collectgarbage("count"))'
# GUI (non-eager): the timer also advances a load that a MIDI byte or a key
# press STARTED (LS set). LS is nil through cold boot, so the timer can never
# be the one to start compiling.
if SETUP_MODE != "eager":
    MEM = ('--[[@cb]] if LS and not RX then L() end '
           'print("seq3 mem KB: " .. collectgarbage("count"))')

# --- element 13, event 8: screen draw (<= 900 chars) ------------------------
# The adapter (inside the pre-linked bundle) draws the live view when dirty.
# MUST NOT call L(): the draw event fires during the cold-boot sequence, so
# loading from here would defeat the whole point of a bare setup. The screen
# stays dark until a MIDI byte or a key press has loaded the chain.
DRAW = "--[[@cb]] if RX then RX.ui(self) end"

# Encoder turn keeps its --[[@sen]] relative-mode setup (epmo(1)) — the only
# way epva() yields a ±1 delta on device (seq-2 hardware finding).
ENCODER_TURN = (
    '--[[@sen]] self:epmo(1)self:epv0(64)self:epmi(0)self:epma(127)self:epse(1)'
    + ('--[[@cb]] if RX then RX.turn(self:epva()-64) end' if SETUP_MODE == "eager"
       else '--[[@cb]] L() if RX then RX.turn(self:epva()-64) end')
)

# Control elements: keyswitches 0-7 -> RX.key(i), encoder click -> RX.press(),
# small buttons 9-12 -> RX.btn(i). Everything is already loaded at setup.
CB_FULL = {}
for _k in range(0, 8):
    CB_FULL[(_k, 3)] = press_cb(f"RX.key({_k})")
CB_FULL[(8, 3)] = press_cb("RX.press()")
for _b in range(9, 13):
    CB_FULL[(_b, 3)] = press_cb(f"RX.btn({_b})")

if HEADLESS:
    SETUP = HL_SETUP
    MEM = HL_TIMER
    DRAW = ""                      # no GUI: the draw event does nothing
    CB_FULL = {}
    for _k in range(0, 8):
        CB_FULL[(_k, 3)] = HL_KEY
    CB_FULL[(8, 3)] = HL_KEY
    for _b in range(9, 13):
        CB_FULL[(_b, 3)] = HL_KEY
    ENCODER_TURN = ('--[[@sen]] self:epmo(1)self:epv0(64)self:epmi(0)'
                    'self:epma(127)self:epse(1)--[[@cb]] L().key()')

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


def write_probe():
    """--probe: the smallest possible profile on this element skeleton.

    EVERY event config is blanked except el 13 ev0 (glsb(255), which the
    working seq-1 profile also has) and el 255 ev6, which prints "probe alive".
    No require, no module code, no draw. It answers one question that nothing
    on the Mac can:

      boots + prints "probe alive"  -> the element skeleton and our event
                                       wiring are innocent; the problem is the
                                       Lua we load (bundles / setup).
      dies                          -> the seq-2-derived template itself is
                                       the killer; rebuild it from a working
                                       seq-1 profile instead.
    """
    prof = copy.deepcopy(json.load(open(TEMPLATE)))
    by = {c["controlElementNumber"]: c for c in prof["configs"]}
    for c in prof["configs"]:
        for e in c["events"]:
            e["config"] = ""
    set_event(by[13], 0, "--[[@cb]] glsb(255)")
    set_event(by[255], 6, '--[[@cb]] print("probe alive")')
    validate_events(prof)
    now = iso_now()
    prof.update({
        "id": str(uuid.uuid4()),
        "name": "seq3 probe",
        "description": ("seq-3 boot probe: every event blank except a timer "
                        "print. No require, no module code. If this cold boots, "
                        "the element skeleton is innocent."),
        "fileName": "seq3 probe.json",
        "createdAt": now, "modifiedAt": now,
        "isEditable": True, "syncStatus": "local",
    })
    check_schema(prof)
    data = json.dumps(prof)
    out = os.path.join(ROOT, "dist", "seq3 probe.json")
    open(out, "w").write(data)
    print(f"wrote {out}  ({len(data)} B)")
    if "--install" in sys.argv:
        dst = os.path.expanduser("~/Documents/grid-userdata/configs/seq3 probe.json")
        open(dst, "w").write(data)
        print(f"wrote {dst}")


def main():
    if "--probe" in sys.argv:
        write_probe()
        return
    prof = copy.deepcopy(json.load(open(TEMPLATE)))
    by = {c["controlElementNumber"]: c for c in prof["configs"]}

    # The seq-2 template puts print("tick") on the timer (ev6) of ALL 14
    # elements; seq-1's working profile has 2. Fourteen timers printing during
    # the cold-boot sequence is needless churn, so blank every element timer
    # and keep only el 255's RAM diagnostic.
    for _n, _c in by.items():
        if _n == 255:
            continue
        for _e in _c["events"]:
            if _e["event"] == 6:
                _e["config"] = ""

    set_event(by[255], 0, SETUP)
    set_event(by[255], 6, MEM)
    set_event(by[13], 8, DRAW)
    set_event(by[8], 7, ENCODER_TURN)
    for (el, ev), cb in CB_FULL.items():
        set_event(by[el], ev, cb)

    validate_events(prof)

    now = iso_now()
    prof.update({
        "id": str(uuid.uuid4()),
        "name": "seq3 headless" if HEADLESS else "seq3 core",
        "description": (
            ("seq-3 v12 HEADLESS: no GUI. Clock -> 3 lanes -> MIDI out; the "
             "timer prints one line per lane. Upload seq3.lua + seq3e.lua + "
             "seq3h.lua.")
            if HEADLESS else
            ("seq-3 v15 (setup=" + SETUP_MODE + "): staged start, one bundle "
             "per event; buttons act on press only; screen in seq3s.")),
        "fileName": ("seq3 headless.json" if HEADLESS else "seq3 core.json"),
        "createdAt": now, "modifiedAt": now,
        "isEditable": True, "syncStatus": "local",
    })

    check_schema(prof)
    data = json.dumps(prof)
    name = "seq3 headless.json" if HEADLESS else "seq3 core.json"
    out = os.path.join(ROOT, "dist", name)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "w").write(data)
    print(f"wrote {out}  ({len(data)} B)")

    if "--install" in sys.argv:
        dst = os.path.expanduser("~/Documents/grid-userdata/configs/" + name)
        open(dst, "w").write(data)
        print(f"wrote {dst}")

    print(f"elements: {sorted(by)} | setup {len(SETUP)}/900 | draw {len(DRAW)}/900")
    print(f"target: {'HEADLESS (no GUI)' if HEADLESS else 'GUI'} | "
          f"setup mode: {'headless-lazy' if HEADLESS else SETUP_MODE}")
    ticks = sum(1 for c in prof["configs"] for e in c["events"]
                if e["event"] == 6 and e.get("config", "").strip())
    print(f"timer (ev6) events kept: {ticks} (was 14 from the seq-2 template)")


if __name__ == "__main__":
    main()
