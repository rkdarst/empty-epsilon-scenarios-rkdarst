-- tests/scenario_42_feverrun.communication.autotest.lua - communication-channel
-- driver for Fever Run. The main driver proves the world works; this one proves
-- the crew is TOLD (ee-skills/testing/communication-testing.md):
--   push       notify() spy               persist   fr_log() spy (no read API)
--   pull       orders reply, by label     locate    waypoint count + aim coords
--   feedback   arrival line at the phase flip        recovery   idle hint (knob shrunk)
--   descriptions  getDescription() before/after the scan flip
--
-- ee_wait is poll+continuation (the engine strips the coroutine library, so
-- nothing blocks): outcome-dependent assertions live inside cont().
--
-- NOTE on ee_dlg_click_by_label(d, label, target, source): the reply callback
-- receives (comms_source, comms_target) = (player, station), matching the
-- engine - so target = the station, source = the player ship, as everywhere.

ee_finish_at = 120
-- ee_runtime: 150
local fc = {}

FR.idle_s = 8                       -- recovery test: shrink the idle knob
ee_spy("notify")
ee_spy("fr_log")

-- Invariant (anti-softlock as runtime maths): there is always a valid station
-- to talk to from boot to finish.
ee_invariant("a station is always valid to talk to", function()
    for _, st in pairs(stations) do
        if st:isValid() then return true end
    end
    return false
end)

-- Waypoint coords are read defensively (getter shape varies across pins).
local function fc_waypoint(p, i)
    local ok, a, b = pcall(function() return p:getWaypoint(i) end)
    if not ok then return nil end
    if type(a) == "table" then return a.x, a.y end
    return a, b
end

-- t=2: PUSH + PERSIST - the briefing reached the crew.
ee_step(2, function()
    fc.crew = active_players()[1]
    ee_check(fc.crew ~= nil and fc.crew:isValid(), "crew ship exists")
    ee_check(phase == 1, "mission starts in phase 1")
    ee_check(ee_spy_seen("notify", "fever outbreak") ~= nil,
        "push: briefing queued to the crew")
    ee_check(ee_spy_seen("fr_log", "Meridian orders") ~= nil,
        "persist: briefing written to the ship log (spy saw the write)")
end)

-- t=4: PULL - the orders reply answers what phase 1 needs, clicked by label.
ee_step(4, function()
    fc.dlg = ee_dlg_open(commsMeridian, stations.meridian, fc.crew)
    fc.msgs = ee_dlg_click_by_label(fc.dlg, "What are my current orders?",
        stations.meridian, fc.crew)
    ee_check(#fc.msgs == 1 and
        fc.msgs[1]:find("Current orders: set course for Coldfield Relay") ~= nil,
        "pull: phase-1 orders name the relay")
end)

-- t=6: LOCATE - the relay marks the objective; phase 1 aims at the relay itself.
ee_step(6, function()
    fc.rdlg = ee_dlg_open(commsRelay, stations.relay, fc.crew)
    fc.msgs = ee_dlg_click_by_label(fc.rdlg, "Mark the next objective on our nav.",
        stations.relay, fc.crew)
    ee_check(fc.crew:getWaypointCount() >= 1, "locate: relay placed a waypoint")
    local wx, wy = fc_waypoint(fc.crew, 1)
    if wx then
        local sx, sy = stations.relay:getPosition()
        ee_check(math.abs(wx - sx) < 1500 and math.abs(wy - sy) < 1500,
            "locate: phase-1 waypoint sits on the relay")
    end
end)

-- t=8: RECOVERY - no progress for FR.idle_s=8 s, so the idle hint must land.
ee_wait("recovery: idle hint names the next step", 40, function()
    return ee_spy_seen("notify", "cases A and B are waiting there") ~= nil
end)

-- t=30: FEEDBACK - arriving at the relay announces itself, on both channels.
-- ee_wait is armed AFTER the trigger: the harness pollers run before the
-- scenario's update() each tick, so a wait armed at top level with a deadline
-- equal to the trigger time fails one tick early. [obs]
ee_step(30, function()
    probe_warp_to(U(31), U(5))
    ee_wait("feedback: relay arrival line pushed", 30, function()
        return ee_spy_seen("notify", "made good time") ~= nil
    end, function()
        ee_check(phase == 2, "feedback: arrival flipped the mission to the triage phase")
        ee_check(ee_spy_seen("fr_log", "Arrived Coldfield Relay", 25) ~= nil,
            "persist: arrival also written to the ship log")
    end)
end)

-- t=60: PULL + LOCATE in phase 2 - orders name the triage; the waypoint aims
-- BETWEEN the broadcasters on purpose (a hull waypoint would spoil the puzzle).
ee_step(60, function()
    fc.dlg = ee_dlg_open(commsMeridian, stations.meridian, fc.crew)
    fc.msgs = ee_dlg_click_by_label(fc.dlg, "What are my current orders?",
        stations.meridian, fc.crew)
    ee_check(#fc.msgs == 1 and fc.msgs[1]:find("scan both") ~= nil,
        "pull: phase-2 orders name the triage")
    fc.rdlg = ee_dlg_open(commsRelay, stations.relay, fc.crew)
    fc.msgs = ee_dlg_click_by_label(fc.rdlg, "Mark the next objective on our nav.",
        stations.relay, fc.crew)
    ee_check(fc.crew:getWaypointCount() >= 2, "locate: phase-2 waypoint added (cap logic ran)")
    local wx, wy = fc_waypoint(fc.crew, fc.crew:getWaypointCount())
    if wx then
        local px, py = polaris:getPosition()
        local dp = math.sqrt((wx - px) ^ 2 + (wy - py) ^ 2)
        ee_check(dp > 2000, "locate: phase-2 waypoint is NOT on Polaris's hull (no spoiler)")
    end
end)

-- t=64: DESCRIPTIONS - the label channel before and after the scan flip.
ee_step(64, function()
    local pre = polaris:getDescription()
    ee_check(string.find(pre, "dark and drifting", 1, true) ~= nil,
        "description: Polaris reads as a dark drifting ship before the scan")
    ee_check(string.find(decoy:getDescription(), "relay tug", 1, true) ~= nil,
        "description: decoy reads as a relay tug before the scan")
    ee_check(probe_scan("polaris") == "scanned", "scan probe works")
    local post = polaris:getDescription()
    -- [obs] probe result (see the FR-COMM log line): getDescription() returns
    -- the BASE text even after setScanStateByFaction("fullscan") - the
    -- scanned-state text is not readable headlessly. Assert the base persists.
    ee_check(string.find(tostring(post), "dark and drifting", 1, true) ~= nil,
        "description: base text persists after the scan (scanned text not readable)")
end)

function ee_on_finish()
    print("FC-COMM: notify calls=" .. #ee_spies.notify.calls
        .. " fr_log calls=" .. #ee_spies.fr_log.calls)
end
