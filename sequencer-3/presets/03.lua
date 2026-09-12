-- Preset 03 — MIDI-reactive lane.
--
-- Sends note/CC into Sequencer3ClockIn to drive the sequencer:
--   note 36 -> advance lane 1        (external.0)
--   note 37 -> reset lane 1 to step 1 (external.1)
--   note 38 -> jump lane 1 to a random step (external.2)
--   CC   23 -> address lane 1's playhead (external.3 value; unset until sent)
-- The lane has no transport advance, so it only moves when you play it.
return {
    version = 1,
    lanes = {
        {
            type = "note", channel = 1, dims = "16x1", length = 16, division = 1,
            scaleMask = 0xAB5, root = 0,
            advanceSource = "external.0",
            resetSource   = "external.1",
            randomSource  = "external.2",
            addressSource = "external.3",
            pitch = { 60, 62, 64, 65, 67, 69, 71, 72, 72, 71, 69, 67, 65, 64, 62, 60 },
            velocity = { 110, 90, 110, 90, 110, 90, 110, 90,
                         110, 90, 110, 90, 110, 90, 110, 90 },
            stepLength = { 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6 },
        },
    },
}
