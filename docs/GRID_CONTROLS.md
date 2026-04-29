### Overview

A hardware module is built up from control elements. Each control element has number of events, defined under the control element types. The events can have 880 character long script space, where lua code can be written. The events are initialized on the control elements first as indexed, the uility system event is lats. The events can call various functions, scoped to themselves, with `self:` or scoped elsewhere. The docs grid-screen-buttons-reference should contain more info.

### Control elements
Shared events across control elements:
- init: runs code, when page is loaded, module booted
- timer: can be started to do a delayed code run, can be retriggered when calling itself

#### Buttons
Events:
- button: runs every time the user physically interacts with the control element, pressing and releasing it.

#### Endless
This is the large endless jog wheel.
Events:
- button: runs every time the user physically interacts with the control element, pressing and releasing it.
- endless: the rotation event, either going up or down

#### Screen
Events:
- draw: this is basically a setInterval, where the code here runs every render cycle. 

The gui manipulating `draw_...` configurations alter the screen's buffer, which is then rendered on `draw_swap()` call. The draw event is usually the place, where we place a `draw_swap()`.

### Scopes
On the control elements, we can access a control elements scope: `self`. Globally no a module, we can access a global scope. Local also works under events for one-off calculations. 


### VSN1 hardware controller
The VSN1 hardware controller has 4 small buttons under the 320x240px LCD screen. It features a jog-wheel, endless and clickable. There are 8 normal keyswitch buttons.
