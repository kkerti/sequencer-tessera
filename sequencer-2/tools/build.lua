-- tools/build.lua — build the deployable Grid module bundles + the grid-wasm
-- preview screen. Run:  lua tools/build.lua
--
-- Two bundles (seq-1's proven split — one big bundle reboots the module's
-- watchdog on load, two thin ones don't):
--   dist/seq2.lua     Core + midi_rx. Required at the module's setup event.
--                     Pure playback (clock in -> notes out) runs on this alone.
--   dist/seq2_ui.lua  Screen draw. Lazy-loaded on the first draw event.
--
-- Load on device / in tests:  local SEQ = (loadfile"dist/seq2.lua")()
-- The UI bundle's require-shim falls back to the host require("seq2") so its
-- require("pattern") resolves through the Core bundle's flat aliases.
--
-- Also emits screens/seq2_live.lua — a THIN data-only grid-wasm preview whose
-- notes are baked by running the generator here at build time (the engine must
-- NOT be embedded in a screen script; see docs/ARCHITECTURE.md §10).

-- ---- bundle definitions -----------------------------------------------
local CORE = {
    { key = "event",   path = "src/core/event.lua"   },
    { key = "scales",  path = "src/core/scales.lua"  },
    { key = "range",   path = "src/fx/range.lua"     },
    { key = "random",  path = "src/fx/random.lua"    },
    { key = "scale",   path = "src/fx/scale.lua"     },
    { key = "rack",    path = "src/core/rack.lua"    },
    { key = "pattern", path = "src/core/pattern.lua" },
    { key = "track",   path = "src/core/track.lua"   },
    { key = "engine",  path = "src/core/engine.lua"  },
    { key = "generate",path = "src/core/generate.lua"},
    { key = "midirx",  path = "src/core/midi_rx.lua" },
}
local UI = {
    { key = "control", path = "src/app/control.lua"  },
    { key = "draw",    path = "src/hal/draw_vsn1.lua" },
}

local CORE_NS = [[
return {
    engine=R.engine, track=R.track, pattern=R.pattern, rack=R.rack,
    event=R.event, scales=R.scales, generate=R.generate, midirx=R.midirx,
    range=R.range, random=R.random, scalefx=R.scale,
}
]]
local UI_NS = "return { draw=R.draw.draw, control=R.control }\n"

local SHIM_CORE = "local R={}\nlocal function require(n) return R[n] end\n"
-- UI shim: local module first, else delegate to the loaded Core bundle.
local SHIM_UI = [[
local R={}
local _host=require
local _seq
local function require(n)
    local r=R[n] if r~=nil then return r end
    if not _seq then _seq=_host("seq2") end
    return _seq[n]
end
]]

-- ---- minify (string/bracket-aware; from seq-1) ------------------------
local function stripComments(src)
    local out, i, n = {}, 1, #src
    while i <= n do
        local c = src:sub(i, i)
        if c == '"' or c == "'" then
            local q = c; out[#out+1] = c; i = i + 1
            while i <= n do
                local d = src:sub(i, i); out[#out+1] = d; i = i + 1
                if d == "\\" and i <= n then out[#out+1] = src:sub(i, i); i = i + 1
                elseif d == q then break end
            end
        elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
            local after = i + 2
            if src:sub(after, after) == "[" then
                local eqs = src:match("^=*", after + 1)
                local s = after + 1 + #eqs
                if src:sub(s, s) == "[" then
                    local e = src:find("]" .. eqs .. "]", s + 1, true)
                    i = e and (e + #eqs + 2) or (n + 1)
                else local nl = src:find("\n", i, true); i = nl or (n + 1) end
            else local nl = src:find("\n", i, true); i = nl or (n + 1) end
        else out[#out+1] = c; i = i + 1 end
    end
    return table.concat(out)
end
local function stripAsserts(src)
    src = src:gsub("\n[ \t]*assert%b()[ \t]*\n", "\n")
    for _ = 1, 3 do src = src:gsub("assert(%b())", "%1") end
    return src
end
local function collapseWs(src)
    src = src:gsub("\r\n", "\n"):gsub("\r", "\n")
    src = src:gsub("[ \t]+\n", "\n"):gsub("\n\n+", "\n"):gsub("[ \t]+", " ")
    return src
end
local function read(p) local f = assert(io.open(p, "r")); local s = f:read("*a"); f:close(); return s end

local function buildBundle(files, shim, ns, out, header)
    local parts, raw = { header, shim }, 0
    for _, m in ipairs(files) do
        local s = read(m.path); raw = raw + #s
        parts[#parts+1] = string.format("R[%q]=(function()\n%s\nend)()\n",
            m.key, collapseWs(stripAsserts(stripComments(s))))
    end
    parts[#parts+1] = ns
    local b = table.concat(parts)
    local f = assert(io.open(out, "w")); f:write(b); f:close()
    local ok, err = loadfile(out)
    if not ok then io.stderr:write("VERIFY FAIL " .. out .. ": " .. tostring(err) .. "\n"); os.exit(1) end
    io.write(string.format("%-16s source %d B  bundle %d B  (%.0f%%)  parses OK\n", out, raw, #b, 100 * #b / raw))
    return b
end

os.execute("mkdir -p dist")
buildBundle(CORE, SHIM_CORE, CORE_NS, "dist/seq2.lua",    "-- dist/seq2.lua (Core + midi_rx; auto-generated)\n")
buildBundle(UI,   SHIM_UI,   UI_NS,   "dist/seq2_ui.lua", "-- dist/seq2_ui.lua (screen; auto-generated)\n")

-- ---- emit a THIN, data-only grid-wasm preview screen ------------------
-- Runs the generator HERE at build time, bakes variants' notes as arrays, and
-- ships a screen that only draws them. No engine embedded (that OOMs the VM
-- heap; see §10). Encoder scrubs; KEY 0..3 (held) pick a variant.
package.path = "src/core/?.lua;src/fx/?.lua;" .. package.path
local Pattern  = require("pattern")
local Generate = require("generate")
local function arr(t, n) local s = {} for i = 1, n do s[i] = t[i] end return "{" .. table.concat(s, ",") .. "}" end

local NVAR, baked = 4, {}
for v = 0, NVAR - 1 do
    local p = Pattern.new{ length = 16, zoom = 6 }
    Generate.run(p, { scaleIndex = 3, root = 9, hits = 6, seed = v + 1,
                      pitchRoot = 60, pitchSpread = 6, velRoot = 100, velSpread = 20 })
    local e = p.events
    baked[#baked + 1] = string.format("VP[%d]=%s VS[%d]=%s VL[%d]=%s VN[%d]=%d\n",
        v, arr(e.pitch, e.n), v, arr(e.start, e.n), v, arr(e.len, e.n), v, e.n)
end
local INIT = "BG={12,12,16} DIM={60,60,60} GREY={130,130,130} WHITE={235,235,235}\n"
    .. "ORANGE={249,150,0} DIMOR={150,95,20} CYAN={0,200,220}\n"
    .. "PLO=45 PHI=80 LOOP=96\nVP={} VS={} VL={} VN={}\n" .. table.concat(baked)
local LOOP = [[
local sel=0
if uiControlDown then for k=0,3 do if uiControlDown[k]==1 then sel=k end end end
local P,S,L,N=VP[sel],VS[sel],VL[sel],VN[sel]
local ph=math.floor((sliderValue or 0)/255*LOOP)
local rowH=116/(PHI-PLO)
ggdrf(0,0,0,320,240,BG)
local on=0
for i=1,N do
  local s,l,p=S[i],L[i],P[i]
  local x1=2+s/LOOP*316 local x2=2+(s+l)/LOOP*316 if x2-x1<2 then x2=x1+2 end
  local y=118-(p-PLO)*rowH
  local act=(ph>=s and ph<s+l)
  if act then on=on+1 end
  ggdrf(0,x1,y-rowH/2,x2,y+rowH/2,act and ORANGE or DIMOR)
end
local px=2+ph/LOOP*316
ggdl(0,px,0,px,119,CYAN)
ggdl(0,0,120,320,120,DIM)
ggdft(0,'SEQ2 GEN (euclid, A minor)',8,128,8,ORANGE)
ggdft(0,'ENCODER=SCRUB  KEY0-3=VARIANT',8,148,8,GREY)
ggdft(0,'VARIANT',8,168,8,GREY) ggdft(0,tostring(sel),130,168,8,ORANGE)
ggdft(0,'NOTES',170,168,8,GREY) ggdft(0,tostring(N),250,168,8,ORANGE)
ggdft(0,'TICK',8,188,8,GREY) ggdft(0,ph..' / '..LOOP,130,188,8,ORANGE)
ggdft(0,'ON',170,188,8,GREY) ggdft(0,tostring(on),250,188,8,WHITE)
ggdsw()
]]
local live = table.concat({
    "-- seq2_live.lua (AUTO-GENERATED by tools/build.lua — do not edit)\n",
    "-- THIN preview: generator ran at BUILD time; these are baked note arrays.\n",
    "-- No engine embedded. Encoder scrubs; KEY0-3 pick a variant.\n\n",
    "-- INIT START\n", INIT, "-- INIT END\n\n",
    "-- LOOP START\n", LOOP, "-- LOOP END\n",
})
local lf = assert(io.open("screens/seq2_live.lua", "w")); lf:write(live); lf:close()
io.write(string.format("screens/seq2_live.lua  %d B, init %d B  (thin preview, %d baked variants)\n", #live, #INIT, NVAR))
