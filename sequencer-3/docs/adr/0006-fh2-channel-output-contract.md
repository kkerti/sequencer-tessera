# FH-2 channels are the output contract; expanders absorb the budget

Status: accepted

The engine emits MIDI notes and CCs on channels; it never models CV outputs.
Expert Sleepers FH-2 maps channels to physical outputs, and **FHX-8CV/8GT
expanders add 8 outputs each**, so the channel→output plan lives in deployment
config, not in the engine. A single FH-2 has 8 outputs and each Note voice costs
roughly pitch+gate, but the budget is a **preset-design** concern rather than an
engine cap. Presets should document the channels/voices they expect.

Considered: modelling an output budget in the engine. Rejected because it would
bake one person's current expander count into musical code.
