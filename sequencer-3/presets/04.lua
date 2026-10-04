-- Preset 04 — "Voice": a trig lane, a melody and two modulation lanes.
--
-- Lane 1 is a trigger pattern on 16th notes (ch 1, note 36). Lanes 2-4 also
-- advance on 16ths (lane->lane routing was cut for device RAM).
-- Lane 2 is the melody (ch 2, A minor). Lanes 3/4 are chromatic note lanes
-- whose pitches are modulation values (ch 3, ch 4): an FH-2 turns them into
-- CV. They were Mod (CC) lanes before Mod was folded into Note.
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
            advanceSource = "transport.sixteenth",
            pitch = { 69, 72, 76, 74, 72, 69, 67, 72, 69, 72, 76, 79, 76, 72, 69, 67 },
            velocity = { 110, 90, 100, 90, 110, 90, 100, 90,
                         110, 90, 100, 90, 110, 90, 100, 90 },
            stepLength = { 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6 },
        },
        {
            type = "note", channel = 3, scaleMask = 0,
            advanceSource = "transport.sixteenth",
            pitch = { 20, 60, 100, 80, 40, 90, 30, 70, 20, 60, 100, 80, 40, 90, 30, 70 },
        },
        {
            type = "note", channel = 4, scaleMask = 0,
            advanceSource = "transport.sixteenth",
            pitch = { 0, 80, 120, 40, 90, 20, 110, 50, 0, 80, 120, 40, 90, 20, 110, 50 },
        },
    },
}
