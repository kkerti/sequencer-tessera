-- proto/term/main.lua — headless terminal harness for the sequencer Core.
--
-- External clock from Ableton (through tools/bridge.py):
--   python3 tools/bridge.py --lua "lua proto/term/main.lua --monitor"
--
-- Internal test clock (no Ableton; prints the note protocol to the terminal):
--   lua proto/term/main.lua --bpm 120 --monitor
--
-- Stdin protocol (one per line, from bridge.py or typed into its terminal):
--   CLK | START | STOP | QUIT
--   LOAD <slot> | SAVE <slot>                  (presets/NN.lua)
--   NOTE <note> <vel> <ch> | CC <cc> <val> <ch>   (mapped by io/midi_in)
--
-- Flags: --bpm <n> internal clock | --preset <n> load slot at boot
--        --monitor four-line lane view on stderr | --pulses <n> exit after n

package.path = "src/core/?.lua;src/?.lua;" .. package.path

local Engine  = require("engine")
local Stdio   = require("io.stdio")
local MidiIn  = require("io.midi_in")
local Persist = require("persist")
local Monitor = require("io.monitor")

local bpm, preset, maxPulses = nil, nil, nil
for i = 1, #arg do
    if arg[i] == "--bpm" then bpm = tonumber(arg[i + 1]) end
    if arg[i] == "--preset" then preset = tonumber(arg[i + 1]) end
    if arg[i] == "--pulses" then maxPulses = tonumber(arg[i + 1]) end
    if arg[i] == "--monitor" then Monitor.enabled = true end
    if arg[i] == "--plain" then Monitor.inPlace = false end
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

local function note(msg) io.stderr:write("[seq3] ", msg, "\n"); io.stderr:flush() end

if preset then
    local ok, err = Persist.load(Persist.slotPath(preset))
    note(ok and string.format("loaded slot %02d", preset)
            or string.format("slot %02d load failed: %s", preset, tostring(err)))
end

-- SAVE/LOAD from the stdin protocol. Both are off the pulse path.
local function doSave(slot)
    Monitor.reset()
    local ok, err = Persist.save(Persist.slotPath(slot))
    note(ok and string.format("saved slot %02d -> %s", slot, Persist.slotPath(slot))
            or string.format("slot %02d save failed: %s", slot, tostring(err)))
end

local function doLoad(slot)
    Monitor.reset()
    local ok, err = Persist.load(Persist.slotPath(slot))
    note(ok and string.format("loaded slot %02d", slot)
            or string.format("slot %02d load failed: %s", slot, tostring(err)))
end

if Monitor.enabled then Monitor.header() end

if bpm then
    local interval = 60.0 / (bpm * 24)   -- seconds per 24-PPQN pulse
    local function sleep(sec) local t = os.clock() + sec; while os.clock() < t do end end
    note(string.format("internal clock @ %g BPM (Ctrl-C to stop)", bpm))
    Engine.onStart()
    local n = 0
    while true do
        Stdio.emit(Engine.onPulse())
        Monitor.render(Engine)
        n = n + 1
        if maxPulses and n >= maxPulses then break end
        sleep(interval)
    end
    Stdio.emit(Engine.onStop())
    Monitor.render(Engine, true)
else
    Engine.onStart()
    for line in io.lines() do
        if line == "CLK" then
            Stdio.emit(Engine.onPulse())
            Monitor.render(Engine)
        elseif line == "START" then
            Stdio.emit(Engine.onStart())
            Monitor.render(Engine, true)
        elseif line == "STOP" then
            Stdio.emit(Engine.onStop())
            Monitor.render(Engine, true)
        elseif line:match("^SAVE%s+%d+") then
            doSave(tonumber(line:match("%d+")))
        elseif line:match("^LOAD%s+%d+") then
            doLoad(tonumber(line:match("%d+")))
        elseif line:sub(1, 5) == "NOTE " or line:sub(1, 3) == "CC " then
            MidiIn.handle(line)
        elseif line == "QUIT" then
            break
        end
    end
end
