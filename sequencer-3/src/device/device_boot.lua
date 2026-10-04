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

-- Demo pattern, FOUR lanes, each at its own rate against one clock:
--   L1 note ch1  melody, 16 steps on quarters
--   L2 trig ch2  4x4 pattern, quarters / 4
--   L3 note ch3  bass, 8 steps on eighths
--   L4 trig ch4  hats (note 42), 16 steps on sixteenths
-- Lane fields are written DIRECTLY, not through the setters: the setters live
-- in a lazy bundle (edit.lua), and app start must not compile it.
-- Starts running; Ableton start/stop overrides.
function M.demo()
    Engine.init{ lanes = 4, channel = 1 }
    local QUARTER, EIGHTH, SIXTEENTH = 3, 4, 5      -- Sources transport taps
    local melody = { 60, 62, 64, 67, 69, 67, 64, 62, 60, 64, 67, 72, 71, 67, 64, 60 }
    local bass = { 36, 36, 43, 36, 41, 41, 39, 43 }
    local a, b, c, d = Engine.lanes[1], Engine.lanes[2], Engine.lanes[3], Engine.lanes[4]
    for i = 1, 16 do
        a.pitch[i] = melody[i]
        a.velocity[i] = 70 + (i % 4) * 15
        b.gate[i] = (i * 7) % 3 ~= 0 and 1 or 0
        d.gate[i] = (i % 4 ~= 1) and 1 or 0
        d.velocity[i] = (i % 2 == 0) and 110 or 70
        d.stepLength[i] = 2
    end
    for i = 1, 8 do c.pitch[i] = bass[i]; c.stepLength[i] = 10 end
    a.advanceSource = QUARTER
    b.type = "trig"; b.division = 4; b.advanceSource = QUARTER
    Lane.setDims(b, "4x4")
    c.length = 8; c.advanceSource = EIGHTH
    c.rawScaleMask, c.scaleMask = 0, 0                -- bass plays as written
    d.type = "trig"; d.midiNote = 42; d.advanceSource = SIXTEENTH
    Engine.onStart()
end

return M
