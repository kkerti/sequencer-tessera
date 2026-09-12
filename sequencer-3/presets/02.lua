-- Preset 02 — 4x4 matrix navigation on one Note lane.
--
-- X advances every 16th note (wraps within the row); Y advances every quarter
-- note (wraps within the column). Play it and sweep Y to change the row.
return {
    version = 1,
    lanes = {
        {
            type = "note", channel = 1, dims = "4x4",
            scaleMask = 0xAB5, root = 0,
            xAdvanceSource = "transport.sixteenth",
            yAdvanceSource = "transport.quarter",
            pitch = {
                60, 62, 64, 67,
                64, 65, 67, 69,
                67, 69, 71, 72,
                69, 71, 72, 74,
            },
            velocity = {
                100, 80, 100, 90,
                100, 80, 100, 90,
                100, 80, 100, 90,
                100, 80, 100, 90,
            },
            stepLength = { 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4 },
        },
    },
}
