-- tests/scenario_42_feverrun.lost-case.autotest.lua - MID-PHASE FAILURE
-- INJECTION driver (anti-softlock test (e)). Run explicitly:
--   AUTOTEST=tests/scenario_42_feverrun.lost-case.autotest.lua \
--     ./tools/func_test.sh scenarios/scenario_42_feverrun.lua
--
-- With a phase open, remove the object one of its micro-objectives needs and
-- assert the phase still exits - re-acquired, reassigned or defeat - instead
-- of polling forever. Two lost cases, chosen from the anti-softlock §5
-- checklist:
--   1. the courier (helper NPC) destroyed before her codes exist -> the relay
--      override must re-acquire them and bump the phase machine to load;
--   2. the case C container shot to pieces while adrift -> the drop-watch must
--      respawn it (it is the mission's only re-acquirable pickup).

ee_finish_at = 40
-- ee_runtime: 60

-- t=2: boot census, then warp alongside Coldfield Relay to open the triage
-- phase (this is where the override deadline gets armed).
ee_step(2, function()
    probe_state()
    ee_check(phase == 1, "mission starts in phase 1")
    ee_check(polaris ~= nil and polaris:isValid(), "Polaris exists at boot")
    probe_warp_to(U(35), U(5))
end)

-- t=4: the triage phase is open and its micro-objective dies - hooklessly on
-- purpose (destroy() fires no onDestruction): the recovery must be a polled
-- world fact, not a death hook. The real override knob is FR.override_s = 300,
-- far too long for a headless run, so the driver shortens the already-armed
-- clock (white-box: the driver shares the chunk; give_codes is the same path
-- the probe and the relay both use).
ee_step(4, function()
    ee_check(phase == 2, "arrival opened the triage phase")
    ee_check(codes == false, "no codes before the triage")
    pcall(function() polaris:destroy() end)
    ee_check(not polaris:isValid(), "Polaris destroyed before the codes existed")
    codes_deadline = clock + 5
end)

-- t=6: register the override watch (evaluated over the coming ticks), then
-- spring the second lost case: shoot the case C container. The phase==3
-- assertion lives in ee_on_finish - ee_until polls asynchronously, so a
-- synchronous check here would race the very tick the override lands.
ee_step(6, function()
    ee_until("override codes arrive after Polaris is lost", 30,
        function() return codes end)
    ee_check(case_c_obj ~= nil and case_c_obj:isValid(), "case C still adrift")
    pcall(function() case_c_obj:destroy() end)
end)

-- t=8: the drop-watch must put the case back within FR.case_grace_s + margin.
ee_step(8, function()
    ee_until("case C respawned by the drop-watch", 30,
        function() return case_c_obj ~= nil and case_c_obj:isValid() end)
    ee_check(case_c_aboard == false, "respawn is a fresh container, not a phantom pickup")
end)

function ee_on_finish()
    ee_check(codes, "final: codes were re-acquired via the relay override")
    ee_check(phase == 3, "final: override bumped the phase to load - no hang in triage")
    ee_check(case_c_obj ~= nil and case_c_obj:isValid(), "final: case C is obtainable again")
    probe_state()
end