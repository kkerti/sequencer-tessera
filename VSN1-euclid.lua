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
-- Pure-playback path never loads UI/VSN1 bundles. Each `require` stays
-- well within the module watchdog budget.
--
-- All real handler logic lives in src/euclidean/vsn1_app.lua (bundled
-- into dist/euclid_vsn1.lua). Each per-event scriptlet here is a thin
-- one-line dispatch into APP.
--
-- ---------------------------------------------------------------------------
-- CLOCK MODE  (decided at config time; affects which blocks you paste)
-- ---------------------------------------------------------------------------
--   "external"  pulses + transport from MIDI rx (0xF8 / 0xFA / 0xFC).
--               BPM unknown to the module.
--               Paste: [1 INIT-EXTERNAL] + [2 MIDI RX] + [3]..[7].
--               Skip:  [1 INIT-INTERNAL] + [2b TIMER].
--
--   "internal"  pulses + transport from a Grid element_timer event bound
--               to keyswitch element 0 (TIMER_ELEMENT below). BPM editable
--               via keyswitch 6, transport toggle via keyswitch 7.
--               Paste: [1 INIT-INTERNAL] + [2b TIMER] + [3]..[7].
--               Skip:  [1 INIT-EXTERNAL] + [2 MIDI RX].
--
-- Element 0 (the first keyswitch) hosts the timer in internal mode. Any
-- element will do; element 0 is conventional and free of input collisions
-- (its button event still works — keyswitch + timer are independent
-- scriptlets on the same element).
-- =============================================================================

CLOCK_MODE     = "internal"          -- "internal" | "external"
TIMER_ELEMENT  = 0                   -- only used in internal mode
BPM_DEFAULT    = 120                 -- only used in internal mode

-- Hardware mapping (current spec):
--   Screen     : 320x240 concentric rings + right-column PARAMS.
--   Keyswitch  : 1=STEPS 2=PULSES 3=ROTATE 4=RATE 5=PITCH
--                6=BPM (internal only) 7=PLAY/STOP (internal only) 8=SHIFT.
--   4 small btns: select track 1..4.
--   Endless    : turn = act-per-mode; click = mute toggle on selected track.
--                Shift + turn coarsens PITCH by x12, BPM by x10.

-- =============================================================================
-- [1 INIT-EXTERNAL]  (MIDI clock)   PASTE in module init when CLOCK_MODE="external"
-- =============================================================================
-- The init block below covers BOTH modes — paste this entire block once
-- in the module init scriptlet. It branches on CLOCK_MODE at runtime.

EUC    = require("euclid")
ENGINE = EUC.Core.engine
TRACK  = EUC.Core.track
APP    = nil
CTL    = nil
TIMER_MS = 0                          -- current timer interval (internal only)

ENGINE.init({ trackCount = 4 })

-- Four tracks with recognisable euclidean defaults so something audible
-- happens immediately when the clock starts. Channels 0..3.
--   T1 E(3,8)   tresillo         on C4   ch 0
--   T2 E(5,8)   cinquillo        on D#4  ch 1
--   T3 E(4,16)  four-on-floor    on G4   ch 2
--   T4 E(7,12)  7-against-12     on A#4  ch 3
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
    APP.setClockMode(CLOCK_MODE)

    if CLOCK_MODE == "internal" then
        -- BPM-change callback: APP fires this when the user edits BPM
        -- via the encoder. We recompute the timer interval and re-arm
        -- it. The next timer firing will pick up the new rate.
        APP.setBpmCallback(function(ms)
            TIMER_MS = ms
            element_timer_start(TIMER_ELEMENT, ms)
        end)
        -- Transport callback: APP fires true on play, false on stop.
        APP.setTransportCallback(function(playing)
            if playing then
                element_timer_start(TIMER_ELEMENT, TIMER_MS)
            else
                element_timer_stop(TIMER_ELEMENT)
            end
        end)
        -- Seed TIMER_MS directly. APP's M.bpm default already matches
        -- BPM_DEFAULT (120), so calling APP.setBpm(BPM_DEFAULT) would
        -- early-return without firing the callback. Compute it here so
        -- the value is live before the first timer fires / first toggle.
        TIMER_MS = APP._bpmToMs(BPM_DEFAULT)
        -- Auto-start: kick off the engine + timer immediately so the
        -- module makes sound on power-up. User can stop via key 7.
        APP.toggleTransport()
    end
    return APP
end


-- =============================================================================
-- [2 MIDI RX]  PASTE into module rtmidi event   ONLY if CLOCK_MODE="external"
-- =============================================================================
-- Pure-playback path: never loads UI. The realtime callback receives the
-- status byte directly (NOT a table). We decode the four transport bytes
-- inline and forward emitted note events to midi_send.
--   0xF8 clock tick     -> ENGINE.onPulse()  (zero-alloc hot path)
--   0xFA start          -> ENGINE.onStart()
--   0xFB continue       -> ENGINE.onStart()  if not already running
--   0xFC stop           -> ENGINE.onStop()   (flush note-offs)

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
-- [2b TIMER]  PASTE into element 0 timer event   ONLY if CLOCK_MODE="internal"
-- =============================================================================
-- Drives the engine when there's no external MIDI clock. One pulse per
-- timer firing. Re-arms the timer at the end so it loops at TIMER_MS.
-- TIMER_MS is set by APP.setBpmCallback (called from setBpm/init).
--
-- Engine + emitEvents are identical to external mode; only the trigger
-- source differs. Note: rtmrx_cb above is harmless when MIDI clock isn't
-- present, but for paste hygiene only paste ONE of [2] or [2b].

emitEvents(ENGINE.onPulse())
element_timer_start(self:element_index(), TIMER_MS)


-- =============================================================================
-- [3] SCREEN DRAW                   PASTE into screen draw event (always)
-- =============================================================================

loadAPP().draw(self)


-- =============================================================================
-- [4] KEYSWITCHES  (element_index 0..7  ->  idx 1..8)   PASTE into button event
-- =============================================================================

loadAPP().onKey(self:element_index() + 1, self:button_state() == 127)


-- =============================================================================
-- [5] ENDLESS TURN                  PASTE into endless turn event
-- =============================================================================

local d = self:endless_value() - 64
if d ~= 0 then loadAPP().onTurn(d) end


-- =============================================================================
-- [6] ENDLESS CLICK                 PASTE into endless button event
-- =============================================================================

if self:button_state() == 127 then loadAPP().onClick() end


-- =============================================================================
-- [7] SMALL BUTTONS  (element_index 9..12 -> sidx 1..4)  PASTE into button event
-- =============================================================================

if self:button_state() == 127 then loadAPP().onSmallBtn(self:element_index() - 8) end


-- =============================================================================
-- NOTES
-- * Two clock modes: internal (Grid element_timer) or external (MIDI 0xF8).
--   Selected by CLOCK_MODE constant at top of file. Paste blocks accordingly.
-- * Polyrhythm = per-track `steps` + per-track `ppstep` (RATE ladder).
-- * Zero allocations per pulse (locked by tests/euclidean/test_no_alloc.lua).
-- * Rebuild after src/ changes:  lua tools/build_dist.lua
-- =============================================================================
