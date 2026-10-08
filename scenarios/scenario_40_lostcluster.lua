-- Name: Lost Cluster
-- Description: A stolen supercomputer cluster lies scattered across the sector. Recover every component, find the Ansible Playbooks, and defend Lumina 1.
--- The research cluster of Lumina 1 was looted and hauled to hidden facilities across the sector.
--- Phase 1: follow the hint chain (Kajaani 1 -> Tampere 1 / Turku 1 -> LUT 1) and recover all six
--- cluster components. Phase 2: ten civilian freighters shuttle between the stations - three of
--- them were handed an Ansible Playbook. Phase 3: the enemy is coming for Lumina 1.
-- Author: scenario-dev (implements scenarios/scenario_40_lostcluster.md)
-- Type: Mission
-- Setting[Difficulty]: Mission difficulty.
-- Difficulty[Normal|Default]: Standard balance.
-- Difficulty[Story]: Story mode: player beams one-shot anything they hit.

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
WARP_SPEED = 1000   -- 1000 is 60u/second

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

-- Story mode: player beams get one-shot damage. Applied by watch_player(),
-- which update() re-runs for late joiners and GM respawns, so every hull
-- that can fire is covered. Turrets/missiles keep normal damage (2024.12
-- exposes no per-turret damage API).
LC_DIFFICULTY = getScenarioSetting("Difficulty")
if LC_DIFFICULTY == nil or LC_DIFFICULTY == "" then LC_DIFFICULTY = "Normal" end
STORY_MODE = LC_DIFFICULTY == "Story"
STORY_BEAM_DAMAGE = 5000

function story_buff(p)
    local n = 0
    for i = 0, 15 do
        local ok, arc = pcall(p.getBeamWeaponArc, p, i)
        if ok and arc and arc > 0 then
            local _, dir = pcall(p.getBeamWeaponDirection, p, i)
            local _, rng = pcall(p.getBeamWeaponRange, p, i)
            local _, cyc = pcall(p.getBeamWeaponCycleTime, p, i)
            if pcall(p.setBeamWeapon, p, i, arc, dir, rng, cyc, STORY_BEAM_DAMAGE) then
                n = n + 1
            end
        end
    end
    print("LC: story buff on " .. (p:getCallSign() or "?") .. ": " .. n .. " beam(s) set to damage " .. STORY_BEAM_DAMAGE)
end

function all_dead(group)
    for _, s in ipairs(group) do
        if s:isValid() then return false end
    end
    return true
end

-- Fallback ship for comms registration wrappers on engines that pass no
-- source argument at all (there is no Player.get() in the 2024.12 API).
function lc_first_player()
    local ok, list = pcall(getActivePlayerShips)
    if ok and list and list[1] and list[1]:isValid() then return list[1] end
    return nil
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

-- Notifications are queued and delivered by update(): sendCommsMessage
-- returns false while a player is busy in a comms dialog, and those
-- messages used to be dropped silently. lc_notify(msg, from) also sends
-- station-voiced lines from the right station instead of always Lumina 1.
lc_msgq = {}

function lc_notify(msg, from)
    table.insert(lc_msgq, { msg = msg, from = from, until_s = clock + 25, done = {} })
end

function lc_pump_messages()
    if #lc_msgq == 0 then return end
    local players = active_players()
    for i = #lc_msgq, 1, -1 do
        local q = lc_msgq[i]
        local sender = q.from
        if sender == nil or not sender:isValid() then sender = stations.lumina end
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
        if not waiting or clock > q.until_s then table.remove(lc_msgq, i) end
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

-- Ambient world density knobs (see the ambient section). nebula_frac is
-- the fraction of the playable box covered by 5U nebula clouds; every
-- generator scales linearly from these numbers.
AMBIENT = {
    nebula_frac = 0.10,   -- ~120 nebulae over the ~90 000 u^2 station box
    nebula_max  = 260,    -- hard cap (0.20 frac would need ~255 clouds)
    belts       = 6,      -- asteroid-dust belts crossing the middle
    belt_dust   = 4,      -- VisualAsteroid gravel per belt node (decoration)
    belt_rocks  = 2,      -- real collidable Asteroids per belt node (hazard)
    mine_fields = 5,      -- derelict mine rings (6 mines each)
    wrecks      = 7,      -- derelict hulks, the first this many are mine-ringed
    wreck_mines = 2,
    traders     = 6,      -- extra Independent traffic (on top of init's shuttles)
    wormholes   = true,   -- one linked pair far from the station lanes
}
ambient_stats = { nebulae = 0, dust = 0, rocks = 0, mines = 0, wrecks = 0, traders = 0, wormholes = 0 }
ambient_mines = {}
ambient_box = {}
ambient_wh = {}        -- wormhole mouths: { obj=, partner=, dirx=, diry= } (autotest inspects)
lc_wh_transits = {}    -- recent transits: { obj=, t=clock }, for the re-entry guard

function part_delivered_count(names)
    local n = 0
    for _, name in ipairs(names) do
        if parts[name] and parts[name].delivered then n = n + 1 end
    end
    return n
end

-- ========================= cargo containers =========================
-- The engine does NOT progress Artifacts through the scan states (only
-- SpaceShips do; artifacts are "created as fully scanned"), so a reveal
-- keyed to one scan state can silently never surface in the UI. Instead,
-- every description starts out generic in ALL scan states, and update()
-- flips base + every scan state at once when a player comes within 5u -
-- whichever state the engine consults, the label then reads correctly.
containers = {}

function mk_container(desc, x, y)
    local a = Artifact():setModel("artifact6"):setPosition(x, y):setSpin(0.3)
    a:setDescription("An unmarked cargo container.")
    a:setDescriptionForScanState("notscanned", "An unmarked cargo container.")
    a:setDescriptionForScanState("simplescan", "A cargo container with a worn shipping label.")
    a:setDescriptionForScanState("fullscan", "A cargo container with a worn shipping label, too far away to read the printing.")
    local c = { a = a, name = nil, desc = desc, junk = false, revealed = false }
    table.insert(containers, c)
    return a, c
end

function lc_reveal_container(c)
    c.revealed = true
    if c.a:isValid() then
        c.a:setDescription(c.desc)
        c.a:setDescriptionForScanState("notscanned", c.desc)
        c.a:setDescriptionForScanState("simplescan", c.desc)
        c.a:setDescriptionForScanState("fullscan", c.desc)
    end
    print("LC: container revealed: " .. c.desc)
end

function lc_reveal_all()
    for _, c in ipairs(containers) do
        if not c.revealed then lc_reveal_container(c) end
    end
end

function mk_junk(x, y)
    local a, c = mk_container("Junk (spare parts).", x, y)
    a:allowPickup(false)
    c.junk = true
    c.revealed = true   -- decoys always tell the truth about themselves
    a:setDescription(c.desc)
    a:setDescriptionForScanState("notscanned", c.desc)
    a:setDescriptionForScanState("simplescan", c.desc)
    a:setDescriptionForScanState("fullscan", c.desc)
    a:setCommsFunction(function(comms_source, comms_target)
        math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
        setCommsMessage("Automated salvage tag: spare hull plating and scrap parts. Nothing worth recovering.")
        return true
    end)
    return a
end

function mk_part(name, x, y)
    parts[name] = parts[name] or { carried = false, delivered = false }
    local desc = "Cluster component: " .. name
    for _, b in ipairs(BOOK_NAMES) do
        if b == name then desc = name .. " - sealed Ansible research data core." end
    end
    local a, c = mk_container(desc, x, y)
    c.name = name
    parts[name].cont = c
    a:allowPickup(true)
    a:onPickUp(function(art, ship)
        math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
        if parts[name].obj == art and art:isValid() then art:destroy() end
        parts[name].carried = ship
        lc_notify("Cargo bay secured: " .. name)
    end)
    a:setCommsFunction(function(comms_source, comms_target)
        math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
        if c.revealed then
            setCommsMessage("Automated cargo container. Contents: " .. c.desc .. " Fly over the container to collect it.")
        else
            setCommsMessage("Automated cargo container, fleet property. Bring your ship close to read the shipping label, then fly over the container to collect it.")
        end
        return true
    end)
    parts[name].obj = a
    return a
end

-- Spawn point on a ring around a station, clear of its hull so that a
-- collision-based pickup is actually reachable.
function ring_pos(st, u)
    local ang = random(0, 6.283)
    local x, y = st:getPosition()
    return x + math.cos(ang) * U(u), y + math.sin(ang) * U(u)
end

-- ========================= ambient world =========================
-- Environmental density so the middle of the map is not empty vacuum:
-- nebula clouds, asteroid-dust belts, derelict minefields, hulk wreck
-- sites with debris and civilian traffic. All seeded in init() AFTER the
-- mission geometry, so keep-out rings around stations win. Nebulae are
-- engine-fixed 5U blobs that blind long-range radar; VisualAsteroid is
-- off-plane decoration (zero collision), Asteroid is the real hazard.

function ambient_init_box()
    local x0, y0, x1, y1
    for _, st in pairs(stations) do
        local x, y = st:getPosition()
        if x0 == nil or x < x0 then x0 = x end
        if x1 == nil or x > x1 then x1 = x end
        if y0 == nil or y < y0 then y0 = y end
        if y1 == nil or y > y1 then y1 = y end
    end
    ambient_box = { x0 = x0 - U(15), y0 = y0 - U(15), x1 = x1 + U(15), y1 = y1 + U(15) }
end

function ambient_clear(x, y, u)
    for _, st in pairs(stations) do
        local ox, oy = st:getPosition()
        local r = u + (st == stations.lumina and 3 or 0)   -- keep the home radar clean
        if (x - ox) ^ 2 + (y - oy) ^ 2 < U(r) ^ 2 then return false end
    end
    return true
end

function ambient_spot(u)
    for _ = 1, 30 do
        local x = random(ambient_box.x0, ambient_box.x1)
        local y = random(ambient_box.y0, ambient_box.y1)
        if ambient_clear(x, y, u) then return x, y end
    end
    return nil
end

function ambient_nebulas()
    local w = (ambient_box.x1 - ambient_box.x0) / 1000
    local h = (ambient_box.y1 - ambient_box.y0) / 1000
    local n = math.ceil(-math.log(1 - AMBIENT.nebula_frac) * w * h / (math.pi * 25))
    n = math.max(10, math.min(AMBIENT.nebula_max, n))
    local centers = {}
    for i = 1, math.max(4, math.floor(n / 4)) do
        local x, y = ambient_spot(8)
        if x then table.insert(centers, { x = x, y = y }) end
    end
    for i = 1, n do
        local x, y
        if #centers > 0 and math.random(100) <= 45 then
            local c = centers[math.random(#centers)]
            x, y = c.x + random(-U(4), U(4)), c.y + random(-U(4), U(4))
        else
            x, y = random(ambient_box.x0, ambient_box.x1), random(ambient_box.y0, ambient_box.y1)
        end
        if ambient_clear(x, y, 5) then
            Nebula():setPosition(x, y)
            ambient_stats.nebulae = ambient_stats.nebulae + 1
        end
    end
end

function ambient_belts()
    for b = 1, AMBIENT.belts do
        local px, py = ambient_spot(10)
        if px then
            local ang = random(0, 6.283)
            local dx, dy = math.cos(ang), math.sin(ang)
            local nx, ny = -dy, dx
            for i = 0, 44 do
                local bx = px + dx * U(2) * i + nx * math.sin(i * 0.3) * U(7)
                local by = py + dy * U(2) * i + ny * math.sin(i * 0.3) * U(7)
                if bx > ambient_box.x0 - U(20) and bx < ambient_box.x1 + U(20)
                    and by > ambient_box.y0 - U(20) and by < ambient_box.y1 + U(20) then
                    for k = 1, AMBIENT.belt_dust do
                        local vx, vy = bx + random(-U(4), U(4)), by + random(-U(4), U(4))
                        if ambient_clear(vx, vy, 5) then
                            VisualAsteroid():setSize(random(70, 240)):setPosition(vx, vy)
                            ambient_stats.dust = ambient_stats.dust + 1
                        end
                    end
                    for k = 1, AMBIENT.belt_rocks do
                        local vx, vy = bx + random(-U(2), U(2)), by + random(-U(2), U(2))
                        if ambient_clear(vx, vy, 5) then
                            Asteroid():setPosition(vx, vy)
                            ambient_stats.rocks = ambient_stats.rocks + 1
                        end
                    end
                end
            end
        end
    end
end

function ambient_wrecks()
    local hulks = { "Flavia", "Odin", "Stalker Q7", "Nirvana R5", "Atlantis X23" }
    for i = 1, AMBIENT.wrecks do
        local x, y = ambient_spot(6)
        if x then
            local s = CpuShip():setTemplate(hulks[math.random(#hulks)]):setFaction("Independent")
                :setPosition(x, y):setCallSign("Derelict " .. i)
            pcall(function() s:setHullMax(50); s:setHull(4) end)  -- battered hulk
            s:orderStandGround()
            ambient_stats.wrecks = ambient_stats.wrecks + 1
            for k = 1, 12 do   -- debris halo around the hulk
                local vx, vy = x + random(-U(3), U(3)), y + random(-U(3), U(3))
                VisualAsteroid():setSize(random(60, 220)):setPosition(vx, vy)
                ambient_stats.dust = ambient_stats.dust + 1
            end
            if i <= AMBIENT.wreck_mines then   -- salvage sites guarded by old mines
                for k = 1, 4 do
                    local a2 = random(0, 6.283)
                    local mx, my = x + math.cos(a2) * U(2.5), y + math.sin(a2) * U(2.5)
                    if ambient_clear(mx, my, 5) then
                        local m = Mine():setFaction("Independent"):setPosition(mx, my)
                        table.insert(ambient_mines, m)
                        ambient_stats.mines = ambient_stats.mines + 1
                    end
                end
            end
        end
    end
end

function ambient_mine_fields()
    for f = 1, AMBIENT.mine_fields do
        local x, y = ambient_spot(10)
        if x then
            for i = 1, 6 do
                local ang = (i - 1) * 1.047 + random(-0.2, 0.2)
                local r = U(2) + random(-U(1), U(1))
                local mx, my = x + math.cos(ang) * r, y + math.sin(ang) * r
                if ambient_clear(mx, my, 8) then
                    local m = Mine():setFaction("Independent"):setPosition(mx, my)
                    table.insert(ambient_mines, m)
                    ambient_stats.mines = ambient_stats.mines + 1
                end
            end
        end
    end
end

function ambient_traders()
    for i = 1, AMBIENT.traders do
        local x, y = ambient_spot(6)
        if x then
            CpuShip():setTemplate("Atlantis"):setFaction("Independent")
                :setPosition(x, y):setCallSign("Trader " .. i)
                :orderRoamingAt(random(ambient_box.x0, ambient_box.x1), random(ambient_box.y0, ambient_box.y1))
            ambient_stats.traders = ambient_stats.traders + 1
        end
    end
end

function ambient_wormholes()
    local ax, ay = ambient_spot(12)
    if ax == nil then return end
    local bx, by = ambient_box.x1 - (ax - ambient_box.x0), ambient_box.y1 - (ay - ambient_box.y0)
    if not ambient_clear(bx, by, 12) then return end
    local dx, dy = bx - ax, by - ay
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < U(10) then return end   -- need room for the offset exits (see below)
    -- Engine physics (wormHole.cpp 2024.12): a mouth drags every weighted
    -- object within 2.5U toward its center and teleports anything that gets
    -- within ~0.18U to target_position +/- 0.5U, with NO re-entry cooldown
    -- (upstream TODO: "escaping is impossible"). Targeting the partner
    -- mouth's CENTRE therefore perma-loops: you drop 0.5U inside its pull
    -- zone and are sucked straight back. So each exit sits 3.5U BEYOND the
    -- partner along the pair axis - outside the 2.5U pull radius (residual
    -- drift at the worst exit spread is ~35 m/s, easily outthrust).
    local ex, ey = bx + dx / dist * U(3.5), by + dy / dist * U(3.5)
    local fx, fy = ax - dx / dist * U(3.5), ay - dy / dist * U(3.5)
    if not ambient_clear(ex, ey, 8) or not ambient_clear(fx, fy, 8) then return end
    local a = WormHole():setPosition(ax, ay)
    local b = WormHole():setPosition(bx, by)
    a:setTargetPosition(ex, ey)
    b:setTargetPosition(fx, fy)
    ambient_wh = { { obj = a, partner = b, dirx = dx / dist, diry = dy / dist },
                   { obj = b, partner = a, dirx = -dx / dist, diry = -dy / dist } }
    for _, wh in ipairs(ambient_wh) do
        local w = wh
        w.obj:onTeleportation(function(this_wormhole, teleported_object)
            math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
            wh_transit(w, teleported_object)
        end)
    end
    ambient_stats.wormholes = 2
    print("LC: wormhole pair seeded, exits offset 3.5U beyond the far mouths")
end

-- Re-entry guard (belt & braces under the offset exits): the engine drops
-- the traveler at target +/- 500u and does not zero its velocity, so a ship
-- exiting straight INTO the far mouth at speed can fall back in. If the same
-- object transits twice within 15 s, override the drop to 2U further out.
function wh_transit(entry, obj)
    local e = nil
    for _, w in ipairs(lc_wh_transits) do
        if w.obj == obj then e = w break end
    end
    local again = e ~= nil and (clock - e.t) < 15
    if e then
        e.t = clock
    else
        if #lc_wh_transits > 64 then
            local fresh = {}
            for _, w in ipairs(lc_wh_transits) do
                if w.obj:isValid() and clock - w.t < 60 then table.insert(fresh, w) end
            end
            lc_wh_transits = fresh
        end
        table.insert(lc_wh_transits, { obj = obj, t = clock })
    end
    if again and obj:isValid() then
        local tx, ty = entry.obj:getTargetPosition()
        pcall(obj.setPosition, obj, tx + entry.dirx * U(2), ty + entry.diry * U(2))
        local okc, cs = pcall(function() return obj:getCallSign() end)
        print("LC: wormhole re-entry suppressed for " .. tostring(okc and cs or "an object"))
    end
end

function seed_ambient()
    ambient_init_box()
    ambient_nebulas()
    ambient_belts()
    ambient_wrecks()
    ambient_mine_fields()
    ambient_traders()
    if AMBIENT.wormholes then ambient_wormholes() end
    local total = 0
    for _, v in pairs(ambient_stats) do total = total + v end
    print("LC: ambient seeded nebulae=" .. ambient_stats.nebulae .. " dust=" .. ambient_stats.dust ..
        " rocks=" .. ambient_stats.rocks .. " mines=" .. ambient_stats.mines ..
        " wrecks=" .. ambient_stats.wrecks .. " traders=" .. ambient_stats.traders ..
        " wormholes=" .. ambient_stats.wormholes .. " total=" .. total)
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
contents only once you fly close enough to read the shipping label.]])
    -- Ambient environment (nebulas, dust belts, derelict mines, wrecks,
    -- traffic, a wormhole pair) everywhere the mission does not live.
    seed_ambient()

    print("LC: init complete, phase=" .. phase .. " difficulty=" .. LC_DIFFICULTY)
end

function mk_station(name, tmpl, fac, x, y, fn)
    local s = SpaceStation():setTemplate(tmpl):setFaction(fac):setPosition(x, y)
    s:setCallSign(name)
    if fn then
        local st = s
        -- Bind the target via closure: comms *functions* are documented to
        -- receive only comms_source, so never rely on the comms_target global.
        st:setCommsFunction(function(src)
            math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
            return fn(st, src or comms_source or lc_first_player())
        end)
    end
    return s
end

-- Hook a player ship: cargo eject on death + a comms handler so other
-- player ships can hail it for part transfers (design doc: "We would like
-- to transfer [object] to you"). update() re-runs this for late joiners
-- and GM-spawned replacements, which otherwise would silently keep (or
-- lose) mission cargo.
function watch_player(p)
    p.lc_watched = true
    if STORY_MODE then
        story_buff(p)
    end
    p:onDestruction(function(ship, instigator)
        local dropped = false
        for name, info in pairs(parts) do
            if info.carried == ship and not info.delivered then
                info.carried = false
                mk_part(name, ship.lc_x or 0, ship.lc_y or 0)
                dropped = true
            end
        end
        if dropped then
            lc_notify("Lost contact with a ship! Its cargo was ejected as containers at the wreck. The GM can spawn a replacement ship.")
        else
            lc_notify("Lost contact with a ship. The GM can spawn a replacement ship.")
        end
    end)
    local ok, err = pcall(function()
        p:setCommsFunction(function(src)
            return commsPlayerShip(p, src or comms_source)
        end)
    end)
    if not ok then print("LC: player ship comms unavailable: " .. tostring(err)) end
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
    local b300 = parts["B300 GPU nodes"]
    if b300 and not b300.delivered and not b300.carried then
        if part_out_there("B300 GPU nodes") then
            s = s .. "\nThe B300 container is adrift in sector C10, where the Kraylor patrol went down."
        else
            s = s .. "\nB300 GPU nodes: hijacked by a Kraylor patrol - Tampere 1 tracked them into sector C10."
        end
    end
    return s
end

function carrying_any(ship)
    if ship == nil then return false end
    for _, info in pairs(parts) do
        if info.carried == ship and not info.delivered then return true end
    end
    return false
end

-- Reply effects live in act_* functions: no comms globals in there, so the
-- autotest driver can invoke the exact same logic headless.

function act_deliver(station, ship)
    return deliver_to_lumina(ship)
end

function act_collect_tampere(t)
    local info = parts["H200 GPU nodes"]
    if info and info.carried and not info.delivered then
        return "That container is already loaded aboard a recovery ship - deliver it to Lumina 1."
    end
    if not part_out_there("H200 GPU nodes") then
        local x, y = ring_pos(t, 5)
        mk_part("H200 GPU nodes", x, y)
        return "We float a container out to you - it is just outside the station."
    end
    return "The container is already out there - check your sensors."
end

function act_collect_lut(t)
    local info = parts["AMD compute nodes"]
    if info and info.carried and not info.delivered then
        return "That container is already loaded aboard a recovery ship - deliver it to Lumina 1."
    end
    if not part_out_there("AMD compute nodes") then
        local x, y = ring_pos(t, 5)
        mk_part("AMD compute nodes", x, y)
        return "Container is away, just outside the station."
    end
    return "It is already outside - check short-range sensors."
end

function act_stop_transport(t)
    t:orderIdle()
    t.lc_stopped = true
    return "Fine, we are stopping. Pull alongside, stop, and hail us to initiate the transfer."
end

function act_transfer_book(t, ship)
    if ship and d2(ship, t) < U(3) ^ 2 then
        parts[t.lc_book].given = true
        local x, y = t:getPosition()
        mk_part(t.lc_book, x + 1500, y + 1500)
        return "Transferring the playbook container into your cargo bay area. Away it goes.", true
    end
    return "Too far - get within 3 units of the hull and hail again.", false
end

-- Ship-to-ship transfer of a carried part (player ship hails the ship
-- holding it). act_* so the autotest drives the exact comms-reply logic.
function act_transfer_part(target, receiver, name)
    local info = parts[name]
    if info == nil or info.delivered then return "We are not carrying the " .. name .. "." end
    if info.carried ~= target then return "We do not have the " .. name .. " aboard." end
    if receiver == nil or receiver == target then return "We cannot transfer it to the same ship." end
    if d2(target, receiver) > U(3) ^ 2 then
        return "Too far - pull alongside us (within 3u), stop, and hail again."
    end
    info.carried = receiver
    lc_notify("Ship-to-ship transfer of the " .. name .. " complete. Deliver it to Lumina 1.")
    return "Transfer complete - we have handed over the " .. name .. ". Fly it to Lumina 1 to turn it in."
end

-- Comms handler installed on every player ship by watch_player().
--
-- Engine comms semantics (commsScriptInterface.cpp): clicking a reply clears
-- ALL replies, then runs the callback, and inside a callback every
-- setCommsMessage REPLACES the displayed text. So a reply callback must
-- render exactly ONE message: re-rendering a whole menu page after the
-- result text wipes the result and the click looks like a no-op. Hence the
-- split of every dialog into a page function (sets the text) and a
-- *_replies function (only adds choices): result pages call
-- setCommsMessage(result) + *_replies, never the page function.
function commsPlayerShip_offered(t, src)
    local offered = {}
    if src ~= t then
        for _, list in ipairs({ PART_NAMES, BOOK_NAMES }) do
            for _, n in ipairs(list) do
                local info = parts[n]
                if info and info.carried == t and not info.delivered then
                    table.insert(offered, n)
                end
            end
        end
    end
    return offered
end

function commsPlayerShip(t, src)
    local offered = commsPlayerShip_offered(t, src)
    if #offered == 0 then
        setCommsMessage("Ship " .. t:getCallSign() .. " here. Nothing to transfer from us.")
        return true
    end
    setCommsMessage("Ship " .. t:getCallSign() .. " here. We are carrying: " .. table.concat(offered, ", ") ..
        ". Pull alongside (within 3u), stop, and we can transfer it to you.")
    commsPlayerShip_replies(t, src)
    return true
end

function commsPlayerShip_replies(t, src)
    for _, n in ipairs(commsPlayerShip_offered(t, src)) do
        addCommsReply("We would like to transfer the " .. n .. " to us.", function(comms_source, comms_target)
            math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
            local who = comms_source or src
            setCommsMessage(act_transfer_part(t, who, n))
            commsPlayerShip_replies(t, who)   -- keep the result visible, re-offer remaining cargo
            return true
        end)
    end
end

function commsLumina(t, src)
    setCommsMessage("Lumina 1 here.\n" .. lc_status())
    commsLumina_replies(t, src)
    return true
end

function commsLumina_replies(t, src)
    addCommsReply("What is the mission status?", function(comms_source, comms_target)
        math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
        setCommsMessage(lc_status())
        commsLumina_replies(t, comms_source or src)
        return true
    end)
    addCommsReply("Who might have the cluster hardware?", function(comms_source, comms_target)
        math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
        setCommsMessage(lc_who_has())
        commsLumina_replies(t, comms_source or src)
        return true
    end)
    if carrying_any(src) then
        addCommsReply("Hand over the recovered equipment.", function(comms_source, comms_target)
            math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
            local who = comms_source or src
            setCommsMessage(act_deliver(t, who))
            commsLumina_replies(t, who)
            return true
        end)
    end
end

function commsKajaani(t, src)
    setCommsMessage([[Kajaani 1. Our stores were looted - the whole supercomputer shipment is gone.
We were supposed to ship the first batch to Lumina 1. Whoever did this also hit Tampere 1 and Turku 1;
those two went dark with their stations, moving out of long-range radar.]])
    commsKajaani_replies(t, src)
    return true
end

function commsKajaani_replies(t, src)
    addCommsReply("Where are Tampere 1 and Turku 1?", function(comms_source, comms_target)
        math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
        known.tampere = true
        known.turku = true
        setCommsMessage([[ Tampere 1 last pinged near sector ]] .. hint_sector(stations.tampere) ..
            [[ and Turku 1 near sector ]] .. hint_sector(stations.turku) ..
            [[. The reply beacon drifts, so they can be up to 50u from those sector squares.
If you find out anything about LUT 1, they were moving AMD nodes - but that is all we know.]])
        commsKajaani_replies(t, comms_source or src)   -- replies only: the intel stays visible
        return true
    end)
    addCommsReply("We will look around.", function(comms_source, comms_target)
        math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
        setCommsMessage("Good luck out there.")
        return true
    end)
end

function commsTampere(t, src)
    if tampere_state == "ambush" then
        setCommsMessage([[Tampere 1: we are under attack! Clear those ships from around us before we can talk.]])
        return true
    end
    setCommsMessage([[Tampere 1 here. We still have the H200 GPU nodes, hidden in the nebula around us.
The B300 GPU nodes were taken by Kraylor ships - our trackers say they headed for sector C10.]])
    commsTampere_replies(t, src)
    return true
end

function commsTampere_replies(t, src)
    if tampere_state == "ambush" then return end
    addCommsReply("Collect the H200 GPU nodes.", function(comms_source, comms_target)
        math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
        setCommsMessage(act_collect_tampere(t))
        commsTampere_replies(t, comms_source or src)   -- replies only: the result stays visible
        return true
    end)
    addCommsReply("What about LUT 1?", function(comms_source, comms_target)
        math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
        local near = false
        for _, p in ipairs(active_players()) do
            if d2(p, t) < U(10) ^ 2 then near = true break end
        end
        if near then
            known.lut = true
            setCommsMessage([[Fine - you have earned it. LUT 1 sits near sector ]] .. hint_sector(stations.lut) ..
                [[ with our AMD compute nodes. But something is wrong there: their last transmissions were... wrong. Attack anything Kraylor-painted nearby, and do not go in alone.]])
        else
            setCommsMessage("That information is confidential. Approach within 10 units of us and we will talk.")
        end
        commsTampere_replies(t, comms_source or src)   -- replies only: the answer stays visible
        return true
    end)
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

function commsTurku(t, src)
    setCommsMessage([[Turku 1. We were attacked, so we hid the Intel compute nodes and the Lustre
fileserver in cargo containers across seven nebulas around us - our courier ship made it that far before
it was shot down. The containers only say what is inside once you are right next to them; the Kraylor
left junk decoys behind. LUT 1 has the AMD nodes, if they are still ours to ask.]])
    commsTurku_replies(t, src)
    return true
end

function commsTurku_replies(t, src)
    addCommsReply("Anything else?", function(comms_source, comms_target)
        math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
        setCommsMessage("The nebula shadows hide things at long range. Fly into each one and sweep with short-range sensors.")
        commsTurku_replies(t, comms_source or src)   -- replies only: the tip stays visible
        return true
    end)
end

function commsLUT(t, src)
    if lut_state == "hostile" then
        setCommsMessage([[Alone you are weak and we will be victorious! Come back with more people, or stay away.]])
        return true
    end
    if lut_state == "friendly" then
        setCommsMessage([[LUT 1, operations. The AMD compute node shipment is still in our bay. Is there a problem?]])
    else
        setCommsMessage([[LUT 1 is back under our control - and that was no accident; they were already inside
when we opened the doors. The AMD compute nodes are aboard; we are floating the container out to you.]])
    end
    commsLUT_replies(t, src)
    return true
end

function commsLUT_replies(t, src)
    if lut_state == "hostile" then return end
    if lut_state == "friendly" then
        addCommsReply("We will check the perimeter.", function(comms_source, comms_target)
            math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
            setCommsMessage("Understood. Sensors show Kraylor signatures on the station - be careful.")
            return true
        end)
        return
    end
    addCommsReply("Collect the AMD compute nodes.", function(comms_source, comms_target)
        math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
        setCommsMessage(act_collect_lut(t))
        commsLUT_replies(t, comms_source or src)   -- replies only: the result stays visible
        return true
    end)
end

function commsTransport(t, src)
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
    else
        setCommsMessage("Freighter " .. t:getCallSign() .. " is stopped. We were told to hand over one Ansible Playbook to whoever came looking.")
    end
    commsTransport_replies(t, src)
    return true
end

function commsTransport_replies(t, src)
    if t.lc_book == nil then return end
    if parts[t.lc_book] and parts[t.lc_book].given then return end
    if not t.lc_stopped then
        addCommsReply("Please stop for a data transfer.", function(comms_source, comms_target)
            math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
            setCommsMessage(act_stop_transport(t))
            commsTransport_replies(t, comms_source or src)   -- offers the transfer straight away
            return true
        end)
    else
        addCommsReply("Please transfer the Ansible Playbook to us.", function(comms_source, comms_target)
            math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
            local who = comms_source or src
            local msg, ok = act_transfer_book(t, who)
            setCommsMessage(msg)
            commsTransport_replies(t, who)   -- refused: re-offers; accepted: page ends
            return true
        end)
    end
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
    lc_pump_messages()

    -- Late joiners and GM respawns: cargo-eject hook + transfer comms on
    -- every player ship we have not seen before (watch_player marks them).
    for _, p in ipairs(players) do
        if p:isValid() and not p.lc_watched then watch_player(p) end
    end

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

    -- Cargo containers reveal their shipping labels at close range: the
    -- engine never advances an Artifact's scan state, so we flip every
    -- description (base + all scan states) once a player is within 5u.
    for _, c in ipairs(containers) do
        if not c.revealed and c.a:isValid() then
            for _, p in ipairs(players) do
                if d2(p, c.a) < U(5) ^ 2 then
                    lc_reveal_container(c)
                    break
                end
            end
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
            lc_notify("Tampere 1: the ships around us are gone. The area is clear - hail us.", stations.tampere)
        end
    end

    -- Turku 1 greets arriving ships.
    if not turku_greeted then
        for _, p in ipairs(players) do
            if d2(p, stations.turku) < U(20) ^ 2 then
                lc_notify([[Turku 1 here! We hid the Intel compute nodes and the
Lustre server in cargo containers across seven nebulas around us. Fly close to every
container to read the labels - the Kraylor scattered junk decoys among them.]], stations.turku)
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
                -- The "come back with more" taunt only makes sense when
                -- there ARE more ships to come back with: in a one-ship
                -- game it is pure noise, so it only fires for split groups.
                if with <= 1 and #players >= 2 then
                    taunt_armed[p] = false
                    stations.lut:sendCommsMessage(p, [[Alone you are weak and we will be victorious!
Come back with more people, or stay away.]])
                end
            end
        end
        if all_dead(groups.lut) then
            lut_state = "liberated"
            stations.lut:setFaction("Human Navy")
            lc_notify("LUT 1 is back under Human Navy control. The AMD compute nodes are aboard - hail the station.", stations.lut)
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
    lc_notify("Unidentified ships warping in around Tampere 1!", stations.tampere)
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
        t.lc_sign = "Freighter " .. i   -- remembered while alive: getCallSign on a
                                        -- destroyed hull returns nothing (mk_transport_like)
        t:setDescriptionForScanState("fullscan", "A civilian freighter. Cargo manifest: routine supplies.")
        local tr = t
        tr:setCommsFunction(function(src)
            return commsTransport(tr, src or comms_source or lc_first_player())
        end)
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
    -- getCallSign on a destroyed hull yields nothing, so pass it no nil
    -- default and never crash update(): prefer the remembered sign.
    local sign = old.lc_sign
    if sign == nil or sign == "" then sign = old:getCallSign() end
    if sign == nil or sign == "" then sign = "Freighter ?" end
    local t = CpuShip():setTemplate("Atlantis"):setFaction("Independent")
        :setPosition(sx + random(-2000, 2000), sy + random(-2000, 2000)):setCallSign(sign)
    t.lc_stopped = false
    t.lc_book = nil
    t.lc_next = nil
    t.lc_sign = sign
    t:setDescriptionForScanState("fullscan", "A civilian freighter. Cargo manifest: routine supplies.")
    local tr = t
    tr:setCommsFunction(function(src)
        return commsTransport(tr, src or comms_source or lc_first_player())
    end)
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

function probe_warp_to(x, y)
    for _, p in ipairs(active_players()) do p:setPosition(x, y) end
    print("LC-PROBE players warped to " .. tostring(x) .. "," .. tostring(y))
end

function probe_containers()
    for _, c in ipairs(containers) do
        print("LC-CONT name=" .. tostring(c.name or c.desc) ..
            " revealed=" .. tostring(c.revealed) ..
            " valid=" .. tostring(c.a:isValid()))
    end
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

-- NOTE: the engine only fires onDestruction hooks on damage kills
-- (takeHullDamage), never on a script destroy() - so probe_kill_group is
-- safe only for polling-based groups (ambush, lut, wave). Destruction-hook
-- groups (b300, transports, guards) are killed organically by the autotest.
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

function probe_watch()
    local n, w = 0, 0
    for _, p in ipairs(active_players()) do
        n = n + 1
        if p.lc_watched then w = w + 1 end
    end
    print("LC-PROBE players watched: " .. w .. "/" .. n)
    return n > 0 and w == n
end

-- Ship-to-ship transfer exercise: part "carried" by player0, receiver is
-- a throwaway ship at `dist` units. State is restored before returning.
function probe_transfer(name, dist)
    local info = parts[tostring(name)]
    if info == nil then print("LC-PROBE no such part: " .. tostring(name)) return false end
    local p = active_players()[1]
    if p == nil then print("LC-PROBE no player ship") return false end
    local save_c, save_d = info.carried, info.delivered
    info.delivered = false
    info.carried = p
    local r = CpuShip():setTemplate("Atlantis"):setFaction("Human Navy")
    local x, y = p:getPosition()
    r:setPosition(x + (dist or 0), y)
    local msg = act_transfer_part(p, r, tostring(name))
    local accepted = info.carried == r
    r:destroy()
    info.carried, info.delivered = save_c, save_d
    print("LC-PROBE transfer dist=" .. tostring(dist) .. " accepted=" .. tostring(accepted) .. " msg=" .. msg)
    return accepted
end

function part_out_there(name)
    local info = parts[name]
    if info == nil then return false end
    if info.delivered or info.carried then return true end
    return info.obj ~= nil and info.obj:isValid()
end
