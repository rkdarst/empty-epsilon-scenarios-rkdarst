-- Tick driver for scenario_41_lostcluster_dsl.lua (mission-DSL twin).
-- Appended by tools/func_test.sh via AUTOTEST=tools/autotest/gen41_autotest.lua:
-- lets update() run live, then asserts the generator tick loop works
-- (events fired, archetype spawn + n_alive tracking, no runtime errors).
local ticks = 0
local done41 = false
local _up41 = update
function update(delta)
    _up41(delta)
    ticks = ticks + 1
    if not done41 and gen.clock > 26 then
        done41 = true
        assert(gen_event_fired("thieves"), "thieves event did not fire")
        assert(gen_alive("raider") == 2, "raiders not spawned: " .. gen_alive("raider"))
        print("LC-AUTOTEST done (41-lite ticks=" .. ticks
            .. " stage=" .. gen.stage .. ")")
    end
end