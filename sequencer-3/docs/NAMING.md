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

Every source is a **trigger source**: it fires on a transport tap. Used by
advance / xAdvance / yAdvance / reset / random / previous / shift. (Value
sources, `external.N` and `lane.N` were cut for device RAM in 2026-10; they
are in git history.)

| Public string | Kind | Meaning |
|---|---|---|
| `"off"` | trigger | disabled |
| `"transport.whole"` | trigger | whole note |
| `"transport.half"` | trigger | half note |
| `"transport.quarter"` | trigger | quarter note |
| `"transport.eighth"` | trigger | eighth note |
| `"transport.sixteenth"` | trigger | sixteenth note |

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

Numeric values live in `src/core/sources.lua` (0..5); the strings in
`src/core/source_names.lua`, which loads lazily. Keep all three in sync.

## Abbreviation lookup

| Abbreviation | Expansion | Where it is allowed |
|---|---|---|
| `BPM` | beats per minute | Public API (`setBPM`) — an acronym, not a shortening. |

Avoid in public names: `chan` (use channel), `div` (division), `cc`
(controller), `vel` (velocity), `dims` (dimensions). The glossary may still use
the MD2 term as a *concept*, but the API spells it out.
