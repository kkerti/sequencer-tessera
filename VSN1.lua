-- VSN1.lua
-- =============================================================================
-- ON-DEVICE ENTRY POINT for the VSN1 module of the sequencer.
-- =============================================================================
--
-- Lazy-load chain:
--   [1]  init           -> require("sequencer")        (Core, ~7 KB)
--   first user input    -> require("sequencer_ui")     (screen, ~6 KB)
--                          require("sequencer_vsn1")   (handlers, ~3 KB)
--
-- Pure-playback path (MIDI rx only, never any input) never loads the
-- UI/VSN1 bundles. This keeps boot light and respects the module
-- watchdog: each individual `require` is small enough not to trip it.
--
-- All real handler logic lives in src/vsn1_app.lua (bundled into
-- dist/sequencer_vsn1.lua). Each per-event scriptlet here is just a
-- thin call into APP. Library bundles have no per-scriptlet size limit;
-- only this file's sections do, but staying thin keeps copy-paste sane.
--
-- Hardware mapping:
--   Screen     : 320x240 EDIT view (greyscale + mute red).
--   Keyswitch  : 1=NOTE 2=VEL 3=GATE 4=MUTE 5=LASTSTEP
--                7=LOAD (SHIFT+7=SAVE)  8=SHIFT (toggle; LED = full-bright orange).
--   4 small btns: viewport (no shift) / track select (+ shift).
--   Endless    : turn = act-per-mode; click = mute toggle on selected step.
--                In GATE focus, SHIFT + turn edits dur (snaps ladder).
--                Shift + turn coarsens NOTE/VEL/GATE by x12.
--
-- EN16 satellite (optional, dx=+1, dy=0):
--   VSN1 -> EN16   "EN16.U(mu,f,sel,cap,v1..v16);paint()"
--                  "EN16.H(slot);paint()"
--   EN16 -> VSN1   "vsn1_t(i,d)"  /  "vsn1_p(i)"
-- =============================================================================


-- =============================================================================
-- [1] MODULE INIT  (Core only; UI is lazy)
-- =============================================================================

SEQ    = require("sequencer")
ENGINE = SEQ.Core.engine
STEP   = SEQ.Core.step
MIDIRX = SEQ.Core.midi_rx
PERSIST = SEQ.Core.persist
APP    = nil
CTL    = nil

ENGINE.init({ trackCount = 4, stepsPerTrack = 64 })

-- Autoload saved sequence from disk. Path lives in vsn1_app.SAVE_PATH but
-- we hardcode the same string here to avoid pulling in the VSN1 bundle on
-- the pure-playback path. If load succeeds, skip the hardcoded seed motif.
if not PERSIST.load("sequencer_data.lua") then
    -- Seed track 1 motif (fallback so the engine has content even if no
    -- save file exists yet and the UI never loads).
    local notes = { 60, 63, 67, 70, 72, 67, 63, 60 }
    for i, p in ipairs(notes) do
        ENGINE.tracks[1].steps[i] = STEP.pack({ pitch = p, vel = 100, dur = 6, gate = 3 })
    end
end

-- Lazy loader. Called from every input scriptlet and the first screen
-- draw. Loads the screen UI bundle, the VSN1 handler bundle, wires them.
function loadAPP()
    if APP then return APP end
    local UI = require("sequencer_ui")
    CTL = UI.screen
    APP = require("sequencer_vsn1").init(CTL)
    return APP
end

-- Boot seed for EN16: clear playhead. Full state push happens once UI loads.
immediate_send(1, 0, "EN16.H(0);paint()")

-- Cross-module receivers (EN16 -> VSN1). Defined as globals at init so
-- the EN16 module can target them by name.
function vsn1_t(i, d) loadAPP().fromEN16Turn(i, d) end
function vsn1_p(i)    loadAPP().fromEN16Press(i)   end


-- =============================================================================
-- [2] MIDI RX  (external clock + transport)
-- =============================================================================
-- Pure-playback path: NEVER loads UI. Engine + MIDI live in Core.
-- EN16 playhead push only happens once APP is loaded (post first input).

self.rtmrx_cb = function(self, t)
    local r = MIDIRX.handle(t, midi_send)
    if r == "tick" then
        if APP then APP.pushPlayhead() end
    elseif r == "start" then
        if APP then APP.lastPh = -1 end
    elseif r == "stop" then
        if APP then APP.lastPh = 0 end
        immediate_send(1, 0, "EN16.H(0);paint()")
    end
end


-- =============================================================================
-- [3] SCREEN DRAW
-- =============================================================================

loadAPP()
CTL.draw(self)


-- =============================================================================
-- [4] KEYSWITCHES  (element_index 0..7  ->  idx 1..8)
-- =============================================================================

loadAPP().onKey(self:element_index() + 1, self:button_state() == 127)

-- SHIFT LED (element 7 = keyswitch 8): full-bright orange while the toggle
-- is active, off otherwise. onKey flips CTL.shift on the press edge, so by
-- the time this runs the state already reflects the new value.
if self:element_index() == 7 then
    if CTL.shift then
        led_color(7, 2, 255, 140, 20, 0)
    else
        led_color(7, 2, 0, 0, 0, 0)
    end
end


-- =============================================================================
-- [5] ENDLESS TURN
-- =============================================================================

local d = self:endless_value() - 64
if d ~= 0 then loadAPP().onTurn(d) end


-- =============================================================================
-- [6] ENDLESS CLICK
-- =============================================================================

if self:button_state() == 127 then loadAPP().onClick() end


-- =============================================================================
-- [7] SMALL BUTTONS  (element_index 9..12  ->  sidx 1..4)
-- =============================================================================

if self:button_state() == 127 then loadAPP().onSmallBtn(self:element_index() - 8) end


-- =============================================================================
-- [8] CROSS-MODULE RECEIVERS  (EN16 -> VSN1)
-- =============================================================================
-- vsn1_t / vsn1_p defined as globals in [1]. Nothing per-event here.


-- =============================================================================
-- NOTES
-- * No internal clock. Polyrhythm = per-track lastStep + per-step dur.
-- * Zero allocations per pulse.
-- * Rebuild after src/ changes:  lua tools/build_dist.lua
-- =============================================================================
