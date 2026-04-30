# 2026-04-14 Memory Profiling & Grid Constraints

> **PARTIALLY SUPERSEDED (2026-04-27).** The memory-budget analysis in this note is still relevant. The 880-char per-file deployment-tooling references are obsolete — that limit no longer applies and `tools/gridsplit.lua` has been removed. See `docs/ARCHITECTURE.md` for the current pipeline.


## Context

Grid runs on an ESP32 with limited RAM. The sequencer engine must fit comfortably within a **100 KB runtime memory budget** (engine data only, excluding the Lua VM and module code overhead). Today we built tooling to measure and validate this.

## What was done

### Memory profiler (`tools/memprofile.lua`)

Built a dedicated memory profiler that measures `collectgarbage("count")` at each lifecycle phase:

1. Bare Lua VM baseline (~29.6 KB)
2. After requiring all 10 modules (~139.4 KB total, ~109.8 KB module overhead)
3. After `Engine.new` (empty engine)
4. After scenario build (engine populated with tracks/patterns/steps)
5. Peak during tick loop (raw allocation sampled every 4 pulses, no forced GC — captures worst-case)
6. After full run + GC (steady-state)

The profiler runs against all 11 test scenarios in `tests/sequences/` and reports per-step memory cost in bytes, estimated max step count within budget, and over/under budget status.

### Results (heaviest scenario: `11_four_track_dark_polyrhythm`)

| Metric | Value |
|---|---|
| Tracks | 4 |
| Steps | 30 |
| Pulses run | 128 |
| Engine data cost | 10.9 KB |
| Peak engine-only | 78.5 KB (78% of budget) |
| Steady-state after GC | 17.3 KB |
| Per-step cost | ~373 bytes |
| Estimated max steps in 100 KB | ~274 |
| Headroom | 21.5 KB |

### Results (lightest scenario: `01_basic_patterns`)

| Metric | Value |
|---|---|
| Tracks | 1 |
| Steps | 8 |
| Peak engine-only | 17.8 KB (18% of budget) |
| Per-step cost | ~446 bytes |
| Headroom | 82.2 KB |

### Key observations

- **Peak vs steady-state gap is large.** The 4-track polyrhythm scenario peaks at 78.5 KB during playback but settles to 17.3 KB after GC. The peak comes from transient event tables and string keys created during `Engine.tick`. This is the main area to watch.
- **Per-step cost is ~370-450 bytes.** Each step is a Lua table with 7 fields (pitch, velocity, duration, gate, ratchet, probability, active). At this cost, the 2000-step pool limit from the data model would require ~730-890 KB — well over budget. In practice, no scenario comes close to 2000 steps.
- **Module code overhead is ~110 KB.** This is the cost of loading all 10 `require`d modules. On Grid, the 880-char split files will have different loading characteristics — this needs measurement on device.
- **No explicit GC tuning in the engine.** The engine does not call `collectgarbage` anywhere. Lua's incremental GC handles cleanup. Whether the default GC pacer is adequate on ESP32 under real-time timer pressure is an open question.

## Deployment size tooling (related)

Separately, `tools/gridsplit.lua` and `tools/charcheck.lua` handle the **880-character-per-script-file** deployment constraint. This is a Grid firmware limit on script storage, not a runtime memory concern, but it is part of the same "constrained platform" picture. See `docs/2026-04-14-grid-880-deployment-tooling.md` for details.

## Engine refactoring done today

The `Engine.tick` function was split into smaller sub-functions (`engineHandleNoteOn`, `engineHandleNoteOff`, `engineProcessTrackEvent`, `engineTickSceneChain`) to improve readability and to help the grid splitter fit functions within the 880-char limit. This refactoring is also beneficial for memory: smaller functions mean smaller closures and more granular GC eligibility for temporaries.

## Open questions for next session

1. **Tick allocation pressure.** Each `Engine.tick` call creates a fresh `events` table and string keys (`"pitch:channel"`) for `activeNotes`. On ESP32 at 120 BPM / 4 ppb, that is ~8 allocations per second. Is this enough to trigger GC pauses audible as timing jitter? Consider pre-allocating an event buffer and reusing it.
2. **GC tuning on device.** Lua 5.4 supports `collectgarbage("incremental", pause, stepmul, stepsize)`. We may need to tune these on ESP32 to avoid stop-the-world pauses during playback. Profile on real hardware.
3. **Module loading cost on Grid.** The 110 KB module overhead measured on macOS Lua 5.5 may differ on Grid's Lua 5.4 VM with the 880-char split files. Measure on the WASM simulator or on device.
4. **Step pool budget.** The data model allows 2000 steps but the memory budget supports ~274 at peak. Either lower the documented limit or accept that the 2000 figure is a theoretical cap that will never be hit on ESP32.
5. **Event table reuse.** Instead of `events = {}` on every tick, pass a reusable buffer and clear it with a length counter. Avoids a table allocation per tick.
