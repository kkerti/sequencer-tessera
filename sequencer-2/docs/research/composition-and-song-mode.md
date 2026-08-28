# Composition & Song-Mode Research — seeding the next grill

**Purpose.** This doc feeds the next *grill* session on seq-2's next milestone:
composition modes, an extended sequence "work area" (parts → bars → steps with a
zoom/page overview), loop regions, per-track "nap"/mute, a **commit** action
instead of mutate-on-every-turn, and **song recall** (arranging tracks/sequences
into songs you can play back later). It surveys how real hardware sequencers
solve these, then frames the open decisions for seq-2.

**Date:** 2026-08-26.

**Provenance / trust level.**
- The **Hermod+** sections are cited to the local manual PDF
  (`docs/manual/HERMODPLUS_manual-*.pdf`, hermodplusOS 3.0, updated 2026-07-17) —
  this is a **primary source** and our stated model. Cite as `HERMOD+ p.N`.
- The **other-device** sections (§3 PNW/PPW, §4 Elektron • Deluge • Squarp •
  Torso • Polyend • Oxi • Five12) were **re-verified with primary-source
  citations** during a web pass on 2026-08-26 (official manuals/docs, cited
  inline). Claims that could not be pinned to a primary spec are still tagged
  `⚠︎VERIFY` (see §7 for the well-documented vs thin verdict).

**RAM lens (why it's all over this doc).** seq-2 sits at ~140 KB with ~20 KB
headroom on the Grid VM. Almost every composition feature below is *index /
metadata* (which pattern plays when, loop start/end ticks, repeat counts, mute
masks) — small integer arrays, cheap — **not** new note data. Note data is the
expensive thing, and our locked file-swap model already caps it to *the active
sequence only*. So the recurring question isn't "can we afford the feature" but
"can we afford the **UI code** and keep the pulse path allocation-free."

---

## 0. Terminology — we have a collision to resolve first

seq-2's code currently calls the on-track note container a **pattern**, and there
is exactly one per track. The user's language ("the *sequence* on a track", "each
part of a *sequence* has steps") uses **sequence** for that same thing. Hermod+
uses the words differently, and the difference *is* the composition model:

| Term (Hermod+) | Meaning | seq-2 today |
| --- | --- | --- |
| **Pattern** | the note/mod content on **one track** (steps, bars, pages). 16 per track. | our `pattern` (1 per track) |
| **Sequence** | a **vertical slice**: one pattern index across **all** tracks at once = a *scene*/section. `SEQ1` = all the `P1`s. | ✗ doesn't exist |
| **Song** | an ordered **chain of sequences**. | ✗ doesn't exist |
| **Project** | everything: all tracks, all patterns, all sequences, effects. | our `engine` state |

Source: HERMOD+ p.7, p.59, p.72.

**This is the first grill decision:** do we adopt Hermod+'s three-level
vocabulary (pattern → sequence/scene → song), or a flatter "the user's sequence =
our pattern, and a song is a chain of patterns per track" model? It changes every
data structure downstream and belongs in `CONTEXT.md`.

---

## 1. TL;DR — cross-device patterns that recur (with RAM cost)

Ordered by how directly they answer the user's ask. "RAM" = rough cost in seq-2's
SoA world.

1. **Per-track length + clock-divide → polymeter.** Each track/pattern loops at
   its own length; unequal lengths drift and re-align (LCM). Hermod+, Elektron,
   Torso, Hapax all do this. **RAM: ~0** — we already store `length` + `zoom`
   per pattern. (HERMOD+ p.16–17.)
2. **A page/overview bar under the roll: "4 pages = 4 bars", highlighted current
   page, a moving needle.** Exactly the user's "small bar showing which part is
   visible, split for 4 bars." **RAM: 0** — pure draw from `length`+`zoom`+`gt`.
   (HERMOD+ p.16.)
3. **Zoom decouples edit resolution from loop length** (÷4…×8), and zoom×length
   yields odd time signatures. **RAM: 0** — one enum per pattern (we have it).
4. **Scene = one pattern-index across all tracks; song = a queued chain of
   scenes.** The backbone of "compose then recall". **RAM: tiny** — a scene is N
   small ints (pattern-per-track) + a mute mask; a song is a list of scene ids.
   Note *data* stays on the FS (swap on scene change). (HERMOD+ p.72–73.)
5. **Two mute tiers: pattern/local mute (this scene only) vs global mute (all
   scenes).** Plus "mute affects input?" so a muted track can still take live
   input / run generators. The user's "nap it for some time." **RAM: ~2 masks.**
   (HERMOD+ p.59–60, p.67.)
6. **Quantized launch / commit boundaries.** Scene & edit changes don't apply
   instantly — they wait for a musical boundary (bar / track reset / LCM /
   "same as track X"). This is the natural home for the user's **commit** idea.
   **RAM: a couple "pending" ints.** (HERMOD+ p.73–75.)
7. **Non-destructive transforms.** Quantize, scale, transpose sit *over* stored
   notes and can change any time without rewriting the originals. Maps to seq-2's
   live-effects rack. **RAM: 0 extra** (already our model). (HERMOD+ p.67.)
8. **Generate-on-trigger, not continuously.** The pattern regenerates on an
   explicit event (a gate, a button), not on every knob move — reinforcing the
   commit model. **RAM: 0.** (HERMOD+ p.68, TRIG GENERATOR.)
9. **Copy/paste + seamless project swap for recall.** Sequences copy across
   projects; projects load in background without stopping playback. **RAM: 0**
   (FS ops). (HERMOD+ p.75.)
10. **Probability / conditional trigs per step** (Elektron trig conditions, Torso
    chance, PNW skip). Composition depth without more note rows. **RAM: 1 byte per
    step *if per-step*; ~0 if per-pattern.** ⚠︎VERIFY.

---

## 2. Hermod+ — our model (PRIMARY, cited)

Project → up to **16 tracks**; each track = **16 patterns** + an **8-slot effect
rack** + a modMatrix. Projects live on SD; load/save without stopping playback.
Four modes: **STEP, EFFECTS, TRACK, SEQ.** (HERMOD+ p.7.)

### (1) Sequence structure & the zoom / page-overview UI  *(STEP mode, p.16–18)*
- Under the piano roll, a **bottom bar** shows: **number of bars** in the current
  pattern, the **currently-viewed page**, and the **playhead**. Labeled parts:
  *playhead*, *pattern pages (4 pages = 4 bars)*, *page viewed (highlighted)*,
  *pages needle*, *track length (64 steps = 4 bars)*, *zoom (×1 = no zoom)*.
  → **This is precisely the user's requested overview bar.** (p.16.)
- **Page nav:** press ◄/► to pick the page; page count depends on length × zoom.
  By default the viewed page **follows the playhead**; scrolling pages
  temporarily detaches it (re-enter STEP to re-follow, or disable in MISC). (p.16.)
- **Pattern length:** hold ◄ + turn = **16 steps (1 bar) → 256 steps (16 bars)**;
  hold + click while scrolling = **per-step** fine length (17 steps = 1 bar +
  1/16…). Unequal lengths playing together = **polymeter.** (p.16.)
- **Zoom:** hold ► + turn. Levels **/4, /2, 2/3, ×1, 3/2, ×2, ×4, ×8**. ×1 = 1
  bar of 16 steps per page; /4 = long-sequence overview; ×8 = micro-edit.
  zoom×length → non-4/4 (12 @ ×1 = 3/4; 12 @ 2/3 = 6/8). (p.17.)
- **Note event = pitch (C0–C10) + length + velocity**; patterns are polyphonic
  and **grid-free** (chords, off-grid). Matches our SoA `pitch/start/len/vel`. (p.17.)

### (2) Song mode / arrangement & recall  *(SEQ mode, p.72–76)*
- A **sequence** = a collection of the **16 patterns `P1…P16`**, one per track
  ("SEQ1 holds all the P1 of the 16 tracks"). Selecting SEQ2 gives **16 fresh
  empty patterns** → author a new song **section**. (p.72.)
- SEQ screen shows: **playing sequence (SE1)**, **next sequence (SE2)**, project
  name, **LOOP** value, **RUN** mode, and a **tracks-overview of concurrent
  progress bars** (each pattern's own length → different %, i.e. polymeter). (p.72.)
- **Chain into a song:** hold ► + press pads to **queue** sequences; press ►
  briefly to clear the queue; press play → the whole song loops per RUN+SYNC.
  While the chain is *not* playing you can **scroll to any step and launch that
  sequence directly** (jump without rewriting the chain); relaunch resumes from
  the start of the currently-playing sequence. (p.73.)
- **Recall / save:** SEQ → PROJECT SAVE/LOAD → **SAVE / SAVE AS / NEW / LOAD /
  DELETE**. Projects **load in the background without stopping playback**; swap is
  offered **in sync (end of bar)** with a BPM-adopt prompt. Sequences
  **COPY/PASTE across projects** (patterns, effects, mute states, modMatrix carry
  over). (p.75–76.)

### (3) Per-track loop / repeat / "nap"  *(TRACK mode, p.59–67)*
- **Two mute tiers:** **PATTERN MUTE** (press pad) mutes the track **only in the
  current sequence**; **GLOBAL MUTE** (hold `track` + press pad) mutes it **across
  all sequences**. (p.59.)
- **MUTE AFFECTS INPUT** (per track): YES = muted **post-FX**; NO = only the
  **sequenced** data is muted while **live input + generative effects stay
  active.** (p.60, p.67.) → this is the knob that makes "nap" musical vs total.
- Independent **per-track length** already gives per-track looping; a *shorter*
  length is effectively a loop region for that track. (p.16.)
- **Track transpose leader:** one track drives real-time transposition of others.
  (p.66.) Composition tool worth noting.
- COPY / PASTE / CLEAR whole tracks; 12-char track **names** saved with project.
  (p.60.)

### (4) Commit-vs-live editing model
Hermod+ is mostly **live**, but has strong **quantized-boundary** and
**non-destructive** behavior that we can borrow for an explicit commit:
- **Launch quantization (SYNC):** a queued sequence starts only at a boundary —
  **MODULO** (LCM re-sync of all patterns), **N + X BARS**, **SHORTEST/LONGEST
  TRACK** reset, or **SAME AS TRACK X** reset (step-level). (p.73–74.)
- **RUN modes:** **SYNC/INSTANT** (apply at boundary vs immediately) and
  **RESTART/FREE** (restart on launch vs continue from position). (p.75.)
- **Non-destructive QUANTIZE** over stored notes — "modified at any time without
  overwriting positions of original notes." (p.67.) Same spirit as our live FX.
- **Generate on an explicit trigger**, not continuously: TRIG GENERATOR (gate →
  new pattern), TRIG GENERATOR MOD (gate → regen the mod lane only, notes
  untouched), TRIG GENERATOR PITCH/LENGTH/VELOCITY. (p.68.) → **directly supports
  the user's "commit action instead of change on every interaction."**
- **Track layouts / poly allocators** (POLYLRU default, POLY, FIRST, CYCLIC,
  RANDOM) — relevant to our 4-voice ring's voice-stealing. (p.62–65.)

---

## 3. ALM Busy Circuits — Pamela's New Workout (PNW) / Pamela's Pro Workout (PPW) *(PRIMARY, cited)*

Primary sources: official ALM manuals (busycircuits.com › Support › Manuals &
Firmware):
- PNW (ALM-017): https://assets.busycircuits.com/docs/alm017-manual.pdf
- PPW (ALM-034): https://assets.busycircuits.com/docs/alm034-manual.pdf

PNW is a **clocked gate/trigger/function generator**, not a note-composition
sequencer — the user likely names it for its **per-output generative model** and
tight UI, not song arranging. The relevant build here is **PPW**, ALM's feature
superset of PNW. (Naming correction vs. the earlier draft: ALM's expanders are
**PEXP-1/PEXP-2** and **PPEXP1/PPEXP2** plus **AXON-1/AXON-2** — not "CXM/PXOXO".)

- **(1) Structure:** master clock (PNW 10–300 BPM; PPW 10–330 BPM) + **8 clocked
  voltage outputs**, each with an independent **clock divider/multiplier** (PNW
  /512…×48; PPW /16384…×192, incl. non-integer factors) and an output **shape**
  (Gate/Triangle/Sine/Envelope/Random/Smooth Random; PPW adds Ratchets, Trapezoid,
  Hump, Exp/Log env). (PNW p.4–5, §3.3; PPW §2, §4.1.) A modifier of "x2" = "two
  steps per beat", "/2" = a pulse every other beat; a full waveform cycle = one
  step. (PNW §3.3; PPW §3.3.) → per-output length + divide = the polyrhythm /
  polymeter idea, same as Hermod+ per-track length; **RAM ~0 for us** (divide =
  one int per track).
- **Euclidean per channel:** per-output **ESteps / ETrig (fill) / EShift
  (rotation / phase)**; PPW adds **EPad** (padding steps). (PNW p.11; PPW §4.7.)
  → independently confirms *fill* + *rotation* as the core Euclid knobs (we
  already do Euclid + rotate).
- **Probability / skip:** a per-output "percentage likelihood a step will occur or
  be **skipped** with no effective output" — PPW §4.6; PNW's older **RSkip**
  param is that skipped-chance (PNW §3.3). → "chance/generative variation
  **without more note rows**" — same trade-off as our CHANCE fx.
- **Loop region / "nap":** PPW per-output **Loop** (beat at which the output
  resets), **Loop Nap** (shut the output off for N loops), **Loop Wake** (run N
  loops before napping), **Loop Shift** (offset nap/wake start). (PPW §4.8.) —
  This is literally the "mute it for some time then auto-return" idea.
- **Quantizer:** per-output **Quantiser** (scale + root) for 1 V/oct CV — mirrors
  our SCALE effect. (PPW §4.10, §4.12; PNW p.8–12.)
- **(2) Song / arrangement: NONE.** The only arrangement-scale container is a
  global **bank** covering the whole 8-output set + BPM. PPW: "Load Bank — Loads an
  entire bank (all 8 outputs) and current bpm. Save Bank — Saves an entire
  bank…". (PPW §6.5/6.6, p.21; per-output Load/Save/Reset as copy/paste §4.14.)
  PNW: 26 letter banks (a–z) × 8 slots, per-output and full-bank save/load
  (PNW p.14). Nothing like Hermod+'s scene/song chain. Chaining exists only as
  **clocked bank advance**: `Clk` = `NEXT BANK` (advance on each trigger) and
  `Run` = `PREV BANK`/`ROTATE` (PPW §6.1/6.2, p.20–21); PNW legacy **Run input**
  actions "Load Sequenced Bank"/"Load CV Bank" (PNW p.15–16). → a
  hardware-triggered bank advance, **not** a stored arrangement. PNW's lesson for
  us is *generative-depth + bank recall*, not song structure.
- **(3) Mute:** per-output **mute** via a hard-held key combo — PNW "toggle
  mute/un-mute… by clicking and holding the pan knob then clicking start/stop"
  (PNW p.14); PPW hold-start + turn program knob toggles current output mute
  (PPW §4.14 Key Shortcuts, p.19). Muted outputs are fully silent in PNW; PNW did
  **not** expose a "keep lanes running while muted" toggle (unlike Hermod's MMSF),
  so the "nap keeps generators alive" behavior is Hermod+-only. (See §2.)
- **(4) Commit model — live, instant, no quantized apply.** "Instant Saving and
  loading of output settings and banks" + "Clock does not need to be stopped for
  current parameters to be saved across power cycles." (PPW §10.5.) PNW auto-saves
  and remembers between power cycles (PNW p.14) — the *counter-example* to a
  staged-commit. Worth contrasting in the grill: our user explicitly wants the
  *opposite* (staged commit) for composition. One honest caveat: PNW warns
  "Saving may introduce timing errors if done whilst clock running" (PNW p.14) —
  i.e. even ALM treats save-as-mutating as clock-unsafe, supporting a commit/bake
  boundary.

---

## 4. Other composition-capable sequencers *(PRIMARY, cited — descriptions cite official manuals)*

Compact matrix, then one-liners. Sources per device are noted under the table;
everything below was verified against an official manufacturer manual/docs page
(see §7 for the "well-documented vs thin" verdict). Claims I could **not**
verify are tagged ⚠︎VERIFY inline.

| Device | Structure / zoom | Song / recall | Loop / mute / "nap" | Commit vs live |
| --- | --- | --- | --- | --- |
| **Elektron Digitakt** | pattern = ≤8 tracks + length (2–1024 steps) + swing + time-sig (§9 p.25); **PER-TRACK SCALE** = per-track length + ×rate for polymeter (p.36) | **SONG MODE** = ≤99 rows, fields **pattern, row-repeat(1–32), row-length, row-tempo, row-mute**, + END=LOOP/STOP (pp.40–42) | **chain** (≤64 patterns, live, non-persistent); track mute; **trig conditions** (prob/FILL/PRE/NEI/1ST/A:B) | live; temp SAVE/RELOAD `FUNC+YES/NO`; SAVE TO PROJ to persist |
| **Elektron Octatrack** | bank = 4 parts × 16 patterns; **Parts** (non-persist machine/sample/FX/scene settings) + **Scenes** (§10) | **ARRANGER** = ≤256 rows, fields **pattern, REP×(repeat), OF(offset), LN(length-override), SCENE A/B, T (per-midi-transpose), B (tempo), M (row-mute)**, + HALT/LOOP/REM/JUMP; 8 arrangements/project (§14, p.87–88) | **pattern chain** same-bank-only, no repeats, loop-only (§12.2.3) | live; Part RELOAD/EDIT revert-to-saved; arrangement SAVE/RELOAD |
| **Synthstrom Deluge** | Song view groups **clips** (per-clip length, `[SHIFT]+turn`); **Arranger** = per-track grid of **clip instances** | Arranger = linear **clip-instance timeline**; **Song Sections** = looping clip groups, auto-chain up to 12 colours, repeat modes (Infinite/#/SHAR) (§7.5) | loop = **extended clip instance loops its content**; row mute; **white clips** = unique variation instances | no commit step; live undo/redo; edits propagate to linked instances |
| **Squarp Pyramid** | 64 tracks × 32 patterns; per-track **length (1–16 bars + fraction)** & **time-signature → true poly/polyrhythm**; zoom /4…×48 | **SEQ mode** — sequence = per-track **mute-state + pattern**; **song = chain of sequences**, each row = {sequence, bar-count}; PLAY/LOOP/PERFORM; seq length = LCM of track lengths | mute = pad toggle, muted tracks **keep evolving in parallel**; sync-deferred by PERFORM delay; run modes FREE/RELATCH/TRIG | live; **CONSOLIDATE** = bake fx to notes (destructive); effects live & non-destructive |
| **Squarp Hapax** | 2 projects × 16 tracks × 16 patterns; **per-pattern length** 1–32 bars / 1–512 steps; **zoom** step-resolution; **loop points** per-pattern, real-time; **time-elasticity** = per-track BPM (polyrhythm) | **Sections → SONG**; song row = {section, duration}, reuse sections; PLAY SONG/LOOP SONG; **OVERRIDE** = re-save section; **Snapshot** per-pattern toggle-recall | **mute-hold** = flash-group mute applied on release; instant `2ND+mute`; per-pattern mute; project mute in-sync at bar | live edits + destruct/non-destruct quantize; HARD REC vs OVERDUB |
| **Torso T-1** | 16 tracks/pattern, 16 channels, polyphony; per-track **Division** (clock res), **Length/Steps/Pulses** + **Cycles** evolution; banks | Bank = 16 patterns, "one bank per song"; patterns **launched quantized + chained** into longer sequences; externally via MIDI-Program-Change | per-track **mute** page; per-step **Probability** skip; **Repeats/Ramp** | live/real-time; no formal commit/bake concept in manual |
| **Polyend Tracker/Play** | Tracker = row-grid (12 tracks, pattern ≤128 steps); Play = step-grid + per-track Length/Speed/*Step Pages*/*Variations* | **Tracker Song mode** chains patterns (Play-all button); Play = **pattern chain** + Fill | per-track **Mute/Solo** (Tracker); per-track mute (Play) | Tracker = **parameter-locked/step-edit** + live rec; Play = live grid + Live Rec |
| **Oxi One** | 8 sequencers/64 tracks, 9 modes (Mono/Poly/Chord/Drum/Stochastic/…); per-track patterns | **Arranger Mode** for song layout; **pattern chaining** | **Performance Mode** = all-track mute/launch grid; Loop | live: real-time rec (with quantize), per-step micro offsets ⚠︎VERIFY deep detail |
| **Five12 Vector** | **8 Parts**, 16/32/64-step patterns, 2 sub-sequencers, per-Part **Presets/Playlists/Scenes**, 42 presets/part; **Chance Ops** per step | Scenes/Playlists as song/session layer; project recall; ⚠︎VERIFY "12 snapshots + morph" | per-Part | live-ish; PDF-only specifics ⚠︎VERIFY box for morph/interval |

**Citations per device (primary sources):**
- **Elektron** — *Digitakt User Manual* OS 1.52A: `https://www.elektron.se/wp-content/uploads/2025/07/Digitakt-User-Manual_ENG_OS1.52A_250708.pdf` (SONG MODE §10.11, pp.40–42; PER TRACK scale §3.2 p.36; trig conditions §10.6.4 p.28). *Octatrack MKII User Manual* OS 1.40A: `https://www.elektron.se/wp-content/uploads/2024/09/Octatrack-MKII-User-Manual_ENG_OS1.40A_210414.pdf` (Parts/Scenes §10 pp.30–34; The Arranger §14 pp.87–88; pattern chaining §12.2.3 p.64). *Digitone* manual is the same Elektron set.
- **Synthstrom Deluge**: official community-authored guidebook distributed by Synthstrom, *Deluge Guidebook 4p0* `https://synthstrom-audible-deluge.s3.us-east-2.amazonaws.com/Deluge-Guidebook-4p4.pdf` (views §2.4 p.17; clip length §3.9 p.59; arranger §8.3 pp.153–160; sections §7.5–7.6 pp.145–148; white-clip variations §8.4 pp.162–163). ⚠️ **Label: community-authored but distributed by the manufacturer** (Synthstrom's own manuals started from community-driven docs). *Deluge community docs* (non-primary): `https://seangoodvibes.github.io/DelugeDocs/`; official community-firmware manual `https://delugecommunity.com/manual/` (still skeletal).
- **Squarp Pyramid**: official HTML manual `https://squarp.net/legacy/pyramid/manual/` (PyraOS v3.2; the site's `static/` area also hosts the single-file user-guide PDF, though that PDF is a community-authored LaTeX transcription). SEQ chains pp.37–39; mute pp.27–28; CONSOLIDATE pp.28–29; time-signature & polymeter p.33–34; effects non-destructive p.42. Note: **squarp.com (old) is dead — official site is squarp.net**.
- **Squarp Hapax**: official manual (hapaxOS 3.10): `https://squarp.net/static/HAPAX_manual-955ab84ef06fd2782cc0ee083550f72c.pdf` (architecture §1.3 p.9–10; length/zoom §3.6 p.51; loop points §3.7 p.53; time-elasticity §1.23 p.26; Sections→Song §5.13–5.15 pp.84–87; Snapshot §1.21 p.24; mute §1.14–1.15 pp.18–19; per-pattern mute §5.5 p.76; effects §7.1 pp.99–100; quantize §1.18/§2.3 p.20/29–30).
- **Torso T-1**: official docs `https://docs.torsoelectronics.com/t1/introduction/`; tracks § `…/t1/tracks-patterns-banks/tracks/`; Division `…/t1/parameter-reference/shape/division/`; banks/patterns/chaining `…/t1/tracks-patterns-banks/banks-patterns/`; Cycles `…/t1/core-concepts/cycles/`; Velocity & Probability `…/t1/parameter-reference/groove/velocity-probability/`; Mute `…/t1/miscellaneous/mute/`. Tech spec `https://www.torsoelectronics.com/t1/technical-specifications`. *(Domain note: do not use "toroneouspiece" or "polyendman" — the latter is a third-party mirror, not official.)*
- **Polyend**: official site/manual viewer `https://polyend.com/manuals/tracker/` and download pages `https://polyend.com/downloads/tracker-downloads/`, `https://polyend.com/downloads/play-downloads/` (Song-mode/pattern-chain facts cited from the device changelogs hosted there). ⚠️ The full Tracker/Play/Seq **song-mode PDF** internals (exact row fields/pages) were **not** extracted in this pass — device is **thin-documented for our purpose**; treat those cells as verified-at-changelog level only.
- **Oxi One**: official product + support `https://oxiinstruments.com/support` / `https://oxiinstruments.com/oxi-one-mkii`. **⚠︎VERIFY — thin official docs**: the only manual is a Google-Drive-hosted PDF (`https://drive.google.com/file/d/1LdJvG-…/view`); Arranger/Performance-mode/chain internals confirmed only at the product-page level, not manual-spec level.
- **Five12 Vector**: official manual PDF `https://files.five12.com/VectorUserGuideV3.0.pdf` + product page `https://www.five12.com/hq/ProdVector` (8 parts, per-part presets/playlists/scenes, chance-ops confirmed). **⚠︎VERIFY — the "12 snapshots + morph/Vector-mod" specifics live inside the PDF but it is >5 MB and not machine-extractable here**; cite the PDF URL, page numbers UNVERIFIED.

**One-liners worth carrying into the grill (now verified):**
- **Elektron song mode / Octatrack arranger** is the cleanest **recall-arrangement** template that stays RAM-cheap: a **list of rows** = `(pattern, length, repeat, muteMask)` — Digitakt verifies **repeat, length, tempo, mute** per row; Octatrack adds **per-row transpose + scene + length-override**. **This is the strongest candidate structure for seq-2's song layer.**
- **Trig conditions** (Elektron FILL/PRE/…/%/A:B, §10.6.4) and **chance** (Torso Probability, PNW Probability/RSkip) are how these boxes get compositional variation **without** more note storage — confirmed, ≤1 byte/step.
- **Five12 "snapshots + morph"** is an alternate recall metaphor — an open question (morph/interval model) for the grill ⚠︎VERIFY.
- **Deluge arranger** is the most DAW-like (timeline of clip instances) — richest but the most UI/RAM to build; probably out of scope for a 320×240 + encoder surface. *(verified from official guide.)*
- **Pyramid / Hapax "sequence = mute-state + pattern-per-track"** and **song row = {sequence, duration}** is effectively Hermod+'s **scene-chain** given another name — a good signal that Hermod+'s model isn't an outlier.

---

## 5. Where seq-2 stands today (gap analysis)

Current reality (from `src/`):
- **2 tracks, exactly 1 "pattern" each.** No pattern slots, no scenes, no song.
  (`engine.tracks[t].pattern`.)
- Pattern already has **`length` + `zoom`** (ZOOM tps table) → polymeter is one
  step away; **`loopTicks = length × tps`** drives playback wrap. We just don't
  *draw* a page/overview bar yet.
- `control.lua` **regenerates on every encoder turn** (`M.turn` → `regen`) — the
  exact behavior the user wants to replace with a **commit**.
- Effects rack (RANGE/RANDOM/SCALE) already is the **non-destructive transform**
  layer — the Hermod+ "live over stored notes" model, done.
- No mute, no loop-region, no per-track nap, no scene/song, no page overview.

**Cheapest high-value wins (for the grill to rank), all RAM-light:**
- Page/overview bar under the roll (draw-only). ✅ 0 RAM.
- Staged-edit + **commit** (dirty `gen` copy → apply on click / bar). ~1 table.
- Loop region per pattern = `loopStart/loopEnd` ticks (2 ints); playback wraps
  the sub-range. Tiny.
- Per-track **nap** = transient mute + optional auto-unmute countdown (2 ints);
  must be applied inside `onPulse` **allocation-free**.
- Scene layer = per-track pattern index + mute mask; song = list of scene ids;
  note data swapped from FS on scene change (our locked model). Index-only RAM.

---

## 6. Implications & open questions for the grill (the payload)

Framed as decisions, with the trade-off and RAM note. **No answers picked here.**

1. **Vocabulary (blocking).** Adopt Hermod+'s *pattern → sequence(scene) → song*,
   or a flatter *pattern → song(chain of patterns)*? Everything downstream keys
   off this. → write the winner into `CONTEXT.md`. (RAM: n/a.)
2. **Song = discrete scene-chain (Hermod+) or row-list arranger (Elektron) or
   snapshot+morph (Five12)?** Scene-chain is simplest to drive from 8 keyswitches;
   row-list gives repeats/mutes per section; morph is fancy but heavy. (RAM: all
   small; UI cost differs a lot.)
3. **Is the extended "work area" a flat step list up to N bars (Hermod+: 16 bars /
   256 steps) or an explicit bars→pages hierarchy?** Flat + a *derived* page view
   (page = 16 steps × zoom) is cheapest and is what Hermod+ actually does under
   the hood. Do we cap at 4 bars (user's hint) or allow more? (RAM: note count
   scales with bars — but capped by FS-swap; the SoA arrays grow lazily.)
4. **Loop region: transient performance state or saved per-pattern?** If saved,
   it's 2 ints in the pattern; if transient, it's engine state cleared on stop.
   Does looping a sub-range also gate recording into that range? (RAM: 2 ints.)
5. **"Nap": manual mute you toggle back, or timed (mute for N bars then
   auto-return)?** Timed needs a per-track countdown ticked in `onPulse`
   (alloc-free). Does nap silence post-FX (total) or pre-FX (generators/live keep
   running) — i.e. do we copy Hermod+'s MUTE AFFECTS INPUT? (RAM: 1–2 ints/track.)
6. **Commit semantics: what's the boundary?** (a) explicit encoder-click commit,
   (b) quantized apply at next bar / pattern reset (Hermod+ SYNC), (c) both. And
   **what is staged** — only generator params, or manual note edits too? (RAM: one
   dirty `gen` copy per track ≈ a dozen ints.)
7. **Do generator params stay live-preview while staged, or is the pattern frozen
   until commit?** Live-preview means we still regen on turn (the thing the user
   dislikes); frozen means we show *intended* params as text and only regen on
   commit. Leaning frozen — confirm. (RAM: 0.)
8. **Per-track independent length/divide (polymeter) — expose now?** We're one
   `zoom`/`length` UI away; it's the single biggest musical payoff for ~0 RAM.
   How to show drift (concurrent progress bars, à la Hermod+ SEQ)? 
9. **Mute tiers — do we need both pattern-local and global mute with only 2
   tracks?** Maybe only one tier until track count grows. (RAM: 1 mask either way.)
10. **New composition *modes* — how many, and how do they share the 8
    keyswitches?** Candidates: STEP (edit), GEN (generator/commit), SONG (scene
    chain), PERFORM (mute/nap/loop). Hermod+ uses 4 hardware mode keys; we have
    KS7 toggling PLAY/SETUP today. A mode ring vs dedicated keys? (RAM: n/a; this
    is the UX crux.)
11. **Probability/chance depth: per-pattern (we have a CHANCE fx) or per-step?**
    Per-step is 1 byte/step and unlocks Elektron-style variation but changes the
    SoA (add a `cond[]`/`prob[]` array). Worth the RAM? (RAM: +1 array sized to
    note count.)
12. **Recall storage: reuse the locked Lua-chunk FS-swap for scenes/songs?** A
    song = a tiny index file; each scene swaps its patterns in. Confirm this fits
    the "only active sequence in RAM" decision and the seamless-swap goal. (RAM:
    index only.)
13. **Do we keep 2 tracks for this milestone** (per locked decision #6) while
    adding the whole scene/song layer, and scale to more later? Song/scene index
    structures are track-count-agnostic if sized dynamically. (RAM: scales with
    tracks×scenes, but ints only.)

**Top 5 to open the grill with:** #1 (vocabulary), #2 (song shape), #6 (commit
boundary), #5 (nap semantics), #3 (work-area model).

---

## 7. Follow-up: citation pass — COMPLETE

**Status: done (2026-08-26).** The earlier "account-limit" note is stale: a web
pass re-ran §3 and §4, and they now carry primary citations inline.

**Devices WELL documented (primary source):**
- **§3 ALM PNW / PPW** — official PDFs (alm017 / alm034); structure, euclid,
  Loop/Nap/Wake, mute, and live commit model all cited to section + page.
- **Elektron Digitakt + Octatrack** — official SONG MODE / ARRANGER row fields
  fully verified. This answered the strongest open question: song rows carry
  **pattern, repeat, length, tempo, mute**; Octatrack adds **transpose + scene +
  length/offset**. (The "needs VERIFY exact row fields" tag on §4 is now removed.)
- **Squarp Pyramid + Hapax** — official squarp.net manual/HTML (note squarp.com
  is defunct; and the Pyramid PDF is a community LaTeX transcription).
- **Synthstrom Deluge** — officially-distributed guidebook (community-authored,
  clearly labelled); arranger + sections verified.
- **Torso T-1** — official Torso docs (the best primary web docs of the set).

**Devices THIN (a few claims verified; deeper internals still ⚠︎VERIFY):**
- **Polyend** — official guides are large PDFs; Song/pattern-chain facts cited only
  at changelog level, exact song-row fields/pages not extracted. ⚠︎VERIFY critical.
- **Oxi One** — manual is a Google-Drive PDF only; Arranger/Performance internals
  confirmed only at product-page level. ⚠︎VERIFY that detail.
- **Five12 Vector** — the manual PDF is >5 MB and not machine-extractable here;
  8 Parts + per-Part presets/playlists/scenes + Chance-Ops verified, but the
  "12 snapshots + morph/Vector" page numbers stay ⚠︎VERIFY until a human reads the PDF.

The Hermod+ sections were already primary-cited and are unchanged.
