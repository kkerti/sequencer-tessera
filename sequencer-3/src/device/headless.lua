-- headless.lua — NO GUI. The smallest device adapter that proves the engine:
-- clock in -> lanes advance -> MIDI notes out, plus a periodic text report of
-- the lanes on the debug console.
--
-- Why it exists: screen.lua + menu.lua are 8.6 KB of stripped source and the
-- module ran out of memory initialising them. This path never compiles either,
-- so the resident set is the core plus ~2 KB.
--
-- Device rules: no string.format, no table.concat, no collectgarbage (the
-- profile's timer event prints the RAM figure). Report lines are built by
-- concatenation and only ever run from the timer, never from the pulse path,
-- so Engine.onPulse stays allocation-free.

local M = {}

local Engine, Data
local started = false

-- One-time load: engine, then the sequence, then run. Each stage prints, so
-- the console shows exactly how far a boot got.
function M.ensure()
    if started then return end
    started = true
    print("seq3h: engine")
    Engine = require("engine")
    print("seq3h: engine ok")
    Data = require("seq_data")
    Data.apply(Engine)
    print("seq3h: sequence ok")
    Engine.onStart()
    print("seq3h: running")
end

-- Emit an engine.out buffer through the caller's send (midi_send on device).
local function emit(out, send)
    local n = out.n
    local typ, pitch, vel, ch = out.typ, out.pitch, out.velocity, out.channel
    for i = 1, n do
        local t = typ[i]
        if t == 1 then
            send(ch[i], 0x90, pitch[i], vel[i])
        elseif t == 2 then
            send(ch[i], 0xB0, pitch[i], vel[i])
        else
            send(ch[i], 0x80, pitch[i], 0)
        end
    end
end

-- MIDI in. 0xF8 clock, 0xFA start, 0xFB continue, 0xFC stop.
function M.handle(t, send)
    M.ensure()
    if t == 0xF8 then
        emit(Engine.onPulse(), send)
    elseif t == 0xFA then
        Engine.onStart()
    elseif t == 0xFB then
        if not Engine.running then Engine.onStart() end
    elseif t == 0xFC then
        emit(Engine.onStop(), send)
    end
end

-- A control press loads the chain too, so the sequence can be armed without a
-- DAW attached.
function M.key() M.ensure() end

local function limit(l)
    if l.height == 1 then return l.length end
    return l.width * l.height
end

-- What a lane is sounding right now, as text.
local function playing(l)
    if l.type == "mod" then return "cc" .. l.controller .. "=" .. l.value[l.position] end
    if not l.activeNote then return "-" end
    return "n" .. l.activeNote
end

-- Called from the profile's timer event: one line per lane. This is the whole
-- "show me the lanes are playing" surface.
function M.report()
    if not Engine then
        print("seq3h: idle (send clock or press a key)")
        return
    end
    for i = 1, #Engine.lanes do
        local l = Engine.lanes[i]
        print("L" .. i .. " " .. l.type
              .. " ch" .. l.channel
              .. " step " .. l.position .. "/" .. limit(l)
              .. " " .. playing(l)
              .. (Engine.running and "" or " STOPPED"))
    end
end

return M
