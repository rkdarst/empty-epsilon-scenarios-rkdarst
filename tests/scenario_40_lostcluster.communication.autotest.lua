-- tests/scenario_40_lostcluster.communication.autotest.lua - communication-
-- channel driver for Lost Cluster. The main driver proves the mechanics; this
-- one proves the crew is TOLD (ee-skills/testing/communication-testing.md):
--   pull       Lumina 1 status / who-has pages, clicked by label
--   recovery   idle hint with LC_IDLE_S shrunk to 8
--   feedback   station-loss announcement when Tampere 1 dies
--   persist    a station death never invents a part that was not on the map
--              (the H200 materializes only when the crew hails Tampere 1; the
--              spill path itself is covered by the main driver)
--
-- lc_notify() is the push AND persist choke point (it mirrors every line into
-- each active ship's log), so one spy covers both channels. ee_wait is
-- poll+continuation (the engine strips the coroutine library): outcome-dependent
-- assertions live inside cont().

ee_finish_at = 160
-- ee_runtime: 200
local cl = {}

LC_IDLE_S = 8                       -- recovery test: shrink the idle knob
ee_spy("lc_notify")

-- Invariant (anti-softlock as runtime maths): the delivery target outlives
-- this driver (only Tampere 1 is killed here, never Lumina 1).
ee_invariant("Lumina 1 stays alive", function()
    return stations.lumina ~= nil and stations.lumina:isValid()
end)

-- t=2: boot census.
ee_step(2, function()
    probe_state()
    cl.crew = active_players()[1]
    ee_check(phase == 1, "mission starts in phase 1")
    ee_check(stations.tampere ~= nil and stations.tampere:isValid(),
        "Tampere 1 exists at boot")
    ee_check(parts["H200 GPU nodes"] == nil,
        "H200 GPU nodes are not on the map until Tampere 1 is hailed")
end)

-- t=4: PULL - the queryable status page, clicked by label, text asserted.
ee_step(4, function()
    cl.dlg = ee_dlg_open(commsLumina, stations.lumina, cl.crew)
    cl.msgs = ee_dlg_click_by_label(cl.dlg, "What is the mission status?",
        stations.lumina, cl.crew)
    ee_check(#cl.msgs == 1 and cl.msgs[1]:find("Phase 1: cluster recovery") ~= nil,
        "pull: status page answers with the phase-1 tally")
    cl.msgs = ee_dlg_click_by_label(cl.dlg, "Who might have the cluster hardware?",
        stations.lumina, cl.crew)
    ee_check(#cl.msgs == 1 and cl.msgs[1]:find("Kajaani 1") ~= nil,
        "pull: who-has page names the first lead")
end)

-- t=8: RECOVERY - no progress for LC_IDLE_S=8 s, so the idle hint must land.
ee_wait("recovery: idle hint names the next step", 40, function()
    return ee_spy_seen("lc_notify", "we still lack cluster components") ~= nil
end)

-- t=40: FEEDBACK - Tampere 1 dies; the crew must be told. Hookless destroy on
-- purpose: watch_stations() is a polled world fact, not a death hook (same
-- shape as the defeat driver's test). ee_wait is armed AFTER the trigger so
-- its deadline cannot race the scenario's update tick. [obs]
ee_step(40, function()
    pcall(function() stations.tampere:destroy() end)
    ee_wait("feedback: station-loss announcement pushed", 20, function()
        return ee_spy_seen("lc_notify", "Tampere 1 has been destroyed") ~= nil
    end, function()
        -- The part only materializes when the crew hails Tampere 1; killing
        -- the station before that must NOT invent a part or claim a spill.
        ee_check(ee_spy_seen("lc_notify", "spilled adrift") == nil,
            "feedback: no spill announcement - the part was never on the map")
        ee_check(parts["H200 GPU nodes"] == nil,
            "persist: a death never invents a part that was not held")
        ee_check(tampere_state == "clear", "state: Tampere's leash/comms state retired")
    end)
end)

function ee_on_finish()
    probe_state()
    print("CL-COMM: lc_notify calls=" .. #ee_spies.lc_notify.calls)
end
