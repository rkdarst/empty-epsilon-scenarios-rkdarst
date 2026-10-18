-- tests/scenario_42_feverrun.autotest.lua - driver for the Fever Run mission.
-- Appended after lib/autotest.lua by ee_func.sh, so ee_* helpers and the
-- scenario's globals/probes are all in scope.
--
-- Headless has no human crew, so the driver IS the crew: it warps the player
-- hull (probe_warp_to), stands in for science scans (probe_scan) and cargo
-- pickup (probe_pickup), and clicks the real comms pages. Fights: the ambush
-- is wiped hooklessly (probe_kill_group; the group is poll-watched) and the
-- final wave is killed ORGANICALLY by a mercenary squad so onDestruction path
-- coverage exists too. Both are asserted on purpose.

ee_finish_at = 330
-- ee_runtime: 420
local fr = {}

-- t=2: the world came up as designed.
ee_step(2, function()
    probe_state()
    ee_check(phase == 1, "mission starts in phase 1 (get to the relay)")
    ee_check(stations.relay ~= nil and stations.relay:isValid(), "Coldfield Relay exists")
    ee_check(stations.colony ~= nil and stations.colony:isValid(), "Sedgeon Colony exists")
    ee_check(polaris ~= nil and polaris:isValid(), "courier Polaris exists")
    ee_check(polaris:getFaction() == "Human Navy", "Polaris is ours (on the contact list)")
    ee_check(decoy ~= nil and decoy:isValid(), "the decoy exists")
    ee_check(decoy:getFaction() == "Independent", "decoy boots neutral (a same-faction ship cannot hide)")
    ee_check(probe_part("case") == "adrift", "vaccine case C starts adrift")
    ee_check(codes == false and loaded == false and case_c_aboard == false,
        "mission starts with nothing collected")
end)

-- t=4: the dialog contract: one message per page render, choices offered.
ee_step(4, function()
    fr.p = active_players()[1]
    fr.dlg = ee_dlg_open(commsMeridian, stations.meridian, fr.p)
    ee_check(#fr.dlg.msgs == 1, "Meridian page renders exactly one message")
    ee_check(#fr.dlg.replies >= 3, "Meridian page offers its choices")
end)

-- t=6: arrival at the relay is a polling transition - poll it.
ee_step(6, function()
    probe_warp_to(U(31), U(5))
    ee_until("arrival flips the mission to the triage phase", 15,
        function() return phase == 2 end)
end)

-- t=10: the load gate must REFUSE without codes, not apply.
ee_step(10, function()
    fr.rdlg = ee_dlg_open(commsRelay, stations.relay, fr.p)
    ee_check(#fr.rdlg.msgs == 1, "relay page renders exactly one message")
    ee_check(#fr.rdlg.replies >= 4, "relay page offers its choices")
    fr.msgs = ee_dlg_click(fr.rdlg, 2, stations.relay, fr.p)
    ee_check(#fr.msgs == 1, "load click renders exactly one message")
    ee_check(fr.msgs[1]:find("codes") ~= nil, "loading without codes is refused")
    ee_check(loaded == false, "refused load loaded nothing")
end)

-- t=14: science triage: scan the decoy, then come close - the bait must spring.
ee_step(14, function()
    probe_warp_to(U(66), U(2))
    ee_check(probe_scan("decoy") == "scanned", "decoy scan probe works")
    ee_check(decoy_scanned == true, "decoy scan flips the bookkeeping")
    probe_warp_to(U(68.5), U(2))
    ee_until("approaching the decoy springs the ambush", 15,
        function() return ambush_sprung end)
    ee_until("the ambush is two raiders", 10,
        function() return #groups.ambush == 2 end)
end)

-- t=20: wipe the ambush hooklessly; the polled watcher must still clear it.
ee_step(20, function()
    ee_check(probe_kill_group("ambush") == 2, "ambush wiped")
    ee_until("the polled watcher clears the ambush", 20,
        function() return ambush_done end)
end)

-- t=26: the real courier: scan her, then the codes come over comms.
ee_step(26, function()
    probe_warp_to(U(59), U(-8))
    ee_check(probe_scan("polaris") == "scanned", "polaris scan probe works")
    ee_check(polaris_scanned == true, "polaris scan flips the bookkeeping")
    fr.pdlg = ee_dlg_open(commsPolaris, polaris, fr.p)
    ee_check(#fr.pdlg.msgs == 1, "polaris page renders exactly one message")
    fr.msgs = ee_dlg_click(fr.pdlg, 1, polaris, fr.p)
    ee_check(fr.msgs[1]:find("Codes transmitted") ~= nil, "scanned courier hands over the codes")
    ee_until("codes advance the mission to the load phase", 15,
        function() return codes == true and phase == 3 end)
end)

-- t=34: the courier's own case: pickup is collision based, so the probe stands
-- in for the fly-over (the human-acceptance checklist covers the real path).
ee_step(34, function()
    ee_check(probe_pickup("case") == "carried", "vaccine case C collected")
    ee_check(case_c_aboard == true, "case C bookkeeping updated")
end)

-- t=40: station services: the restock action renders one message and fills up.
ee_step(40, function()
    fr.rdlg2 = ee_dlg_open(commsRelay, stations.relay, fr.p)
    fr.msgs = ee_dlg_click(fr.rdlg2, 3, stations.relay, fr.p)
    ee_check(#fr.msgs == 1, "restock click renders exactly one message")
    ee_check(fr.msgs[1]:find("Magazines") ~= nil, "restock confirms the top-up")
end)

-- t=46: load cases A+B for real: alongside, with codes.
ee_step(46, function()
    local rx, ry = stations.relay:getPosition()
    probe_warp_to(rx + U(1.2), ry)             -- 1.2u from the hull: alongside
    fr.rdlg3 = ee_dlg_open(commsRelay, stations.relay, fr.p)
    fr.msgs = ee_dlg_click(fr.rdlg3, 2, stations.relay, fr.p)
    ee_check(#fr.msgs == 1, "load click renders exactly one message")
    ee_check(fr.msgs[1]:find("Crane cycle") ~= nil, "alongside + codes loads the cases")
    ee_until("loading advances the mission to the final leg", 15,
        function() return loaded == true and phase == 4 end)
end)

-- t=54: final leg: warp in; the wave must spring near Sedgeon. Poll only - a
-- step that registers an ee_until keeps running synchronously, so any action
-- that depends on the wave existing belongs in a LATER step.
ee_step(54, function()
    probe_warp_to(U(55), U(51))
    ee_until("approaching the colony springs the raider wave", 15,
        function() return wave_spawned end)
    ee_until("the wave is two raiders", 10,
        function() return #groups.wave == 2 end)
end)

-- t=70: the wave exists by now; give it an ORGANIC death - the mercenary
-- squad gives the engine a moving fight so onDestruction fires.
ee_step(70, function()
    ee_check(#groups.wave >= 1 and groups.wave[1]:isValid(), "wave leader is alive")
    local cx, cy = stations.colony:getPosition()
    ee_merc_squad("Human Navy", cx, cy, groups.wave[1], groups.wave, 3)
    ee_merc_dump("deployed against the wave")
    ee_until("mercenaries wipe the colony raiders organically", 140,
        function() return #groups.wave > 0 and all_dead(groups.wave) end)
end)

ee_step(195, function()
    ee_until("the watcher logs the cleared wave", 45, function() return wave_done end)
end)

-- t=205: deliver through the real dialog action, at the real distance.
ee_step(205, function()
    local cx, cy = stations.colony:getPosition()
    probe_warp_to(cx + U(1.2), cy)             -- alongside the colony
    fr.cdlg = ee_dlg_open(commsColony, stations.colony, fr.p)
    ee_check(#fr.cdlg.msgs == 1, "colony page renders exactly one message")
    fr.msgs = ee_dlg_click(fr.cdlg, 1, stations.colony, fr.p)
    ee_check(#fr.msgs == 1, "deliver click renders exactly one message")
    ee_check(fr.msgs[1]:find("Transfer line secured") ~= nil, "delivery accepted")
end)

ee_step(215, function()
    ee_until("mission ends in victory", 25, function() return done end)
end)

function ee_on_finish()
    ee_check(done, "final: mission ended")
    ee_check(delivered and loaded and case_c_aboard, "final: all three cases delivered")
    ee_check(codes, "final: codes were obtained")
    ee_check(wave_done, "final: colony raiders were cleared")
    ee_merc_retire()
    probe_state()
end
