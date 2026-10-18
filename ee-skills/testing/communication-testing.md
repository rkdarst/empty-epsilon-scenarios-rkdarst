# Communication testing — asserting what the crew was actually told

A driver that only asserts state changes ("the scan flipped", "phase advanced")
proves the *world* works. It says nothing about the other half of the mission:
whether the *players* were told, in time, through a channel they can find. A
scenario whose every mechanic fires but whose comms silently never arrive is a
failed scenario that passes every state-only test.

This doc is the headless testability guide for the channels catalogued in
[../authoring/player-communication.md](../authoring/player-communication.md).
Read that first for *what* to communicate; this tells you *what a driver can
prove* about it.

## The channel × testability matrix

| Channel (from player-communication.md) | Headless-testable? | How |
|---|---|---|
| **Push** (comms popup via notify queue) | **Yes** | `ee_spy("notify")` + `ee_spy_seen` — see below |
| **Pull** (queryable orders / status pages) | **Yes** | dialog walker + `ee_dlg_click_by_label`; assert the rendered message text |
| **Persist** (ship log) | **Only through a choke point** | no read API exists (`getShipLog` is not in the 2024.12.08 reference) — see limits |
| **Locate** (sector names, waypoints) | **Yes** | sector names ride in asserted comms text; `getWaypointCount()` / waypoint coords after a mark-objective reply |
| **Mechanic verb** ("how", via descriptions) | **Yes** | `getDescription()` is readable headlessly — see descriptions |
| **Feedback** (state changes announced) | **Yes** | same spy pattern as push, asserted at the same beat as the state change |
| **Recovery** (idle hints) | **Yes** | shrink the idle knob from the driver, then wait on the spy |

## The choke-point convention (prerequisite for 3 of 7 channels)

A channel is testable only if every write goes through **one named global
function** the driver can wrap:

- **Push** → `notify(msg, from)` — the notify queue (patterns/notify-queue.md);
  the skeleton ships it.
- **Persist** → `log(msg, color)` — the skeleton ships it; never call
  `addToShipLog` raw. Scatter calls and no driver can ever assert what the
  crew was told; consolidate and `ee_spy("log")` sees everything.
- **Pull** → comms page functions, already function-shaped.

Rule for authors: **a channel without a choke point is a channel nobody can
test.** If you find yourself writing `pcall(addToShipLog, ...)` inline in three
places, that is three untestable sites — route them through `log()`.

Caveat: spies wrap the *global*, so this only works if the scenario calls the
choke point by global name at call time. Do not capture it in a local upvalue
(`local notify = notify` at file top) — the spy would never see the calls.

## The spy pattern (push / persist / feedback / recovery)

```lua
-- driver, top level: arm before any beat you care about
ee_spy("notify")
ee_spy("log")

ee_step(3, function()
    -- ee_wait polls every tick; its cont() runs once the condition holds,
    -- so outcome-dependent assertions are safe inside it
    ee_wait("push channel delivered", 30,
        function() return ee_spy_seen("notify", "set course") ~= nil end,
        function()
            ee_check(ee_spy_seen("log", "cargo secured") ~= nil,
                "log has the hand-over")
        end)
end)
```

- `ee_spy_seen(name, pattern, since)` matches the Lua pattern against the
  concatenated arguments of one call; `since` (game seconds) scopes to a beat.
- Assert the *feedback* beat together with the state change: "the scan flipped"
  AND "the crew was told the scan flipped". One without the other is how a
  mission looks finished while players are lost.
- Idle hints (recovery): the driver shares the scenario chunk, so shrink the
  knob — `SC.hint_after_s = 5` (or the scenario's knob) — then trigger no
  progress and `ee_wait` on the hint text through the spy. Set the knob before
  any step that could trigger the hint timer.

## Pull channel: click by label, assert the text

```lua
local d = ee_dlg_open(comms_orders_fn, target, player)
local msgs = ee_dlg_click_by_label(d, "What are my current orders?", target, player)
ee_check(#msgs == 1 and string.find(msgs[1], "Coldfield Relay"),
    "orders reply names the destination")
```

- Prefer `ee_dlg_click_by_label` over index clicks: reply order is unstable
  while authoring, and an index click hits the wrong reply silently.
- Authoring rule that keeps drivers stable: **new replies append after the
  originals** — never insert one mid-page.
- Assert page text, not just "click runs without error": a dead click (a menu
  renderer clobbering the action result) passes the click check and fails the
  player.

## Descriptions: readable, so assert them

`getDescription()` exists in the vendored reference (2024.12.08) — the
description channel is directly observable headlessly, **for the base text**
(the scanned-state text is not returned — see limits below). The convention
that makes it assertable is **text lives in one place per object**: one struct
field plus one function that applies it (base and every scan state), in the
spirit of Lost Cluster's `c.desc` + `lc_container_text()`:

```lua
ee_check(string.find(a:getDescription(), "unchecked", 1, true) ~= nil,
    "container label unreadable before proximity")
-- ... trigger the reveal ...
ee_check(string.find(a:getDescription(), "spare parts", 1, true) ~= nil,
    "container label resolves after proximity")
```

Skeleton scenarios should expose `probe_text(obj)` (or apply text through one
function the driver can call) so a driver can assert label flips at each beat.

## Waypoints (locate channel)

After a "mark the objective" reply: `getWaypointCount()` is the cheap presence
assert; the waypoint's coords (compare against the objective's known position,
within a stated tolerance) prove the *aim* — and are how you verify a
deliberate fudge (e.g. aiming between two objects so a puzzle is not spoiled)
without spoiling test intent.

## Headless limits (put these on the human-acceptance list)

- **No ship-log read API.** A spy sees the write attempt, not what the player's
  log screen finally renders; popup rendering, colors, and log ordering stay
  human checks (human-acceptance.md).
- **`getDescription()` returns the BASE text only.** After
  `setDescriptions(base, scanned)` + a full scan state, it still reads the
  not-scanned text `[obs]` (probed with Fever Run's Polaris). Scanned-state
  labels are assertable only if the scenario mirrors its own text (Lost
  Cluster's `c.desc` pattern) or by a human session.
- **Comms popups arriving mid-dialog** (queue retry behavior) behave
  differently with real clients; headless the queue always lands on first try.
- Multi-crew branches (`#players >= 2`) and anything needing real movement or
  collision physics are not headless-testable (runtime-surprises.md).

## Worked examples

- `ee-skills/examples/demo/` — skeleton-convention scenario: `notify()`/`log()`
  choke points, probe hooks.
- `scenarios/scenario_40_lostcluster` — `lc_notify()` choke point,
  `probe_container_text()` description readback, per-phase idle hints.
- `scenarios/scenario_42_feverrun` — `fr_log()` consolidation, orders reply,
  waypoint reply, `FR.idle_s` knob.
