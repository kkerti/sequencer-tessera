# One pulse path at 24 PPQN

Status: accepted

The engine has a single internal resolution of 24 PPQN. External MIDI clock
(`0xF8`) and the internal timer both call the same `onPulse()`; the transport
derives named taps from a position counter — `transport.whole` = 96 pulses,
`.half` = 48, `.quarter` = 24, `.eighth` = 12, `.sixteenth` = 6. The engine
itself has no BPM.

Considered: a BPM-relative scheduler. Rejected because MIDI clock is natively 24
PPQN (so no resampling is needed for tight sync) and a single pulse entry point
keeps the engine agnostic about whether time comes from the Mac, MIDI, or a
device timer.
