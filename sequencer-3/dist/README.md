# dist/ — seq-3 on the Grid VSN1

**v7: SEQ-1 WIRING + THREE pre-linked bundles.**

**Reference correction: sequencer-1 is the cold-boot-proven project** (seq-2
is dead; its profile was never the verified baseline).

## Evidence table

| Build | Wiring / shape | Result |
|---|---|---|
| v0 full GUI, 13 FS files, eager | gms + grxm(2,3) | 183 KB, bricked |
| v0b–v4 core-only, FS modules, various laziness | gms + grxm(2,3) | 149–139 KB; cold boot dead every time |
| v5 empty setup, FS modules | gms + grxm(2,3) | cold boot dead **even with a 16-char setup** |
| v6 two big pre-linked bundles (37 KB), eager | gms + grxm(2,3) | cold boot dead |
| **seq-1 (proven, cold boots every time)** | **midi_send + rtmrx_cb, NO grxm anywhere**, bundles 10.3 + 8.8 KB | boots |
| **v7 (this dist)** | **midi_send, no grxm**, bundles 19.2 + 10.7 + 7.5 KB | measure |

The one constant across every seq-3 failure — even v5, whose setup was
literally `RX=nil` — is `gms`/`grxm(2,3)`, inherited from the dead seq-2.
seq-1 never calls `grxm` and uses the `midi_send` global. If `grxm` errors
during the cold-boot sequence (MIDI subsystem not ready while the profile
loads), every one of our boots dies regardless of Lua heap. v7 removes it.

## Upload (Grid editor)

1. Delete ALL previously uploaded per-file modules (`engine`, `sources`,
   `screen`, `menu`, …) from the module's file storage.
2. Upload the three bundles under these exact names:
   - `dist/seq3.lua` (19.2 KB — core: sources/scales/lane/transport/engine)
   - `dist/seq3ui.lua` (10.7 KB — device_boot/midi_rx/screen/menu)
   - `dist/seq3x.lua` (7.5 KB — generate/ext/ops/preset, loaded at setup so
     the engine's lazy loaders resolve; candidate for lazy-loading if cold
     boot still dies)
3. Load the refreshed **seq3 core** profile. Setup: 3 requires + demo +
   `rtmrx_cb = function(self,h,t) RX.handle(t, midi_send) end` — **no grxm**.
4. Route MIDI clock in (Ableton), module MIDI out to the DAW.

## What works (verified headlessly through the real bundles)

2-lane demo (note + trig), clock → notes out, stop → note-offs,
Overview/Focus/Config, param editing, Zero/Shred, lane select, lazy ops/
generate/ext/preset through the bundle chain. `seq3 mem KB: <n>` prints from
the timer event — report it at boot and per screen.

## Regenerate

```
sh tools/make_dist.sh [--install]     # bundles + profile
lua tests/dist_smoke.lua              # loads the real bundles headlessly
```

## If v7 still fails cold

The remaining deltas vs seq-1, in cut order:
1. **Bundle sizes**: seq-1's max chunk is 10.3 KB; ours is 19.2 KB. Split
   `seq3.lua` into `seq3.lua` (sources/scales/lane/transport, ~7 KB) +
   `seq3b.lua` (engine, ~12 KB).
2. **Total eager load**: seq-1 loads 10.3 KB at init (UI lazy). Ours loads
   37.4 KB across 3 requires. Drop `seq3x` from setup — require it on the
   first op/generate call instead (edit `seq3.lua`'s shim: fall through to a
   guarded `require("seq3x")`).
3. `rtmrx_cb` signature: seq-1 uses `function(self, t)`; we use the same.
   Template's event 4 (`gpl(gpn())`) runs — harmless, kept.
4. Element mode setup (`epmo(1)` on the encoder) — seq-1 has no such setup
   block and reads `endless_value()`; if cold boot still fails, strip the
   `--[[@sen]]` prefix from event 7 and switch to `self:endless_value()-64`.
