-- sequencer/midi_translate.lua
-- Converts a stream of (cvA, cvB, gate) samples into NOTE_ON / NOTE_OFF events.
--
-- The engine produces (cvA=pitch, cvB=velocity, gate=bool) per pulse. This
-- module owns the per-track edge-detection state needed to decide when to
-- emit MIDI:
--
--   * gate rising edge (false → true): emit NOTE_ON  cvA cvB
--   * gate falling edge (true → false): emit NOTE_OFF lastPitch
--   * pitch change while gate stays HIGH: emit NOTE_OFF lastPitch
--                                          then NOTE_ON cvA cvB (retrigger)
--   * gate stays LOW: nothing
--   * gate stays HIGH at same pitch: nothing
--
-- State is per-track (one struct per track). The host owns the table and
-- passes it back in on every call. `emit` is a callback with the signature
--   emit(kind, pitch, velocityOrNil, channel)
-- where `kind` is "NOTE_ON" or "NOTE_OFF". velocity is nil for NOTE_OFF.

local MidiTranslate = {}

-- Returns a fresh per-track state struct.
function MidiTranslate.new()
    return {
        prevGate  = false,
        lastPitch = nil,
    }
end

-- Processes one pulse of (cvA, cvB, gate) for a single track and emits any
-- resulting MIDI events via the `emit` callback.
--
-- cvA      : pitch (MIDI note number)
-- cvB      : velocity
-- gate     : boolean
-- channel  : MIDI channel (1-based)
-- emit     : function(kind, pitch, velocity, channel)
function MidiTranslate.step(state, cvA, cvB, gate, channel, emit)
    local prevGate  = state.prevGate
    local lastPitch = state.lastPitch

    if gate then
        if not prevGate then
            -- Rising edge: NOTE_ON.
            emit("NOTE_ON", cvA, cvB, channel)
            state.lastPitch = cvA
        elseif lastPitch ~= cvA then
            -- Pitch changed mid-gate: retrigger.
            emit("NOTE_OFF", lastPitch, nil, channel)
            emit("NOTE_ON",  cvA, cvB, channel)
            state.lastPitch = cvA
        end
    else
        if prevGate then
            -- Falling edge: NOTE_OFF the pitch that was held.
            emit("NOTE_OFF", lastPitch, nil, channel)
            state.lastPitch = nil
        end
    end

    state.prevGate = gate
end

-- Forces a NOTE_OFF if a note is currently held. Used on stop / panic.
function MidiTranslate.panic(state, channel, emit)
    if state.prevGate and state.lastPitch ~= nil then
        emit("NOTE_OFF", state.lastPitch, nil, channel)
    end
    state.prevGate  = false
    state.lastPitch = nil
end

return MidiTranslate
