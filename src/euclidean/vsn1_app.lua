-- src/euclidean/vsn1_app.lua
-- VSN1 input dispatch for the Euclidean engine. Mirrors src/vsn1_app.lua
-- in shape: thin handlers that mutate the controls module then mark dirty.
--
-- We do not push to EN16 here. EN16 wiring is a separate module and not
-- required by the brief. If/when added, hook it in pushEN16().

local Engine = require("euclidean.engine")

local M = {}

M.CTL = nil

function M.init(controls)
    M.CTL = controls
    controls.dirtyAll()
    return M
end

-- Keyswitches 1..8.
--   1 ROTATE  2 EVENTS  3 STEPS  4 KEY  5 RATE   <- focus modes (active)
--   6..7      reserved (MODE_MUTE still reachable via encoder click)
--   8 SHIFT
-- RATE drives `tr.ppstep` (external pulses per pattern step) which is the
-- engine's polyrhythm primitive. Without this binding the field could only
-- be set from boot-patch code; with it, every visible PARAM is editable.
function M.onKey(idx, pressed)
    local CTL = M.CTL
    if idx == 8 then
        CTL.setShift(pressed)
    elseif pressed and idx >= 1 and idx <= 5 then
        CTL.onKey(idx)
    end
end

function M.onTurn(dir)         M.CTL.onEndless(dir)      end
function M.onClick()           M.CTL.onEndlessClick()    end
function M.onSmallBtn(sidx)    M.CTL.onSmallBtn(sidx)    end

-- Screen-draw scriptlet entry. The VSN1 runtime hands us `self` (the
-- screen) only inside the draw event; we forward it to the controls
-- module's draw(), which honours the dirty flag and only repaints when
-- something changed. Called from VSN1.lua section [3].
function M.draw(scr)           M.CTL.draw(scr)           end

return M
