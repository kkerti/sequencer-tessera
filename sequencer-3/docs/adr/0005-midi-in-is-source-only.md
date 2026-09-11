# MIDI in is a source, never an editor

Status: accepted

Incoming MIDI is exposed **only** as routable sources: **trigger sources**
(note-on and thresholded CC lines) used by advance/reset/random/previous/shift,
and **value sources** (a CC value) used by step addressing. There are no
MD2-style editor mappings: no CC step-writing, no note-edit, and no Program
Change preset loading. Presets are loaded through the action API. Using a value
source to modulate a lane parameter (division, length, scale, root, range) is a
separate, **deferred** decision.

Considered: reproducing MD2's MIDI editing matrix. Rejected because a host Grid
controller already provides editing and preset control through the action API,
making in-engine editing redundant; the musically interesting use of MIDI in is
as a source that makes the sequencer react to a eurorack system.
