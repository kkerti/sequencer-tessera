-- tools/build.lua — build the deployable Grid module bundles + the grid-wasm
-- preview screen. Run:  /opt/homebrew/opt/lua@5.4/bin/lua5.4 tools/build.lua
--
-- MUST run under Lua 5.4 (bytecode version matches the Grid module if
-- --bytecode is used). Keg-only path on this machine:
--   /opt/homebrew/opt/lua@5.4/bin/lua5.4 tools/build.lua
--
-- LEAN LAYOUT (seq-1's proven load discipline; see docs/DEPLOY.md):
-- PLAIN TEXT source bundles, each <= ~10 KB — bigger single loads trip the
-- module watchdog — loaded sequentially, UI bundles lazy on first input/draw:
--   dist/seq2.lua      Core data model: event, scales, fx, rack, pattern,
--                      track. Required at setup. (~10 KB, the proven max.)
--   dist/seq2b.lua     Core runtime: sequence, engine, midi_rx. Required at
--                      setup right after seq2. (~4 KB)
--   dist/seq2_ctl.lua  control (staged params, modes). Lazy: first input/draw.
--   dist/seq2_ui.lua   text-only draw (draw_text) + LED pass. Lazy.
--   dist/seq2_gen.lua  generator; pulled by seq2_ctl's require("generate").
-- Device-code rules (violating these rebooted the module before):
--   NO collectgarbage, NO package.loaded manipulation, NO string.format,
--   total shipped Lua ~25-28 KB (heap ceiling ~130 KB, ~91 KB boot baseline).
--
-- --bytecode emits all bundles as string.dump(f, true) instead of text
-- (smaller resident chunks, but the Grid editor may reject binary uploads —
-- text is the proven path).
--
-- Also emits screens/seq2_live.lua — a THIN data-only grid-wasm preview whose
-- notes are baked by running the generator here at build time (the engine must
-- NOT be embedded in a screen script; see docs/ARCHITECTURE.md §10).

assert(_VERSION == "Lua 5.4",
    "build.lua must run under Lua 5.4 (bytecode version matches the Grid module). " ..
    "Use: /opt/homebrew/opt/lua@5.4/bin/lua5.4 tools/build.lua")

-- ---- bundle definitions -----------------------------------------------
local CORE_A = {                    -- dist/seq2.lua — self-contained data model
    { key = "event",   path = "src/core/event.lua"   },
    { key = "scales",  path = "src/core/scales.lua"  },
    { key = "range",   path = "src/fx/range.lua"     },
    { key = "random",  path = "src/fx/random.lua"    },
    { key = "scale",   path = "src/fx/scale.lua"     },
    { key = "rack",    path = "src/core/rack.lua"    },
    { key = "pattern", path = "src/core/pattern.lua" },
    { key = "track",   path = "src/core/track.lua"   },
}
local CORE_B = {                    -- dist/seq2b.lua — runtime (needs seq2)
    { key = "sequence", path = "src/core/sequence.lua" },
    { key = "engine",   path = "src/core/engine.lua"   },
    { key = "midirx",   path = "src/core/midi_rx.lua"  },
}
local CTL = { { key = "control", path = "src/app/control.lua" } }
local UI  = {                      -- dist/seq2_ui.lua — lazy screen + LEDs
    { key = "draw", path = "src/hal/draw_text.lua" },
    { key = "leds", path = "src/hal/leds.lua"     },
}
local GEN = { { key = "generate", path = "src/core/generate.lua" } }

local NS_A = [[
return {
    track=R.track, pattern=R.pattern, rack=R.rack,
    event=R.event, scales=R.scales,
    range=R.range, random=R.random, scalefx=R.scale,
}
]]
local NS_B = "return { engine=R.engine, midirx=R.midirx, sequence=R.sequence }\n"
local NS_CTL = "return { control=R.control }\n"
local NS_UI = "return { draw=R.draw.draw, leds=R.leds.update }\n"
local NS_GEN = "return { generate=R.generate }\n"

local SHIM_CORE = "local R={}\nlocal function require(n) return R[n] end\n"
-- Fallback shims: local R first, then a chain of host bundles by alias.
-- (Shim bodies are plain require lookups — no package.loaded, no GC.)
local function shimChain(names)
    local body = { "local R={}", "local _host=require" }
    for i in ipairs(names) do body[#body + 1] = "local _" .. i end
    body[#body + 1] = "local function require(n)"
    body[#body + 1] = " local r=R[n] if r~=nil then return r end"
    for i, n in ipairs(names) do
        body[#body + 1] = string.format(
            " if not _%d then _%d=_host(%q) end local m=_%d[n] if m then return m end",
            i, i, n, i)
    end
    body[#body + 1] = " error('seq2 module not found: '..tostring(n))"
    body[#body + 1] = "end\n"
    return table.concat(body, "\n")
end
local SHIM_B   = shimChain{ "seq2" }                    -- engine needs track/pattern
local SHIM_CTL = shimChain{ "seq2", "seq2b", "seq2_gen" } -- control needs generate + midirx
local SHIM_UI  = shimChain{ "seq2", "seq2b" }           -- draw_text needs pattern
local SHIM_GEN = shimChain{ "seq2" }                    -- generate needs event/scales

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

-- asText: write the (minified) SOURCE instead of stripped bytecode. TEXT is
-- the default and the proven path (the Grid editor rejects binary uploads;
-- the device compiles text at load). Resident chunk is ~4x bigger than the
-- stripped-bytecode form — that's the price of uploadability.
local function buildBundle(files, shim, ns, out, header, asText)
    local parts, raw = { header, shim }, 0
    for _, m in ipairs(files) do
        local s = read(m.path); raw = raw + #s
        parts[#parts+1] = string.format("R[%q]=(function()\n%s\nend)()\n",
            m.key, collapseWs(stripAsserts(stripComments(s))))
    end
    parts[#parts+1] = ns
    local src = table.concat(parts)

    -- Compile the source bundle, then re-dump WITHOUT debug info. The device
    -- heap is dominated by debug info: load() interned every local-variable
    -- name and kept per-instruction line tables (~70% of the compiled chunk).
    -- A stripped binary chunk loads without re-compiling (no identifier
    -- interning) and carries no debug info — a ~4x smaller resident chunk.
    local f = assert(load(src, "@" .. out))
    local bin
    if asText then
        bin = src
    else
        bin = string.dump(f, true)
    end
    local fo = assert(io.open(out, "wb")); fo:write(bin); fo:close()

    local ok, err = loadfile(out)
    if not ok then io.stderr:write("VERIFY FAIL " .. out .. ": " .. tostring(err) .. "\n"); os.exit(1) end
    io.write(string.format("%-26s source %d B  %s %d B  (%.0f%% of source)  loads OK\n",
        out, raw, asText and "text" or "stripped", #bin, 100 * #bin / raw))
    return bin
end

local TEXT = true
for _, a in ipairs(arg or {}) do if a == "--bytecode" then TEXT = false end end

os.execute("mkdir -p dist")
local total = 0
local function out(bin) total = total + #bin end
out(buildBundle(CORE_A, SHIM_CORE, NS_A, "dist/seq2.lua",
    "-- dist/seq2.lua (Core data model; auto-generated)\n", TEXT))
out(buildBundle(CORE_B, SHIM_B, NS_B, "dist/seq2b.lua",
    "-- dist/seq2b.lua (Core runtime: engine+midi_rx; auto-generated)\n", TEXT))
out(buildBundle(CTL, SHIM_CTL, NS_CTL, "dist/seq2_ctl.lua",
    "-- dist/seq2_ctl.lua (control; lazy on first input/draw; auto-generated)\n", TEXT))
out(buildBundle(UI, SHIM_UI, NS_UI, "dist/seq2_ui.lua",
    "-- dist/seq2_ui.lua (text draw + LEDs; lazy; auto-generated)\n", TEXT))
out(buildBundle(GEN, SHIM_GEN, NS_GEN, "dist/seq2_gen.lua",
    "-- dist/seq2_gen.lua (generator; pulled by seq2_ctl; auto-generated)\n", TEXT))
io.write(string.format("lean build: 5 bundles, %s, total %d B%s\n",
    TEXT and "TEXT" or "BYTECODE", total,
    TEXT and "" or " (bytecode: editor upload may reject binary)"))

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
