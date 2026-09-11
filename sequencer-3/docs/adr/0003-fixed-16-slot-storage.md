# Fixed 16-slot storage per lane

Status: accepted

Each lane is a fixed record built once at init, and step values live in
preallocated arrays of exactly 16 (`pitch/vel/len`, `value`, or `gate`). Values
are stored linearly 0..15; `dims` maps (x,y) to an index. There is no dynamic
event store.

Considered: seq-2's growable structure-of-arrays event store with variable tick
offsets. Rejected because 16 steps is a hard maximum, variable-length
polyphonic events are unnecessary here, and fixed storage gives predictable RAM
and a zero-allocation pulse path.
