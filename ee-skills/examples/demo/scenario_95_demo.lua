-- Name: Demo Cache Run
-- Description: Two cargo cores fell from a wrecked hauler. Find both and bring them back to Depot.
--- A compact example mission built from the ee-skills patterns: a hidden relay
--- station, cargo containers with two-state labels, a guarded drop with a
--- hookless-death safety net, and a docking hand-over gate.
-- Author: ee-skills
-- Type: Mission
-- Setting[Difficulty]: Mission difficulty.
-- Difficulty[Normal|Default]: Standard balance.
-- Difficulty[Story]: Story mode: player beams one-shot anything they hit.

-- =====================================================================
-- This is the package's worked example: every block here has a recipe in
-- ee-skills/patterns/. It is also the acceptance test for the harness
-- (bin/ee_selftest.sh runs it), so keep it API-plain and headless-safe.
-- =====================================================================

-- ========================= scale & knobs =========================
-- 1 displayed unit == 1000 script units. Keep every tunable in this one block
-- so a rebalance never means hunting through logic.
function U(u) return u * 1000 end

DEMO = {
    find_u     = 6,     -- the hidden relay stops hiding at this range
    reveal_u   = 5,     -- container labels resolve here
    handover_u = 1,     -- minimum hand-over reach (bigger hulls need more)
    patrol_n   = 2,     -- escorts around the cache
    grace_s    = 10,    -- drop-watch grace: let the real hook win first
}
STATION_HULL_U = { ["Small Station"] = 0.3, ["Medium Station"] = 1.0, ["Large Station"] = 1.3 }

DIFFICULTY = getScenarioSetting("Difficulty")
if DIFFICULTY == nil or DIFFICULTY == "" then DIFFICULTY = "Normal" end
STORY_MODE = DIFFICULTY == "Story"
print("DEMO: difficulty=" .. DIFFICULTY)

-- ========================= geometry & helpers =========================
function d2(a, b)
    local ax, ay = a:getPosition()
    local bx, by = b:getPosition()
    return (ax - bx) ^ 2 + (ay - by) ^ 2
end

function station_hull_u(st) return STATION_HULL_U[st.demo_template] or 0.3 end

-- "Next to the hull": a flat minimum for small stations, growing with the hull,
-- because a crate or a ship at the centre of a Large station is not reachable.
function handover_u(st)
    local r = station_hull_u(st) + 0.4
    if r < DEMO.handover_u then r = DEMO.handover_u end
    return r
end

-- Docking always satisfies a range gate; otherwise it is plain distance.
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

-- A dropped container has to clear the (solid) hull yet stay inside the reach
-- the station itself talks from.
function eject_pos(st)
    local r = station_hull_u(st) + 0.35
    if r >= handover_u(st) then r = handover_u(st) - 0.05 end
    local ang = random(0, 6.283)
    local x, y = st:getPosition()
    return x + math.cos(ang) * U(r), y + math.sin(ang) * U(r)
end

-- Stock player templates ship WITHOUT FTL, which strands the crew on a
-- multi-sector map. Cheap guard, called every tick, covers late joiners and
-- GM-spawned replacements.
function ensure_ftl(players)
    for _, p in ipairs(players) do
        if p:isValid() and not p:hasWarpDrive() then
            p:setWarpDrive(true)
            p:setWarpSpeed(1000)                 -- 1000 == 60u/second
        end
    end
end
-- ========================= world state =========================
clock = 0
done = false
ever_had_players = false      -- an empty crew before the first join is not a loss
stations = {}
containers = {}
parts = {}
PART_NAMES = { "Coolant core", "Nav core" }
patrol = {}
found_waypoint = false

-- ========================= cargo containers =========================
-- An Artifact never advances through the scan states (only ships do), so the
-- text for the CURRENT story state goes into the base description and all
-- three scan states at once; whichever one the UI consults reads the same.
function container_text(a, text)
    a:setDescription(text)
    a:setDescriptionForScanState("notscanned", text)
    a:setDescriptionForScanState("simplescan", text)
    a:setDescriptionForScanState("fullscan", text)
end

LABEL_FAR = "An unmarked cargo container."

function mk_container(desc, x, y)
    local a = Artifact():setModel("artifact6"):setPosition(x, y):setSpin(0.3)
    container_text(a, LABEL_FAR)
    local c = { a = a, desc = desc, name = nil, revealed = false }
    table.insert(containers, c)
    return a, c
end

function reveal_container(c)
    c.revealed = true
    if c.a:isValid() then container_text(c.a, c.desc) end
end

function mk_part(name, x, y)
    parts[name] = parts[name] or { carried = false, delivered = false }
    local a, c = mk_container("Cargo container: " .. name .. ". Fly over it to collect.", x, y)
    c.name = name
    parts[name].cont = c
    parts[name].obj = a
    parts[name].drop_x, parts[name].drop_y = x, y
    a:allowPickup(true)
    a:onPickUp(function(art, ship)
        math.abs(0)   -- ScriptSimpleCallback wants the globals table as upvalue #1
        if parts[name].obj == art and art:isValid() then art:destroy() end
        parts[name].carried = ship
        notify("Cargo bay secured: " .. name, stations.depot)
    end)
    a:setCommsFunction(function(comms_source, comms_target)
        math.abs(0)
        if c.revealed then
            setCommsMessage("Automated cargo container. Contents: " .. c.desc .. " Fly over the container to collect it.")
        else
            setCommsMessage("Automated cargo container. Bring your ship close enough to read the shipping label.")
        end
        return true
    end)
    return a
end

function part_count_delivered()
    local n = 0
    for _, name in ipairs(PART_NAMES) do
        if parts[name] and parts[name].delivered then n = n + 1 end
    end
    return n
end

-- Accounted for = delivered, in a cargo bay, or a crate that still exists. A
-- crate blown up before anyone reached it is NOT accounted for.
function part_accounted(name)
    local info = parts[name]
    if info == nil then return false end
    if info.delivered or info.carried then return true end
    if info.obj == nil then return false end
    local ok, valid = pcall(function() return info.obj:isValid() end)
    if ok == false or valid then return true end
    return false
end

-- ========================= notifications =========================
-- sendCommsMessage returns false (and drops the message) while a player is
-- busy inside a dialog, so lines are queued and retried from the poll loop.
msgq = {}

function notify(msg, from)
    table.insert(msgq, { msg = msg, from = from, until_s = clock + 25, done = {} })
end

function pump_messages()
    if #msgq == 0 then return end
    local players = active_players()
    for i = #msgq, 1, -1 do
        local q = msgq[i]
        local sender = q.from
        if sender == nil or not sender:isValid() then sender = stations.depot end
        local waiting = false
        for _, p in ipairs(players) do
            local key = p:getCallSign()
            if key == nil or key == "" then key = tostring(p) end
            if not q.done[key] then
                if sender:sendCommsMessage(p, q.msg) then
                    q.done[key] = true
                else
                    waiting = true
                end
            end
        end
        if not waiting or clock > q.until_s then table.remove(msgq, i) end
    end
end
-- ========================= stations =========================
function mk_station(name, tmpl, fac, x, y, page_fn)
    local s = SpaceStation():setTemplate(tmpl):setFaction(fac):setPosition(x, y)
    s:setCallSign(name)
    s.demo_template = tmpl            -- for the hull-radius lookups
    if page_fn then
        local st = s
        -- A comms FUNCTION is documented to receive only comms_source, so the
        -- target is bound in the closure; never trust the comms_target global.
        s:setCommsFunction(function(src)
            math.abs(0)
            return page_fn(st, src or comms_source)
        end)
    end
    return s
end

-- Hiding a FRIENDLY station needs faction neutrality, not a nebula: same-
-- faction objects are always on the crew's contact list, and nebulae only
-- shadow the LONG-range radar. Reveal = flip faction + restore the radar.
function hide_station(st, reveal_to)
    st.demo_hidden = true
    st.demo_reveal_to = reveal_to
    st:setFaction("Independent")
    pcall(st.setShortRangeRadarRange, st, 0)
    return st
end

function station_reveal(name)                 -- one-way and idempotent
    local st = stations[name]
    if st == nil or not st:isValid() or found_waypoint then return end
    found_waypoint = true
    if st.demo_hidden and not st.demo_revealed then
        st.demo_revealed = true
        if st.demo_reveal_to then st:setFaction(st.demo_reveal_to) end
        pcall(st.setShortRangeRadarRange, st, 5000)    -- the engine default
    end
    notify("Waypoint 7 answers on our own channel - it is one of ours.", st)
end

-- ========================= dialogs =========================
-- The page function sets the text ONCE and adds choices; the *_replies function
-- ONLY adds choices. A callback that re-renders the page wipes its own result
-- text (the engine clears replies, then every setCommsMessage inside a callback
-- REPLACES the message) and the player's click looks dead.
function commsDepot(t, src)
    setCommsMessage([[Depot. Two cargo cores from the wrecked hauler are still out there.
The last beacon puts the debris in the nebula east of here - our relay, Waypoint 7,
went quiet out that way and dropped off the long-range radar with it.]])
    commsDepot_replies(t, src)
    return true
end

function commsDepot_replies(t, src)
    addCommsReply("What is out there?", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage([[Waypoint 7, our relay. It stopped answering an hour ago and its
transponder went dark. Nothing of ours shows on the long-range radar out that way.
Search the nebula cluster. Bring both cores back and dock or come alongside to
hand them over - the transfer gate is physical, so get next to the hull.]])
        commsDepot_replies(t, comms_source or src)   -- replies only: text stays
        return true
    end)
    addCommsReply("Hand over the cores.", function(comms_source, comms_target)
        math.abs(0)
        -- The page call already bound the ship that opened this dialog; inside
        -- a callback the engine-supplied comms_target/comms_source order is not
        -- something to bet the mission on, so prefer the captured source.
        local ship = src or comms_source
        setCommsMessage(act_deliver(t, ship))
        commsDepot_replies(t, comms_source or src)
        return true
    end)
    addCommsReply("Nothing to report.", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage("Stand by, then.")
        return true
    end)
end

-- The hand-over gate: physical proximity (or docking), never a script flag.
function act_deliver(station, ship)
    if ship == nil or not ship:isValid() then return "Nobody is alongside." end
    if not near_or_docked(ship, station, handover_u(station)) then
        return "Come alongside the station to hand the cores over."
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
    if n == 0 then return "Your cargo bay holds no core we need." end
    return ("Received %d core(s); %d of %d accounted for."):format(
        n, part_count_delivered(), #PART_NAMES)
end
-- ========================= drop-watchdog =========================
-- A container normally appears from an onDestruction hook, and that hook fires
-- ONLY on damage kills (takeHullDamage): a script destroy(), a GM removal or a
-- collision-only death drops nothing and the mission becomes unsolvable. So the
-- hook is the fast path and this polled watcher is the truth.
drop_watches = {}

function mk_drop_watch(part_name, group, on_drop, grace)
    local w = { part = part_name, group = group, on_drop = on_drop,
                grace = grace or DEMO.grace_s, drops = 0, done = false }
    table.insert(drop_watches, w)
    return w
end

function drop_watch()
    for _, w in ipairs(drop_watches) do drop_watch_run(w) end
end

function drop_watch_run(w)
    if w.done then return end
    for _, s in ipairs(w.group) do
        if s:isValid() then                 -- somebody is still out there
            w.x, w.y = s:getPosition()
            w.alive_at = clock
            return
        end
    end
    if part_accounted(w.part) then return end
    w.alive_at = w.alive_at or clock
    if clock - w.alive_at < w.grace then return end    -- give the hook its turn
    w.drops = w.drops + 1
    if w.drops >= 2 then w.done = true end             -- never spam crates
    w.on_drop(w.x or 0, w.y or 0)
    print("DEMO: drop watchdog fired for " .. w.part)
end

function guarded_cache_drop(x, y)
    if part_accounted("Nav core") then return end
    mk_part("Nav core", x, y)
    notify("The escort around the cache is down. The debris includes a cargo container.",
        stations.depot)
end

-- Story mode: player beams one-shot anything they hit. There is no
-- setBeamDamage() in 2024.12 - rewrite each arc through setBeamWeapon().
function story_buff(p)
    local n = 0
    for i = 0, 15 do
        local ok, arc = pcall(p.getBeamWeaponArc, p, i)
        if ok and arc and arc > 0 then
            local _, dir = pcall(p.getBeamWeaponDirection, p, i)
            local _, rng = pcall(p.getBeamWeaponRange, p, i)
            local _, cyc = pcall(p.getBeamWeaponCycleTime, p, i)
            if pcall(p.setBeamWeapon, p, i, arc, dir, rng, cyc, 5000) then n = n + 1 end
        end
    end
    print("DEMO: story buff on " .. (p:getCallSign() or "?") .. ": " .. n .. " beam(s)")
end

-- ========================= init =========================
function init()
    print("DEMO: init begin")

    player = PlayerSpaceship():setFaction("Human Navy"):setTemplate("Atlantis")
    player:setPosition(0, 0):setCallSign("Epsilon")

    stations.depot = mk_station("Depot", "Medium Station", "Human Navy", -U(20), 0, commsDepot)

    -- Nebula cluster east of Depot; the quiet relay sits in the middle of it.
    for i = 1, 5 do
        Nebula():setPosition(U(24 + (i % 3) * 6), U((i - 3) * 5))
    end
    for _ = 1, 40 do
        Asteroid():setPosition(random(U(15), U(40)), random(-U(15), U(15)))
    end

    stations.waypoint = hide_station(
        mk_station("Waypoint 7", "Small Station", "Human Navy", U(28), 0, nil), "Human Navy")

    mk_part("Coolant core", U(16), U(2))     -- one crate adrift near the wreck
    mk_station_cache()                       -- the other one is guarded

    notify([[Depot to Epsilon: the hauler broke up east of your position. Two cargo cores
survived the breakup. Recover both and bring them back. Fly close to anything
adrift - the shipping labels only resolve at short range.]], stations.depot)
    print("DEMO: init complete, difficulty=" .. DIFFICULTY)
end

-- A cache nobody can see yet, escorts leashed to it, and a drop-watch so the
-- second core exists no matter how those escorts die.
function mk_station_cache()
    local x, y = U(30), U(-6)
    stations.cache = mk_station("Cache 7", "Small Station", "Independent", x, y, nil)
    for i = 1, DEMO.patrol_n do
        local s = CpuShip():setTemplate("Adder MK5"):setFaction("Exuari")
            :setPosition(x + U(i), y + U(1)):orderIdle()
        table.insert(patrol, s)
    end
    mk_part("Nav core", x + U(station_hull_u(stations.cache) + 0.35), y)
    mk_drop_watch("Nav core", patrol, guarded_cache_drop)
end
-- ========================= update =========================
function update(delta)
    clock = clock + delta
    if done then return end
    local players = active_players()
    if #players > 0 then ever_had_players = true end
    ensure_ftl(players)
    pump_messages()

    -- Late joiners and GM respawns: init() only ever sees the first hull, so
    -- per-ship setup belongs in the poll loop with an idempotent guard flag.
    for _, p in ipairs(players) do
        if p:isValid() then
            p.demo_x, p.demo_y = p:getPosition()      -- "where did it die?"
            if not p.demo_watched then
                p.demo_watched = true
                if STORY_MODE then story_buff(p) end
            end
        end
    end

    -- Two-state labels: the engine never advances an Artifact's scan state, so
    -- flip all four descriptions once somebody is alongside.
    for _, c in ipairs(containers) do
        if not c.revealed and c.a:isValid() then
            for _, p in ipairs(players) do
                if d2(p, c.a) < U(DEMO.reveal_u) ^ 2 then
                    reveal_container(c)
                    break
                end
            end
        end
    end

    -- Discovery of the hidden relay: only a faction flip really hides a friendly
    -- station, so that is also what the reveal has to undo.
    if not found_waypoint then
        for _, p in ipairs(players) do
            if d2(p, stations.waypoint) < U(DEMO.find_u) ^ 2 then
                station_reveal("waypoint")
                break
            end
        end
    end

    -- Leash the cache escorts: they neither wander off-map nor camp on the crew.
    local cx, cy = stations.cache:getPosition()
    for _, s in ipairs(patrol) do
        if s:isValid() then
            local sx, sy = s:getPosition()
            if (sx - cx) ^ 2 + (sy - cy) ^ 2 > U(14) ^ 2 then s:orderFlyTowards(cx, cy) end
        end
    end

    drop_watch()

    if part_count_delivered() >= #PART_NAMES then
        done = true
        notify("Both cores are in. Well flown.", stations.depot)
        victory("Human Navy")
    elseif ever_had_players and #active_players() == 0 then
        done = true
        notify("All ships are gone. Depot marks the mission lost.", stations.depot)
        victory("Exuari")
    end
end

-- ========================= test hooks =========================
-- Reachable from the headless console and from an appended autotest driver.
-- Keep them read-mostly and idempotent so a test run cannot steer the mission.
function probe_state()
    print(("DEMO-STATE done=%s delivered=%d/%d found=%s players=%d patrol=%d t=%.1f"):format(
        tostring(done), part_count_delivered(), #PART_NAMES,
        tostring(found_waypoint), #active_players(), #patrol, clock))
    return part_count_delivered()
end

function probe_warp_to(x, y)
    for _, p in ipairs(active_players()) do p:setPosition(x, y) end
    print("DEMO-PROBE players warped to " .. tostring(x) .. "," .. tostring(y))
end

function probe_containers()
    for _, c in ipairs(containers) do
        print("DEMO-CONT name=" .. tostring(c.name or c.desc) ..
            " revealed=" .. tostring(c.revealed) .. " valid=" .. tostring(c.a:isValid()))
    end
end

-- Collection stands in for the crew here: pickup is COLLISION based, and a
-- teleported ship does not collide with anything, so a headless run cannot
-- trigger onPickUp. This exercises the same bookkeeping the hook does; the real
-- collision path is on the human-acceptance checklist.
function probe_pickup(name)
    local info = parts[tostring(name)]
    if info == nil then return "unknown" end
    if info.carried then return "carried" end
    if info.delivered then return "delivered" end
    if info.obj == nil or not info.obj:isValid() then return "missing" end
    info.obj:destroy()
    info.carried = active_players()[1] or true
    notify("Cargo bay secured: " .. tostring(name), stations.depot)
    return "carried"
end

function probe_part(name)
    local info = parts[tostring(name)]
    if info == nil then return "unknown" end
    if info.delivered then return "delivered" end
    if info.carried then return "carried" end
    if info.obj and info.obj:isValid() then return "adrift" end
    return "missing"
end

-- destroy() NEVER fires onDestruction (only damage kills do), so this is safe
-- only for polling-watched groups - exactly why the drop-watch exists.
function probe_kill_group(name)
    local g = (tostring(name) == "patrol") and patrol or {}
    local n = 0
    for _, s in ipairs(g) do
        if s:isValid() then s:destroy() n = n + 1 end
    end
    print("DEMO-PROBE killed " .. n .. " in " .. tostring(name))
    return n
end




