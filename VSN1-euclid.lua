-- VSN1-euclid.lua
-- =============================================================================
-- ON-DEVICE ENTRY POINT for the VSN1 module running the EUCLIDEAN engine.
-- =============================================================================
--
-- Sibling of VSN1.lua. Same lazy-load shape, different bundles:
--   [1]  init           -> require("euclid")        (Core, ~5 KB)
--   first user input    -> require("euclid_ui")     (screen, ~5 KB)
--                          require("euclid_vsn1")   (handlers, ~1 KB)
--
-- Pure-playback path (MIDI rx only, no input, no draw) never loads the
-- UI/VSN1 bundles. Each individual `require` stays well within the
-- module watchdog budget.
--
-- All real handler logic lives in src/euclidean/vsn1_app.lua (bundled
-- into dist/euclid_vsn1.lua). Each per-event scriptlet here is a thin
-- one-line dispatch into APP.
--
-- Hardware mapping:
--   Screen     : 320x240 concentric overlay (T1 outer ring -> T4 inner ring),
--                polygon connector + per-track playhead pip, right-column
--                params for the selected track. Greyscale + mute red.
--   Keyswitch  : 1=ROTATE 2=EVENTS 3=STEPS 4=KEY  5..7=(reserved)  8=SHIFT.
--   4 small btns: select track 1..4.
--   Endless    : turn = act-per-mode; click = mute toggle on selected track.
--                Shift + turn coarsens KEY by x12.
--
-- No EN16 satellite for euclidean (out of scope per project brief).
-- =============================================================================


-- =============================================================================
-- [1] MODULE INIT  (Core only; UI is lazy)
-- =============================================================================

EUC    = require("euclid")
ENGINE = EUC.Core.engine
TRACK  = EUC.Core.track
APP    = nil
CTL    = nil

-- Four tracks, each with a recognisable euclidean default so something
-- audible happens immediately when external clock starts. Channels 0..3.
--   T1 E(3,8)   tresillo         on C4   ch 0
--   T2 E(5,8)   cinquillo        on D#4  ch 1
--   T3 E(4,16)  four-on-floor    on G4   ch 2
--   T4 E(7,12)  7-against-12     on A#4  ch 3
ENGINE.init({ trackCount = 4 })

ENGINE.setSteps(1, 8);  ENGINE.setEvents(1, 3); ENGINE.setKey(1, 60); ENGINE.setPpstep(1, 6); ENGINE.setGate(1, 3); ENGINE.setChan(1, 0)
ENGINE.setSteps(2, 8);  ENGINE.setEvents(2, 5); ENGINE.setKey(2, 63); ENGINE.setPpstep(2, 6); ENGINE.setGate(2, 3); ENGINE.setChan(2, 1)
ENGINE.setSteps(3, 16); ENGINE.setEvents(3, 4); ENGINE.setKey(3, 67); ENGINE.setPpstep(3, 3); ENGINE.setGate(3, 2); ENGINE.setChan(3, 2)
ENGINE.setSteps(4, 12); ENGINE.setEvents(4, 7); ENGINE.setKey(4, 70); ENGINE.setPpstep(4, 4); ENGINE.setGate(4, 2); ENGINE.setChan(4, 3)

-- Lazy loader. Called from every input scriptlet and the first screen
-- draw. Loads the screen UI bundle, the VSN1 handler bundle, wires them.
function loadAPP()
    if APP then return APP end
    local UI = require("euclid_ui")
    CTL = UI.screen
    APP = require("euclid_vsn1").init(CTL)
    return APP
end


-- =============================================================================
-- [2] MIDI RX  (external clock + transport)
-- =============================================================================
-- Pure-playback path: NEVER loads UI. The realtime callback receives the
-- status byte directly (NOT a table). We decode the four transport bytes
-- inline and forward emitted note events to midi_send.
--   0xF8 clock tick     -> ENGINE.onPulse()  (zero-alloc hot path)
--   0xFA start          -> ENGINE.onStart()
--   0xFB continue       -> ENGINE.onStart()  if not already running
--   0xFC stop           -> ENGINE.onStop()   (flush note-offs)
--
-- ENGINE event shape: {type=1|2, pitch, vel, ch}. type 1 = NOTE_ON, 2 = NOTE_OFF.
-- Mark the controls dirty on every pulse so the playhead pip animates.

local function emitEvents(ev)
    if not ev then return end
    for i = 1, #ev do
        local e = ev[i]
        if e.type == 1 then
            midi_send(e.ch, 0x90, e.pitch, e.vel)
        else
            midi_send(e.ch, 0x80, e.pitch, 0)
        end
    end
end

self.rtmrx_cb = function(self, t)
    if t == 0xF8 then
        emitEvents(ENGINE.onPulse())
    elseif t == 0xFA then
        ENGINE.onStart()
    elseif t == 0xFB then
        if not ENGINE.running then ENGINE.onStart() end
    elseif t == 0xFC then
        emitEvents(ENGINE.onStop())
    end
end


-- =============================================================================
-- [3] SCREEN DRAW
-- =============================================================================

loadAPP().draw(self)


-- =============================================================================
-- [4] KEYSWITCHES  (element_index 0..7  ->  idx 1..8)
-- =============================================================================

loadAPP().onKey(self:element_index() + 1, self:button_state() == 127)


-- =============================================================================
-- [5] ENDLESS TURN
-- =============================================================================

local v = self:endless_value()
if v == 65 then loadAPP().onTurn(1) elseif v == 63 then loadAPP().onTurn(-1) end


-- =============================================================================
-- [6] ENDLESS CLICK
-- =============================================================================

if self:button_state() == 127 then loadAPP().onClick() end


-- =============================================================================
-- [7] SMALL BUTTONS  (element_index 9..12  ->  sidx 1..4) -> select track
-- =============================================================================

if self:button_state() == 127 then loadAPP().onSmallBtn(self:element_index() - 8) end


-- =============================================================================
-- NOTES
-- * No internal clock. All timing comes from MIDI 0xF8 ticks.
-- * Polyrhythm = per-track `steps` + per-track `ppstep`.
-- * Zero allocations per pulse (locked by tests/euclidean/test_no_alloc.lua).
-- * Rebuild after src/ changes:  lua tools/build_dist.lua
-- =============================================================================
