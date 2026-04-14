-- tests/performance.lua

local Performance = require("sequencer/performance")

do
    local hold, carry = Performance.nextSwingHold(1, 4, 50, 0)
    assert(hold == false)
    assert(carry == 0)
end

do
    local carry = 0
    local hold
    hold, carry = Performance.nextSwingHold(1, 4, 72, carry)
    assert(hold == false)
    hold, carry = Performance.nextSwingHold(2, 4, 72, carry)
    assert(hold == true)
end

print("tests/performance.lua OK")
