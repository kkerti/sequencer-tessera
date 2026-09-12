-- Preset 05 — polyrhythm: four Note lanes on one clock, different divisions.
--
-- All lanes advance from the 16th-note tap, divided by 1/2/3/4, so they phase
-- against each other. A whole-note tap resets them together.
return {
    version = 1,
    lanes = {
        {
            type = "note", channel = 1, division = 1, scaleMask = 0xAB5, root = 0,
            advanceSource = "transport.sixteenth", resetSource = "transport.whole",
            pitch = { 60, 64, 67, 72, 60, 64, 67, 72, 60, 64, 67, 72, 60, 64, 67, 72 },
        },
        {
            type = "note", channel = 2, division = 2, scaleMask = 0xAB5, root = 0,
            advanceSource = "transport.sixteenth", resetSource = "transport.whole",
            pitch = { 48, 48, 55, 55, 48, 48, 53, 53, 48, 48, 55, 55, 48, 48, 53, 53 },
        },
        {
            type = "note", channel = 3, division = 3, scaleMask = 0xAB5, root = 0,
            advanceSource = "transport.sixteenth", resetSource = "transport.whole",
            pitch = { 79, 76, 72, 76, 79, 76, 72, 76, 79, 76, 72, 76, 79, 76, 72, 76 },
        },
        {
            type = "note", channel = 4, division = 4, scaleMask = 0xAB5, root = 0,
            advanceSource = "transport.sixteenth", resetSource = "transport.whole",
            pitch = { 36, 43, 36, 43, 36, 43, 36, 43, 36, 43, 36, 43, 36, 43, 36, 43 },
        },
    },
}
