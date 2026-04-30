-- tui.lua
-- Text UI renderer for sequencer state snapshots.
-- Output is append-only plain text for easy log parsing.

local Seq   = require("sequencer")
require("authoring")           -- extend Step/Track with editor/read methods
local Step  = Seq.Step
local Track = Seq.Track
local Utils = Seq.Utils

local Tui   = {}

local function tuiPadRight(value, width)
    local s = tostring(value)
    if #s >= width then
        return s
    end
    return s .. string.rep(" ", width - #s)
end

local function tuiStepCell(step, isActive)
    local base

    if Step.getDuration(step) == 0 then
        base = "SKIP"
    else
        local noteName = Utils.pitchToName(Step.getPitch(step))
        if Step.getGate(step) == 0 then
            base = noteName .. "."
        else
            local dashCount = Step.getDuration(step)
            if dashCount < 1 then
                dashCount = 1
            end
            if dashCount > 4 then
                dashCount = 4
            end
            base = noteName .. string.rep("-", dashCount)
        end
    end

    base = tuiPadRight(base, 7)
    if isActive then
        return "*" .. base
    end
    return " " .. base
end

local function tuiLoopText(track)
    local loopStart = Track.getLoopStart(track)
    local loopEnd = Track.getLoopEnd(track)
    if loopStart == nil and loopEnd == nil then
        return "none"
    end
    return "[" .. tostring(loopStart or "-") .. ".." .. tostring(loopEnd or "-") .. "]"
end

local function tuiEventToText(event)
    local text = event.type .. " " .. Utils.pitchToName(event.pitch)
    if event.type == "NOTE_ON" then
        text = text .. " v" .. tostring(event.velocity)
    end
    return text
end

local function tuiBuildEventLines(events, trackCount)
    local eventsByTrack = {}
    for trackIndex = 1, trackCount do
        eventsByTrack[trackIndex] = {}
    end

    for i = 1, #events do
        local event = events[i]
        local channel = event.channel
        if channel >= 1 and channel <= trackCount then
            local arr = eventsByTrack[channel]
            arr[#arr + 1] = tuiEventToText(event)
        end
    end

    local lines = {}
    lines[#lines + 1] = "EVENTS total:" .. tostring(#events)

    for trackIndex = 1, trackCount do
        local arr = eventsByTrack[trackIndex]
        if #arr == 0 then
            lines[#lines + 1] = "EVT TRK " .. trackIndex .. " -"
        else
            lines[#lines + 1] = "EVT TRK " .. trackIndex .. " " .. table.concat(arr, " | ")
        end
    end

    return lines
end

function Tui.render(engine, pulseCount, events)
    assert(type(engine) == "table", "tuiRender: engine must be a table")
    assert(type(pulseCount) == "number" and pulseCount >= 0, "tuiRender: pulseCount must be non-negative")
    if events == nil then
        events = {}
    end
    assert(type(events) == "table", "tuiRender: events must be a table")

    local beat = math.floor(pulseCount / engine.pulsesPerBeat)
    local lines = {}

    lines[#lines + 1] = "[BEAT:" .. beat .. " PULSE:" .. pulseCount .. " BPM:" .. engine.bpm .. " PPB:" ..
        engine.pulsesPerBeat .. "]"

    local eventLines = tuiBuildEventLines(events, engine.trackCount)
    for i = 1, #eventLines do
        lines[#lines + 1] = eventLines[i]
    end

    for trackIndex = 1, engine.trackCount do
        local track = engine.tracks[trackIndex]
        local midiChannel = Track.getMidiChannel(track) or trackIndex

        lines[#lines + 1] = "TRK " .. trackIndex ..
            " ch:" .. midiChannel ..
            " div:" .. Track.getClockDiv(track) ..
            " mult:" .. Track.getClockMult(track) ..
            " dir:" .. Track.getDirection(track) ..
            " loop:" .. tuiLoopText(track) ..
            " cursor:" .. track.cursor ..
            " steps:" .. Track.getStepCount(track)

        local patternCount = Track.getPatternCount(track)
        for patternIndex = 1, patternCount do
            local patStart = Track.patternStartIndex(track, patternIndex)
            local patEnd = Track.patternEndIndex(track, patternIndex)

            local row = "PAT " .. patternIndex .. " [" .. patStart .. "-" .. patEnd .. "]"
            for flatIndex = patStart, patEnd do
                local step = Track.getStep(track, flatIndex)
                local isActive = (track.cursor == flatIndex)
                row = row .. " " .. tuiStepCell(step, isActive)
            end

            lines[#lines + 1] = row
        end

        if patternCount == 0 then
            lines[#lines + 1] = "PAT - [empty]"
        end
    end

    return table.concat(lines, "\n")
end

function Tui.renderTickTrace(engine, pulseCount, events)
    if events == nil then
        events = {}
    end

    local cursors = {}
    for trackIndex = 1, engine.trackCount do
        local track = engine.tracks[trackIndex]
        cursors[#cursors + 1] = "T" .. trackIndex .. "@" .. track.cursor .. "/p" .. track.pulseCounter
    end

    local eventTokens = {}
    for i = 1, #events do
        eventTokens[#eventTokens + 1] =
            "T" .. events[i].channel .. ":" .. events[i].type .. ":" .. Utils.pitchToName(events[i].pitch)
    end

    local eventsPart = "-"
    if #eventTokens > 0 then
        eventsPart = table.concat(eventTokens, ",")
    end

    return "[TICK pulse:" .. pulseCount .. "] " .. table.concat(cursors, " ") .. " evt:" .. eventsPart
end

return Tui
