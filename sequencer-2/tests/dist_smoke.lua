-- tests/dist_smoke.lua — lean dist-bundle smoke: load the 5 BUILT bundles in
-- the device's order (seq2, seq2b at setup; ctl/ui/gen lazy), bind, and scrub
-- every mode with a mock screen. Run from repo root after the build:
--   /opt/homebrew/opt/lua@5.4/bin/lua5.4 tests/dist_smoke.lua
-- Asserts the device-code rules too: no collectgarbage / package.loaded /
-- string.format inside the shipped bundle text.

local NAMES = { "seq2", "seq2b", "seq2_ctl", "seq2_ui", "seq2_gen" }
for _, n in ipairs(NAMES) do
    package.preload[n] = assert(loadfile("dist/" .. n .. ".lua"),
        "missing/failed dist/" .. n .. ".lua (build first)")
end

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1
    else fail = fail + 1; io.write("  FAIL: ", msg, "\n") end
end

-- ---- device-code rules: scan bundle text --------------------------------
for _, n in ipairs(NAMES) do
    local fh = assert(io.open("dist/" .. n .. ".lua", "r"))
    local src = fh:read("*a"); fh:close()
    ok(not src:find("collectgarbage", 1, true), n .. ": no collectgarbage")
    ok(not src:find("package.loaded", 1, true), n .. ": no package.loaded")
    ok(not src:find("string.format", 1, true), n .. ": no string.format")
    ok(#src <= 11000, n .. ": bundle <= ~10 KB watchdog budget (" .. #src .. " B)")
end

-- ---- boot exactly like the profile's setup event --------------------------
local SEQ  = require("seq2")
local SEQB = require("seq2b")
local ENGINE, MIDIRX = SEQB.engine, SEQB.midirx
ok(type(ENGINE.init) == "function" and type(MIDIRX.handle) == "function",
    "seq2/seq2b expose engine + midirx")
ENGINE.init{ trackCount = 2 }
ok(#ENGINE.tracks == 2, "device boots with 2 tracks")

ok(package.loaded["seq2_ctl"] == nil and package.loaded["seq2_ui"] == nil
   and package.loaded["seq2_gen"] == nil,
   "UI bundles stay lazy after boot (not yet required)")

-- ---- lazy UI load on first draw (the draw event's loadUI) ------------------
local CTL = require("seq2_ctl").control
local U   = require("seq2_ui")
local DRAW, LEDS = U.draw, U.leds
CTL.bind(ENGINE, SEQ)
ok(package.loaded["seq2_gen"] ~= nil, "seq2_gen pulled in by control's require")

local calls = 0
local Mock = {}
local function bump() calls = calls + 1 end
Mock.draw_rectangle_filled = bump
Mock.draw_line = bump
Mock.draw_text_fast = bump
Mock.draw_swap = bump

local function frames(n)
    local c0 = calls
    for _ = 1, n do DRAW(Mock, ENGINE, CTL) end
    return calls - c0
end

CTL.mode, CTL.setup = "PLAY", false
local d = frames(3)
ok(d > 10, "PLAY draws (" .. d .. " calls)")

CTL.setup = true
d = frames(3)
ok(d > 30, "SETUP param grid draws (" .. d .. " calls)")
CTL.setup = false

CTL.mode = "STEP"
d = frames(3)
ok(d > 10, "STEP draws (" .. d .. " calls)")

CTL.mode = "SEQ"
d = frames(3)
ok(d > 10, "SEQ slot picker draws (" .. d .. " calls)")

-- playback still runs end-to-end through the bundled engine
ENGINE.onStart()
local ons = 0
for _ = 0, 23 do
    local o = ENGINE.onPulse()
    for i = 1, o.n do if o.typ[i] == 1 then ons = ons + 1 end end
end
ok(ons > 0, "bundled engine emits note-ons under the mock clock (" .. ons .. ")")

LEDS(ENGINE, CTL)  -- headless-safe (no led_color global)
ok(true, "LED pass runs without led_color")

collectgarbage("collect")
io.write(string.format("total resident after smoke: %.1f KB\n", collectgarbage("count")))
io.write(string.format("\nDIST SMOKE: %d passed, %d failed\n", pass, fail))
os.exit(fail == 0 and 0 or 1)
