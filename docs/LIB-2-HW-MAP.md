On the VSN1 hardware controller, we want to be able to select the following parameters:
- step
- track
- pattern
- snapshot
- cvB (note)
- cvA (vel)
- duration
- gate

Selecting any of the buttons should say for the endless knob, what it should control. The endless knob is in relative mode, so it emits 65 or 63, either up or down. It should be able to relatively control the above key parameters. The parameter ranges should be set, either a limited subset of how the manual writes for er-101 or use that sequencer for referene.

I want to write out the text for the controlled parameter and add a background for the currently active text with color red. When a step is not active, the color should be grey-white. On the screen, we surgically edit what is being drawn. We do not want to complete full screen updates as it may lag the device. 

What we see on the screen, should represent the give sequencer setting.

I want to be able to edit a sequence and play it with the buttons and the endless knob.

The screen at the first stage should show a grid of 4x2 blocks, where each block is the parameter above and it's value, simple as that.
