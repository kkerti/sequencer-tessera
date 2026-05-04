-- controls_en16.lua  (EN16-side; standalone)
-- Holds shadow of the visible 16 steps + meta. No engine, no step module.
-- VSN1 broadcasts shadow + meta via immediate_send. EN16 recomputes LED
-- colors locally.
--
-- LED MODEL (color-only, no brightness):
--   Out-of-range step (i > lastStep) -> off (0,0,0)
--   Playhead step                    -> white (255,255,255)
--   Muted step                       -> dim red (40,0,0)
--   Normal step                      -> current focus mode color
--
-- One led_color call per encoder per state-change. No led_value at all.
-- Hardware ignores brightness because we keep value at the boot default.
--
-- Public API:
--   M.setShadow(i, packed)                packed step int
--   M.setMeta(focus, lastStep, ph, selS, vplo, shift)
--   M.refreshColors(emit)                 emit(idx, r, g, b)
--   M.invalidateAll()                     force next refresh to re-emit all

local M = {}
M.NUM_ENC = 16

M.SH = {}
for i = 1, 16 do M.SH[i] = 0 end
M.focus    = 1
M.lastStep = 16
M.playhead = 0
M.selS     = 1
M.vplo     = 1
M.shift    = 0

-- per-encoder last-emitted packed RGB (so refreshColors can diff cheaply)
M.LAST = {}
for i = 1, 16 do M.LAST[i] = -1 end

local MR = {  30, 255, 240, 220,  60,  70, 230 }
local MG = { 200, 140, 210,  50, 120,  70, 230 }
local MB = { 220,  30,  40,  50, 255,  75, 230 }
M.MR, M.MG, M.MB = MR, MG, MB

local function muted(p) return ((p >> 29) & 1) == 1 end

function M.setShadow(i, packed)
    if i >= 1 and i <= 16 then M.SH[i] = packed end
end

-- Alias for clarity at call sites: "this single step changed".
M.setStep = M.setShadow

function M.setMeta(focus, lastStep, playhead, selS, vplo, shift)
    M.focus    = focus
    M.lastStep = lastStep
    M.playhead = playhead
    M.selS     = selS
    M.vplo     = vplo
    M.shift    = shift
end

-- Lightweight playhead-only update (called per pulse from VSN1).
function M.setPlayhead(ph) M.playhead = ph end

function M.invalidateAll()
    for i = 1, 16 do M.LAST[i] = -1 end
end

-- Compute color for each encoder; emit only when changed.
-- emit(idx, r, g, b)  -- 1-based idx, 0..255 channels
function M.refreshColors(emit)
    local f, ls, ph, vplo = M.focus, M.lastStep, M.playhead, M.vplo
    local mr, mg, mb = MR[f], MG[f], MB[f]
    local SH, LAST = M.SH, M.LAST

    local phEnc = 0
    if ph >= vplo and ph < vplo + 16 then phEnc = ph - vplo + 1 end

    for i = 1, 16 do
        local s = vplo + i - 1
        local r, g, b
        if s > ls then
            r, g, b = 0, 0, 0
        elseif i == phEnc then
            r, g, b = 255, 255, 255
        elseif muted(SH[i]) then
            r, g, b = 180, 0, 0
        else
            r, g, b = mr, mg, mb
        end
        local packed = (r << 16) | (g << 8) | b
        if LAST[i] ~= packed then
            LAST[i] = packed
            emit(i, r, g, b)
        end
    end
end

return M
