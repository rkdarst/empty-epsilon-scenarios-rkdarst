-- tests/scenario_42_feverrun.defeat.autotest.lua - DEFEAT-PATH driver for Fever
-- Run. Run explicitly:
--   AUTOTEST=tests/scenario_42_feverrun.defeat.autotest.lua \
--     ./tools/func_test.sh scenarios/scenario_42_feverrun.lua
--
-- Anti-softlock test (d): make the mission un-winnable on purpose and assert a
-- terminal state is declared instead of a hang. The crew can shoot their own
-- colony (friendly fire), the GM can delete it, or the raider wave can level it
-- - in every case Sedgeon's death must end the mission, at ANY phase, not leave
-- phase 4 waiting to deliver to a dead station. The bug this guards: the defeat
-- branch used to require wave_spawned, so a colony destroyed any other way
-- softlocked the mission.

ee_finish_at = 40
-- ee_runtime: 60

-- t=2: boot census; the colony is alive and the mission has not ended.
ee_step(2, function()
    probe_state()
    ee_check(phase == 1, "mission starts in phase 1")
    ee_check(stations.colony ~= nil and stations.colony:isValid(), "Sedgeon Colony exists")
    ee_check(done == false, "mission has not ended at boot")
end)

-- t=4: destroy the colony at phase 1 - the earliest, most order-hostile point
-- (friendly fire / GM removal; no wave has ever spawned). Hookless on purpose:
-- the defeat branch must be a polled world fact, not a death hook.
ee_step(4, function()
    pcall(function() stations.colony:destroy() end)
    ee_check(not stations.colony:isValid(), "colony destroyed out from under the mission")
end)

-- t=6: the poll must notice and declare defeat within a couple of ticks.
ee_step(6, function()
    ee_until("defeat declared after the colony dies at phase 1", 20,
        function() return done end)
    ee_check(delivered == false, "defeat, not a phantom delivery")
end)

function ee_on_finish()
    ee_check(done, "final: mission reached a terminal state after colony loss")
    probe_state()
end
