-- io/stdio.lua — the Mac host adapter. Formats engine events as the line
-- protocol tools/bridge.py consumes, and installs itself as midi/out's sink.
--
--   ON  <pitch> <velocity> <channel>
--   OFF <pitch> <channel>
--   CC  <controller> <value> <channel>
--
-- Formatting allocates, but this is IO outside the guarded hot path.

local MidiOut = require("midi.out")

local M = {}

function M.send(kind, pitch, velocity, channel)
    if kind == 1 then
        io.write("ON ", pitch, " ", velocity, " ", channel, "\n")
    elseif kind == 2 then
        io.write("CC ", pitch, " ", velocity, " ", channel, "\n")
    else
        io.write("OFF ", pitch, " ", channel, "\n")
    end
end

function M.attach()
    MidiOut.setSink(M.send)
end

function M.emit(out)
    MidiOut.emit(out)
    io.flush()
end

return M
