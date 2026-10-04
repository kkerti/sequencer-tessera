-- device_boot.lua — device-side bootstrap. v0 is CORE ONLY (headless): the
-- profile load that pulled the GUI (host + widgets + layout_core) exceeded the
-- module RAM (183 KB > acceptable). Until each piece is re-added and measured,
-- this module only wires the engine: demo pattern + the pulse hook.
--
-- Device-code rules: device modules ship plain (no GC calls, no package
-- manipulation, no text formatting).

local Engine = require("engine")
local Lane   = require("lane")

local M = {}

-- Demo pattern: 1 note melody + 1 trig lane, both advancing on the transport
-- quarter. TWO LANES at boot (4-lane init costs ~6 KB of step arrays). Lane
-- fields are written DIRECTLY, not through the setters: the setters live in
-- the lazy editing bundle (edit.lua), and app start must not compile it.
-- Starts running; Ableton start/stop overrides.
function M.demo()
    Engine.init{ lanes = 2, channel = 1 }
    local QUARTER = 3                        -- Sources transport tap
    local melody = { 60, 62, 64, 67, 69, 67, 64, 62, 60, 64, 67, 72, 71, 67, 64, 60 }
    local a, b = Engine.lanes[1], Engine.lanes[2]
    for i = 1, 16 do
        a.pitch[i] = melody[i]
        a.velocity[i] = 70 + (i % 4) * 15
        b.gate[i] = (i * 7) % 3 ~= 0 and 1 or 0
    end
    a.advanceSource = QUARTER
    b.type = "trig"; b.division = 4; b.advanceSource = QUARTER
    Lane.setDims(b, "4x4")
    Engine.onStart()
end

return M
