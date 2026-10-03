-- Name: Template Scenario
-- Description: A skeleton scenario - copy, rename, and edit.
---
--- The description continues on lines starting with three dashes.
--- Use this to explain the setup the crew starts with.
-- Author: (your name)
-- Type: Mission
-- Setting[EnemyStrength]: How strongly the enemy is represented.
-- EnemyStrength[Light]: A couple of scout ships.
-- EnemyStrength[Standard|Default]: A balanced patrol force.
-- EnemyStrength[Heavy]: A serious strike force.

--- Scenario
-- @script scenario_90_template

-- init() is called once when the scenario is started. Build the world here.
function init()
    -- The player ship.
    player = PlayerSpaceship():setFaction("Human Navy"):setTemplate("Atlantis")
    player:setPosition(10000, 10000):setCallSign("Epsilon")

    -- Friendly infrastructure.
    main_station = SpaceStation():setTemplate("Medium Station"):setFaction("Human Navy")
    main_station:setPosition(-20000, 20000):setCallSign("Base-1")

    -- Terrain.
    Nebula():setPosition(0, 0)
    for n = 1, 20 do
        Asteroid():setPosition(random(-15000, 15000), random(-15000, 15000))
    end

    -- Enemies, scaled by the scenario setting chosen in the menu
    -- (see the Setting[EnemyStrength] header lines above).
    enemies = {}
    local strength = getScenarioSetting("EnemyStrength")
    if strength == "" then strength = "Standard" end   -- headless default

    if strength == "Light" then
        spawnEnemyAt("Adder MK5", -5000, -5000)
    elseif strength == "Heavy" then
        spawnEnemyAt("Phobos T3", -5000, -5000)
        spawnEnemyAt("Phobos T3", -6000, -5000)
        spawnEnemyAt("Starhammer II", -7000, -5000)
    else
        spawnEnemyAt("Adder MK5", -5000, -5000)
        spawnEnemyAt("Phobos T3", -6000, -5000)
    end

    -- Opening transmission (i18n key + fallback text).
    main_station:sendCommsMessage(
        player,
        _("intro", [[Epsilon, we have confirmed hostile activity in this sector.
Investigate and neutralize the enemy force.]]))

    -- Mission state machine (see notes/01-scenario-anatomy.md).
    mission_state = missionActive
    mission_timer = 120
end

-- update(delta) runs every game tick; delta is elapsed seconds.
function update(delta)
    -- Global fail/win checks first.
    if not player:isValid() then
        victory("Exuari")
        return
    end

    if mission_state ~= nil then
        mission_state(delta)
    end
end

function missionActive(delta)
    -- Example: reinforcements on a countdown timer.
    mission_timer = mission_timer - delta
    if mission_timer < 0 then
        mission_timer = 120
        local x, y = player:getPosition()
        table.insert(enemies, spawnEnemyAt("MT52 Hornet", x + 8000, y))
    end

    -- Win when all tracked enemies are gone.
    local all_dead = true
    for _, enemy in ipairs(enemies) do
        if enemy:isValid() then
            all_dead = false
            break
        end
    end
    if all_dead then
        main_station:sendCommsMessage(player, _("clear", [[Sector is clear. Well done, Epsilon!]]))
        victory("Human Navy")
        mission_state = nil
    end
end

-- Helper: spawn a hostile ship at a position and track it. Returns the ship.
function spawnEnemyAt(template, x, y)
    local ship = CpuShip():setTemplate(template):setFaction("Exuari"):setPosition(x, y):orderRoaming()
    table.insert(enemies, ship)
    return ship
end

