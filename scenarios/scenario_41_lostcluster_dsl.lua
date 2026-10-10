-- Name: Lost Cluster (DSL lite)
-- Description: A looted research cluster lies scattered across the sector. Trace the hint chain, clear the ambush at Tampere 1, and deliver the recovered hardware to Lumina 1.
--- Hand-emitted "generator output" for dsl/samples/lost-cluster-lite.yaml
--- (mission DSL schema v0.1). Purpose: validate the Phase-2 generator
--- contract (notes/05) against the real engine before writing
--- tools/mission_gen.py. Sections marked "scripts:" are the YAML's
--- raw-Lua passthrough; everything else shows the expected codegen shape.
-- Author: mission_gen (hand-emitted draft)
-- Type: Mission

-- ========================= generated state =========================
gen = {
    clock = 0, done = false, stage = 0,
    lastkill_x = 140000, lastkill_y = 20000,     -- b300_watcher drop spot
    gate_b = { x = 140000, y = 20000 },
    flags = {                                    -- flags: + auto once:
        ambush_spawned = false, ambush_cleared = false, b300_dropped = false,
        h200_delivered = false, b300_delivered = false,
        told_intel = false, told_tampere = false, tampere_found = false,
    },
}
gen_events_fired = { thieves = false }
E = {}                                           -- entity registry
E_ARCH = {                                       -- archetypes (at_start: false)
    raider  = { template = "Adder MK5",   faction = "Kraylor", list = {} },
    ambusher = { template = "Piranha F12", faction = "Kraylor", list = {} },
}
ITEMS = {                                        -- items: (one_of, bookkeeping
    h200 = { label = "H200 GPU nodes", carrier = false, obj = nil,   -- like LC)
             far = "A vented cargo crate with a scorched, unreadable label." },
    b300 = { label = "B300 GPU nodes", carrier = false, obj = nil,
             far = "A vented cargo crate with a scorched, unreadable label." },
}
GEN_LABEL_U = 5          -- items.label.scanned range (GAP-14)
GEN_FIND_U = 6           -- hidden station reveal range (GAP-4)
GEN_STATION_HULL_U = { ["Small Station"] = 0.3, ["Medium Station"] = 1.0,
                       ["Large Station"] = 1.3 }   -- scripts/model_data.lua

-- ========================= helpers (generator-provided) =========================
function U(u)
    return u * 1000
end

function gen_active_players()
    local t = {}
    local ok, list = pcall(getActivePlayerShips)
    if ok and list then
        for _, p in ipairs(list) do
            if p:isValid() then table.insert(t, p) end
        end
    end
    return t
end

function gen_player()
    local ok, list = pcall(getActivePlayerShips)
    if ok and list then
        for _, p in ipairs(list) do
            if p:isValid() then return p end
        end
    end
    return nil
end

function in_range(a, b, r)                       -- DSL: in_range(a, b, units)
    local ax, ay = a:getPosition()
    local bx, by = b:getPosition()
    return (ax - bx) ^ 2 + (ay - by) ^ 2 <= r * r
end

function gen_alive(arch)                         -- DSL: n_alive(archetype)
    local n = 0
    for _, s in ipairs(E_ARCH[arch].list) do
        if s:isValid() then n = n + 1 end
    end
    return n
end

function gen_spawn(arch, n, x, y)                -- DSL: spawn N arch in sys at anchor
    for i = 1, n do
        local s = CpuShip():setTemplate(E_ARCH[arch].template)
            :setFaction(E_ARCH[arch].faction)
            :setPosition(x + (i - 1) * 1500 - 750 * n, y + 800)
            :orderDefendLocation(x, y)
        s.lc_x, s.lc_y = s:getPosition()
        s:onDestruction(function(ship)
            math.abs(0)                          -- ScriptSimpleCallback upvalue trick
            gen.lastkill_x, gen.lastkill_y = ship.lc_x or x, ship.lc_y or y
        end)
        table.insert(E_ARCH[arch].list, s)
    end
end

function gen_ensure_ftl()                        -- world.ships.*.ftl: warp (GAP-6)
    for _, p in ipairs(gen_active_players()) do
        if p:isValid() and not p:hasWarpDrive() then
            p:setWarpDrive(true)
            p:setWarpSpeed(1000)
        end
    end
end

-- Notification queue: sendCommsMessage fails while a player sits in another
-- comms dialog, so station-voiced lines are queued and retried (LC lc_notify).
gen_msgq = {}

function gen_notify(msg, from)
    table.insert(gen_msgq, { msg = msg, from = from, until_s = gen.clock + 25, done = {} })
end

function gen_pump()
    if #gen_msgq == 0 then return end
    local players = gen_active_players()
    for i = #gen_msgq, 1, -1 do
        local q = gen_msgq[i]
        local sender = q.from
        if sender == nil or not sender:isValid() then sender = E.lumina end
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
        if not waiting or gen.clock > q.until_s then table.remove(gen_msgq, i) end
    end
end

-- ========================= item bookkeeping (GAP-9) =========================
-- LC model: `carried` is script bookkeeping, world drops are Artifacts.
function gen_carried(id)
    return ITEMS[id].carrier ~= false
end

function gen_has(ship, id)                       -- DSL: has(player, item)
    return ITEMS[id].carrier == ship
end

function gen_player_has(id)
    local p = gen_player()
    return p ~= nil and gen_has(p, id)
end

function gen_give(ship, id)                      -- DSL: give player item
    local o = ITEMS[id].obj
    if o and o:isValid() then pcall(o.destroy, o) end
    ITEMS[id].carrier = ship
end

function gen_take(ship, id)                      -- DSL: take player item
    ITEMS[id].carrier = false
end

function gen_item(id)
    local o = ITEMS[id].obj
    if o and o:isValid() then return o end
    return nil
end

function gen_take_item(id, ship)                 -- proximity pickup stand-in
    ITEMS[id].carrier = ship
end

function gen_spawn_item(id, x, y)
    -- GAP-14: an item should be able to declare what it READS before someone
    -- scans it. Artifacts never advance through the scan states (notes/06), so
    -- the generator has to write the current story text into base + all three
    -- states and flip them together on proximity (gen_watch_labels).
    local a = Artifact():setModel("artifact6"):setPosition(x, y):setSpin(0.3)
    gen_item_text(a, ITEMS[id].far)
    ITEMS[id].obj = a
    ITEMS[id].revealed = false
end

function gen_item_text(a, text)
    a:setDescription(text)
    a:setDescriptionForScanState("notscanned", text)
    a:setDescriptionForScanState("simplescan", text)
    a:setDescriptionForScanState("fullscan", text)
end

function gen_watch_labels(delta)                 -- GAP-2 + GAP-14
    math.abs(0)
    local p = gen_player()
    if p == nil then return end
    for _, it in pairs(ITEMS) do
        if it.obj ~= nil and it.obj:isValid() and not it.revealed
           and in_range(p, it.obj, U(GEN_LABEL_U)) then
            it.revealed = true
            gen_item_text(it.obj, "A cargo crate holding " .. it.label .. ".")
        end
    end
end

-- GAP-13: interactions have no range semantics in the grammar; the generator
-- gets "alongside" from the station hull (docking always counts).
function gen_station_hull_u(st)
    return GEN_STATION_HULL_U[st.lc_template] or 0.3
end

function gen_handover_u(st)
    local r = gen_station_hull_u(st) + 0.4
    if r < 1.0 then r = 1.0 end
    return r
end

function gen_near_or_docked(a, b)
    if a == nil or b == nil then return false end
    local docked = false
    pcall(function() docked = a:isDocked(b) end)
    if docked then return true end
    return in_range(a, b, U(gen_handover_u(b)))
end

-- GAP-15: no restock/shop primitive — this is the whole "service".
function gen_replenish(station, ship)
    if ship == nil then return "We cannot service a ship we cannot see." end
    if not gen_near_or_docked(ship, station) then
        return "Pull alongside us (within " .. string.format("%.1f", gen_handover_u(station)) ..
            " units), or dock, and we will load you up."
    end
    local mx, cur = 0, 0
    pcall(function() mx = ship:getWeaponStorageMax("Homing") or 0 end)
    if mx <= 0 then return "We would, but your hull has no homing tubes fitted - that is all we can spare." end
    pcall(function() cur = ship:getWeaponStorage("Homing") or 0 end)
    if cur >= mx then return "Your homing racks are already full: " .. cur .. " of " .. mx .. "." end
    ship:setWeaponStorage("Homing", mx)
    return "Loaded " .. (mx - cur) .. " homing missiles, no charge - that is all we can spare."
end

function gen_replenish_reply(t, src, replies)
    if t:getFaction() ~= "Human Navy" then return end
    addCommsReply("Replenish our homing missiles.", function(comms_source, comms_target)
        math.abs(0)
        local who = comms_source or src
        setCommsMessage(gen_replenish(t, who))
        replies(t, who)   -- replies only: the result stays visible
        return true
    end)
end

-- ========================= wormhole pair (generator fix, note 01) =========================
-- Exits sit 3.5U BEYOND the far mouth: the engine has no re-entry cooldown
-- and a 2.5U pull radius, so exiting AT the partner centre perma-loops.
gen_wh = {}
gen.transits = {}

function gen_transit(entry, obj)                 -- belt-and-braces re-entry guard
    local e
    for _, w in ipairs(gen.transits) do
        if w.obj == obj then e = w break end
    end
    local again = e ~= nil and (gen.clock - e.t) < 15
    if e then
        e.t = gen.clock
    else
        table.insert(gen.transits, { obj = obj, t = gen.clock })
    end
    if again and obj:isValid() then
        local tx, ty = entry.obj:getTargetPosition()
        pcall(obj.setPosition, obj, tx + entry.dirx * U(2), ty + entry.diry * U(2))
        print("GEN: wormhole re-entry suppressed")
    end
end

function gen_wormholes()
    local ax, ay = 60000, 0                      -- world.wormholes.gate.a
    local bx, by = 140000, 20000                 -- world.wormholes.gate.b
    local dx, dy = bx - ax, by - ay
    local dist = math.sqrt(dx * dx + dy * dy)
    local a = WormHole():setPosition(ax, ay)
    local b = WormHole():setPosition(bx, by)
    a:setTargetPosition(bx + dx / dist * U(3.5), by + dy / dist * U(3.5))
    b:setTargetPosition(ax - dx / dist * U(3.5), ay - dy / dist * U(3.5))
    gen_wh = { { obj = a, dirx = dx / dist, diry = dy / dist },
               { obj = b, dirx = -dx / dist, diry = -dy / dist } }
    for _, wh in ipairs(gen_wh) do
        local w = wh
        w.obj:onTeleportation(function(this_wh, obj)
            math.abs(0)
            gen_transit(w, obj)
        end)
    end
end

-- ========================= stations + init =========================
function gen_station(obj, fn, template)           -- LC mk_station pattern
    local st = obj
    st.lc_template = template                     -- hull radius (GAP-13)
    if fn then
        st:setCommsFunction(function(src)
            math.abs(0)
            return fn(st, src or comms_source or gen_player())
        end)
    end
    return st
end

-- GAP-4: `hidden: nebula` is not just a nebula — a same-faction object is
-- listed for the players at ANY range (shared telemetry, notes/06), so hiding
-- means staying out of the players' faction until someone gets close.
function gen_hide_station(st, reveal_to)
    st.lc_hidden, st.lc_reveal_to = true, reveal_to
    st:setFaction("Independent")
    pcall(st.setShortRangeRadarRange, st, 0)      -- no telemetry bubble
    return st
end

function gen_watch_hidden(delta)                  -- GAP-1/2/4: a `watch:` entry
    math.abs(0)
    local p = gen_player()
    if p == nil then return end
    for _, name in ipairs(gen.hidden_stations) do
        local st = E[name]
        if st ~= nil and st:isValid() and not st.lc_revealed
           and in_range(p, st, U(GEN_FIND_U)) then
            st.lc_revealed = true
            if st.lc_reveal_to then st:setFaction(st.lc_reveal_to) end
            pcall(st.setShortRangeRadarRange, st, 5000)
            gen.flags[name .. "_found"] = true
            print("GEN: " .. name .. " revealed")
        end
    end
end

function init()
    -- Factions: Kraylor are engine-default enemies of the Human Navy.
    E.lumina = gen_station(
        SpaceStation():setTemplate("Medium Station"):setFaction("Human Navy"):setPosition(0, 10000):setCallSign("Lumina 1"),
        dlg_lumina_intro, "Medium Station")
    E.lumina.lc_x, E.lumina.lc_y = 0, 10000
    Nebula():setPosition(150000, 20000)           -- world.stars.deep.has_nebula
    E.tampere = gen_station(
        SpaceStation():setTemplate("Small Station"):setFaction("Human Navy"):setPosition(150000, 20000):setCallSign("Tampere 1"),
        dlg_tampere_intro, "Small Station")
    E.tampere.lc_x, E.tampere.lc_y = 150000, 20000
    gen.hidden_stations = { "tampere" }
    gen_hide_station(E.tampere, "Human Navy")     -- GAP-4: hidden: nebula
    E.kajaani = gen_station(
        SpaceStation():setTemplate("Medium Station"):setFaction("Human Navy"):setPosition(200000, -30000):setCallSign("Kajaani 1"),
        dlg_kajaani_intro, "Medium Station")
    E.kajaani.lc_x, E.kajaani.lc_y = 200000, -30000

    gen_wormholes()

    E.player0 = PlayerSpaceship():setFaction("Human Navy"):setTemplate("Phobos M3P")
        :setPosition(3000, 13000):setCallSign("Epsilon")

    -- greeting event (auto: first player spawn) -> queued station hail
    gen_notify([[Epsilon, this is Lumina 1. Our research cluster was looted - Kajaani 1 was supposed to ship the first batch to us. Start with them; watch for Kraylor signatures near the deep-side gate.]], E.lumina)
    print("GEN: init complete")
end

-- ========================= dialogs: lumina =========================
function dlg_lumina_intro(t, src)
    setCommsMessage([[Lumina 1 here. Our research cluster was looted - Kajaani 1 was supposed to ship the first batch. Tampere 1 went dark on the deep side. Start with Kajaani.]])
    dlg_lumina_intro_replies(t, src)
    return true
end

function dlg_lumina_intro_replies(t, src)
    -- GAP-13: `take player <item>` is an interaction with no distance term in
    -- the grammar, but it is a physical transfer. The generator wraps every
    -- physical give/take in the hand-over gate (GAP-15 style condition).
    if gen_player_has("h200") then
        addCommsReply("Here's the H200 GPU nodes.", function(comms_source, comms_target)
            math.abs(0)
            local who = comms_source or src
            if not gen_near_or_docked(who, t) then
                setCommsMessage("Too far to transfer anything - come alongside us (within " ..
                    string.format("%.1f", gen_handover_u(t)) .. " units) or dock.")
                dlg_lumina_intro_replies(t, who)
                return true
            end
            gen_take(who, "h200")
            gen.flags.h200_delivered = true
            setCommsMessage([[The H200 nodes! Kajaani will be relieved.]])
            gen_notify([[That's the compute backbone. Anything else?]], t)
            dlg_lumina_intro_replies(t, who)
            return true
        end)
    end
    if gen_player_has("b300") then
        addCommsReply("We found the B300 nodes too.", function(comms_source, comms_target)
            math.abs(0)
            local who = comms_source or src
            if not gen_near_or_docked(who, t) then
                setCommsMessage("Too far to transfer anything - come alongside us (within " ..
                    string.format("%.1f", gen_handover_u(t)) .. " units) or dock.")
                dlg_lumina_intro_replies(t, who)
                return true
            end
            gen_take(who, "b300")
            gen.flags.b300_delivered = true
            setCommsMessage([[Recovered! You've put the cluster back together, spacer.]])
            gen_notify([[The whole batch is back. Well flown.]], t)
            dlg_lumina_intro_replies(t, who)
            return true
        end)
    end
    if not gen.flags.told_intel then                       -- once: told_intel
        addCommsReply("What do you know about the thieves?", function(comms_source, comms_target)
            math.abs(0)
            gen.flags.told_intel = true                    -- consumed on click
            return dlg_lumina_intel(t, comms_source or src)
        end)
    end
    gen_replenish_reply(t, src, dlg_lumina_intro_replies)  -- GAP-15
end

function dlg_lumina_intel(t, src)
    setCommsMessage([[Kraylor raiders, by the wreckage marks. Kajaani 1 was hit first; Tampere 1 went dark in the deep-system nebulae.]])
    dlg_lumina_intel_replies(t, src)
    return true
end

function dlg_lumina_intel_replies(t, src)
    addCommsReply("Back", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage([[Lumina 1 here. Our research cluster was looted - Kajaani 1 was supposed to ship the first batch. Tampere 1 went dark on the deep side. Start with Kajaani.]])
        dlg_lumina_intro_replies(t, comms_source or src)
        return true
    end)
end

-- ========================= dialogs: tampere =========================
function dlg_tampere_intro(t, src)
    setCommsMessage([[Tampere 1... we were boarded. Those ships outside - they've pinned us down.]])
    dlg_tampere_intro_replies(t, src)
    return true
end

function dlg_tampere_intro_replies(t, src)
    if gen.flags.ambush_spawned and gen_alive("ambusher") == 0 then
        addCommsReply("You're clear now. The H200 nodes?", function(comms_source, comms_target)
            math.abs(0)
            local who = comms_source or src
            if not gen_near_or_docked(who, t) then       -- GAP-13: physical hand-over
                setCommsMessage("Too far to transfer anything - come alongside us (within " ..
                    string.format("%.1f", gen_handover_u(t)) .. " units) or dock.")
                dlg_tampere_intro_replies(t, who)
                return true
            end
            gen_give(who, "h200")
            setCommsMessage([[Take them - they were always for Lumina 1. The thieves took the B300s toward the gate.]])
            gen_notify([[The H200 nodes are aboard. Deliver them to Lumina 1.]], t)
            dlg_tampere_intro_replies(t, who)
            return true
        end)
    end
    if not gen.flags.ambush_spawned then
        addCommsReply("We're holding, but those ships out there won't let us move a crate.", function(comms_source, comms_target)
            math.abs(0)
            setCommsMessage([[We're holding, but those ships out there won't let us move a crate.]])
            dlg_tampere_intro_replies(t, comms_source or src)
            return true
        end)
    end
    if gen.flags.ambush_spawned and gen_alive("ambusher") > 0 then
        addCommsReply("Please - clear the ships off us first.", function(comms_source, comms_target)
            math.abs(0)
            setCommsMessage([[Please - clear the ships off us first.]])
            dlg_tampere_intro_replies(t, comms_source or src)
            return true
        end)
    end
end

-- ========================= dialogs: kajaani =========================
function dlg_kajaani_intro(t, src)
    setCommsMessage([[Kajaani 1. Our stores were looted - the whole supercomputer shipment is gone. Tampere 1 and the others went dark with theirs.]])
    dlg_kajaani_intro_replies(t, src)
    return true
end

function dlg_kajaani_intro_replies(t, src)
    addCommsReply("Who would hit a research convoy?", function(comms_source, comms_target)
        math.abs(0)
        return dlg_kajaani_intel(t, comms_source or src)
    end)
    if not gen.flags.told_tampere then                     -- once: told_tampere
        addCommsReply("Where is Tampere 1?", function(comms_source, comms_target)
            math.abs(0)
            gen.flags.told_tampere = true                  -- consumed on click
            setCommsMessage([[Last ping came from the deep-system nebulae by the gate. If anyone had the first batch, Tampere did.]])
            gen_notify([[Tampere 1 last pinged in the deep-system nebulae, near the gate.]], t)
            dlg_kajaani_intro_replies(t, comms_source or src)
            return true
        end)
    end
    if gen.flags.told_intel then
        addCommsReply("Kraylor marks, we said. Everything points at the raiders.", function(comms_source, comms_target)
            math.abs(0)
            setCommsMessage([[Kraylor marks, we said. Everything points at the raiders.]])
            dlg_kajaani_intro_replies(t, comms_source or src)
            return true
        end)
    end
    gen_replenish_reply(t, src, dlg_kajaani_intro_replies)   -- GAP-15
end

function dlg_kajaani_intel(t, src)
    setCommsMessage([[Convoy escort logs say Kraylor marks on the boarding pods. Same signature that hit Tampere 1 and the deep-side freighters.]])
    dlg_kajaani_intel_replies(t, src)
    return true
end

function dlg_kajaani_intel_replies(t, src)
    addCommsReply("Back", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage([[Kajaani 1. Our stores were looted - the whole supercomputer shipment is gone. Tampere 1 and the others went dark with theirs.]])
        dlg_kajaani_intro_replies(t, comms_source or src)
        return true
    end)
end

-- ========================= scripts: (verbatim passthrough) =========================
-- --- scripts.ambush_watcher (GAP-1/2: would be a `watch:` entry) ---------
function gen_watch_ambush(delta)
    math.abs(0)
    if not gen.flags.ambush_spawned then
        local p = gen_player()
        -- GAP-2: this wants to be `watch: when in_range(player, tampere, 24000)`
        if p and in_range(p, E.tampere, 24000) then
            gen.flags.ambush_spawned = true
            gen_spawn("ambusher", 3, E.tampere.lc_x + 8000, E.tampere.lc_y)
            gen_notify("Tampere 1: they're launching again - we can't move!", E.tampere)
        end
    elseif not gen.flags.ambush_cleared and gen_alive("ambusher") == 0 then
        gen.flags.ambush_cleared = true
        gen_notify("Tampere 1: the ships around us are gone. The area is clear - hail us.", E.tampere)
    end
end

-- --- scripts.b300_watcher (GAP-3/9/12: would be on_destroy + initial + pickup) --
gen.b300_spot = { x = 140000, y = 20000 }        -- last seen raidler position
function gen_watch_b300(delta)
    math.abs(0)
    -- GAP-3/GAP-12: LC hooks onDestruction per thief, but that hook only fires
    -- on DAMAGE kills (notes/06) - a script-destroyed or GM-removed hull would
    -- take the cargo out of the game. So the DSL form must be a POLL, and the
    -- poll has to track the drop position ITSELF: the hook that would normally
    -- record it never ran.
    local alive = 0
    for _, s in ipairs(E_ARCH.raider.list) do
        if s:isValid() then
            gen.b300_spot.x, gen.b300_spot.y = s:getPosition()
            alive = alive + 1
        end
    end
    if not gen.flags.b300_dropped and alive == 0 and gen_event_fired("thieves") then
        gen.flags.b300_dropped = true
        -- Drop clear of the wormhole mouth the raidlers parked next to: a
        -- weighted object sitting in a mouth gets dragged/teleported forever
        -- (wormHole.cpp), which reads as a NaN position within seconds.
        gen_spawn_item("b300", gen.b300_spot.x + U(3), gen.b300_spot.y + U(3))
        gen_notify("Debris field by the gate: a GPU crate floats among the wreckage.")
    end
    -- GAP-9: no pickup semantics; proximity bookkeeping stand-in.
    if gen.flags.b300_dropped and not gen_carried("b300") then
        local p = gen_player()
        local it = gen_item("b300")
        if p and it and in_range(p, it, 6000) then
            gen_take_item("b300", p)
            gen_notify("Cargo bay: the B300 crate is aboard.")
        end
    end
end

-- ========================= events / stages / outcomes =========================
function gen_event_fired(name)
    return gen_events_fired[name] == true
end

function gen_events()
    -- events.thieves: after: 20, when: true
    if not gen_events_fired.thieves and gen.clock >= 20 then
        gen_events_fired.thieves = true
        gen_spawn("raider", 2, gen.gate_b.x, gen.gate_b.y)
        globalMessage("Long-range radar: Kraylor signatures hauling cargo near the deep-side gate.")
    end
end

GEN_STAGES = {
    { when = function() return true end,
      title = "Trace the loot",
      text = "Kajaani 1 (deep system) was looted. Find what happened to the cluster shipment." },
    { when = function() return gen.flags.ambush_cleared end,
      title = "Recover and deliver",
      text = "Tampere 1 is clear - collect the H200 nodes and bring the hardware to Lumina 1." },
    { when = function() return gen.flags.h200_delivered and gen.flags.b300_delivered end,
      title = "Cluster rebuilt",
      text = "Every component is back at Lumina 1." },
}

function gen_stages()
    local cur = 0
    for i, st in ipairs(GEN_STAGES) do
        if st.when() then cur = i end          -- last match wins (default first)
    end
    if cur ~= gen.stage then                   -- GAP-10: no directive API in
        gen.stage = cur                        -- 2024.12 -> announcement only
        local st = GEN_STAGES[cur]
        if st then globalMessage("Mission update: " .. st.title .. ". " .. st.text) end
    end
end

function gen_outcomes()
    if gen.done then return end
    if gen.flags.h200_delivered and gen.flags.b300_delivered then
        gen.done = true
        globalMessage("The research cluster is whole again. Lumina 1 owes you a drink.")
        victory("Human Navy")
    elseif gen_player() == nil then
        gen.done = true                        -- GAP-11: no fail() -> the
        globalMessage("The recovery fleet lost its only hull. The loot is gone with it.")
        victory("Kraylor")                     -- enemy faction wins
    end
end

-- ========================= update (generator tick loop) =========================
function update(delta)
    gen.clock = gen.clock + delta
    gen_pump()
    gen_ensure_ftl()
    for _, a in pairs(E_ARCH) do               -- position tracking (lc_x/lc_y)
        for _, s in ipairs(a.list) do
            if s:isValid() then s.lc_x, s.lc_y = s:getPosition() end
        end
    end
    if gen.done then return end
    gen_events()
    gen_watch_ambush(delta)                    -- scripts: watchers, in YAML order
    gen_watch_hidden(delta)                    -- GAP-4: hidden: nebula reveal
    gen_watch_b300(delta)
    gen_watch_labels(delta)                    -- GAP-14: item label states
    gen_stages()
    gen_outcomes()
end
