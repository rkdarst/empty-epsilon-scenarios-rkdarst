# Templates

| File | Use |
|---|---|
| [scenario_skeleton.lua](scenario_skeleton.lua) | a complete, booting scenario with every pattern wired but no content — copy it, then fill in the map, beats and dialogs |
| [autotest_driver.lua](autotest_driver.lua) | the matching driver; steps 1-2 pass on a fresh copy, the beat steps are commented until you implement them |
| [design_brief.md](design_brief.md) | the one-page brief an author writes before any code (facts / feel / flavour / ask) |

Both Lua templates are verified to parse and boot: the skeleton's `init()` runs
clean and the driver's opening steps pass against it, so a new mission starts from
something demonstrably working — including its GM console section, which renders
its first page (`SC-GM: page main drawn, 5 button(s)`) during the boot check.

## Copy-paste commands

```sh
cp templates/scenario_skeleton.lua <root>/scenarios/scenario_90_mine.lua
bin/ee_smoke.sh <root>/scenarios/scenario_90_mine.lua          # must print OK

cp templates/autotest_driver.lua <root>/tests/scenario_90_mine.autotest.lua
bin/ee_func.sh  <root>/scenarios/scenario_90_mine.lua          # discovers the driver
```

## What to change first

1. the **header** (Name / Description / Type) — a missing `Type:` files the
   mission under *Unknown* ([authoring/HEADER-FORMAT.md](../authoring/HEADER-FORMAT.md));
2. the **knob block** for the mission's scale (`SC`, `AMBIENT`);
3. `PART_NAMES` / `init()` / `goal_done()` — the actual objective and map;
4. one dialog page per station you actually use;
5. the **GM console** pages (`gm_page_*`) — keep the plumbing, replace the
   buttons with the levers your mission actually needs
   ([patterns/gm-console.md](../patterns/gm-console.md));
6. then uncomment the driver's beat steps as you implement the beats.
