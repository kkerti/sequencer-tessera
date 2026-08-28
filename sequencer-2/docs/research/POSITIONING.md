# seq-2 Positioning

How seq-2 compares to and sits among its stated inspirations (CONTEXT.md,
ARCHITECTURE.md): the **Squarp Hermod+** (structural model), **ALM Pamela's
PRO Workout** (Loop Nap/Wake, clocked-euclid spirit), the **Euclidean rhythm
tradition**, and **sequencer-1** (deployment discipline; also the rejected
mono packed-int model). Companion to `docs/FEATURES.md`.

## Feature comparison

| Dimension | Hermod+ | Pamela's PRO Workout | seq-1 (ours) | **seq-2** |
|---|---|---|---|---|
| Tracks | 8, poly, per-track MIDI ch | 8 clocked euclid voices (CV) | 1 mono track | **2 poly (4-voice) tracks, engine supports 4** |
| Pattern storage | 16 patterns/track, event-based | none (algorithmic, params only) | fixed 16-step grid | **4 slots/track, grid-free events (pitch/start/len/vel)** |
| Effects | 8-slot rack, live, per-pattern values | n/a | none | **3-slot live rack (RANGE→RANDOM→SCALE), per-pattern values planned** |
| Generative | no (player + fx) | euclid + chance per voice | euclid variant | **seeded euclid generator + spread, reroll, auto-reroll, chance** |
| Performance mutability | mutes, pattern swap, fx sweeps | **nap/wake**, rotates, pokes | — | **nap/wake (from PPW), staged commit, auto-reroll** |
| Sequences/song | 16 sequences → songs | n/a | n/a | **4 sequences; song engine built, UI cut** |
| Recording | yes, quantized | no | no | **planned (M3)** |
| Persistence | project save/load | presets | Lua-chunk save | **planned (M4)** |
| UI richness | color graphic screen | small text LED menu | text + step strip | **text-only (RAM casualty)** |
| Platform | dedicated HW, ample RAM | dedicated HW | Grid VSN1, ~10 KB chunks | **Grid VSN1, ~130 KB heap, 5×≤10 KB text bundles** |

## Positioning

**seq-2 = Hermod+ architecture × PPW performance mutations × euclid
generation, squeezed onto a button-and-text module.** No single product
occupies that cell. The closest commercial spiritual cousins:

- **Torso T-1** shares the generative-euclid-with-parameters workflow, but is
  locked-in algorithmic — seq-2's generator *authors stored notes* you can
  then hand-edit in STEP mode. That two-stage "generate → edit the result" is
  Hermod's model, and seq-2 keeps it.
- **Hermod+** itself: seq-2 has the skeleton (tracks→patterns→rack→
  sequences, synchronized swap, non-destructive fx order) at ~1/8 the track
  count and none of the polish. Where seq-2 is *ahead* conceptually:
  deterministic seeded generation as a first-class param (SEED on the panel),
  staged-commit, and nap-into-an-evolved-state.
- **Pamela's PRO Workout**: seq-2 borrowed nap/wake and the "everything hangs
  off one clock" discipline, but adds polyphony and note-level data PPW
  doesn't have.

## Engineering position (vs seq-1)

This is where seq-2 is strongest: seq-1 proved the *deployment* (mono,
packed ints, text bundles ≤ ~10 KB); seq-2 proves a **polyphonic,
zero-alloc-on-pulse event engine can live inside the same budget** —
structure-of-arrays store, voice stealing, live fx chain, deterministic
generator, all under a heap ceiling that killed two earlier UI attempts. The
text GUI is the acknowledged regression vs seq-1's step strip;
`FEATURES.md` §8/§11 mark the path back.

## Honest scorecard

- **Engine / architecture** — at or beyond the inspirations in its niche.
- **Feature completeness** — well behind Hermod+ (no record, no save, no song
  UI, 2 tracks).
- **Immediacy / playability** — behind PPW/T-1 (params buried in menus, no
  visual rhythm feedback yet).

**The differentiator to protect: seeded, editable, non-destructive —**
generate like PPW, edit like Hermod, mutate live.
