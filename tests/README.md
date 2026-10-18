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
tools/func_test.sh scenarios/scenario_40_lostcluster.lua                       # discovered
AUTOTEST=tests/other.autotest.lua tools/func_test.sh scenarios/scenario_x.lua  # explicit
AUTOTEST=none tools/func_test.sh scenarios/scenario_x.lua                      # idle boot only
EE_SETTINGS="Difficulty=Story" tools/func_test.sh scenarios/scenario_40_lostcluster.lua
```

| Driver | Covers |
|---|---|
| `scenario_40_lostcluster.autotest.lua` | the full Lost Cluster mission (~169 assertions), including hook-less-death safety, dialog contracts and container-description readback |
| `scenario_40_lostcluster.defeat.autotest.lua` | anti-softlock (d): Lumina 1 destroyed at phase 1 → defeat declared, not a hang |
| `scenario_40_lostcluster.communication.autotest.lua` | communication channels: status/who-has pulls by label, idle hint (knob shrunk), station-loss announcement + part spill |
| `scenario_41_lostcluster_dsl.autotest.lua` | the DSL twin: live-tick liveness, generator invariants, emitted shapes |
| `scenario_42_feverrun.autotest.lua` | the full Fever Run mission (~59 assertions), triage, fights, delivery |
| `scenario_42_feverrun.defeat.autotest.lua` | Polaris destroyed pre-load → relay override path |
| `scenario_42_feverrun.lost-case.autotest.lua` | lost-case: relay-loss defeat branch, case-C drop-watch respawn |
| `scenario_42_feverrun.communication.autotest.lua` | communication channels: orders pulls by label, waypoints, idle hint, `fr_log` spy, description flips |

Writing or extending one: [ee-skills/testing/writing-drivers.md](../ee-skills/testing/writing-drivers.md)
and the skeleton [ee-skills/templates/autotest_driver.lua](../ee-skills/templates/autotest_driver.lua).
Communication-channel assertions specifically:
[ee-skills/testing/communication-testing.md](../ee-skills/testing/communication-testing.md).
