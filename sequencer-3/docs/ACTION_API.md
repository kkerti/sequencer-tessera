# ACTION_API.md — sequencer-3

The full named action API. This is the single control surface: the Lua shell and
the future Grid GUI both call these. Implementing a module means implementing
its verbs here.

Naming follows `docs/NAMING.md`: full readable words at the boundary; compact
enums only internally.

## Conventions

- `lane` is **1-based** (1..4). `step` is **1-based** (1..16).
- Sources are strings (`"off"` or a `transport.*` tap) or their enum numbers;
  see `docs/NAMING.md`.
- Types: `"note" | "trig"`. Mod and Gate were folded in for device RAM (2026-10):
  a Trig step with a long `stepLength` is a gate, and modulation is a chromatic
  Note lane whose pitches an FH-2 turns into CV. `setType` still accepts
  `"mod"` / `"gate"` (as note / trig) so old slots load.
- Dimensions: `"16x1" | "8x2" | "5x3" | "4x3" | "4x4"`.
- Values: pitch 0..127, velocity 1..127, step length in 24-PPQN ticks, gate
  0/1, division 1..16. Velocity and step length apply to Note and Trig steps.
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
seq3.setMidiNote(lane, note)         -- Trig lane's note
seq3.setScale(lane, mask, root)
seq3.setRange(lane, min, max)        -- pitch range (output clamp, Shred/Random range)

-- trigger sources
seq3.setAdvanceSource(lane, source)
seq3.setXAdvanceSource(lane, source)
seq3.setYAdvanceSource(lane, source)
seq3.setResetSource(lane, source)
seq3.setRandomSource(lane, source)
seq3.setPreviousSource(lane, source)
seq3.setShiftSource(lane, source)    -- trigger rotates by setShiftAmount
seq3.setShiftAmount(lane, steps)
```

## Step editing

```lua
seq3.setPitch(lane, step, note)
seq3.setVelocity(lane, step, v)
seq3.setStepLength(lane, step, ticks)
seq3.setGate(lane, step, on)         -- Trig lane
seq3.setPosition(lane, step)         -- manual playhead position
```

## Sequence operations (the MD2 combos)

```lua
seq3.shred(lane)                     -- randomize the current step
seq3.randomize(lane)                 -- Random: shred every used step at once
seq3.zero(lane)                      -- current step to min
seq3.rotate(lane, steps)             -- positional rotate (MD2 Shift/manual)
seq3.copy(from, to)                  -- copy one lane to another
```

## Presets / introspection

```lua
seq3.loadPreset(data)                -- apply a preset table in place
seq3.get(lane, field)
seq3.state(lane)                     -- read-only snapshot for a GUI
seq3.set(lane, field, v)             -- generic escape hatch
```

### Slots

Slot files are read and written by the `persist` module, keeping IO out of the
Core:

```lua
persist.save(path)          -- write the live engine state
persist.load(path)          -- read a file and apply it through loadPreset
persist.saveSlot(n)         -- presets/NN.lua
persist.loadSlot(n)
persist.slotPath(n)         -- "presets/NN.lua"
persist.SLOTS               -- 24
```

A saved file is a Lua chunk of exactly the same shape as the hand-written
`presets/` files — `return { version = 1, lanes = { ... } }` — so a saved slot
stays readable and hand-editable, and any preset is a valid save file.

**Save is lossless against load**: every field `loadPreset` reads, `save`
writes, and `load(save(x)) == x` for all lane settings. Guaranteed by a
round-trip test in `tests/run.lua`. Specifics:

- Sources are written as their public names
  (`advanceSource = "transport.sixteenth"`), and only when routed.
- Derived fields are **not** stored: `width`/`height` are rebuilt from `dims`,
  and `scaleMask` from `rawScaleMask` + `root`.
- Live playback state is **not** stored: `position`, `activeNote`, `divCount`
  and friends. Loading never moves the playhead.
- Step arrays are written for the lane's own type, plus any other array holding
  non-default data — so switching a lane's type doesn't drop the data behind it.

The terminal harness exposes both over the stdin protocol as `SAVE <slot>` /
`LOAD <slot>`; `tools/bridge.py` forwards lines typed in its terminal, so a
slot can be saved or recalled mid-session.

## Cut for device RAM (2026-10)

Removed to make the text GUI fit the VSN1 (measured in `dist/README.md`):
lane->lane routing (`lane.N` sources), external MIDI sources (`external.N`,
`triggerExternal`, `setExternalValue`, the Mac `io/midi_in` mapping), value
addressing (`setAddressSource` / X / Y), the Mod and Gate lane types, and the
Gamut / Euclid / live generators (`generate`; `randomize` replaces them). All of
it is in git history before the cut.

## Deliberately not here yet

- **Parameter modulation** — a value source driving division / length / scale /
  root / range. Deferred decision; not in the v1 API.
- **MPE expression targets** — output-layer flag; per-lane expression source TBD.
