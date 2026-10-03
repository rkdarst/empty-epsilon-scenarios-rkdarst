# Our scenarios

Drop custom scenarios here as `scenario_<NN>_<name>.lua`.

- Copy `templates/scenario_template.lua` to start.
- Test: `../tools/smoke_test.sh scenario_NN_name.lua`
- Deploy locally: copy into `~/.emptyepsilon/scripts/` (game picks them up
  automatically under their `Type:` category; never edit the game install).

Numbering convention (borrowed from upstream): 00-09 basic/missions,
10-49 story scenarios, 80+ PvP/testing — adjust to taste.
