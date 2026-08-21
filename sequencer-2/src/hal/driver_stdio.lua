-- driver_stdio.lua — terminal event sink. Reads the engine's preallocated out
-- buffer and writes the line protocol bridge.py consumes:
--
--   ON  <pitch> <vel> <ch>
--   OFF <pitch> <ch>
--
-- String formatting here allocates, but this is IO on the App side, outside the
-- engine hot path guarded by test_no_alloc. One flush per pulse.

local M = {}

function M.emit(out)
    if out.n == 0 then return end
    local typ, pitch, vel, ch = out.typ, out.pitch, out.vel, out.ch
    for i = 1, out.n do
        if typ[i] == 1 then
            io.write("ON ", pitch[i], " ", vel[i], " ", ch[i], "\n")
        else
            io.write("OFF ", pitch[i], " ", ch[i], "\n")
        end
    end
    io.flush()
end

return M
