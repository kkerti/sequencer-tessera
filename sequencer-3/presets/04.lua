-- Preset 04 — "Voice": one trig lane drives a note lane and two mod lanes.
--
-- Lane 1 is a trigger pattern on 16th notes (ch 1, note 36). Lanes 2-4 advance
-- every time lane 1 actually fires, so they move only on active trig steps.
-- Lane 2 is the melody (ch 2, A minor); lanes 3/4 are modulation CCs
-- (ch 3 = CC 74 cutoff, ch 4 = CC 1 mod wheel).
return {
    version = 1,
    lanes = {
        {
            type = "trig", channel = 1, midiNote = 36,
            advanceSource = "transport.sixteenth",
            gate = { 1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 0 },
        },
        {
            type = "note", channel = 2, scaleMask = 0x5AD, root = 9,
            advanceSource = "lane.1",
            pitch = { 69, 72, 76, 74, 72, 69, 67, 72, 69, 72, 76, 79, 76, 72, 69, 67 },
            velocity = { 110, 90, 100, 90, 110, 90, 100, 90,
                         110, 90, 100, 90, 110, 90, 100, 90 },
            stepLength = { 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6 },
        },
        {
            type = "mod", channel = 3, controller = 74,
            advanceSource = "lane.1",
            value = { 20, 60, 100, 80, 40, 90, 30, 70, 20, 60, 100, 80, 40, 90, 30, 70 },
        },
        {
            type = "mod", channel = 4, controller = 1,
            advanceSource = "lane.1",
            value = { 0, 80, 120, 40, 90, 20, 110, 50, 0, 80, 120, 40, 90, 20, 110, 50 },
        },
    },
}
