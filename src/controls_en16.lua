-- controls_en16.lua  (slim)
local Engine   = require("engine")
local Step     = require("step")
local Controls = require("controls")

local M = {}
M.NUM_ENC = 16
M.LED = {
    valueMax    = 200,
    valueMin    = 20,
    audibleBase = 30,
    playhead    = 255,
    off         = 0,
    beautify    = 0,
}

local function resolve(idx)
    if idx < 1 or idx > 16 then return nil, nil end
    local tr = Engine.tracks[Controls.selT]
    if not tr then return nil, nil end
    return tr, Controls.viewportLo(Controls.viewport) + (idx - 1)
end

function M.onEncoder(idx, delta)
    local f = Controls.focus
    if f == 7 or f == 5 then return end
    local tr, s = resolve(idx); if not tr then return end
    Controls.setSelectedStep(s)
    Controls.setParam(f, Controls.selT, s, delta > 0 and 1 or -1)
    Controls.dirtyValueCells()
end

function M.onEncoderPress(idx)
    local tr, s = resolve(idx); if not tr then return end
    if Controls.focus == 7 then
        Engine.setLastStep(Controls.selT, s)
    else
        Engine.setStepParam(Controls.selT, s, "mute",
            Step.muted(tr.steps[s]) and 0 or 1)
    end
    Controls.dirtyValueCells()
end

local function modeValue(stp, f)
    if f == 1 then return Step.pitch(stp) end
    if f == 2 then return Step.vel(stp)   end
    if f == 3 then
        return Controls.shift and Step.dur(stp) or Step.gate(stp)
    end
    if f == 4 then return Step.muted(stp) and 0 or 127 end
    return 127   -- STEP / LASTSTEP / reserved
end

function M.refreshLeds(emit)
    local tr = Engine.tracks[Controls.selT]; if not tr then return end
    local lo    = Controls.viewportLo(Controls.viewport)
    local focus = Controls.focus
    local mr, mg, mb = Controls.modeColor(focus)
    local L = M.LED
    local vmin, vmax = L.valueMin, L.valueMax
    local off, ab, ph_b = L.off, L.audibleBase, L.playhead

    local ph = 0
    if Engine.running and tr.pos >= lo and tr.pos < lo + 16 then
        ph = tr.pos - lo + 1
    end

    for i = 1, 16 do
        local s   = lo + i - 1
        local oor = (s > tr.lastStep)
        local stp = tr.steps[s]
        local muted = (not oor) and Step.muted(stp)

        -- press layer
        local p
        if oor or muted then p = off
        elseif i == ph    then p = ph_b
        else                   p = ab end
        emit(i, 1, p, p, p)

        -- turn layer
        if oor or muted then
            emit(i, 2, off, off, off)
        else
            local v = modeValue(stp, focus)
            local b = vmin + ((vmax - vmin) * v) // 127
            emit(i, 2, (mr * b) // 255, (mg * b) // 255, (mb * b) // 255)
        end
    end
end

return M
