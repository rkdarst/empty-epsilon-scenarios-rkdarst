# Our scenarios

Drop custom scenarios here as `scenario_<NN>_<name>.lua`.

- Copy `../ee-skills/templates/scenario_skeleton.lua` to start (valid parsed
  header, knob block, poll-based `update()`, test hooks).
- Test: `../tools/smoke_test.sh scenario_NN_name.lua`, then
  `../tools/func_test.sh scenario_NN_name.lua` once it has a driver in `../tests/`.
- Any `scenario_*.lua` placed here is loaded by the game as a real mission — test
  drivers therefore live in `../tests/`, never in this directory.
- Deploy locally: copy into `~/.emptyepsilon/scripts/` (game picks them up
  automatically under their `Type:` category; never edit the game install).

## Conventions

| Thing | Rule |
|---|---|
| Design note | every non-trivial mission gets `scenario_NN_<name>.AGENTS-brief.txt` beside it (facts, fiction, tuning decisions, invariants) |
| Driver | `../tests/scenario_NN_<name>.autotest.lua`, discovered automatically |
| Settings | read with a default (`if s == nil then s = "Normal" end`) — a headless boot gets none |
| Numbers | one knob block at the top, distances via `U(u)`, times in seconds |

Numbering convention (borrowed from upstream): 00-09 basic/missions,
10-49 story scenarios, 80+ PvP/testing.

| Scenario | Notes |
|---|---|
| `scenario_40_lostcluster.lua` | our long investigation mission — brief: `scenario_40_lostcluster.AGENTS-brief.txt` |
| `scenario_41_lostcluster_dsl.lua` | the same mission generated from the mission DSL ([../dsl/DESIGN.md](../dsl/DESIGN.md)) |
| `scenario_90_template.lua` | minimal boot-check scenario, used by the smoke test in CI-style runs |

