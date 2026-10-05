-- Name: Lost Cluster
-- Description: A stolen supercomputer cluster lies scattered across the sector. Recover every component, find the Ansible Playbooks, and defend Lumina 1.
--- The research cluster of Lumina 1 was looted and hauled to hidden facilities across the sector.
--- Phase 1: follow the hint chain (Kajaani 1 -> Tampere 1 / Turku 1 -> LUT 1) and recover all six
--- cluster components. Phase 2: ten civilian freighters shuttle between the stations - three of
--- them were handed an Ansible Playbook. Phase 3: the enemy is coming for Lumina 1.
-- Author: scenario-dev (implements scenarios/scenario_40_lostcluster.md)
-- Type: Mission

-- ========================= scale & helpers =========================
-- 1 in-game displayed unit == 1000 script units. Sector grid is the engine
-- native one: letters are rows (A top), numbers are columns (1 left).
function U(u)
    return u * 1000
end

function sector_center(sector)
    local x, y = sectorToXY(sector)
    return x + 10000, y + 10000
end

function hint_sector(st)
    local x, y = st:getPosition()
    return getSectorName(x + random(-U(30), U(30)), y + random(-U(30), U(30)))
end

function d2(a, b)
    local ax, ay = a:getPosition()
    local bx, by = b:getPosition()
    return (ax - bx) ^ 2 + (ay - by) ^ 2
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

-- Stock EE ship templates (incl. the Phobos M3P players start in) ship
-- WITHOUT any FTL. This map spans many sectors, so install warp drives on
-- players and transports. Called every tick: cheap (hasWarpDrive guard),
-- and covers late joiners, respawns and phase-2 transport replacements.
WARP_SPEED = 1   -- ~1 sector/second: the whole map is ~20 s of warp

function ensure_ftl(players)
    for _, p in ipairs(players or active_players()) do
        if p:isValid() and not p:hasWarpDrive() then
            p:setWarpDrive(true)
            p:setWarpSpeed(WARP_SPEED)
        end
    end
    for _, t in ipairs(transports) do
        if t:isValid() and not t:hasWarpDrive() then
            t:setWarpDrive(true)
            t:setWarpSpeed(WARP_SPEED)
        end
    end
end

function all_dead(group)
    for _, s in ipairs(group) do
        if s:isValid() then return false end
    end
    return true
end

function leash(group, anchor, radius)
    local ax, ay = anchor:getPosition()
    for _, s in ipairs(group) do
        if s:isValid() then
            local sx, sy = s:getPosition()
            if (sx - ax) ^ 2 + (sy - ay) ^ 2 > radius ^ 2 then
                s:orderFlyTowards(ax, ay)
            end
        end
    end
end

function lc_notify(msg)
    for _, p in ipairs(active_players()) do
        stations.lumina:sendCommsMessage(p, msg)
    end
end

lc_broadcast = lc_notify

-- ========================= world state =========================
phase = 1
done = false
stations = {}
found = { tampere = false, turku = false, lut = false }
known = { lumina = true, kajaani = true }
parts = {}          -- name -> { carried=ship|false, delivered=bool }
PART_NAMES = { "AMD compute nodes", "B300 GPU nodes", "H200 GPU nodes",
               "Intel compute nodes", "Lustre fileserver", "Infiniband switches" }
BOOK_NAMES = { "Ansible Playbook 1 (of 3)", "Ansible Playbook 2 (of 3)",
               "Ansible Playbook 3 (of 3)" }
groups = { ambush = {}, lut = {}, b300 = {}, guards = {}, wave = {} }
tampere_state = "waiting"     -- waiting | ambush | clear
lut_state = "friendly"        -- friendly | hostile | liberated
turku_greeted = false
infini_hint_given = false
transports = {}
guard_slots = {}              -- { name, respawns_left, timer, ships={} }
phase3 = { armed = false, warned = false, timer = 0, spawned = false }
taunt_armed = {}

function part_delivered_count(names)
    local n = 0
    for _, name in ipairs(names) do
        if parts[name] and parts[name].delivered then n = n + 1 end
    end
    return n
end

-- ========================= cargo containers =========================
function mk_container(desc, x, y)
    local a = Artifact():setModel("artifact6"):setPosition(x, y):setSpin(0.3)
    a:setDescription(desc)
    a:setDescriptionForScanState("notscanned", "An unmarked cargo container.")
    a:setDescriptionForScanState("simplescan", "A cargo container with a worn shipping label.")
    a:setDescriptionForScanState("fullscan", desc)
    return a
end

function mk_junk(x, y)
    local a = mk_container("Junk (spare parts).", x, y)
    a:allowPickup(false)
    return a
end

function mk_part(name, x, y)
    parts[name] = parts[name] or { carried = false, delivered = false }
    local a = mk_container("Cluster component: " .. name, x, y)
    a:allowPickup(true)
    a:onPickUp(function(art, ship)
        if parts[name].obj == art and art:isValid() then art:destroy() end
        parts[name].carried = ship
        lc_notify("Cargo bay secured: " .. name)
    end)
    parts[name].obj = a
    return a
end

-- ========================= init =========================
function init()
    -- Note on factions: Kraylor are only wired as enemies of the Human Navy, so
    -- Independent civilian traffic is left alone by both sides by default.

    -- Stations.
    local lx, ly = sector_center("E3")
    stations.lumina = mk_station("Lumina 1", "Medium Station", "Human Navy", lx, ly, commsLumina)
    local kx, ky = sector_center("H20")
    stations.kajaani = mk_station("Kajaani 1", "Medium Station", "Human Navy", kx, ky, commsKajaani)
    -- Hidden stations sit inside a nebula: radar-shadowed until someone flies in.
    local tx, ty = sector_center("H5")
    Nebula():setPosition(tx, ty)
    stations.tampere = mk_station("Tampere 1", "Small Station", "Human Navy", tx, ty, commsTampere)
    local ux, uy = sector_center("B2")
    Nebula():setPosition(ux, uy)
    stations.turku = mk_station("Turku 1", "Small Station", "Human Navy", ux, uy, commsTurku)
    local lx3, ly3 = sector_center("L3")
    Nebula():setPosition(lx3, ly3)
    stations.lut = mk_station("LUT 1", "Small Station", "Human Navy", lx3, ly3, commsLUT)

    -- Home area dressing around Lumina 1.
    Nebula():setPosition(lx + U(4), ly + U(2))
    for i = 1, 25 do
        Asteroid():setPosition(lx + random(-U(8), U(8)), ly + random(-U(8), U(8)))
    end
    for i = 1, 6 do
        Mine():setFaction("Independent"):setPosition(lx + random(-U(7), U(7)), ly + random(-U(7), U(7)))
    end
    for i = 1, 2 do
        CpuShip():setTemplate("Piranha F12"):setFaction("Human Navy")
            :setPosition(lx + random(-U(3), U(3)), ly + random(-U(3), U(3))):orderDefendLocation(lx, ly)
    end

    -- B300 thief patrol in sector C10 (they are hauling the B300 GPU nodes).
    local bx, by = sector_center("C10")
    for i, tmpl in ipairs({ "Piranha F12", "Piranha F12", "Adder MK5", "Adder MK5" }) do
        local s = CpuShip():setTemplate(tmpl):setFaction("Kraylor")
            :setPosition(bx + random(-U(3), U(3)), by + random(-U(3), U(3))):orderDefendLocation(bx, by)
        s:onDestruction(b300_died)
        table.insert(groups.b300, s)
    end

    -- Central-map traffic, rows E-J x columns 6-15: static friendly lanes and
    -- hostile outposts; the engine AI engages anything that comes too close.
    for i = 1, 4 do
        CpuShip():setTemplate("Atlantis"):setFaction("Independent")
            :setPosition(random(20000, 220000), random(-20000, 100000)):setCallSign("Shuttle " .. i)
            :orderRoamingAt(random(20000, 220000), random(-20000, 100000))
    end
    for i = 1, 3 do
        CpuShip():setTemplate("Piranha F12"):setFaction("Kraylor")
            :setPosition(random(40000, 200000), random(0, 80000)):orderDefendLocation(random(40000, 200000), random(0, 80000))
    end

    -- Turku 1 hid the Intel nodes and the Lustre server in nearby nebulas.
    spawn_turku_field(ux, uy)
    -- The Infiniband switches were dumped somewhere in the mid-map box A-E x 8-13.
    spawn_infini_field()

    -- First player ship (the GM can spawn more during play).
    player0 = PlayerSpaceship():setFaction("Human Navy"):setTemplate("Phobos M3P")
        :setPosition(lx + 3000, ly + 3000):setCallSign("Epsilon")
    watch_player(player0)

    stations.lumina:sendCommsMessage(player0,
        [[Epsilon, this is Lumina 1. Our research cluster was looted and the parts are being
moved to hidden facilities across the sector. Kajaani 1 was supposed to ship the first batch - they are
on the far side of the map, near sector ]] .. getSectorName(kx, ky) ..
    [[. Start with them. Scan anything suspicious; cargo containers reveal their
contents only under a full scan.]])
    print("LC: init complete, phase=" .. phase)
end

function mk_station(name, tmpl, fac, x, y, fn)
    local s = SpaceStation():setTemplate(tmpl):setFaction(fac):setPosition(x, y)
    s:setCallSign(name)
    if fn then s:setCommsFunction(fn) end
    return s
end

function watch_player(p)
    p:onDestruction(function(ship, instigator)
        for name, info in pairs(parts) do
            if info.carried == ship and not info.delivered then
                info.carried = false
                mk_part(name, ship.lc_x or 0, ship.lc_y or 0)
            end
        end
        lc_notify("Lost contact with a ship! Cargo was ejected. The GM can spawn a replacement ship.")
    end)
end

function spawn_turku_field(ux, uy)
    local nebs = {}
    for i = 1, 7 do
        local nx, ny = ux + random(-U(25), U(25)), uy + random(-U(25), U(25))
        Nebula():setPosition(nx, ny)
        table.insert(nebs, { x = nx, y = ny })
    end
    local a = math.random(1, 7)
    local b = math.random(1, 7)
    while b == a do b = math.random(1, 7) end
    mk_part("Intel compute nodes", nebs[a].x + random(-2000, 2000), nebs[a].y + random(-2000, 2000))
    mk_part("Lustre fileserver", nebs[b].x + random(-2000, 2000), nebs[b].y + random(-2000, 2000))
    local placed = 0
    for i = 1, 7 do
        if i ~= a and i ~= b and placed < 4 then
            placed = placed + 1
            mk_junk(nebs[i].x + random(-2000, 2000), nebs[i].y + random(-2000, 2000))
        end
    end
    for i = 1, 3 do
        mk_junk(ux + random(-U(20), U(20)), uy + random(-U(20), U(20)))
    end
end

function spawn_infini_field()
    local x0, y0 = sectorToXY("A8")
    local cx, cy = x0 + U(60), y0 + U(50)
    local ex, ey = cx + random(-U(40), U(40)), cy + random(-U(40), U(40))
    Nebula():setPosition(ex, ey)
    mk_part("Infiniband switches", ex + random(-2000, 2000), ey + random(-2000, 2000))
    local decoys = {}
    for i = 1, 8 do
        local nx, ny = cx + random(-U(45), U(45)), cy + random(-U(45), U(45))
        Nebula():setPosition(nx, ny)
        table.insert(decoys, { x = nx, y = ny })
    end
    for i = 1, 3 do
        local d = decoys[math.random(1, #decoys)]
        mk_junk(d.x + random(-2000, 2000), d.y + random(-2000, 2000))
    end
end

-- ========================= comms trees =========================
function lc_status()
    local s = "Lost Cluster status.\n"
    if phase == 1 then
        s = s .. "Phase 1: cluster recovery - " .. part_delivered_count(PART_NAMES) .. " of 6 components delivered to Lumina 1.\n"
        for _, name in ipairs(PART_NAMES) do
            local info = parts[name]
            if info and info.delivered then
                s = s .. "  [x] " .. name .. "\n"
            else
                local where = "unknown - ask around the stations"
                if info and info.carried then where = "in a cargo bay, bring it to Lumina 1" end
                s = s .. "  [ ] " .. name .. " - " .. where .. "\n"
            end
        end
        if infini_hint_given then
            s = s .. "The Infiniband switches were dumped somewhere in the mid-map box, rows A-E x columns 8-13."
        end
    elseif phase == 2 then
        s = s .. "Phase 2: Ansible Playbooks - " .. part_delivered_count(BOOK_NAMES) .. " of 3 recovered.\n" ..
            "Ten Neutral freighters shuttle between the stations. Deep-scan them: three were handed a playbook. Hail one to make it stop, then pull alongside and hail again for the transfer."
    else
        s = s .. "Phase 3: a Kraylor wave is inbound to Lumina 1. Destroy it - that is the battle we win the war with."
    end
    return s
end

function lc_who_has()
    local s = "Here is who knows what:\n"
    local kx, ky = stations.kajaani:getPosition()
    s = s .. "Kajaani 1 (visible, sector " .. getSectorName(kx, ky) .. ") knows where Tampere 1 and Turku 1 went.\n"
    if known.tampere then
        s = s .. "Tampere 1: last signal near sector " .. hint_sector(stations.tampere) .. ", possibly up to 50u off.\n"
    else
        s = s .. "Tampere 1: hidden - ask Kajaani 1.\n"
    end
    if known.turku then
        s = s .. "Turku 1: last signal near sector " .. hint_sector(stations.turku) .. ", possibly up to 50u off.\n"
    else
        s = s .. "Turku 1: hidden - ask Kajaani 1.\n"
    end
    if known.lut then
        s = s .. "LUT 1: coordinates point near sector " .. hint_sector(stations.lut) .. "."
    else
        s = s .. "LUT 1: rumoured to hold AMD nodes - Tampere 1 has the coordinates, but they are tight-lipped unless you are within 10u of them."
    end
    return s
end

function carrying_any(ship)
    for _, info in pairs(parts) do
        if info.carried == ship and not info.delivered then return true end
    end
    return false
end

function commsLumina()
    setCommsMessage("Lumina 1 here.\n" .. lc_status())
    commsLumina_replies()
    return true
end

function commsLumina_replies()
    addCommsReply("What is the mission status?", function()
        setCommsMessage(lc_status())
        commsLumina_replies()
    end)
    addCommsReply("Who might have the cluster hardware?", function()
        setCommsMessage(lc_who_has())
        commsLumina_replies()
    end)
    if carrying_any(comms_source) then
        addCommsReply("Hand over the recovered equipment.", function()
            setCommsMessage(deliver_to_lumina(comms_source))
            commsLumina_replies()
        end)
    end
end

function deliver_to_lumina(ship)
    local given = {}
    for _, name in ipairs(PART_NAMES) do
        local info = parts[name]
        if info and info.carried == ship and not info.delivered then
            info.delivered = true
            info.carried = false
            table.insert(given, name)
        end
    end
    for _, name in ipairs(BOOK_NAMES) do
        local info = parts[name]
        if info and info.carried == ship and not info.delivered then
            info.delivered = true
            info.carried = false
            table.insert(given, name)
        end
    end
    if #given == 0 then return "We have nothing to take from you." end
    local msg = "Received: " .. table.concat(given, ", ") .. "."
    if phase == 2 and part_delivered_count(BOOK_NAMES) >= #BOOK_NAMES and not phase3.armed then
        phase3.armed = true
        print("LC: all playbooks delivered, phase 3 armed")
    end
    local ndone = part_delivered_count(PART_NAMES)
    if phase == 1 and ndone >= #PART_NAMES then
        msg = msg .. "\nAll six components! But our Ansible Playbooks were loaded onto a civilian transport. We are launching shuttle patrols to help you find them."
        phase2_start()
        return msg
    end
    if phase == 1 and not infini_hint_given then
        infini_hint_given = true
        known.infini = true
        msg = msg .. "\nStill missing: the Infiniband switches. Intel places them somewhere in the mid-map box, rows A-E x columns 8-13. Search the nebulas there."
    elseif phase == 1 then
        msg = msg .. "\n" .. ndone .. " of 6 components delivered."
    end
    if phase == 2 then
        msg = msg .. "\n" .. part_delivered_count(BOOK_NAMES) .. " of 3 playbooks recovered."
    end
    return msg
end

function commsKajaani()
    setCommsMessage([[Kajaani 1. Our stores were looted - the whole supercomputer shipment is gone.
We were supposed to ship the first batch to Lumina 1. Whoever did this also hit Tampere 1 and Turku 1;
those two went dark with their stations, moving out of long-range radar.]])
    addCommsReply("Where are Tampere 1 and Turku 1?", function()
        known.tampere = true
        known.turku = true
        setCommsMessage([[ Tampere 1 last pinged near sector ]] .. hint_sector(stations.tampere) ..
            [[ and Turku 1 near sector ]] .. hint_sector(stations.turku) ..
            [[. The reply beacon drifts, so they can be up to 50u from those sector squares.
If you find out anything about LUT 1, they were moving AMD nodes - but that is all we know.]])
        commsKajaani()
    end)
    addCommsReply("We will look around.", function() setCommsMessage("Good luck out there.") end)
    return true
end

function commsTampere()
    if tampere_state == "ambush" then
        setCommsMessage([[Tampere 1: we are under attack! Clear those ships from around us before we can talk.]])
        return true
    end
    setCommsMessage([[Tampere 1 here. We still have the H200 GPU nodes, hidden in the nebula around us.
The B300 GPU nodes were taken by Kraylor ships - our trackers say they headed for sector C10.]])
    addCommsReply("Collect the H200 GPU nodes.", function()
        if not part_out_there("H200 GPU nodes") then
            local x, y = comms_target:getPosition()
            mk_part("H200 GPU nodes", x + random(-3000, 3000), y + random(-3000, 3000))
            setCommsMessage("We float a container out to you - it is just outside the station.")
        else
            setCommsMessage("The container is already out there - check your sensors.")
        end
        commsTampere()
    end)
    addCommsReply("What about LUT 1?", function()
        local near = false
        for _, p in ipairs(active_players()) do
            if d2(p, comms_target) < U(10) ^ 2 then near = true break end
        end
        if near then
            known.lut = true
            setCommsMessage([[Fine - you have earned it. LUT 1 sits near sector ]] .. hint_sector(stations.lut) ..
                [[ with our AMD compute nodes. But something is wrong there: their last transmissions were... wrong. Attack anything Kraylor-painted nearby, and do not go in alone.]])
        else
            setCommsMessage("That information is confidential. Approach within 10 units of us and we will talk.")
        end
        commsTampere()
    end)
    return true
end

function commsTurku()
    setCommsMessage([[Turku 1. We were attacked, so we hid the Intel compute nodes and the Lustre
fileserver in cargo containers across seven nebulas around us - our courier ship made it that far before
it was shot down. The containers only say what is inside under a full scan; the Kraylor left junk
decoys behind. LUT 1 has the AMD nodes, if they are still ours to ask.]])
    addCommsReply("Anything else?", function()
        setCommsMessage("The nebula shadows hide things at long range. Fly into each one and sweep with short-range sensors.")
        commsTurku()
    end)
    return true
end

function commsLUT()
    if lut_state == "hostile" then
        setCommsMessage([[Alone you are weak and we will be victorious! Come back with more people, or stay away.]])
        return true
    end
    if lut_state == "friendly" then
        setCommsMessage([[LUT 1, operations. The AMD compute node shipment is still in our bay. Is there a problem?]])
        addCommsReply("We will check the perimeter.", function() setCommsMessage("Understood. Sensors show Kraylor signatures on the station - be careful.") end)
        return true
    end
    setCommsMessage([[LUT 1 is back under our control - and that was no accident; they were already inside
when we opened the doors. The AMD compute nodes are aboard; we are floating the container out to you.]])
    addCommsReply("Collect the AMD compute nodes.", function()
        if not part_out_there("AMD compute nodes") then
            local x, y = comms_target:getPosition()
            mk_part("AMD compute nodes", x + random(-3000, 3000), y + random(-3000, 3000))
            setCommsMessage("Container is away, just outside the station.")
        else
            setCommsMessage("It is already outside - check short-range sensors.")
        end
        commsLUT()
    end)
    return true
end

function commsTransport()
    local t = comms_target
    if t.lc_book == nil then
        setCommsMessage("Freighter " .. t:getCallSign() .. ", standard cargo between the stations. Nothing for you here.")
        return true
    end
    if parts[t.lc_book] and parts[t.lc_book].given then
        setCommsMessage("Freighter " .. t:getCallSign() .. ". We already handed over that data core.")
        return true
    end
    if not t.lc_stopped then
        setCommsMessage("Freighter " .. t:getCallSign() .. " here, busy on a run.")
        addCommsReply("Please stop for a data transfer.", function()
            t:orderIdle()
            t.lc_stopped = true
            setCommsMessage("Fine, we are stopping. Pull alongside, stop, and hail us to initiate the transfer.")
            commsTransport()
        end)
        return true
    end
    setCommsMessage("Freighter " .. t:getCallSign() .. " is stopped. We were told to hand over one Ansible Playbook to whoever came looking.")
    addCommsReply("We would like to transfer the Ansible Playbook.", function()
        if d2(comms_source, t) < U(2) ^ 2 then
            parts[t.lc_book].given = true
            local x, y = t:getPosition()
            mk_part(t.lc_book, x + 1500, y + 1500)
            setCommsMessage("Transferring the playbook container into your cargo bay area. Away it goes.")
            commsTransport()
        else
            setCommsMessage("Too far - get within 2 units and stop first.")
            commsTransport()
        end
    end)
    return true
end

-- ========================= event callbacks =========================
function b300_died(ship, instigator)
    if part_delivered_count({ "B300 GPU nodes" }) > 0 then return end
    if parts["B300 GPU nodes"] and parts["B300 GPU nodes"].obj then return end
    for _, s in ipairs(groups.b300) do
        if s:isValid() then return end
    end
    local x, y = ship.lc_x or 0, ship.lc_y or 0
    mk_part("B300 GPU nodes", x, y)
    lc_notify("The Kraylor patrol in C10 is destroyed. Debris includes a cluster component container - the B300 GPU nodes.")
end

-- ========================= update & triggers =========================
clock = 0
book_transport = {}

function update(delta)
    clock = clock + delta
    if done then return end
    local players = active_players()
    ensure_ftl(players)

    -- Remember positions so drops land where the ship died.
    local tracked = {}
    for _, p in ipairs(players) do tracked[p] = true end
    for _, gname in ipairs({ "ambush", "lut", "b300", "wave" }) do
        for _, s in ipairs(groups[gname]) do tracked[s] = true end
    end
    for _, t in ipairs(transports) do tracked[t] = true end
    for s in pairs(tracked) do
        if s:isValid() then
            local x, y = s:getPosition()
            s.lc_x, s.lc_y = x, y
        end
    end

    -- Discovery of the hidden stations.
    for _, name in ipairs({ "tampere", "turku", "lut" }) do
        if not found[name] then
            for _, p in ipairs(players) do
                if d2(p, stations[name]) < U(40) ^ 2 then
                    found[name] = true
                    print("LC: station " .. name .. " found")
                    break
                end
            end
        end
    end

    -- Tampere 1: ambush on first approach.
    if tampere_state == "waiting" then
        for _, p in ipairs(players) do
            if d2(p, stations.tampere) < U(20) ^ 2 then
                tampere_ambush()
                break
            end
        end
    elseif tampere_state == "ambush" then
        leash(groups.ambush, stations.tampere, U(22))
        if all_dead(groups.ambush) then
            tampere_state = "clear"
            lc_notify("Tampere 1: the ships around us are gone. The area is clear - hail us.")
        end
    end

    -- Turku 1 greets arriving ships.
    if not turku_greeted then
        for _, p in ipairs(players) do
            if d2(p, stations.turku) < U(20) ^ 2 then
                stations.turku:sendCommsMessage(p, [[Turku 1 here! We hid the Intel compute nodes and the
Lustre server in cargo containers across seven nebulas around us. Full-scan everything - the Kraylor
scattered junk decoys among them.]])
                turku_greeted = true
                break
            end
        end
    end

    -- LUT 1: the trap, the taunts, the liberation.
    if lut_state == "friendly" then
        for _, p in ipairs(players) do
            if d2(p, stations.lut) < U(20) ^ 2 then
                lut_reveal()
                break
            end
        end
    elseif lut_state == "hostile" then
        leash(groups.lut, stations.lut, U(20))
        for _, p in ipairs(players) do
            local d = d2(p, stations.lut)
            if d > U(40) ^ 2 then
                taunt_armed[p] = true
            elseif d < U(20) ^ 2 and taunt_armed[p] ~= false then
                local with = 0
                for _, q in ipairs(players) do
                    if d2(q, stations.lut) < U(30) ^ 2 then with = with + 1 end
                end
                if with <= 1 then
                    taunt_armed[p] = false
                    stations.lut:sendCommsMessage(p, [[Alone you are weak and we will be victorious!
Come back with more people, or stay away.]])
                end
            end
        end
        if all_dead(groups.lut) then
            lut_state = "liberated"
            stations.lut:setFaction("Human Navy")
            lc_notify("LUT 1 is back under Human Navy control. The AMD compute nodes are aboard - hail the station.")
        end
    end

    -- Phase 2 machinery.
    if phase >= 2 then
        update_transports(delta)
    end

    -- Phase 3: leave base and the hammer falls.
    if phase3.armed and not phase3.warned then
        for _, p in ipairs(players) do
            if d2(p, stations.lumina) > U(40) ^ 2 then
                phase3.warned = true
                phase3.timer = 180
                lc_notify([[Lumina 1 to all ships: a large Kraylor force has been detected approaching the
station. Return to Lumina 1 immediately and prepare for defense!]])
                break
            end
        end
    elseif phase3.warned and not phase3.spawned then
        phase3.timer = phase3.timer - delta
        if phase3.timer <= 0 then
            spawn_wave()
            phase3.spawned = true
        end
    elseif phase3.spawned and all_dead(groups.wave) then
        done = true
        lc_notify("The Kraylor wave is destroyed. Lumina 1 is safe - the cluster will live again. Well done!")
        print("LC: mission complete - victory declared")
        victory("Human Navy")
    end
end

function tampere_ambush()
    tampere_state = "ambush"
    local x, y = stations.tampere:getPosition()
    local players = active_players()
    for i = 1, 3 do
        local s = CpuShip():setTemplate("Adder MK5"):setFaction("Kraylor")
            :setPosition(x + random(-U(4), U(4)), y + random(-U(4), U(4)))
        if #players > 0 then s:orderAttack(players[1]) else s:orderRoaming() end
        table.insert(groups.ambush, s)
    end
    lc_notify("Unidentified ships warping in around Tampere 1!")
end

function lut_reveal()
    lut_state = "hostile"
    stations.lut:setFaction("Kraylor")
    local x, y = stations.lut:getPosition()
    local n = math.max(2, 3 * #active_players())
    for i = 1, n do
        local s = CpuShip():setTemplate("Piranha F12"):setFaction("Kraylor")
            :setPosition(x + random(-U(3), U(3)), y + random(-U(3), U(3))):orderDefendLocation(x, y)
        table.insert(groups.lut, s)
    end
    print("LC: LUT 1 revealed as hostile, garrison=" .. n)
end

-- ========================= phase 2 machinery =========================
function phase2_start()
    phase = 2
    local route = { stations.lumina, stations.kajaani, stations.tampere, stations.turku, stations.lut }
    local order = {}
    for i = 1, 10 do order[i] = i end
    for i = 10, 2, -1 do
        local j = math.random(1, i)
        order[i], order[j] = order[j], order[i]
    end
    for i = 1, 10 do
        local st = route[math.random(1, #route)]
        local sx, sy = st:getPosition()
        local t = CpuShip():setTemplate("Atlantis"):setFaction("Independent")
            :setPosition(sx + random(-2000, 2000), sy + random(-2000, 2000)):setCallSign("Freighter " .. i)
        t.lc_stopped = false
        t.lc_book = nil
        t.lc_next = nil
        t:setDescriptionForScanState("fullscan", "A civilian freighter. Cargo manifest: routine supplies.")
        t:setCommsFunction(commsTransport)
        t:onDestruction(transport_died)
        table.insert(transports, t)
    end
    for k = 1, 3 do
        local t = transports[order[k]]
        t.lc_book = BOOK_NAMES[k]
        book_transport[BOOK_NAMES[k]] = t
        parts[BOOK_NAMES[k]] = { carried = false, delivered = false }
        t:setDescriptionForScanState("fullscan", "A civilian freighter. Cargo manifest: one Ansible Playbook, sealed.")
        local gx, gy = t:getPosition()
        local slot = { name = BOOK_NAMES[k], respawns_left = 2, respawn_at = nil, ships = {} }
        for i = 1, 2 do
            local g = CpuShip():setTemplate("Adder MK5"):setFaction("Kraylor")
                :setPosition(gx + random(-U(4), U(4)), gy + random(-U(4), U(4))):orderDefendLocation(gx, gy)
            g.lc_slot = slot
            g:onDestruction(guard_died)
            table.insert(slot.ships, g)
            table.insert(groups.guards, g)
        end
        table.insert(guard_slots, slot)
    end
    print("LC: phase 2 start, 10 transports, 3 playbook guards")
end

function update_transports(delta)
    local route = { stations.lumina, stations.kajaani, stations.tampere, stations.turku, stations.lut }
    for i, t in ipairs(transports) do
        if t:isValid() then
            if not t.lc_stopped then
                if t.lc_next == nil or d2(t, t.lc_next) < U(3) ^ 2 then
                    t.lc_next = route[math.random(1, #route)]
                    local x, y = t.lc_next:getPosition()
                    t:orderFlyTowards(x, y)
                end
            end
        elseif t.lc_respawn_at and clock >= t.lc_respawn_at then
            transports[i] = mk_transport_like(t)
        end
    end
    for _, slot in ipairs(guard_slots) do
        local delivered = parts[slot.name] and parts[slot.name].delivered
        if not delivered then
            local t = book_transport[slot.name]
            for j, g in ipairs(slot.ships) do
                if g ~= "dead" and g:isValid() and t and t:isValid() and d2(g, t) > U(9) ^ 2 then
                    local x, y = t:getPosition()
                    g:orderFlyTowards(x, y)
                end
            end
            if slot.respawn_at and clock >= slot.respawn_at then
                slot.respawn_at = nil
                local x, y = 0, 0
                if t and t:isValid() then x, y = t:getPosition() end
                local g = CpuShip():setTemplate("Adder MK5"):setFaction("Kraylor")
                    :setPosition(x + random(-U(4), U(4)), y + random(-U(4), U(4))):orderDefendLocation(x, y)
                g.lc_slot = slot
                g:onDestruction(guard_died)
                table.insert(slot.ships, g)
                table.insert(groups.guards, g)
                print("LC: playbook guard respawned at " .. slot.name)
            end
        end
    end
end

function mk_transport_like(old)
    local route = { stations.lumina, stations.kajaani, stations.tampere, stations.turku, stations.lut }
    local st = route[math.random(1, #route)]
    local sx, sy = st:getPosition()
    local t = CpuShip():setTemplate("Atlantis"):setFaction("Independent")
        :setPosition(sx + random(-2000, 2000), sy + random(-2000, 2000)):setCallSign(old:getCallSign())
    t.lc_stopped = false
    t.lc_book = nil
    t.lc_next = nil
    t:setDescriptionForScanState("fullscan", "A civilian freighter. Cargo manifest: routine supplies.")
    t:setCommsFunction(commsTransport)
    t:onDestruction(transport_died)
    return t
end

function transport_died(obj, instigator)
    if obj.lc_book then
        local info = parts[obj.lc_book]
        if info and not info.given and not info.delivered then
            info.given = true
            mk_part(obj.lc_book, obj.lc_x or 0, obj.lc_y or 0)
            lc_notify("A freighter carrying an Ansible Playbook was destroyed - the playbook container spilled into space!")
        end
    end
    obj.lc_respawn_at = clock + 30
end

function guard_died(ship, instigator)
    local slot = ship.lc_slot
    if slot == nil or slot.respawns_left <= 0 then return end
    if parts[slot.name] and parts[slot.name].delivered then return end
    slot.respawns_left = slot.respawns_left - 1
    slot.respawn_at = clock + 60
end

-- ========================= phase 3 =========================
function spawn_wave()
    phase = 3
    local x, y = stations.lumina:getPosition()
    local np = math.max(1, #active_players())
    for i = 1, np do
        local ang = random(0, 628) / 100
        local wx, wy = x + math.cos(ang) * U(30), y + math.sin(ang) * U(30)
        for _, tmpl in ipairs({ "Starhammer II", "Piranha F12" }) do
            local s = CpuShip():setTemplate(tmpl):setFaction("Kraylor")
                :setPosition(wx + random(-2000, 2000), wy + random(-2000, 2000)):orderAttack(stations.lumina)
            table.insert(groups.wave, s)
        end
    end
    lc_notify("Kraylor fleet dropping out of warp around Lumina 1! All ships, engage!")
    print("LC: phase 3 wave spawned, count=" .. #groups.wave)
end

-- ========================= test hooks =========================
-- For headless testing via the console:  callscriptfunction probe_state  etc.
function probe_state()
    print("LC-STATE phase=" .. phase .. " done=" .. tostring(done) ..
        " tampere=" .. tampere_state .. " lut=" .. lut_state ..
        " p1=" .. part_delivered_count(PART_NAMES) .. "/6 books=" .. part_delivered_count(BOOK_NAMES) ..
        "/3 players=" .. #active_players() .. " transports=" .. #transports ..
        " ambush=" .. #groups.ambush .. " lutg=" .. #groups.lut .. " wave=" .. #groups.wave)
end

function probe_warp_sector(sector)
    local x, y = sector_center(tostring(sector))
    for _, p in ipairs(active_players()) do p:setPosition(x, y) end
    print("LC-PROBE players warped to " .. tostring(sector))
end

function probe_has_ftl()
    local missing = 0
    for _, p in ipairs(active_players()) do
        if p:isValid() and not p:hasWarpDrive() then missing = missing + 1 end
    end
    for _, t in ipairs(transports) do
        if t:isValid() and not t:hasWarpDrive() then missing = missing + 1 end
    end
    print("LC-PROBE ships missing warp drive: " .. missing)
    return missing == 0
end

function probe_kill_group(name)
    local g = groups[tostring(name)]
    if g == nil then
        print("LC-PROBE unknown group: " .. tostring(name))
        return
    end
    local n = 0
    for _, s in ipairs(g) do
        if s:isValid() then
            s:destroy()
            n = n + 1
        end
    end
    print("LC-PROBE killed " .. n .. " ships in " .. tostring(name))
end

function probe_deliver_all()
    for _, n in ipairs(PART_NAMES) do
        parts[n] = parts[n] or { carried = false, delivered = false }
        parts[n].delivered = true
    end
    if phase == 1 and part_delivered_count(PART_NAMES) >= #PART_NAMES then
        phase2_start()
    end
    print("LC-PROBE all parts delivered, phase=" .. phase)
end

function probe_deliver_books()
    for _, n in ipairs(BOOK_NAMES) do
        parts[n] = parts[n] or { carried = false, delivered = false }
        parts[n].delivered = true
    end
    if part_delivered_count(BOOK_NAMES) >= #BOOK_NAMES then
        phase3.armed = true
    end
    print("LC-PROBE books delivered, armed=" .. tostring(phase3.armed))
end

function probe_arm_wave()
    phase3.armed = true
    phase3.warned = true
    phase3.timer = 0
    print("LC-PROBE wave armed with timer 0")
end

function part_out_there(name)
    local info = parts[name]
    if info == nil then return false end
    if info.delivered or info.carried then return true end
    return info.obj ~= nil and info.obj:isValid()
end
