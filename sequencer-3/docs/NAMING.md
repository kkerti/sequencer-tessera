# NAMING.md — sequencer-3

The naming contract. Code size matters on the Grid, but **not at the cost of
obscurity**. Public names are readable full words; only internal hot-path enums
are compact, and this file is the lookup.

## Principles

1. **Public** (action API verbs, source strings, preset files, docs): full,
   readable words. Optimise for a human typing in a Lua shell.
2. **Internal** (hot-path structs and enums): compact integer constants are
   fine. Field names on non-hot-path structures stay readable words.
3. **Every abbreviation used anywhere appears in the lookup below.**
4. Public strings are parsed to internal enums **once, at the boundary** — never
   on the pulse path. Readability therefore costs no runtime.

## Action API verbs

Verb + full noun: `setChannel`, `setDivision`, `setController`, `setVelocity`,
`setStepLength`, `setPosition`, `setDimensions`, `setAdvanceSource`, …

Musical edit names keep the MD2 vocabulary because they are the instrument's
language: `shred`, `zero`, `nudge`, `rotate`, `ramp`, `hill`.

## Source vocabulary

Sources have two kinds:

- **trigger source** — fires on an event. Used by advance / xAdvance / yAdvance
  / reset / random / previous / shift.
- **value source** — carries a value. Used by address / xAddress / yAddress, and
  later by parameter modulation (deferred).

| Public string | Kind | Meaning |
|---|---|---|
| `"off"` | trigger | disabled |
| `"transport.whole"` | trigger | whole note |
| `"transport.half"` | trigger | half note |
| `"transport.quarter"` | trigger | quarter note |
| `"transport.eighth"` | trigger | eighth note |
| `"transport.sixteenth"` | trigger | sixteenth note |
| `"external.0"` … `"external.7"` | trigger / value | MIDI-in line |
| `"lane.1"` … `"lane.4"` | trigger / value | another lane's pulse / value |

A source may serve both roles where sensible: `external.N` can be thresholded
into a trigger or read as a value; `lane.N` can pulse or be read as its current
value.

## Internal enum map

The engine stores sources as small integers. Shortened enum identifiers are
allowed **here only**; this table is the translation.

| Enum identifier | Public string |
|---|---|
| `SRC_OFF` | `off` |
| `SRC_TRANSPORT_WHOLE` | `transport.whole` |
| `SRC_TRANSPORT_HALF` | `transport.half` |
| `SRC_TRANSPORT_QUARTER` | `transport.quarter` |
| `SRC_TRANSPORT_EIGHTH` | `transport.eighth` |
| `SRC_TRANSPORT_SIXTEENTH` | `transport.sixteenth` |
| `SRC_EXTERNAL_0` … `SRC_EXTERNAL_7` | `external.0` … `external.7` |
| `SRC_LANE_1` … `SRC_LANE_4` | `lane.1` … `lane.4` |

Numeric values are assigned when `transport.lua` is written; keep this table in
sync.

## Abbreviation lookup

| Abbreviation | Expansion | Where it is allowed |
|---|---|---|
| `EXT` | external | Prose only ("external/`EXT` source"). Public string is `external.N`. |
| `BPM` | beats per minute | Public API (`setBPM`) — an acronym, not a shortening. |

Avoid in public names: `chan` (use channel), `div` (division), `cc`
(controller), `vel` (velocity), `dims` (dimensions). The glossary may still use
the MD2 term as a *concept*, but the API spells it out.
