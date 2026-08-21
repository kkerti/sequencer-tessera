# 2026-04-27 — Sequencer lite carve

## Why

User measured on-device RAM after uploading three test songs:
- Empty song + player ≈ 6 KB total (player ~5–6 KB by itself).
- four_on_floor (32 events) + player ≈ 6 KB.
- dark_groove (232 events) + player ≈ 20 KB.

Per-event runtime cost ≈ 80 bytes on ESP32 (5 array slots × ~16 B/double + table overhead). Player code ≈ 5 KB resident from a 3 KB stripped source.

User wanted to know whether the **authoring** engine could also live on device, with a clear list of features dropped to make space.

## What was done

1. **`docs/dropped-features.md`** — three-tier drop catalogue (modules removed entirely → features removed from carried-over modules → future trimming candidates) with revival recipes for each.
2. **`sequencer_lite/`** — carved authoring engine, four files:
   - `step.lua` and `pattern.lua` — byte-equivalent copies, only `require()` paths rewritten.
   - `track.lua` — drops `copyPattern`, `duplicatePattern`, `insertPattern`, `deletePattern`, `swapPatterns`, `pastePattern`, plus three private helpers.
   - `engine.lua` — drops scene-chain hooks; `Engine.onPulse` becomes a no-op stable hook so callers don't branch on lite-vs-full.
3. **`tests/sequencer_lite.lua`** — smoke test verifying module load, structure, step round-trip, 16-pulse advance produces 8 correct events, reset, no-op onPulse, removed-API absence, scale quantizer, all 5 direction modes settable.
4. **`docs/ARCHITECTURE.md`** — added Lite-engine section with size table; updated file layout.
5. **`AGENTS.md`** — added lite test to the run command, added `sequencer_lite/` to file layout, listed `dropped-features.md` under docs.

## Sizes (stripped)

| Folder | Raw | Stripped | Reduction |
|---|---|---|---|
| `sequencer_lite/` + `utils.lua` | 29.8 KB | 17.8 KB | 40.4% |
| `sequencer/` (full) + `utils.lua` | 69.2 KB | 38.1 KB | 44.9% |

Lite saves ~20 KB of source vs. full.

## Verification

All 14 behavioural tests + 11 sequence scenarios pass:
- Full `sequencer/` engine unaffected (the carve is purely additive).
- Lite engine smoke test passes — playback semantics match full engine for the basic forward-walk case.

## Decisions

- **Duplicate vs. split vs. conditional:** chose duplicate. Pros: zero risk to the proven `sequencer/` engine. Cons: ~2x maintenance for shared modules. Justification: `step.lua` and `pattern.lua` rarely change; if they drift, a `git diff sequencer_lite/X.lua sequencer/X.lua` immediately surfaces it.
- **Scope = tier 1 + tier 2:** dropped snapshot/mathops/scene/song_writer entirely; dropped pattern manipulation from `track.lua`; dropped scene hooks from `engine.lua`. Kept all 5 direction modes, full ratchet/probability/scale support. Tier-3 candidates (forward-only, drop swing, drop ratchet) documented but not yet executed.
- **`Engine.onPulse` kept as a no-op** in lite — keeps the player call sites identical between lite and full engines.
- **Lite engine is not yet wired into the Grid bundle.** Next step is to upload + measure.

## Status

Lite engine carved, smoke-tested, documented. Not yet bundled or measured on device.

## Next steps

1. Build a Grid bundle that includes `sequencer_lite/` (5 files: step, pattern, track, engine, utils) and upload it to measure RAM cost — establishes the on-device baseline for "engine + nothing else".
2. Decide whether the ~18 KB stripped source is small enough to comfortably co-exist with player + a non-trivial compiled song. If yes, proceed to the on-device song-builder UI. If no, attack tier-3 drops in order: swing → ratchet → direction modes → quantizer → probability → clock div/mult.
3. Build `live/edit.lua` — the small in-place editor on the compiled song arrays (pitch + velocity + mute as the user picked). This is the lower-cost alternative to a full on-device authoring engine and may eliminate the need for one entirely.
