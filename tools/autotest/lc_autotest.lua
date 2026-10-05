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
        lc_check(probe_has_ftl(), "player ship starts with warp drive")
    end },
    { t = 5, f = function()
        -- Ambient world seeding (counts are deterministic given AMBIENT).
        lc_check(ambient_stats ~= nil and ambient_stats.nebulae >= 40, "ambient nebulae seeded (>=40)")
        lc_check(ambient_stats and ambient_stats.dust >= 800, "ambient dust belts seeded (>=800)")
        lc_check(ambient_stats and ambient_stats.rocks >= 300, "ambient asteroid belts seeded (>=300)")
        lc_check(ambient_stats and ambient_stats.mines >= AMBIENT.mine_fields * 4, "ambient minefields seeded")
        lc_check(ambient_stats and ambient_stats.wrecks >= 4 and ambient_stats.traders >= 4,
            "derelicts and ambient traders afloat")
        local bad = 0
        for _, m in ipairs(ambient_mines) do
            if m:isValid() then
                for _, st in pairs(stations) do
                    if d2(m, st) < U(5) ^ 2 then bad = bad + 1 end
                end
            end
        end
        lc_check(bad == 0, "no ambient mine inside a station keep-out ring")
        lc_check(probe_watch(), "every active player ship is watched (cargo-eject + transfer comms)")
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
        lc_check(probe_has_ftl(), "transports and players all have warp")
        local books = 0
        for _, n in ipairs(BOOK_NAMES) do if parts[n] then books = books + 1 end end
        lc_check(books == 3, "3 playbooks assigned to freighters")
        probe_deliver_books()
    end },
    { t = 37, f = function()
        lc_check(phase3.armed, "all playbooks delivered arms phase 3")
        probe_warp_sector("E15")
    end },
    { t = 28, f = function()
        -- Comms pickup flow (act_* are the exact functions the comms
        -- replies call): containers must spawn OUTSIDE the station hull.
        act_collect_tampere(stations.tampere)
        local obj = parts["H200 GPU nodes"] and parts["H200 GPU nodes"].obj
        lc_check(obj ~= nil and obj:isValid(), "Tampere collect spawns the H200 container")
        lc_check(obj and d2(obj, stations.tampere) > U(4) ^ 2, "H200 container spawns clear of the station hull")
        lc_check(act_collect_tampere(stations.tampere):find("already") ~= nil, "Tampere collect is idempotent")
        act_collect_lut(stations.lut)
        local obj2 = parts["AMD compute nodes"] and parts["AMD compute nodes"].obj
        lc_check(obj2 ~= nil and obj2:isValid(), "LUT collect spawns the AMD container")
        lc_check(obj2 and d2(obj2, stations.lut) > U(4) ^ 2, "AMD container spawns clear of the station hull")
        local cx, cy = obj:getPosition()
        probe_warp_to(cx + U(4), cy)   -- close enough to read, not touching
    end },
    { t = 29.5, f = function()
        -- Proximity reveal must flip the container even though the engine
        -- never advances an Artifact through the scan states.
        lc_check(parts["H200 GPU nodes"].cont.revealed == true, "container reveals its label within 5u")
        probe_warp_sector("H5")   -- back to calm space while phase 1 ends
    end },
    { t = 32, f = function()
        -- Phase-2 freighter comms: stop action + ranged transfer gate.
        local tr = nil
        for _, t in ipairs(transports) do
            if t:isValid() and t.lc_book and not parts[t.lc_book].given and not parts[t.lc_book].delivered then tr = t break end
        end
        lc_check(tr ~= nil, "a playbook freighter is still available")
        if tr then
            act_stop_transport(tr)
            lc_check(tr.lc_stopped == true, "hail can stop a transport")
            local msg, ok = act_transfer_book(tr, active_players()[1])
            lc_check(ok == false, "playbook transfer refused at range")
            local tx, ty = tr:getPosition()
            probe_warp_to(tx + U(1), ty)
            lc_autotest_tr = tr
        end
    end },
    { t = 33, f = function()
        local tr = lc_autotest_tr
        if tr and tr:isValid() then
            local msg, ok = act_transfer_book(tr, active_players()[1])
            lc_check(ok == true, "playbook transfer succeeds alongside the freighter")
            lc_check(parts[tr.lc_book].obj:isValid(), "playbook container appears next to the freighter")
        else
            lc_check(false, "playbook transfer succeeds alongside the freighter")
        end
        probe_warp_sector("E3")
    end },
    { t = 33.5, f = function()
        -- Ship-to-ship transfer of a carried part: refused at range,
        -- accepted alongside (probe restores the bookkeeping state).
        lc_check(probe_transfer("Intel compute nodes", 40000) == false,
            "ship-to-ship part transfer refused at range")
        lc_check(probe_transfer("Intel compute nodes", 1000) == true,
            "ship-to-ship part transfer works alongside")
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
