-- tests/euclidean/test_engine.lua
package.path = "src/?.lua;" .. package.path

local Engine = require("euclidean.engine")
local Track  = require("euclidean.track")

local M = {}

local function eq(a, b, msg)
    if a ~= b then
        error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
    end
end

function M.test_init_creates_4_tracks()
    Engine.init({ trackCount = 4 })
    eq(#Engine.tracks, 4)
    eq(Engine.tracks[1].chan, 0)
    eq(Engine.tracks[4].chan, 3)
end

function M.test_pulse_when_stopped_returns_nil()
    Engine.init({})
    eq(Engine.onPulse(), nil)
end

function M.test_start_then_pulse_emits()
    Engine.init({ trackCount = 1 })
    Engine.setSteps(1, 4)
    Engine.setEvents(1, 4)
    Engine.setPpstep(1, 1)
    Engine.setGate(1, 1)
    Engine.setKey(1, 60)
    Engine.onStart()
    local ev = Engine.onPulse()
    if not ev then error("expected events on first pulse after start") end
    eq(ev[1].type, Track.EV_ON)
    eq(ev[1].pitch, 60)
end

function M.test_stop_emits_alloff_for_active_notes()
    Engine.init({ trackCount = 1 })
    Engine.setSteps(1, 4)
    Engine.setEvents(1, 4)
    Engine.setPpstep(1, 4)        -- long step
    Engine.setGate(1, 4)          -- long gate so note is still on at stop
    Engine.setKey(1, 60)
    Engine.onStart()
    Engine.onPulse()              -- triggers note on
    local off = Engine.onStop()
    local found = false
    for _, e in ipairs(off) do
        if e.type == Track.EV_OFF and e.pitch == 60 then found = true end
    end
    if not found then error("expected NOTE_OFF on stop") end
end

function M.test_polyrhythm_independent_advance()
    Engine.init({ trackCount = 2 })
    Engine.setSteps(1, 3); Engine.setEvents(1, 3); Engine.setPpstep(1, 1); Engine.setGate(1, 1)
    Engine.setSteps(2, 4); Engine.setEvents(2, 4); Engine.setPpstep(2, 1); Engine.setGate(2, 1)
    Engine.onStart()
    -- 12 pulses = LCM(3,4); both tracks complete integer cycles
    local ons = { 0, 0 }
    for _ = 1, 12 do
        local ev = Engine.onPulse()
        if ev then
            for _, e in ipairs(ev) do
                if e.type == Track.EV_ON then
                    ons[e.ch + 1] = ons[e.ch + 1] + 1
                end
            end
        end
    end
    eq(ons[1], 12, "track 1: 4 cycles of 3 events")
    eq(ons[2], 12, "track 2: 3 cycles of 4 events")
end

function M.test_setEvents_recomputes_pattern()
    Engine.init({ trackCount = 1 })
    Engine.setSteps(1, 8)
    Engine.setEvents(1, 0)
    eq(Engine.tracks[1].hits, 0)
    Engine.setEvents(1, 8)
    eq(Engine.tracks[1].hits, 0xFF)
end

-- Regression: changing key while a note is sounding must NOT leave the
-- old pitch hanging. The eventual NOTE_OFF must address the pitch that
-- was actually started, not the new key. Same invariant for chan.
function M.test_setKey_midnote_does_not_hang_old_pitch()
    Engine.init({ trackCount = 1 })
    Engine.setSteps(1, 4); Engine.setEvents(1, 4)
    Engine.setPpstep(1, 4); Engine.setGate(1, 4); Engine.setKey(1, 60)
    Engine.onStart()
    -- pulse 1 fires step 0 (a hit) -> NOTE_ON 60. actOff = 4.
    local ev = Engine.onPulse()
    eq(ev[1].type, Track.EV_ON); eq(ev[1].pitch, 60)
    -- user turns KEY encoder up to 67 mid-note
    Engine.setKey(1, 67)
    -- ticks 2..4 just count down; OFF lands at the start of pulse 5
    -- (when actOff hits 0 after decrement). Drain pulses until we see it.
    local off
    for _ = 1, 6 do
        local r = Engine.onPulse()
        if r then for i = 1, #r do if r[i].type == Track.EV_OFF then off = r[i] break end end end
        if off then break end
    end
    if not off then error("expected a NOTE_OFF after key change") end
    eq(off.pitch, 60, "OFF must address the original pitch, not the new key")
end

return M
