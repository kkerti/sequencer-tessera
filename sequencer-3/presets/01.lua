-- Preset 01 — a default C-major arpeggio on lane 1 (16th notes, ch 1).
return {
    version = 1,
    lanes = {
        {
            type = "note", channel = 1, dims = "16x1", length = 16, division = 1,
            scaleMask = 0xAB5, root = 0,
            advanceSource = "transport.sixteenth",
            pitch = { 60, 62, 64, 67, 69, 67, 64, 62, 60, 64, 67, 72, 71, 67, 64, 60 },
            velocity = { 100, 100, 100, 100, 100, 100, 100, 100,
                         100, 100, 100, 100, 100, 100, 100, 100 },
            stepLength = { 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6 },
        },
    },
}
