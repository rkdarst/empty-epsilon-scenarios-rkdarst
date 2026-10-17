-- Name: Lost Cluster
-- Description: A stolen supercomputer cluster lies scattered across the sector. Recover every component, find the Ansible Playbooks, and defend Lumina 1.
--- The research cluster of Lumina 1 was looted and hauled to hidden facilities across the sector.
--- Phase 1: follow the hint chain (Kajaani 1 -> Tampere 1 / Turku 1 -> LUT 1) and recover all six
--- cluster components. Phase 2: ten civilian freighters shuttle between the stations - three of
--- them were handed an Ansible Playbook. Phase 3: the enemy is coming for Lumina 1.
-- Author: scenario-dev (implements scenarios/scenario_40_lostcluster.AGENTS-brief.txt)
-- Type: Mission
-- Setting[Difficulty]: Mission difficulty.
-- Difficulty[Normal|Default]: Standard balance.
-- Difficulty[Story]: Story mode: player beams one-shot anything they hit.
-- Setting[GMMenu]: Show the gamemaster console controls (see the GM section).
-- GMMenu[Enabled|Default]: GM console gets the mission-control buttons.
-- GMMenu[Disabled]: no GM buttons are added; lc_gm_* functions still work.

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

-- ========================= mission tuning knobs =========================
-- Distances are in in-game units (U() converts to script units).
LC_FIND_U = 6        -- a hidden station stops hiding at this range. The player
                     -- short-range radar is 5U and nebulae only blind the
                     -- LONG-range radar, so ~6u is where the station shows up
                     -- anyway. (Was 40u, which flagged stations as "found"
                     -- while they were still supposed to be lost.)
LC_HANDOVER_U = 1    -- how close to Lumina 1 you must be to hand hardware over
                     -- (docking always counts, whatever the distance).
LC_REVEAL_U = 5      -- cargo-container shipping labels become readable here.
TURKU_NEB = 10       -- nebulas hiding Turku 1's caches (was 7)
TURKU_R_MIN, TURKU_R_MAX = 10, 18  -- ring they are scattered on. A nebula has
                                  -- a 5U radius (notes/06), so this spacing
                                  -- (~9u apart) keeps the clouds distinguish-
                                  -- able, and the whole search stays at most
                                  -- one sector away; the old +-25u square put
                                  -- caches up to 35u out, 1-2 sectors off-map
TURKU_JUNK = 6       -- decoys inside the spare nebulas (+ 2 loose ones)
TURKU_LOOSE_JUNK = 2
TURKU_LOOSE_SPREAD_U = 12          -- how far the loose decoys wander

-- Station hull radii in script units per in-game unit, taken from
-- scripts/model_data.lua (space_station_4: radius 300; space_station_3: radius
-- 1000; U(1) == 1000 script units). Containers are ejected just clear of the
-- hull and always inside the hand-over bubble, so a crate is never dropped
-- somewhere the player cannot reach from the hand-over position.
STATION_HULL_U = { ["Small Station"] = 0.3, ["Medium Station"] = 1.0, ["Large Station"] = 1.3 }

function station_hull_u(st)
    return STATION_HULL_U[st.lc_template] or 0.3
end

-- How close a ship must be to trade with a station: "next to the hull", which
-- for a Small station is the flat LC_HANDOVER_U and for bigger hulls grows with
-- their radius (docking always satisfies it regardless).
function handover_u(st)
    local r = station_hull_u(st) + 0.4
    if r < LC_HANDOVER_U then r = LC_HANDOVER_U end
    return r
end

-- Distance test for the "come closer" gates: docking always satisfies it.
function near_or_docked(a, b, u)
    if a == nil or b == nil then return false end
    local docked = false
    pcall(function() docked = a:isDocked(b) end)
    if docked then return true end
    return d2(a, b) < U(u) ^ 2
end

-- Read a per-object script field off an object that may already be gone
-- (custom fields die with the object; notes/04).
function obj_field(obj, key, default)
    local ok, v = pcall(function() return obj[key] end)
    if ok and v ~= nil then return v end
    return default
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
    if p.lc_save ~= nil then return end   -- already buffed; watch_player calls this per tick
    local save, n = {}, 0
    for i = 0, 15 do
        local ok, arc = pcall(p.getBeamWeaponArc, p, i)
        if ok and arc and arc > 0 then
            local _, dir = pcall(p.getBeamWeaponDirection, p, i)
            local _, rng = pcall(p.getBeamWeaponRange, p, i)
            local _, cyc = pcall(p.getBeamWeaponCycleTime, p, i)
            local _, dmg = pcall(p.getBeamWeaponDamage, p, i)
            save[i] = { arc = arc, dir = dir, rng = rng, cyc = cyc, dmg = dmg }
            if pcall(p.setBeamWeapon, p, i, arc, dir, rng, cyc, STORY_BEAM_DAMAGE) then
                n = n + 1
            end
        end
    end
    -- Remember what we overwrote: the difficulty toggle has to be reversible
    -- mid-mission and setBeamWeapon is absolute, so buffing again without
    -- restoring first would only ever ratchet.
    if n > 0 then p.lc_save = save end
    print("LC: story buff on " .. (p:getCallSign() or "?") .. ": " .. n .. " beam(s) set to damage " .. STORY_BEAM_DAMAGE)
end

-- Undo story_buff from the snapshot taken above (lc_gm_difficulty / story mode
-- toggle). Returns false for a ship that was never buffed.
function story_off(p)
    local save = p.lc_save
    if save == nil then return false end
    local n = 0
    for i, b in pairs(save) do
        if pcall(p.setBeamWeapon, p, i, b.arc, b.dir, b.rng, b.cyc, b.dmg) then
            n = n + 1
        end
    end
    p.lc_save = nil
    print("LC: story buff removed from " .. (p:getCallSign() or "?") .. ": " .. n .. " beam(s) restored")
    return true
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
-- Cargo = physical Artifact()s; the scenario keeps the carry/deliver
-- bookkeeping. Labels are a small state machine (see lc_container_text).
containers = {}
CONTAINER_FAR = "An unmarked cargo container."
JUNK_DESC = "Junk (spare parts)."
JUNK_FAR = "Junk (unchecked)."

-- The engine never advances an Artifact through the scan states (only
-- SpaceShips do; artifacts are "created as fully scanned"), so the text for
-- the current *story* state has to be written into base + all three states at
-- once; whichever state the UI consults, it reads the same thing. update()
-- flips them together when a player comes within LC_REVEAL_U.
function lc_container_text(a, text)
    a:setDescription(text)
    a:setDescriptionForScanState("notscanned", text)
    a:setDescriptionForScanState("simplescan", text)
    a:setDescriptionForScanState("fullscan", text)
end

-- far = what the label reads until someone flies close enough to scan it.
function mk_container(desc, x, y, far)
    local a = Artifact():setModel("artifact6"):setPosition(x, y):setSpin(0.3)
    lc_container_text(a, far or CONTAINER_FAR)
    local c = { a = a, name = nil, desc = desc, far = far or CONTAINER_FAR,
                junk = false, revealed = false }
    table.insert(containers, c)
    return a, c
end

function lc_reveal_container(c)
    c.revealed = true
    if c.a:isValid() then lc_container_text(c.a, c.desc) end
    print("LC: container revealed: " .. c.desc)
end

function lc_reveal_all()
    for _, c in ipairs(containers) do
        if not c.revealed then lc_reveal_container(c) end
    end
end

function mk_junk(x, y)
    local a, c = mk_container(JUNK_DESC, x, y, JUNK_FAR)
    a:allowPickup(false)
    c.junk = true
    a:setCommsFunction(function(comms_source, comms_target)
        math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
        if c.revealed then
            setCommsMessage("Automated salvage tag: spare hull plating and scrap parts. Nothing worth recovering.")
        else
            setCommsMessage("Automated salvage tag, corroded beyond reading at this range. Fly close enough to scan it.")
        end
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
    -- Remember where it was dumped: the hint chain can then name the sector
    -- instead of leaving a crate that died far off-route unrecoverable.
    parts[name].drop_x, parts[name].drop_y = x, y
    parts[name].drop_sector = getSectorName(x, y)
    return a
end

-- Spawn point on a ring around a station, clear of its hull so that a
-- collision-based pickup is actually reachable.
function ring_pos(st, u)
    local ang = random(0, 6.283)
    local x, y = st:getPosition()
    return x + math.cos(ang) * U(u), y + math.sin(ang) * U(u)
end

-- Where a station ejects a container: just clear of its hull and always inside
-- that station's hand-over bubble (0.65u for a Small, 1.35u for a Medium).
function eject_pos(st)
    local r = station_hull_u(st) + 0.35
    if r >= handover_u(st) then r = handover_u(st) - 0.05 end
    return ring_pos(st, r)
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
    -- Pick the pair by rejection sampling: both mouths AND both offset exits
    -- must sit clear of the station keep-out rings. One shot at a single
    -- ambient_spot() made this a coin flip per run (the autotest then sees an
    -- "ambient wormhole pair" that was never seeded); sampling until one fits
    -- is pure arithmetic, so 200 attempts are free at init.
    local ax, ay, bx, by, dx, dy, dist
    for _ = 1, 200 do
        local sx, sy = random(ambient_box.x0, ambient_box.x1), random(ambient_box.y0, ambient_box.y1)
        local mx = ambient_box.x1 - (sx - ambient_box.x0)
        local my = ambient_box.y1 - (sy - ambient_box.y0)
        local ddx, ddy = mx - sx, my - sy
        local dd = math.sqrt(ddx * ddx + ddy * ddy)
        if dd >= U(10) and ambient_clear(sx, sy, 12) and ambient_clear(mx, my, 12)
           and ambient_clear(mx + ddx / dd * U(3.5), my + ddy / dd * U(3.5), 8)
           and ambient_clear(sx - ddx / dd * U(3.5), sy - ddy / dd * U(3.5), 8) then
            ax, ay, bx, by = sx, sy, mx, my
            dx, dy, dist = ddx, ddy, dd
            break
        end
    end
    if ax == nil then return end
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
    -- Hidden stations sit inside a nebula AND start out neutral: a Human Navy
    -- station is a friendly contact whose short-range telemetry is shared with
    -- the player on Relay/Strategic Map, which is exactly what gives a "hidden"
    -- station away. Independent = no friendly contact, no telemetry share, and
    -- the Kraylor (at war only with the Human Navy) leave it alone.
    local tx, ty = sector_center("H5")
    Nebula():setPosition(tx, ty)
    stations.tampere = mk_station("Tampere 1", "Small Station", "Human Navy", tx, ty, commsTampere)
    hide_station(stations.tampere, "Human Navy")
    local ux, uy = sector_center("B2")
    Nebula():setPosition(ux, uy)
    stations.turku = mk_station("Turku 1", "Small Station", "Human Navy", ux, uy, commsTurku)
    hide_station(stations.turku, "Human Navy")
    local lx3, ly3 = sector_center("L3")
    Nebula():setPosition(lx3, ly3)
    stations.lut = mk_station("LUT 1", "Small Station", "Human Navy", lx3, ly3, commsLUT)
    -- LUT 1 keeps its own reveal scene (neutral -> Kraylor -> Human Navy), so
    -- it gets no reveal faction here.
    hide_station(stations.lut, nil)

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
    -- Safety net: if a hull dies without firing onDestruction (script destroy,
    -- GM removal), the patrol's cargo must still reach the players.
    mk_drop_watch("B300 GPU nodes", groups.b300, function(x, y) drop_b300(x, y) end)

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

    -- Gamemaster console (no-op when Setting[GMMenu] is Disabled; the lc_gm_*
    -- functions work either way). pcall: a missing GM API must not break a mission.
    pcall(lc_gm_boot)

    print("LC: init complete, phase=" .. phase .. " difficulty=" .. LC_DIFFICULTY)
end

function mk_station(name, tmpl, fac, x, y, fn)
    local s = SpaceStation():setTemplate(tmpl):setFaction(fac):setPosition(x, y)
    s:setCallSign(name)
    s.lc_template = tmpl     -- hull radius lookups (STATION_HULL_U)
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

-- Park a Human Navy station out of sight: neutral faction (no friendly contact,
-- no relay telemetry bubble) and a zeroed short-range radar range while dark.
-- reveal_to = faction it adopts once found, or nil when a scripted scene owns
-- the station's faction (LUT 1).
function hide_station(st, reveal_to)
    st.lc_hidden = true
    st.lc_reveal_to = reveal_to
    st:setFaction("Independent")
    pcall(st.setShortRangeRadarRange, st, 0)
    return st
end

-- One-way, idempotent: a player flew close enough to have seen it anyway.
function station_reveal(name)
    local st = stations[name]
    if st == nil or not st:isValid() then return end
    if found[name] then return end
    found[name] = true
    if st.lc_hidden and not st.lc_revealed then
        st.lc_revealed = true
        if st.lc_reveal_to then st:setFaction(st.lc_reveal_to) end
        pcall(st.setShortRangeRadarRange, st, 5000)   -- engine default
    end
    print("LC: station " .. name .. " found")
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
    -- A ring of nebulas around the station: TURKU_NEB clouds at
    -- TURKU_R_MIN..TURKU_R_MAX units, evenly spaced in bearing with jitter, so
    -- the search is a sweep of the neighbourhood instead of a scavenger hunt
    -- across two sectors.
    local nebs = {}
    local step = 6.283 / TURKU_NEB
    for i = 1, TURKU_NEB do
        local ang = (i - 1) * step + math.rad(random(-10, 10))
        local r = U(random(TURKU_R_MIN * 100, TURKU_R_MAX * 100) / 100)
        local nx, ny = ux + math.cos(ang) * r, uy + math.sin(ang) * r
        Nebula():setPosition(nx, ny)
        table.insert(nebs, { x = nx, y = ny })
    end
    turku_nebs = nebs     -- for the functional test (ring geometry)
    local a = math.random(1, TURKU_NEB)
    local b = math.random(1, TURKU_NEB)
    while b == a do b = math.random(1, TURKU_NEB) end
    mk_part("Intel compute nodes", nebs[a].x + random(-2000, 2000), nebs[a].y + random(-2000, 2000))
    mk_part("Lustre fileserver", nebs[b].x + random(-2000, 2000), nebs[b].y + random(-2000, 2000))
    local placed = 0
    for i = 1, TURKU_NEB do
        if i ~= a and i ~= b and placed < TURKU_JUNK then
            placed = placed + 1
            mk_junk(nebs[i].x + random(-2000, 2000), nebs[i].y + random(-2000, 2000))
        end
    end
    for i = 1, TURKU_LOOSE_JUNK do
        mk_junk(ux + random(-U(TURKU_LOOSE_SPREAD_U), U(TURKU_LOOSE_SPREAD_U)),
                uy + random(-U(TURKU_LOOSE_SPREAD_U), U(TURKU_LOOSE_SPREAD_U)))
    end
    return nebs
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
            s = s .. "\nThe B300 container is adrift in sector " .. (b300.drop_sector or "C10") ..
                ", where the Kraylor patrol went down."
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
    if ship == nil then return "We cannot read a cargo manifest off an empty comms channel." end
    if not near_or_docked(ship, station, handover_u(station)) then
        return "Too far to transfer anything - come alongside us (within " ..
            string.format("%.1f", handover_u(station)) .. " units) or dock, and we can take it off you."
    end
    return deliver_to_lumina(ship)
end

-- Stations that are ours can top up homing missiles, free of charge. Nothing
-- else: no other weapon, no hull, no reputation business.
function act_replenish(station, ship)
    if ship == nil then return "We cannot service a ship we cannot see." end
    if not near_or_docked(ship, station, handover_u(station)) then
        return "Pull alongside us (within " .. string.format("%.1f", handover_u(station)) ..
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

-- The homings choice, shared by every station dialog. Only ours hand them out,
-- which also keeps LUT 1 quiet while it is dark or Kraylor-held. `replies` is
-- the station's own *_replies function: result text first, then the menu, never
-- the page function (the result would be wiped - see commsPlayerShip above).
function comms_replenish_reply(t, src, replies)
    if t:getFaction() ~= "Human Navy" then return end
    addCommsReply("Replenish our homing missiles.", function(comms_source, comms_target)
        math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
        local who = comms_source or src
        setCommsMessage(act_replenish(t, who))
        replies(t, who)   -- replies only: the result stays visible
        return true
    end)
end

function act_collect_tampere(t)
    local info = parts["H200 GPU nodes"]
    if info and info.carried and not info.delivered then
        return "That container is already loaded aboard a recovery ship - deliver it to Lumina 1."
    end
    if not part_out_there("H200 GPU nodes") then
        local x, y = eject_pos(t)
        mk_part("H200 GPU nodes", x, y)
        return "We float a container out to you - it is right outside the station."
    end
    return "The container is already out there - check your sensors."
end

function act_collect_lut(t)
    local info = parts["AMD compute nodes"]
    if info and info.carried and not info.delivered then
        return "That container is already loaded aboard a recovery ship - deliver it to Lumina 1."
    end
    if not part_out_there("AMD compute nodes") then
        local x, y = eject_pos(t)
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
        local x, y = ring_pos(t, 1.2)   -- clear of any hull, still inside the
                                        -- 3u "stop and transfer" range
        mk_part(t.lc_book, x, y)
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
    comms_replenish_reply(t, src, commsLumina_replies)
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
    comms_replenish_reply(t, src, commsKajaani_replies)
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
    comms_replenish_reply(t, src, commsTampere_replies)
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
    return "Received: " .. table.concat(given, ", ") .. "." .. lc_after_delivery()
end

-- What a completed hand-over does to the mission, as one function so the comms
-- path and the GM shortcut (lc_gm_mark_part / lc_gm_deliver_book) can never arm
-- different phases. Returns the text to append to the crew's message.
function lc_after_delivery()
    local extra = ""
    if phase == 2 and part_delivered_count(BOOK_NAMES) >= #BOOK_NAMES and not phase3.armed then
        phase3.armed = true
        print("LC: all playbooks delivered, phase 3 armed")
    end
    local ndone = part_delivered_count(PART_NAMES)
    if phase == 1 and ndone >= #PART_NAMES then
        extra = extra .. "\nAll six components! But our Ansible Playbooks were loaded onto a civilian transport. We are launching shuttle patrols to help you find them."
        phase2_start()
        return extra
    end
    if phase == 1 and not infini_hint_given then
        infini_hint_given = true
        known.infini = true
        extra = extra .. "\nStill missing: the Infiniband switches. Intel places them somewhere in the mid-map box, rows A-E x columns 8-13. Search the nebulas there."
    elseif phase == 1 then
        extra = extra .. "\n" .. ndone .. " of 6 components delivered."
    end
    if phase == 2 then
        extra = extra .. "\n" .. part_delivered_count(BOOK_NAMES) .. " of 3 playbooks recovered."
    end
    return extra
end

function commsTurku(t, src)
    setCommsMessage([[Turku 1. We were attacked, so we hid the Intel compute nodes and the Lustre
fileserver in cargo containers across ]] .. TURKU_NEB .. [[ nebulas around us - our courier ship made it
that far before it was shot down. The containers only say what is inside once you are right next to
them; the Kraylor left junk decoys behind. LUT 1 has the AMD nodes, if they are still ours to ask.]])
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
    comms_replenish_reply(t, src, commsTurku_replies)
end

-- Turku 1's arrival greeting. Its own function so the GM console can replay it
-- (the players arriving is the normal trigger, see update()).
function turku_greet()
    if turku_greeted then return "already greeted" end
    lc_notify([[Turku 1 here! We hid the Intel compute nodes and the
Lustre server in cargo containers across seven nebulas around us. Fly close to every
container to read the labels - the Kraylor scattered junk decoys among them.]], stations.turku)
    turku_greeted = true
    return "greeted"
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
    comms_replenish_reply(t, src, commsLUT_replies)
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
    -- The last killer is not necessarily an active player (autopilot ships and
    -- turrets also count as instigator), and a player may have already jumped
    -- out; always credit the whole crew with a broadcast.
    -- NOTE: the object being destroyed can still read isValid() inside its own
    -- hook, so "was that the last one?" has to skip the ship argument itself.
    for _, s in ipairs(groups.b300) do
        if s ~= ship and s:isValid() then return end
    end
    drop_b300(obj_field(ship, "lc_x", 0), obj_field(ship, "lc_y", 0))
end

-- ========================= drop watchdogs =========================
-- A container only ever appears from a destruction hook, and onDestruction
-- fires ONLY on damage kills (takeHullDamage): a script destroy(), a GM removal
-- or a collision-only death drops nothing and the mission becomes unsolvable.
-- So the hooks are a fast path and the truth is polled here - the same idiom
-- the DSL twin uses with gen_watch_b300 (dsl/DESIGN.md GAP-3 / GAP-12).
drop_watches = {}

-- Poll `group` and hand the last known position to on_drop(x, y) once the whole
-- group is gone and the part is still unaccounted for. `grace` gives the real
-- destruction hook time to do its job first.
function mk_drop_watch(part_name, group, on_drop, grace)
    local w = { part = part_name, group = group, on_drop = on_drop,
                grace = grace or 10, drops = 0, done = false }
    table.insert(drop_watches, w)
    return w
end

-- Is this part already handled: delivered, in a cargo bay, or a crate that
-- still exists? (A crate that was blown up before anyone reached it is not.)
function part_accounted(name)
    local info = parts[name]
    if info == nil then return false end
    if info.delivered or info.carried then return true end
    if info.obj == nil then return false end
    local ok, valid = pcall(function() return info.obj:isValid() end)
    if ok == false or valid then return true end
    return false
end

function drop_watch(delta)
    for _, w in ipairs(drop_watches) do drop_watch_run(w) end
    drop_watch_books()
end

function drop_watch_run(w)
    if w.done then return end
    for _, s in ipairs(w.group) do
        if s:isValid() then
            w.x, w.y = s:getPosition()
            w.alive_at = clock
            return
        end
    end
    if part_accounted(w.part) then return end
    if w.alive_at == nil then w.alive_at = clock end
    if clock - w.alive_at < w.grace then return end
    w.drops = w.drops + 1
    if w.drops >= 2 then w.done = true end   -- never spam crates every tick
    w.on_drop(w.x or 0, w.y or 0)
    print("LC: drop watchdog fired for " .. w.part)
end

function drop_b300(x, y)
    if part_accounted("B300 GPU nodes") then return end
    mk_part("B300 GPU nodes", x, y)
    lc_notify("The Kraylor patrol in C10 is destroyed. Debris includes a cluster component container - the B300 GPU nodes.")
end

-- Playbooks ride on merchant hulls that are meant to respawn 30 s after a loss;
-- if the death hook never ran, neither the spill nor the respawn happens and
-- the playbook is unreachable forever. So keep a script-side mirror of every
-- freighter slot (position, call sign, booked cargo, time of death) that
-- survives the hull, and drive both the spill and the respawn from it.
transport_pos = {}

function drop_watch_books()
    for i, t in ipairs(transports) do
        local st = transport_pos[i]
        if t:isValid() then
            st = st or {}
            st.x, st.y = t:getPosition()
            st.sign = t:getCallSign()
            st.book = obj_field(t, "lc_book", nil)
            st.dead_at = nil
            transport_pos[i] = st
        else
            st = st or {}
            transport_pos[i] = st
            st.dead_at = st.dead_at or clock
            local info = st.book and parts[st.book]
            if info ~= nil and not info.given and not info.delivered and not info.carried then
                if clock - st.dead_at >= 10 then
                    info.given = true
                    mk_part(st.book, st.x or 0, st.y or 0)
                    lc_notify("A freighter carrying an Ansible Playbook was lost - " .. st.book ..
                        " is adrift near sector " .. getSectorName(st.x or 0, st.y or 0) .. ".")
                end
            end
        end
    end
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
    -- description (base + all scan states) once a player is within range.
    for _, c in ipairs(containers) do
        if not c.revealed and c.a:isValid() then
            for _, p in ipairs(players) do
                if d2(p, c.a) < U(LC_REVEAL_U) ^ 2 then
                    lc_reveal_container(c)
                    break
                end
            end
        end
    end

    -- Discovery of the hidden stations: neutral -> ours, and the relay telemetry
    -- bubble comes back up (station_reveal is idempotent).
    for _, name in ipairs({ "tampere", "turku", "lut" }) do
        if not found[name] then
            for _, p in ipairs(players) do
                if d2(p, stations[name]) < U(LC_FIND_U) ^ 2 then
                    station_reveal(name)
                    break
                end
            end
        end
    end

    -- Container-drop safety net (hookless deaths must not softlock the mission).
    drop_watch(delta)

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
                turku_greet()
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
        elseif transport_pos[i] and transport_pos[i].dead_at
               and clock - transport_pos[i].dead_at >= 30 then
            -- Death hook never ran (script destroy / GM removal): respawn from
            -- the script-side mirror, which still knows the call sign.
            transports[i] = mk_transport_like({ lc_sign = transport_pos[i].sign or "Freighter ?" })
            print("LC: freighter respawn watchdog fired (destruction hook missed)")
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

-- ========================= gamemaster console =========================
-- EE's GM console is a FLAT list of script buttons; there is no nesting API.
-- Shipped missions fake submenus with a label convention - "+Name" opens a
-- page, "-Name" goes back - and swap the list by hand with clearGMFunctions()
-- (vendor scripts/scenario_88_chaos.lua). [obs]
--
-- Three engine facts this section is built around (see
-- ee-skills/patterns/gm-console.md):
--  * The button list is scenario-wide, not per-GM. A page swap is global
--    state, so every action re-renders the page it belongs to instead of
--    leaving a second GM sitting on dead buttons.
--  * A function handed to addGMFunction must have the globals table as upvalue
--    #1. Passing a named function that references a chunk local fails with
--    "Upvalue 1 of function is not a table", so every button goes through
--    lc_gm_button's closure with the usual math.abs(0) guard. [obs]
--  * Headless, addGMFunction / clearGMFunctions / addGMMessage all succeed and
--    getGMSelection() returns an empty table, so pages render and actions run
--    in the autotest exactly as they do at the table. [obs]
--
-- Every action is also a plain global lc_gm_* function - the doorway the
-- in-game LUA console uses, and what tests/scenario_40_lostcluster.autotest.lua
-- drives. Actions are idempotent, log exactly one "LC-GM:" line, refuse to run
-- once the mission is over, and never call destroy() on a ship: kills go
-- through takeDamage so onDestruction and the drop watchdogs still fire.

LC_GM_MENU = getScenarioSetting("GMMenu")
if LC_GM_MENU == nil or LC_GM_MENU == "" then LC_GM_MENU = "Enabled" end
lc_gm_page = "main"
lc_gm_hidden = (LC_GM_MENU == "Disabled")
GM_WARP_STEPS = { WARP_SPEED, 1500, 2000, 500 }
lc_gm_warp_idx = 1
GM_SHIP_TEMPLATES = { "Phobos M3P", "Exguard", "Athena", "Overlord" }
lc_gm_ship_idx = 1

function lc_gm_log(msg)
    -- lc_gm_last / LC_GM_CALLS are the audit trail the autotest driver asserts
    -- on: the console has no text fields, so the log is the observable truth.
    LC_GM_CALLS = (LC_GM_CALLS or 0) + 1
    lc_gm_last = msg
    print("LC-GM: " .. msg)
    return msg
end

-- Report to the GM: always the log (the autotest greps it), plus a console
-- message when a GM console actually exists.
function lc_gm_say(msg)
    lc_gm_log(msg)
    pcall(addGMMessage, "LC: " .. msg)
    return msg
end

function lc_gm_guard()
    if done then
        lc_gm_say("mission already finished - controls are locked")
        return false
    end
    return true
end

-- The GM console draws each button in a fixed-width cell and CENTERS the text,
-- so a label longer than the cell is clipped at both ends - and what disappears
-- is the verb that said what the button does. Observed budget in EE-2024.12.08:
-- 23 characters fits, more does not. So: 20 characters, verb first, no state
-- suffixes (a state belongs in a readout message or a marker, not on a button),
-- and the check lives here so the driver fails on a long label instead of a GM
-- failing to read one on a live console.
LC_GM_LABEL_MAX = 20
LC_GM_LABEL_OVER = LC_GM_LABEL_OVER or 0
LC_GM_LABEL_LONGEST = LC_GM_LABEL_LONGEST or 0
lc_gm_label_longest_text = ""

function lc_gm_label(label)
    label = tostring(label)
    if #label > LC_GM_LABEL_LONGEST then
        LC_GM_LABEL_LONGEST = #label
        lc_gm_label_longest_text = label
    end
    if #label <= LC_GM_LABEL_MAX then return label end
    LC_GM_LABEL_OVER = LC_GM_LABEL_OVER + 1
    print("LC-GM: label over the " .. LC_GM_LABEL_MAX .. "-char budget (" .. #label .. "): " .. label)
    return label:sub(1, LC_GM_LABEL_MAX - 3) .. "..."
end

-- Dive-button marker: "+" opens a page, "*" opens a page whose subject is
-- already finished. One character, so a page stays a glanceable progress list
-- without a ": delivered" suffix eating the budget.
function lc_gm_done(name)
    local info = parts[name]
    return (info ~= nil and info.delivered == true) and "*" or "+"
end

-- One console button. The closure keeps the globals table as upvalue #1 (the
-- engine converts it into a ScriptSimpleCallback and checks exactly that).
function lc_gm_button(label, fn)
    LC_GM_BUTTONS = (LC_GM_BUTTONS or 0) + 1
    local shown = lc_gm_label(label)
    local ok, err = pcall(addGMFunction, shown, function()
        math.abs(0) -- ScriptSimpleCallback wants the globals table as upvalue #1
        return fn()
    end)
    if ok == false then print("LC-GM: addGMFunction(" .. shown .. ") failed: " .. tostring(err)) end
    return ok
end

function lc_gm_show(page)
    lc_gm_page = page
    local ok, err = pcall(lc_gm_render)
    if ok == false then print("LC-GM: page render failed: " .. tostring(err)) end
    return ok
end

-- ---------- target and name resolution ----------
-- Headless - and for a GM that selected nothing - this is nil, so every action
-- needs a fallback that does not depend on a selection.
function lc_gm_selected()
    local ok, sel = pcall(getGMSelection)
    if ok == false or sel == nil then return nil end
    for _, o in ipairs(sel) do
        if o ~= nil and o:isValid() then return o end
    end
    return nil
end

-- "all", an exact part name, or a bare index ("4" = 4th component; the playbooks
-- page uses "1".."3"). Always returns a list, empty for nonsense.
function lc_gm_part_names(arg)
    local out = {}
    if arg == nil or tostring(arg) == "all" then
        for _, n in ipairs(PART_NAMES) do table.insert(out, n) end
        for _, n in ipairs(BOOK_NAMES) do table.insert(out, n) end
        return out
    end
    local s = tostring(arg)
    for _, n in ipairs(PART_NAMES) do if n == s then return { n } end end
    for _, n in ipairs(BOOK_NAMES) do if n == s then return { n } end end
    local i = tonumber(s:match("^(%d+)$"))
    if i ~= nil then
        if PART_NAMES[i] then return { PART_NAMES[i] } end
        if BOOK_NAMES[i] then return { BOOK_NAMES[i] } end
    end
    return out
end

function lc_gm_book_names(arg)
    local out = {}
    if arg == nil or tostring(arg) == "all" then
        for _, n in ipairs(BOOK_NAMES) do table.insert(out, n) end
        return out
    end
    local s = tostring(arg)
    for _, n in ipairs(BOOK_NAMES) do if n == s then return { n } end end
    local i = tonumber(s:match("^(%d+)$"))
    if i ~= nil and BOOK_NAMES[i] then return { BOOK_NAMES[i] } end
    return out
end

-- Take a part out of whatever cargo bay holds it (player or freighter) as part
-- of a GM shortcut, so the world cannot end up holding a part twice.
function lc_gm_uncarry(name)
    local info = parts[name]
    if info == nil or info.carried == nil or info.carried == false then return false end
    local holder = info.carried
    info.carried = false
    if holder ~= nil and holder:isValid() and holder.lc_book == name then
        holder.lc_book = nil
        pcall(holder.setDescription, holder, "routine supplies")
    end
    book_transport[name] = nil
    return true
end

-- Remove a crate. Artifacts carry no destruction bookkeeping (the parts table
-- is the truth), so destroy() is fine here - unlike for ships, where a kill has
-- to go through damage for the hooks to run.
function lc_gm_clear_crate(name)
    local info = parts[name]
    if info == nil or info.obj == nil then return false end
    local ok, valid = pcall(function() return info.obj:isValid() end)
    if ok == false or valid == false then
        info.obj = nil
        return false
    end
    info.obj:destroy()
    info.obj = nil
    return true
end

-- A position where the crew can reach something right now.
function lc_gm_near_players()
    local ps = active_players()
    if #ps > 0 then
        local x, y = ps[1]:getPosition()
        return x + U(2), y
    end
    local x, y = stations.lumina:getPosition()
    return x + U(2), y
end

-- A live Kraylor hull near the players, tracked in the wave group so the phase-3
-- "wave destroyed" check still sees a clean slate.
function lc_gm_spawn_enemy(template, faction)
    if not lc_gm_guard() then return "locked" end
    local x, y = lc_gm_near_players()
    local s = CpuShip():setTemplate(template or "Adder MK5"):setFaction(faction or "Kraylor")
        :setPosition(x + random(-U(4), U(4)), y + random(-U(4), U(4)))
        :setCallSign("Kraylor " .. (#groups.wave + 1))
    local players = active_players()
    if #players > 0 then s:orderAttack(players[1]) else s:orderRoaming() end
    table.insert(groups.wave, s)
    return lc_gm_say("spawned a hostile " .. (template or "Adder MK5") .. " beside the players (" ..
        #groups.wave .. " in the wave group)")
end

-- ---------- actions: parts and playbooks ----------
-- The shortcut for "the crew found this". It runs the same consequence code as
-- a real hand-over (lc_after_delivery), so a button press can never arm a phase
-- the players would not have armed themselves.
function lc_gm_mark_part(arg)
    if not lc_gm_guard() then return "locked" end
    local phase_before, n, skipped = phase, 0, 0
    for _, name in ipairs(lc_gm_part_names(arg)) do
        local info = parts[name]
        if info == nil then
            parts[name] = { carried = false, delivered = false }
            info = parts[name]
        end
        if info.delivered then
            skipped = skipped + 1
        else
            lc_gm_uncarry(name)
            lc_gm_clear_crate(name)
            info.delivered = true
            n = n + 1
        end
    end
    local extra = lc_after_delivery()
    if phase ~= phase_before then
        lc_notify("Lumina 1: the analysis is complete - our next objective is underway.")
    end
    return lc_gm_say("marked " .. n .. " part(s) delivered, " .. skipped .. " already done" ..
        "; components " .. part_delivered_count(PART_NAMES) .. "/6, playbooks " ..
        part_delivered_count(BOOK_NAMES) .. "/3" .. extra)
end

-- Put a crate beside the crew, or move the existing crate there. Refuses while
-- the part sits in a cargo bay or is already delivered, since that would put a
-- second copy of the same object in the world.
function lc_gm_drop_part(arg)
    if not lc_gm_guard() then return "locked" end
    local x, y = lc_gm_near_players()
    local n, refused = 0, 0
    for _, name in ipairs(lc_gm_part_names(arg)) do
        local info = parts[name]
        if info == nil then
            parts[name] = { carried = false, delivered = false }
            info = parts[name]
        end
        local adrift = info.obj ~= nil and pcall(function() return info.obj:isValid() end) and info.obj:isValid()
        if info.delivered or (info.carried and info.carried ~= false) then
            refused = refused + 1
        elseif adrift then
            info.obj:setPosition(x, y)
            n = n + 1
        else
            mk_part(name, x, y)
            n = n + 1
        end
    end
    return lc_gm_say("placed " .. n .. " crate(s) beside the players, " .. refused ..
        " refused (in a bay or already delivered)")
end

-- "Tell them where to look." Repeats what the mission already knows; it never
-- invents a location, so it cannot contradict a comms hint.
function lc_gm_announce_part(arg)
    if not lc_gm_guard() then return "locked" end
    local n = 0
    for _, name in ipairs(lc_gm_part_names(arg)) do
        local info = parts[name]
        if info ~= nil then
            local where = "not recovered yet"
            if info.delivered then
                where = "already delivered to Lumina 1"
            elseif info.carried and info.carried ~= false then
                where = "in " .. (info.carried:getCallSign() or "a cargo bay") .. "'s cargo bay"
            elseif info.obj ~= nil and pcall(function() return info.obj:isValid() end) and info.obj:isValid() then
                local cx, cy = info.obj:getPosition()
                where = "adrift in sector " .. (info.drop_sector or getSectorName(cx, cy))
            end
            lc_notify("Lumina 1 sensor summary: " .. name .. " is " .. where .. ".")
            n = n + 1
        end
    end
    return lc_gm_say("broadcast a location for " .. n .. " part(s)")
end

-- ---------- actions: stations and hints ----------
-- "Reveal" only lifts the nebula shadow (the station becomes visible); it does
-- not hand the crew the coordinates, which is what the known[] hints do. The
-- two are deliberately separate buttons because they are separate facts in the
-- fiction, and the driver asserts they stay separate.
function lc_gm_reveal_station(which)
    if not lc_gm_guard() then return "locked" end
    local n = 0
    for _, name in ipairs({ "tampere", "turku", "lut" }) do
        if which == nil or which == "all" or which == name then
            if found[name] then
                lc_gm_log("station " .. name .. " was already found")
            else
                station_reveal(name)
                n = n + 1
            end
        end
    end
    return lc_gm_say("revealed " .. n .. " hidden station(s); coordinates are still" ..
        " only what the hint buttons give")
end

function lc_gm_hint(which)
    if not lc_gm_guard() then return "locked" end
    local n = 0
    for _, name in ipairs({ "tampere", "turku", "lut", "infini" }) do
        if which == nil or which == "all" or which == name then
            if known[name] then
                lc_gm_log("hint for " .. name .. " was already given")
            else
                known[name] = true
                n = n + 1
            end
        end
    end
    if n > 0 then
        lc_notify("Intel has forwarded the coordinates our shutters lost. Check the status page.")
    end
    return lc_gm_say("gave the crew coordinates for " .. n .. " site(s)")
end

-- ---------- actions: phase ----------
function lc_gm_phase2()
    if not lc_gm_guard() then return "locked" end
    if phase > 1 then return lc_gm_say("phase 2 is already running (phase=" .. phase .. ")") end
    for _, name in ipairs(PART_NAMES) do
        local info = parts[name]
        if info == nil then
            parts[name] = { carried = false, delivered = false }
            info = parts[name]
        end
        if not info.delivered then
            lc_gm_uncarry(name)
            lc_gm_clear_crate(name)
            info.delivered = true
        end
    end
    local extra = lc_after_delivery()
    return lc_gm_say("marked all six components delivered, phase is now " .. phase .. extra)
end

-- Arm or disarm the phase-3 fleet. update() does the warning and the spawn, so
-- a GM arming it far from Lumina 1 simply never triggers it - the same rule the
-- players are under.
function lc_gm_arm_phase3(on)
    if not lc_gm_guard() then return "locked" end
    local want = on
    if want == nil then want = not phase3.armed end
    if want == phase3.armed then
        return lc_gm_say("phase 3 is already " .. (want and "armed" or "disarmed"))
    end
    phase3.armed = want
    if want then
        phase3.warned = false
        phase3.timer = 0
    end
    return lc_gm_say("phase 3 " .. (want and "armed: it warns, then spawns a fleet" or "disarmed"))
end

-- Skip the warning timer and put the fleet on the table now.
function lc_gm_spawn_wave()
    if not lc_gm_guard() then return "locked" end
    phase3.armed = true
    phase3.warned = true
    phase3.timer = 0
    phase3.spawned = false
    return lc_gm_say("fleet spawn requested; update() spawns it on the next tick")
end

function lc_gm_victory()
    if not lc_gm_guard() then return "locked" end
    done = true
    lc_notify("Lumina 1: the cluster is ours. Well done, Epsilon.")
    victory("Human Navy")
    return lc_gm_say("victory declared for Human Navy")
end

-- ---------- actions: playbooks and freighters ----------
-- Put a playbook on a freighter hull: the booking (lc_book), the scan
-- description and the guard slot all follow the object, and update_transports
-- re-homes the guards from book_transport, so nothing else needs patching.
function lc_gm_give_book(arg)
    if not lc_gm_guard() then return "locked" end
    local names = lc_gm_book_names(arg)
    if #names ~= 1 then return lc_gm_say("give_book needs exactly one playbook, got " .. #names) end
    local book = names[1]
    local info = parts[book]
    if info ~= nil and info.delivered then return lc_gm_say(book .. " is already delivered") end
    if info ~= nil and info.carried and info.carried ~= false then
        return lc_gm_say(book .. " is already in " .. (info.carried:getCallSign() or "a ship") .. "'s cargo bay")
    end
    local sel, t = lc_gm_selected(), nil
    for _, tr in ipairs(transports) do
        if tr:isValid() and sel ~= nil and tr == sel then t = tr end
    end
    if t == nil and sel ~= nil then
        return lc_gm_say("the selection is not a freighter - select one, or give_book(\"" .. book .. "\") picks one")
    end
    if t == nil then
        for _, tr in ipairs(transports) do
            if t == nil and tr:isValid() and obj_field(tr, "lc_book", nil) == nil then t = tr end
        end
    end
    if t == nil then
        return lc_gm_say("no free freighter is carrying anything - phase 2 spawns the ten freighters")
    end
    if info == nil then
        parts[book] = { carried = false, delivered = false }
        info = parts[book]
    end
    lc_gm_uncarry(book)
    lc_gm_clear_crate(book)
    info.given = nil
    t.lc_book = book
    book_transport[book] = t
    t:setDescriptionForScanState("fullscan", "A civilian freighter. Cargo manifest: one Ansible Playbook, sealed.")
    return lc_gm_say("gave " .. book .. " to " .. (t.lc_sign or t:getCallSign()) .. " (its guards follow the hull)")
end

function lc_gm_deliver_book(arg)
    if not lc_gm_guard() then return "locked" end
    local n = 0
    for _, book in ipairs(lc_gm_book_names(arg)) do
        local info = parts[book]
        if info == nil then
            parts[book] = { carried = false, delivered = false }
            info = parts[book]
        end
        if info.delivered then
            lc_gm_log(book .. " was already delivered")
        else
            lc_gm_uncarry(book)
            lc_gm_clear_crate(book)
            info.delivered = true
            n = n + 1
        end
    end
    local extra = lc_after_delivery()
    return lc_gm_say("delivered " .. n .. " playbook(s), " .. part_delivered_count(BOOK_NAMES) ..
        "/3 recovered, phase 3 armed=" .. tostring(phase3.armed) .. extra)
end

-- ---------- actions: freighter traffic ----------
function lc_gm_freighters(stop)
    if not lc_gm_guard() then return "locked" end
    if #transports == 0 then
        return lc_gm_say("no freighters on the map yet - phase 2 spawns the ten of them")
    end
    local n = 0
    for _, t in ipairs(transports) do
        if t:isValid() then
            t.lc_stopped = stop and true or false
            if stop == false or stop == nil then t.lc_next = nil end  -- resume: re-route at once
            n = n + 1
        end
    end
    return lc_gm_say((stop and "halted " or "resumed ") .. n .. " freighter(s)")
end

-- Bring a shot-down freighter back without waiting for the 30 s watchdog.
function lc_gm_respawn_freighter(arg)
    if not lc_gm_guard() then return "locked" end
    local n, waiting = 0, 0
    for i, t in ipairs(transports) do
        local st = transport_pos[i]
        local sign = t.lc_sign or (st and st.sign) or "Freighter ?"
        local want = arg == nil or tostring(arg) == "all" or tostring(arg) == sign or
            ("Freighter " .. tostring(arg)) == sign
        if want then
            if t:isValid() then
                waiting = waiting + 1
            else
                transports[i] = mk_transport_like({ lc_sign = sign })
                transport_pos[i] = nil
                n = n + 1
            end
        end
    end
    return lc_gm_say("respawned " .. n .. " wrecked freighter(s), " .. waiting .. " still alive")
end

-- Guard respawn credits: how many Kraylor escorts a playbook slot may still
-- replace. Zero credits means the convoy is finally harmless.
function lc_gm_guard_credits(n)
    if not lc_gm_guard() then return "locked" end
    local add = tonumber(n) or 1
    if #guard_slots == 0 then return lc_gm_say("no playbook convoys exist yet to add credits to") end
    local pending = 0
    for _, slot in ipairs(guard_slots) do
        slot.respawns_left = slot.respawns_left + add
        pending = pending + slot.respawns_left
    end
    return lc_gm_say("added " .. add .. " respawn credit(s) per convoy; " .. pending .. " respawns left in total")
end

-- ---------- actions: scenes ----------
-- Replay or skip the scripted beats. Each one calls the very function the
-- trigger calls, so the story text and the world effects stay identical.
function lc_gm_scene(which)
    if not lc_gm_guard() then return "locked" end
    if which == "tampere_ambush" then
        if tampere_state ~= "waiting" then
            return lc_gm_say("the Tampere 1 ambush already played (" .. tampere_state .. ")")
        end
        tampere_ambush()
        return lc_gm_say("Tampere 1 ambush spawned (3 Adders)")
    elseif which == "lut_reveal" then
        if lut_state ~= "friendly" then
            return lc_gm_say("LUT 1 is already " .. lut_state)
        end
        lut_reveal()
        return lc_gm_say("LUT 1 revealed as hostile with its garrison")
    elseif which == "turku_greet" then
        return lc_gm_say("Turku 1 greeting: " .. tostring(turku_greet()))
    elseif which == "b300_drop" then
        local info = parts["B300 GPU nodes"]
        if info ~= nil and info.delivered then return lc_gm_say("the B300 nodes are already delivered") end
        if not all_dead(groups.b300) then
            lc_gm_sweep("b300")     -- organic kill: the destruction hook drops the crate
            return lc_gm_say("destroyed the C10 patrol; its hook drops the crate")
        end
        if part_out_there("B300 GPU nodes") then return lc_gm_say("the B300 crate is already on the map") end
        local x, y = sector_center("C10")
        drop_b300(x, y)
        return lc_gm_say("dropped the B300 crate in C10 by hand (patrol was already gone)")
    end
    return lc_gm_say("unknown scene: " .. tostring(which) ..
        " (tampere_ambush, lut_reveal, turku_greet, b300_drop)")
end

-- ---------- actions: groups ----------
-- Wipe a group. Kills go through takeDamage, never destroy(), because
-- onDestruction only fires on damage kills and the B300 crate, the playbook
-- spill and the guard respawns all hang off those hooks.
function lc_gm_group_names()
    local out = {}
    for _, k in ipairs({ "ambush", "lut", "b300", "guards", "wave", "freighters" }) do
        table.insert(out, k)
    end
    return out
end

function lc_gm_sweep(which)
    if not lc_gm_guard() then return "locked" end
    local group, label = groups[which], which
    if which == "freighters" then group, label = transports, "freighters" end
    if group == nil then
        return lc_gm_say("unknown group \"" .. tostring(which) .. "\": " .. table.concat(lc_gm_group_names(), " "))
    end
    local killed, wrecked = 0, 0
    for _, s in ipairs(group) do
        if s ~= nil and s:isValid() then
            pcall(function() s:takeDamage(5000, "hull") end)
            killed = killed + 1
        else
            wrecked = wrecked + 1
        end
    end
    return lc_gm_say("blew up " .. killed .. " ship(s) in " .. label .. ", " .. wrecked ..
        " already wrecked; watchdogs cover anything a hook missed")
end

-- ---------- actions: tuning and spawns ----------
-- Warp speed is a live knob: WARP_SPEED is what ensure_ftl() hands to the next
-- ship, and this pushes the new value onto everything already flying.
function lc_gm_warp(step)
    if not lc_gm_guard() then return "locked" end
    local v = tonumber(step)
    if v == nil then
        if step ~= nil then return lc_gm_say("warp step must be a number, got " .. tostring(step)) end
        lc_gm_warp_idx = lc_gm_warp_idx % #GM_WARP_STEPS + 1
        v = GM_WARP_STEPS[lc_gm_warp_idx]
    end
    WARP_SPEED = v
    local n = 0
    for _, p in ipairs(active_players()) do
        if p:hasWarpDrive() then p:setWarpSpeed(v) n = n + 1 end
    end
    for _, t in ipairs(transports) do
        if t:isValid() and t:hasWarpDrive() then t:setWarpSpeed(v) n = n + 1 end
    end
    return lc_gm_say("warp speed set to " .. v .. " (" .. (v / 16.6667) .. "u/s), applied to " .. n ..
        " ship(s); new ships inherit it")
end

-- Grant/refresh warp drive on every friendly hull (the mission installs it on
-- players and freighters; this is the "just fix it" button).
function lc_gm_grant_warp()
    if not lc_gm_guard() then return "locked" end
    ensure_ftl()
    local n = 0
    for _, p in ipairs(active_players()) do
        if p:hasWarpDrive() then p:setWarpSpeed(WARP_SPEED) n = n + 1 end
    end
    return lc_gm_say("warp drive ensured on all friendly hulls at speed " .. WARP_SPEED .. " (" .. n .. " player ship(s))")
end

function lc_gm_difficulty(mode)
    if not lc_gm_guard() then return "locked" end
    local want = mode
    if want == nil then want = STORY_MODE and "Normal" or "Story" end
    if want ~= "Story" and want ~= "Normal" then
        return lc_gm_say("difficulty must be Story or Normal, got " .. tostring(mode))
    end
    STORY_MODE = (want == "Story")
    LC_DIFFICULTY = want
    local changed = 0
    for _, p in ipairs(active_players()) do
        if STORY_MODE then
            story_buff(p)
        elseif story_off(p) then
            changed = changed + 1
        end
    end
    return lc_gm_say("difficulty is now " .. want .. (STORY_MODE and
        " (beams one-shot; buffs applied to " .. #active_players() .. " ship(s))" or
        " (original beam numbers restored on " .. changed .. " ship(s))"))
end

-- The brief's "the GM can spawn more ships": a fresh player hull at Lumina 1,
-- hooked exactly like the first one (cargo-on-death, comms, story buffs).
function lc_gm_spawn_ship(template)
    if not lc_gm_guard() then return "locked" end
    local tmpl = template
    if tmpl == nil then
        lc_gm_ship_idx = lc_gm_ship_idx % #GM_SHIP_TEMPLATES + 1
        tmpl = GM_SHIP_TEMPLATES[lc_gm_ship_idx]
    end
    local x, y = stations.lumina:getPosition()
    local p = PlayerSpaceship():setFaction("Human Navy"):setTemplate(tmpl)
        :setPosition(x + random(-U(3), U(3)), y + random(-U(3), U(3)))
        :setCallSign("Epsilon " .. (#active_players() + 1))
    watch_player(p)
    ensure_ftl()
    return lc_gm_say("spawned a player ship (" .. tostring(tmpl) .. ") at Lumina 1")
end

-- Menu visibility, for tables where the GM wants no buttons at all. The
-- lc_gm_* functions keep working either way - this only controls the buttons.
function lc_gm_menu(on)
    local want = on
    if want == nil then want = not lc_gm_hidden end
    lc_gm_hidden = not want and true or false
    lc_gm_page = "main"
    lc_gm_render()
    return lc_gm_say("GM menu " .. (lc_gm_hidden and "hidden (lc_gm_* still callable)" or "shown"))
end

-- ---------- readouts ----------
-- The GM console has no text fields, only buttons and messages, so every
-- readout is an addGMMessage plus the same text in the log - which is also what
-- makes the pages assertable from the autotest driver.
function lc_gm_report(s)
    LC_GM_CALLS = (LC_GM_CALLS or 0) + 1
    lc_gm_last = s
    for line in (s .. "\n"):gmatch("([^\n]*)\n") do print("LC-GM: " .. line) end
    pcall(addGMMessage, s)
    return s
end

function lc_gm_alive_count(group)
    local n = 0
    for _, s in ipairs(group or {}) do
        if s ~= nil and s:isValid() then n = n + 1 end
    end
    return n
end

function lc_gm_guard_total()
    local n = 0
    for _, slot in ipairs(guard_slots) do n = n + slot.respawns_left end
    return n
end

function lc_gm_status()
    local alive, wrecked, crates = 0, 0, 0
    for _, t in ipairs(transports) do
        if t:isValid() then alive = alive + 1 else wrecked = wrecked + 1 end
    end
    for _, c in ipairs(containers) do
        if c.a:isValid() then crates = crates + 1 end
    end
    return lc_gm_report("Lost Cluster, GM view\n" .. lc_status() .. "\n" ..
        "phase=" .. phase .. " done=" .. tostring(done) ..
        " clock=" .. string.format("%.0f", clock or 0) .. "s" ..
        " difficulty=" .. tostring(LC_DIFFICULTY) .. " warp=" .. tostring(WARP_SPEED) .. "\n" ..
        "components " .. part_delivered_count(PART_NAMES) .. "/6, playbooks " ..
        part_delivered_count(BOOK_NAMES) .. "/3, containers on map " .. crates .. "/" .. #containers .. "\n" ..
        "stations found: tampere=" .. tostring(found.tampere) .. " turku=" .. tostring(found.turku) ..
        " lut=" .. tostring(found.lut) .. " | coordinates known: tampere=" .. tostring(known.tampere) ..
        " turku=" .. tostring(known.turku) .. " lut=" .. tostring(known.lut) ..
        " infini=" .. tostring(known.infini) .. "\n" ..
        "scenes: tampere=" .. tampere_state .. " lut=" .. lut_state ..
        " turku_greeted=" .. tostring(turku_greeted) .. "\n" ..
        "phase3: armed=" .. tostring(phase3.armed) .. " warned=" .. tostring(phase3.warned) ..
        " timer=" .. string.format("%.0f", phase3.timer or 0) .. " spawned=" .. tostring(phase3.spawned) .. "\n" ..
        "freighters: " .. alive .. " alive, " .. wrecked .. " wrecked; guard respawns left " ..
        lc_gm_guard_total() .. "\n" ..
        "groups: ambush=" .. lc_gm_alive_count(groups.ambush) .. " lut=" .. lc_gm_alive_count(groups.lut) ..
        " b300=" .. lc_gm_alive_count(groups.b300) .. " guards=" .. lc_gm_alive_count(groups.guards) ..
        " wave=" .. lc_gm_alive_count(groups.wave) .. "\n" ..
        "players: " .. #active_players() .. ", ambient: " .. ambient_stats.nebulae .. " nebulas, " ..
        ambient_stats.rocks .. " rocks, " .. ambient_stats.wrecks .. " wrecks, " ..
        ambient_stats.wormholes .. " wormholes")
end

function lc_gm_players()
    local ps = active_players()
    local s = "Player ships (" .. #ps .. "):\n"
    for _, p in ipairs(ps) do
        local x, y = p:getPosition()
        local cargo = {}
        for _, name in ipairs(PART_NAMES) do
            local info = parts[name]
            if info ~= nil and info.carried == p then table.insert(cargo, name) end
        end
        for _, name in ipairs(BOOK_NAMES) do
            local info = parts[name]
            if info ~= nil and info.carried == p then table.insert(cargo, name) end
        end
        -- NOTE: there is no getTemplate()/getName() on ships in this build's
        -- script API, so the readout shows what the script really knows. [obs]
        s = s .. "  " .. (p:getCallSign() or "?") ..
            " hull=" .. string.format("%.0f", p:getHull()) .. " sector=" .. getSectorName(x, y) ..
            " warp=" .. (p:hasWarpDrive() and tostring(p:getWarpSpeed()) or "no") ..
            " watched=" .. tostring(p.lc_watched == true) ..
            " cargo=" .. (#cargo > 0 and table.concat(cargo, ", ") or "empty") .. "\n"
    end
    return lc_gm_report(s)
end

function lc_gm_freighter_list()
    if #transports == 0 then return lc_gm_report("No freighters yet - phase 2 spawns ten of them.") end
    local s = "Freighters (" .. #transports .. "):\n"
    for _, t in ipairs(transports) do
        if t:isValid() then
            local x, y = t:getPosition()
            s = s .. "  " .. (t.lc_sign or "?") .. " sector=" .. getSectorName(x, y) ..
                " book=" .. tostring(t.lc_book or "none") ..
                " stopped=" .. tostring(t.lc_stopped == true) .. "\n"
        else
            s = s .. "  " .. (t.lc_sign or "?") .. " WRECKED (respawns on a 30 s watchdog)\n"
        end
    end
    return lc_gm_report(s)
end

function lc_gm_containers()
    local shown, junk = 0, 0
    local s = "Containers (" .. #containers .. "):\n"
    for _, c in ipairs(containers) do
        if c.a:isValid() then
            local x, y = c.a:getPosition()
            if c.junk then junk = junk + 1 end
            s = s .. "  " .. (c.revealed and (c.desc or "unlabelled") or "unlabelled") ..
                " sector=" .. getSectorName(x, y) .. (c.junk and " (decoy)" or "") .. "\n"
            shown = shown + 1
        end
    end
    return lc_gm_report(s .. "on map: " .. shown .. ", of which decoys: " .. junk)
end

-- ---------- pages ----------
-- The pager: a page is a function that adds its buttons; lc_gm_open() is how a
-- "+Label" button dives one level deeper, "-Back" comes up. lc_gm_arg carries
-- the subject of a detail page (a part name), because the button list is the
-- only state the engine keeps.
function lc_gm_open(page, arg)
    lc_gm_page = page
    lc_gm_arg = arg
    lc_gm_render()
end

function lc_gm_back(page)
    lc_gm_button("-Back", function() lc_gm_open(page) end)
end

function lc_gm_part_state(name)
    local info = parts[name]
    if info == nil then return "not placed" end
    if info.delivered then return "delivered" end
    if info.carried and info.carried ~= false then
        return "in " .. (info.carried:getCallSign() or "a cargo bay")
    end
    if info.obj ~= nil and pcall(function() return info.obj:isValid() end) and info.obj:isValid() then
        local x, y = info.obj:getPosition()
        return "adrift " .. getSectorName(x, y)
    end
    return "not recovered"
end

function lc_gm_page_main()
    -- The header is a readout: short on the button, the long version in the
    -- message, because the cell cannot hold "phase 3, 6/6 parts, 3/3 convoys".
    lc_gm_button("LC phase " .. phase, function() lc_gm_status() end)
    lc_gm_button("+Components " .. part_delivered_count(PART_NAMES) .. "/" .. #PART_NAMES,
        function() lc_gm_open("parts") end)
    lc_gm_button("+Convoys " .. part_delivered_count(BOOK_NAMES) .. "/" .. #BOOK_NAMES,
        function() lc_gm_open("books") end)
    lc_gm_button("+Stations & hints", function() lc_gm_open("stations") end)
    lc_gm_button("+Phase & finale", function() lc_gm_open("phase") end)
    lc_gm_button("+Scenes & sweeps", function() lc_gm_open("scenes") end)
    lc_gm_button("+Tuning & spawns", function() lc_gm_open("tuning") end)
    lc_gm_button("+Ships & cargo", function() lc_gm_open("ships") end)
    lc_gm_button("Status report", function() lc_gm_status() end)
    lc_gm_button("Console commands", function() lc_gm_help() end)
end

function lc_gm_page_parts()
    lc_gm_back("main")
    lc_gm_button("Mark all delivered", function() lc_gm_mark_part("all") end)
    lc_gm_button("Drop all crates", function() lc_gm_drop_part("all") end)
    lc_gm_button("Announce locations", function() lc_gm_announce_part("all") end)
    for _, name in ipairs(PART_NAMES) do
        lc_gm_button(lc_gm_done(name) .. name, function() lc_gm_open("part", name) end)
    end
end

-- A detail page's own name button: the label can hold the name or its state, not
-- both, so clicking the name reports the state that did not fit. It takes the
-- same argument forms as the other actions, so `lc_gm_part_info("all")` on the
-- console is a one-line census of every crate.
function lc_gm_part_info(arg)
    local lines = {}
    for _, name in ipairs(lc_gm_part_names(arg)) do
        table.insert(lines, name .. ": " .. lc_gm_part_state(name))
    end
    return lc_gm_report(table.concat(lines, "\n"))
end

function lc_gm_page_part()
    local name = lc_gm_arg
    if name == nil then return lc_gm_open("parts") end
    lc_gm_back("parts")
    lc_gm_button(name, function() lc_gm_part_info(name) end)
    lc_gm_button("Where is it?", function() lc_gm_announce_part(name) end)
    lc_gm_button("Drop crate at crew", function() lc_gm_drop_part(name) end)
    lc_gm_button("Mark delivered", function() lc_gm_mark_part(name) end)
end

function lc_gm_page_books()
    lc_gm_back("main")
    lc_gm_button("Halt all freighters", function() lc_gm_freighters(true) end)
    lc_gm_button("Resume freighters", function() lc_gm_freighters(false) end)
    lc_gm_button("Respawn freighters", function() lc_gm_respawn_freighter("all") end)
    lc_gm_button("Freighter list", function() lc_gm_freighter_list() end)
    lc_gm_button("Container list", function() lc_gm_containers() end)
    for k, name in ipairs(BOOK_NAMES) do
        lc_gm_button(lc_gm_done(name) .. "Playbook " .. k, function() lc_gm_open("book", name) end)
    end
end

-- "Ansible Playbook 2 (of 3)" -> "Playbook 2": the whole label cannot fit, and
-- the index is the only part that tells two of them apart on a button.
function lc_gm_book_short(name)
    return tostring(name):match("[Pp]laybook %d+") or tostring(name):sub(1, LC_GM_LABEL_MAX)
end

function lc_gm_page_book()
    local name = lc_gm_arg
    if name == nil then return lc_gm_open("books") end
    lc_gm_back("books")
    lc_gm_button(lc_gm_book_short(name), function() lc_gm_part_info(name) end)
    lc_gm_button("Give to freighter", function() lc_gm_give_book(name) end)
    lc_gm_button("Mark delivered", function() lc_gm_deliver_book(name) end)
    lc_gm_button("Drop crate at crew", function() lc_gm_drop_part(name) end)
    lc_gm_button("Sweep its guards", function() lc_gm_sweep("guards") end)
    lc_gm_button("+Guard credits", function() lc_gm_guard_page() end)
end

function lc_gm_guard_page()
    lc_gm_back("books")
    lc_gm_button("respawns left: " .. lc_gm_guard_total(), function() lc_gm_guard_page() end)
    lc_gm_button("Convoy +1 credit", function() lc_gm_guard_credits(1) end)
    lc_gm_button("Convoy +3 credits", function() lc_gm_guard_credits(3) end)
    lc_gm_button("Sweep the guards", function() lc_gm_sweep("guards") end)
end

function lc_gm_page_stations()
    lc_gm_back("main")
    lc_gm_button("Reveal all stations", function() lc_gm_reveal_station("all") end)
    lc_gm_button("Reveal Tampere 1", function() lc_gm_reveal_station("tampere") end)
    lc_gm_button("Reveal Turku 1", function() lc_gm_reveal_station("turku") end)
    lc_gm_button("Reveal LUT 1", function() lc_gm_reveal_station("lut") end)
    lc_gm_button("Give all hints", function() lc_gm_hint("all") end)
    lc_gm_button("Hint Tampere+Turku", function() lc_gm_hint("tampere"); lc_gm_hint("turku") end)
    lc_gm_button("Hint: LUT 1", function() lc_gm_hint("lut") end)
    lc_gm_button("Hint Infiniband", function() lc_gm_hint("infini") end)
end

function lc_gm_page_phase()
    lc_gm_back("main")
    lc_gm_button("phase " .. phase .. (phase3.armed and " armed" or " not armed"),
        function() lc_gm_open("phase") end)
    lc_gm_button("Finish phase 1", function() lc_gm_phase2() end)
    lc_gm_button("Deliver playbooks", function() lc_gm_deliver_book("all") end)
    lc_gm_button(phase3.armed and "Disarm finale fleet" or "Arm finale fleet",
        function() lc_gm_arm_phase3() end)
    lc_gm_button("Spawn finale fleet", function() lc_gm_spawn_wave() end)
    lc_gm_button("Declare victory", function() lc_gm_victory() end)
end

function lc_gm_page_scenes()
    lc_gm_back("main")
    lc_gm_button("Tampere 1 ambush", function() lc_gm_scene("tampere_ambush") end)
    lc_gm_button("LUT 1 turns hostile", function() lc_gm_scene("lut_reveal") end)
    lc_gm_button("Turku 1 greeting", function() lc_gm_scene("turku_greet") end)
    lc_gm_button("B300 crate appears", function() lc_gm_scene("b300_drop") end)
    for _, g in ipairs(lc_gm_group_names()) do
        lc_gm_button("Sweep " .. g .. ": " .. lc_gm_alive_count(g == "freighters" and transports or groups[g]),
            function() lc_gm_sweep(g) end)
    end
end

function lc_gm_page_tuning()
    lc_gm_back("main")
    lc_gm_button("warp " .. tostring(WARP_SPEED) .. " " .. tostring(LC_DIFFICULTY),
        function() lc_gm_open("tuning") end)
    lc_gm_button("Warp: next step", function() lc_gm_warp() end)
    for _, v in ipairs(GM_WARP_STEPS) do
        lc_gm_button("Warp = " .. v, function() lc_gm_warp(v) end)
    end
    lc_gm_button("Give all warp drive", function() lc_gm_grant_warp() end)
    lc_gm_button(STORY_MODE and "Switch to Normal" or "Switch to Story",
        function() lc_gm_difficulty() end)
    lc_gm_button("Ship at Lumina 1", function() lc_gm_spawn_ship() end)
    lc_gm_button("Hostile by players", function() lc_gm_spawn_enemy() end)
    lc_gm_button("Hide this menu", function() lc_gm_menu(false) end)
end

function lc_gm_page_ships()
    lc_gm_back("main")
    lc_gm_button("Player list", function() lc_gm_players() end)
    lc_gm_button("Freighter list", function() lc_gm_freighter_list() end)
    lc_gm_button("Container list", function() lc_gm_containers() end)
    lc_gm_button("Ship at Lumina 1", function() lc_gm_spawn_ship() end)
    lc_gm_button("Respawn freighters", function() lc_gm_respawn_freighter("all") end)
    lc_gm_button("Reveal all labels", function() lc_gm_reveal_containers() end)
end

-- Detail page for "which container is where": labels on demand.
function lc_gm_reveal_containers()
    if not lc_gm_guard() then return "locked" end
    lc_reveal_all()
    return lc_gm_say("every container label revealed to the crew (" .. #containers .. " containers)")
end

function lc_gm_help()
    return lc_gm_report("Lost Cluster, console commands (each line is Lua on the server):\n" ..
        "  lc_gm_status()            lc_gm_players()       lc_gm_freighter_list()\n" ..
        "  lc_gm_containers()        lc_gm_show(\"parts\")   lc_gm_menu(false)\n" ..
        "  lc_gm_mark_part(\"all\")    lc_gm_mark_part(4)    lc_gm_drop_part(2)\n" ..
        "  lc_gm_announce_part(\"all\")  lc_gm_phase2()      lc_gm_arm_phase3(true)\n" ..
        "  lc_gm_spawn_wave()        lc_gm_victory()       lc_gm_scene(\"lut_reveal\")\n" ..
        "  lc_gm_give_book(1)        lc_gm_deliver_book(\"all\")  lc_gm_freighters(true)\n" ..
        "  lc_gm_respawn_freighter(\"Freighter 3\")  lc_gm_guard_credits(2)  lc_gm_sweep(\"wave\")\n" ..
        "  lc_gm_warp(1500)          lc_gm_grant_warp()    lc_gm_difficulty(\"Story\")\n" ..
        "  lc_gm_spawn_ship(\"Exguard\")  lc_gm_spawn_enemy(\"Piranha F12\")\n" ..
        "  lc_gm_reveal_station(\"all\")  lc_gm_hint(\"all\")   lc_gm_reveal_containers()\n" ..
        "  lc_gm_part_info(\"all\")      lc_gm_part_info(2)   (crate state, or all)")
end

lc_gm_pages = {
    main = lc_gm_page_main,
    parts = lc_gm_page_parts,
    part = lc_gm_page_part,
    books = lc_gm_page_books,
    book = lc_gm_page_book,
    guards = lc_gm_guard_page,
    stations = lc_gm_page_stations,
    phase = lc_gm_page_phase,
    scenes = lc_gm_page_scenes,
    tuning = lc_gm_page_tuning,
    ships = lc_gm_page_ships,
}

-- Rebuild the whole button list for the current page. The engine keeps no page
-- structure, so this is the pager: clear, then let one page function add its own
-- buttons. Called after every action so a second GM (or a stale page) can never
-- leave a dead button on screen.
function lc_gm_render()
    local before = LC_GM_BUTTONS or 0
    pcall(clearGMFunctions)
    if lc_gm_hidden then
        lc_gm_button("+Show LC menu", function() lc_gm_menu(true) end)
    else
        local fn = lc_gm_pages[lc_gm_page] or lc_gm_pages.main
        fn()
    end
    -- The page swap gets its own audit line, and deliberately not through
    -- lc_gm_log(): a redraw must never overwrite the action result that the
    -- driver (or a GM reading the log) just asked for.
    print("LC-GM: page " .. lc_gm_page .. " drawn, " .. ((LC_GM_BUTTONS or 0) - before) .. " button(s)")
end

-- Called from init(): one pcall so a missing GM API can never break the mission.
function lc_gm_boot()
    local ok, err = pcall(lc_gm_render)
    print("LC-GM: menu=" .. LC_GM_MENU .. " page=" .. lc_gm_page .. " rendered=" .. tostring(ok) ..
        (ok == false and (" err=" .. tostring(err)) or ""))
    return ok
end

-- ========================= test hooks =========================
-- This build has no callscriptfunction(); a LUA console line IS Lua, so the
-- console doorway is simply `probe_state()` / `lc_gm_status()` etc. The
-- autotest driver runs in this same chunk and calls them directly. [obs]
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
    -- Same doorway the GM console uses, so the two can never drift apart.
    for _, n in ipairs(PART_NAMES) do lc_gm_mark_part(n) end
    if phase == 1 and part_delivered_count(PART_NAMES) >= #PART_NAMES then
        phase2_start()
    end
    print("LC-PROBE all parts delivered, phase=" .. phase)
end

function probe_deliver_books()
    for _, n in ipairs(BOOK_NAMES) do lc_gm_deliver_book(n) end
    -- lc_after_delivery() arms it only when the mission is in phase 2 (the only
    -- phase where playbooks exist); a shortcut timeline that skips straight here
    -- still needs the finale armed, so the probe keeps its own explicit call.
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

-- Visibility contract: a hidden station must not be Human Navy (friendly
-- contacts are shared over relay telemetry no matter what nebula hides them).
function probe_hidden()
    for _, name in ipairs({ "tampere", "turku", "lut" }) do
        local st = stations[name]
        print("LC-PROBE station " .. name .. " faction=" .. st:getFaction() ..
            " found=" .. tostring(found[name] == true) ..
            " revealed=" .. tostring(st.lc_revealed == true))
    end
    return stations.tampere:getFaction() ~= "Human Navy"
end

-- Is a container for this part actually in the world (the anti-softlock
-- question the destruction hooks alone cannot answer)?
function probe_dropped(name)
    local info = parts[tostring(name)]
    local exists = info ~= nil and info.obj ~= nil and info.obj:isValid()
    print("LC-PROBE part " .. tostring(name) .. " container=" .. tostring(exists) ..
        " delivered=" .. tostring(info and info.delivered == true) ..
        " carried=" .. tostring(info ~= nil and info.carried and true or false) ..
        " sector=" .. tostring(info and info.drop_sector))
    return exists
end

-- Hand-over range gate: throwaway carrier at `dist` units from Lumina 1
-- ("near" = just inside the bubble, "far" = well outside it).
function probe_handover(mode)
    local st = stations.lumina
    if st == nil or not st:isValid() then print("LC-PROBE no Lumina") return false end
    local info = parts["H200 GPU nodes"]
    if info == nil then print("LC-PROBE no H200 part record") return false end
    local p = CpuShip():setTemplate("Atlantis"):setFaction("Human Navy")
    local x, y = st:getPosition()
    local d = 20
    if mode == "near" then d = handover_u(st) * 0.8 end
    p:setPosition(x + U(d), y)
    local save_c, save_d = info.carried, info.delivered
    local save_hint, save_known, save_phase = infini_hint_given, known.infini, phase
    info.carried, info.delivered = p, false
    local msg = act_deliver(st, p)
    local accepted = info.delivered == true
    info.carried, info.delivered = save_c, save_d
    infini_hint_given, known.infini, phase = save_hint, save_known, save_phase
    p:destroy()
    print("LC-PROBE handover " .. tostring(mode) .. " dist=" .. string.format("%.1f", d) ..
        "u accepted=" .. tostring(accepted) .. " msg=" .. msg)
    return accepted
end

-- Turku 1 nebula ring: count and how far out it reaches.
function probe_turku_field()
    if turku_nebs == nil then print("LC-PROBE turku field not built") return false end
    local x, y = stations.turku:getPosition()
    local n, far = 0, 0
    for _, nb in ipairs(turku_nebs) do
        n = n + 1
        local d = math.sqrt((nb.x - x) ^ 2 + (nb.y - y) ^ 2) / 1000
        if d > far then far = d end
    end
    print("LC-PROBE turku nebulas=" .. n .. " max_radius_u=" .. string.format("%.1f", far))
    return n == TURKU_NEB and far <= TURKU_R_MAX + 0.1
end

-- What does container #i read right now (label-state machine)?
function probe_container_text(i)
    local c = containers[tonumber(i) or 0]
    if c == nil or not c.a:isValid() then print("LC-PROBE no such container") return "" end
    local t = c.a:getDescription()
    print("LC-PROBE container " .. tostring(i) .. " junk=" .. tostring(c.junk) ..
        " revealed=" .. tostring(c.revealed) .. " text=" .. t)
    return t
end

-- Station-ejection geometry: eject a part beside a station and report how far
-- the crate landed from the hull (must be reachable, so <= LC_HANDOVER_U).
function probe_eject_geometry(part_name, station_name)
    local st = stations[tostring(station_name)]
    if st == nil or not st:isValid() then print("LC-PROBE no such station") return false end
    local info = parts[tostring(part_name)]
    if info == nil then print("LC-PROBE no such part") return false end
    local save = info.obj
    info.obj = nil
    local x, y = eject_pos(st)
    local probe_a = mk_part(tostring(part_name), x, y)
    local sx, sy = st:getPosition()
    local d = math.sqrt((x - sx) ^ 2 + (y - sy) ^ 2) / 1000
    local hull = station_hull_u(st)
    if probe_a:isValid() then probe_a:destroy() end   -- throwaway crate only
    info.obj = save
    if info.cont then info.cont.a = save end
    print("LC-PROBE eject " .. tostring(part_name) .. " at " .. string.format("%.2f", d) ..
        "u from " .. tostring(station_name) .. " (hull " .. string.format("%.2f", hull) ..
        "u, hand-over " .. string.format("%.2f", handover_u(st)) .. "u)")
    return d > hull and d <= handover_u(st)
end

