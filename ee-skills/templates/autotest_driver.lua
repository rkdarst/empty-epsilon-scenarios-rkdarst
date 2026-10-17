-- ee-skills/templates/autotest_driver.lua - skeleton for a scenario's test
-- driver. ee_func.sh appends it after lib/autotest.lua, in the same Lua chunk
-- as the scenario, so scenario globals and functions are visible here.
--
-- Discoverable by default when placed at <root>/tests/<scenario-name>.autotest.lua
-- (that location is required: any scenario_*.lua in the scenarios dir would be
-- loaded by the game as a mission). Override with AUTOTEST=path.lua.
--
-- Markers ee_func.sh greps:  EE-ASSERT ok|FAIL|ERROR  /  EE-AUTOTEST done
--
-- Timeline length: ee_func.sh takes its default RUNTIME from a header line of
-- the form `-- ee_runtime: N` (see the bottom of this file), so a plain
-- `ee_func.sh <scenario>` lets the whole schedule play out. ee_finish_at below
-- is the in-world backstop that ends a run early once the timeline is done.

local t = {}                    -- scratch shared between steps

-- ---------------------------------------------------------------- boot state
ee_step(2, function()
    probe_state()                                   -- the scenario's own census
    ee_check(delivered_count() == 0, "mission starts with nothing delivered")
    ee_check(#active_players() >= 1, "at least one crew hull exists")
    -- invariants worth asserting on every scenario:
    --  * nothing at the same coordinates (containers inside a hull, ships in a
    --    station),  * no hidden object already revealed,  * world census totals
    --    match the knob block.
end)

-- ------------------------------------------------------------ dialog contract
ee_step(4, function()
    t.dlg = ee_dlg_open(commsHome, stations.home, active_players()[1])
    ee_check(#t.dlg.msgs == 1, "home page renders exactly one message")
    ee_check(#t.dlg.replies >= 1, "home page offers choices")
    local msgs = ee_dlg_click(t.dlg, 1, stations.home, active_players()[1])
    ee_check(#msgs == 1, "first action renders exactly one message")
end)

-- ---------------------------------------------------------------------------
-- 2. Mission beats: one step per beat, in mission order, each asserting the state
--    the beat must leave behind. Trigger, then poll -- never sample: an organic
--    event finishes when the world is done, not when the timeline says so.
--    These are the idioms to copy once your beats exist; a step that is still a
--    comment cannot pass, so this block doubles as your to-do list
--    (see writing-drivers.md).
--
-- ee_step(20, function()
--     -- probe_deliver_all()   -- or drive it honestly, one beat per step
--     ee_until("phase 2 armed", 45, function() return phase == 2 end)
-- end)
--
-- -- organic kills: something must happen on its own, and the AI needs a moving
-- -- target -- a parked idle hull is parked next to and never shot at.
-- ee_step(60, function()
--     t.pool = {}
--     for i = 1, 2 do
--         t.pool[i] = CpuShip():setTemplate("Adder MK5"):setFaction("Exuari")
--             :setPosition(U(40) + U(i), U(6)):orderFlyTowards(U(90), U(50))
--     end
--     ee_merc_squad("Human Navy", U(40), U(6), t.pool[1], t.pool, 3)
--     ee_until("mercs clear the group organically", 170, function()
--         return all_dead(t.pool)
--     end)
-- end)
--
-- -- anti-softlock: hook-less wipe, then the watchdog must still deliver
-- ee_step(240, function()
--     probe_kill_group("patrol")
--     ee_until("drop-watch still delivers the object", 40, function()
--         return probe_part("Component A") ~= "missing"
--     end)
-- end)
--
-- ee_step(260, function()
--     ee_until("mission reaches a terminal state", 30, function() return done end)
-- end)

-- A fresh skeleton has no beats yet, so the timeline ends here. Raise this as you
-- schedule steps above; ee_finish_at is only the backstop for a hung wait.
ee_finish_at = 45
-- ee_runtime: 60

function ee_on_finish()
    ee_merc_retire()                 -- no stray hulls left in the world
    probe_state()                    -- the scenario's own census, once more
    -- final invariants, once the mission can actually end:
    -- ee_check(done, "final: mission ended")
    -- ee_check(delivered_count() == #PART_NAMES, "final: all objectives delivered")
end
