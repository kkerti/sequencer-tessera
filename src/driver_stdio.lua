-- driver_stdio.lua
-- macOS event sink. Writes line protocol to stdout for bridge.py to consume.
--
-- Line protocol (one event per line):
--   ON <pitch> <vel> <ch>
--   OFF <pitch> <ch>
--
-- Also mirrors every emitted event into midi_out.log with a pulse counter
-- and timestamp, for static post-run analysis.

local Track = require("track")

local M = {}

local logFile  = io.open("midi_out.log", "w")
local pulseIdx = 0

-- Called by main.lua right before each Engine.onPulse() so the log can
-- attribute events to a pulse number.
function M.tickPulse()
    pulseIdx = pulseIdx + 1
end

local function logLine(s)
    if not logFile then return end
    logFile:write(string.format("[p=%06d t=%.4f] %s\n",
        pulseIdx, os.clock(), s))
    logFile:flush()
end

function M.note(msg)
    logLine("-- " .. msg)
end

function M.emit(events)
    if not events then return end
    for i = 1, #events do
        local e = events[i]
        if e.type == Track.EV_ON then
            local line = string.format("ON %d %d %d", e.pitch, e.vel, e.ch)
            io.write(line, "\n")
            logLine(line)
        else
            local line = string.format("OFF %d %d", e.pitch, e.ch)
            io.write(line, "\n")
            logLine(line)
        end
    end
    io.flush()
end

return M
