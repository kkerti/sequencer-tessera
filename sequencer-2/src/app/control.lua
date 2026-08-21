-- control.lua — input handling + the pattern parameter model (UI bundle).
--
-- Lives in the uploaded bundle, so all logic is here and the module event
-- scripts stay one-liners (loadUI() CTL.button(9) etc.). Bound at first input
-- to the engine + Core namespace; owns each track's generator opts and
-- regenerates the pattern live when a generative param changes.
--
--   CTL.bind(engine, seq)   -- once, on first input/draw
--   CTL.button(9..12)       -- small buttons
--   CTL.turn(d)             -- encoder turn  (edit selected param)
--   CTL.click(down)         -- encoder press (reroll)
--   CTL.key(k, down)        -- keyswitches: 0 = SHIFT, 1 = toggle SETUP
-- Screen reads: CTL.mode, CTL.track, CTL.sel, CTL.shift, CTL.params

local M = { mode = "PLAY", track = 1, sel = 3 }

local E, S           -- engine, Core namespace (SEQ)
local NOTE = { "C","C#","D","D#","E","F","F#","G","G#","A","A#","B" }
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end
local function noteName(m) return NOTE[m % 12 + 1] .. (m // 12 - 1) end

local function gen(t) return E.tracks[t].gen end

local function defaults(t)
    if t == 1 then
        return { scaleIndex=3, root=9, hits=7, rotate=0, seed=1,
                 pitchRoot=60, pitchSpread=6, velRoot=100, velSpread=20, gateRoot=6, gateSpread=3 }
    end
    return { scaleIndex=8, root=9, hits=4, rotate=0, seed=2,
             pitchRoot=40, pitchSpread=4, velRoot=110, velSpread=15, gateRoot=18, gateSpread=6 }
end

-- (re)author the pattern from its generator opts; keep the SCALE fx in sync.
local function regen(t)
    local tr = E.tracks[t]
    local g = tr.gen
    local sc = tr.rack.fx[3]
    sc:setScale(g.scaleIndex); sc:setRoot(g.root)
    S.generate.run(tr.pattern, g)
end
M.regen = regen

function M.bind(engine, seq)
    if E then return end
    E, S = engine, seq
    for t = 1, #E.tracks do E.tracks[t].gen = defaults(t); regen(t) end
end

-- ---- parameter model --------------------------------------------------
-- Each: { label, show() -> string, edit(d), regen (default true) }
-- All operate on the currently focused track (M.track).
local P = {}
local function add(label, show, edit, noregen) P[#P+1] = { label=label, show=show, edit=edit, regen=not noregen } end

add("SCALE",  function() return S.scales.SCALES[gen(M.track).scaleIndex].name end,
              function(d) local g=gen(M.track); g.scaleIndex=clamp(g.scaleIndex+d,1,#S.scales.SCALES) end)
add("KEY",    function() return noteName(gen(M.track).root):gsub("%-?%d","") end,
              function(d) local g=gen(M.track); g.root=(g.root+d)%12 end)
add("HITS",   function() local g=gen(M.track); return g.hits.." / "..E.tracks[M.track].pattern.length end,
              function(d) local g=gen(M.track); g.hits=clamp(g.hits+d,1,E.tracks[M.track].pattern.length) end)
add("ROTATE", function() return tostring(gen(M.track).rotate) end,
              function(d) local g=gen(M.track); g.rotate=(g.rotate+d)%E.tracks[M.track].pattern.length end)
add("PITCH",  function() return noteName(gen(M.track).pitchRoot) end,
              function(d) local g=gen(M.track); g.pitchRoot=clamp(g.pitchRoot+d,24,96) end)
add("SPREAD", function() return gen(M.track).pitchSpread.." deg" end,
              function(d) local g=gen(M.track); g.pitchSpread=clamp(g.pitchSpread+d,0,12) end)
add("VEL",    function() return tostring(gen(M.track).velRoot) end,
              function(d) local g=gen(M.track); g.velRoot=clamp(g.velRoot+d,1,127) end)
add("GATE",   function() return gen(M.track).gateRoot.."t" end,
              function(d) local g=gen(M.track); g.gateRoot=clamp(g.gateRoot+d,1,48) end)
add("SEED",   function() return tostring(gen(M.track).seed) end,
              function(d) local g=gen(M.track); g.seed=math.max(1,g.seed+d) end)
add("LENGTH", function() return E.tracks[M.track].pattern.length.." st" end,
              function(d) local p=E.tracks[M.track].pattern; p.length=clamp(p.length+d,1,64); local g=gen(M.track); g.hits=clamp(g.hits,1,p.length) end)
add("ZOOM",   function() return "z"..E.tracks[M.track].pattern.zoom end,
              function(d) local z=S.pattern.ZOOM; local p=E.tracks[M.track].pattern; local i=1 for k,v in ipairs(z) do if v.tps==p.zoom then i=k end end p.zoom=z[clamp(i+d,1,#z)].tps end)
add("CHANCE", function() return E.tracks[M.track].rack.fx[2].chance.."%" end,
              function(d) local r=E.tracks[M.track].rack.fx[2]; r.chance=clamp(r.chance+d,0,100) end, true) -- playback fx, no regen
add("TRACK",  function() return M.track.." / "..#E.tracks end,
              function(d) M.track=clamp(M.track+d,1,#E.tracks) end, true)
M.params = P

-- All control on keyswitches 0-7 + encoder (small buttons 9-12 are dead on HW).
local STEP = { [7] = 4, [12] = 5, [8] = 2 }              -- VEL/CHANCE/GATE turn faster
local KSEL = { [0]=3, [1]=2, [2]=1, [3]=6, [4]=7, [5]=12 } -- PLAY: HITS KEY SCALE SPREAD VEL CHANCE

-- ---- handlers ---------------------------------------------------------
function M.reroll()
    local g = gen(M.track); g.seed = g.seed + 1; regen(M.track)
end
local function toggleTrack() M.track = M.track % #E.tracks + 1 end

function M.turn(d)
    local p = P[M.sel]; if not p then return end
    p.edit((d > 0 and 1 or -1) * (STEP[M.sel] or 1))
    if p.regen then regen(M.track) end
end

function M.click(down) if down then M.reroll() end end

-- keyswitches 0-7 (fires on press; `down` false = release, ignored)
function M.key(n, down)
    if not down then return end
    if n == 7 then M.mode = (M.mode == "PLAY") and "SETUP" or "PLAY"; return end
    if n == 6 then toggleTrack(); return end
    if M.mode == "SETUP" then
        if n == 0 then M.sel = (M.sel - 2) % #P + 1        -- prev
        elseif n == 1 then M.sel = M.sel % #P + 1          -- next
        elseif n == 5 then M.reroll() end
    elseif KSEL[n] then
        M.sel = KSEL[n]                                    -- PLAY: direct select
    end
end

return M
