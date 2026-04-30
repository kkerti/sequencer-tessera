-- tests/run.lua
-- Minimal test runner. Discovers tests/*.lua (except this file), runs each.

package.path = "src/?.lua;tests/?.lua;" .. package.path

local tests = {
    "test_step",
    "test_track_advance",
    "test_track_dir",
    "test_track_ratchet",
    "test_track_probability",
    "test_track_group_edit",
    "test_engine",
    "test_track_region",
    "test_engine_region_switch",
    "test_no_alloc",
    "test_dist_smoke",
}

local total, passed = 0, 0
local fails = {}

for _, name in ipairs(tests) do
    local mod = require(name)
    for tname, fn in pairs(mod) do
        if type(fn) == "function" and tname:match("^test_") then
            total = total + 1
            local ok, err = pcall(fn)
            if ok then
                passed = passed + 1
                io.write(string.format("  PASS  %s.%s\n", name, tname))
            else
                fails[#fails+1] = string.format("  FAIL  %s.%s\n         %s", name, tname, tostring(err))
                io.write(string.format("  FAIL  %s.%s\n", name, tname))
            end
        end
    end
end

io.write(string.format("\n%d/%d passed\n", passed, total))
for _, f in ipairs(fails) do io.write(f .. "\n") end
os.exit(passed == total and 0 or 1)
