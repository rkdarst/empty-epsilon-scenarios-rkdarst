-- Name: <NN> Human Readable Name
-- Description: One sentence for the mission list: what the crew is doing, what is at stake.
--- First paragraph of the long description (detail pane). Any line starting with
--- three hyphens belongs to this block.
--- Second paragraph: the hook, the complication, the tone.
-- Author: <who>
-- Type: Mission
-- Setting[Difficulty]: Mission difficulty.
-- Difficulty[Normal|Default]: Standard balance.
-- Difficulty[Story]: Story mode: player beams one-shot anything they hit.

-- =====================================================================
-- Scenario skeleton. Patterns: ee-skills/patterns/ ; verified facts:
-- ee-skills/reference/ ; tests: ee-skills/testing/ .
-- Order that works: knobs -> helpers -> state -> builders -> init -> update
-- -> dialogs -> probe hooks. Smoke-test as soon as init() exists.
-- =====================================================================

-- ========================= scale & knobs =========================
-- 1 displayed unit == 1000 script units. Every tunable lives here (see
-- patterns/tuning-knobs.md); never a bare 5-digit number inside logic.
function U(u) return u * 1000 end

SC = {
    find_u       = 6,    -- range at which a hidden object reveals itself
    reveal_u     = 5,    -- range at which container labels resolve
    handover_u   = 1,    -- minimum hand-over reach (grows with the hull)
    grace_s      = 10,   -- drop-watch grace period
    respawn_s    = 30,   -- guard slot respawn delay
    respawns_max = 2,    -- per slot
    hint_after_s = 240,  -- idle hint after this long in one phase
    patrol_n     = 2,    -- guards per defended site
}
STATION_HULL_U = { ["Small Station"] = 0.3, ["Medium Station"] = 1.0, ["Large Station"] = 1.3 }
WARP_SPEED = 1000                       -- 1000 == 60u/second

DIFFICULTY = getScenarioSetting("Difficulty")
if DIFFICULTY == nil or DIFFICULTY == "" then DIFFICULTY = "Normal" end
STORY_MODE = DIFFICULTY == "Story"
print("SC: difficulty=" .. DIFFICULTY)

-- ========================= helpers =========================
function d2(a, b)
    local ax, ay = a:getPosition()
    local bx, by = b:getPosition()
    return (ax - bx) ^ 2 + (ay - by) ^ 2
end

function station_hull_u(st) return STATION_HULL_U[st.scen_template] or 0.3 end

function handover_u(st)
    local r = station_hull_u(st) + 0.4
    if r < SC.handover_u then r = SC.handover_u end
    return r
end

-- Docking always satisfies a range gate (patterns/station-handover.md).
function near_or_docked(a, b, u)
    if a == nil or b == nil then return false end
    local docked = false
    pcall(function() docked = a:isDocked(b) end)
    if docked then return true end
    return d2(a, b) < U(u) ^ 2
end

function active_players()
    local t = {}
    local ok, list = pcall(getActivePlayerShips)
    if ok and list then
        for _, p in ipairs(list) do
            if p:isValid() then table.insert(t, p) end
        end
    end
    return t
end

function all_dead(group)
    for _, s in ipairs(group) do
        if s:isValid() then return false end
    end
    return true
end

-- Read a field off something that may already be gone (pitfall 10).
function obj_field(obj, key, default)
    local ok, v = pcall(function() return obj[key] end)
    if ok and v ~= nil then return v end
    return default
end

-- Eject point: clear of the (solid) hull, inside the hand-over bubble.
function eject_pos(st)
    local r = station_hull_u(st) + 0.35
    if r >= handover_u(st) then r = handover_u(st) - 0.05 end
    local ang = random(0, 6.283)
    local x, y = st:getPosition()
    return x + math.cos(ang) * U(r), y + math.sin(ang) * U(r)
end

-- Stock templates have no FTL; run this every tick so respawns are covered.
function ensure_ftl(players)
    for _, p in ipairs(players) do
        if p:isValid() and not p:hasWarpDrive() then
            p:setWarpDrive(true)
            p:setWarpSpeed(WARP_SPEED)
        end
    end
end

-- Station builder: template remembered for hull maths, comms target bound in
-- the closure (a comms FUNCTION only receives comms_source).
function mk_station(name, tmpl, fac, x, y, page_fn)
    local s = SpaceStation():setTemplate(tmpl):setFaction(fac):setPosition(x, y)
    s:setCallSign(name)
    s.scen_template = tmpl
    if page_fn then
        local st = s
        s:setCommsFunction(function(src)
            math.abs(0)   -- ScriptSimpleCallback wants globals as upvalue #1
            return page_fn(st, src or comms_source or active_players()[1])
        end)
    end
    return s
end

-- Park a friendly station out of sight (patterns/hidden-station.md).
function hide_station(st, reveal_to)
    st.scen_hidden, st.scen_reveal_to = true, reveal_to
    st:setFaction("Independent")
    pcall(st.setShortRangeRadarRange, st, 0)
    return st
end

function reveal_station(st)
    if st == nil or not st:isValid() or not st.scen_hidden or st.scen_revealed then return end
    st.scen_revealed = true
    if st.scen_reveal_to then st:setFaction(st.scen_reveal_to) end
    pcall(st.setShortRangeRadarRange, st, 5000)     -- the engine default
end

-- ========================= state =========================
clock = 0
phase = 1
done = false
ever_had_players = false        -- an empty crew before the first join is no loss
stations = {}
groups = { patrol = {}, wave = {} }
containers = {}
parts = {}
PART_NAMES = { "Component A", "Component B" }
drop_watches = {}
msgq = {}
guard_slots = {}

-- ========================= cargo =========================
-- Artifacts have no scan-state machine, so the CURRENT text goes into the base
-- description and all three states (patterns/container-drop.md).
function container_text(a, text)
    a:setDescription(text)
    a:setDescriptionForScanState("notscanned", text)
    a:setDescriptionForScanState("simplescan", text)
    a:setDescriptionForScanState("fullscan", text)
end

LABEL_FAR = "An unmarked cargo container."

function mk_part(name, x, y)
    parts[name] = parts[name] or { carried = false, delivered = false }
    local a = Artifact():setModel("artifact6"):setPosition(x, y):setSpin(0.3)
    local c = { a = a, name = name, revealed = false,
                desc = "Cargo container: " .. name .. ". Fly over it to collect." }
    container_text(a, LABEL_FAR)
    table.insert(containers, c)
    parts[name].cont, parts[name].obj = c, a
    parts[name].drop_x, parts[name].drop_y = x, y
    parts[name].drop_sector = getSectorName(x, y)
    a:allowPickup(true)
    a:onPickUp(function(art, ship)
        math.abs(0)
        if parts[name].obj == art and art:isValid() then art:destroy() end
        parts[name].carried = ship
        notify("Cargo bay secured: " .. name)
    end)
    a:setCommsFunction(function(comms_source, comms_target)
        math.abs(0)
        if c.revealed then
            setCommsMessage("Automated cargo container. Contents: " .. c.desc)
        else
            setCommsMessage("Automated cargo container. Come closer to read the shipping label.")
        end
        return true
    end)
    return a
end

function part_accounted(name)
    local info = parts[name]
    if info == nil then return false end
    if info.delivered or info.carried then return true end
    if info.obj == nil then return false end
    local ok, valid = pcall(function() return info.obj:isValid() end)
    if ok == false or valid then return true end
    return false
end

function delivered_count()
    local n = 0
    for _, name in ipairs(PART_NAMES) do
        if parts[name] and parts[name].delivered then n = n + 1 end
    end
    return n
end

-- ========================= notifications =========================
-- sendCommsMessage returns false while a player is in a dialog, so the queue
-- retries until it lands or expires (patterns/notify-queue.md).
function notify(msg, from)
    table.insert(msgq, { msg = msg, from = from, until_s = clock + 25, done = {} })
end

function pump_messages()
    if #msgq == 0 then return end
    local players = active_players()
    for i = #msgq, 1, -1 do
        local q = msgq[i]
        local sender = q.from
        if sender == nil or not sender:isValid() then sender = stations.home end
        local waiting = false
        for _, p in ipairs(players) do
            local key = p:getCallSign()
            if key == nil or key == "" then key = tostring(p) end
            if not q.done[key] then
                if sender:sendCommsMessage(p, q.msg) then q.done[key] = true else waiting = true end
            end
        end
        if not waiting or clock > q.until_s then table.remove(msgq, i) end
    end
end


-- ========================= drop-watchdog =========================
-- onDestruction fires only on damage kills, so this poll is the guarantee
-- (patterns/guanteed-drop.md).
function mk_drop_watch(key, group, on_drop)
    local w = { key = key, group = group, on_drop = on_drop,
                grace = SC.grace_s, drops = 0, done = false }
    table.insert(drop_watches, w)
    return w
end

function drop_watch()
    for _, w in ipairs(drop_watches) do
        if not w.done then
            local alive = false
            for _, s in ipairs(w.group) do
                if s:isValid() then
                    w.x, w.y = s:getPosition()
                    w.alive_at = clock
                    alive = true
                end
            end
            if not alive and not part_accounted(w.key) then
                w.alive_at = w.alive_at or clock
                if clock - w.alive_at >= w.grace then
                    w.drops = w.drops + 1
                    if w.drops >= 2 then w.done = true end     -- never spam crates
                    w.on_drop(w.x or 0, w.y or 0)
                    print("SC: drop watchdog fired for " .. w.key)
                end
            end
        end
    end
end

-- ========================= guard slots =========================
function mk_guard_slot(name, station, n, factory)
    table.insert(guard_slots, { name = name, station = station, timer = 0,
                                respawns_left = SC.respawns_max, ships = {}, n = n,
                                factory = factory })
end

function guard_update()
    for _, g in ipairs(guard_slots) do
        local alive = 0
        for i, s in ipairs(g.ships) do
            if s ~= "dead" and s ~= nil and s:isValid() then alive = alive + 1 else g.ships[i] = "dead" end
        end
        if alive == 0 then
            if g.timer == 0 then g.timer = clock end
            if g.respawns_left > 0 and clock - g.timer >= SC.respawn_s then
                g.timer, g.respawns_left = 0, g.respawns_left - 1
                for i = 1, g.n do table.insert(g.ships, g.factory(g.station, i)) end
                print("SC: " .. g.name .. " respawned (" .. g.respawns_left .. " left)")
            end
        else
            g.timer = 0
        end
    end
end

-- ========================= init =========================
function init()
    print("SC: init begin")

    player = PlayerSpaceship():setFaction("Human Navy"):setTemplate("Atlantis")
    player:setPosition(0, 0):setCallSign("Epsilon")

    stations.home = mk_station("Home", "Medium Station", "Human Navy", -U(20), 0, commsHome)

    -- world goes here: nebulae, belts, objective sites, patrols ...
    mk_drop_watch("Component A", groups.patrol, function(x, y)
        if not part_accounted("Component A") then mk_part("Component A", x, y) end
    end)

    notify([[Home to Epsilon: two components are missing from the convoy route.
Recover them and bring them back - dock or come alongside to hand them over.]], stations.home)
    print("SC: init complete, difficulty=" .. DIFFICULTY)
end

-- ========================= update =========================
function update(delta)
    clock = clock + delta
    if done then return end
    local players = active_players()
    if #players > 0 then ever_had_players = true end
    ensure_ftl(players)
    pump_messages()
    guard_update()

    -- Per-ship setup belongs here, not in init(): init only sees the first hull.
    for _, p in ipairs(players) do
        if p:isValid() then
            p.scen_x, p.scen_y = p:getPosition()          -- "where did it die?"
            if not p.scen_watched then
                p.scen_watched = true
                if STORY_MODE then story_buff(p) end
            end
        end
    end

    -- Two-state container labels: flip all four descriptions at once.
    for _, c in ipairs(containers) do
        if not c.revealed and c.a:isValid() then
            for _, p in ipairs(players) do
                if d2(p, c.a) < U(SC.reveal_u) ^ 2 then
                    c.revealed = true
                    container_text(c.a, c.desc)
                    break
                end
            end
        end
    end

    drop_watch()
    phase_check()
end

function story_buff(p)                    -- there is no setBeamDamage() in 2024.12
    for i = 0, 15 do
        local ok, arc = pcall(p.getBeamWeaponArc, p, i)
        if ok and arc and arc > 0 then
            local _, dir = pcall(p.getBeamWeaponDirection, p, i)
            local _, rng = pcall(p.getBeamWeaponRange, p, i)
            local _, cyc = pcall(p.getBeamWeaponCycleTime, p, i)
            pcall(p.setBeamWeapon, p, i, arc, dir, rng, cyc, 5000)
        end
    end
end

-- ========================= phase machine =========================
function phase_check()
    if phase == 1 and delivered_count() >= #PART_NAMES then
        phase = 2
        notify("All components accounted for. Next: the freighters.", stations.home)
    elseif phase == 2 and goal_done() then
        done = true
        victory("Human Navy")
    elseif ever_had_players and #active_players() == 0 then
        done = true
        victory("Exuari")
    end
end

function goal_done() return delivered_count() >= #PART_NAMES end   -- TODO your goal


-- ========================= dialogs =========================
-- Page: set the text ONCE, then only add choices. Callbacks set their own result
-- text and call the _replies function, never the page (patterns/dialog-page.md).
function commsHome(t, src)
    setCommsMessage([[Home. Two components are missing from the convoy route.
Recover them and bring them back - the hand-over gate is physical, so get next to
the hull or dock.]])
    commsHome_replies(t, src)
    return true
end

function commsHome_replies(t, src)
    addCommsReply("Hand over the components.", function(comms_source, comms_target)
        math.abs(0)                       -- ScriptSimpleCallback wants globals first
        setCommsMessage(act_deliver(t, src or comms_source))
        commsHome_replies(t, comms_source or src)
        return true
    end)
    addCommsReply("Status.", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage(("Components delivered: %d of %d. Phase %d."):format(
            delivered_count(), #PART_NAMES, phase))
        commsHome_replies(t, comms_source or src)
        return true
    end)
end

function act_deliver(station, ship)
    if ship == nil or not ship:isValid() then return "Nobody is alongside." end
    if not near_or_docked(ship, station, handover_u(station)) then
        return "Come alongside the station to hand the cargo over."
    end
    local n = 0
    for _, name in ipairs(PART_NAMES) do
        local info = parts[name]
        if info and info.carried and info.carried == ship then
            info.carried = false
            info.delivered = true
            n = n + 1
        end
    end
    if n == 0 then return "Your cargo bay holds nothing we need." end
    return ("Received %d item(s); %d of %d accounted for."):format(
        n, delivered_count(), #PART_NAMES)
end

-- ========================= test hooks =========================
-- Read-mostly and idempotent so a test cannot steer the mission. A headless run
-- has player hulls but no clients: nothing moves and nothing collides, so
-- movement-dependent mechanics need a stand-in hook that shares the real path's
-- bookkeeping (testing/runtime-surprises.md).
function probe_state()
    print(("SC-STATE done=%s phase=%d delivered=%d/%d players=%d t=%.1f"):format(
        tostring(done), phase, delivered_count(), #PART_NAMES, #active_players(), clock))
    return phase
end

function probe_warp_to(x, y)
    for _, p in ipairs(active_players()) do p:setPosition(x, y) end
end

function probe_part(name)
    local info = parts[tostring(name)]
    if info == nil then return "unknown" end
    if info.delivered then return "delivered" end
    if info.carried then return "carried" end
    if info.obj and info.obj:isValid() then return "adrift" end
    return "missing"
end

function probe_pickup(name)                      -- collision pickup stand-in
    local info = parts[tostring(name)]
    if info == nil or info.delivered then return probe_part(name) end
    if info.carried then return "carried" end
    if info.obj == nil or not info.obj:isValid() then return "missing" end
    info.obj:destroy()
    info.carried = active_players()[1] or true
    return "carried"
end

-- destroy() never fires onDestruction; only safe for polling-watched groups.
function probe_kill_group(name)
    local g = groups[tostring(name)] or {}
    local n = 0
    for _, s in ipairs(g) do
        if s:isValid() then s:destroy() n = n + 1 end
    end
    print("SC-PROBE killed " .. n .. " in " .. tostring(name))
    return n
end


