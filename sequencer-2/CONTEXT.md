# CONTEXT — sequencer-2 glossary

The ubiquitous language of this project. Glossary only — no implementation
details (those live in `docs/ARCHITECTURE.md`). When a word here and a word in
the code disagree, one of them is wrong; fix it.

## Time

- **Pulse** — one external MIDI clock tick. The engine consumes pulses; it has no
  BPM of its own.
- **Tick** — the engine's time unit. 1 tick = 1 pulse. **24 ticks = 1 quarter
  note** (24 PPQN). A 1/16 note = 6 ticks.
- **Step** — a grid position for editing/quantizing. Its duration in ticks is set
  by **zoom** (at ×1, one step = a 1/16 note = 6 ticks). A pattern's loop
  **length** is counted in steps. A step is *not* a storage slot — notes store
  absolute ticks; steps are the grid they snap to.
- **Zoom** — the magnification mapping steps to ticks (e.g. ×1, ×2 finer, /2
  coarser, triplet grids). Changes step duration and how many steps fit a page.
- **Page** — the window of steps shown on screen at once.
- **Playhead** — a track's current position within its pattern loop. Tracks with
  different lengths have independent playheads (polymetry).

## Structure

- **Project** — the whole saved state: all tracks, their patterns, sequences,
  and song.
- **Track** — one musical voice-group: its pattern slots, one effect **rack**,
  one MIDI channel, one playhead, one record buffer. 4 tracks.
- **Pattern** — a polyphonic, grid-free collection of **notes** plus a loop
  length, its per-pattern effect values, and a **loop region**. Hermod's
  P1..P16 per track; we keep 4 slots/track (extensible to 8).
- **Loop region** — a sub-range of a pattern's steps that plays in a tight
  loop when active, instead of the pattern's full length. Saved per-pattern.
- **Sequence** — one selected pattern slot per track, played together, plus
  each track's **mute** state for this sequence only. (Hermod §5.)
- **Song** — sequences chained in order. A chain step is just a sequence-id
  (Hermod's simplest shape); the gap between steps is one global SYNC
  setting, not stored per-step.

## Notes

- **Note** — a single sounding event: **pitch**, **start** (tick offset from
  pattern start), **length** (ticks held), **velocity**. Chords = notes sharing a
  start. (Reserve "event" for the engine-internal note-on/note-off it emits.)
- **Voice** — one currently-sounding note occupying an output slot. A track has a
  fixed **voice cap** (4); a new note past the cap steals a voice.
- **Quantize** — snap a note's start to the nearest step on write/record. Storage
  stays free-form so notes can later be nudged off-grid.

## Effects

- **Rack** — a track's ordered chain of up to 8 **effects**. Order is meaningful.
  Runs live on every pulse; never rewrites stored notes.
- **Effect** — a non-destructive transform of the notes flowing through the rack.
  M1 set: **SCALE**, **RANGE**, **RANDOM**.
- **SCALE** — quantizes pitch to a musical scale.
- **RANGE** — the performance limiter: clamps pitch / velocity / length to a
  min–max window. The knobs you sweep while performing.
- **RANDOM** — probabilistic variation of notes (skip / jitter).
- **Pattern value** — a per-effect-parameter override: a parameter can hold a
  *global* value (shared by all patterns of the track) or a *pattern* value (this
  pattern only). (Hermod §3.5.)

## Generation

- **Generator** — a one-shot command that *authors* notes into a pattern's event
  store (overwrites it). Distinct from an effect: an effect transforms notes at
  play time; the generator creates stored notes at edit time.
- **Euclidean** — the generator's rhythm: `hits` onsets spread as evenly as
  possible over the pattern's length, optionally `rotate`d.
- **Spread** — the generator's ± amount around a **root** for a field (pitch in
  scale degrees, velocity, gate). The *authoring* counterpart to RANGE's
  play-time clamp — same shape, opposite verb (create vs limit).
- **Reroll** — regenerate with the next **seed**, applied immediately (never
  staged — its whole point is to show a new variant now). Same seed ⇒ same
  pattern, so a variant you like is recallable.

## Control

- **Overdub** — record new notes layered on top of existing ones (non-destructive).
- **Handoff** — delegating control of the sequencer to another connected Grid
  controller (e.g. a 16-button module as a step keyboard).
- **Mode** — the top-level control-surface context: **PLAY** (generator params,
  staged), **STEP** (per-note editing, live), **SEQ** (pattern-slot/sequence/
  song browsing). SETUP is a full-screen detail view of PLAY, not a separate
  mode.
- **Staged / pending** — a generator-param edit that's been dialed but not yet
  applied. Only generator params stage (they *regenerate*, i.e. overwrite, the
  whole pattern); note edits, reroll, and auto-reroll always apply live.
- **Commit** — the explicit action (dedicated key) that applies staged
  generator-param edits, calling the generator once.
- **Auto-reroll** — reroll fired automatically every N of the track's own
  pattern loops, instead of only on a manual key. Applies immediately, like a
  manual reroll.
- **Nap** — temporarily mute a track for N loops, then auto-resume ("Wake").
  The track's generator/effects keep running underneath while napped, so it
  can wake into an evolved state. (PPW's Loop Nap/Loop Wake.)
