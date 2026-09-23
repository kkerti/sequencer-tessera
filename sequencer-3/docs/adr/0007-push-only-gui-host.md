# Push-only GUI host at two observation points

Status: accepted

The Grid GUI adapter (`GUI host`, see `CONTEXT.md` and `docs/SCREENS.md`) pushes
state into widgets only at the two moments state can change; it never polls or
diffs:

1. **Clock in** — the pulse is an observation point: on device the `midirx_cb`
   event script sees the MIDI clock before calling `seq3.onPulse()`; in
   grid-wasm the loop frame drives `seq3.tick()`. Either way the host pushes
   playhead markers right after the pulse.
2. **Action out** — every other state change originates from a host-initiated
   action call, so the host knows exactly which widgets to update at that
   moment.

The Core emits no events, and it stays that way (Core purity, ADR-0001): no
change-counters, no dirty broadcast, no `getStateVersion()`. Widget references
live in host-owned lookup arrays (`lane_views[lane][step]`), so targeting is a
direct array index, not a search. Dirty flags do change detection at render
time; change-detecting `set` makes repeated pushes free.

Considered: poll-and-diff (GUI snapshots `seq3.state()` every frame and diffs).
Rejected because the diff exists only to rediscover changes the host already
caused or witnessed — an extra snapshot allocation per frame and a second
source of truth, with no benefit the two observation points don't already
provide. Push-only also keeps the widget-set contract identical between device
(midirx_cb-driven) and harness (loop-driven) builds.

The pattern was validated in `layout-system/` (direct widget refs +
change-detecting `set`, commit 93cf1fe) before being adopted here.