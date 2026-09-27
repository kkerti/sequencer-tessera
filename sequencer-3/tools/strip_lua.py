#!/usr/bin/env python3
"""strip_lua.py — strip comments and blank lines from Lua source, string-aware.

Prints to stdout. Used by make_dist.sh: the device compiles text chunks at
load, so comments are pure ballast (bigger compiled chunks + more transient
string garbage — both count against the module's tight RAM ceiling).

Usage: python3 tools/strip_lua.py <file.lua> > <out>
"""
import sys

def strip(src):
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
                # --[==[[ ... ]]==] long bracket? treat the rest as comment
                j = i + 2
                if j < n and line[j] == "[":
                    k = line.find("]]", j)
                    if k == -1:
                        i = n          # comment runs to end of line
                    else:
                        i = k + 1      # inline long comment; resume after it
                        continue
                break
            else:
                out.append(c)
            i += 1
        s = "".join(out).strip()
        if s:
            out_lines.append(s)
    return "\n".join(out_lines)

if __name__ == "__main__":
    sys.stdout.write(strip(open(sys.argv[1]).read()))