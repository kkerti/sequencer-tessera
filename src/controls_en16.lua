-- controls_en16.lua
-- Engine-side EN16 surface. KEPT LIGHT on purpose: cache, palette, and
-- LED dedupe live in the EN16 grid profile, not here.
--
-- Behaviour: the 16 EN16 encoders are HARD-WIRED to NOTE (pitch) of the
-- 16 steps in the SELECTED TRACK's CURRENT REGION. The selected track is
-- whatever VSN1's controls module currently has selected (Controls.selT).
-- The VSN1 keyswitch focus has no effect on EN16; the two control
-- surfaces are independent.
--
-- Public API:
--   M.onEncoder(idx, delta)     1..16, delta = +/-1   -> pitch += delta
--   M.onEncoderPress(idx)       1..16                 -> toggle `active`
--   M.refreshLeds(emit)         emit(idx, brightness) per encoder
--
-- Brightness scale (raw values, no constants table):
--   0   inactive
--   80  active
--   255 playhead
--
-- The caller's `emit` decides what to do with the value (typically a
-- cache-gated immediate_send to EN16 at [0,1]).

local Engine   = require("engine")
local Track    = require("track")
local Step     = require("step")
local Controls = require("controls")

local M = {}
M.NUM_ENC = 16

-- Resolve the absolute step index in the buffer for encoder `idx` (1..16),
-- using the currently selected track and its current region. Returns the
-- track ref AND the absolute step index, both validated.
local function resolve(idx)
    if idx < 1 or idx > 16 then return nil, nil end
    local tr = Engine.tracks[Controls.selT]
    if not tr then return nil, nil end
    return tr, Track.regionLo(tr.curRegion) + (idx - 1)
end

function M.onEncoder(idx, delta)
    local tr, s = resolve(idx)
    if not tr then return end
    local d = delta > 0 and 1 or -1
    Engine.setStepParam(Controls.selT, s, "pitch", Step.pitch(tr.steps[s]) + d)
    -- VSN1's NOTE/VEL/etc. cells display the SELECTED step. If EN16 just
    -- edited that same step, mark value cells dirty so the screen reflects
    -- the change on the next draw tick.
    if s == Controls.selS then Controls.dirtyValueCells() end
end

function M.onEncoderPress(idx)
    local tr, s = resolve(idx)
    if not tr then return end
    local cur = Step.active(tr.steps[s]) and 1 or 0
    Engine.setStepParam(Controls.selT, s, "active", cur == 0 and 1 or 0)
    if s == Controls.selS then Controls.dirtyValueCells() end
end

-- Compute brightness per encoder and hand it to `emit`. Caller dedupes.
function M.refreshLeds(emit)
    local tr = Engine.tracks[Controls.selT]; if not tr then return end
    local lo = Track.regionLo(tr.curRegion)
    local ph = 0
    if Engine.running and tr.pos >= lo and tr.pos < lo + 16 then
        ph = tr.pos - lo + 1
    end
    for i = 1, 16 do
        local b
        if i == ph then b = 255
        elseif Step.active(tr.steps[lo + i - 1]) then b = 80
        else b = 0 end
        emit(i, b)
    end
end

return M
