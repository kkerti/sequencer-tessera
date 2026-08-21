-- tools/play.lua
-- Self-contained macOS harness driving the engine from a luv timer at a
-- chosen BPM. Writes the bridge.py line protocol on stdout AND mirrors to
-- midi_out.log. Auto-exits after a fixed duration.
--
-- Usage:
--     lua tools/play.lua [bpm] [seconds] [patch]
--     lua tools/play.lua                 -> 120 BPM, 4s, default patch
--     lua tools/play.lua 100 8 default   -> 100 BPM, 8s
--
-- Pipe to bridge.py to hear it in Ableton:
--     lua tools/play.lua 120 8 default | python3 tools/bridge.py

package.path = "src/?.lua;patches/?.lua;" .. package.path

local uv     = require("luv")
local Engine = require("engine")
local Step   = require("step")
local Track  = require("track")

local bpm     = tonumber(arg[1]) or 120
local seconds = tonumber(arg[2]) or 4
local patchN  = arg[3] or "default"

local PPQN = 24
local pulseMs = 60000.0 / (bpm * PPQN)   -- ms between MIDI clock pulses

-- ---- log -----------------------------------------------------------------
local logFile = io.open("midi_out.log", "w")
local pulseIx = 0
local function logf(fmt, ...)
    if not logFile then return end
    logFile:write(string.format("[p=%06d t=%.4f] " .. fmt .. "\n",
        pulseIx, uv.now() / 1000, ...))
    logFile:flush()
end

-- ---- engine + patch ------------------------------------------------------
Engine.init({ trackCount = 4, stepsPerTrack = 64,
              log = function(s) logf("ENG %s", s) end })

local patch = require(patchN)
for ti = 1, math.min(#patch.tracks, #Engine.tracks) do
    local pt, tr = patch.tracks[ti], Engine.tracks[ti]
    tr.len  = pt.len  or tr.len
    tr.chan = pt.chan or tr.chan
    tr.div  = pt.div  or tr.div
    tr.dir  = pt.dir  or tr.dir
    for si = 1, math.min(#pt.steps, tr.cap) do
        tr.steps[si] = Step.pack(pt.steps[si])
    end
end
logf("PATCH loaded %s (%d tracks)", patchN, #patch.tracks)
logf("CONFIG bpm=%d seconds=%d pulseMs=%.4f", bpm, seconds, pulseMs)

-- ---- emit handler --------------------------------------------------------
local nOn, nOff = 0, 0
local function emit(events)
    if not events then return end
    for i = 1, #events do
        local e = events[i]
        if e.type == Track.EV_ON then
            nOn = nOn + 1
            logf("ON  pitch=%3d vel=%3d ch=%d", e.pitch, e.vel, e.ch)
            io.write(string.format("ON %d %d %d\n", e.pitch, e.vel, e.ch))
        else
            nOff = nOff + 1
            logf("OFF pitch=%3d           ch=%d", e.pitch, e.ch)
            io.write(string.format("OFF %d %d\n", e.pitch, e.ch))
        end
    end
    io.flush()
end

-- ---- run ----------------------------------------------------------------
logf("START")
Engine.onStart()

local clockTimer = uv.new_timer()
local stopTimer  = uv.new_timer()

clockTimer:start(0, math.max(1, math.floor(pulseMs + 0.5)), function()
    pulseIx = pulseIx + 1
    local ev = Engine.onPulse()
    if ev then emit(ev) end
end)

stopTimer:start(seconds * 1000, 0, function()
    clockTimer:stop()
    local off = Engine.onStop()
    emit(off)
    logf("STOP")
    logf("SUMMARY pulses=%d notes_on=%d notes_off=%d", pulseIx, nOn, nOff)
    if logFile then logFile:close() end
    uv.stop()
end)

uv.run()
