-- midi_rx.lua — device MIDI receiver: 0xF8 clock -> engine pulse -> MIDI out.
-- The send function is supplied by the caller; on device that is `midi_send`
-- (seq-1's proven wiring — gms/grxm was never part of a cold-boot-proven
-- profile).
--
-- LAZY (v5): the profile requires NOTHING at setup and does not even route
-- clock here until the first CONTROL PRESS — cold boot runs a pure counter in
-- the event script, because the full first-byte chain (engine + deps ≈ 21 KB
-- source) still overshot the module's cold-boot budget. Loading this module
-- compiles the whole sequencer chain + demo, in stages, with a printed
-- ladder: the Grid console shows exactly how far each load got.
--
--   handle(t, send):
--     0xF8 clock  -> pulse; emit engine.out via send;        returns "tick"
--     0xFA/0xFB   -> onStart if not running;                 returns "start"
--     0xFC stop   -> onStop(); emit note-offs;               returns "stop"
--
-- status(lcd) draws the plain lane view; ui(lcd) routes to the screen once
-- it is loaded. Long draw names here: FS modules minify on upload.

local M = {}
local Engine, Boot

-- One-time load + demo fill. midi_rx -> device_boot -> engine chain.
-- (Exposed as M.ensure for the screen module.) Prints are the boot ladder.
function M.ensure()
    if not Engine then
        print("seq3: loading engine")
        Engine = require("engine")
        print("seq3: engine ok")
        Boot   = require("device_boot")
        Boot.demo()
        print("seq3: demo ok")
    end
end

-- Emit an engine.out buffer via the caller's send. typ 1=note on, 0=note
-- off, 2=control; pitch carries note or CC number.
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

function M.handle(t, send)
    if not Engine then return end             -- not loaded until first press
    if t == 0xF8 then
        Engine.onPulse()
        emit(Engine.out, send)
    elseif t == 0xFA or t == 0xFB then
        if not Engine.running then Engine.onStart() end
    elseif t == 0xFC then
        emit(Engine.onStop(), send)
    end
end

-- Plain status view for the draw event: clear + one line per lane.
-- Does NOT ensure(): before the first key press this must stay free.
-- Repaints only when something changed (the draw event fires every frame;
-- a full clear + text each frame made the idle screen blink and churned
-- strings for nothing). sig is the last painted state, -1 = never painted.
local sig = -1
function M.status(lcd)
    local s = 0
    if Engine then
        s = Engine.running and 1 or 2
        for i = 1, #Engine.lanes do s = s * 17 + Engine.lanes[i].position end
    end
    if s == sig then return end
    sig = s
    lcd:draw_rectangle_filled(0, 0, 319, 239, { 12, 12, 16 })
    if not Engine then
        lcd:draw_text_fast("seq3: press a key to load", 8, 110, 16, { 120, 220, 255 })
    else
        for i = 1, #Engine.lanes do
            local l = Engine.lanes[i]
            lcd:draw_text_fast(i .. " " .. l.type .. " " .. l.position,
                8, 8 + (i - 1) * 24, 16, { 120, 220, 255 })
        end
        lcd:draw_text_fast("press a key for the screen", 8, 200, 16, { 120, 120, 140 })
    end
    lcd:draw_swap()
end

-- ------------------------------------------------------------- screen ---
-- LAZY GUI: the full screen loads on the first control press (NOT at boot or
-- draw), so idle runtime stays at the core-only budget. It is its own bundle
-- (seq3s): when it shared seq3ui, requiring midi_rx compiled it at start.
-- SCR is cached. key/btn/turn/press forward into the screen module.

local SCR

-- First control press: compile the chain, then the screen. Each stage prints.
local function loadSCR()
    if SCR then return SCR end
    M.ensure()
    print("seq3: loading screen")
    SCR = require("screen")
    print("seq3: screen ok")
    return SCR
end

function M.key(i)    local s = loadSCR(); s.key(i) end
function M.btn(i)    local s = loadSCR(); s.btn(i) end
function M.press()   local s = loadSCR(); s.press() end
function M.turn(d)
    if d ~= 0 then
        local s = loadSCR(); s.turn(d)
    end
end

-- Draw event: the screen (once loaded) draws itself when dirty; the idle
-- status view runs until the first control press.
function M.ui(lcd)
    if SCR then
        SCR.draw(lcd)
    else
        M.status(lcd)
    end
end

return M
