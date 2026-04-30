-- controls_en16.lua
-- Engine-side EN16 surface. Reads Controls.focus to know which step
-- parameter to edit; both VSN1 endless and EN16 encoders are unified
-- through the same MODE.
--
-- Public API:
--   M.onEncoder(idx, delta)        1..16. Selects that step on VSN1 (so the
--                                  screen tracks what the user is touching),
--                                  then edits in current MODE.
--   M.onEncoderPress(idx)          1..16. Selects that step on VSN1, and in
--                                  MUTE mode (focus==5) also toggles mute.
--   M.refreshLeds(emit)            emit(idx, brightness) per encoder
--
-- Brightness scale (raw values, no constants table):
--   0   muted
--   80  audible
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
-- using the currently selected track and its current region.
local function resolve(idx)
    if idx < 1 or idx > 16 then return nil, nil end
    local tr = Engine.tracks[Controls.selT]
    if not tr then return nil, nil end
    return tr, Track.regionLo(tr.curRegion) + (idx - 1)
end

-- Encoder turn: move VSN1 selection to that step (so the screen reflects
-- what the user is editing), then edit in the current mode.
function M.onEncoder(idx, delta)
    local tr, s = resolve(idx)
    if not tr then return end
    Controls.setSelectedStep(s)
    local d = delta > 0 and 1 or -1
    Controls.setParam(Controls.focus, Controls.selT, s, d)
    Controls.dirtyValueCells()
end

-- Encoder press: always move VSN1 selection to that step. In MUTE mode
-- (focus 5), also toggle the step's mute.
function M.onEncoderPress(idx)
    local tr, s = resolve(idx)
    if not tr then return end
    Controls.setSelectedStep(s)
    if Controls.focus == 5 then
        local newMute = Step.muted(tr.steps[s]) and 0 or 1
        Engine.setStepParam(Controls.selT, s, "mute", newMute)
        Controls.dirtyValueCells()
    end
end

-- Compute brightness per encoder. Caller dedupes.
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
        elseif Step.muted(tr.steps[lo + i - 1]) then b = 0
        else b = 80 end
        emit(i, b)
    end
end

return M
