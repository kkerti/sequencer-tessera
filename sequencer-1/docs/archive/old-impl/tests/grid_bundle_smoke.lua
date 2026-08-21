-- Smoke test: load grid/sequencer.lua exactly as the device would.
-- The device-side bundle is just a copy of root sequencer.lua (no bundling).
package.path = "grid/?.lua;" .. package.path
local Seq         = require("sequencer")
local Driver      = Seq.Driver
local PatchLoader = Seq.PatchLoader

local descriptor = require("four_on_floor")
local engine     = PatchLoader.build(descriptor)

local now = 0
local function clockFn() return now end
local d = Driver.new(engine, clockFn, descriptor.bpm)
Driver.start(d)

local events = {}
local function emit(kind, pitch, velocity, channel)
    events[#events + 1] = { kind = kind, pitch = pitch, velocity = velocity, channel = channel }
end

-- Drive 1 second of internal-clock pulses (no external clock here).
local pulseMs = d.pulseMs
for i = 1, 96 do
    now = now + pulseMs
    Driver.tick(d, emit)
end

print("emitted", #events, "events; first 4:")
for i = 1, math.min(4, #events) do
    local e = events[i]
    print(string.format("  %-9s pitch=%-3d vel=%-3s ch=%d",
        e.kind, e.pitch, tostring(e.velocity or "-"), e.channel))
end
assert(#events >= 4, "expected at least 4 events from four_on_floor in 1 second")
print("OK")
