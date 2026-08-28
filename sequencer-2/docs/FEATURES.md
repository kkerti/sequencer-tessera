# seq-2 Feature Set & Manual

The complete inventory of what the sequencer does today (lean device build),
written as a manual: each feature with a short description and how you
interact with it on the VSN1R. This is the source document for designing the
next menu/GUI system — §8 lists what works but is currently INVISIBLE, §9
what is not built.

Hardware: Grid VSN1R — 8 keyswitches (KS0–7), 4 small buttons (9–12), one
push-encoder, 320×240 text screen. Device build: 2 tracks, 4 pattern slots,
4 sequences.

---

## 1. Transport & MIDI

The sequencer has **no internal clock**. It is driven entirely by an external
MIDI clock (e.g. Ableton): incoming **0xF8** realtime bytes are pulses,
**0xFA/0xFB** = start/continue, **0xFC** = stop. All note output goes through
the module's MIDI out; **track 1 plays on channel 1, track 2 on channel 2**.

| What | Description |
|---|---|
| Run/stop | Start/stop the master; the screen header shows RUN or STOP. On stop, every still-sounding note receives a note-off (no hanging voices). |
| Polyphony | Each track plays up to **4 simultaneous notes**. A 5th note steals the voice whose note ends soonest (its note-off is sent first). |
| Quantize | Notes are emitted exactly on incoming clock ticks — timing is the master's timing. |

**Interaction:** just route a MIDI clock into the module and the module's out
to a synth. Press play on the master.

---

## 2. The three modes

**KS7 cycles the mode: PLAY → STEP → SEQ → PLAY.** The KS7 LED colour shows
where you are: orange = PLAY, cyan = STEP, purple = SEQ.

---

## 3. PLAY — the generator cockpit

PLAY is where you shape a track's **generated pattern**. Each track owns a
seeded Euclidean generator: a rhythm with `hits` onsets spread over the
pattern length, note pitches drawn `root ± spread` in the current scale.

### 3.1 Staging and COMMIT

Generator edits are **staged, not immediate**: turning the encoder changes a
staged value, the screen marks the track `*` (dirty, "staged"). Pressing
**button 12 (OK)** applies everything and regenerates the pattern once. This
lets you prepare a change and drop it in on purpose.

*Exception:* **CHANCE** is a live effect parameter — it applies instantly,
never stages.

### 3.2 The 12 generator parameters

| # | Param | Meaning |
|---|---|---|
| 1 | SCALE | One of 8: off (chromatic), Major, Minor, Harm Minor, Dorian, Phrygian, Mixolydian, Min Pentatonic. |
| 2 | KEY | Root note of the scale, C..B. |
| 3 | HITS | How many note onsets the Euclid rhythm places (1..length). Screen shows `hits / length`. |
| 4 | ROTATE | Rotates the rhythm right by n steps. |
| 5 | PITCH | Centre note the generated pitches orbit (e.g. C4). |
| 6 | SPREAD | How far pitches wander from the centre, in **scale degrees** (stays in key). |
| 7 | VEL | Centre velocity. |
| 8 | GATE | Note length centre, in ticks. |
| 9 | SEED | The generator seed. Same seed = same pattern. |
| 10 | LENGTH | Pattern length in steps (1..64). |
| 11 | ZOOM | Ticks per step: /2 (12), x1 (6), 2/3 (4), x2 (3) — the step grid resolution. |
| 12 | CHANCE | % probability each note actually plays (live RANDOM effect, 0–100). |

### 3.3 PLAY interactions

| Input | Action |
|---|---|
| KS0–KS4 | Quick-select param: **HITS / KEY / SCALE / SPREAD / VEL** |
| KS5 | Toggle **auto-reroll** (green LED) |
| KS6 | Next **track** |
| KS7 | Next mode |
| Encoder turn | **Stage** ± on the selected param (VEL/GATE/CHANCE use coarse steps) |
| Encoder click | **REROLL** — seed++, regenerate NOW (never staged) |
| Button 10 | ENTER → **SETUP** (all 12 params) |
| Button 11 | **NAP** toggle for the current track |
| Button 12 | **COMMIT** staged edits → regenerate once |

Screen: header (`PLAY T1 SEQ1/4 RUN`), selected param + value in large text,
`pos t/n notes N` (playhead position / note count), flags line
(`nap auto staged`), two hint lines.

---

## 4. SETUP — the full parameter grid

ENTER from PLAY. All 12 params in a two-column list with a `>` cursor; same
staging rule as PLAY.

| Input | Action |
|---|---|
| KS0 / KS1 | Cursor prev / next param |
| KS5 / KS6 | Auto-reroll / track (same as PLAY) |
| Encoder turn | Stage the highlighted param |
| Encoder click | Reroll |
| Button 9 | BACK → compact PLAY |
| Button 12 | COMMIT |

---

## 5. STEP — per-note editing (live)

STEP edits the **stored notes of the active pattern** directly — immediate,
no staging, no regeneration. One step cursor moves along the pattern's step
grid; one note per step is shown/edited (the first event starting exactly on
that step).

| Input | Action |
|---|---|
| Encoder turn | Move the **step cursor** (`st n/len`) |
| Encoder click | Cycle the **edit field**: PITCH → LEN → VEL |
| KS0 | **ADD** a note at the cursor (C4, one step long, vel 100) — skipped if the step is occupied |
| KS1 | **DELETE** every note at the cursor step |
| KS2 / KS3 | Note at cursor: octave down / up |
| KS4 / KS5 | Note at cursor: edit field − / + (pitch ±1 semitone, len ±1 step, vel ±5) |
| KS6 | Next track |

Screen: `st n/len`, the field name and its value (`PITCH C4`, `LEN 6t`,
`VEL 100`).

---

## 6. SEQ — sequences & pattern slots

A **sequence** is one "scene": which pattern slot each track plays. There are
4 sequences; **SEQ k = slot k on every track** (Hermod's "SEQ1 = all P1"), but
slots can be changed per track afterwards. Switching a sequence (or a slot)
flushes the affected track's sounding notes first, then selects the new
pattern — seamless.

| Input | Action |
|---|---|
| KS0–KS3 | Select **track** 1..4 to edit (orange row) |
| KS5 | Toggle that track's **mute** in the CURRENT sequence only (`m` marker) |
| Encoder turn | Change the selected track's **pattern slot** (P1..P4, live) |
| Encoder click | Switch to the **next sequence** (1..4, wrap) |

Screen: one row per track, `T1:P1` (e.g. track 1 playing pattern 1), `m` if
muted in this sequence.

---

## 7. Performance features

| Feature | Description | Interaction |
|---|---|---|
| NAP | Mutes a track for 2 of its OWN loops, wakes it for 2, alternating. The generator keeps evolving underneath, so the track wakes up *changed* (PPW Loop Nap/Wake). | Button 11 (current track). Red LED blinks while armed+awake, steady while napping. Flag `nap`/`NAP!` on screen. |
| Auto-reroll | Every 2 loops the track's seed increments and the pattern regenerates — a slowly mutating arp. | KS5 in PLAY/SETUP. Green LED. Flag `auto`. |
| Reroll | One-shot regenerate now (seed++). | Encoder click in PLAY/SETUP. |
| CHANCE | Live probability filter — thin a track to a ghost of itself without touching the stored pattern. | Select param 12, turn encoder. |
| Mute | Sequence-local mute (each of the 4 sequences remembers its own mutes). | SEQ mode, KS5. |

---

## 8. In the engine but INVISIBLE (no UI yet) — candidates for the new GUI

These run today but cannot be reached from the control surface. Prime
material for menu pages / performance knobs.

- **RANGE effect** — per-track live clamps: pitch min/max, velocity min/max,
  length min/max. Defaults transparent. Ideal live "window sweep" knobs
  (compress a part into a narrow band live).
- **RANDOM jitter** — pitch ±semitones, velocity ±, octave ± per note, on top
  of CHANCE. Humanize/octave-spray knobs.
- **Loop region** — every pattern has loopStart/loopEnd: play only a
  sub-window of the pattern (natural live "A/B"/half-loop builds). No UI.
- **Song chain** — sequences can be chained into a song (`songAdd/remove/
  clear/advance`, bar-quantized advance via `syncBars`). Engine API complete;
  the SONG UI page was cut for RAM.
- **Tracks 3–4** — the engine supports 4 tracks; the device boots 2 for heap
  budget. A menu could raise this once RAM allows.
- **Panic / all-notes-off** — `engine.panic()` flushes all voices; not wired
  to any control.
- **4 sequences × per-track slots** — only reachable one sequence at a time;
  no overview/copy.

## 9. Not built (roadmap)

- MIDI-in **recording** (M3): play notes in, quantized to the step grid,
  edit them (STEP mode is already the editor).
- **Save/load + RAM swap** (M4): patterns persist as Lua chunks; inactive
  slots swap to file.
- **Per-pattern fx values** — Hermod-style global-vs-pattern parameter
  override.
- Generator extras: chord-per-hit, random-walk pitch, live EUCLID effect.
- Pattern copy between slots.

---

## 10. LED reference (every 4th frame)

| Element | Meaning |
|---|---|
| KS7 | Mode colour: orange PLAY / cyan STEP / purple SEQ |
| KS0–4 (PLAY) | White = selected quick param, dim = available |
| KS0–3 (SEQ) | White = selected track |
| KS5 | Green = auto-reroll armed; red (SEQ) = track muted |
| Button 11 | Red blinking = nap armed, steady red = napping |
| Button 12 | Orange blinking = staged edits pending (dirty) |

## 11. GUI design constraints (why the GUI is text)

The device heap is ~130 KB with a ~91 KB boot baseline; all 5 code bundles
must stay ≤ ~10 KB each as plain text. What is cheap: `draw_text_fast`,
simple filled rectangles, one `draw_swap` per frame, ≤20 fps. What is
expensive: per-note piano-roll rectangles every frame (the old GUI), LED
updates every frame (already throttled to every 4th). A 1-row 16-cell step
strip with bar heights (seq-1 style) is roughly free and restores most
rhythm readability.
