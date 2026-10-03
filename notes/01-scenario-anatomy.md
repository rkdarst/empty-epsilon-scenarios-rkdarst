# 01 — Scenario anatomy (verified against `src/scenarioInfo.cpp` @ master)

## Discovery

- The game loads **every file matching `scenario_*.lua`** from all content
  paths (`findResources("scenario_*.lua")`), sorts by filename, removes
  duplicates. First match by sorted name wins for duplicates.
- Content path priority (first hit wins):
  1. active mod overlay (`mod=` preference, `~/.emptyepsilon/resources/mods/`)
  2. install dir `scripts/` (next to the binary / package data dir)
  3. **`~/.emptyepsilon/scripts/`** (fallback path, `$HOME` must be set/writable)
  4. compile-time `RESOURCE_BASE_DIR` paths (deb installs)
- The name shown in menus defaults to the filename minus `scenario_` and
  `.lua` (`filename.substr(9, -4)`) unless a `-- Name:` header is given.

## Header grammar

The file starts with `--` comment lines; parsing stops at the first non-`--`
line. Kinds of lines:

```lua
-- Name: My Scenario                -- display name (translated via locale .po)
-- Description: One-line summary.   -- shown in the scenario browser
---                                 -- a line starting with --- appends the
--- More description text.          -- rest of the description (multi-para)
-- Author: Some Body                -- optional
-- Type: Mission                    -- menu category; repeatable for several
                                     -- categories. Missing => "Unknown" (warning in log)
-- Setting[EnemyCount]: How many foes to spawn.   -- declares a setting
-- EnemyCount[Easy]: A gentle day.                -- option lines for it
-- EnemyCount[Hard|Default]: A hard day.          -- "|Default" marks the default option
-- Variation[Hard]: Rebalanced for veterans.      -- shortcut: adds a value to the
                                     -- built-in "variation" setting (auto-created,
                                     -- default option "None")
```

Verified quirks:

- `Setting[Key]` **must appear before** its option lines — options are attached
  to an already-declared setting; otherwise you get
  `LOG(WARNING) "Unknown scenario meta data"`.
- Keys are matched case-insensitively (`name`, `type`, `category`, ...);
  setting keys/options keep case.
- Values are translatable through `locale/<scenario_file>.<lang>.po`
  (see repo wiki "Translation and Localization").
- Read options at runtime with `getScenarioSetting("EnemyCount")` → string.
  From headless/CLI they can be forced with
  `scenario_settings=EnemyCount=Hard;Other=Val` (semicolon list).

## Script contract

```lua
function init()          -- run once when the scenario starts; build the world
function update(delta)   -- run every tick (~30 Hz); delta = seconds
```

There is no `onMissionStart`; `init()` is it. Finish with
`victory("Human Navy")` / `victory("Exuari")`. Other useful globals observed
in shipped scenarios: `random(a, b)`, `allowNewPlayerShips(false)`,
`_("i18n.key", "fallback text")` for translatable messages.

## API essentials seen in shipped scenarios

(Confirm exact signatures in `vendor/**/script_reference.html`.)

- Constructors (all chainable via `:setter` returning self):
  `PlayerSpaceship()`, `CpuShip()`, `SpaceStation()`, `Asteroid()`,
  `VisualAsteroid()`, `Mine()`, `Nebula()` (+ `BlackHole`, see reference)
- Common: `:setFaction("Human Navy"|"Exuari"|"Independent"|"The Society"|"System Security")`,
  `:setTemplate("Atlantis")` (see `scripts/shiptemplates/`),
  `:setPosition(x, y)`, `:setRotation(deg)`, `:setCallSign("Epsilon")`,
  `:setScanned(true)`, `:setHull(n)`, `:setShieldsMax(f, r)`
- Orders: `:orderIdle()`, `:orderRoaming()`, `:orderAttack(obj)`,
  `:orderMove(x, y)`, `:orderDefendTarget(obj)`, `:orderDock(obj)`
- Queries: `:isValid()`, `:getPosition()`, `:isDocked(station)`,
  `:getCallSign()`, `:hull()` etc.
- Comms: `obj:sendCommsMessage(target, _("key", [[free text]]))`,
  `obj:setCommsScript(filename)` / `obj:setCommsFunction(callback)`,
  free-form `obj.comms_data = {...}` table consumed by
  `scripts/comms_station.lua` / `comms_ship.lua` (e.g.
  `comms_data = {supplydrop = "neutral", weapons = {Mine = "friend"}}`).

## Mission-state pattern (from `scenario_05_beacon.lua`)

Rather than many timers, shipped missions keep a state function pointer:

```lua
mission_state = mission_step_one      -- in init()/transitions
function update(delta)
    if <fail condition> then victory("Exuari"); return end
    if mission_state ~= nil then mission_state(delta) end
end
```

Timers are usually plain countdown variables decremented with `delta`
(`mission_timer = mission_timer - delta`). The reference also documents
`setTimer`-style helpers — check it before hand-rolling.

## Example scenarios in the release (`vendor/**/scripts/`)

`scripts/README.md` upstream indexes them by number:

| File | What to learn |
|---|---|
| `scenario_00_basic.lua` | minimal spawn setup |
| `scenario_02_surrounded.lua`, `scenario_03_waves.lua` | simple combat loops |
| `scenario_05_beacon.lua` | **the official website tutorial**: multi-stage mission, comms, victory logic |
| `scenario_08_atlantis.lua` | starter skirmish |
| `scenario_10_empty.lua` | empty sandbox + GM "Copy Scenario" prototyping trick |
| `scenario_2x_*.lua` (training, liberation, surf) | training/text-heavy scenarios |
| `scenario_4x/5x_*.lua` | community scenarios: outposts, carriers, races, capture-the-flag... |
| `scenario_81_pvp.lua` | PvP with several player ships |
| `scenario_99_battlefield.lua` | `Setting[...]` usage + mass spawning |
| `tutorial/`, `utils.lua`, `ee.lua`, `luax.lua` | server-side Lua libs you may `require` |

## Prototyping trick

Load `scenario_10_empty.lua` in the game, move/place things with the GM
screen, press **"Copy Scenario"** — the current world is serialized as Lua
code you can paste into `init()`.
