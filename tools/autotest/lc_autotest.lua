-- lc_autotest.lua: scenario self-driver for headless functional testing.
-- tools/func_test.sh concatenates this AFTER a copy of the scenario, so
-- production scenarios need no test hooks at all.
lc_autotest_ok, lc_autotest_fail = 0, 0

function lc_check(cond, msg)
    if cond then
        lc_autotest_ok = lc_autotest_ok + 1
        print("LC-ASSERT ok: " .. msg)
    else
        lc_autotest_fail = lc_autotest_fail + 1
        print("LC-ASSERT FAIL: " .. msg)
    end
end

steps = {
    { t = 3, f = function()
        lc_check(phase == 1, "boots into phase 1")
    end },
    { t = 6, f = function() probe_warp_sector("H5") end },
    { t = 14, f = function()
        lc_check(tampere_state == "ambush" and #groups.ambush == 3, "Tampere ambush warps in on approach")
        probe_kill_group("ambush")
    end },
    { t = 18, f = function()
        lc_check(tampere_state == "clear", "Tampere clears after ambush destroyed")
        probe_warp_sector("L3")
    end },
    { t = 26, f = function()
        lc_check(lut_state == "hostile", "LUT turns hostile on approach")
        lc_check(#groups.lut >= 2, "LUT garrison scales with players")
        lc_check(taunt_armed[active_players()[1]] == false, "solo player gets taunted at LUT")
        probe_kill_group("lut")
    end },
    { t = 30, f = function()
        lc_check(lut_state == "liberated", "LUT liberated after garrison destroyed")
        probe_warp_sector("E3")
        probe_deliver_all()
    end },
    { t = 34, f = function()
        lc_check(phase == 2, "all parts delivered starts phase 2")
        lc_check(#transports == 10, "10 transports launched")
        local books = 0
        for _, n in ipairs(BOOK_NAMES) do if parts[n] then books = books + 1 end end
        lc_check(books == 3, "3 playbooks assigned to freighters")
        probe_deliver_books()
    end },
    { t = 37, f = function()
        lc_check(phase3.armed, "all playbooks delivered arms phase 3")
        probe_warp_sector("E15")
    end },
    { t = 41, f = function()
        lc_check(phase3.warned, "leaving base triggers the invasion warning")
        phase3.timer = 3
    end },
    { t = 44, f = function() phase3.timer = 1 end },
    { t = 47, f = function()
        lc_check(phase3.spawned and #groups.wave > 0, "invasion wave spawns")
        print(string.format("LC-AUTOTEST done: %d ok, %d fail", lc_autotest_ok, lc_autotest_fail))
    end },
    { t = 48.5, f = function()
        probe_kill_group("wave")   -- scenario should now declare victory and stop ticking
    end },
}

function lc_run_steps()
    for _, s in ipairs(steps) do
        if not s.done and clock >= s.t then
            s.done = true
            local ok, err = pcall(s.f)
            if not ok then
                lc_autotest_fail = lc_autotest_fail + 1
                print("LC-ASSERT ERROR: " .. tostring(err))
            end
        end
    end
end

-- Wrap the scenario update so steps keep running even after victory.
local orig_update = update
function update(delta)
    lc_run_steps()
    return orig_update(delta)
end
