-- tests/utils.lua
-- Behavioural tests for utils.lua.
-- Run with: lua tests/utils.lua

require("authoring")
local Utils = require("sequencer").Utils

assert(Utils.tableNew(4, 0)[3] == 0)
assert(#Utils.tableNew(8, false) == 8)

local src = { a = 1, b = 2 }
local dst = Utils.tableCopy(src)
assert(dst.a == 1 and dst.b == 2)
dst.a = 99
assert(src.a == 1, "tableCopy: original should be unchanged")

assert(Utils.clamp(5,   0, 10) == 5)
assert(Utils.clamp(-1,  0, 10) == 0)
assert(Utils.clamp(11,  0, 10) == 10)

assert(Utils.pitchToName(60) == "C4")
assert(Utils.pitchToName(48) == "C3")
assert(Utils.pitchToName(51) == "Eb3")
assert(Utils.pitchToName(69) == "A4")
assert(Utils.pitchToName(0) == "C-1")

print("utils: all tests passed")
