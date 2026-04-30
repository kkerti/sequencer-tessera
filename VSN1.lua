-- VSN1.lua
-- =============================================================================
-- ON-DEVICE ENTRY POINT for the VSN1 module of the sequencer.
-- The sequencer engine + UI lives on the VSN1. This is its consumer manifest.
-- =============================================================================
--
-- Two-bundle layout (memory-conscious, IoT-style):
--   dist/sequencer.lua     -- Core only. Loaded at module init. ~10 KB.
--   dist/sequencer_ui.lua  -- Controls layer. Lazy-loaded on first input
--                             event or first screen draw. ~8 KB.
--
-- Pure-playback paths (master clock running, no user input, screen disabled)
-- never pay the UI heap cost. Boot stays under the Grid memory ceiling.
--
-- Build:    lua tools/build_dist.lua    -> both bundles into dist/
-- Upload:   both files to the VSN1 module's filesystem.
--
-- Hardware mapping (per docs/LIB-2-HW-MAP.md and AGENTS.md):
--   Screen        : 320 x 240
--                     top half (y=0..119)   = 4x2 parameter cells
--                     bottom half (y=120..) = 4 per-track region strips
--   4 small btns  : queue region 1..4 (global switch at end-of-region)
--   8 keyswitches : select which parameter the endless edits (cells 1..8)
--   Endless       : relative; 65 = up, 63 = down. Click toggles `active`.
--
-- The EN16 module (separate hardware, separate file: EN16.lua at repo root)
-- talks to this engine remotely via immediate_send. EN16's input messages
-- also trigger UI lazy-load on VSN1 (since they call vsn1_en16_turn/press
-- which require the Controls layer to be resident).
-- =============================================================================


-- =============================================================================
-- [1] MODULE INIT EVENT
-- -----------------------------------------------------------------------------
-- Loads the Core bundle ONLY. Controls layer is deferred to keep boot heap
-- minimal. UI globals (CTL, EN16) start nil; loadUI() populates them on
-- first need.
-- =============================================================================

SEQ     = require("sequencer")     -- Core bundle (dist/sequencer.lua)
ENGINE  = SEQ.Core.engine
TRACK   = SEQ.Core.track
STEP    = SEQ.Core.step
CTL     = nil                      -- lazy: SEQ.Controls.screen after loadUI()
EN16    = nil                      -- lazy: SEQ.Controls.en16   after loadUI()

ENGINE.init({
    trackCount    = 4,
    stepsPerTrack = 64,
})

-- Default seed: a short C minor riff in track 1, region 1 (steps 1..16).
local notes = { 60, 63, 67, 70, 72, 67, 63, 60 }
for i, p in ipairs(notes) do
    ENGINE.tracks[1].steps[i] = STEP.pack({
        pitch = p, vel = 100, dur = 6, gate = 3,
    })
end
ENGINE.tracks[1].chan = 1

-- Lazy UI loader. Idempotent. Called by every event chunk that touches CTL
-- or EN16. After first call, SEQ.Controls is populated and subsequent calls
-- return immediately.
--
-- Note: the vsn1_en16_turn / vsn1_en16_press globals are NOT defined here.
-- The require("sequencer_ui") call alone consumes most of the available
-- heap budget for the tick. Defining additional global closures in the
-- same event chunk has been observed to OOM. They are self-defined inside
-- their own event chunks (section [8]) on first call.
function loadUI()
    if CTL then return end
    local UI = require("sequencer_ui")
    SEQ.Controls = UI            -- promote into the namespace for inspection
    CTL  = UI.screen
    EN16 = UI.en16
    CTL.dirtyAll()
end


-- =============================================================================
-- [2] MIDI RX  (clock + transport from Ableton or other master)
-- -----------------------------------------------------------------------------
-- Place this in the module's MIDI Rx event. Pure Core path: NEVER touches
-- UI. Pure-playback users never trigger loadUI().
--
--     0xF8  CLOCK    -> advance engine one pulse, ship its events out
--     0xFA  START    -> reset transport, start playing
--     0xFB  CONTINUE -> resume without reset
--     0xFC  STOP     -> stop, flush any held notes
-- =============================================================================

self.rtmrx_cb = function(self, t)
    if t == 0xF8 then
        local events = ENGINE.onPulse()
        if events then
            for i = 1, #events do
                local e = events[i]
                if e.type == 1 then
                    midi_send(e.ch, 0x90, e.pitch, e.vel)
                else
                    midi_send(e.ch, 0x80, e.pitch, 0)
                end
            end
        end
    elseif t == 0xFA then
        ENGINE.onStart()
    elseif t == 0xFB then
        if not ENGINE.running then ENGINE.onStart() end
    elseif t == 0xFC then
        local off = ENGINE.onStop()
        if off then
            for i = 1, #off do
                local e = off[i]
                midi_send(e.ch, 0x80, e.pitch, 0)
            end
        end
    end
end


-- =============================================================================
-- [3] SCREEN DRAW EVENT
-- -----------------------------------------------------------------------------
-- First draw triggers UI lazy-load. Subsequent draws are surgical updates
-- only. EN16 LED updates piggyback on this tick, cache-gated so idle
-- frames send no immediate_send messages.
-- =============================================================================

if not CTL then loadUI() end
CTL.draw(self)

if not EN16_LED_CACHE then
    EN16_LED_CACHE = {}
    for i = 1, 16 do EN16_LED_CACHE[i] = -1 end
end
EN16.refreshLeds(function(idx, b)
    if EN16_LED_CACHE[idx] == b then return end
    EN16_LED_CACHE[idx] = b
    immediate_send(0, 1,
        "led_value(" .. (idx - 1) .. ",2," .. b .. ")")
end)


-- =============================================================================
-- [4] KEYSWITCH BUTTON EVENTS  (8 buttons -> select parameter)
-- -----------------------------------------------------------------------------
-- Cell layout (from src/controls.lua):
--     1 TRACK   2 STEP    3 NOTE   4 VEL
--     5 DUR     6 GATE    7 RATCH  8 PROB
-- =============================================================================

if self:button_state() == 127 then
    if not CTL then loadUI() end
    local idx = self:element_index() + 1
    if idx >= 1 and idx <= 8 then CTL.onKey(idx) end
end


-- =============================================================================
-- [5] ENDLESS ENCODER EVENT
-- -----------------------------------------------------------------------------
-- Relative encoder. 65 = clockwise/up, 63 = counter-clockwise/down.
-- =============================================================================

if not CTL then loadUI() end
local v = self:encoder_value()
if v == 65 then
    CTL.onEndless(1)
elseif v == 63 then
    CTL.onEndless(-1)
end


-- =============================================================================
-- [6] ENDLESS CLICK EVENT  -> toggle focused step's `active` bit
-- -----------------------------------------------------------------------------
-- The cell display does not currently show `active` state, so toggling
-- has no on-screen effect. It is audible (silenced steps emit nothing).
-- =============================================================================

if self:button_state() == 127 then
    if not CTL then loadUI() end
    local cur = STEP.active(ENGINE.tracks[CTL.selT].steps[CTL.selS]) and 1 or 0
    ENGINE.setStepParam(CTL.selT, CTL.selS, "active", 1 - cur)
end


-- =============================================================================
-- [7] SMALL BUTTONS UNDER SCREEN  (4 buttons -> queue region 1..4)
-- -----------------------------------------------------------------------------
-- Pressing the button for the active region cancels any pending queue.
-- The queued-region pip on each row blinks until the engine completes the
-- flip (all tracks reaching their region boundary).
-- =============================================================================

if self:button_state() == 127 then
    if not CTL then loadUI() end
    local idx = self:element_index() + 1
    if idx >= 1 and idx <= 4 then CTL.onSmallBtn(idx) end
end


-- =============================================================================
-- [8] CROSS-MODULE COMMUNICATION  (VSN1 [0,0]  <->  EN16 [0,1])
-- -----------------------------------------------------------------------------
-- Outbound (VSN1 -> EN16): in [3], one immediate_send per CHANGED encoder
-- LED, payload `led_value(idx, 2, brightness)`. Cache-gated.
--
-- Inbound (EN16 -> VSN1): EN16 sends
--   immediate_send(0, -1, 'vsn1_en16_turn(' .. idx .. ',' .. delta .. ')')
--   immediate_send(0, -1, 'vsn1_en16_press(' .. idx .. ')')
--
-- These globals self-define on first invocation. They are NOT defined in
-- loadUI() because that event chunk already consumes most of the available
-- heap budget pulling in the UI bundle; adding two more closure
-- allocations to the same tick has been observed to OOM. The trade-off:
-- the very first EN16 turn or press only registers the global and is
-- otherwise lost; the second message onward works normally.
--
-- Place the following two snippets in two separate Lua-string-receiver
-- event chunks on VSN1 (or rely on the receiver being the global Lua
-- environment that immediate_send executes against).
--
-- Snippet A: turn receiver
function vsn1_en16_turn(idx, delta)
    if not EN16 then loadUI() end
    if EN16 then EN16.onEncoder(idx, delta) end
end

-- Snippet B: press receiver
function vsn1_en16_press(idx)
    if not EN16 then loadUI() end
    if EN16 then EN16.onEncoderPress(idx) end
end


-- =============================================================================
-- NOTES
-- -----------------------------------------------------------------------------
-- * Two-bundle split keeps boot heap small. UI loads on first user input
--   or first screen draw — typically within the first second of use, but
--   never during a pure-playback boot sequence.
-- * No internal clock. If the master is stopped, engine emits nothing.
-- * Region model: 4 fixed 16-step windows of each track's 64-step buffer.
--   Global at-end-of-region switching coordinated by the engine.
-- * One voice per track. Track-N notes default to MIDI channel N.
-- * Zero allocations per pulse — locked by tests/test_no_alloc.lua.
-- * Rebuild after src/ changes:  lua tools/build_dist.lua
-- =============================================================================
