-- io/monitor.lua — a four-line live view of the lanes, one line per lane.
--
-- A host-side adapter, Mac only: it reads lane state and writes text. Nothing
-- here is on the pulse path's allocation budget, and it never touches stdout —
-- stdout is the MIDI line protocol tools/bridge.py consumes, so the monitor
-- writes to stderr.
--
--   L1 note ch01 d1 [...>............]  4/16  play D4  (62) v85 len4
--
-- Grid glyphs: '.' step idle   '#' gate/trig step armed   '>' playhead
--              '*' playhead on an armed step
-- Mod lanes draw a coarse level ramp (_.-=^) instead of gates.

local Lane = require("lane")

local M = {}

M.enabled = false
M.inPlace = true      -- redraw the same four lines (ANSI cursor-up)
M.every = 1           -- redraw at most every N pulses

local NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

local drawn = false
local pulses = 0
local lastPos, lastNote = {}, {}

-- True when any lane's playhead or sounding note moved since the last redraw.
local function changed(Engine)
    local dirty = false
    for i = 1, #Engine.lanes do
        local l = Engine.lanes[i]
        if lastPos[i] ~= l.position or lastNote[i] ~= l.activeNote then
            lastPos[i], lastNote[i] = l.position, l.activeNote
            dirty = true
        end
    end
    return dirty
end

local function noteName(n)
    if not n then return nil end
    return string.format("%s%d", NAMES[(n % 12) + 1], (n // 12) - 1)
end

-- One lane's step grid, padded to 16 columns so the lines stay aligned.
local function grid(l)
    local used = Lane.limit(l)
    local cells = {}
    for i = 1, used do
        local c
        if l.type == "trig" then
            c = (l.gate[i] == 1) and "#" or "."
        else
            c = "."
        end
        if i == l.position then
            c = (c == "#") and "*" or ">"
        end
        cells[i] = c
    end
    for i = used + 1, Lane.CAP do cells[i] = " " end
    return table.concat(cells)
end

-- What this lane is sounding right now.
local function playing(l)
    if not l.activeNote then return "--" end
    if l.type == "note" then
        return string.format("%-4s(%3d) v%-3d len%d",
            noteName(l.activeNote), l.activeNote,
            l.velocity[l.position], l.stepLength[l.position])
    end
    return string.format("%-4s(%3d)", noteName(l.activeNote), l.activeNote)
end

function M.line(i, l)
    return string.format("L%d %-4s ch%02d d%-2d [%s] %2d/%-2d  %s",
        i, l.type, l.channel, l.division, grid(l),
        l.position, Lane.limit(l), playing(l))
end

function M.header()
    io.stderr:write(
        "[seq3] lanes: '.' idle  '#' armed  '>' playhead  '*' playhead+armed"
        .. "  (mod: _.-=^ level)\n")
    io.stderr:flush()
end

-- Call once per pulse with the engine; cheap and throttled.
function M.render(Engine, force)
    if not M.enabled then return end
    pulses = pulses + 1
    if not force then
        if M.every > 1 and (pulses % M.every) ~= 0 then return end
        -- Redraw only when something actually moved: at 24 PPQN a per-pulse
        -- redraw is mostly identical frames.
        if not changed(Engine) then return end
    end
    local out = {}
    if M.inPlace and drawn then out[#out + 1] = string.format("\27[%dA", #Engine.lanes) end
    for i = 1, #Engine.lanes do
        out[#out + 1] = M.line(i, Engine.lanes[i])
        if M.inPlace then out[#out + 1] = "\27[K" end
        out[#out + 1] = "\n"
    end
    io.stderr:write(table.concat(out))
    io.stderr:flush()
    drawn = true
end

-- After a load/stop the cursor bookkeeping restarts on the next render.
function M.reset()
    drawn = false
    lastPos, lastNote = {}, {}
end

return M
