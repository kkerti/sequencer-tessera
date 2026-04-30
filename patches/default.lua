-- patches/default.lua
-- Test patch in human form. Loaded and packed at startup.
-- Schema:
--   { tracks = { { len, chan, div, dir, steps = { {pitch=, vel=, dur=, gate=, ratch=, prob=, active=}, ... } }, ... } }

return {
    tracks = {
        {
            len = 8, chan = 1, div = 1, dir = 1,
            steps = {
                { pitch=60, vel=100, dur=6, gate=3 },
                { pitch=63, vel=90,  dur=6, gate=2 },
                { pitch=67, vel=110, dur=6, gate=4, ratch=true },
                { pitch=70, vel=80,  dur=6, gate=3, prob=64 },
                { pitch=72, vel=100, dur=6, gate=3 },
                { pitch=67, vel=90,  dur=6, gate=2 },
                { pitch=63, vel=85,  dur=6, gate=2 },
                { pitch=60, vel=95,  dur=6, gate=6 },  -- legato into next loop
            },
        },
        {
            len = 4, chan = 2, div = 2, dir = 1,
            steps = {
                { pitch=36, vel=120, dur=12, gate=4 },
                { pitch=36, vel=100, dur=12, gate=4 },
                { pitch=38, vel=120, dur=12, gate=4 },
                { pitch=36, vel=110, dur=12, gate=4 },
            },
        },
        {
            len = 16, chan = 3, div = 1, dir = 3,  -- ping-pong
            steps = {
                { pitch=72, vel=80, dur=3, gate=1 },
                { pitch=74, vel=80, dur=3, gate=1 },
                { pitch=76, vel=80, dur=3, gate=1 },
                { pitch=79, vel=80, dur=3, gate=1 },
            },
        },
        {
            len = 1, chan = 10, div = 1, dir = 1,
            steps = { { pitch=42, vel=90, dur=6, gate=2, active=false } },
        },
    },
}
