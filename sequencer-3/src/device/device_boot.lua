-- device_boot.lua — device-side bootstrap. v0 is CORE ONLY (headless): the
-- profile load that pulled the GUI (host + widgets + layout_core) exceeded the
-- module RAM (183 KB > acceptable). Until each piece is re-added and measured,
-- this module only wires the engine: demo pattern + the pulse hook.
--
-- Device-code rules: device modules ship plain (no GC calls, no package
-- manipulation, no text formatting).

local Engine = require("engine")

local M = {}

-- One pulse from any source (MIDI clock via midi_rx, or a test hook). The GUI
-- host (when it returns) will replace this indirection.
function M.pulse()
    Engine.onPulse()
end

-- Demo pattern, filled through the action API: 1 note melody + 2 trig, both
-- advancing on the transport quarter. TWO LANES at boot (4-lane init costs
-- ~6 KB of step arrays; lanes 3/4 can be added from the menu later). Starts
-- running; Ableton start/stop overrides.
function M.demo()
    Engine.init{ lanes = 2, channel = 1 }
    local melody = { 60, 62, 64, 67, 69, 67, 64, 62, 60, 64, 67, 72, 71, 67, 64, 60 }
    for i = 1, 16 do
        Engine.setPitch(1, i, melody[i])
        Engine.setVelocity(1, i, 70 + (i % 4) * 15)
        Engine.setStepLength(1, i, 6)
    end
    local QUARTER = 3                        -- Sources transport tap
    Engine.setAdvanceSource(1, QUARTER)
    Engine.setType(2, "trig"); Engine.setDimensions(2, "4x4"); Engine.setDivision(2, 4)
    Engine.setAdvanceSource(2, QUARTER)
    for i = 1, 16 do Engine.setGate(2, i, (i * 7) % 3 ~= 0 and 1 or 0) end
    Engine.onStart()
end

return M
