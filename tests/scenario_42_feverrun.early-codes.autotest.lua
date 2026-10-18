-- tests/scenario_42_feverrun.early-codes.autotest.lua - REGRESSION driver for
-- the sequence-free path of Fever Run. Run explicitly:
--   AUTOTEST=tests/scenario_42_feverrun.early-codes.autotest.lua \
--     ./tools/func_test.sh scenarios/scenario_42_feverrun.lua
--
-- It plays the mission OUT OF ORDER, the way an unscripted crew can: straight
-- to the beacons WITHOUT visiting Coldfield Relay first (the spawn->Polaris
-- line passes ~9.6u from the relay, outside the 6u arrival radius), codes
-- taken at phase 1, THEN the relay. The bug this guards: the phase machine
-- used to leave phase stuck at 2 on arrival and the mission could never end.

ee_finish_at = 95
-- ee_runtime: 110
local fr = {}

-- t=2: boot census.
ee_step(2, function()
    probe_state()
    ee_check(phase == 1, "mission starts in phase 1")
    ee_check(codes == false, "no codes at boot")
end)

-- t=4: skip the relay entirely: scan the courier and take the codes at
-- phase 1. The fix makes give_codes bump straight to the load phase.
ee_step(4, function()
    fr.p = active_players()[1]
    probe_warp_to(U(59), U(-8))
    ee_check(probe_scan("polaris") == "scanned", "courier scanned out of order")
    fr.dlg = ee_dlg_open(commsPolaris, polaris, fr.p)
    fr.msgs = ee_dlg_click(fr.dlg, 1, polaris, fr.p)
    ee_check(fr.msgs[1]:find("Codes transmitted") ~= nil, "codes handed over at phase 1")
    ee_until("codes advance the mission to the load phase immediately", 10,
        function() return codes == true and phase == 3 end)
end)

-- t=10: the courier's own case comes too (still fine at any phase).
ee_step(10, function()
    ee_check(probe_pickup("case") == "carried", "case C collected")
end)

-- t=14: NOW arrive at the relay: the arrival branch must NOT reset the phase
-- to 2 (pre-fix it did, deadlocking the mission), and the override watchdog
-- must never have been armed.
ee_step(14, function()
    probe_warp_to(U(36.2), U(5))
    ee_until("arrival with codes in hand stays in the load phase", 10,
        function() return phase == 3 end)
    ee_check(codes_deadline == nil, "override watchdog was never armed")
end)

-- t=20: load cases A+B alongside, with the out-of-order codes.
ee_step(20, function()
    fr.rdlg = ee_dlg_open(commsRelay, stations.relay, fr.p)
    fr.msgs = ee_dlg_click(fr.rdlg, 2, stations.relay, fr.p)
    ee_check(fr.msgs[1]:find("Crane cycle") ~= nil, "alongside + out-of-order codes loads the cases")
    ee_until("loading advances to the final leg", 10,
        function() return loaded == true and phase == 4 end)
end)

-- t=30: the colony wave still springs (the wave watches phase 4, not history).
-- Poll only here: an ee_until registers and returns, so the kill belongs in a
-- later step.
ee_step(30, function()
    probe_warp_to(U(55), U(51))
    ee_until("approaching the colony springs the raider wave", 15,
        function() return wave_spawned end)
end)

-- t=45: the wave exists by now; wipe it hooklessly (the poll covers it).
ee_step(45, function()
    ee_check(#groups.wave >= 1 and groups.wave[1]:isValid(), "wave leader is alive")
    ee_check(probe_kill_group("wave") == 2, "wave wiped (hookless; poll covers it)")
    ee_until("the watcher logs the cleared wave", 30, function() return wave_done end)
end)

-- t=70: deliver and win - the whole point of the regression.
ee_step(70, function()
    local cx, cy = stations.colony:getPosition()
    probe_warp_to(cx + U(1.2), cy)
    fr.cdlg = ee_dlg_open(commsColony, stations.colony, fr.p)
    fr.msgs = ee_dlg_click(fr.cdlg, 1, stations.colony, fr.p)
    ee_check(fr.msgs[1]:find("Transfer line secured") ~= nil, "delivery accepted")
    ee_until("out-of-order run still ends in victory", 15, function() return done end)
end)

function ee_on_finish()
    ee_check(done, "final: mission ended despite the out-of-order route")
    ee_check(delivered and loaded and case_c_aboard and codes, "final: all objectives met")
    probe_state()
end
