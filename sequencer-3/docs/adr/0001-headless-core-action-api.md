# Headless Core behind one action API

Status: accepted

The engine is a pure, headless Lua Core with no drawing, MIDI, or device
knowledge; every control path goes through a named action API, and host adapters
(stdio→MIDI on Mac now, Grid VSN1 buttons/screen later) are thin translators.
This keeps musical logic testable and identical across Mac and device, and lets
the GUI be built later without rewriting the engine.

Considered: building screen-first or coupling Core directly to drivers (the
seq-1/seq-2 path). Rejected because it makes the engine untestable in isolation
and bakes UI assumptions into musical code.
