-- tests/boot_sim.lua — run the GUI profile's REAL event scripts, in the
-- device's order, against the real bundles.
-- Run from the sequencer-3 directory:  lua tests/boot_sim.lua
--
-- The scripts are read from dist/seq3 core.json (not copied here), so this
-- tests exactly what is uploaded. The contract:
--
--   * setup (el 255 ev0) compiles and runs without loading ANY bundle
--   * the draw (el 13 ev8) and timer (el 255 ev6) events, which fire during
--     cold boot, load nothing until a MIDI byte or a key press starts a load
--   * the staged loader compiles at most ONE bundle per call:
--     seq3, then seq3e, then seq3ui; the timer finishes a started load
--   * app start never compiles the screen (seq3s) or a lazy bundle
--   * the first control press after start compiles seq3s, and only that

package.path = ""

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1
    else fail = fail + 1; print("FAIL: " .. msg) end
end

-- ---- read the event scripts out of the profile JSON -------------------------
local function jsonString(src, i)            -- src:sub(i,i) == '"'
    local out, j = {}, i + 1
    while true do
        local c = src:sub(j, j)
        if c == '"' then return table.concat(out), j + 1 end
        if c == "\\" then
            local e = src:sub(j + 1, j + 1)
            if e == "n" then out[#out + 1] = "\n"
            elseif e == "t" then out[#out + 1] = "\t"
            elseif e == "u" then
                out[#out + 1] = utf8.char(tonumber(src:sub(j + 2, j + 5), 16)); j = j + 4
            else out[#out + 1] = e end
            j = j + 2
        else
            out[#out + 1] = c; j = j + 1
        end
    end
end

local json = io.open("dist/seq3 core.json"):read("a")
local EV = {}                                -- EV[element][event] = script
local pos = 1
while true do
    local s, e, el = json:find('"controlElementNumber":%s*(%d+)', pos)
    if not s then break end
    local nextEl = json:find('"controlElementNumber"', e) or #json
    EV[tonumber(el)] = {}
    local p = e
    while true do
        local s2, e2, ev = json:find('"event":%s*(%d+),%s*"config":%s*', p)
        if not s2 or s2 > nextEl then break end
        local str, after = jsonString(json, e2 + 1)
        EV[tonumber(el)][tonumber(ev)] = str
        p = after
    end
    pos = nextEl
end

-- Each event script runs as the device runs it: a chunk with `self`.
local function run(el, ev, self)
    local src = EV[el] and EV[el][ev]
    if not src or src == "" then return end
    local f = assert(load("local self = ...\n" .. src, "el" .. el .. "ev" .. ev, "t"))
    f(self)
end

-- ---- the device's require: one FS module per bundle, compiled on demand ----
local loaded, order = {}, {}
local oldreq = require
local FILES = { seq3 = "dist/seq3.lua", seq3e = "dist/seq3e.lua",
                seq3ui = "dist/seq3ui.lua", seq3s = "dist/seq3s.lua",
                seq3h = "dist/seq3h.lua", seq3x = "dist/seq3x.lua",
                seq3p = "dist/seq3p.lua", seq3l = "dist/seq3l.lua" }
require = function(n)
    if loaded[n] then return loaded[n] end
    if FILES[n] then
        order[#order + 1] = n
        loaded[n] = dofile(FILES[n])
        return loaded[n]
    end
    return oldreq(n)
end
local function nLoaded()
    local k = 0
    for _ in pairs(loaded) do k = k + 1 end
    return k
end

local printed = {}
local oldprint = print
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end

local sent = {}
function midi_send(ch, st, p1, p2) sent[#sent + 1] = { ch = ch, st = st } end

local LcdMock = dofile("tests/lcd_mock.lua")
local lcd = LcdMock.new()
local el255, el13 = {}, lcd                  -- `self` per element

-- ---- cold boot: setup, then draw and timer ticks ---------------------------
run(255, 0, el255)
ok(nLoaded() == 0, "SETUP loads no bundle (loaded " .. nLoaded() .. ")")
ok(RX == nil and LS == nil, "SETUP leaves RX and the load stage unset")
ok(type(L) == "function", "SETUP defines the loader")
ok(type(el255.rtmrx_cb) == "function", "SETUP assigns rtmrx_cb")

for _ = 1, 5 do run(13, 8, el13); run(255, 6, el255) end
ok(nLoaded() == 0, "draw + timer during cold boot load nothing")
ok(lcd.calls == 0, "draw is a no-op before a trigger (screen stays dark)")

-- ---- the first MIDI byte STARTS a staged load ------------------------------
el255.rtmrx_cb(el255, 0xFA)                  -- MIDI start
ok(nLoaded() == 1 and loaded.seq3, "first MIDI byte compiles ONLY seq3 (" .. table.concat(order, ",") .. ")")
run(255, 6, el255)                           -- timer continues the load
ok(nLoaded() == 2 and loaded.seq3e, "next stage compiles ONLY seq3e")
el255.rtmrx_cb(el255, 0xF8)                  -- a clock byte finishes it
ok(nLoaded() == 3 and loaded.seq3ui and RX ~= nil, "third stage compiles seq3ui and wires RX")
ok(loaded.seq3s == nil, "app start does NOT compile the screen (seq3s)")
ok(loaded.seq3x == nil and loaded.seq3p == nil and loaded.seq3l == nil,
   "app start compiles no lazy bundle")

local timerBefore = nLoaded()
run(255, 6, el255)
ok(nLoaded() == timerBefore, "the timer loads nothing once the chain is up")

-- ---- clock plays -------------------------------------------------------------
el255.rtmrx_cb(el255, 0xFA)
for _ = 1, 96 do el255.rtmrx_cb(el255, 0xF8) end
local ons = 0
for _, m in ipairs(sent) do if m.st == 0x90 then ons = ons + 1 end end
ok(ons >= 1, "clock through rtmrx_cb(self,t) produces note-ons (" .. ons .. ")")

-- ---- idle status view: paints once, then only on change ---------------------
local c0 = lcd.calls
run(13, 8, el13)
local c1 = lcd.calls
run(13, 8, el13); run(13, 8, el13)
ok(c1 > c0, "status view paints after start")
ok(lcd.calls == c1, "status view does not repaint an unchanged frame")

-- ---- the first control press compiles the screen, and only that -------------
local before = nLoaded()
run(1, 3, {})                                -- keyswitch 1
ok(loaded.seq3s ~= nil and nLoaded() == before + 1,
   "first key press compiles ONLY seq3s (" .. table.concat(order, ",") .. ")")
run(13, 8, el13)
ok(#lcd.errors == 0, "every draw used real, in-bounds LCD calls"
   .. (#lcd.errors > 0 and (" -- first: " .. lcd.errors[1]) or ""))

el255.rtmrx_cb(el255, 0xFC)                  -- stop
local offs = 0
for _, m in ipairs(sent) do if m.st == 0x80 then offs = offs + 1 end end
ok(offs >= 1, "stop emits note-offs (" .. offs .. ")")

-- ---- a key press alone can also start (and the timer finishes) the load -----
do
    for k in pairs(loaded) do loaded[k] = nil end
    order = {}
    RX, LS, UI = nil, nil, nil
    run(255, 0, el255)
    run(0, 3, {})                            -- keyswitch 0: stage 1
    run(255, 6, el255); run(255, 6, el255)   -- timer: stages 2, 3
    ok(RX ~= nil and loaded.seq3s == nil, "key press + timer bring the chain up without the screen")
end

print = oldprint
print("boot order: " .. table.concat(order, " -> "))
print("boot_sim: " .. pass .. " checks, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
