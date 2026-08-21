-- src/euclidean/vsn1_app.lua
-- VSN1 input dispatch + transport/BPM state for the Euclidean engine.
-- Mirrors src/vsn1_app.lua in shape: thin handlers that mutate the
-- controls module then mark dirty.
--
-- Two clock-source modes are supported, selected at boot from
-- VSN1-euclid.lua via M.setClockMode():
--
--   "external"  pulses arrive from MIDI rx (0xF8). Transport via 0xFA/FC.
--               BPM is unknown to this module. Keyswitches 6,7 are no-ops.
--
--   "internal"  pulses arrive from a Grid element_timer scriptlet bound
--               to the device. This module owns BPM (default 120, range
--               30..240) and the play/stop bool. The device-side init
--               registers two callbacks via setBpmCallback / setTransportCallback
--               so this module can request `element_timer_start` rate
--               changes and timer start/stop without ever calling the
--               hardware API itself (Core layer stays IO-free).
--
-- We do not push to EN16 here. EN16 wiring is out of scope per project brief.

local Engine = require("euclidean.engine")

local M = {}

M.CTL = nil

-- Clock-source mode. Default "external" so an unconfigured boot keeps the
-- pre-existing MIDI-clock behaviour. VSN1-euclid.lua calls setClockMode
-- *before* the first input event, before controls.lua reads the flag.
M.clockMode = "external"

-- BPM state (only meaningful in "internal" mode). 30..240. Stored as int.
M.bpm = 120

-- Transport state (only mutated in "internal" mode; external mode leaves
-- transport entirely to the Engine which tracks `running` from MIDI start).
M.playing = false

-- Callbacks registered by the device entry-point. Both are no-ops by
-- default so calling them in tests / external mode is safe.
local NOOP = function() end
M._bpmCb       = NOOP   -- fn(ms_per_pulse)   schedule next timer interval
M._transportCb = NOOP   -- fn(playing_bool)   start/stop the timer

-- ms-per-pulse for a given BPM at 24 PPQN. Integer division so the
-- caller can hand the result straight to element_timer_start.
local function bpmToMs(b)
    if b < 30 then b = 30 elseif b > 240 then b = 240 end
    -- 60_000 ms / minute / (b beats * 24 pulses/beat)
    return 60000 // (b * 24)
end
M._bpmToMs = bpmToMs

function M.init(controls)
    M.CTL = controls
    if controls.setApp then controls.setApp(M) end
    controls.dirtyAll()
    return M
end

-- --- clock-mode + callbacks (called from VSN1-euclid.lua boot) -------------

function M.setClockMode(mode)
    if mode ~= "internal" and mode ~= "external" then return end
    M.clockMode = mode
    if M.CTL then M.CTL.dirtyAll() end
end

function M.setBpmCallback(fn)       M._bpmCb       = fn or NOOP end
function M.setTransportCallback(fn) M._transportCb = fn or NOOP end

-- --- BPM accessors (read by controls.lua's BPM row + delta handler) -------

function M.getBpm() return M.bpm end

function M.setBpm(b)
    if b < 30 then b = 30 elseif b > 240 then b = 240 end
    if b == M.bpm then return end
    M.bpm = b
    if M.CTL then M.CTL.dirtyAll() end
    M._bpmCb(bpmToMs(b))
end

-- --- transport (only used in internal mode; key 7 toggles) ----------------

function M.toggleTransport()
    if M.clockMode ~= "internal" then return end
    if M.playing then
        M.playing = false
        M._transportCb(false)
        Engine.onStop()                        -- flush note-offs
    else
        M.playing = true
        Engine.onStart()
        M._transportCb(true)
    end
    if M.CTL then M.CTL.dirtyAll() end
end

-- --- input dispatch -------------------------------------------------------

-- Keyswitches 1..8.
--   1 STEPS  2 PULSES  3 ROTATE  4 RATE  5 PITCH        <- focus modes (always)
--   6 BPM             internal-clock mode only          (no-op externally)
--   7 PLAY/STOP       internal-clock mode only          (no-op externally)
--   8 SHIFT           always
function M.onKey(idx, pressed)
    local CTL = M.CTL
    if idx == 8 then
        CTL.setShift(pressed)
        return
    end
    if not pressed then return end
    if idx >= 1 and idx <= 5 then
        CTL.onKey(idx)
    elseif idx == 6 then
        if M.clockMode == "internal" then CTL.onKey(idx) end
    elseif idx == 7 then
        if M.clockMode == "internal" then M.toggleTransport() end
    end
end

function M.onTurn(dir)         M.CTL.onEndless(dir)      end
function M.onClick()           M.CTL.onEndlessClick()    end
function M.onSmallBtn(sidx)    M.CTL.onSmallBtn(sidx)    end

-- Screen-draw scriptlet entry. The VSN1 runtime hands us `self` (the
-- screen) only inside the draw event; we forward it to the controls
-- module's draw(), which honours the dirty flag and only repaints when
-- something changed. Called from VSN1-euclid.lua section [3].
function M.draw(scr)           M.CTL.draw(scr)           end

return M
