-- proto/term/main.lua — headless terminal harness for the sequencer Core.
--
-- External clock from Ableton (through tools/bridge.py):
--   python3 tools/bridge.py --lua "lua proto/term/main.lua"
--
-- Internal test clock (no Ableton; prints the note protocol to the terminal):
--   lua proto/term/main.lua --bpm 120
--
-- Stdin protocol (one per line, from bridge.py):
--   CLK | START | STOP | QUIT | LOAD <slot>
--   NOTE <note> <vel> <ch> | CC <cc> <val> <ch>   (mapped by io/midi_in)

package.path = "src/core/?.lua;src/?.lua;" .. package.path

local Engine  = require("engine")
local Stdio   = require("io.stdio")
local MidiIn  = require("io.midi_in")
local Persist = require("persist")

local bpm = nil
local preset = nil
for i = 1, #arg do
    if arg[i] == "--bpm" then bpm = tonumber(arg[i + 1]) end
    if arg[i] == "--preset" then preset = tonumber(arg[i + 1]) end
end

Engine.init{ lanes = 4, channel = 1 }
Stdio.attach()

-- Default musical pattern (C major) on lane 1. Presets override it.
for i = 2, 4 do Engine.setType(i, "trig") end   -- unused lanes stay silent
Engine.setType(1, "note")
Engine.setChannel(1, 1)
Engine.setScale(1, 0xAB5, 0)
Engine.setDivision(1, 1)
Engine.setAdvanceSource(1, "transport.sixteenth")
local melody = { 60, 62, 64, 67, 69, 67, 64, 62, 60, 64, 67, 72, 71, 67, 64, 60 }
for i = 1, 16 do
    Engine.setPitch(1, i, melody[i])
    Engine.setVelocity(1, i, 70 + (i % 4) * 15)
    Engine.setStepLength(1, i, 4)
end

if preset then Persist.load(Persist.slotPath(preset)) end

if bpm then
    local interval = 60.0 / (bpm * 24)   -- seconds per 24-PPQN pulse
    local function sleep(sec) local t = os.clock() + sec; while os.clock() < t do end end
    io.stderr:write(string.format("[seq3] internal clock @ %g BPM (Ctrl-C to stop)\n", bpm))
    Engine.onStart()
    while true do
        Stdio.emit(Engine.onPulse())
        sleep(interval)
    end
else
    Engine.onStart()
    for line in io.lines() do
        if line == "CLK" then
            Stdio.emit(Engine.onPulse())
        elseif line == "START" then
            Stdio.emit(Engine.onStart())
        elseif line == "STOP" then
            Stdio.emit(Engine.onStop())
        elseif line:match("^LOAD ") then
            Persist.load(Persist.slotPath(tonumber(line:match("%d+"))))
        elseif line:sub(1, 5) == "NOTE " or line:sub(1, 3) == "CC " then
            MidiIn.handle(line)
        elseif line == "QUIT" then
            break
        end
    end
end
