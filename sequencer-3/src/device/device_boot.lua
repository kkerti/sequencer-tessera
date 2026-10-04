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

-- Demo pattern, FOUR lanes:
--   L1 note ch1  melody, 4x4: X on eighths, Y on quarter triplets
--   L2 trig ch2  5x3 pattern: X on sixteenths, Y on quarters
--   L3 note ch3  bass, 8 steps, advanced by L2's hits (lane -> lane)
--   L4 trig ch4  hats (note 42), 16 steps on sixteenths
-- Lane fields are written DIRECTLY, not through the setters: the setters live
-- in a lazy bundle (edit.lua), and app start must not compile it.
-- Starts running; Ableton start/stop overrides.
function M.demo()
    Engine.init{ lanes = 4, channel = 1 }
    -- Sources enums: transport taps, quarter triplet, lane 2 fired
    local QUARTER, EIGHTH, SIXTEENTH, QTRIPLET, LANE2 = 3, 4, 5, 6, 12
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
    Lane.setDims(a, "4x4"); a.xAdvanceSource = EIGHTH; a.yAdvanceSource = QTRIPLET
    b.type = "trig"; Lane.setDims(b, "5x3")
    b.xAdvanceSource = SIXTEENTH; b.yAdvanceSource = QUARTER
    c.length = 8; c.advanceSource = LANE2
    c.rawScaleMask, c.scaleMask = 0, 0                -- bass plays as written
    d.type = "trig"; d.midiNote = 42; d.advanceSource = SIXTEENTH
    Engine.onStart()
end

return M
