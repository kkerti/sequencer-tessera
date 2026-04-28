# Dropped features (sequencer_lite)

`sequencer_lite/` is the on-device carve of the authoring engine. It exists so a Grid module can author, edit, and re-compile songs in place — without paying the full ~60 KB resident cost of the macOS authoring engine.

The full engine (`sequencer/`) on macOS is unchanged. Anything dropped here can still be authored on macOS, compiled, and shipped to the device as a static song.

This document lists exactly what is dropped, why, and how to revive it if the on-device need arises later.

---

## Drop tier 1 — modules removed entirely

These modules are not loaded on device. Their features are macOS-authoring concerns; once a song is compiled, the device does not need them.

### `snapshot.lua` — full engine state serialization

- **What it did:** save/load the full live-engine state (all tracks, patterns, steps, loop points, clock, scene chain) to disk via `io`.
- **Why dropped:** the device receives precompiled songs. There is no live "engine state" to snapshot — the compiled song *is* the persistent state.
- **Revive when:** you want on-device "presets" that are richer than swapping which compiled song is loaded — e.g. live tweaks that should survive a power cycle without re-compiling.
- **Revival recipe:** copy `sequencer/snapshot.lua` into `sequencer_lite/`. No other changes needed; it depends only on `Track`, `Step`, `Pattern`, `Scene`, `Engine` (the last two would need to be present too if you want the full payload).

### `mathops.lua` — batch parameter mutation

- **What it did:** transpose / jitter / randomize step parameters across a track, pattern, or step range.
- **Why dropped:** these are authoring-time bulk operations. Live performance edits typically touch one step at a time; bulk mutation is rare in performance and easy to re-author + re-compile from macOS.
- **Revive when:** you want a "humanize" or "randomize all velocities" button on the device.
- **Revival recipe:** copy `sequencer/mathops.lua` into `sequencer_lite/`. Pure function over Step tables; no other dependencies inside the engine besides `Step`.

### `scene.lua` — automated loop-point sequencing

- **What it did:** scene chain that walks a list of saved loop-point configurations, switching them on beat boundaries.
- **Why dropped:** scenes are an authoring-time song-structure feature. The compiled song already encodes the final event sequence — there is nothing to sequence between.
- **Revive when:** you want to perform live arrangements where the human reorders sections on the fly without re-compiling.
- **Revival recipe:** (a) copy `sequencer/scene.lua` into `sequencer_lite/`; (b) restore the scene-chain block in `sequencer_lite/engine.lua` (search for "Scene chain" in `sequencer/engine.lua` for the original code); (c) wire `Engine.onPulse` to call `engineTickSceneChain`. Note that scene chains operate on the *authoring* engine, not on the compiled song the player walks — so you would also need to re-compile after every scene transition for the change to take audible effect, *or* extend the player to honour mid-song loop-point changes.

### `song_writer.lua` — non-destructive probability re-roll

- **What it did:** mutates the compiled song's `kind[]` array each loop boundary so probability re-evaluates per pass.
- **Why dropped:** the player owns this in-place. The lite engine does not need to bridge to it — if the device builds a song with probability, it produces the same `kind[]` schema and the player handles the re-roll.
- **Revive when:** never (lite engine compiles the song fresh each time; if probability is in a step, the compiled output already supports re-roll via the player).
- **Revival recipe:** N/A — already supported by the player.

---

## Drop tier 2 — features removed from carried-over modules

These features still exist in `sequencer/` on macOS. They were sliced out of `sequencer_lite/` because they're rarely used during live editing and add disproportionate code weight.

### `track.lua` — pattern manipulation

Removed from `sequencer_lite/track.lua`:

- `Track.copyPattern(track, srcIndex)`
- `Track.duplicatePattern(track, srcIndex)`
- `Track.insertPattern(track, patternIndex, stepCount)`
- `Track.deletePattern(track, patternIndex)`
- `Track.swapPatterns(track, indexA, indexB)`
- `Track.pastePattern(track, destIndex, srcPattern)`
- private helpers `trackRemovePatternFromArray`, `trackShiftLoopAfterDelete`, `trackAdjustLoopPointsAfterInsert`

**What still works:**

- `Track.addPattern` (append a new empty pattern) — still present.
- All step access (`getStep`, `setStep`, `getCurrentStep`).
- All loop-point setters/getters.
- All clock div/mult/channel setters.
- All 5 direction modes (forward, reverse, ping-pong, random, brownian).
- `Track.advance` and `Track.reset`.

**Why dropped:** pattern restructuring is an authoring activity. On device you will be editing existing steps inside an existing pattern layout, not slicing patterns around. Saved bytes by removing this group: ~6 KB raw source.

**Revive when:** you want on-device song-structure editing (rare for a live sequencer; more typical for a desktop DAW).

**Revival recipe:** copy the missing functions and their three private helpers from `sequencer/track.lua` into `sequencer_lite/track.lua`. They depend only on `Pattern`, `Step`, and `Utils.tableCopy` — all present in lite.

### `engine.lua` — scene chain hooks

Removed from `sequencer_lite/engine.lua`:

- `Engine.setSceneChain` / `getSceneChain` / `clearSceneChain`
- `Engine.activateSceneChain` / `deactivateSceneChain`
- private `engineTickSceneChain` helper
- `engine.sceneChain` field in `Engine.new`
- the scene-chain block in `Engine.reset`
- the `require("sequencer/scene")` import

**What still works:**

- `Engine.new`, `Engine.getTrack`, `Engine.bpmToMs`.
- Scale set/clear.
- `Engine.advanceTrack` and `Engine.onPulse` (both become trivial: `onPulse` is now a no-op).
- `Engine.reset`.

**Revive when:** you re-introduce `scene.lua` (see tier 1 above).

**Revival recipe:** copy the "Scene chain" block from `sequencer/engine.lua` (lines ~113–170 and ~199–209). Re-add the import at the top.

---

## Drop tier 3 — features still available, but candidates for further trimming if memory pressure persists

These are *not yet dropped* from `sequencer_lite/`, but listed here so the next memory pass has an obvious target. Each entry includes the estimated savings.

| Candidate | Savings | What you lose |
|---|---|---|
| Direction modes (keep only `forward`) | ~2 KB | Reverse / ping-pong / random / brownian playback. Most sequencers use forward exclusively. |
| Per-step probability | ~0.6 KB code | Songs become deterministic — every pass identical. |
| Per-track clock div/mult | ~1 KB | All tracks lock to the same clock. Loses polyrhythm support. |
| Ratchet | ~0.5 KB | No per-step repeat count. |

If the lite engine still doesn't fit comfortably, attack these in this order: **ratchet → direction modes → probability → clock div/mult**. (The order roughly matches "least musical loss first".)

> **Already dropped from the project entirely** (not just from lite): swing and live scale quantization. These are timing-feel and harmony-shaping concerns; apply them downstream of MIDI in your DAW or via a dedicated MIDI processor. See `docs/2026-04-28-drop-swing-and-scales.md`.

---

## How to find dropped code

The full engine remains the canonical source. To recover anything dropped:

```sh
git log --all -- sequencer/snapshot.lua
git log --all -- sequencer/mathops.lua
git log --all -- sequencer/scene.lua
git diff sequencer/track.lua sequencer_lite/track.lua
git diff sequencer/engine.lua sequencer_lite/engine.lua
```

The diff between `sequencer/` and `sequencer_lite/` is the authoritative list of what's missing on device.
