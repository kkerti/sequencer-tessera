-- Smoke test: load grid/sequencer.lua exactly as the device would.
package.path = "grid/?.lua;" .. package.path
local Driver = require("sequencer")
local descriptor = require("four_on_floor")
local engine = Driver.PatchLoader.build(descriptor)

local now = 0
local function clockFn() return now end
local d = Driver.new(engine, clockFn, descriptor.bpm)
Driver.start(d)

local events = {}
local function emit(line) events[#events + 1] = line end

-- Drive 1 second of internal-clock pulses (no external clock here).
local pulseMs = d.pulseMs
for i = 1, 96 do
    now = now + pulseMs
    Driver.tick(d, emit)
end
print("emitted", #events, "events; first 4:")
for i = 1, math.min(4, #events) do print("  " .. events[i]) end
assert(#events >= 4, "expected at least 4 events from four_on_floor in 1 second")
print("OK")
