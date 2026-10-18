-- tests/scenario_40_lostcluster.defeat.autotest.lua - DEFEAT-PATH driver for
-- Lost Cluster. Run explicitly:
--   AUTOTEST=tests/scenario_40_lostcluster.defeat.autotest.lua \
--     ./tools/func_test.sh scenarios/scenario_40_lostcluster.lua
--
-- Anti-softlock test (d): make the mission un-winnable on purpose and assert a
-- terminal state is declared instead of a hang. Lumina 1 is the only delivery
-- target AND the phase-3 wave's target; before this driver existed, its death
-- (GM removal, stray Kraylor fire, the wave winning) left the mission polling
-- forever - or, in phase 3, declaring victory over the debris.

ee_finish_at = 40
-- ee_runtime: 60

-- t=2: boot census; the home station is alive and the mission has not ended.
ee_step(2, function()
    probe_state()
    ee_check(phase == 1, "mission starts in phase 1")
    ee_check(stations.lumina ~= nil and stations.lumina:isValid(), "Lumina 1 exists at boot")
    ee_check(not done, "mission has not ended at boot")
end)

-- t=4: destroy the home station at phase 1 - the earliest, most order-hostile
-- point, before any part has been delivered. Hookless on purpose: the defeat
-- branch must be a polled world fact, not a death hook.
ee_step(4, function()
    pcall(function() stations.lumina:destroy() end)
    ee_check(not stations.lumina:isValid(), "home station destroyed out from under the mission")
end)

-- t=6: the poll must notice and declare defeat within a couple of ticks.
ee_step(6, function()
    ee_until("defeat declared after Lumina 1 dies at phase 1", 20,
        function() return done end)
end)

function ee_on_finish()
    ee_check(done, "final: mission reached a terminal state after home-station loss")
    probe_state()
end