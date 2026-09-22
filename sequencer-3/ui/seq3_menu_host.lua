-- seq3_menu_host.lua
-- Host side of the sequencer-3 menu screen. Pure host policy (SPEC §6): the
-- action-API surface, the menu tree, canvas assembly, and the control map.
--
-- PREVIEW MODEL: `seq3` below is an in-memory snapshot implementing the
-- action-API verbs the menu uses (docs/ACTION_API.md) over the settled lane
-- record fields. On device, bind the same menu to the real Core instead:
--   local seq3 = require("engine")        -- the same named actions
-- The GUI calls only the named verbs — the action API is the boundary
-- (sequencer-3 AGENTS.md rule 7). The preview stores `scaleMask` UNROTATED
-- (the device engine stores the root-rotated form).
--
-- The tree hides inapplicable settings per docs/PARAM_DEPENDENCIES.md:
--   dims 16x1 -> ADV + LEN ; multi-dims -> XADV + YADV
--   SCALE + ROOT only on Note lanes
--   GEN KIND euclid -> HITS ; gamut -> SPREAD / D-U / VEL / GATE

-- ---------------------------------------------------------------------------
-- action API surface (preview snapshot; device binds require("engine"))
-- ---------------------------------------------------------------------------
seq3 = { lanes = {} }
do
  local gen_defaults = { kind = "gamut", hits = 4, spread = 12, downUp = 64,
                         velSpread = 30, gateSpread = 20, seed = 1 }
  for lane = 1, 4 do
    local t = {
      type = "note", dims = "16x1", length = 16, division = 1, channel = lane,
      scaleMask = 0xAB5, root = 0,
      advanceSource = "transport.sixteenth",
      xAdvanceSource = "transport.quarter",
      yAdvanceSource = "transport.sixteenth",
      controller = 20, midiNote = 36,
      gen = {}, genTick = 0,
    }
    for k, v in pairs(gen_defaults) do t.gen[k] = v end
    seq3.lanes[lane] = t
  end
end

function seq3.get(lane, field) return seq3.lanes[lane][field] end
function seq3.set(lane, field, v) seq3.lanes[lane][field] = v end

-- thin named verbs — the menu calls only these plus get/set
function seq3.setType(lane, kind) seq3.set(lane, "type", kind) end
function seq3.setDimensions(lane, d) seq3.set(lane, "dims", d) end
function seq3.setLength(lane, n) seq3.set(lane, "length", n) end
function seq3.setDivision(lane, n) seq3.set(lane, "division", n) end
function seq3.setChannel(lane, ch) seq3.set(lane, "channel", ch) end
function seq3.setScale(lane, mask, root)
  seq3.set(lane, "scaleMask", mask)
  seq3.set(lane, "root", root)
end
function seq3.setAdvanceSource(lane, s) seq3.set(lane, "advanceSource", s) end
function seq3.setXAdvanceSource(lane, s) seq3.set(lane, "xAdvanceSource", s) end
function seq3.setYAdvanceSource(lane, s) seq3.set(lane, "yAdvanceSource", s) end
function seq3.generate(lane, opts)
  local g = seq3.lanes[lane].gen
  for k, v in pairs(opts) do g[k] = v end
  seq3.lanes[lane].genTick = seq3.lanes[lane].genTick + 1   -- preview marker
end

-- ---------------------------------------------------------------------------
-- vocabulary (docs/NAMING.md; masks from src/core/scales.lua M.SCALES)
-- ---------------------------------------------------------------------------
local TYPES = { "note", "mod", "trig", "gate" }
local DIMS  = { "16x1", "8x2", "5x3", "4x3", "4x4" }
local SOURCES = { "off", "transport.whole", "transport.half", "transport.quarter",
  "transport.eighth", "transport.sixteenth" }
for i = 0, 7 do SOURCES[#SOURCES + 1] = "external." .. i end
for i = 1, 4 do SOURCES[#SOURCES + 1] = "lane." .. i end
local SCALES = {
  { name = "off",      mask = 0x000 },
  { name = "major",    mask = 0xAB5 },
  { name = "minor",    mask = 0x5AD },
  { name = "harm min", mask = 0x9AD },
  { name = "dorian",   mask = 0x6AD },
  { name = "phrygian", mask = 0x5AB },
  { name = "mixolyd",  mask = 0x6B5 },
  { name = "min pent", mask = 0x4A9 },
}
local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

-- ---------------------------------------------------------------------------
-- item builders
-- ---------------------------------------------------------------------------
local function cycleItem(label, list, getf, setf)
  return {
    label = label,
    value = function() return tostring(getf()) end,
    edit = function(delta)
      local cur = getf()
      local idx = 1
      for i = 1, #list do
        if list[i] == cur then idx = i break end
      end
      idx = idx + delta
      if idx < 1 then idx = 1 elseif idx > #list then idx = #list end
      setf(list[idx])
    end,
  }
end

local function rangeItem(label, lo, hi, step, getf, setf, fmt)
  return {
    label = label,
    value = function()
      local v = getf()
      return fmt and fmt(v) or tostring(v)
    end,
    edit = function(delta)
      local v = getf() + delta * step
      if v < lo then v = lo elseif v > hi then v = hi end
      setf(v)
    end,
  }
end

local function scaleItem(lane)
  local L = seq3.lanes[lane]
  return {
    label = "SCALE",
    value = function()
      local mask = L.scaleMask
      for _, s in ipairs(SCALES) do
        if s.mask == mask then return s.name end
      end
      return "0x" .. string.format("%03X", mask)
    end,
    edit = function(delta)
      local idx = 1
      for i, s in ipairs(SCALES) do
        if s.mask == L.scaleMask then idx = i break end
      end
      idx = idx + delta
      if idx < 1 then idx = 1 elseif idx > #SCALES then idx = #SCALES end
      seq3.setScale(lane, SCALES[idx].mask, L.root)
    end,
  }
end

-- ---------------------------------------------------------------------------
-- menu tree
-- ---------------------------------------------------------------------------
local function genNode(lane)
  local G = seq3.lanes[lane].gen
  local items = {
    cycleItem("KIND", { "gamut", "euclid" },
      function() return G.kind end, function(v) G.kind = v end),
  }
  if G.kind == "euclid" then
    items[#items + 1] = rangeItem("HITS", 1, 16, 1,
      function() return G.hits end, function(v) G.hits = v end)
  else
    items[#items + 1] = rangeItem("SPREAD", 0, 48, 1,
      function() return G.spread end, function(v) G.spread = v end)
    items[#items + 1] = rangeItem("D/U", 0, 127, 8,
      function() return G.downUp end, function(v) G.downUp = v end,
      function(v) return (v <= 42 and "below") or (v >= 85 and "above") or "mixed" end)
    items[#items + 1] = rangeItem("VEL", 0, 127, 4,
      function() return G.velSpread end, function(v) G.velSpread = v end)
    items[#items + 1] = rangeItem("GATE", 0, 127, 4,
      function() return G.gateSpread end, function(v) G.gateSpread = v end)
  end
  items[#items + 1] = rangeItem("SEED", 0, 9999, 1,
    function() return G.seed end, function(v) G.seed = v end)
  items[#items + 1] = {
    label = "GEN NOW",
    value = function()
      local tick = seq3.lanes[lane].genTick
      return tick > 0 and ("RUN x" .. tick) or "RUN"
    end,
    act = function()
      seq3.generate(lane, {
        kind = G.kind, hits = G.hits, spread = G.spread, downUp = G.downUp,
        velSpread = G.velSpread, gateSpread = G.gateSpread, seed = G.seed,
      })
    end,
  }
  return { title = "GEN L" .. lane, items = items }
end

local function laneNode(lane)
  local L = seq3.lanes[lane]
  local items = {
    cycleItem("TYPE", TYPES,
      function() return L.type end, function(v) seq3.setType(lane, v) end),
    cycleItem("DIMS", DIMS,
      function() return L.dims end, function(v) seq3.setDimensions(lane, v) end),
  }
  if L.dims == "16x1" then
    items[#items + 1] = rangeItem("LEN", 1, 16, 1,
      function() return L.length end, function(v) seq3.setLength(lane, v) end)
    items[#items + 1] = cycleItem("ADV", SOURCES,
      function() return L.advanceSource end,
      function(v) seq3.setAdvanceSource(lane, v) end)
  else
    items[#items + 1] = cycleItem("XADV", SOURCES,
      function() return L.xAdvanceSource end,
      function(v) seq3.setXAdvanceSource(lane, v) end)
    items[#items + 1] = cycleItem("YADV", SOURCES,
      function() return L.yAdvanceSource end,
      function(v) seq3.setYAdvanceSource(lane, v) end)
  end
  items[#items + 1] = rangeItem("DIV", 1, 16, 1,
    function() return L.division end, function(v) seq3.setDivision(lane, v) end)
  items[#items + 1] = rangeItem("CHAN", 1, 16, 1,
    function() return L.channel end, function(v) seq3.setChannel(lane, v) end)
  if L.type == "note" then
    items[#items + 1] = scaleItem(lane)
    items[#items + 1] = rangeItem("ROOT", 0, 11, 1,
      function() return L.root end, function(v) seq3.setScale(lane, L.scaleMask, v) end,
      function(v) return NOTE_NAMES[v + 1] end)
  end
  items[#items + 1] = { label = "GEN", sub = function() return genNode(lane) end }
  return { title = "LANE " .. lane, items = items }
end

local function rootNode()
  local items = {}
  for lane = 1, 4 do
    items[lane] = { label = "LANE " .. lane, sub = function() return laneNode(lane) end }
  end
  return { title = "SEQ3 SETUP", items = items }
end

-- ---------------------------------------------------------------------------
-- canvas assembly. grid-wasm has no LCD element; the §3.1 shim forwards the
-- element-method calls onto the harness globals with the screen index (0)
-- prepended. On device, `lcd` is the real element (self) and the shim is
-- never shipped.
-- ---------------------------------------------------------------------------
lcd = setmetatable({}, {
  __index = function(_, name)
    return function(_, ...) return _G[name](0, ...) end
  end,
})

canvas = core.Layout:new()
canvas:initialize(lcd, nil, nil, 0, 0, 320, 240)
canvas:place(0, 0, 320, 220, MW.menu{ root = rootNode(), rows = 6 })
canvas:place(0, 220, 320, 20,
  MW.label{ text = "KS0/1 MOVE KS2 OPEN KS3 BACK ENC EDIT" })

-- ---------------------------------------------------------------------------
-- control map (host policy). On device, element events call canvas:dispatch
-- directly; the grid-wasm loop edge-handler maps grid.event_* onto this.
--   KS0 up / KS1 down / KS2 open / KS3 back ; encoder edits the selected value
--   BTN9-12 mirror open/back/up/down
-- ---------------------------------------------------------------------------
handleControl = function(index, delta)
  if index == 8 then
    canvas:dispatch("enc_cb", delta or 0)
  elseif index >= 0 and index <= 7 then
    if index == 0 then canvas:dispatch("nav_cb", -1)
    elseif index == 1 then canvas:dispatch("nav_cb", 1)
    elseif index == 2 then canvas:dispatch("enter_cb")
    elseif index == 3 then canvas:dispatch("back_cb") end
  else
    if index == 9 then canvas:dispatch("enter_cb")
    elseif index == 10 then canvas:dispatch("back_cb")
    elseif index == 11 then canvas:dispatch("nav_cb", -1)
    elseif index == 12 then canvas:dispatch("nav_cb", 1) end
  end
end