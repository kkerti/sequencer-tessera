# ACTION_API.md — sequencer-3

The full named action API. This is the single control surface: the Lua shell and
the future Grid GUI both call these. Implementing a module means implementing
its verbs here.

Naming follows `docs/NAMING.md`: full readable words at the boundary; compact
enums only internally.

## Conventions

- `lane` is **1-based** (1..4). `step` is **1-based** (1..16).
- Sources are strings; see `docs/NAMING.md` for the vocabulary and the
  trigger-source vs value-source distinction.
- Types: `"note" | "mod" | "trig" | "gate"`.
- Dimensions: `"16x1" | "8x2" | "5x3" | "4x3" | "4x4"`.
- Values: pitch 0..127, velocity 1..127, step length in 24-PPQN ticks, mod value
  0..127, gate 0/1, division 1..16.
- None of these run on the pulse hot path; they may allocate/validate freely.

## Lifecycle / clock

```lua
seq3.init{ lanes = 4, channel = 1 }
seq3.start()
seq3.stop()
seq3.reset()                 -- reset all lanes to step 1
seq3.onPulse()               -- one external MIDI clock pulse (0xF8)
seq3.tick()                  -- one pulse from the host's internal timer
-- The host timer owns BPM; the engine has no BPM (ADR-0004).
```

## Lane configuration

```lua
seq3.setType(lane, kind)
seq3.setDimensions(lane, layout)
seq3.setLength(lane, n)              -- sequence length, 16x1 only
seq3.setDivision(lane, n)            -- 1..16
seq3.setChannel(lane, channel)
seq3.setController(lane, cc)         -- Mod lane
seq3.setScale(lane, mask, root)
seq3.setRange(lane, min, max)        -- Note: pitch range; Mod: value range

-- trigger sources
seq3.setAdvanceSource(lane, source)
seq3.setXAdvanceSource(lane, source)
seq3.setYAdvanceSource(lane, source)
seq3.setResetSource(lane, source)
seq3.setRandomSource(lane, source)
seq3.setPreviousSource(lane, source)
seq3.setShiftSource(lane, source)    -- trigger rotates by setShiftAmount
seq3.setShiftAmount(lane, steps)

-- value sources (address the playhead; see below)
seq3.setAddressSource(lane, source)
seq3.setXAddressSource(lane, source)
seq3.setYAddressSource(lane, source)
```

## Step editing

```lua
seq3.setPitch(lane, step, note)
seq3.setVelocity(lane, step, v)
seq3.setStepLength(lane, step, ticks)
seq3.setValue(lane, step, v)         -- Mod lane
seq3.setGate(lane, step, on)         -- Trig/Gate lane
seq3.setPosition(lane, step)         -- manual playhead position
```

## Sequence operations (the MD2 combos)

```lua
seq3.shred(lane)                     -- randomize the current step
seq3.shredAll(lane)                  -- randomize all steps
seq3.zero(lane)                      -- current step to min
seq3.nudge(lane)                     -- slight random change to current step
seq3.rotate(lane, steps)             -- positional rotate (MD2 Shift/manual)
seq3.offset(lane, delta)             -- value offset (all steps +/- delta)
seq3.ramp(lane)                      -- ramp pattern
seq3.hill(lane)                      -- hill pattern
seq3.boost(lane, factor)             -- raise/lower all values (MD2 Copy+turn)
seq3.copy(from, to)                  -- copy one lane to another
seq3.generate(lane, opts)            -- fill a lane (see Generators below)
```

## Presets / introspection

```lua
seq3.loadPreset(data)                -- apply a preset table in place
seq3.get(lane, field)
seq3.state(lane)                     -- read-only snapshot for a GUI
seq3.dump()                          -- full engine snapshot
seq3.set(lane, field, v)             -- generic escape hatch
```

Slot files are read and written by the `persist` module
(`persist.load(path)` / `persist.save(path)`), keeping IO out of the Core.

## Addressing (value sources)

When an address value source updates, the playhead is set to
`floor(value * usedSteps)`, clamped to the lane's used steps. A `transport.*`
source is not meaningful here; use `external.N` (a CC value) or `lane.N`
(another lane's current value). This is MD2's `Ofs`/`XOfs`/`YOfs` behaviour:
navigate the sequence with an external signal.

## Internal routing

`lane.N` as an advance/reset/random/shift trigger fires when lane `N` pulses
(Trig/Gate) or its value crosses a threshold (Note/Mod). As a value source it
reads lane `N`'s current value. The enum is wired from the start; behaviour
lands after the 4-lane core.

## Generators

`seq3.generate(lane, opts)`:

- **`kind = "gamut"`** (default): fill the lane around `base`, quantized to the
  lane's scale. `spread` (semitones), `downUp` (0 = all below base .. 127 = all
  above), `velSpread`, `gateSpread`, `seed`. On a Trig/Gate lane, `spread`
  reads as density percent.
  - `live = true`: regenerate the playhead step on every advance (endless).
  - `fill = false`: configure only; don't fill the steps now.
- **`kind = "euclid"`** (alias `rhythm`): fill a Trig/Gate lane with `hits`
  onsets across the steps, optional `rotate`.

Deterministic for a given `seed`; alloc-free, so `live` is safe on the pulse
path.

## External MIDI mapping (host convention)

The Mac adapter (`src/io/midi_in.lua`) maps incoming MIDI to external sources:

- note `36 + n` -> `external.n` trigger (n = 0..7)
- CC `20 + n` -> `external.n` value   (n = 0..7)

The Core only ever sees `external.N`; the mapping is an adapter concern, so the
Grid adapter can choose its own.

## Deliberately not here yet

- **Parameter modulation** — a value source driving division / length / scale /
  root / range. Deferred decision; not in the v1 API.
- **MPE expression targets** — output-layer flag; per-lane expression source TBD.
