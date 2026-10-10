# Demo mission — "Demo Cache Run"

A complete, deliberately small mission that uses every core pattern in this
package without simplifying any of them. It exists so the docs can point at real
code instead of pseudocode, and so `bin/ee_selftest.sh` has something to assert
against in an environment that has nothing else but a vendored game.

```sh
bin/ee_smoke.sh examples/demo/scenario_95_demo.lua          # boot check
bin/ee_func.sh  examples/demo/scenario_95_demo.lua \
                AUTOTEST=$PWD/examples/demo/autotest.lua     # ~3 min, 27 assertions
```

## The mission

The crew is told to recover two cargo cores from a hauler that died near a fuel
cache. Somewhere in the same region sits a relay station their side built and
never registered on the sensor net.

| Beat | Pattern it exercises |
|---|---|
| Home station hails you | dialog page/replies split, one-message contract |
| Fuel cache with a wreck, containers, mines | container drop, two-state labels, world seeding |
| Recover the cores | station hand-over distance gate (refused from open space) |
| A patrol escorts the cache | drop-watchdog after a hook-less death |
| Waypoint 7 relay | hidden station: faction flip + radar range, revealed at 6u |
| Mercenary squad clears a fresh escort | organic killing (the only way to test hooks) |
| Both cores in → victory | phase machine + terminal state |

## Files

| File | Role |
|---|---|
| `scenario_95_demo.lua` | the mission: one file, valid parsed header, knobs, init/update, dialogs, `probe_*` hooks |
| `autotest.lua` | its driver: a timeline of steps + polled assertions |

## Reading order

1. the **knob block** at the top - every tunable number in one place,
2. `init()` - what exists, including the two `mk_drop_watch` calls,
3. `update()` - the poll loop: FTL, message queue, labels, hidden-station reveal,
   drop-watch, phase check,
4. `commsDepot` / `commsCache` / `commsStatus` - the dialog page + `_replies` split,
5. the `probe_*` functions at the bottom - how the driver reaches inside,
6. `autotest.lua` - what "correct" means for all of the above.

## Known limits of the automated part

Pickup is collision-based and a teleported hull never collides, so `probe_pickup`
stands in for the real `onPickUp`; dialog *rendering* needs a client. Both are on
the human-acceptance checklist ([testing/human-acceptance.md](../../testing/human-acceptance.md)),
and the driver says so in its comments - see
[testing/runtime-surprises.md](../../testing/runtime-surprises.md).
