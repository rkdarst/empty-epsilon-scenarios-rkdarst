# tests/ — assertion drivers

One driver per scenario, named exactly after it:

```
scenario_40_lostcluster.lua            ->  scenario_40_lostcluster.autotest.lua
```

`tools/func_test.sh <scenario>` concatenates `ee-skills/lib/autotest.lua` and the
driver **after** a copy of the scenario, in one Lua chunk, so a driver can call
the scenario's own functions and `probe_*` hooks. This directory - not
`scenarios/` - is where they live because any `scenario_*.lua` inside the scenario
dir would be loaded by the game as a real mission.

```sh
tools/func_test.sh scenarios/scenario_40_lostcluster.lua             # discovered
tools/func_test.sh scenarios/x.lua AUTOTEST=tests/other.lua           # explicit
tools/func_test.sh scenarios/x.lua AUTOTEST=none                      # idle boot only
EE_SETTINGS="Difficulty=Story" tools/func_test.sh scenarios/scenario_40_lostcluster.lua
```

| Driver | Covers |
|---|---|
| `scenario_40_lostcluster.autotest.lua` | the full Lost Cluster mission (~128 assertions over ~1000 game seconds), including hook-less-death safety and dialog contracts |
| `scenario_41_lostcluster_dsl.autotest.lua` | the DSL twin: live-tick liveness, generator invariants, emitted shapes |

Writing or extending one: [ee-skills/testing/writing-drivers.md](../ee-skills/testing/writing-drivers.md)
and the skeleton [ee-skills/templates/autotest_driver.lua](../ee-skills/templates/autotest_driver.lua).
