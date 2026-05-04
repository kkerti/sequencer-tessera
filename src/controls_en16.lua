-- controls_en16.lua
-- Engine-side EN16 surface. Reads Controls (selT, viewport, focus); both
-- VSN1 endless and EN16 encoders are unified through the same MODE.
--
-- Public API:
--   M.onEncoder(idx, delta)        1..16. Selects that step on VSN1, then
--                                  edits in current MODE. Inert in LASTSTEP.
--   M.onEncoderPress(idx)          1..16. Toggles mute on that step. In
--                                  LASTSTEP mode, sets the track's lastStep
--                                  to that absolute step index. SHIFT+press
--                                  is intercepted by VSN1.lua and routed
--                                  to Controls.setSelectedStep instead.
--   M.refreshLeds(emit)            emit(idx, layer, r, g, b) per LED.
--                                  layer 1 = press color (white wash for
--                                            audible / playhead / off).
--                                  layer 2 = turn color (mode color
--                                            scaled by per-step value).
--
-- All emit callbacks are cache-gated by the caller (one immediate_send
-- per CHANGED LED layer).

local Engine   = require("engine")
local Step     = require("step")
local Controls = require("controls")

local M = {}
M.NUM_ENC = 16

-- ---- LED brightness defaults (tunable; one place) ----
M.LED = {
    valueMax    = 200,   -- turn-layer brightness for value=127
    valueMin    = 20,    -- turn-layer brightness for value=0   (still visible)
    audibleBase = 30,    -- press-layer floor for non-muted, non-playhead
    playhead    = 255,   -- press-layer brightness on the active step
    off         = 0,     -- muted / out-of-range
    beautify    = 0,     -- 0 = honor zero exactly; 1 = firmware floor glow
}

-- ---- step resolution ----
local function resolve(idx)
    if idx < 1 or idx > 16 then return nil, nil end
    local tr = Engine.tracks[Controls.selT]
    if not tr then return nil, nil end
    return tr, Controls.viewportLo(Controls.viewport) + (idx - 1)
end

-- ---- input ----

function M.onEncoder(idx, delta)
    if Controls.focus == Controls.MODE_LASTSTEP then return end
    local tr, s = resolve(idx)
    if not tr then return end
    Controls.setSelectedStep(s)
    local d = delta > 0 and 1 or -1
    Controls.setParam(Controls.focus, Controls.selT, s, d)
    Controls.dirtyValueCells()
end

function M.onEncoderPress(idx)
    local tr, s = resolve(idx)
    if not tr then return end
    if Controls.focus == Controls.MODE_LASTSTEP then
        Engine.setLastStep(Controls.selT, s)
    else
        local newMute = Step.muted(tr.steps[s]) and 0 or 1
        Engine.setStepParam(Controls.selT, s, "mute", newMute)
    end
    Controls.dirtyValueCells()
end

-- ---- value-per-mode lookup ----
-- Returns 0..127 representing "how much" of the current mode this step
-- carries. Used to scale turn-layer brightness.
local function modeValue(stp, focus)
    if focus == Controls.MODE_NOTE  then return Step.pitch(stp) end
    if focus == Controls.MODE_VEL   then return Step.vel(stp)   end
    if focus == Controls.MODE_GATE  then return Step.gate(stp)  end
    if focus == Controls.MODE_DUR   then return Step.dur(stp)   end
    if focus == Controls.MODE_MUTE  then
        return Step.muted(stp) and 0 or 127
    end
    if focus == Controls.MODE_RATCH then
        return Step.ratch(stp) and 127 or 0
    end
    -- LASTSTEP mode: brightness encodes "is this slot within lastStep"
    return 127
end

local function scaleColor(r, g, b, brightness)
    -- brightness 0..255 → scale RGB linearly. Cheap; no clamps needed
    -- because inputs are already clamped.
    local f = brightness
    return (r * f) // 255, (g * f) // 255, (b * f) // 255
end

-- ---- LED refresh ----
-- emit signature: emit(idx, layer, r, g, b)
function M.refreshLeds(emit)
    local tr = Engine.tracks[Controls.selT]; if not tr then return end
    local lo = Controls.viewportLo(Controls.viewport)
    local focus = Controls.focus
    local mr, mg, mb = Controls.modeColor(focus)
    local L = M.LED

    -- which encoder mirrors the playhead, if any
    local ph = 0
    if Engine.running and tr.pos >= lo and tr.pos < lo + 16 then
        ph = tr.pos - lo + 1
    end

    for i = 1, 16 do
        local s   = lo + i - 1
        local oor = (s > tr.lastStep)
        local stp = tr.steps[s]
        local muted = (not oor) and Step.muted(stp)

        -- ---- press layer (layer 1): white wash ----
        local pr, pg, pb
        if oor or muted then
            pr, pg, pb = L.off, L.off, L.off
        elseif i == ph then
            pr, pg, pb = L.playhead, L.playhead, L.playhead
        else
            pr, pg, pb = L.audibleBase, L.audibleBase, L.audibleBase
        end
        emit(i, 1, pr, pg, pb)

        -- ---- turn layer (layer 2): mode color scaled by value ----
        local tr_, tg_, tb_
        if oor or muted then
            tr_, tg_, tb_ = L.off, L.off, L.off
        else
            local v = modeValue(stp, focus)
            local b = L.valueMin + ((L.valueMax - L.valueMin) * v) // 127
            tr_, tg_, tb_ = scaleColor(mr, mg, mb, b)
        end
        emit(i, 2, tr_, tg_, tb_)
    end
end

return M
