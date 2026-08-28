-- control.lua — input handling + the staged parameter model (UI bundle).
--
-- Modes (ARCHITECTURE §6): PLAY (staged generator params), STEP (per-note
-- editing, live), SEQ (pattern-slot / sequence / song). SETUP is a full-screen
-- detail view WITHIN PLAY, not a separate mode (CONTEXT.md).
--
-- Staging rule: only generator params stage — edits mutate a per-track staged
-- copy; COMMIT applies it and regenerates once. Per-note edits (STEP), reroll,
-- auto-reroll, nap, and mute all apply immediately. COMMIT and NAP are
-- DEDICATED small buttons (never a shifted/chorded key).
--
-- Control surface:
--   keyswitches 0-7   context actions (mode-specific, below)
--   small buttons 9-12:  9 = BACK   10 = ENTER   11 = NAP   12 = COMMIT
--   encoder           turn = stage / cursor / slot   click = reroll / field / jump
--
-- Hierarchy (ENTER goes deeper, BACK returns):
--   PLAY  (compact)  --ENTER-->  SETUP (full param grid)
--   SEQ   (SLOT)     --ENTER-->  SONG
--
--   GLOBAL          KS7 = MODE  PLAY -> STEP -> SEQ -> PLAY
--   PLAY            KS0..KS4 = HITS, KEY, SCALE, SPREAD, VEL
--                   KS5 = AUTO-REROLL toggle   KS6 = TRACK next
--                   enc turn = STAGE   enc click = REROLL
--                   ENTER = SETUP   NAP = nap toggle   COMMIT = apply staged
--   SETUP (PLAY)    KS0/KS1 = prev/next param   KS5 = AUTO-REROLL   KS6 = TRACK
--                   enc turn = STAGE   enc click = REROLL   BACK = exit
--   STEP            KS0 = ADD note   KS1 = DELETE note(s)
--                   KS2/KS3 = octave down/up   KS4/KS5 = field value -/+
--                   KS6 = TRACK next   enc turn = step cursor   enc click = field
--   SEQ (SLOT)      KS0..KS3 = track 1..4   KS5 = MUTE toggle
--                   enc turn = slot +/-   enc click = next sequence
--                   ENTER = SONG page
--   SEQ (SONG)      KS0 = append seq   KS1 = remove step   KS2 = clear song
--                   enc turn = song cursor   enc click = jump   BACK = SLOT page
--
-- Screen reads: CTL.mode, track, sel, params, setup, step, field, seqPage,
--               seqTrack, songCur. CTL.frame() services auto-reroll.

local M = { mode = "PLAY", track = 1, sel = 1, setup = false,
            step = 0, field = 1, seqPage = "SLOT", seqTrack = 1, songCur = 1 }

local E, S           -- engine, Core namespace (SEQ)
local NOTE = { "C","C#","D","D#","E","F","F#","G","G#","A","A#","B" }
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end
local function noteName(m) return NOTE[m % 12 + 1] .. (m // 12 - 1) end

local BTN_BACK, BTN_ENTER, BTN_NAP, BTN_COMMIT = 9, 10, 11, 12

local function Tr(t) return E.tracks[t] end
local function Sg(t) return E.tracks[t].staged end

-- ---- generator defaults + staging --------------------------------------
local DEFAULTS = {
    { scaleIndex=3, root=9, hits=7, rotate=0, seed=1,
      pitchRoot=60, pitchSpread=6, velRoot=100, velSpread=20, gateRoot=6, gateSpread=3 },
    { scaleIndex=8, root=9, hits=4, rotate=0, seed=2,
      pitchRoot=40, pitchSpread=4, velRoot=110, velSpread=15, gateRoot=18, gateSpread=6 },
}
local function defaults(t)
    local d = DEFAULTS[((t - 1) % 2) + 1]
    local c = {}
    for k, v in pairs(d) do c[k] = v end
    c.seed = t                     -- distinct seed per track
    return c
end

local function initStaged(t)
    local tr = E.tracks[t]
    local s = {}
    for k, v in pairs(tr.gen) do s[k] = v end
    s.length = tr.pattern.length
    s.zoom   = tr.pattern.zoom
    tr.staged = s
    tr.dirty  = false
end

-- (re)author the pattern from its APPLIED generator opts; keep SCALE fx synced.
local function regen(t)
    local tr = E.tracks[t]
    local g = tr.gen
    local sc = tr.rack.fx[3]
    sc:setScale(g.scaleIndex); sc:setRoot(g.root)
    S.generate.run(tr.pattern, g)
end

-- Apply staged edits: copy staged -> gen + pattern length/zoom, regen once.
local function commit(t)
    local tr = E.tracks[t]
    local s = tr.staged
    local g = tr.gen
    tr.pattern.length = clamp(s.length, 1, 64)
    tr.pattern.zoom   = s.zoom
    for k, v in pairs(s) do
        if k ~= "length" and k ~= "zoom" then g[k] = v end
    end
    g.hits = clamp(g.hits, 1, tr.pattern.length)
    regen(t)
    tr.dirty = false
end
M.commit = commit

-- Reroll: seed++ and regenerate NOW (never staged). staged.seed follows so the
-- display stays honest when there are no other pending edits.
local function reroll(t)
    local g = E.tracks[t].gen
    g.seed = g.seed + 1
    E.tracks[t].staged.seed = g.seed
    regen(t)
end
M.reroll = function() reroll(M.track) end

function M.bind(engine, seq)
    if E then return end
    E, S = engine, seq
    for t = 1, #E.tracks do
        E.tracks[t].gen = defaults(t)
        initStaged(t)
        regen(t)
    end
end

-- Auto-reroll servicing: called once per draw frame (off the hot path). The
-- generator runs here, never inside onPulse.
function M.frame()
    if not E then return end
    for t = 1, #E.tracks do
        local tr = E.tracks[t]
        if tr.auto.due then
            tr.auto.due = false
            reroll(t)
        end
    end
end

-- ---- parameter model ----------------------------------------------------
-- Each: { label, show() -> string, edit(d) }. edit() of a generator param
-- mutates the staged copy + sets dirty; live params apply immediately.
local P = {}
local function add(label, show, edit) P[#P + 1] = { label = label, show = show, edit = edit } end
local function dirty(t) E.tracks[t].dirty = true end

local function sNum(key, lo, hi)
    return function(d)
        local s = Sg(M.track)
        s[key] = clamp(s[key] + d, lo, hi)
        dirty(M.track)
    end
end

add("SCALE",  function() return S.scales.SCALES[Sg(M.track).scaleIndex].name end,
              function(d) local s = Sg(M.track); s.scaleIndex = clamp(s.scaleIndex + d, 1, #S.scales.SCALES); dirty(M.track) end)
add("KEY",    function() return noteName(Sg(M.track).root):gsub("%-?%d", "") end,
              function(d) local s = Sg(M.track); s.root = (s.root + d) % 12; dirty(M.track) end)
add("HITS",   function() local s = Sg(M.track); return s.hits .. " / " .. s.length end,
              function(d) local s = Sg(M.track); s.hits = clamp(s.hits + d, 1, s.length); dirty(M.track) end)
add("ROTATE", function() return tostring(Sg(M.track).rotate) end,
              function(d) local s = Sg(M.track); s.rotate = (s.rotate + d) % s.length; dirty(M.track) end)
add("PITCH",  function() return noteName(Sg(M.track).pitchRoot) end,
              sNum("pitchRoot", 24, 96))
add("SPREAD", function() return Sg(M.track).pitchSpread .. " deg" end,
              sNum("pitchSpread", 0, 12))
add("VEL",    function() return tostring(Sg(M.track).velRoot) end,
              sNum("velRoot", 1, 127))
add("GATE",   function() return Sg(M.track).gateRoot .. "t" end,
              sNum("gateRoot", 1, 48))
add("SEED",   function() return tostring(Sg(M.track).seed) end,
              function(d) local s = Sg(M.track); s.seed = math.max(1, s.seed + d); dirty(M.track) end)
add("LENGTH", function() return Sg(M.track).length .. " st" end,
              function(d) local s = Sg(M.track); s.length = clamp(s.length + d, 1, 64); s.hits = clamp(s.hits, 1, s.length); dirty(M.track) end)
add("ZOOM",   function() return "z" .. Sg(M.track).zoom end,
              function(d) local z = S.pattern.ZOOM; local s = Sg(M.track); local i = 1
                  for k, v in ipairs(z) do if v.tps == s.zoom then i = k end end
                  s.zoom = z[clamp(i + d, 1, #z)].tps; dirty(M.track) end)
add("CHANCE", function() return Tr(M.track).rack.fx[2].chance .. "%" end,
              function(d) local r = Tr(M.track).rack.fx[2]; r.chance = clamp(r.chance + d, 0, 100) end)
M.params = P

-- per-param coarse encoder step (faster on the params you sweep most)
local COARSE = { [7] = 5, [8] = 2, [12] = 5 }         -- VEL / GATE / CHANCE
local PLAY_SEL = { [0] = 3, [1] = 2, [2] = 1, [3] = 6, [4] = 7 }

-- ---- navigation helpers -------------------------------------------------
local function nextTrack(dir)
    local n = #E.tracks
    M.track = ((M.track - 1 + dir) % n) + 1
    local len = E.tracks[M.track].pattern.length
    if M.step < 0 or M.step >= len then M.step = 0 end
end

local function nextMode()
    if M.mode == "PLAY" then
        M.mode = "STEP"; M.setup = false
        local len = E.tracks[M.track].pattern.length
        if M.step < 0 or M.step >= len then M.step = 0 end
    elseif M.mode == "STEP" then
        M.mode = "SEQ"; M.seqPage = "SLOT"
    else
        M.mode = "PLAY"
    end
end

local function goBack()
    if M.mode == "PLAY" and M.setup then M.setup = false
    elseif M.mode == "SEQ" and M.seqPage == "SONG" then M.seqPage = "SLOT" end
end

local function goEnter()
    if M.mode == "PLAY" and not M.setup then M.setup = true
    elseif M.mode == "SEQ" and M.seqPage == "SLOT" then M.seqPage = "SONG"; M.songCur = 1 end
end

-- Emit any pending engine.out (note-offs from seq/mute switches) via Grid's
-- `gms` if present. Tests / headless have no gms -> no-op.
local function emitOut()
    if gms and E.out.n > 0 then S.midirx.emit(E.out, gms) end
end

local function toggleNap(t)
    local tr = E.tracks[t]
    if tr.nap.armed then S.track.disarmNap(tr) else S.track.armNap(tr, 2, 2) end
end
local function toggleAuto(t)
    local tr = E.tracks[t]
    if tr.auto.armed then S.track.disarmAuto(tr) else S.track.armAuto(tr, 2) end
end

-- ---- STEP-mode note editing (live, in place) ---------------------------
local function addAtStep(t, step)
    local pat = E.tracks[t].pattern
    if step < 0 or step >= pat.length then return end
    if S.pattern.findEventAtStep(pat, step, pat.zoom) then return end
    S.event.add(pat.events, 60, step * pat.zoom, pat.zoom, 100)
end
local function deleteAtStep(t, step)
    local pat = E.tracks[t].pattern
    while true do
        local i = S.pattern.findEventAtStep(pat, step, pat.zoom)
        if not i then break end
        S.event.removeAt(pat.events, i)
    end
end
local function editAtStep(t, step, field, dir)
    local pat = E.tracks[t].pattern
    local tick = step * pat.zoom
    local ev = pat.events
    for i = 1, ev.n do
        if ev.start[i] == tick then
            if field == 1 then      ev.pitch[i] = clamp(ev.pitch[i] + dir, 0, 127)
            elseif field == 2 then  ev.len[i] = math.max(1, ev.len[i] + dir * pat.zoom)
            else                    ev.vel[i] = clamp(ev.vel[i] + dir * 5, 1, 127) end
        end
    end
end
local function octaveAtStep(t, step, d)
    local pat = E.tracks[t].pattern
    local tick = step * pat.zoom
    local ev = pat.events
    for i = 1, ev.n do
        if ev.start[i] == tick then ev.pitch[i] = clamp(ev.pitch[i] + d, 0, 127) end
    end
end

-- ---- handlers -----------------------------------------------------------
function M.turn(d)
    if not E then return end
    local s = (d > 0 and 1 or -1)
    if M.mode == "PLAY" then
        local p = P[M.sel]; if not p then return end
        p.edit(s * (COARSE[M.sel] or 1))
    elseif M.mode == "STEP" then
        local len = E.tracks[M.track].pattern.length
        M.step = clamp(M.step + s, 0, len - 1)
    elseif M.seqPage == "SLOT" then
        local seq = E.sequences[E.currentSeq]
        local t = M.seqTrack
        seq.slot[t] = clamp(seq.slot[t] + s, 1, E.tracks[t].nSlots)
        E.setSequence(E.currentSeq); emitOut()
    else
        local n = #E.song.steps
        if n > 0 then M.songCur = ((M.songCur - 1 + s) % n) + 1 end
    end
end

function M.click(down)
    if not down or not E then return end
    if M.mode == "PLAY" then
        reroll(M.track)
    elseif M.mode == "STEP" then
        M.field = M.field % 3 + 1
    elseif M.seqPage == "SLOT" then
        local n = #E.sequences
        E.setSequence((E.currentSeq % n) + 1); emitOut()
    else
        local steps = E.song.steps
        if #steps > 0 then
            M.songCur = clamp(M.songCur, 1, #steps)
            E.setSequence(steps[M.songCur]); emitOut()
        end
    end
end

-- Keyswitches 0-7 (mode-specific direct actions; no SHIFT layer).
function M.key(n, down)
    if not down or not E then return end
    if n == 7 then nextMode(); return end

    if M.mode == "PLAY" then
        if M.setup then
            if n == 0 then M.sel = (M.sel - 2) % #P + 1
            elseif n == 1 then M.sel = M.sel % #P + 1
            elseif n == 5 then toggleAuto(M.track)
            elseif n == 6 then nextTrack(1) end
        else
            if PLAY_SEL[n] then M.sel = PLAY_SEL[n] end
            if n == 5 then toggleAuto(M.track) end
            if n == 6 then nextTrack(1) end
        end

    elseif M.mode == "STEP" then
        if n == 0 then addAtStep(M.track, M.step)
        elseif n == 1 then deleteAtStep(M.track, M.step)
        elseif n == 2 then octaveAtStep(M.track, M.step, -12)
        elseif n == 3 then octaveAtStep(M.track, M.step, 12)
        elseif n == 4 then editAtStep(M.track, M.step, M.field, -1)
        elseif n == 5 then editAtStep(M.track, M.step, M.field, 1)
        elseif n == 6 then nextTrack(1) end

    else -- SEQ
        if M.seqPage == "SLOT" then
            if n >= 0 and n <= 3 then M.seqTrack = n + 1 end
            if n == 5 then
                local seq = E.sequences[E.currentSeq]
                E.setTrackMute(M.seqTrack, not seq.mute[M.seqTrack]); emitOut()
            end
        else
            if n == 0 then E.songAdd(E.currentSeq) end
            if n == 1 then
                local nsteps = #E.song.steps
                if nsteps > 0 then
                    E.songRemoveAt(M.songCur)
                    if M.songCur > #E.song.steps then M.songCur = #E.song.steps end
                    if M.songCur < 1 then M.songCur = 1 end
                end
            end
            if n == 2 then E.songClear(); M.songCur = 1 end
        end
    end
end

-- Small buttons 9-12: BACK / ENTER / NAP / COMMIT (dedicated, no chord).
function M.button(b, down)
    if not down or not E then return end
    if b == BTN_NAP then toggleNap(M.track); return end
    if b == BTN_COMMIT then if M.mode == "PLAY" then commit(M.track) end return end
    if b == BTN_BACK then goBack() end
    if b == BTN_ENTER then goEnter() end
end

return M
