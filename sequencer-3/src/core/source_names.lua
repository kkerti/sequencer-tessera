-- source_names.lua — the public source vocabulary ("off",
-- "transport.quarter", ...) <-> the engine's small integers.
--
-- LAZY, and not in the resident core: the device passes numeric sources, so
-- these strings are only built when a string arrives (the Mac shell, a preset
-- file) or persist writes a name. On the device it lives in the persist
-- bundle (seq3p).

local Sources = require("sources")

local NAMES = { ["off"] = Sources.OFF }
local taps = { "whole", "half", "quarter", "eighth", "sixteenth" }
for i = 1, #taps do NAMES["transport." .. taps[i]] = Sources.TRANSPORT_WHOLE + i - 1 end
local REVERSE = {}
for k, v in pairs(NAMES) do REVERSE[v] = k end

return { names = NAMES, reverse = REVERSE }
