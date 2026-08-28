-- dist/seq2_gen.lua (generator; pulled by seq2_ctl; auto-generated)
local R={}
local _host=require
local _1
local function require(n)
 local r=R[n] if r~=nil then return r end
 if not _1 then _1=_host("seq2") end local m=_1[n] if m then return m end
 error('seq2 module not found: '..tostring(n))
end
R["generate"]=(function()

local Event = require("event")
local Scales = require("scales")
local M = {}
local function isOnset(i, hits, M_)
 if hits <= 0 then return false end
 if hits >= M_ then return true end
 return (i * hits) // M_ ~= ((i - 1) * hits) // M_
end
function M.run(pattern, opts)
 opts = opts or {}
 local ev = pattern.events
 local M_ = pattern.length
 local tps = pattern.zoom
 local scaleIndex = opts.scaleIndex or 1
 local root = (opts.root or 0) % 12
 local mask = Scales.rotate((Scales.SCALES[scaleIndex] or Scales.SCALES[1]).mask, root)
 local hits = opts.hits or math.max(1, M_ // 4)
 local rotate = (opts.rotate or 0) % M_
 local pRoot = opts.pitchRoot or (57 + root)
 local pSpr = opts.pitchSpread or 4
 local vRoot = opts.velRoot or 100
 local vSpr = opts.velSpread or 20
 local gRoot = opts.gateRoot or tps
 local gSpr = opts.gateSpread or (tps // 2)
 local seed = (opts.seed or 1) & 0xFFFFFFFF
 local function rnd() seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF; return (seed >> 16) & 0x7FFF end
 local function ri(lo, hi) if hi <= lo then return lo end return lo + rnd() % (hi - lo + 1) end
 Event.clear(ev)
 local count = 0
 for i = 0, M_ - 1 do
 if isOnset(i, hits, M_) then
 local s = (i + rotate) % M_
 local pitch = Scales.step(pRoot, mask, ri(-pSpr, pSpr))
 local vel = vRoot + ri(-vSpr, vSpr)
 if vel < 1 then vel = 1 elseif vel > 127 then vel = 127 end
 local gate = gRoot + ri(-gSpr, gSpr)
 if gate < 1 then gate = 1 end
 Event.add(ev, pitch, s * tps, gate, vel)
 count = count + 1
 end
 end
 return count
end
return M

end)()
return { generate=R.generate }
