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

-- Dialog walker: stubs the two comms globals and drives the SAME functions
-- the engine's CommsScriptInterface drives (page function to open, reply
-- callback to click). The engine clears all replies before running a reply
-- callback and every setCommsMessage inside it REPLACES the text, so a well
-- behaved page produces EXACTLY ONE message; two means a menu renderer
-- clobbered the action result and the player sees nothing happen.
lc_dlg = { msgs = {}, replies = {} }
local lc_real_set, lc_real_add = setCommsMessage, addCommsReply

local function lc_dlg_capture()
    lc_dlg.msgs, lc_dlg.replies = {}, {}
    setCommsMessage = function(m) table.insert(lc_dlg.msgs, tostring(m)) end
    addCommsReply = function(label, f) table.insert(lc_dlg.replies, { label = label, fn = f }) end
end

local function lc_dlg_restore()
    setCommsMessage, addCommsReply = lc_real_set, lc_real_add
end

function lc_dlg_open(fn, t, src)
    lc_dlg_capture()
    local ok, err = pcall(fn, t, src)
    lc_dlg_restore()
    lc_check(ok, "dialog opens without error: " .. (ok and tostring(t) or tostring(err)))
    return lc_dlg
end

-- Click reply `idx` the way commChannelMessage() does: replies cleared,
-- callback called with (ship, station). Returns messages rendered.
function lc_dlg_click(d, idx, t, src)
    local reply = d.replies[idx]   -- grab BEFORE the capture clears the list
    if reply == nil then
        lc_check(false, "dialog has a reply #" .. idx)
        return {}
    end
    lc_dlg_capture()
    local ok, err = pcall(reply.fn, src, t)
    lc_dlg_restore()
    lc_check(ok, "reply click runs without error: " .. tostring(err or reply.label))
    return d.msgs
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
        -- Wormhole pair: exits must land OUTSIDE the far mouth's 2.5U pull
        -- radius or the engine perma-loops the traveler (wormHole.cpp has no
        -- re-entry cooldown). Also exercise the script-side bounce guard.
        lc_check(not AMBIENT.wormholes or #ambient_wh == 2, "wormhole pair seeded")
        local far = true
        for _, wh in ipairs(ambient_wh) do
            local tx, ty = wh.obj:getTargetPosition()
            local px, py = wh.partner:getPosition()
            if (tx - px) ^ 2 + (ty - py) ^ 2 <= 3000 ^ 2 then far = false end
        end
        lc_check(#ambient_wh ~= 2 or far, "wormhole exits sit outside the far mouth's pull radius")
        if #ambient_wh == 2 then
            local p = active_players()[1]
            local x0, y0 = p:getPosition()
            local wh = ambient_wh[1]
            wh_transit(wh, p)   -- fresh transit must NOT override the drop
            local x1, y1 = p:getPosition()
            lc_check(x0 == x1 and y0 == y1, "first wormhole transit leaves the drop position alone")
            local tx, ty = wh.obj:getTargetPosition()
            p:setPosition(tx + wh.dirx * 400, ty + wh.diry * 400)   -- worst-case engine drop
            wh_transit(wh, p)   -- immediate re-entry attempt
            local px, py = wh.partner:getPosition()
            local x2, y2 = p:getPosition()
            lc_check((x2 - px) ^ 2 + (y2 - py) ^ 2 > 4500 ^ 2,
                "wormhole re-entry within cooldown is pushed clear of the far mouth")
            p:setPosition(x0, y0)
        end
    end },
    { t = 5.2, f = function()
        -- Dialog-tree regression walk (before anyone nears Tampere): stub
        -- the comms globals, click every choice on every page. Exactly ONE
        -- message per rendered page = the overwrite bug cannot return.
        local p = active_players()[1]
        local function walk(fn, st, min_replies, tag)
            local d = lc_dlg_open(fn, st, p)
            lc_check(#d.msgs == 1, tag .. ": menu page renders one message")
            lc_check(#d.replies >= min_replies, tag .. ": menu offers its choices")
            return d
        end
        local d = walk(commsLumina, stations.lumina, 2, "Lumina 1")
        lc_dlg_click(d, 1, stations.lumina, p)
        lc_check(#lc_dlg.msgs == 1 and #lc_dlg.replies >= 2, "Lumina status page: message + menu stays live")
        d = walk(commsKajaani, stations.kajaani, 2, "Kajaani 1")
        lc_dlg_click(d, 1, stations.kajaani, p)
        lc_check(#lc_dlg.msgs == 1 and known.tampere, "Kajaani intel page: one message, hints unlocked")
        lc_dlg_click(d, 2, stations.kajaani, p)
        lc_check(#lc_dlg.msgs == 1 and #lc_dlg.replies == 0, "Kajaani goodbye is a clean terminal page")
        d = walk(commsTampere, stations.tampere, 2, "Tampere 1")
        lc_dlg_click(d, 2, stations.tampere, p)   -- LUT question from far away
        lc_check(#lc_dlg.msgs == 1 and known.lut ~= true, "Tampere refuses the LUT coordinates at range")
        lc_dlg_click(d, 1, stations.tampere, p)   -- collect H200 via the dialog
        lc_check(#lc_dlg.msgs == 1 and parts["H200 GPU nodes"].obj:isValid(),
            "Tampere collect reply shows its result AND spawns the container")
        d = walk(commsTurku, stations.turku, 1, "Turku 1")
        lc_dlg_click(d, 1, stations.turku, p)
        lc_check(#lc_dlg.msgs == 1 and #lc_dlg.replies == 1, "Turku tip page: message keeps its choice")
        d = walk(commsLUT, stations.lut, 1, "LUT 1 (friendly)")
        lc_dlg_click(d, 1, stations.lut, p)
        lc_check(#lc_dlg.msgs == 1, "LUT friendly page click renders one message")
        d = lc_dlg_open(commsPlayerShip, p, p)
        lc_check(#d.msgs == 1 and #d.replies == 0, "self-hail of player ship is a clean one-liner")
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
        lc_check(taunt_armed[active_players()[1]] ~= false, "one-ship group is not taunted at LUT")
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
        -- Phase-2 freighter comms through the dialog tree: stop option,
        -- then a ranged transfer attempt that must be refused.
        local tr = nil
        for _, t in ipairs(transports) do
            if t:isValid() and t.lc_book and not parts[t.lc_book].given and not parts[t.lc_book].delivered then tr = t break end
        end
        lc_check(tr ~= nil, "a playbook freighter is still available")
        if tr then
            local p = active_players()[1]
            local tx, ty = tr:getPosition()
            probe_warp_to(tx - U(20), ty)   -- deterministic "at range"
            local d = lc_dlg_open(commsTransport, tr, p)
            lc_check(#d.msgs == 1 and #d.replies == 1, "unstopped freighter page offers the stop option")
            lc_dlg_click(d, 1, tr, p)
            lc_check(tr.lc_stopped == true and #lc_dlg.msgs == 1 and #lc_dlg.replies == 1,
                "dialog stop action works and immediately offers the transfer")
            lc_dlg_click(d, 1, tr, p)   -- transfer attempt from out of range
            lc_check(parts[tr.lc_book].given ~= true and #lc_dlg.replies == 1,
                "playbook transfer refused at range, choice re-offered")
            probe_warp_to(tx + U(1), ty)
            lc_autotest_tr = tr
        end
    end },
    { t = 33, f = function()
        local tr = lc_autotest_tr
        if tr and tr:isValid() then
            local p = active_players()[1]
            local d = lc_dlg_open(commsTransport, tr, p)
            lc_dlg_click(d, 1, tr, p)
            lc_check(parts[tr.lc_book].given == true,
                "playbook transfer succeeds alongside the freighter")
            lc_check(#lc_dlg.msgs == 1 and #lc_dlg.replies == 0,
                "transfer result page renders one message and ends cleanly")
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
