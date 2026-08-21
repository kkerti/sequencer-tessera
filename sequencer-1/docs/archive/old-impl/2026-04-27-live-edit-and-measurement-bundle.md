# 2026-04-27 — live/edit.lua + on-device measurement bundle

> **PARTIALLY SUPERSEDED (2026-04-27 later)** — The flat `grid/` bundle replaced
> per-folder layout (see `docs/2026-04-27-flat-grid-bundle.md`), and the
> `--rewrite-require` flag described below has since been removed from
> `tools/strip.lua` because the flat layout requires no path rewriting.
> Bundle and live-edit content otherwise still applies.

## Goal
Build the smallest possible on-device authoring path so we can validate "edit a song on Grid without rebooting" before committing to the full lite-engine route. Two parallel candidates are now bundled and ready to measure on hardware:

1. **`live/edit.lua`** (~6.6 KB stripped) — in-place editor on compiled song arrays.
2. **`sequencer_lite/`** (~17.8 KB stripped, was already built) — full Track/Pattern/Step authoring engine.

## What shipped

### `live/edit.lua` (NEW)
Direct mutation of a compiled song's parallel arrays. No engine model, no source-step abstraction.

- O(1) edits, safe at any pulse: `setPitch`, `setVelocity`, `mute`, `mutePair`, `unmute`, `unmutePair`.
- `findMate(song, eventIdx)` — scan for the matching NOTE_OFF/NOTE_ON pair when the writer sidecar `pairOff[]` is absent.
- `setRatchet(song, spec)` — splice operation: removes the current ratchet group, inserts the new one, rebuilds `pairOff[]`. Accepts spec table with **both** current and new geometry, since the compiled schema does not record source-step boundaries — the caller is the source of truth.
- `queueRatchetEdit(queue, spec)` + `applyQueue(song, queue)` — defer splice ops until the next loop boundary so the player's cursor isn't invalidated mid-loop.

Addressing model: **event-index-based, caller-tracks-groups** (decided this session). The caller passes `firstOnIdx`, `currentCount`, `currentSubPulses`, `currentGate`, `newCount`, `newSubPulses`, `newGate`. No per-event source-step ID is stored.

### `tests/live_edit.lua` (NEW)
11 checks covering O(1) edits, mate-finding, mute round-trip, player runtime pickup, ratchet up (1→4), ratchet down (4→1), pairOff consistency after splice, queue defer/apply, and middle-step ratchet edit preserving neighbours.

### `tools/strip.lua` — new flag
Added `--rewrite-require FROM=TO` (repeatable). Rewrites the literal string passed to `require(...)` calls inside the source. Used to convert macOS-style relative requires (`require("sequencer_lite/track")`) into Grid-style absolute paths (`require("/sequencer_lite/track")`) at build time, without maintaining two source copies.

### `grid/sequencer_lite/`, `grid/utils/`, `grid/live/` (NEW bundles)
Lite engine and live editor are now first-class members of the Grid upload bundle. Build commands:

```sh
mkdir -p grid/utils grid/sequencer_lite grid/live
lua tools/strip.lua utils.lua --out grid/utils/utils.lua
for f in step pattern track engine; do
  lua tools/strip.lua sequencer_lite/$f.lua \
    --rewrite-require "sequencer_lite/=/sequencer_lite/" \
    --rewrite-require "utils=/utils/utils" \
    --out grid/sequencer_lite/$f.lua
done
lua tools/strip.lua live/edit.lua --out grid/live/edit.lua
```

### `grid_module.lua` — restructured
Was a stub holding only the rtmidi callback. Now contains three labelled blocks: INIT (player + song), LITE-ENGINE MEASUREMENT HOOK (commented out), LIVE-EDIT MEASUREMENT HOOK (commented out), and the rtmidi callback. Each measurement hook is documented with the upload protocol for capturing RAM delta.

## On-device measurement protocol

Modules alone cost almost nothing on the heap once `package.loaded` caches them — the interesting numbers are the **live object graphs** an authoring session creates. Both hooks in `grid_module.lua` are now structured in tiers so each cost can be isolated.

### Baseline
Boot with both measurement hooks commented out. This is the player + compiled song only. Note free RAM as **B** (baseline).

### Live-edit hook (smaller, mutates compiled song in place)

| Tier | Config | Captures |
|---|---|---|
| A | `require("/live/edit")` + `Edit.newQueue()` | module load + empty queue |
| B | A + queue wired into `song.onLoopBoundary` | realistic in-use cost |

### Lite-engine hook (full authoring engine resident)

| Tier | Config | Captures |
|---|---|---|
| A | `require` of all 4 lite modules | module load only |
| B | A + `Engine.new()` (default 4 tracks × 1 pat × 8 steps = 32 steps) | minimal authoring graph |
| C | A + `Engine.new(120, 4, 4, 16)` populated (4 tracks × 16 steps = 64 steps) with scale set | realistic authoring graph |

Tier C represents what an actual on-device authoring session looks like: a few tracks, a couple of patterns each, a global scale. If C is comfortable on free RAM, on-device authoring is viable.

### Decision logic
- Live-edit B comfortable, lite-engine C tight → ship live-edit only, defer lite engine.
- Lite-engine C comfortable → use the full lite engine; live-edit becomes optional.
- Both tight → tier-3 trim list in `docs/dropped-features.md` is the next attack surface.

## Decisions
- **Caller tracks ratchet groups.** No per-event source-step ID added. Caller passes both old and new ratchet geometry to `setRatchet`. Keeps the compiled schema unchanged and shipping songs unenlarged.
- **Splice rebuilds `pairOff[]` from scratch** after each ratchet edit. O(N²) worst case but trivial for ~200-event songs and not on a per-pulse path.
- **Splice operations are queued, not immediate.** The player's cursor walks the parallel arrays linearly; mid-loop splices would shift indices under the cursor. Queue + drain at `onLoopBoundary` keeps the cursor invariant.
- **Build pipeline does the path rewrite.** Adding `--rewrite-require` to `tools/strip.lua` means the source files don't need two variants for macOS vs Grid.

## Status
- 14 unit suites + 11 sequence scenarios + new live_edit suite all pass.
- Grid bundle now includes `/player/`, `/utils/`, `/sequencer_lite/`, `/live/`, and 3 song folders. Ready to upload and measure.

## Next
- Upload bundle to Grid; capture RAM at all 4 configurations.
- Decide between live-edit-only, lite-engine, or both based on RAM headroom.
- (Deferred until measurement) Decide whether to drop scale + swing from the compiler to shrink the engine path.
