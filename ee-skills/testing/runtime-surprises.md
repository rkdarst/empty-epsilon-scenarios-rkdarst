# Runtime surprises index

What headless runs show you, what they hide, and what "weird" actually means.

## Headless has no *clients*

A `PlayerSpaceship()` created by the scenario **does** count as an active player
ship (`getActivePlayerShips()` returns it, hull and weapons work, dialogs can be
driven programmatically), so scenario logic that reads the crew works in a
headless run. `[obs]` What does not exist is a connected client, so:

* nobody renders the dialogs the scenario builds (the driver must call the page
  functions directly);
* nothing moves by itself - a ship's position changes only through orders/AI, and
  a scripted `setPosition()` is a teleport, not a flight;
* **collision-based interactions do not happen**: flying *over* a pickupable
  artifact needs real movement, so `onPickUp` never fires from a teleported ship. `[obs]`

**Do this in the scenario** so it is both correct in play and testable headless:

```lua
if #players > 0 then ever_had_players = true end   -- in update()
```

plus `probe_warp_to(x, y)` / `probe_pickup(name)` style hooks that stand in for
the mechanics a client would drive, and keep the *bookkeeping* they trigger in
one place so the probe path and the real path stay identical. `[obs]`

## What headless proves and what it cannot

| Proven by headless | Needs a human client |
|---|---|
| syntax, `init()` correctness, no runtime errors | does the mission *make sense* |
| world census (counts, factions, positions, geometry) | radar/visibility feel |
| dialog contracts (one message per action, choices exist) | dialog UX, font/line lengths |
| phase transitions and their conditions | whether a search is fun |
| container reachability numerically | whether pickup actually triggers |
| hook-less-death safety, respawn/no-duplicate invariants | warp-transit timing |
| victory/defeat reaching a terminal state | how a nebula fight plays |

The second column is the 30-minute session in
[human-acceptance.md](human-acceptance.md).

## "Weird" behaviours that are really the engine

| Observation | Explanation |
|---|---|
| Nothing happens for a while, then a burst | idle clients pause the world; log timestamps are wall-clock, `clock` is game time |
| A ship "teleports" during a chase | either a warp jump or a scripted anti-camping drop-in |
| Same-faction station visible across the map | faction contacts bypass radar shadowing |
| A station's comms range seems infinite | stations are always-contact objects for their own faction |
| A ship will not shoot a parked ship | AI engagement geometry - [reference/ai-behaviour.md](../reference/ai-behaviour.md) |
| Containers appear twice | a hook *and* an uncapped watcher; cap the watcher's drops |
| `delta` is 0 for some ticks | paused world (headless starts paused) |
| Driver steps pass but the world is empty (`players=0`, `stations.x` nil) | a **top-level error in the assembled chunk** stopped Lua before the scenario's `init()`; the definitions survive, so `update()` and the driver keep ticking. Read the `init complete` census line before believing a green run ([runner-anatomy.md](runner-anatomy.md)) |

## Debugging order that works

1. Read the log's own story: `Load script`, your `init()` census line, the first
   `ERROR: LUA:` line. The first error is usually the only real one.
2. Reproduce the specific claim in a **20-line probe scenario** (see
   [testing/writing-drivers.md](writing-drivers.md)) instead of
   adding prints to a 2000-line mission.
3. If a probe contradicts the docs, believe the probe, then confirm it in the
   engine source, then write it down in `reference/` with a tag.
4. If a test fails only *sometimes*, it is timing: find the sampled condition and
   turn it into a poll with a deadline.
