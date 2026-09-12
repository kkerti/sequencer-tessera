-- Preset 06 — Gamut: a live random quantized melody plus a Euclidean trigger.
--
-- Lane 1 regenerates a fresh in-scale note at the playhead on every 8th note
-- (turn it off with seq3.generate(1,{fill=false}) or by editing the preset to
-- drop `live`). Lane 2 is a 5-hit Euclidean gate pattern on 16ths.
return {
    version = 1,
    lanes = {
        {
            type = "note", channel = 1, scaleMask = 0x5AD, root = 9,   -- A minor
            advanceSource = "transport.eighth",
            generate = { kind = "gamut", base = 69, spread = 12, downUp = 64,
                         velSpread = 18, gateSpread = 2, seed = 11, live = true },
        },
        {
            type = "trig", channel = 2, midiNote = 38,
            advanceSource = "transport.sixteenth",
            generate = { kind = "euclid", hits = 5 },
        },
    },
}
