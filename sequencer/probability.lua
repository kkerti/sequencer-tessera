-- sequencer/probability.lua
-- Non-destructive probability layer for step playback.
-- Evaluated at Engine.tick() time between step read and MIDI event emission.
-- Inspired by Blackbox per-note PLAY probability (0-100%).
--
-- This module is intentionally stateless: it does not track which steps
-- were suppressed. The engine handles NOTE_OFF suppression by tracking
-- whether a NOTE_ON was actually emitted for the current step.

local Probability = {}

-- Returns true if the step should play, false if suppressed.
-- Uses step.probability (0-100). 100 = always, 0 = never.
-- Steps without a probability field default to 100 (always play).
function Probability.shouldPlay(step)
    local prob = step.probability
    if prob == nil or prob >= 100 then
        return true
    end
    if prob <= 0 then
        return false
    end
    local roll = math.random(1, 100)
    return roll <= prob
end

return Probability
