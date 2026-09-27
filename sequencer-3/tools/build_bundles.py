#!/usr/bin/env python3
"""build_bundles.py — pack the seq-3 modules into seq-2-SHAPE bundles.

Why: v5's 13-file dist cold-boot-dead while seq-2's 5-bundle dist cold-boots
on the same module. The delta is file count / load shape, so this emits the
proven shape: few plain-text bundles, each <= ~10 KB, pre-linked through a
registry shim (require resolves inside the bundle; no FS module load at
runtime, no per-file boot cost).

  dist/seq3.lua       core chain: sources, scales, lane, transport, engine
  dist/seq3ui.lua     boot + midi_rx + screen + menu (needs seq3)
  dist/seq3x.lua      lazy periphery: generate, ext, ops, preset, persist

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
    ("engine",    "src/core/engine.lua"),
]
UI = [
    ("device_boot", "src/device/device_boot.lua"),
    ("midi_rx",     "src/device/midi_rx.lua"),
    ("screen",      "src/device/screen.lua"),
    ("menu",        "src/device/menu.lua"),
]
# Live performance ops: Shred / Zero / rotate, Gamut / Euclid, X-Y addressing.
OPS = [
    ("ops",       "src/core/ops.lua"),
    ("generate",  "src/core/generate.lua"),
    ("ext",       "src/core/ext.lua"),
]
# Save / load / copy. Only the Config slot items and loadPreset need these.
PERSIST = [
    ("preset",    "src/core/preset.lua"),
    ("persist",   "src/core/persist.lua"),
]

BUNDLES = [
    ("seq3.lua",   CORE),
    ("seq3ui.lua", UI),
    ("seq3x.lua",  OPS),
    ("seq3p.lua",  PERSIST),
]

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
    total = 0
    for name, mods in BUNDLES:
        total += build(name, mods)
    print(f"4 bundles, {total} B total")
