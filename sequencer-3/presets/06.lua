-- Preset 06 — a random quantized melody plus a 5-hit trigger pattern.
--
-- Lane 1 is a melody that the old live Gamut generator produced, frozen as
-- steps (A minor, on 8ths). Lane 2 is a 5-hit Euclidean pattern on 16ths.
-- Press key 3 (Random) on a lane to roll a fresh pattern.
return {
    version = 1,
    lanes = {
        {
            type = "note", channel = 1, scaleMask = 0x5AD, root = 9,   -- A minor
            advanceSource = "transport.eighth",
            pitch = { 71, 74, 67, 72, 65, 72, 72, 74, 69, 72, 67, 72, 67, 62, 72, 74 },
            velocity = { 92, 89, 94, 108, 98, 111, 98, 96, 100, 97, 96, 88, 83, 83, 114, 115 },
            stepLength = { 8, 5, 6, 8, 6, 8, 5, 4, 7, 8, 5, 5, 7, 7, 4, 4 },
        },
        {
            type = "trig", channel = 2, midiNote = 38,
            advanceSource = "transport.sixteenth",
            gate = { 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0 },
        },
    },
}
