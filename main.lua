-- main.lua  (macOS harness)
-- Loads the engine, applies a patch, drives it from stdin pulse lines.
--
-- Stdin protocol (one per line):
--   START
--   STOP
--   CLK         (advance one pulse)
--   QUIT
--
-- All MIDI events are written to stdout via driver_stdio.
-- Engine activity is also logged to sequencer.log.

package.path = "src/?.lua;patches/?.lua;" .. package.path

local Engine = require("engine")
local Step   = require("step")
local Driver = require("driver_stdio")

-- log file
local logFile = io.open("sequencer.log", "w")
local function log(s)
    if logFile then logFile:write(s .. "\n"); logFile:flush() end
end

Engine.init({ trackCount = 4, stepsPerTrack = 64, log = log })

-- Apply patch
local function applyPatch(p)
    for ti = 1, math.min(#p.tracks, #Engine.tracks) do
        local pt = p.tracks[ti]
        local tr = Engine.tracks[ti]
        tr.chan = pt.chan or tr.chan
        tr.div  = pt.div  or tr.div
        tr.dir  = pt.dir  or tr.dir
        for si = 1, math.min(#pt.steps, tr.cap) do
            tr.steps[si] = Step.pack(pt.steps[si])
        end
    end
end

local patch = require("default")
applyPatch(patch)
log(string.format("loaded patch: %d tracks", #patch.tracks))

-- Drive loop
for line in io.lines() do
    if line == "START" then
        Driver.note("START")
        Engine.onStart()
    elseif line == "STOP" then
        Driver.note("STOP")
        local off = Engine.onStop()
        Driver.emit(off)
    elseif line == "CLK" then
        Driver.tickPulse()
        local ev = Engine.onPulse()
        if ev then Driver.emit(ev) end
    elseif line:sub(1,3) == "REG" then
        -- "REG 2" -> queue region 2
        local r = tonumber(line:sub(5))
        Engine.setQueuedRegion(r)
        Driver.note("QUEUE " .. tostring(r))
    elseif line == "QUIT" then
        break
    end
end

if logFile then logFile:close() end
