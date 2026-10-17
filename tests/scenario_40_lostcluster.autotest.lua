-- scenario_40_lostcluster autotest driver: self-driving timeline for headless runs.
-- tools/func_test.sh concatenates this AFTER a copy of the scenario, so
-- production scenarios need no test hooks at all. Living in tests/ (named after
-- the scenario) is what makes func_test.sh discover it automatically.
--
-- The schedule below runs to ~70 game seconds, so declare the length for the
-- runner (a plain `tools/func_test.sh <scenario>` then lets it finish;
-- RUNTIME=N still overrides from the outside).  See ee-skills/bin/ee_func.sh.
-- ee_runtime: 80

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

-- The engine fires onDestruction ONLY on damage kills (takeHullDamage), and
-- scripts have no damage API - so hook-driven deaths (b300 drop, transport
-- spill, playbook guards) are killed organically by a mercenary Starhammer
-- ordered onto the target. They are retired (plain destroy, hook-less) when
-- their job is done.

-- A Starhammer II AI fires only its HVLI tubes (ShipAI::runAttack has no
-- beam fire at all). Gluing ships with per-tick setPosition instead of
-- letting them fly ruins the missile lead solution (probe5: natural AI
-- kills a defending Adder in ~18 s; teleported ships never land a hit).
-- So: one orderAttack per target, warp drive for chase, and the driver
-- only intervenes when a ship has been stuck >4U for 2 s (nebula-camping
-- targets go radar-dark and the AI parks) - one clean teleport, no spam.
-- After a kill the engine AI keeps the dead order_target forever, so the
-- driver retargets the squad onto the next pool survivor itself.
lc_mercs = {}
lc_pools = {}
function lc_merc(fac, x, y, target, pool)
    local ang = (#lc_mercs + 1) * 2.1
    local sx, sy = x + math.cos(ang) * 2500, y + math.sin(ang) * 2500
    local s = CpuShip():setTemplate("Starhammer II"):setFaction(fac)
        :setPosition(sx, sy)
    s:setWarpDrive(true)
    s:setWarpSpeed(1000)           -- needed to catch 80 u/s freighters
    s:orderAttack(target)
    s:setCallSign("Merc " .. (#lc_mercs + 1))
    s.lc_target = target
    s.lc_pool = pool
    s.lc_stale = 0
    table.insert(lc_mercs, s)
    return s
end

function lc_merc_squad(fac, x, y, target, pool, n)
    for _ = 1, (n or 3) do lc_merc(fac, x, y, target, pool) end
end

function lc_merc_update()
    for _, m in ipairs(lc_mercs) do
        if m:isValid() then
            local t = m.lc_target
            if t and (not t:isValid()) and m.lc_pool then
                t = nil   -- engine AI never drops an explicit attack order
                for _, c in ipairs(m.lc_pool) do
                    if c ~= "dead" and c ~= nil and c:isValid() then t = c break end
                end
                m.lc_target = t
                m.lc_stale = 0
                if t then m:orderAttack(t) end
            end
            if t and t:isValid() then
                local mx, my = m:getPosition()
                local tx, ty = t:getPosition()
                local dx, dy = tx - mx, ty - my
                local d = math.sqrt(dx * dx + dy * dy)
                if d > 2000 then
                    m.lc_stale = m.lc_stale + 1
                    if m.lc_stale > 90 then   -- parked (radar-dark target?):
                        m.lc_stale = 0        -- one clean drop-in, no spam
                        m:setPosition(tx - dx / d * 2000, ty - dy / d * 2000)
                        m:orderAttack(t)
                    end
                else
                    m.lc_stale = 0
                end
            end
        end
    end
end

function lc_merc_retire()
    for _, pool in ipairs(lc_pools) do           -- scripted teardown first:
        for _, c in ipairs(pool) do              -- hook-less destroy so no
            if c ~= "dead" and c ~= nil and c:isValid() then c:destroy() end
        end                                      -- stray spills/respawns later
    end
    for _, m in ipairs(lc_mercs) do
        if m:isValid() then m:destroy() end   -- hooks never fire on script destroy
    end
    lc_mercs = {}
    lc_pools = {}
end

-- probe_has_ftl() with the warp-stripped prey excluded (the freighter the
-- mercenaries chase must stay on impulse: HVLI cannot lead a warp target).
function probe_has_ftl_excluding(skip)
    local missing = 0
    for _, p in ipairs(active_players()) do
        if p:isValid() and not p:hasWarpDrive() then missing = missing + 1 end
    end
    for _, t in ipairs(transports) do
        if t:isValid() and t ~= skip and not t:hasWarpDrive() then missing = missing + 1 end
    end
    print("LC-PROBE ships missing warp drive: " .. missing)
    return missing == 0
end

-- Ejection geometry: a container must clear the station hull (the pickup is a
-- collision and the hull is solid) and still sit inside that station's
-- hand-over bubble, or the crate ends up somewhere the player cannot reach
-- from the position the station talks to them from.
function lc_eject_ok(part_name, obj, st, msg)
    if obj == nil or not obj:isValid() then
        lc_check(false, msg .. " (no container)")
        return
    end
    local ox, oy = obj:getPosition()
    local sx, sy = st:getPosition()
    local d = math.sqrt((ox - sx) ^ 2 + (oy - sy) ^ 2) / 1000
    local hull, reach = station_hull_u(st), handover_u(st)
    lc_check(d > hull, msg .. ": clear of the " .. string.format("%.2f", hull) ..
        "u hull (at " .. string.format("%.2f", d) .. "u)")
    lc_check(d <= reach, msg .. ": inside the " .. string.format("%.2f", reach) ..
        "u hand-over bubble (at " .. string.format("%.2f", d) .. "u)")
end

function lc_merc_dump(tag)
    local out = {}
    for i, m in ipairs(lc_mercs) do
        if m:isValid() then
            local x, y = m:getPosition()
            local t = m.lc_target
            local info
            if t == nil then info = "?"
            elseif not t:isValid() then info = "k"
            else
                local tx, ty = t:getPosition()
                local okh, hull = pcall(t.getHull, t)
                info = string.format("%.1fU/%s", math.sqrt((tx - x) ^ 2 + (ty - y) ^ 2) / 1000,
                    okh and tostring(hull):sub(1, 5) or "?")
            end
            table.insert(out, m:getCallSign() .. "(" .. info .. ")")
        else
            table.insert(out, i .. ":dead")
        end
    end
    print("LC-MERC[" .. tag .. "] " .. table.concat(out, " "))
end
-- completes the stage silently or, on the final poll, records the failure.
lc_b300_state = "wait"
function lc_b300_poll(final)
    if lc_b300_state == "wait" then
        local alive = 0
        for _, s in ipairs(groups.b300) do if s:isValid() then alive = alive + 1 end end
        if alive == 0 then
            local n = 0
            for _, c in ipairs(containers) do
                if c.name == "B300 GPU nodes" and c.a:isValid() then n = n + 1 end
            end
            lc_check(n <= 1 and (n == 1 or parts["B300 GPU nodes"].delivered),
                "the B300 patrol's death drops the part container exactly once")
            b300_died(groups.b300[1])   -- a spurious re-fire must not duplicate the part
            local n2 = 0
            for _, c in ipairs(containers) do
                if c.name == "B300 GPU nodes" and c.a:isValid() then n2 = n2 + 1 end
            end
            lc_check(n2 == n, "a spurious b300_died re-fire does not duplicate the container")
            lc_check(true, "b300 patrol wiped out by the mercenaries")
            lc_b300_state = "done"
        elseif final then
            lc_check(false, "b300 patrol wiped out by the mercenaries")
        end
    end
end

lc_guard_state = "wait"
function lc_guard_poll(final)
    local slot = lc_autotest_slot
    if slot == nil then
        if final then lc_check(false, "guard slot 1 was recorded") end
        return
    end
    if lc_guard_state == "wait" then
        local died = (not slot.ships[1]:isValid()) or (not slot.ships[2]:isValid())
        if died and slot.respawns_left < 2 then
            lc_check(true, "a damage-killed playbook guard spends one respawn credit")
            slot.respawn_at = clock - 1   -- fast-forward the 60 s timer
            lc_guard_state = "ff"
        elseif final then
            lc_check(false, "a damage-killed playbook guard spends one respawn credit")
        end
    elseif lc_guard_state == "ff" then
        if #slot.ships > 2 and slot.ships[#slot.ships]:isValid() then
            lc_check(true, "the playbook guard respawns beside the freighter")
            lc_guard_state = "done"
        elseif final then
            lc_check(false, "the playbook guard respawns beside the freighter")
        end
    end
end

lc_tr_state = "wait"
function lc_tr_poll(final)
    local dsc = lc_autotest_dead
    if dsc == nil then
        if final then lc_check(false, "the booked freighter casualty was recorded") end
        return
    end
    if lc_tr_state == "wait" then
        local info = parts[dsc.book]
        if info and info.given and info.obj and info.obj:isValid() then
            lc_check(true, "destroying a booked freighter spills the playbook container")
            dsc.tr.lc_respawn_at = clock - 1   -- fast-forward the 30 s replacement
            lc_tr_state = "ff"
        elseif final then
            -- Say which half failed: a freighter the squad never caught is a
            -- different problem from a spill that produced no container.
            local alive = dsc.tr:isValid()
            lc_check(false, "destroying a booked freighter spills the playbook container"
                .. " (freighter " .. (alive and "still alive at t=" .. math.floor(clock)
                    .. " after a " .. math.floor(clock - 30.8) .. "s chase"
                    .. ", and the t=50 backstop kill did not land"
                    or "is dead but parts[" .. tostring(dsc.book) .. "].given="
                    .. tostring(info and info.given) .. " obj valid="
                    .. tostring(info and info.obj and info.obj:isValid())))
        end
    elseif lc_tr_state == "ff" then
        local t = transports[dsc.idx]
        if t ~= nil and t:isValid() and t.lc_book == nil and t:getCallSign() == dsc.sign then
            lc_check(true, "an unbooked replacement freighter took over the casualty's callsign")
            lc_tr_state = "done"
        elseif final then
            lc_check(false, "an unbooked replacement freighter took over the casualty's callsign")
        end
    end
end

steps = {
    { t = 3, f = function()
        lc_check(phase == 1, "boots into phase 1")
        lc_check(probe_has_ftl(), "player ship starts with warp drive")
        -- A "hidden" station must not be a friendly contact: same-faction
        -- objects are shared over relay telemetry no matter what nebula hides
        -- them, so hiding is done by staying Independent until discovered.
        lc_check(probe_hidden(), "hidden stations boot as non-Human-Navy contacts")
        print("LC-PROBE difficulty=" .. tostring(LC_DIFFICULTY) .. " story=" .. tostring(STORY_MODE))
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
        -- Mouths and exits must also keep clear of mission containers: the
        -- 2.5U drag zone teleports whatever it catches to 3.5U past the
        -- partner, which once flung a Turku ring part across the map (the
        -- container stayed valid, so only its distance from the station gave
        -- it away). The scenario keeps 4U of clearance at seed time.
        local near_cargo = false
        for _, wh in ipairs(ambient_wh) do
            local mx2, my2 = wh.obj:getPosition()
            local ex2, ey2 = wh.obj:getTargetPosition()
            local px2, py2 = wh.partner:getPosition()
            local fx2, fy2 = wh.partner:getTargetPosition()
            for _, pt in ipairs({ { mx2, my2 }, { ex2, ey2 }, { px2, py2 }, { fx2, fy2 } }) do
                for _, c in ipairs(containers) do
                    if c.a and c.a:isValid() then
                        local ox, oy = c.a:getPosition()
                        if (pt[1] - ox) ^ 2 + (pt[2] - oy) ^ 2 < U(4) ^ 2 then near_cargo = true end
                    end
                end
            end
        end
        lc_check(#ambient_wh ~= 2 or not near_cargo, "wormhole mouths/exits keep clear of mission containers")
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
        lc_check(#d.replies == 3, "Lumina menu also offers free homing replenishment")
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
        lc_check(#lc_dlg.msgs == 1 and #lc_dlg.replies >= 1, "Turku tip page: message keeps its choice")
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
        lc_check(stations.tampere:getFaction() == "Human Navy",
            "a hidden station joins the friendly contact list only after discovery")
        probe_warp_sector("L3")
    end },
    { t = 12, f = function()
        -- B300 thieves in C10: two mercenaries per patrol ship so the four
        -- damage kills run in parallel (pool = whole group for retargeting;
        -- polled 26.5..52).
        table.insert(lc_pools, groups.b300)
        for i = 1, 8 do
            local tgt = groups.b300[((i - 1) % #groups.b300) + 1]
            local bx, by = tgt:getPosition()
            lc_merc("Human Navy", bx, by, tgt, groups.b300)
        end
    end },
    { t = 19, f = function()
        -- Turku sortie: the whole Turku side of the map.
        probe_warp_sector("B2")
    end },
    { t = 19.4, f = function()
        lc_check(turku_greeted, "Turku 1 greets ships entering the perimeter")
        local junk = 0
        for _, c in ipairs(containers) do if c.junk then junk = junk + 1 end end
        lc_check(junk == TURKU_JUNK + TURKU_LOOSE_JUNK + 3,
            "Turku ring + loose + Infiniband junk decoys seeded (" .. junk .. ")")
        lc_check(probe_turku_field(), "Turku caches sit on the designed nebula ring")
        local near_t = 0
        for _, n in ipairs({ "Intel compute nodes", "Lustre fileserver" }) do
            local o = parts[n] and parts[n].obj
            if o and o:isValid() and d2(o, stations.turku) < U(TURKU_R_MAX + 3) ^ 2 then near_t = near_t + 1 end
        end
        lc_check(near_t == 2, "both Turku part containers adrift near the station")
        lc_check(taunt_armed[active_players()[1]] == true,
            "the lone skipper far from LUT re-arms the split-group taunt flag")
    end },
    { t = 19.6, f = function()
        lc_check(lut_state == "hostile", "LUT stands revealed as the sortie leaves L3")
        local d = lc_dlg_open(commsLUT, stations.lut, active_players()[1])
        lc_check(#d.msgs == 1 and #d.replies == 0, "hostile LUT page is the taunt only, no dead-end menu")
    end },
    { t = 20.5, f = function()
        -- Lumina dialog handover path: who-has page, a partial organic
        -- delivery through the dialog, and the once-only Infiniband hint.
        local p = active_players()[1]
        parts["B300 GPU nodes"] = parts["B300 GPU nodes"]
            or { carried = false, delivered = false }   -- may predate the wreck drop
        parts["B300 GPU nodes"].carried = p   -- simulate picking the wreck's cargo up
        -- Hand-over geometry first (throwaway carrier, state restored): a
        -- crate cannot be handed over across a solar system.
        lc_check(probe_handover("far") == false, "hand-over refused from 20u away")
        lc_check(probe_handover("near") == true, "hand-over accepted alongside the hull")
        probe_warp_sector("E3")   -- the dialog path needs the player alongside
        local d = lc_dlg_open(commsLumina, stations.lumina, p)
        lc_check(#d.msgs == 1 and #d.replies == 4, "Lumina offers the handover while carrying cargo")
        lc_dlg_click(d, 2, stations.lumina, p)   -- who has what
        lc_check(#lc_dlg.msgs == 1 and lc_dlg.msgs[1]:find("Kajaani 1", 1, true) ~= nil,
            "who-has page names the station chain")
        lc_dlg_click(d, 3, stations.lumina, p)   -- hand it over
        lc_check(parts["B300 GPU nodes"].delivered and infini_hint_given and known.infini,
            "dialog handover delivers the part and opens the Infiniband hint once")
        local m3 = table.concat(lc_dlg.msgs, " ~ "):gsub("\n", " / ")
        lc_check((lc_dlg.msgs[1] or ""):find("mid-map box", 1, true) ~= nil,
            "the delivery page itself carries the hint | n=" .. #lc_dlg.msgs ..
            " phase=" .. tostring(phase) .. " got: " .. m3:sub(1, 300))
        lc_dlg_click(d, 1, stations.lumina, p)   -- status page (handover choice is gone)
        local m4 = table.concat(lc_dlg.msgs, " ~ "):gsub("\n", " / ")
        lc_check(#d.replies == 3 and m4:find("[x] B300 GPU nodes", 1, true) ~= nil
            and m4:find("mid-map box", 1, true) ~= nil,
            "status page reflects delivery+hint, no phantom handover | n=" .. #lc_dlg.msgs ..
            " phase=" .. tostring(phase) .. " got: " .. m4:sub(1, 300))
        -- Free homings: drain the tubes, ask, and the racks must come back
        -- full. Nothing else is for sale, so no other storage may move.
        local got, mx = 0, 0
        pcall(function() got = p:getWeaponStorage("Homing") or 0 end)
        pcall(function() mx = p:getWeaponStorageMax("Homing") or 0 end)
        pcall(function() p:setWeaponStorage("Homing", 0) end)
        local dp = lc_dlg_open(commsLumina, stations.lumina, p)
        lc_dlg_click(dp, #dp.replies, stations.lumina, p)   -- last choice = replenish
        local got2 = got
        pcall(function() got2 = p:getWeaponStorage("Homing") or 0 end)
        local msg = lc_dlg.msgs[1] or ""
        if mx > 0 then
            lc_check(got2 == mx and msg:find("homing missiles") ~= nil,
                "station reloads homing missiles for free (" .. got2 .. "/" .. mx .. ")")
        else
            lc_check(msg:find("no homing tubes") ~= nil,
                "hull without homing tubes gets an explicit refusal, not silence")
        end
    end },
    { t = 26, f = function()
        lc_check(lut_state == "hostile", "LUT turns hostile on approach")
        lc_check(#groups.lut >= 2, "LUT garrison scales with players")
        lc_check(taunt_armed[active_players()[1]] ~= false, "one-ship group is not taunted at LUT")
        probe_kill_group("lut")
    end },
    { t = 26.5, f = function()
        lc_merc_dump("b300"); lc_b300_poll(false)
    end },
    { t = 30, f = function() lc_b300_poll(false) end },
    { t = 33, f = function() lc_b300_poll(false) end },
    { t = 36, f = function() lc_b300_poll(false) end },
    { t = 40, f = function() lc_b300_poll(false) end },
    { t = 43, f = function() lc_b300_poll(false) end },
    { t = 48, f = function() lc_b300_poll(false) end },
    { t = 52, f = function() lc_b300_poll(true) end },
    { t = 30, f = function()
        lc_check(lut_state == "liberated", "LUT liberated after garrison destroyed")
        probe_warp_sector("E3")
        probe_deliver_all()
    end },
    { t = 34, f = function()
        lc_check(phase == 2, "all parts delivered starts phase 2")
        lc_check(#transports == 10, "10 transports launched")
        lc_check(probe_has_ftl_excluding(lc_autotest_dead and lc_autotest_dead.tr),
            "transports and players all have warp")
        local books = 0
        for _, n in ipairs(BOOK_NAMES) do if parts[n] then books = books + 1 end end
        lc_check(books == 3, "3 playbooks assigned to freighters")
    end },
    { t = 34.6, f = function()
        -- Late joiner: a second player ship appearing mid-mission must pick
        -- up every hook (watch loop + ensure_ftl) on the next tick.
        local lx, ly = stations.lumina:getPosition()
        local ok, err = pcall(function()
            lc_autotest_p2 = PlayerSpaceship():setFaction("Human Navy"):setTemplate("Phobos M3P")
                :setPosition(lx - 5000, ly - 5000):setCallSign("Beta")
        end)
        lc_check(ok and lc_autotest_p2 ~= nil, "second player ship spawns: " .. tostring(err))
    end },
    { t = 35.2, f = function()
        local p2 = lc_autotest_p2
        if p2 == nil then lc_check(false, "late joiner exists"); return end
        local seen = false
        for _, p in ipairs(active_players()) do
            if p:isValid() and p:getCallSign() == "Beta" then seen = true end
        end
        lc_check(p2:isValid() and seen, "late joiner counts as an active player ship")
        lc_check(p2.lc_watched == true, "late joiner picked up the cargo/comms hooks")
        lc_check(p2:hasWarpDrive(), "late joiner received a warp drive")
    end },
    { t = 35.6, f = function()
        if lc_autotest_p2 then lc_autotest_p2:destroy() end
        lc_autotest_p2 = nil
    end },
    { t = 36.0, f = function()
        local beta = false
        for _, p in ipairs(active_players()) do
            if p:isValid() and p:getCallSign() == "Beta" then beta = true end
        end
        lc_check(not beta, "the departed joiner is no longer an active player ship")
        lc_check(probe_watch(), "every remaining player ship is still hooked")
    end },
    { t = 37, f = function()
        probe_warp_sector("E15")
    end },
    { t = 33, f = function() lc_tr_poll(false) end },
    { t = 36, f = function() lc_tr_poll(false) end },
    { t = 38, f = function() lc_merc_dump("late"); lc_tr_poll(false) end },
    { t = 44, f = function() lc_tr_poll(false) end },
    { t = 48.2, f = function() lc_merc_dump("tr48"); lc_tr_poll(false) end },
    { t = 50, f = function()
        -- The mercenary squad is the natural killer, but the fact under test is the
        -- spill on a *damage* death, not merc AI, and a fleeing target in a 520-rock
        -- field makes that a coin flip. If the chase is still unresolved, land the
        -- identical damage kill here and say so in the log: the answer becomes
        -- deterministic instead of occasional.
        local dsc = lc_autotest_dead
        if dsc ~= nil and lc_tr_state == "wait" and dsc.tr:isValid() then
            print("LC-PROBE mercenary chase unresolved at t=50 - landing the damage kill directly")
            pcall(function() dsc.tr:takeDamage(5000, "hull") end)
        end
    end },
    { t = 51, f = function() lc_tr_poll(false) end },
    { t = 53, f = function() lc_tr_poll(false) end },
    { t = 56, f = function() lc_tr_poll(false) end },
    { t = 58, f = function() lc_tr_poll(false) end },
    { t = 61, f = function() lc_tr_poll(false) end },
    { t = 63, f = function() lc_tr_poll(true) end },
    { t = 64, f = function()
        probe_deliver_books()
        lc_check(phase3.armed, "all playbooks delivered arms phase 3")
    end },
    { t = 64.6, f = function()
        lc_merc_retire()
        lc_check(true, "mercenary support retired")
    end },
    { t = 28, f = function()
        -- Comms pickup flow (act_* are the exact functions the comms
        -- replies call): an ejected container must clear the station hull but
        -- stay inside the hand-over bubble, or the player has to fly a crate
        -- that is unreachable from where the station talks to them.
        act_collect_tampere(stations.tampere)
        local obj = parts["H200 GPU nodes"] and parts["H200 GPU nodes"].obj
        lc_check(obj ~= nil and obj:isValid(), "Tampere collect spawns the H200 container")
        lc_eject_ok("H200 GPU nodes", obj, stations.tampere, "Tampere ejects inside the hand-over bubble")
        lc_check(act_collect_tampere(stations.tampere):find("already") ~= nil, "Tampere collect is idempotent")
        act_collect_lut(stations.lut)
        local obj2 = parts["AMD compute nodes"] and parts["AMD compute nodes"].obj
        lc_check(obj2 ~= nil and obj2:isValid(), "LUT collect spawns the AMD container")
        lc_eject_ok("AMD compute nodes", obj2, stations.lut, "LUT ejects inside the hand-over bubble")
        local cx, cy = obj:getPosition()
        probe_warp_to(cx + U(4), cy)   -- close enough to read, not touching
    end },
    { t = 28.2, f = function()
        -- Tampere's "What about LUT 1?" NEAR side: the coordinates only
        -- unlock within 10u, and the collect ring put us ~5-9u out.
        local p = active_players()[1]
        local d = lc_dlg_open(commsTampere, stations.tampere, p)
        lc_check(#d.msgs == 1 and #d.replies >= 2, "Tampere menu after the collect is intact")
        lc_dlg_click(d, 2, stations.tampere, p)
        lc_check(known.lut == true and lc_dlg.msgs[1]:find("sector") ~= nil
            and lc_dlg.msgs[1]:find("AMD compute nodes") ~= nil,
            "Tampere gives the LUT coordinates to a ship standing right outside")
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
        local dead_tr = lc_autotest_dead and lc_autotest_dead.tr
        for _, t in ipairs(transports) do
            if t ~= dead_tr and t:isValid() and t.lc_book and not parts[t.lc_book].given
                and not parts[t.lc_book].delivered then tr = t break end
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
    { t = 30.4, f = function()
        -- Playbook guard kill-switch: a guard killed by damage is replaced
        -- 60 s later unless the playbook is delivered (which now happens at
        -- t=56, giving the mercenaries this whole window). Two mercenaries
        -- per guard of slot 1; the poll machine tracks the victim's fate.
        local slot = guard_slots[1]
        local victim = nil
        for _, g in ipairs(slot.ships) do
            if g ~= "dead" and g:isValid() then victim = g break end
        end
        lc_check(victim ~= nil, "playbook slot 1 has a live guard")
        if victim then
            table.insert(lc_pools, slot.ships)
            for i, g in ipairs(slot.ships) do
                if g ~= "dead" and g:isValid() then
                    local gx, gy = g:getPosition()
                    lc_merc("Human Navy", gx, gy, g, slot.ships)
                    lc_merc("Human Navy", gx, gy, g, slot.ships)
                end
            end
        end
        lc_autotest_slot = slot
    end },
    { t = 33.8, f = function() lc_guard_poll(false) end },
    { t = 35.5, f = function() lc_guard_poll(false) end },
    { t = 37.5, f = function() lc_guard_poll(false) end },
    { t = 39.5, f = function() lc_guard_poll(false) end },
    { t = 41.5, f = function() lc_guard_poll(false) end },
    { t = 44, f = function() lc_guard_poll(false) end },
    { t = 47, f = function() lc_merc_dump("g47"); lc_guard_poll(false) end },
    { t = 50, f = function() lc_guard_poll(false) end },
    { t = 52, f = function() lc_guard_poll(false) end },
    { t = 54, f = function() lc_guard_poll(false) end },
    { t = 58, f = function() lc_guard_poll(true) end },
    { t = 30.8, f = function()
        -- A booked freighter destroyed by damage: the playbook must spill
        -- as a container, and an unbooked twin must later replace the hull.
        -- (Polled until t=53, before deliver_books at 56.)
        local idx, tr, book = nil, nil, nil
        for i, t in ipairs(transports) do
            if t:isValid() and t.lc_book and t ~= lc_autotest_tr
                and not (parts[t.lc_book] and parts[t.lc_book].given) then
                idx, tr, book = i, t, t.lc_book
                break
            end
        end
        lc_check(tr ~= nil, "a booked freighter with an unreleased playbook is available")
        if tr then
            lc_autotest_dead = { idx = idx, sign = tr.lc_sign or tr:getCallSign(), tr = tr, book = book }
            tr:setFaction("Kraylor")     -- Human Navy mercenaries need a hostile
            tr:setWarpDrive(false)       -- flag; warp-locked targets are unsolvable
            local tx, ty = tr:getPosition()
            local pool = { tr }
            table.insert(lc_pools, pool)
            lc_merc_squad("Human Navy", tx, ty, tr, pool, 6)
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
    { t = 65, f = function()
        lc_check(phase3.warned, "leaving base triggers the invasion warning")
        phase3.timer = 3
    end },
    { t = 68.5, f = function()
        lc_check(phase3.spawned and #groups.wave > 0, "invasion wave spawns")
        -- Not the final line: the GM-console steps below keep ticking until the
        -- victory locks the controls (the runner stops 3 s after "done").
        print(string.format("LC-AUTOTEST progress: %d ok, %d fail", lc_autotest_ok, lc_autotest_fail))
    end },
    { t = 69.3, f = function()
        probe_kill_group("wave")   -- scenario should now declare victory and stop ticking
    end },
    { t = 12.5, f = function()
        -- A hull that dies WITHOUT firing onDestruction (script destroy, GM
        -- removal, collision-only death) must still drop its cargo, or the
        -- mission is unsolvable. The hook is only a fast path; the polled
        -- watchdog is the guarantee. Synthetic group + part, cleaned up below.
        local x, y = sector_center("G9")
        local g = {}
        for i = 1, 2 do
            g[i] = CpuShip():setTemplate("Piranha F12"):setFaction("Kraylor")
                :setPosition(x + i * 2000, y):orderIdle()
        end
        parts["Autotest crate"] = { carried = false, delivered = false }
        lc_autotest_watch = mk_drop_watch("Autotest crate", g, function(dx, dy)
            mk_part("Autotest crate", dx, dy)
        end, 5)
        for _, s in ipairs(g) do s:destroy() end     -- hook-LESS death
    end },
    { t = 19, f = function()
        local o = parts["Autotest crate"] and parts["Autotest crate"].obj
        lc_check(o ~= nil and o:isValid(),
            "a hook-less kill still drops the cargo container (watchdog)")
        if lc_autotest_watch then lc_autotest_watch.done = true end
        if o ~= nil and o:isValid() then o:destroy() end
        parts["Autotest crate"] = nil
    end },
    { t = 19.8, f = function()
        -- Label states: the engine never advances an Artifact through the scan
        -- states, so "unchecked" -> "readable" is entirely scripted. Park a
        -- decoy out of reveal range and reset it to its unscanned text.
        local j = nil
        for i, c in ipairs(containers) do if c.junk and c.a:isValid() then j = i break end end
        lc_check(j ~= nil, "a junk decoy is available for the label test")
        if j then
            lc_label_idx = j
            local p = active_players()[1]
            local px, py = p:getPosition()
            lc_container_text(containers[j].a, containers[j].far)
            containers[j].revealed = false
            containers[j].a:setPosition(px + U(60), py)
        end
    end },
    { t = 20.2, f = function()
        if lc_label_idx == nil then return end
        lc_check(probe_container_text(lc_label_idx):find("unchecked") ~= nil,
            "junk label reads 'unchecked' while out of scan range")
        local p = active_players()[1]
        local px, py = p:getPosition()
        containers[lc_label_idx].a:setPosition(px + U(3), py)   -- into reveal range
    end },
    { t = 20.6, f = function()
        if lc_label_idx == nil then return end
        lc_check(probe_container_text(lc_label_idx):find("spare parts") ~= nil,
            "same label reads 'spare parts' once a ship is alongside")
    end },
}

-- ===================== gamemaster console coverage =====================
-- The console buttons are thin wrappers around the lc_gm_* globals (the same
-- doorway the in-game LUA console uses), so calling the globals IS the test a
-- headless run can do: getGMSelection() is empty and nobody clicks.
-- See ee-skills/patterns/gm-console.md.

-- Substring test that never interprets Lua magic characters: part names and
-- messages contain "(of 3)" and "Containers (", which are patterns otherwise.
function lc_has(hay, needle)
    return string.find(tostring(hay), needle, 1, true) ~= nil
end

-- First beam index with a non-zero arc, for the difficulty-toggle asserts.
function lc_gm_beam_index(p)
    for i = 0, 15 do
        local ok, arc = pcall(p.getBeamWeaponArc, p, i)
        if ok and arc and arc > 0 then return i end
    end
end

function lc_gm_page_count()
    local n = 0
    for _ in pairs(lc_gm_pages) do n = n + 1 end
    return n
end

-- Every page must render headless: a page function that throws would leave a GM
-- staring at a half-built (or empty) button list with no error on screen. Every
-- detail page is opened for EVERY subject, because a label built from a data
-- string is only proven short enough if the longest string was rendered.
function lc_gm_pages_sweep()
    local bad, n = {}, 0
    for name in pairs(lc_gm_pages) do
        n = n + 1
        if lc_gm_show(name) == false then table.insert(bad, name) end
    end
    -- The two detail pages need a subject, so open them directly.
    for _, name in ipairs(PART_NAMES) do lc_gm_open("part", name) end
    for _, name in ipairs(BOOK_NAMES) do lc_gm_open("book", name) end
    lc_gm_show("main")
    return bad, n
end

-- Buttons are counted with a cumulative counter (the engine's list is cleared on
-- every page swap), so a test must measure the delta a redraw produces.
local function gm_redraw(page)
    local before = LC_GM_BUTTONS or 0
    lc_gm_show(page)
    return (LC_GM_BUTTONS or 0) - before
end

table.insert(steps, { t = 6.0, f = function()
    -- Setting[GMMenu] only decides whether the action buttons get drawn: the page
    -- table and every lc_gm_* action are built either way, which is what lets a GM
    -- bring the menu back mid-mission - and what makes a Disabled run a valid test
    -- of the actions themselves.
    lc_check(type(lc_gm_pages) == "table" and next(lc_gm_pages) ~= nil,
        "the pager's page table is built whatever the menu setting says")
    if LC_GM_MENU == "Disabled" then
        lc_check(lc_gm_hidden == true, "Setting[GMMenu]=Disabled boots with the menu hidden")
        lc_check(gm_redraw("main") == 1, "a hidden menu draws only the bring-it-back button")
        lc_gm_menu(true)                    -- exactly what that one button does
        lc_check(lc_gm_hidden == false and gm_redraw("main") > 1
            and tostring(lc_gm_last):find("shown") ~= nil,
            "and that one button brings the whole menu back")
    else
        lc_check(lc_gm_hidden == false, "GM console boots enabled from Setting[GMMenu]")
        local buttons_before = LC_GM_BUTTONS or 0
        local bad, n = lc_gm_pages_sweep()
        lc_check(#bad == 0, "all " .. n .. " GM pages render headless" ..
            (#bad > 0 and (": " .. table.concat(bad, ", ")) or ""))
        lc_check((LC_GM_BUTTONS or 0) > buttons_before,
            "rendering actually registers buttons (" .. ((LC_GM_BUTTONS or 0) - buttons_before) .. " added)")
        -- The GM button cell is fixed-width and centers its text, so a long label
        -- loses both ends - and the verb is what a GM needs. lc_gm_label() counts
        -- the overflow, which makes "readable on a real console" a test result
        -- rather than a screenshot review.
        local over = LC_GM_LABEL_OVER
        lc_check(over == 0, "every GM button label fits the " .. LC_GM_LABEL_MAX
            .. "-char cell (longest " .. LC_GM_LABEL_LONGEST .. ")"
            .. (over > 0 and (": " .. over .. " cut, e.g. " .. lc_gm_label_longest_text) or ""))
        print("LC-PROBE longest GM label: " .. LC_GM_LABEL_LONGEST .. " chars - " .. lc_gm_label_longest_text)
        -- The dive marker is where progress lives now that ": delivered" no
        -- longer fits, so both of its states need asserting. parts[] is filled
        -- lazily as crates are placed, so build the entry if the sweep got here
        -- before this component exists, and remove it again afterwards.
        local key = PART_NAMES[1]
        local fresh = parts[key] == nil
        if fresh then parts[key] = {} end
        local info, saved = parts[key], parts[key].delivered
        info.delivered = true
        local done_mark = lc_gm_done(key)
        info.delivered = false
        local open_mark = lc_gm_done(key)
        if fresh then parts[key] = nil else info.delivered = saved end
        lc_check(done_mark == "*" and open_mark == "+",
            "a dive button marks a finished subject '*' and an open one '+'")
        lc_gm_menu(false)
        lc_check(lc_gm_hidden == true, "the menu can be hidden from the console mid-mission")
        lc_gm_menu(true)
        lc_check(lc_gm_hidden == false and gm_redraw("main") > 1, "and shown again with its buttons")
        lc_check(LC_GM_LABEL_OVER == 0, "restoring the menu still draws no over-long label")
    end
end })
table.insert(steps, { t = 6.4, f = function()
    -- "Reveal" lifts the nebula shadow; the coordinates are a separate fact, so
    -- one button must not quietly hand out the other. (LUT is the probe: the
    -- Kajaani dialog already unlocked the Tampere/Turku hints by now.)
    local before = found.lut
    lc_gm_reveal_station("all")
    lc_check(before == false and found.lut == true, "GM reveal makes LUT 1 a known contact")
    lc_check(known.lut ~= true, "revealing a station is not the same as knowing its coordinates")
    lc_check(tostring(lc_gm_reveal_station("tampere")):find("0 hidden station") ~= nil,
        "revealing an already-found station is a no-op, not an error")
end })
table.insert(steps, { t = 6.8, f = function()
    lc_gm_hint("infini")
    lc_check(known.infini == true, "GM hint hands over the Infiniband search box")
    lc_check(tostring(lc_gm_hint("infini")):find("0 site") ~= nil, "GM hint is idempotent")
    lc_check(lc_has(lc_gm_announce_part("B300 GPU nodes"), "broadcast a location"),
        "GM announce reports a location without touching state")
    lc_check(parts["B300 GPU nodes"] == nil or parts["B300 GPU nodes"].delivered ~= true,
        "announcing a part created no delivery")
end })
table.insert(steps, { t = 7.2, f = function()
    lc_check(lc_has(lc_gm_status(), "phase="), "status readout is text")
    lc_check(lc_has(lc_gm_players(), "Epsilon"), "player list names the crew")
    lc_check(lc_has(lc_gm_freighter_list(), "No freighters yet"),
        "freighter list explains an empty phase 1 instead of printing nothing")
    lc_check(lc_has(lc_gm_containers(), "Containers ("), "container list renders")
    lc_check(lc_has(lc_gm_help(), "lc_gm_mark_part"), "console command list documents the globals")
end })
table.insert(steps, { t = 7.6, f = function()
    local p = active_players()[1]
    lc_gm_warp(2000)
    lc_check(WARP_SPEED == 2000, "GM warp knob updates the world knob")
    lc_check(p:getWarpSpeed() == 2000, "GM warp knob reaches the ship already flying")
    lc_gm_warp(1000)
    lc_check(WARP_SPEED == 1000 and p:getWarpSpeed() == 1000, "GM warp knob is restored")
    lc_gm_grant_warp()
    lc_check(p:hasWarpDrive(), "grant-warp leaves warp drive installed")
end })

table.insert(steps, { t = 45.5, f = function()
    lc_gm_freighters(true)
    local moving = 0
    for _, t in ipairs(transports) do
        if t:isValid() and not t.lc_stopped then moving = moving + 1 end
    end
    lc_check(moving == 0, "GM halt silences every freighter")
    lc_gm_freighters(false)
    local free = 0
    for _, t in ipairs(transports) do
        if t:isValid() and not t.lc_stopped then free = free + 1 end
    end
    lc_check(free > 0 and lc_has(lc_gm_last, "resumed"), "GM resume releases them again (update re-routes on the next tick)")
end })
table.insert(steps, { t = 46.2, f = function()
    -- Re-booking a playbook must move the hull reference, the scan description
    -- and (through book_transport) the guards, and must never duplicate the part.
    local moved = nil
    for k, name in ipairs(BOOK_NAMES) do
        local info = parts[name]
        if moved == nil and info ~= nil and not info.delivered and info.given ~= true
            and not (info.carried and info.carried ~= false)
            and (lc_autotest_dead == nil or lc_autotest_dead.book ~= name) then
            lc_gm_give_book(k)
            local t = book_transport[name]
            if t ~= nil and t:isValid() and t.lc_book == name then moved = name end
        end
    end
    lc_check(moved ~= nil, "GM can reassign a playbook to another freighter")
    if moved ~= nil then
        lc_check(lc_has(lc_gm_last, "gave " .. moved), "the reassignment names the new carrier in the log")
        lc_check(parts[moved].carried == false and parts[moved].delivered ~= true,
            "the reassigned playbook is still aboard a hull, not duplicated")
    end
end })
table.insert(steps, { t = 46.6, f = function()
    lc_check(tostring(lc_gm_scene("turku_greet")):find("greet") ~= nil,
        "the Turku greeting replays, or reports it already played")
    local x, y = sector_center("G12")
    local g = {}
    for i = 1, 2 do
        g[i] = CpuShip():setTemplate("Piranha F12"):setFaction("Kraylor")
            :setPosition(x + i * 1500, y):orderIdle()
    end
    groups.autotest_gm = g
    lc_gm_sweep("autotest_gm")
    local alive = 0
    for _, s in ipairs(g) do if s:isValid() then alive = alive + 1 end end
    lc_check(alive == 0 and tostring(lc_gm_last):find("blew up 2") ~= nil,
        "GM sweep kills through damage, so hooks and watchdogs still apply")
    groups.autotest_gm = nil
    lc_check(tostring(lc_gm_sweep("nosuchgroup")):find("unknown group") ~= nil,
        "GM sweep rejects an unknown group name")
end })
table.insert(steps, { t = 62, f = function()
    -- Story mode is an absolute setter, so toggling must be reversible: read one
    -- real beam, buff, restore. Under a Story preset the ship is already buffed
    -- at spawn, so the exact-value round trip only applies to a Normal start; the
    -- invariant that always holds is "after Normal, damage is not one-shot and
    -- the snapshot is gone".
    local p = active_players()[1]
    local idx = p and lc_gm_beam_index(p) or nil
    if idx == nil then
        lc_check(false, "a player beam exists for the difficulty toggle test")
    else
        local started_story = STORY_MODE
        local _, base = pcall(p.getBeamWeaponDamage, p, idx)
        lc_gm_difficulty("Story")
        local _, buffed = pcall(p.getBeamWeaponDamage, p, idx)
        lc_check(STORY_MODE == true and buffed == STORY_BEAM_DAMAGE,
            "GM story mode raises beam damage to one-shot")
        lc_gm_difficulty("Normal")
        local _, back = pcall(p.getBeamWeaponDamage, p, idx)
        lc_check(STORY_MODE == false and back ~= STORY_BEAM_DAMAGE and p.lc_save == nil,
            "GM story mode gives real damage back (" .. tostring(back) .. ") and drops the snapshot")
        if not started_story then
            lc_check(back == base, "the round trip lands on the original number (" .. tostring(back) .. ")")
        end
        if started_story then lc_gm_difficulty("Story") end   -- leave the run as configured
        lc_check(STORY_MODE == started_story, "the toggle leaves the configured difficulty alone")
    end
end })
table.insert(steps, { t = 68.6, f = function()
    -- Controls lock the moment the mission is over. The real victory arrives at
    -- t=69.4 (wave killed) and the runner stops 3 s after the first "done" line,
    -- so flip the flag in place instead of waiting for the ending: one tick, no
    -- victory() call, nothing else in the world notices.
    local saved = done
    done = true
    local r1, r2 = lc_gm_mark_part("all"), lc_gm_arm_phase3()
    local s = lc_gm_status()
    done = saved
    lc_check(r1 == "locked" and r2 == "locked", "GM actions refuse to run once the mission is over")
    lc_check(lc_has(s, "done=true"), "readouts are never locked, even while the actions are")
    lc_check(done == saved, "the synthetic lock left the mission state untouched")
end })
table.insert(steps, { t = 68.9, f = function()
    print(string.format("LC-AUTOTEST done: %d ok, %d fail", lc_autotest_ok, lc_autotest_fail))
end })

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
    lc_merc_update()
    lc_run_steps()
    local r = orig_update(delta)
    if lc_autotest_dead and lc_autotest_dead.tr and lc_autotest_dead.tr:isValid() then
        local tr = lc_autotest_dead.tr
        tr:setWarpDrive(false)   -- ensure_ftl re-grants it each tick
        tr:orderIdle()            -- flying freighters warp-lock: missiles
    end                          -- cannot hit a warp target; hold still
    return r
end
