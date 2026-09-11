# Lanes only: no tracks, patterns, or sequences

Status: accepted

seq-3 models four flat **lanes**, each holding up to 16 steps and one config
block. There are no tracks, patterns, sequences, or racks (seq-2's composition
layers). Lane-to-lane interaction happens purely through source enums
(`LANE(n)`).

Considered: reusing seq-2's track→pattern→sequence composition. Rejected because
that complexity is the thing seq-3 exists to shed; the target is quick, live,
16-step musical ideas, and flat lanes give a predictable RAM shape.
