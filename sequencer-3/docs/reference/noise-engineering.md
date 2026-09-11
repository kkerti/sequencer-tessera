# Noise Engineering sequencer reference

Distilled from:

- Mimetic Digitwolis product page: <https://noiseengineering.us/products/mimetic-digitwolis/>
- Mimetic Digitwolis manual: <https://noiseengineering.us/manuals/mimetic-digitwolis/>
- Gamut Repetitor manual: <https://noiseengineering.us/manuals/gamut-repetitor/>

This is the design reference for sequencer-3. It is deliberately a distillation,
not a copy: firmware internals, power, warranty, and marketing copy are dropped.
EURORACK-only features are flagged, with a note on the MIDI/VSN1 equivalent.

---

## Part 1 — Mimetic Digitwolis (MD2)

### 1.1 One-line concept

Four independent, configurable **lanes**. Each lane holds a sequence of 1..16
steps and outputs one of several signal *types*. Inputs (CV + triggers + MIDI)
are freely mapped onto lane functions. It is a "Cartesian performance
sequencer": the same 16 steps can be laid out as a 1-D line or as a 2-D grid and
navigated in X/Y.

### 1.2 Hardware / signal facts

- 4 CV outs, 4 CV ins (0..+5 V), 5 trigger ins (threshold ~+1.8 V), MIDI in+out
  (TRS type A). CV outs 0..+5 V; gates/triggers 0..+5.3 V.
- Internal clock **plus** external clock/transport.
- 24 save slots (4 banks x 6), full autosave on reboot.
- MIDI **in**: clock, transport, program change, scale editing, step editing.
- MIDI **out**: notes and CCs, per lane.

### 1.3 Two sequencer screens

- **Overview** — all four lanes at once.
- **Focus** — one lane in detail.
- **View** button swaps between them (also backs out of a submenu).
- From Overview, **Config** opens **Globals**. From Focus, **Config** opens the
  focused lane's **Lane** menu. The `1/2/3/4` buttons jump between Global and
  per-lane config.

*(sequencer-3 has no screen; these map to host/Lua-shell views.)*

### 1.4 Panel controls (the full control surface)

| Control | Role |
|---|---|
| **Edit encoder** | Turn = change highlighted item / coarse value; press = enter/select or enable edit; press+turn = fine value (coarse/fine per lane type). |
| **View** | Overview/Focus swap; back out of submenu. |
| **1 / 2 / 3 / 4** | Lane select. Overview: select/deselect lanes for editing (double-tap = solo). Focus: swap focused lane. Config: swap lane. |
| **Stop / Edit / Run** (3-pos switch) | Stop; Edit = edit playhead while playing; Run = normal. Run resets all lanes to step 1. |
| **Config** | Open/close config menu. |
| **Copy** | Copy + lane button, then destination lane button = copy a lane. |
| **Save / Load** | Open save/load menu (4 banks x 6 slots; also "Reset All"). |
| **Prev / Next** | Previous/next step (only for selected lanes on Overview). Press both = jump to step 1. |
| **Zero** | Set current step to min (or max if already min). |
| **Shred** | Set current step to a random value. |

That is **1 encoder + 13 buttons + 1 three-way switch**. VSN1 has 8 keyswitches
+ 4 small buttons (possibly dead) + 1 push-encoder. See Part 3.4 for the mapping
problem.

### 1.5 Combo moves (sequence-level editing)

| Combo | Effect |
|---|---|
| Save + 1/2/3/4 | Save all data to slot A/B/C/D. |
| Load + 1/2/3/4 | Load all data from slot A/B/C/D. |
| Load + rotate Edit | Ramp pattern in selected lanes. |
| Save + rotate Edit | Hill pattern in selected lanes. |
| Copy + rotate Edit | Raise/lower all step values in selected lanes. |
| Hold 1/2/3/4 + rotate Edit | Offset the sequence forward/back one step per click (destructive). |
| Hold 1/2/3/4 + press+rotate Edit | Change pattern length. |
| Load + Zero | All steps to min. |
| Load + Shred | Randomize all steps. |
| Save + Shred | Nudge current step. |
| Save + Load + Shred | Nudge all steps. |
| Next + Prev | Reset all lanes to step 1. |

### 1.6 Lane types

The first item in a lane's config selects its output type.

| Type | Meaning | MIDI out (when `Chan` != Off) |
|---|---|---|
| **CV** | Unquantized CV, modulation destination. | Stepped CC; CC number settable. |
| **Note** | Quantized CV, pitch sequencing (1 V/oct). | Note on + note off; octave offset + note length. |
| **Gate** | Binary, time-dependent (ADSR etc). | Note on at active step, note off at inactive step. |
| **Trig** | 5 ms pulse on active steps (drums). | Note on immediately followed by note off. |
| **Qtiz** | Quantizer for *external* CV; can also emit MIDI notes from analog in. | Note matching CV, length matching gate input. |

**Key insight for seq-3:** MD2 stores essentially *one value per step per lane*.
Pitch lives on a Note lane; duration is mostly a lane-global (`Time`) and gate
is a separate lane. seq-3 wants per-step pitch + velocity + length, which is a
MIDI-native enrichment, not a copy of MD2.

### 1.7 Per-lane config, grouped by the manual's tabs

#### Step tab (navigation and addressing)

- **Dims**: `16x1`, `8x2`, `5x3`, `4x3`, `4x4` — the layout and therefore the
  step max and navigation scheme. Default `16x1`.
- **Advn** (`16x1`) / **XAdv** + **YAdv** (multi-dim): trigger source mapped to
  advancing one step.
- **Prev** (`16x1` only): trigger source to move back one step.
- **Rset**: trigger source; after a reset, lane jumps to step 1 on the *next*
  advance (so simultaneous reset+advance still lands step 1).
- **Rand**: trigger source; jump to a random step.
- **Ofs** (`16x1`) / **XOfs** + **YOfs**: CV source that addresses the step
  (navigate with an LFO/sequencer). `16x1` has one; multi-dim has X and Y.

#### Sequence tab

- **Len** (`16x1` only): sequence length (1..16), also CV-mappable.
- **Div**: clock divider 1..16 applied to all advance triggers, CV-mappable.
- **Shift**: trigger source; on each trigger the whole sequence shifts forward
  by **Amt** steps.
- **Amt**: number of steps for Shift.

#### Output tab

- **Slew**: smoothing between values.
- **VMin / VMax** (CV) or **Min / Max** (Note): output range clamp.
- **Scale** (Note/Qtiz): scale selection submenu (see 1.10).
- **Scl**: CV input that scales lane output.
- **Ofs**: CV input that offsets lane output.

#### MIDI tab

- **Chan**: output channel; `Off` disables MIDI. For Note/Qtiz, also the input
  channel.
- **cc i**: first CC of the contiguous block that maps to steps 1..16 (default
  `4..19`). Incoming CCs set step values directly.
- **cc o** (CV lane): CC the sequence is emitted on.
- **Octv** (Note/Qtiz): starting octave.
- **Mode** (Note): incoming MIDI note behavior — `edit` (assign note to current
  step), `hold` / `time` / `toggle` (build the quantizer scale from a keyboard).
- **Note** (Gate/Trig): which MIDI note to emit.
- **Time** (Note/Trig): MIDI note length in ms.

#### Modify tab (destructive edits, all trigger-mapped)

- **Read** + **Inp**: on trigger at `Inp`, read CV at `Read` and write to the
  current step (stepped CV recording).
- **Zero**: trigger sets current step to min.
- **Shrd**: trigger sets current step to a random value.
- **Nudg**: trigger sets current step to a slightly different value.
- **Dist**: CV-controllable direction/bias of Nudge (>8 bias up/on, <8 bias
  down/off; for Gate/Trig it biases probability on/off).

### 1.8 Trigger sources (the routing vocabulary)

Any trigger destination can be sourced from:

- `Off`
- `Trig In R` / `Trig In 1-4` — the physical trigger jacks.
- `CV A-D` — a CV jack repurposed as a trigger.
- `Tprt 1 / 2 / 4 / 8 / 16` — the transport clock at whole / half / quarter /
  8th / 16th note.
- `Out 1-4` — another lane's output crossing the trigger threshold. **This is
  lane-sequences-lane.**

### 1.9 Transport

Global setting `Transport`:

| Mode | Behavior |
|---|---|
| `None` | No transport; lanes advance only from direct trigger mappings. |
| `MIDI` | Follow MIDI clock + transport. MIDI Start resets lanes to step 1. |
| `DIN` | DIN sync (Run + 24 PPQN Clk). |
| `Gate` | Follow clock while a Run gate is high (4 PPQN suitable). |
| `Trig` | Toggleable: first trigger runs, next stops (Run + 4 PPQN Clk + Rst). |
| `Clock` | Internal clock: `BPM` + optional MIDI clock out (`Clck`). |

- Transport events appear as trigger sources (`Tprt...`).
- Lanes can be advanced by MIDI by mapping `Advn` to a `Tprt` tap.
- Resets to step 1 on transport start.
- If transport is MIDI/DIN/Gate/Trig and stopped, lanes stop; quantizers hold.

### 1.10 Scales (Note + Qtiz lanes)

Scale editor types:

- **Keys** (12-TET): toggle individual notes on a one-octave keyboard; Shred
  generates a random scale.
- **Diaton** (12-TET): Root + Mode preset, editable.
- **Symmet** (12-TET): Slonimsky-style algorithmic; `Div` (notes), `Sub`
  (interval for second layer in semitones), `Zig` (`UD`/`DU`).
- **Equal** (microtonal): divide octave into `Tet` = 1..24 equal steps.
- **Ratio** (microtonal): Partch-limit just-intonation from a tonality diamond.

A new scale is applied to existing pitch lanes immediately (performance move).

### 1.11 Presets and MIDI

Factory presets (starting points, all editable):

- **CV x 4** — 4 CV lanes; Trig In R resets all; Trig In 1-4 advance lanes 1-4;
  CV In A-D address lanes 1-4.
- **Null** — 4 CV lanes, nothing mapped.
- **Pitch x 4** — as CV x 4 but 4 Note lanes, major scale.
- **Quant** — 4 quantizer lanes; Trig In 1-4 + CV In A-D mapped per lane.
- **Notes** — lanes 1/3 Trig, lanes 2/4 Note; Trig In 1 advances 1+2, Trig In 2
  advances 3+4; CV In A/B address.
- **4 x 4** — homage to the original: 4 CV lanes sharing mappings; Trig In R
  resets, Trig In 1 = X advance, Trig In 2 = Y advance, Trig In 3 = random jump;
  CV In A = X address, CV In B = Y address.
- **Voice** — self-contained single voice: lane 1 Trig advanced by internal
  clock; lanes 2-4 advanced when lane 1 fires; lane 2 Note; lanes 3/4 CV.
  *(This is the closest to sequencer-3's target shape.)*

MIDI:

- 24 save slots load via Program Change `0..23`; manual load also emits the PC.
- `MIDI: Thru`, `Dump` (SysEx), `Log`, global `Chan` for PC.
- CV/Note steps mapped to a contiguous CC block (`4..19` default) for a
  faderbank; incoming CCs edit steps directly.

### 1.12 Design-note takeaways

- The original MD is ~1500 lines of C; MD2 is ~8192 lines. The complexity is in
  configurability (every input mappable to every function).
- Hard real-time polling: consistent ~1 ms input→output latency. Screen
  rendering was split into 64 steps because even clearing the framebuffer blew
  the budget — **render cost, not just memory, is a hard constraint.**
- External flash added for fast save/load because on-MCU flash could not meet
  the original's quick save/load; screen and flash time-share pins via an async
  state machine.
- Design goal: configurable inputs + a UI per output semantic. The quantizer
  was an emergent feature of that generality.

---

## Part 2 — Gamut Repetitor

### 2.1 Concept

A four-channel **random quantized voltage generator** with looping, range, key,
and scale controls. Turn `Length` up and feed triggers to generate fresh random
voltages; turn `Length` down to loop the last N values. Designed to sound
musical at every switch position.

*"Quad random, highly controllable, quantized-voltage generator and generative
CV sequencer."*

### 2.2 Controls

| Control | Role |
|---|---|
| **Root** | Root note of the scale. |
| **Spread** | Deviation from root, `0..24` semitones. |
| **Length** | Loop length. Fully CW = keep generating (infinite). Turn down to loop the most recent values. |
| **Down/Up** | Shifts the range around the root: max = all values above/at root up 2 oct; min = all values at/below root down 2 oct. |
| **Reset** | Trigger in: resets all 4 channels to the loop start on the next trigger (if Length < infinite). |
| **Reset (hold)** | Long-press toggles Trig Outs between **passthrough** and **rhythm-generation** mode (randomized repeating trigger patterns). |
| **Maj/Min/Sym** | Top scale switch. |
| **Flavor** | Center scale switch. |
| **Count** | Bottom scale switch (number of notes). |
| **M/M/S jack** | CV control of the top Maj/Min/Sym switch. |
| **Scale jack** | CV over all positions of Flavor + Count. |
| **In 1-4** | Trigger ins: advance the loop or generate a new random voltage. Normalled top→bottom (In 1 advances all if nothing patched below). |
| **Trig Out 1-4** | Trigger passthrough by default; rhythm-generation mode as above. |
| **CV Out 1-4** | Generated 1V/8va voltages. |

- **Length LED colors**: divisible by 2 = red, by 3 = blue, both = purple.
- **Scales**: 27 combinations across the three switches, chosen so a one-position
  change stays musical. Root assumed C; `L/C/R` denote switch positions
  top→bottom (e.g. `CRL`).
- **Patch tutorial shape**: clock/trigger → In 1; CV Out 1 → voice 1V/oct; Trig
  Out 1 → voice trigger. Length max → explore Root/Spread/Down-Up/scales →
  turn Length down to lock a loop. Other channels = more randomized sequences.

### 2.3 Why it matters for sequencer-3

Gamut is the **generative** counterpart to MD2's **programmed** steps:

- No stored steps: values are *generated* by (Root, Spread, Down/Up, scale, RNG)
  and then *frozen* by reducing Length into a loop buffer of up to N values.
- Once frozen, it is just a 1-D loop that advances on triggers — i.e. exactly a
  lane's step array, filled by a generator instead of by hand.
- Its trigger outputs are a rhythm generator — a natural **Trig lane** whose
  content is patterns rather than musical steps.

So a "Gamut lane" in sequencer-3 is a **Note lane whose values are produced by a
generator and captured into the same 16-slot step array**, with parameters
`root, spread, downUp, length, scale, seed`. It needs no new storage model. The
rhythm-generation part is a separate **Trig lane generator** (probability/pulse
patterns), which overlaps conceptually with MD2's Nudge/Dist and Shred.

---

## Part 3 — Mapping to Grid VSN1 + MIDI (analysis)

### 3.1 Signal reality

VSN1 is a programmable **MIDI controller** with a screen, 8 keyswitches, 4 small
buttons (reported dead on this unit), and one push-encoder. It has **no CV/gate
outputs**. Eurorack is reached via an **Expert Sleepers FH-2** doing MIDI→CV,
expandable with **FHX-8CV/8GT** modules (8 outputs each). Therefore every
"voltage" concept must first become MIDI.

- MD2 CV out → MIDI **CC** (7-bit; 14-bit via CC pairs for higher resolution).
- MD2 Note out → MIDI **Note** (+ velocity + length).
- MD2 Gate out → MIDI **Note** held across active steps.
- MD2 Trig out → MIDI **Note** on/off pulse.
- MD2 CV/trigger **inputs** → MIDI **CC** / **Note** inputs, or messages from
  another lane inside the engine.

### 3.2 EURORACK-only vs MIDI-expressible

| MD2 feature | MIDI/VSN1 equivalent | Verdict |
|---|---|---|
| CV outs 0-5 V | CC (or 14-bit CC pair) | Keep as Mod lane. |
| Pitch CV 1V/oct | MIDI note number + FH-2 | Keep as Note lane. |
| Trigs/gates | MIDI note on/off | Keep as Trig/Gate lane. |
| CV ins as trigger/address | MIDI CC/Note-in mappings | Keep, remapped. |
| DIN sync, Gate/Trig transport | MIDI clock/transport primarily | Drop DIN; keep MIDI + internal. |
| Physical trigger jacks | MIDI notes / virtual lane triggers | Keep as source enums. |
| Slew | CC ramping / glide (could be a per-step or per-lane value) | Optional later. |
| Qtiz (external CV quantizer) | Quantize incoming MIDI notes | Reduced value; likely defer. |
| MPE | FH-2 can expand MPE to CV | New; design output layer for it. |

### 3.3 MPE (multi-polyphonic expression) — what it means here

MPE = one MIDI channel per note (member channels 2-16, master ch 1), with
per-note pitch bend, aftertouch, and CC74. For FH-2, each member channel can map
to an independent voice with its own pitch/gate/expression.

Implication for the engine: a *voice* is (channel, pitch, velocity, length,
expression). The simplest useful model is **one lane = one voice = one member
channel**, which matches MD2's one-value-per-step-per-lane DNA. Per-step fields
could then drive bend/aftertouch later without changing storage. Recommend MPE
as an **output-layer option**, not a core data-model change.

### 3.4 The control-surface problem

MD2 drives everything with 1 encoder + 13 buttons + a 3-way switch. VSN1 offers
8 keyswitches + 4 small buttons + 1 encoder, and the small buttons are
unreliable. So a literal 1:1 port is impossible; the control layer must be
**modal and/or combo-based**, e.g.:

- Keyswitches select lanes / pages; encoder edits; a hold-modifier promotes the
  remaining MD2 verbs (Zero, Shred, Copy, Prev/Next, Save/Load, transport).
- Because sequencer-3 is headless-first, the *same* semantic actions must be
  callable from the Lua shell and from a future button adapter.

This argues for a **Core action API** (named commands) with the button map as a
thin adapter — the "clean boundary" the brief asks for.

### 3.5 Can these sequencers be used? (open findings)

- **MD2 yes.** Its lane model maps cleanly: Note→note, CV→CC, Trig/Gate→note
  pulses. The genuinely eurorack-only parts (DIN, Qtiz) are dropped; CV
  addressing (`Ofs`) is re-expressed as a MIDI **value source** that addresses
  the playhead, and `Shift` becomes a trigger-driven `rotate`.
- **Gamut yes, as a generator.** It fits the same 16-slot lane array; it is
  "generate then freeze into steps," needing only a seeded RNG + quantizer.
- **Lane-as-modulator yes.** MD2's `Out 1-4` trigger source is precedent for
  lane→lane routing; the MIDI version routes a lane's value to another lane's
  parameter (advance, div, len, root, offset).
- **Open:** how much of MD2's general input→function mapping matrix to
  reproduce, versus a fixed useful subset. This is a scope decision.
