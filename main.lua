-- main.lua
-- Dev harness: load a patch descriptor → build engine → drive it live.
-- Pipe to bridge.py for MIDI:
--
--   lua main.lua [patch] | python3 bridge.py
--
-- Where [patch] is a module path (default: "patches/dark_groove").

local uv          = require("luv")
local PatchLoader = require("sequencer/patch_loader")
local Driver      = require("driver/driver")

-- ── Load patch ───────────────────────────────────────────────────────────────

local patchPath = arg[1] or "patches/dark_groove"
local engine    = PatchLoader.load(patchPath)

-- ── Clock + emit ─────────────────────────────────────────────────────────────

local function clockFn() return uv.now() end

local function emit(eventType, pitch, velocity, channel)
    if eventType == "NOTE_ON" then
        io.write("NOTE_ON " .. pitch .. " " .. velocity .. " " .. channel .. "\n")
    else
        io.write("NOTE_OFF " .. pitch .. " " .. channel .. "\n")
    end
end

-- ── Driver ───────────────────────────────────────────────────────────────────

local driver     = Driver.new(engine, clockFn)
local intervalMs = math.floor(driver.pulseMs / 2)

Driver.start(driver)

-- ── Timer + signal ───────────────────────────────────────────────────────────

local timer  = uv.new_timer()
local sigint = uv.new_signal()

local function flushAllNotes()
    Driver.allNotesOff(driver, emit)
    io.flush()
end

uv.signal_start(sigint, "sigint", function()
    io.stderr:write("[main] SIGINT — flushing notes and exiting\n")
    flushAllNotes()
    uv.timer_stop(timer)
    uv.stop()
end)

io.stderr:write(string.format(
    "[main] patch=%s  bpm=%d  ppb=%d  tracks=%d  tick=%dms\n",
    patchPath, engine.bpm, engine.pulsesPerBeat, engine.trackCount, intervalMs))

uv.timer_start(timer, 0, intervalMs, function()
    Driver.tick(driver, emit)
    io.flush()
end)

uv.run()
