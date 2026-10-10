-- Tick driver for scenario_41_lostcluster_dsl.lua (mission-DSL twin).
-- Appended by tools/func_test.sh via AUTOTEST=tools/autotest/gen41_autotest.lua:
-- lets update() run live, then asserts the generator tick loop works (events
-- fired, archetype spawn + n_alive tracking, no runtime errors) and that the
-- twin keeps the same contracts as the hand-written scenario 40: hidden
-- stations, polled cargo drops, hand-over range, item label states, free
-- homings (notes/06, notes/05 GAP-12..15).
local ticks = 0
local done41, done41b, done41c = false, false, false
local a41_ok, a41_fail = 0, 0
local function chk(cond, msg)
    if cond then a41_ok = a41_ok + 1; print("LC-ASSERT ok: " .. msg)
    else a41_fail = a41_fail + 1; print("LC-ASSERT FAIL: " .. msg) end
end
local real_set, real_add = setCommsMessage, addCommsReply
local msgs, replies = {}, {}
local function dlg_open(fn, t, src)
    msgs, replies = {}, {}
    setCommsMessage = function(m) table.insert(msgs, tostring(m)) end
    addCommsReply = function(label, f) table.insert(replies, { label = label, fn = f }) end
    local ok, err = pcall(fn, t, src)
    setCommsMessage, addCommsReply = real_set, real_add
    chk(ok, "dialog renders without error" .. (ok and "" or (": " .. tostring(err))))
    return replies
end
local function dlg_click(t, src, idx)
    local r = replies[idx]
    if r == nil then chk(false, "reply #" .. idx .. " exists"); return end
    msgs, replies = {}, {}
    setCommsMessage = function(m) table.insert(msgs, tostring(m)) end
    addCommsReply = function(label, f) table.insert(replies, { label = label, fn = f }) end
    pcall(r.fn, src, t)
    setCommsMessage, addCommsReply = real_set, real_add
end
local function move(x, y)
    local p = gen_player()
    if p then p:setPosition(x, y) end
    return p
end
local _up41 = update
function update(delta)
    _up41(delta)
    ticks = ticks + 1
    if ticks == 2 then
        -- A "hidden" station may not be a friendly contact at boot (notes/06).
        chk(E.tampere:getFaction() ~= "Human Navy",
            "hidden station boots outside the players' contact list ("
            .. E.tampere:getFaction() .. ")")
    end
    if not done41 and gen.clock > 26 then
        done41 = true
        chk(gen_event_fired("thieves"), "thieves event fired")
        chk(gen_alive("raider") == 2, "raiders spawned (n_alive=" .. gen_alive("raider") .. ")")

        -- Hook-less deaths: script-destroy the raiders -> the polled watcher
        -- must still put the B300 crate in the world (GAP-3/12).
        for _, s in ipairs(E_ARCH.raider.list) do
            if s:isValid() then s:destroy() end
        end

        local sx, sy = E.lumina:getPosition()   -- Medium station: 1.4u bubble
        local p = move(sx, sy + 12000)
        chk(gen_near_or_docked(p, E.lumina) == false, "hand-over refused from 12 units out")
        p:setPosition(sx + 1300, sy)      -- 1.3u: inside the bubble, off the hull
        chk(gen_near_or_docked(p, E.lumina) == true, "hand-over accepted alongside the hull")
        local mx = 0
        pcall(function() mx = p:getWeaponStorageMax("Homing") or 0 end)
        pcall(function() p:setWeaponStorage("Homing", 0) end)
        local rr = dlg_open(dlg_lumina_intro, E.lumina, p)
        local idx
        for i, r in ipairs(rr) do if r.label:find("homing") then idx = i end end
        chk(idx ~= nil, "station menu offers the homing replenishment")
        if idx then
            dlg_click(E.lumina, p, idx)
            local got = 0
            pcall(function() got = p:getWeaponStorage("Homing") or 0 end)
            chk(mx == 0 or got == mx, "free homings refill the racks (" .. got .. "/" .. mx .. ")")
        end

        -- Physical hand-over must be range-gated in the dialog too.
        gen_give(p, "h200")
        move(sx, sy + 5000)
        dlg_open(dlg_lumina_intro_replies, E.lumina, p)
        dlg_click(E.lumina, p, 1)
        chk(gen.flags.h200_delivered ~= true and (msgs[1] or ""):find("Too far") ~= nil,
            "hand-over reply refuses from out of range")
        p:setPosition(sx + 1300, sy)
        dlg_open(dlg_lumina_intro_replies, E.lumina, p)
        dlg_click(E.lumina, p, 1)
        chk(gen.flags.h200_delivered == true, "same reply delivers alongside")

        move(150000, 20000)           -- straight into the hidden station
        -- The approach ambush spawns the same tick (our wrapper runs after the
        -- generator's update); clear it or it kills the Phobos and the scenario
        -- silently flips to defeat, which stops all watchers.
        for _, s in ipairs(E_ARCH.ambusher.list) do
            if s:isValid() then s:destroy() end
        end
    end
    if not done41b and gen.clock > 30 then
        done41b = true
        chk(gen.flags.b300_dropped and gen_item("b300") ~= nil,
            "hook-less raider death still drops the crate (polled watcher)")
        chk(E.tampere:getFaction() == "Human Navy" and gen.flags.tampere_found,
            "hidden station revealed once a player flew into it")
        local it = gen_item("b300")
        if it ~= nil then
            chk(it:getDescription():find("unreadable") ~= nil,
                "crate label reads the unscanned text from a distance")
            local cx, cy = it:getPosition()
            move(cx + 3000, cy)       -- then sit 3u off the crate
        end
    end
    if not done41c and gen.clock > 34 then
        done41c = true
        chk(gen_player() ~= nil, "player still alive for the label sweep")
        local it = gen_item("b300")
        local info = "n/a"
        if it ~= nil and gen_player() ~= nil then
            local ix, iy = it:getPosition()
            local px, py = gen_player():getPosition()
            info = string.format("revealed=%s dist=%.2fu pos=%.0f,%.0f player=%.0f,%.0f text=%s",
                tostring(ITEMS.b300.revealed),
                math.sqrt((ix - px) ^ 2 + (iy - py) ^ 2) / 1000, ix, iy, px, py,
                it:getDescription())
        end
        chk(it ~= nil and it:getDescription():find("B300 GPU nodes") ~= nil,
            "same label becomes readable within the scan radius | " .. info)
        print(string.format("LC-AUTOTEST done (41-lite ticks=%d ok=%d fail=%d stage=%d)",
            ticks, a41_ok, a41_fail, gen.stage))
    end
end