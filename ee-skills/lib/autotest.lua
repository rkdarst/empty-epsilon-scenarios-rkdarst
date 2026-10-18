-- ee-skills/lib/autotest.lua - generic headless test harness.
-- ee_func.sh concatenates: [prelude] scenario + THIS FILE + your driver, so
-- this runs after the scenario's top level and can see its globals, and your
-- driver runs last and registers the timeline. The scenario itself needs no
-- test hooks at all.
--
-- Log markers ee_func.sh greps:
--   EE-ASSERT ok: <msg> / EE-ASSERT FAIL: <msg> / EE-ASSERT ERROR: <err>
--   EE-AUTOTEST done: <n> ok, <m> fail       (the "I finished" signal)
--
-- Minimal driver:
--   ee_step(2,  function() ee_check(probe_state() ~= nil, "world built") end)
--   ee_step(20, function() ee_wait("patrol wiped", 40,
--       function() return all_dead(pool) end,
--       function() ee_check(#pool == 0, "pool cleared") end) end)
--   function ee_on_finish() ee_check(..., "final invariant") end
--   ee_finish_at = 300        -- safety net so the run always ends
-- ee_wait runs its cont() once on success (the engine has no coroutines, so
-- nothing truly blocks); ee_until is the plain async poll variant (assert its
-- outcome only in a LATER step).

ee_ok, ee_fail, ee_clock = 0, 0, 0
ee_steps, ee_pollers, ee_mercs = {}, {}, {}
ee_pools = { list = {} }               -- pool set + insertion-ordered list
ee_finish_at = ee_finish_at or 600          -- absolute wall of the timeline
ee_done_logged = false

function ee_check(cond, msg)
    if cond then
        ee_ok = ee_ok + 1
        print("EE-ASSERT ok: " .. tostring(msg))
    else
        ee_fail = ee_fail + 1
        print("EE-ASSERT FAIL: " .. tostring(msg))
    end
end

-- Register a timeline action at game-second t (runs once, in a pcall).
function ee_step(t, fn)
    table.insert(ee_steps, { t = t, f = fn, done = false })
end

-- Poll-based expectation: call fn() every tick until it returns true, and fail
-- at deadline (game seconds) if it never does. EVERY organic event (an AI kill,
-- a warp transit, a respawn timer) must be polled - sampling one instant is the
-- #1 source of false failures.
function ee_until(msg, deadline, fn)
    table.insert(ee_pollers, { msg = msg, deadline = ee_clock + deadline, fn = fn, done = false })
end

-- Wait-with-continuation: polls fn() every tick (like ee_until) and, on
-- success, runs cont() ONCE in a pcall - put the assertions that DEPEND on the
-- outcome there. The engine sandbox strips the coroutine library, so a truly
-- blocking wait is impossible [obs]: "wait, then continue" must be written as
-- a continuation, and lines after the ee_wait call still run immediately.
-- Without cont it behaves exactly like ee_until.
function ee_wait(msg, deadline, fn, cont)
    table.insert(ee_pollers, { msg = msg, deadline = ee_clock + (deadline or 60),
                               fn = fn, done = false, cont = cont })
end

-- Every-tick invariant (anti-softlock as runtime maths): fn() must be true on
-- EVERY tick from registration until the run ends; the first false (or an
-- error) fails and stops the check. Cheapest guard for "progress is always
-- possible": e.g. at least one valid station remains, or a drop-watch is
-- armed while a part is adrift.
function ee_invariant(msg, fn)
    table.insert(ee_pollers, { msg = msg, fn = fn, invariant = true, done = false })
end

-- ------------------------------------------------------------------- spies
-- Wrap a scenario GLOBAL function (a channel "choke point": notify, log, ...)
-- so every call is recorded and then passed through untouched. This is how a
-- driver asserts PUSH / PERSIST / RECOVERY communication: "the crew was TOLD
-- X" is only observable headlessly if the scenario routes every write of that
-- channel through one named function (testing/communication-testing.md).
ee_spies = {}
function ee_spy(name)
    local rec = ee_spies[name]
    if rec ~= nil then return rec end
    local orig = _G[name]
    rec = { name = name, calls = {} }
    _G[name] = function(...)
        local args = {}
        for i = 1, select("#", ...) do
            args[i] = tostring(select(i, ...))
        end
        table.insert(rec.calls, { args = args, clock = ee_clock })
        if orig ~= nil then return orig(...) end
    end
    ee_spies[name] = rec
    return rec
end

-- First spy call at/after game-second `since` whose concatenated arguments
-- match the Lua pattern; the call record, or nil. Typical use:
--   ee_spy("notify")
--   ee_check(ee_spy_seen("notify", "warp jump") ~= nil, "crew told to warp")
function ee_spy_seen(name, pattern, since)
    ee_spy(name)                        -- ensure installed even if never armed
    local rec = ee_spies[name]
    for _, c in ipairs(rec.calls) do
        if (since == nil or c.clock >= since)
            and string.find(table.concat(c.args, " "), pattern) then
            return c
        end
    end
    return nil
end

function ee_finish(reason)
    if ee_done_logged then return end
    ee_done_logged = true
    if ee_on_finish ~= nil then
        local ok, err = pcall(ee_on_finish)
        if not ok then
            ee_fail = ee_fail + 1
            print("EE-ASSERT ERROR (ee_on_finish): " .. tostring(err))
        end
    end
    print(string.format("EE-AUTOTEST done: %d ok, %d fail (%s)", ee_ok, ee_fail, tostring(reason)))
end

-- ---------------------------------------------------------------- comms walker
-- Stubs the two dialog globals and drives the SAME functions the engine's
-- CommsScriptInterface drives: page function to open, reply callback to click.
-- The engine clears all replies, then runs the callback, and every
-- setCommsMessage inside a callback REPLACES the text - so a well-behaved page
-- emits EXACTLY ONE message. Two means a menu renderer clobbered the action
-- result and the player's click looks dead.
ee_dlg = { msgs = {}, replies = {} }
local ee_real_set, ee_real_add = setCommsMessage, addCommsReply

local function ee_dlg_capture()
    ee_dlg.msgs, ee_dlg.replies = {}, {}
    setCommsMessage = function(m) table.insert(ee_dlg.msgs, tostring(m)) end
    addCommsReply = function(label, f) table.insert(ee_dlg.replies, { label = label, fn = f }) end
end

local function ee_dlg_restore()
    setCommsMessage, addCommsReply = ee_real_set, ee_real_add
end

function ee_dlg_open(page_fn, target, source)
    ee_dlg_capture()
    local ok, err = pcall(page_fn, target, source)
    ee_dlg_restore()
    ee_check(ok, "dialog opens without error: " .. (ok and tostring(target) or tostring(err)))
    return ee_dlg
end

-- Click reply #idx exactly like the engine does (replies cleared first, then
-- callback with (source, target)). Returns the messages the click rendered.
function ee_dlg_click(d, idx, target, source)
    local reply = d.replies[idx]        -- grab BEFORE the capture clears the list
    if reply == nil then
        ee_check(false, "dialog has a reply #" .. tostring(idx))
        return {}
    end
    ee_dlg_capture()
    local ok, err = pcall(reply.fn, source, target)
    ee_dlg_restore()
    ee_check(ok, "reply click runs without error: " .. tostring(err or reply.label))
    return d.msgs
end

-- Click by label instead of index: reply ORDER is unstable while authoring
-- (new replies must append after the originals - an index click then hits the
-- wrong reply and the assertion breaks or, worse, passes wrongly). Exact
-- match first, then Lua pattern; returns the messages the click rendered.
function ee_dlg_click_by_label(d, label, target, source)
    local idx
    for i, r in ipairs(d.replies) do
        if r.label == label then idx = i break end
    end
    if idx == nil then
        for i, r in ipairs(d.replies) do
            if string.find(r.label, label) then idx = i break end
        end
    end
    if idx == nil then
        ee_check(false, "dialog has a reply matching \"" .. tostring(label) .. "\"")
        return {}
    end
    return ee_dlg_click(d, idx, target, source)
end

-- ------------------------------------------------------------------- killing
-- The engine fires onDestruction ONLY on damage kills (takeHullDamage) and
-- scripts have no damage API, so hook-driven logic (drops, spills, respawns)
-- must be triggered ORGANICALLY. A mercenary Starhammer II squad does it: that
-- AI fires only HVLI tubes (ShipAI::runAttack never fires beams), so it needs
-- warp drive to catch fleeing targets. AI kills take ~20-45 s and the engine
-- never drops a stale attack order - hence the retarget + anti-camping logic
-- (a radar-dark target inside a nebula makes the AI park forever).
function ee_merc(fac, x, y, target, pool)
    local ang = (#ee_mercs + 1) * 2.1
    local s = CpuShip():setTemplate("Starhammer II"):setFaction(fac)
        :setPosition(x + math.cos(ang) * 2500, y + math.sin(ang) * 2500)
    s:setWarpDrive(true)
    s:setWarpSpeed(1000)                       -- 1000 == 60u/s: catches freighters
    if target then s:orderAttack(target) end
    s:setCallSign("Merc " .. (#ee_mercs + 1))
    s.ee_target, s.ee_pool, s.ee_stale = target, pool, 0
    if pool and not ee_pools[pool] then
        ee_pools[pool] = true
        table.insert(ee_pools.list, pool)
    end
    table.insert(ee_mercs, s)
    return s
end

function ee_merc_squad(fac, x, y, target, pool, n)
    for _ = 1, (n or 3) do ee_merc(fac, x, y, target, pool) end
end

function ee_merc_update()
    for _, m in ipairs(ee_mercs) do
        if m:isValid() then
            local t = m.ee_target
            if t and (not t:isValid()) and m.ee_pool then
                t = nil                                  -- the engine AI keeps
                for _, c in ipairs(m.ee_pool) do         -- dead orders forever
                    if c ~= "dead" and c ~= nil and c:isValid() then t = c break end
                end
                m.ee_target, m.ee_stale = t, 0
                if t then m:orderAttack(t) end
            end
            if t and t:isValid() then
                local mx, my = m:getPosition()
                local tx, ty = t:getPosition()
                local dx, dy = tx - mx, ty - my
                local d = math.sqrt(dx * dx + dy * dy)
                if d > 2000 then
                    m.ee_stale = m.ee_stale + 1
                    if m.ee_stale > 90 then              -- parked: ONE clean
                        m.ee_stale = 0                   -- drop-in, no spam
                        m:setPosition(tx - dx / d * 2000, ty - dy / d * 2000)
                        m:orderAttack(t)                 -- spam
                    end
                else
                    m.ee_stale = 0
                end
            end
        end
    end
end

function ee_merc_dump(tag)
    local out = {}
    for i, m in ipairs(ee_mercs) do
        if m:isValid() then
            local mx, my = m:getPosition()
            local t, info = m.ee_target, "?"
            if t ~= nil then
                if not t:isValid() then info = "killed"
                else
                    local tx, ty = t:getPosition()
                    info = string.format("%.1fU", math.sqrt((tx - mx) ^ 2 + (ty - my) ^ 2) / 1000)
                end
            end
            table.insert(out, m:getCallSign() .. "(" .. info .. ")")
        else
            table.insert(out, i .. ":dead")
        end
    end
    print("EE-MERC[" .. tostring(tag) .. "] " .. table.concat(out, " "))
end

-- Retire everything the driver spawned. Plain destroy() is hook-less by design,
-- which is exactly what scripted teardown wants (no stray drops / respawns).
function ee_merc_retire()
    for _, pool in ipairs(ee_pools.list) do
        for _, c in ipairs(pool) do
            if c ~= "dead" and c ~= nil and c:isValid() then c:destroy() end
        end
    end
    for _, m in ipairs(ee_mercs) do
        if m:isValid() then m:destroy() end
    end
    ee_mercs, ee_pools = {}, { list = {} }
end


-- ------------------------------------------------------------ geometry helper
-- Dropped containers must clear the station hull (the pickup is collision-
-- based and the hull is solid) yet stay inside the reach the station itself
-- talks from. hull_u/reach_u come from the scenario's own geometry helpers.
function ee_eject_clear(msg, obj, station, hull_u, reach_u)
    if obj == nil or not obj:isValid() then
        ee_check(false, msg .. " (no container)")
        return
    end
    local ox, oy = obj:getPosition()
    local sx, sy = station:getPosition()
    local d = math.sqrt((ox - sx) ^ 2 + (oy - sy) ^ 2) / 1000
    ee_check(d > hull_u, string.format("%s: clear of the %.2fu hull (at %.2fu)", msg, hull_u, d))
    ee_check(d <= reach_u, string.format("%s: inside the %.2fu hand-over bubble (at %.2fu)", msg, reach_u, d))
end

-- ------------------------------------------------------------------- driver
-- The timeline engine. update() is WRAPPED, not replaced: the scenario keeps
-- running normally, our steps/polls run before it, and the merc squad flies in
-- real game time so organic kills behave like real play.
local ee_orig_update = update

-- victory() ends the mission, and the engine stops ticking afterwards, so a
-- driver waiting for its own deadline would never print its end marker. Wrap it:
-- the marker is printed while the world is still alive.
if victory ~= nil and not ee_victory_wrapped then
    local ee_real_victory = victory
    victory = function(faction)
        local ok, err = pcall(ee_real_victory, faction)
        ee_check(ok, "victory(" .. tostring(faction) .. ")" .. (ok and "" or (": " .. tostring(err))))
        if ee_expect_victory_faction ~= nil then
            ee_check(faction == ee_expect_victory_faction,
                "victory faction is " .. tostring(ee_expect_victory_faction)
                .. " (got " .. tostring(faction) .. ")")
        end
        ee_finish("victory declared")
        return ok
    end
    ee_victory_wrapped = true
end

-- Assert the faction the mission ends for ("victory(Kraylor)" for a defeat,
-- "victory(Human Navy)" for a win). The wrapper above evaluates it; without
-- it the printed faction is only decoration nobody can assert on.
function ee_expect_victory(faction) ee_expect_victory_faction = faction end

function update(delta)
    ee_clock = ee_clock + (delta or 0)
    ee_merc_update()
    for _, s in ipairs(ee_steps) do
        if not s.done and ee_clock >= s.t then
            s.done = true
            local ok, err = pcall(s.f)
            if not ok then
                ee_fail = ee_fail + 1
                print("EE-ASSERT ERROR: " .. tostring(err))
            end
        end
    end
    for i = #ee_pollers, 1, -1 do
        local p = ee_pollers[i]
        if not p.done then
            local ok, hit = pcall(p.fn)
            if not ok then
                ee_fail = ee_fail + 1
                print("EE-ASSERT ERROR (poll): " .. tostring(hit))
                p.done = true
            elseif p.invariant then
                if not hit then
                    ee_check(false, p.msg)
                    p.done = true
                end
            elseif hit then
                ee_check(true, p.msg)
                if p.cont ~= nil then
                    local ok2, err2 = pcall(p.cont)
                    if not ok2 then
                        ee_fail = ee_fail + 1
                        print("EE-ASSERT ERROR (cont): " .. tostring(err2))
                    end
                end
                p.done = true
            elseif ee_clock > p.deadline then
                ee_check(false, p.msg)
                p.done = true
            end
        end
    end
    if ee_orig_update ~= nil then ee_orig_update(delta) end
    if not ee_done_logged and ee_clock >= ee_finish_at then
        ee_finish("deadline " .. tostring(ee_finish_at) .. "s")
    end
end
