#!/usr/bin/env python3
"""build_bundles.py — pack the seq-3 modules into seq-2-SHAPE bundles.

Why: v5's 13-file dist cold-boot-dead while seq-2's 5-bundle dist cold-boots
on the same module. The delta is file count / load shape, so this emits the
proven shape: few plain-text bundles, each <= ~10 KB, pre-linked through a
registry shim (require resolves inside the bundle; no FS module load at
runtime, no per-file boot cost).

  dist/seq3.lua       core chain: sources, scales, lane, transport, generate,
                      ext, ops, preset, engine (self-contained, ~13 KB)
  dist/seq3ui.lua     boot + midi_rx + screen + menu (needs seq3, ~10 KB)

The profile's setup requires seq3 then seq3ui and fills the demo — mirroring
seq-2's working setup (14.8 KB eager) — with grxm/rtmrx armed at setup.

Usage:  python3 tools/build_bundles.py
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "dist")

# (key, source path) per bundle, in dependency order -------------------------
# v7 follows seq-1's PROVEN bundle sizes (its biggest was 10.3 KB): split the
# core so no bundle is far above 10 KB, and keep the demo-unused periphery
# (generate/ext/ops/preset) in a THIRD bundle that only loads when one of
# those actions is first used (engine's loadGenerate/loadExt/loadOps/loadPreset
# call require() — the bundle shim serves them without any FS-module load).
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
# Lazy periphery: NOT loaded at setup. The engine's lazy loaders require
# these names on first use; the CORE bundle's require shim falls through to
# the host require, which (after the profile's setup has required seq3x) is
# a registry hit — no FS involvement. If seq3x is not loaded yet, the
# require errors; acceptable: those actions are unused by the demo.
EXTRA = [
    ("generate",  "src/core/generate.lua"),
    ("ext",       "src/core/ext.lua"),
    ("ops",       "src/core/ops.lua"),
    ("preset",    "src/core/preset.lua"),
]

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

SHIM = """local R={}
local _host=require
local _1
local _x
local function require(n)
 local r=R[n] if r~=nil then return r end
 if not _1 then _1=_host(%(host)r) end local m=_1[n] if m then return m end
 if not _x then _x=_host(%(extra)r) end x=_x[n] if x then return x end
 error('seq3 module not found: '..tostring(n))
end
"""

SELF_SHIM = "local R={}\nlocal function require(n) return R[n] end\n"

def build(name, modules, fallback=None):
    """Pack modules into one bundle: R[key]=(function() <src> end)() pairs.

    fallback: bundle name to delegate to when a key is missing locally
    (the bundle's returned table is fetched via the host require at first
    miss). None = fully self-contained.
    """
    parts = []
    if fallback:
        parts.append(SHIM % {"host": fallback[0], "extra": fallback[1]})
        parts.append("local _1\nlocal _x\nlocal x\n")
    else:
        parts.append(SELF_SHIM)
    for key, path in modules:
        src = strip(open(os.path.join(ROOT, path)).read())
        parts.append(f'R["{key}"]=(function()\n\n{src}\n\nend)()\n')
    parts.append(f"return R\n")
    data = "".join(parts)
    out = os.path.join(OUT, name)
    open(out, "w").write(data)
    print(f"wrote {out}  ({len(data)} B)")

if __name__ == "__main__":
    # seq3.lua: core chain; falls through to seq3ui (device_boot etc.) and
    # seq3x (generate/ext/ops/preset) for the lazy modules it names.
    build("seq3.lua", CORE, fallback=("seq3ui", "seq3x"))
    # seq3ui.lua: falls back to seq3 (lane/scales/engine) and seq3x.
    build("seq3ui.lua", UI, fallback=("seq3", "seq3x"))
    # seq3x.lua: needs lane/scales/engine from seq3 only.
    build("seq3x.lua", EXTRA, fallback=("seq3", "seq3x"))
