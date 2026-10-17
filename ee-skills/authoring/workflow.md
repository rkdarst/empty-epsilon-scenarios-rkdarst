# Workflow

The short version of [from-brief-to-code.md](from-brief-to-code.md), as commands.

```sh
# 0. one-time
bin/ee_bootstrap.sh                       # game + runtime libs + boot check

# 1. brief  (human)          templates/design_brief.md -> briefs/<name>.md
# 2. outline (agent/author)  phases + task graph + knobs + open questions
#                            see from-brief-to-code.md; gate G1 is a human review

# 3. code
cp templates/scenario_skeleton.lua scenarios/scenario_NN_name.lua
#    header, then knobs -> helpers -> state -> builders -> init -> update
#    -> dialogs -> GM console -> probe hooks   (authoring/flow-diagrams.md has the model)
bin/ee_smoke.sh scenarios/scenario_NN_name.lua          # G2, run it after every edit

# 4. tests
cp templates/autotest_driver.lua tests/scenario_NN_name.autotest.lua
bin/ee_func.sh scenarios/scenario_NN_name.lua           # G3/G4: boot invariants + beats
#    then add the anti-softlock steps (G5): hook-less kill + long idle
RUNTIME=600 AUTOTEST=none bin/ee_func.sh scenarios/scenario_NN_name.lua

# 5. settings coverage: a branch never run is a branch that is broken
EE_SETTINGS="Difficulty=Story" bin/ee_func.sh scenarios/scenario_NN_name.lua
EE_SETTINGS="GMMenu=Disabled" bin/ee_func.sh scenarios/scenario_NN_name.lua
#    A setting-aware driver asserts the hidden path itself (hidden menu draws
#    only its un-hide button, actions still run, one click restores it). If the
#    driver assumes the menu, add AUTOTEST=none so this at least proves the
#    branch boots.

# 6. play (G6) and iterate on the knobs, not the logic
bin/ee_play.sh
```

## Gate table

| Gate | Proves | Command |
|---|---|---|
| G1 | the outline is solvable and has an anti-softlock argument | human read, 10 min |
| G2 | it boots without script errors | `ee_smoke.sh` (~25 s) |
| G3 | boot-time invariants (counts, factions, no overlaps) | driver steps at t=2 |
| G4 | each phase's exit condition is reachable | one driver step per beat |
| G5 | no softlock: hook-less deaths, respawn, 10-min idle | driver + `RUNTIME=600 AUTOTEST=none` |
| G6 | it plays well | [testing/human-acceptance.md](../testing/human-acceptance.md) |

## When to stop

Stop when G2-G5 are green **and** the log's own census lines look right (object
counts, seed census, no repeated respawn spam). Everything else is tuning: change
a knob, re-run G4, and only then touch logic.
