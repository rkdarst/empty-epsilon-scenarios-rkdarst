-- ee-skills/examples/demo/autotest.lua - self-driving test for the demo
-- mission. Appended after lib/autotest.lua by ee_func.sh, so the ee_* helpers
-- and the scenario's own globals/probes are both in scope.
--
-- The mission: recover two cores and hand them over at Depot. Headless has no
-- human crew, so the driver IS the crew: it warps the player hull around
-- (probe_warp_to), opens dialogs, and kills things either organically (merc
-- squad, so onDestruction fires) or via probe_kill_group (hook-less, so the
-- drop-watch has to catch it). Both drop paths are asserted on purpose.

ee_finish_at = 175
local dem = {}

-- t=2: the world came up as designed.
ee_step(2, function()
    probe_state()
    ee_check(probe_part("Coolant core") == "adrift", "coolant core starts adrift")
    ee_check(probe_part("Nav core") == "adrift", "nav core starts adrift in the cache")
    ee_check(#patrol == DEMO.patrol_n, "cache escorts are in place")
end)

-- t=3: the dialog contract: opening a page renders exactly ONE message and
-- offers replies (a second message means a renderer clobbered the result).
ee_step(3, function()
    dem.dlg = ee_dlg_open(commsDepot, stations.depot, active_players()[1])
    ee_check(#dem.dlg.msgs == 1, "Depot page renders exactly one message")
    ee_check(#dem.dlg.replies >= 3, "Depot page offers its choices")
end)

-- t=4: the range gate: handing over from far away must be refused, not applied.
ee_step(4, function()
    local msgs = ee_dlg_click(dem.dlg, 2, stations.depot, active_players()[1])
    ee_check(#msgs == 1, "hand-over click renders exactly one message")
    ee_check(msgs[1]:find("alongside") ~= nil, "hand-over from open space is refused")
    ee_check(part_count_delivered() == 0, "refused hand-over delivered nothing")
end)

-- t=6: the hidden relay must NOT be a friendly contact at boot: same-faction
-- objects are always on the crew's list, so hiding means faction neutrality.
ee_step(6, function()
    ee_check(stations.waypoint:getFaction() == "Independent",
        "hidden relay boots without our transponder")
end)

-- t=8: fly inside the find radius; reveal is a polling transition, so poll.
ee_step(8, function()
    probe_warp_to(U(28), 0)
    ee_until("hidden relay flips to our faction when reached", 10,
        function() return found_waypoint end)
    ee_until("and its relay telemetry comes back up", 10,
        function() return stations.waypoint:getFaction() == "Human Navy" end)
end)

-- t=12: the shipping label is two-state: unreadable far away, specific close in.
ee_step(12, function()
    for _, c in ipairs(containers) do
        if c.name == "Coolant core" then
            local x, y = c.a:getPosition()
            probe_warp_to(x + U(DEMO.reveal_u + 2), y)
        end
    end
end)
ee_step(13, function()
    for _, c in ipairs(containers) do
        if c.name == "Coolant core" then
            ee_check(not c.revealed, "label stays unmarked beyond the reveal radius")
            local x, y = c.a:getPosition()
            probe_warp_to(x + U(2), y)
        end
    end
end)
ee_step(14, function()
    ee_until("label resolves to its contents once alongside", 6, function()
        for _, c in ipairs(containers) do
            if c.name == "Coolant core" and c.revealed then return true end
        end
        return false
    end)
end)


-- t=16: hook-less death must not softlock the mission. probe_kill_group uses
-- destroy(), which NEVER fires onDestruction - only the polled watcher can drop.
ee_step(16, function()
    probe_kill_group("patrol")
    ee_until("drop-watch recovers the guarded core after a hook-less kill",
        DEMO.grace_s + 15, function() return probe_part("Nav core") == "adrift" end)
end)

-- t=20: the organic path. A fresh escort squad the mercenaries must actually
-- shoot down; the watcher must not duplicate the crate that is already out.
ee_step(20, function()
    probe_warp_to(U(70), U(40))
    local x, y = stations.cache:getPosition()
    dem.pool = {}
    for i = 1, 2 do
        -- Moving targets matter: a Starhammer II squad parks ~11u from an IDLE
        -- target and never lands a shot, while a fleeing ship gets chased down
        -- and killed. So this squad is ordered away, like a courier running for
        -- it, which is also what the escort in the fiction is doing.
        local s = CpuShip():setTemplate("Adder MK5"):setFaction("Exuari")
            :setPosition(x + U(2), y + U(2) * i):orderFlyTowards(U(90), U(50))
        table.insert(dem.pool, s)
    end
    dem.cache_before = probe_part("Nav core")
    ee_merc_squad("Human Navy", x, y, dem.pool[1], dem.pool, 2)
    ee_merc_dump("deployed")
    ee_until("mercenaries wipe the fresh escort squad organically", 85,
        function() return all_dead(dem.pool) end)
end)
ee_step(112, function()
    ee_check(probe_part("Nav core") == dem.cache_before,
        "an organic kill after the watchdog fired does not duplicate the core")
end)

-- t=150: collect what is lying around. Real collection is collision based and a
-- teleported hull does not collide, so probe_pickup stands in for it (the real
-- path shares the same bookkeeping); see testing/runtime-surprises.md.
ee_step(118, function()
    for _, name in ipairs(PART_NAMES) do
        local info = parts[name]
        if info and info.obj and info.obj:isValid() then
            local x, y = info.obj:getPosition()
            probe_warp_to(x, y)                         -- stand where the crate is
            ee_check(probe_pickup(name) == "carried", "core " .. name .. " collected")
        end
    end
end)

-- t=150: finish through the real dialog action, at the real distance.
ee_step(135, function()
    probe_warp_to(-U(20) + U(1.2), 0)          -- alongside Depot (Medium: hull 1.0u)
    local d = ee_dlg_open(commsDepot, stations.depot, active_players()[1])
    local msgs = ee_dlg_click(d, 2, stations.depot, active_players()[1])
    ee_check(#msgs == 1, "hand-over from alongside renders one message")
    ee_check(msgs[1]:find("Received") ~= nil, "hand-over from alongside is accepted")
end)

ee_step(150, function()
    ee_until("mission ends in victory once both cores are in", 20,
        function() return done and part_count_delivered() == #PART_NAMES end)
end)

function ee_on_finish()
    ee_check(part_count_delivered() == #PART_NAMES, "final: both cores delivered")
    ee_check(found_waypoint, "final: relay was discovered")
    ee_merc_retire()
end
