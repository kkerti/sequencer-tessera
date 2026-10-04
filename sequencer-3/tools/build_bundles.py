#!/usr/bin/env python3
"""build_bundles.py — pack the seq-3 modules into seq-2-SHAPE bundles.

Why: v5's 13-file dist cold-boot-dead while seq-2's 5-bundle dist cold-boots
on the same module. The delta is file count / load shape, so this emits the
proven shape: few plain-text bundles, each <= ~10 KB, pre-linked through a
registry shim (require resolves inside the bundle; no FS module load at
runtime, no per-file boot cost).

  dist/seq3.lua       core chain: sources, scales, lane, transport, engine
  dist/seq3ui.lua     boot + midi_rx (what app start compiles, with seq3/seq3e)
  dist/seq3s.lua      the screen (text or colour), on the first control press
  dist/seq3x.lua      lazy editing: setters + shred / randomize / zero / rotate
  dist/seq3p.lua      lazy save: source names, persist
  dist/seq3l.lua      lazy load: preset (loadPreset / copy)

The profile's setup requires seq3 then seq3ui and fills the demo — mirroring
seq-2's working setup (14.8 KB eager) — with grxm/rtmrx armed at setup.

Usage:  python3 tools/build_bundles.py
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "dist")

# (key, source path) per bundle, in dependency order -------------------------
# v10: the lazy periphery is split by TRIGGER, because the device ran out of
# memory compiling the single 11.2 KB seq3x once seq3 + seq3ui were resident:
#
#   LUA not OK! error loading module 'seq3x' from file '/seq3x.lua':
#                                                       not enough memory
#
# Shred/Zero is 843 B of code but was dragging in 11.2 KB. Splitting means the
# most-used live feature compiles ~4.8 KB and save/load ~6.9 KB, separately —
# the peak compile more than halves and neither pulls the other.
CORE = [
    ("sources",   "src/core/sources.lua"),
    ("scales",    "src/core/scales.lua"),
    ("transport", "src/core/transport.lua"),
    ("lane",      "src/core/lane.lua"),
]
# engine.lua alone is the single biggest chunk, so it gets its own bundle: the
# module ran out of memory initialising the modules, and the peak matters as
# much as the total. seq-1's largest chunk was 10.3 KB; this keeps ours near it.
ENGINE = [
    ("engine",    "src/core/engine.lua"),
]
# HEADLESS: no GUI at all. clock -> lanes -> MIDI out + a console report.
# screen.lua + menu.lua are 8.6 KB of stripped source and are never compiled
# on this path.
HEADLESS = [
    ("seq_data",  "src/device/seq_data.lua"),
    ("headless",  "src/device/headless.lua"),
]
# What app START compiles: the MIDI receiver + the demo, nothing else. The
# screen used to live here too, and a bundle runs every module body when it is
# required, so the first MIDI byte compiled the whole GUI as well. Now start
# costs the same as the headless target and the screen is its own bundle.
UI = [
    ("device_boot", "src/device/device_boot.lua"),
    ("midi_rx",     "src/device/midi_rx.lua"),
]
# The screen: compiled on the first CONTROL PRESS (midi_rx.loadSCR), never at
# start. --gui=text: the text-only key/value page replaces screen + menu,
# bundled under the name "screen" so midi_rx and the profile are unchanged.
SCREEN = [
    ("screen",      "src/device/screen.lua"),
    ("menu",        "src/device/menu.lua"),
]
if "--gui=text" in sys.argv:
    SCREEN = [("screen", "src/device/text_screen.lua")]
# Editing: the engine's setters (edit) + Shred / Random / Zero / rotate (ops).
# Compiled on the first edit or performance op, never at app start.
OPS = [
    ("edit",      "src/core/edit.lua"),
    ("ops",       "src/core/ops.lua"),
]
# Save / load, split by trigger like OPS: with the text GUI resident the wasm
# harness could not compile the 6.1 KB combined bundle. Save compiles only
# seq3p (persist + source names); a load or loadPreset also pulls seq3l.
PERSIST = [
    ("source_names", "src/core/source_names.lua"),
    ("persist",   "src/core/persist.lua"),
]
LOAD = [
    ("preset",    "src/core/preset.lua"),
]

BUNDLES = [
    ("seq3.lua",   CORE),
    ("seq3e.lua",  ENGINE),
    ("seq3h.lua",  HEADLESS),
    ("seq3ui.lua", UI),
    ("seq3s.lua",  SCREEN),
    ("seq3x.lua",  OPS),
    ("seq3p.lua",  PERSIST),
    ("seq3l.lua",  LOAD),
]

# The HEADLESS target uploads only these three.
HEADLESS_SET = ("seq3.lua", "seq3e.lua", "seq3h.lua")

# module name -> the bundle that holds it. The shim uses this to resolve a
# cross-bundle require DIRECTLY, so requiring "ops" pulls seq3x and nothing
# else. (The old shim tried each fallback in turn, so one miss could compile a
# bundle we never needed — exactly the RAM we are trying not to spend.)
OWNER = {}
for _name, _mods in BUNDLES:
    _key = _name[:-4]                     # strip ".lua"
    for _k, _ in _mods:
        OWNER[_k] = _key

def strip(src):
    """Strip comments and blank lines, string-aware (same as strip_lua.py)."""
    out_lines = []
    for line in src.split("\n"):
        out, q, i, n = [], None, 0, len(line)
        while i < n:
            c = line[i]
            if q:
                out.append(c)
                if c == "\\":
                    if i + 1 < n:
                        out.append(line[i + 1]); i += 1
                elif c == q:
                    q = None
            elif c in "\"'":
                q = c; out.append(c)
            elif c == "-" and i + 1 < n and line[i + 1] == "-":
                j = i + 2
                if j < n and line[j] == "[":
                    k = line.find("]]", j)
                    if k == -1:
                        i = n
                    else:
                        i = k + 1
                        continue
                break
            else:
                out.append(c)
            i += 1
        s = "".join(out).strip()
        if s:
            out_lines.append(s)
    return "\n".join(out_lines)

SHIM_HEAD = """local R={}
local _host=require
local B=%s
local C={}
local function require(n)
 local r=R[n] if r~=nil then return r end
 local b=B[n]
 if b then
  local m=C[b] if not m then m=_host(b) C[b]=m end
  local v=m[n] if v~=nil then return v end
 end
 error('seq3 module not found: '..tostring(n))
end
"""

def owner_map(exclude):
    """Lua table literal: module name -> owning bundle, for names NOT local to
    this bundle (a local name is served from R before B is consulted)."""
    items = ["%s=%r" % (k, v) for k, v in sorted(OWNER.items()) if k not in exclude]
    return "{" + ",".join(items).replace("'", '"') + "}"

SELF_SHIM = "local R={}\nlocal function require(n) return R[n] end\n"

def build(name, modules):
    """Pack modules into one bundle: R[key]=(function() <src> end)() pairs.

    Cross-bundle names resolve through the OWNER map in the shim, so each
    bundle only ever compiles the bundle that actually owns a missing name.
    """
    local_keys = {k for k, _ in modules}
    parts = [SHIM_HEAD % owner_map(local_keys)]
    for key, path in modules:
        src = strip(open(os.path.join(ROOT, path)).read())
        parts.append(f'R["{key}"]=(function()\n\n{src}\n\nend)()\n')
    parts.append("return R\n")
    data = "".join(parts)
    out = os.path.join(OUT, name)
    open(out, "w").write(data)
    print(f"wrote {out}  ({len(data)} B)")
    return len(data)

if __name__ == "__main__":
    sizes = {}
    for name, mods in BUNDLES:
        sizes[name] = build(name, mods)
    print()
    hl = sum(sizes[n] for n in HEADLESS_SET)
    gui = sum(sizes[n] for n in ("seq3.lua", "seq3e.lua", "seq3ui.lua"))
    scr = sizes["seq3s.lua"]
    print(f"HEADLESS upload ({' + '.join(HEADLESS_SET)}) = {hl} B")
    print(f"GUI start (seq3.lua + seq3e.lua + seq3ui.lua) = {gui} B; screen (seq3s.lua) = {scr} B on first press")
    print(f"largest single chunk = {max(sizes.values())} B (seq-1's proven max: 10300 B)")
