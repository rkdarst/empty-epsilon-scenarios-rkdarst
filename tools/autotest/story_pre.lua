-- SCEN_PRE for a Story-difficulty func_test run: shadows the scenario
-- setting reader BEFORE the concatenated scenario's top level runs. Headless
-- EE 2024.12 has no CLI plumbing for Setting[...] values (they only arrive
-- from the start-server GUI), so this fakes the server choice and exercises
-- everything downstream: STORY_MODE detection and story_buff() on every hull
-- watch_player() ever touches (init spawns, late joiners, GM respawns).
-- The setting wiring itself (getScenarioSetting + the empty-string fallback)
-- is three load-time lines, verified by the LC-PROBE difficulty print.
local lc_real_setting = getScenarioSetting
getScenarioSetting = function(key)
    if key == "Difficulty" then return "Story" end
    return lc_real_setting(key)
end
