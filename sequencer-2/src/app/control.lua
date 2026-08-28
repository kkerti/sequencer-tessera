-- control.lua — input handling + the staged parameter model (UI bundle).
--
-- Modes (ARCHITECTURE §6): PLAY (staged generator params), STEP (per-note
-- editing, live), SEQ (pattern-slot picker). SETUP is a full-screen detail
-- view WITHIN PLAY, not a separate mode (CONTEXT.md). The SONG builder page
-- was CUT for the lean device build (engine song API remains, App-level).
--
-- Staging rule: only generator params stage — edits mutate a per-track staged
-- copy; COMMIT applies it and regenerates once. Per-note edits (STEP), reroll,
-- auto-reroll, nap, and mute all apply immediately. COMMIT and NAP are
-- DEDICATED small buttons (never a shifted/chorded key).
--
-- Control surface:
--   keyswitches 0-7   context actions (mode-specific, below)
--   small buttons 9-12:  9 = BACK   10 = ENTER   11 = NAP   12 = COMMIT
--   encoder           turn = stage / cursor / slot   click = reroll / field
--
-- Hierarchy (ENTER goes deeper, BACK returns):
--   PLAY  (compact)  --ENTER-->  SETUP (full param grid)
--
--   GLOBAL          KS7 = MODE  PLAY -> STEP -> SEQ -> PLAY
--   PLAY            KS0..KS4 = HITS, KEY, SCALE, SPREAD, VEL
--                   KS5 = AUTO-REROLL   KS6 = TRACK next
--                   enc turn = STAGE   enc click = REROLL
--                   ENTER = SETUP   NAP = nap   COMMIT = apply staged
--   SETUP (PLAY)    KS0/KS1 = prev/next param   KS5 = AUTO-REROLL   KS6 = TRACK
--                   enc turn = STAGE   enc click = REROLL   BACK = exit
--   STEP            KS0 = ADD note   KS1 = DELETE note(s)
--                   KS2/KS3 = octave down/up   KS4/KS5 = field value -/+
--                   KS6 = TRACK next   enc turn = step cursor   enc click = field
--   SEQ (SLOT)      KS0..KS3 = track 1..4   KS5 = MUTE
--                   enc turn = slot +/-   enc click = next sequence
--
-- Screen reads: CTL.mode, track, sel, setup, step, field, seqTrack.
--               CTL.params[i] = { label, kind }; CTL.show(i) formats;
--               CTL.edit(i,d) stages. CTL.frame() services auto-reroll.
--
-- Param model is DATA (label + kind), not closures: one edit() dispatcher and
-- one show() formatter keep the compiled footprint small (the device heap is
-- the real constraint — see docs/ARCHITECTURE.md §10).

local M = { mode = "PLAY", track = 1, sel = 1, setup = false,
            step = 0, field = 1, seqTrack = 1 }

local E, S
local Generate = require("generate")
local NOTE = { "C","C#","D","D#","E","F","F#","G","G#","A","A#","B" }
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end
local function noteName(m) return NOTE[m % 12 + 1] .. (m // 12 - 1) end

local function Sg(t) return E.tracks[t].staged end

-- ---- param kinds (P[i] = { label, kind }) -------------------------------
local P = {
    { "SCALE", 1 },  { "KEY", 2 },    { "HITS", 3 },   { "ROTATE", 4 },
    { "PITCH", 5 },  { "SPREAD", 6 }, { "VEL", 7 },    { "GATE", 8 },
    { "SEED", 9 },   { "LENGTH", 10 },{ "ZOOM", 11 },  { "CHANCE", 12 },
}
M.params = P

-- per-param coarse encoder step (1-based param index)
local COARSE = { [7] = 5, [8] = 2, [12] = 5 }
local PLAY_SEL = { [0] = 3, [1] = 2, [2] = 1, [3] = 6, [4] = 7 }

-- Stage a param edit (kind-specific). Live param (CHANCE) applies at once.
function M.edit(i, d)
    local t = M.track
    if i == 12 then
        local r = E.tracks[t].rack.fx[2]
        r.chance = clamp(r.chance + d, 0, 100)
        return
    end
    local s = Sg(t)
    if     i == 1  then s.scaleIndex = clamp(s.scaleIndex + d, 1, #S.scales.SCALES)
    elseif i == 2  then s.root = (s.root + d) % 12
    elseif i == 3  then s.hits = clamp(s.hits + d, 1, s.length)
    elseif i == 4  then s.rotate = (s.rotate + d) % s.length
    elseif i == 5  then s.pitchRoot = clamp(s.pitchRoot + d, 24, 96)
    elseif i == 6  then s.pitchSpread = clamp(s.pitchSpread + d, 0, 12)
    elseif i == 7  then s.velRoot = clamp(s.velRoot + d, 1, 127)
    elseif i == 8  then s.gateRoot = clamp(s.gateRoot + d, 1, 48)
    elseif i == 9  then s.seed = math.max(1, s.seed + d)
    elseif i == 10 then s.length = clamp(s.length + d, 1, 64); s.hits = clamp(s.hits, 1, s.length)
    else
        local z = S.pattern.ZOOM; local j = 1
        for k, v in ipairs(z) do if v.tps == s.zoom then j = k end end
        s.zoom = z[clamp(j + d, 1, #z)].tps
    end
    E.tracks[t].dirty = true
end

-- Format a param value for the screen.
function M.show(i)
    local t = M.track
    if i == 12 then return E.tracks[t].rack.fx[2].chance .. "%" end
    local s = Sg(t)
    if     i == 1  then return S.scales.SCALES[s.scaleIndex].name
    elseif i == 2  then return NOTE[s.root + 1]
    elseif i == 3  then return s.hits .. " / " .. s.length
    elseif i == 4  then return tostring(s.rotate)
    elseif i == 5  then return noteName(s.pitchRoot)
    elseif i == 6  then return s.pitchSpread .. " deg"
    elseif i == 7  then return tostring(s.velRoot)
    elseif i == 8  then return s.gateRoot .. "t"
    elseif i == 9  then return tostring(s.seed)
    elseif i == 10 then return s.length .. " st"
    else return "z" .. s.zoom end
end

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
    c.seed = t
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
    Generate.run(tr.pattern, g)
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

-- Reroll: seed++ and regenerate NOW (never staged).
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

-- Auto-reroll servicing: called once per draw frame (off the hot path).
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
        M.mode = "SEQ"
    else
        M.mode = "PLAY"
    end
end

local function goBack()
    if M.mode == "PLAY" and M.setup then M.setup = false end
end

local function goEnter()
    if M.mode == "PLAY" and not M.setup then M.setup = true end
end

-- Emit pending engine.out (note-offs from seq/mute switches) via gms if present.
-- midirx lives in the seq2b bundle on device; resolve it once, lazily.
local MRX
local function emitOut()
    if gms and E.out.n > 0 then
        if not MRX then MRX = S.midirx or require("midirx") end
        MRX.emit(E.out, gms)
    end
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
        M.edit(M.sel, s * (COARSE[M.sel] or 1))
    elseif M.mode == "STEP" then
        local len = E.tracks[M.track].pattern.length
        M.step = clamp(M.step + s, 0, len - 1)
    else -- SEQ: slot
        local seq = E.sequences[E.currentSeq]
        local t = M.seqTrack
        seq.slot[t] = clamp(seq.slot[t] + s, 1, E.tracks[t].nSlots)
        E.setSequence(E.currentSeq); emitOut()
    end
end

function M.click(down)
    if not down or not E then return end
    if M.mode == "PLAY" then
        reroll(M.track)
    elseif M.mode == "STEP" then
        M.field = M.field % 3 + 1
    else -- SEQ: next sequence
        local n = #E.sequences
        E.setSequence((E.currentSeq % n) + 1); emitOut()
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

    else -- SEQ (slot picker)
        if n >= 0 and n <= 3 then M.seqTrack = n + 1 end
        if n == 5 then
            local seq = E.sequences[E.currentSeq]
            E.setTrackMute(M.seqTrack, not seq.mute[M.seqTrack]); emitOut()
        end
    end
end

-- Small buttons 9-12: BACK / ENTER / NAP / COMMIT (dedicated, no chord).
function M.button(b, down)
    if not down or not E then return end
    if b == 11 then toggleNap(M.track); return end
    if b == 12 then if M.mode == "PLAY" then commit(M.track) end return end
    if b == 9 then goBack() end
    if b == 10 then goEnter() end
end

return M
