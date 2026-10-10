# Examples

| Example | What it demonstrates |
|---|---|
| [demo/](demo/) | a complete mini-mission (`scenario_95_demo.lua`) plus its assertion driver - every core pattern in < 550 lines, and the package's own acceptance test |
| [rebuild-a-large-mission.md](rebuild-a-large-mission.md) | method for growing/rewriting a 1000+ line mission under assertion coverage without losing a working baseline |

## demo/

```
demo/scenario_95_demo.lua   the mission (a valid, loadable scenario file)
demo/autotest.lua           its driver (~30 assertions over ~150 game seconds)
```

Run it directly (the driver must be named `autotest.lua`, so point at it
explicitly — auto-discovery only looks in the scenario's own directory and
`<root>/tests`):

```sh
bin/ee_smoke.sh examples/demo/scenario_95_demo.lua
AUTOTEST=$PWD/examples/demo/autotest.lua bin/ee_func.sh examples/demo/scenario_95_demo.lua
```

or via the packaged self-test, which copies the whole package to a temp dir first
to prove nothing outside it is required:

```sh
bin/ee_selftest.sh
```

The mission is deliberately small but not simplified: it uses the real hidden-station
faction flip, the two-state container labels, the drop-watch, the hand-over distance
gate, the notification queue and the dialog page/replies split - and the driver
asserts the *negative* case of each (not revealed too early, hand-over refused from
open space, label unreadable at range), because those are the ones that rot.

Two places where the driver takes a shortcut are marked in the code and explained in
[testing/runtime-surprises.md](../testing/runtime-surprises.md): teleporting a hull
onto a crate does not trigger the collision-based pickup, and dialog rendering needs
a client. Both are covered by the human-acceptance checklist.
