-- Name: 42 Fever Run
-- Description: Warning: fully AI generated as a test, use with caution.
--- A colony has a fever outbreak. Find the missing vaccine courier, then deliver three cases before the fever does.
--- Your newly commissioned patrol ship gets a mercy errand: Sedgeon Colony has
--- an outbreak, and the vaccine was due yesterday. The courier that carried the
--- third case stopped answering two days ago. Two ships are broadcasting from
--- her last known position - and only one of them is her.
---
--- A short story mission for a fresh crew: one puzzle, two small fights, one
--- delivery. Every station gets work; nothing is tuned to kill you.
-- Author: Cline (scenario test bed)
-- Type: Mission
-- Setting[Difficulty]: Mission difficulty.
-- Difficulty[Normal|Default]: Standard balance: two small raider waves and one trap.
-- Difficulty[Story]: Story mode: player beams one-shot anything they hit.

-- =====================================================================
-- Fever Run. Built from the ee-skills patterns (skeleton + demo):
-- notify queue, split comms pages, range gates, polled watchers,
-- probe hooks. Order: knobs -> helpers -> state -> comms -> gates
-- -> init -> update -> watches -> phase machine -> test hooks.
-- =====================================================================

-- ========================= scale & knobs =========================
function U(u) return u * 1000 end

FR = {
    arrival_u    = 6,     -- "you have reached the relay" radius
    beacon_u     = 2.5,   -- approaching the decoy this close springs the trap
    handover_u   = 1.4,   -- alongside range for load/deliver gates (Medium hull)
    override_s   = 300,   -- relay override key arrives this long after briefing
    wave_u       = 10,    -- final raiders spring this close to the colony
    case_grace_s = 15,    -- drop-watch grace before respawning case C
    notify_s     = 25,    -- notify queue retry deadline
}

DIFFICULTY = getScenarioSetting("Difficulty")
if DIFFICULTY == nil or DIFFICULTY == "" then DIFFICULTY = "Normal" end
STORY_MODE = DIFFICULTY == "Story"
print("FR: difficulty=" .. DIFFICULTY)

-- ========================= helpers =========================
function d2(a, b)
    local ax, ay = a:getPosition()
    local bx, by = b:getPosition()
    return (ax - bx) ^ 2 + (ay - by) ^ 2
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

-- Stock templates lack FTL on some hulls; run every tick so late joiners and
-- GM respawns are covered too (pitfall 11).
function ensure_ftl(players)
    for _, p in ipairs(players) do
        if p:isValid() and not p:hasWarpDrive() then
            p:setWarpDrive(true)
            p:setWarpSpeed(1000)               -- 1000 == 60u/second
        end
    end
end

-- ========================= state =========================
clock = 0
phase = 1                      -- 1 reach relay, 2 triage, 3 load, 4 deliver
done = false
delivered = false
ever_had_players = false
stations = {}
groups = { ambush = {}, wave = {} }
ambush_sprung = false
ambush_done = false
wave_spawned = false
wave_done = false
codes = false                  -- Polaris's medical access codes (or the override)
case_c_aboard = false          -- the courier's own case
loaded = false                 -- cases A+B taken on at the relay
codes_deadline = nil
case_c_grace = nil
polaris_scanned = false
decoy_scanned = false
msgq = {}

-- ========================= notify queue =========================
-- sendCommsMessage is now-or-never (pitfall 3): queue with retry
-- (patterns/notify-queue.md). Every notify names a speaking station.
function notify(msg, from)
    table.insert(msgq, { msg = msg, from = from, until_s = clock + FR.notify_s, done = {} })
end

function pump_messages()
    if #msgq == 0 then return end
    local players = active_players()
    for i = #msgq, 1, -1 do
        local q = msgq[i]
        local sender = q.from
        if sender == nil or not sender:isValid() then sender = stations.meridian end
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

-- ========================= builders =========================
function mk_station(name, tmpl, fac, x, y, page_fn)
    local s = SpaceStation():setTemplate(tmpl):setFaction(fac):setPosition(x, y)
    s:setCallSign(name)
    if page_fn then
        local st = s
        s:setCommsFunction(function(src)
            math.abs(0)   -- ScriptSimpleCallback wants globals as upvalue #1
            return page_fn(st, src or active_players()[1])
        end)
    end
    return s
end

function mk_ship(name, tmpl, fac, x, y)
    local s = CpuShip():setTemplate(tmpl):setFaction(fac):setPosition(x, y)
    s:setCallSign(name)
    s.scen_x, s.scen_y = x, y
    return s
end

-- ========================= the two beacon ships =========================
-- Science work: both ships carry two-state descriptions. The real courier is
-- ours (so she is on the contact list); the decoy is Independent, because
-- same-faction objects cannot hide (pitfall 6).
function build_polaris()
    local p = mk_ship("POLARIS", "Phobos T3", "Human Navy", U(60), U(-8))
    p:setDescriptions(
        "A Human Navy medical courier, dark and drifting. No response to hails.",
        "Medical courier Polaris - the missing courier. Hull breached, reactor " ..
        "dead, crew alive. Her medical locker is still sealed.")
    return p
end

function build_decoy()
    local d = mk_ship("COLDFIELD-2", "Phobos T3", "Independent", U(68), U(2))
    d:setDescriptions(
        "A freighter answering to the name COLDFIELD-2. Claims to be a relay tug.",
        "The transponder says Coldfield tug, but the hull plating is Exuari. " ..
        "This is bait.")
    return d
end

-- ========================= case C (the courier's own case) =========================
-- One physical pickup: fly over it. onPickUp is collision based and a headless
-- hull never collides (pitfall 13), so probe_pickup shares this bookkeeping.
case_c_obj = nil
case_c_drop = { x = U(60.5), y = U(-7.4) }

function case_c_text(a)
    local t = "Medical container: VACCINE CASE C. Fly over it to collect."
    a:setDescription(t)
    a:setDescriptionForScanState("notscanned", t)
    a:setDescriptionForScanState("simplescan", t)
    a:setDescriptionForScanState("fullscan", t)
end

function spawn_case_c()
    if case_c_obj ~= nil and case_c_obj:isValid() then return end
    local a = Artifact():setModel("artifact6")
        :setPosition(case_c_drop.x, case_c_drop.y)
        :setSpin(0.3):allowPickup(true)
    case_c_text(a)
    local art = a
    a:onPickUp(function(_, ship)
        math.abs(0)
        if case_c_aboard then return end
        if art:isValid() then art:destroy() end
        collect_case_c("pickup")
    end)
    a:setCommsFunction(function()
        math.abs(0)
        setCommsMessage("Automated medical container. Contents: VACCINE CASE C. " ..
            "Fly over it to collect it.")
        return true
    end)
    case_c_obj = a
    print("FR: case C spawned at " .. getSectorName(case_c_drop.x, case_c_drop.y))
end

function collect_case_c(how)
    if case_c_aboard then return end
    case_c_aboard = true
    notify("Cargo bay secured: VACCINE CASE C. With the relay's A and B that is " ..
        "all three accounted for.", stations.relay)
    print("FR: case C collected (" .. tostring(how) .. ")")
end

-- The case must always be obtainable: if the container is destroyed without
-- being picked up, put it back (patterns/guaranteed-drop.md).
function case_c_watch()
    if case_c_aboard then return end
    if case_c_obj ~= nil and case_c_obj:isValid() then return end
    if case_c_grace == nil then case_c_grace = clock + FR.case_grace_s end
    if clock > case_c_grace then
        case_c_grace = nil
        spawn_case_c()
        notify("Sensor update: the medical container is transmitting again. " ..
            "It is still out there.", stations.relay)
    end
end

-- ========================= comms: Meridian Starbase =========================
function commsMeridian(t, src)
    setCommsMessage([[Meridian Starbase. Good to see the new ship out of dock.
Sedgeon Colony has a fever outbreak - the vaccine shipment was due two days
ago. Coldfield Relay holds cases A and B, but the courier that carried case C,
the Polaris, stopped answering. Take the ship and sort it out.]])
    commsMeridian_replies(t, src)
    return true
end

function commsMeridian_replies(t, src)
    addCommsReply("What is the situation at Sedgeon?", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage("Fever, not plague. It kills slowly - you have time to do " ..
            "this properly, but not to detour for glory. Reach Sedgeon before the " ..
            "third case does.")
        commsMeridian_replies(t, comms_source or src)
    end)
    addCommsReply("Restock missiles and probes.", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage(act_restock())
        commsMeridian_replies(t, comms_source or src)
    end)
    addCommsReply("Nothing to report.", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage("Meridian out.")
    end)
end

-- ========================= comms: Coldfield Relay =========================
function commsRelay(t, src)
    local txt
    if not codes then
        txt = [[Coldfield Relay. You made good time. Bad news: Polaris took case C
and went quiet two days ago. We will not open the medical locker to just anyone -
the fever panicked people once already. Bring us Polaris's access codes and we
will hand over cases A and B.]]
    else
        txt = [[Coldfield Relay. Codes received. Cases A and B are on the crane,
ready for your cargo bay.]]
    end
    setCommsMessage(txt)
    commsRelay_replies(t, src)
    return true
end

function commsRelay_replies(t, src)
    addCommsReply("What happened to the Polaris?", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage("She was making the last jump to us and vanished off our " ..
            "scopes near " .. sector_polaris .. ". Two ships are broadcasting there " ..
            "now. One of them answers to her name. Check them both before you " ..
            "trust either.")
        commsRelay_replies(t, comms_source or src)
    end)
    addCommsReply("Load the vaccine cases.", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage(act_load(t))
        commsRelay_replies(t, comms_source or src)
    end)
    addCommsReply("Restock missiles and probes.", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage(act_restock())
        commsRelay_replies(t, comms_source or src)
    end)
    addCommsReply("Nothing to report.", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage("Coldfield out.")
    end)
end

-- ========================= comms: Sedgeon Colony =========================
function commsColony(t, src)
    setCommsMessage([[Sedgeon Colony med unit. Our fever wards are filling.
If you are carrying the vaccine, come alongside and we will run the line across.]])
    commsColony_replies(t, src)
    return true
end

function commsColony_replies(t, src)
    addCommsReply("Deliver the vaccine.", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage(act_deliver())
        commsColony_replies(t, comms_source or src)
    end)
    addCommsReply("How bad is it?", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage("Forty-one in the wards, none critical yet. The fever hits " ..
            "the old and the young first. You were expected yesterday, but you are " ..
            "welcome today.")
        commsColony_replies(t, comms_source or src)
    end)
    addCommsReply("Nothing to report.", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage("Med unit standing by.")
    end)
end

-- ========================= comms: the beacon ships =========================
function commsPolaris(t, src)
    if not polaris_scanned then
        setCommsMessage([[...static... This is Polar- ...static... -can't hold
power and comms at the same time. If you are really Navy, get a scan on us and
we will know the credentials to trust.]])
    else
        setCommsMessage([[Polaris, alive but drifting. Case C is strapped to a
buoy outside - we jettisoned it when the raiders came. Take it, take the codes,
and get the vaccine through.]])
    end
    commsPolaris_replies(t, src)
    return true
end

function commsPolaris_replies(t, src)
    if polaris_scanned and not codes then
        addCommsReply("Credentials verified. Request the access codes.", function(comms_source, comms_target)
            math.abs(0)
            setCommsMessage(act_give_codes("Polaris"))
            commsPolaris_replies(t, comms_source or src)
        end)
    end
    addCommsReply("Status report?", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage("Raider rockets took our reactor. We are safe in our suits " ..
            "for now; Meridian knows to look for the beacon. Case C is adrift close by.")
        commsPolaris_replies(t, comms_source or src)
    end)
    addCommsReply("Nothing to report.", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage("...static...")
    end)
end

function commsDecoy(t, src)
    if not decoy_scanned then
        setCommsMessage("This is Coldfield-2, relay tug. We are private contract, " ..
            "no assistance required. Keep your distance.")
    else
        setCommsMessage([[A laugh, then: "Cute scan, Navy. Come closer and find
out what the transponder was hiding."]])
    end
    commsDecoy_replies(t, src)
    return true
end

function commsDecoy_replies(t, src)
    addCommsReply("Identify yourselves properly.", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage(decoy_scanned and
            "\"We did. You just did not believe it.\"" or
            "Coldfield-2, private contract, no assistance required.")
        commsDecoy_replies(t, comms_source or src)
    end)
    addCommsReply("Nothing to report.", function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage("The channel goes quiet - too smoothly, like a door closing.")
    end)
end

-- ========================= gate actions (shared with probes) =========================
function act_restock()
    local players = active_players()
    if #players == 0 then return "No ship to restock." end
    local n = 0
    for _, p in ipairs(players) do
        pcall(function() p:setWeaponStorage("Homing", 6) n = n + 1 end)
        pcall(function() p:setWeaponStorage("EMP", 2) end)
    end
    print("FR: restocked " .. n .. " ship(s)")
    return "Magazines topped up: six homing, two EMP per ship. Coldfield is a " ..
        "pharmacy, not an armory - make them count."
end

function act_load(t)
    if not codes then
        return "We cannot open the medical locker without Polaris's access codes."
    end
    if not near_or_docked(t, active_players()[1], FR.handover_u) then
        return "Come alongside - the crane only reaches so far - and we will load you."
    end
    if loaded then return "You are already carrying cases A and B." end
    loaded = true
    notify("Crane cycle complete: VACCINE CASES A and B aboard. Final leg to " ..
        sector_colony .. ".", stations.relay)
    print("FR: cases A+B loaded")
    return "Crane cycle complete. Cases A and B are in your bay. Good luck."
end

function act_deliver()
    local colony = stations.colony
    local players = active_players()
    if #players == 0 then return "No ship to receive the line." end
    if not (case_c_aboard and loaded) then
        return "We count " .. cases_aboard_count() ..
            " of three cases aboard. We need all three before we open the line."
    end
    if not near_or_docked(colony, players[1], FR.handover_u) then
        return "Come alongside and hold station - we will run the transfer line across."
    end
    delivered = true
    print("FR: vaccine delivered")
    return "Transfer line secured. Three cases received, cold chain intact. " ..
        "Sedgeon thanks you, Captain."
end

function cases_aboard_count()
    local n = 0
    if loaded then n = n + 2 end
    if case_c_aboard then n = n + 1 end
    return n
end

function act_give_codes(how)
    if codes then return "The codes are already with your relay officer." end
    give_codes(how)
    return "Codes transmitted. Coldfield will open the medical locker when you " ..
        "reach them."
end

function give_codes(how)
    if codes then return end
    codes = true
    -- Order-proof: the crew may hail the courier before ever reaching the
    -- relay (phase 1), so bump from any pre-load phase, not just phase 2.
    if phase == 1 or phase == 2 then
        phase = 3
        notify("Access codes accepted. Return to Coldfield Relay and load " ..
            "cases A and B. (" .. tostring(how) .. ")", stations.relay)
    end
    print("FR: codes granted via " .. tostring(how) .. " (phase now " .. phase .. ")")
end

-- ========================= raids =========================
function spawn_raiders(group, tag, x, y, n, order_fn)
    for i = 1, n do
        local s = CpuShip():setTemplate("Adder MK4"):setFaction("Exuari")
            :setPosition(x + U(0.8) * i, y + U(0.5) * (i % 2))
        s:setCallSign("Raider " .. tag .. "-" .. i)
        if order_fn then order_fn(s, i) end
        table.insert(group, s)
    end
    print("FR: spawned " .. n .. " raiders (" .. tag .. ")")
end

-- ========================= init =========================
function init()
    print("FR: init begin")

    player = PlayerSpaceship():setFaction("Human Navy"):setTemplate("Atlantis")
    player:setPosition(0, 0):setCallSign("Epsilon")

    stations.meridian = mk_station("Meridian", "Medium Station", "Human Navy", U(-20), 0, commsMeridian)
    stations.relay    = mk_station("Coldfield", "Medium Station", "Human Navy", U(35), U(5), commsRelay)
    stations.colony   = mk_station("Sedgeon", "Medium Station", "Human Navy", U(55), U(60), commsColony)

    polaris = build_polaris()
    decoy = build_decoy()

    spawn_case_c()

    -- Scenery on the final leg: one nebula to cross, a small rock cluster off
    -- the lane. Budget: a handful of objects, logged (pitfall 12).
    Nebula():setPosition(U(48), U(32))
    local asteroids = 0
    for i = 1, 8 do
        pcall(function()
            Asteroid():setPosition(U(41) + random(-2, 2) * 1000, U(40) + random(-2, 2) * 1000)
            asteroids = asteroids + 1
        end)
    end

    sector_polaris = getSectorName(U(60), U(-8))
    sector_colony  = getSectorName(U(55), U(60))

    pcall(function() player:addToShipLog("Meridian orders: vaccine run to Sedgeon Colony. Courier Polaris missing with case C.", "yellow") end)
    notify("Meridian to Epsilon: Sedgeon Colony has a fever outbreak. The " ..
        "vaccine is due - cases A and B at Coldfield Relay, case C with the " ..
        "courier Polaris, who has gone quiet. Get underway.", stations.meridian)

    print("FR: world seeded: stations=3 beacons=2 case=1 nebulae=1 asteroids=" ..
        asteroids .. " difficulty=" .. DIFFICULTY)
    print("FR: init complete")
end

-- ========================= update =========================
function update(delta)
    clock = clock + delta
    local players = active_players()
    if #players > 0 then ever_had_players = true end
    pump_messages()
    watch_cleared()          -- combat bookkeeping settles even after victory
    if done then return end
    ensure_ftl(players)

    -- Story-mode buff for late joiners too (no setBeamDamage in this pin).
    for _, p in ipairs(players) do
        if p:isValid() and STORY_MODE and not p.fr_buffed then
            p.fr_buffed = true
            local n = 0
            for i = 0, 15 do
                local ok, arc = pcall(p.getBeamWeaponArc, p, i)
                if ok and arc and arc > 0 then
                    local _, dir = pcall(p.getBeamWeaponDirection, p, i)
                    local _, rng = pcall(p.getBeamWeaponRange, p, i)
                    local _, cyc = pcall(p.getBeamWeaponCycleTime, p, i)
                    pcall(p.setBeamWeapon, p, i, arc, dir, rng, cyc, 5000)
                    n = n + 1
                end
            end
            print("FR: story buff applied to " .. tostring(p:getCallSign()) ..
                " (" .. n .. " beams)")
        end
    end

    watch_scans(players)
    watch_trap(players)
    watch_wave(players)
    case_c_watch()
    watch_override()
    phase_check(players)
end

-- Science watches: flip the scan bookkeeping once, then say so once.
function is_scanned(obj, players)
    if obj == nil or not obj:isValid() then return false end
    if obj.fr_scanned then return true end
    for _, p in ipairs(players) do
        local ok, r = pcall(function() return obj:isScannedBy(p) end)
        if ok and r then return true end
    end
    return false
end

function watch_scans(players)
    if not polaris_scanned and is_scanned(polaris, players) then
        mark_scanned("polaris")
    end
    if not decoy_scanned and is_scanned(decoy, players) then
        mark_scanned("decoy")
    end
end

-- Shared bookkeeping: called from update()'s poll (real science scans) and
-- synchronously from probe_scan (the headless stand-in) so the state is
-- consistent the moment either path flips.
function mark_scanned(name)
    if name == "polaris" and not polaris_scanned then
        polaris_scanned = true
        notify("Science: that is Polaris, all right - breach on the reactor ring, " ..
            "life signs in suits. Her medical locker is still sealed.", stations.relay)
        print("FR: polaris scanned")
    elseif name == "decoy" and not decoy_scanned then
        decoy_scanned = true
        notify("Science: the 'tug' COLDFIELD-2 is Exuari-built. The transponder " ..
            "is fake. Treat it as hostile.", stations.relay)
        print("FR: decoy scanned")
    end
end

-- The trap: come too close to the decoy before knowing better and the bait
-- springs. Polling-watched, so the driver may also wipe the group hooklessly.
function watch_trap(players)
    if ambush_sprung or phase < 2 then return end
    if decoy == nil or not decoy:isValid() then return end
    local dx, dy = decoy:getPosition()
    for _, p in ipairs(players) do
        if d2(p, decoy) < U(FR.beacon_u) ^ 2 then
            ambush_sprung = true
            spawn_raiders(groups.ambush, "A", dx, dy, 2, function(s)
                local tgt = players[1]
                if tgt then s:orderAttack(tgt) end
            end)
            notify("It is a trap! Two raiders just lit up behind that 'tug' - " ..
                "the transponder never was Coldfield's.", stations.relay)
            pcall(function() player:addToShipLog("COLDFIELD-2 was bait. Raiders engaging.", "red") end)
            return
        end
    end
end

-- Final raiders: they go for the colony, not for you - you are the escort.
function watch_wave(players)
    if wave_spawned or phase < 4 then return end
    for _, p in ipairs(players) do
        if d2(p, stations.colony) < U(FR.wave_u) ^ 2 then
            wave_spawned = true
            local cx, cy = stations.colony:getPosition()
            spawn_raiders(groups.wave, "S", cx + U(6), cy - U(4), 2, function(s)
                s:orderAttack(stations.colony)
            end)
            notify("Sedgeon control: two raider signatures inbound on the colony. " ..
                "Whatever you brought us, they want it stopped.", stations.colony)
            pcall(function() player:addToShipLog("Raiders inbound on Sedgeon. Weapons free.", "red") end)
            return
        end
    end
end

-- Anti-softlock: if the crew never gets the codes (Polaris destroyed, decoy
-- never triaged), the relay's bureaucracy produces an override key in time.
function watch_override()
    if codes or phase < 2 or codes_deadline == nil then return end
    if clock > codes_deadline then
        give_codes("relay override")
        notify("Coldfield Relay: headquarters found an override key in the " ..
            "paperwork. The medical locker is open - we should not have made you " ..
            "chase a courier for it.", stations.relay)
    end
end

-- ========================= phase machine =========================
function phase_check(players)
    if phase == 1 then
        for _, p in ipairs(players) do
            if d2(p, stations.relay) < U(FR.arrival_u) ^ 2 then
                -- Order-proof: a crew that triaged the beacons before arriving
                -- already holds the codes; skip straight to the load phase.
                if codes then
                    phase = 3
                    print("FR: phase 3 (load) - arrival after codes already granted")
                else
                    phase = 2
                    codes_deadline = clock + FR.override_s
                    notify("Coldfield Relay: you made good time. Bad news about " ..
                        "Polaris - hail us, or just look at the beacons near " ..
                        sector_polaris .. ". Two ships are broadcasting there. One lies.",
                        stations.relay)
                    pcall(function() player:addToShipLog("Arrived Coldfield Relay. Polaris missing near " .. sector_polaris .. ".", "yellow") end)
                    print("FR: phase 2 (triage)")
                end
                break
            end
        end
    elseif phase == 3 then
        if loaded then
            phase = 4
            notify("Coldfield Relay: all three cases accounted for. Final leg to " ..
                "Sedgeon, " .. sector_colony .. ". Watch the dust lane on the way in.",
                stations.relay)
            pcall(function() player:addToShipLog("Vaccine aboard. Final leg: Sedgeon Colony.", "green") end)
            print("FR: phase 4 (deliver)")
        end
    elseif phase == 4 and delivered then
        done = true
        pcall(function() player:addToShipLog("Vaccine delivered. Sedgeon thanks the crew of the Epsilon.", "green") end)
        notify("Meridian to Epsilon: vaccine delivered and a courier rescued on " ..
            "your first run. The fleet could use more ships like yours.", stations.meridian)
        victory("Human Navy")
        print("FR: mission complete")
        return
    end

    if ambush_sprung and not ambush_done and #groups.ambush > 0 and all_dead(groups.ambush) then
        mark_ambush_cleared()
    end
    if wave_spawned and not wave_done and #groups.wave > 0 and all_dead(groups.wave) then
        mark_wave_cleared()
    end

    -- Sedgeon gone (wave the crew never intercepted, friendly fire, GM
    -- removal): delivery is impossible, so defeat must be declared whatever
    -- killed it - not only when the wave was spawned.
    if not done and not delivered and not stations.colony:isValid() then
        done = true
        notify("Sedgeon has gone dark. Without the colony there is no one left to cure.", stations.meridian)
        victory("Exuari")
        print("FR: colony lost")
        return
    end

    if ever_had_players and #players == 0 then
        done = true
        notify("No ships remain. Sedgeon's fever will have to wait for another crew.", stations.meridian)
        victory("Exuari")
        print("FR: crew lost")
    end
end

-- Combat bookkeeping that must settle no matter what: update() keeps calling
-- this even after victory, so the last raider's death is still logged.
function watch_cleared()
    if ambush_sprung and not ambush_done and #groups.ambush > 0 and all_dead(groups.ambush) then
        mark_ambush_cleared()
    end
    if wave_spawned and not wave_done and #groups.wave > 0 and all_dead(groups.wave) then
        mark_wave_cleared()
    end
end

function mark_ambush_cleared()
    ambush_done = true
    notify("Ambush cleared. Coldfield Relay logs your gunnery with gratitude.", stations.relay)
    pcall(function() player:addToShipLog("Ambush raiders destroyed.", "green") end)
    print("FR: ambush cleared")
end

function mark_wave_cleared()
    wave_done = true
    notify("Sedgeon control: raiders down before they reached the wards. Nicely flown.", stations.colony)
    pcall(function() player:addToShipLog("Colony raiders destroyed.", "green") end)
    print("FR: wave cleared")
end

-- ========================= console helper (no GM menu in this scenario) ======
function gm_status()
    print(("FR-STATUS phase=%s codes=%s loaded=%s caseC=%s delivered=%s " ..
        "ambush=%s/%s wave=%s/%s players=%d t=%.1f"):format(
        tostring(phase), tostring(codes), tostring(loaded), tostring(case_c_aboard),
        tostring(delivered), tostring(ambush_sprung), tostring(ambush_done),
        tostring(wave_spawned), tostring(wave_done), #active_players(), clock))
end

-- ========================= test hooks =========================
-- Read-mostly and idempotent; each one shares bookkeeping with the real path
-- (pitfall 13: a headless hull never moves, collides, or scans).
function probe_state()
    gm_status()
    return phase
end

function probe_warp_to(x, y)
    for _, p in ipairs(active_players()) do p:setPosition(x, y) end
    print("FR-PROBE players warped to " .. tostring(x) .. "," .. tostring(y))
end

-- Scan stand-in: flips the same scan bookkeeping the science client would.
function probe_scan(name)
    local obj = (tostring(name) == "polaris") and polaris or
                (tostring(name) == "decoy") and decoy or nil
    if obj == nil or not obj:isValid() then return "missing" end
    pcall(function() obj:setScanStateByFaction("Human Navy", "fullscan") end)
    obj.fr_scanned = true
    mark_scanned(tostring(name))    -- synchronous: same bookkeeping as the real path
    return "scanned"
end

function probe_part(name)
    if tostring(name) == "case" then
        if case_c_aboard then return "carried" end
        if case_c_obj ~= nil and case_c_obj:isValid() then return "adrift" end
        return "missing"
    end
    return "unknown"
end

-- Pickup stand-in (collision never fires headless); same bookkeeping.
function probe_pickup(name)
    if tostring(name) ~= "case" then return "unknown" end
    if case_c_aboard then return "carried" end
    if case_c_obj == nil or not case_c_obj:isValid() then return "missing" end
    local x, y = case_c_obj:getPosition()
    probe_warp_to(x, y)
    case_c_obj:destroy()
    collect_case_c("probe")
    return "carried"
end

-- destroy() never fires onDestruction; safe here because both raider groups
-- are watched by polled all_dead checks, never by hooks.
function probe_kill_group(name)
    local g = groups[tostring(name)] or {}
    local n = 0
    for _, s in ipairs(g) do
        if s:isValid() then s:destroy() n = n + 1 end
    end
    print("FR-PROBE killed " .. n .. " in " .. tostring(name))
    return n
end

-- Codes stand-in for a run that skips the triage entirely; shares give_codes.
function probe_codes()
    give_codes("probe")
    return codes
end
