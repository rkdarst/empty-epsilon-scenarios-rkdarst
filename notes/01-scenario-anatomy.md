> **Status:** project note, still accurate. The canonical, task-oriented version of
> this material is now in the skills package: header grammar in
> [ee-skills/authoring/HEADER-FORMAT.md](../ee-skills/authoring/HEADER-FORMAT.md),
> the callback/loading model in
> [ee-skills/reference/api-and-scripting.md](../ee-skills/reference/api-and-scripting.md).
> Kept as the detailed source-trace record.

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

For the broader picture — execution model, state-storage cells, and the
three driving idioms — see [04-state-and-driving.md](04-state-and-driving.md).


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

## Comms & artifact pitfalls (learned the hard way, 2026-10)

- **`comms_target` is NOT reliably set for `setCommsFunction` dialogs.**
  The 2024.12 reference: *"Comms scripts pass globals `comms_target` and
  `comms_source`. Comms functions pass only `comms_source`"* (and the
  `setCommsFunction` entry is flagged "TODO: confirm"). Dereferencing
  `comms_target` inside a comms *function* (or its `addCommsReply`
  callbacks) can be nil and kills the dialog with a Lua error mid-hail.
  Bind the target via closure at registration time
  (`st:setCommsFunction(function(src) return commsX(st, src) end)`) and
  let every `addCommsReply` callback take the documented two parameters
  `(comms_source, comms_target)` with an upvalue fallback.
- **`ScriptSimpleCallback` requires upvalue #1 of the callback to be a
  table** (the globals table): a callback whose first referenced
  upvalue is an object/userdata fails at *registration* with
  `??[convert<ScriptSimpleCallback>::param] Upvalue 1 of function is not
  a table`. Start such closures with `math.abs(0)` — the documented
  trick — so the globals table is captured first.
- **`sendCommsMessage` returns false and drops the message** when the
  target player is currently in a comms dialog. Queue notifications
  and retry from `update()` instead of firing once.
- **Artifacts never advance scan states**: "most SpaceObjects directly
  switch to fully scanned, only SpaceShips go through all the states".
  A "scan to reveal" mechanic on an `Artifact` is unreliable — flip all
  descriptions from the script when the player gets close instead.
- **`sendCommsMessage` displays the *sender object* it was called on** —
  route each message through the station that is actually speaking or
  the UI attributes everything to whoever you hardcoded.
- **Container spawns at station + random(±3u) can be inside the
  station's collision volume**, and artifact pickup is collision-based.
  Spawn pickups on a ring (5u+) outside the hull.
- **`PlayerSpaceship:setCommsFunction()` works** (verified 2024.12): you
  can put a comms dialog on player ships so other players can hail them
  (used for ship-to-ship part transfers). Register from `update()` for
  late joiners / GM respawns, guarded by a `ship.lc_watched` flag —
  `init()` only sees the first player ship, and an unhooked respawn would
  silently keep (or lose) script-tracked mission cargo.
- **Clicking a reply clears all replies, then runs the callback, and
  every `setCommsMessage` inside a callback REPLACES the text**
  (`commsScriptInterface.cpp`, 2024.12). A reply callback that renders an
  action result and then re-invokes the menu renderer therefore shows
  ONLY the menu — the result is silently wiped and the click looks dead.
  Structure dialogs as page function (sets the text once) + a separate
  `*_replies` function (only adds choices); result pages call
  `setCommsMessage(result)` + `*_replies`, never the page function.

## Wormhole physics (verified from `wormHole.cpp` @ EE-2024.12.08)

- A mouth **drags every weighted object within 2.5U** toward its center
  (as a velocity: `v += dir * R²·50/d²`), including stations and
  containers; AI pathfinding avoids mouths by 2U on its own.
- Anything reaching **within ~0.18U of the center is teleported** to
  `setTargetPosition()` **± 500u random spread**; exit velocity is kept.
- There is **no re-entry cooldown** (upstream `// TODO: escaping is
  impossible`). Pointing two wormholes at **each other's centers is a
  designed infinite ping-pong**: the exit spread lands the traveler
  inside the far mouth's pull zone. Aim each `setTargetPosition` at a
  point **>= 3U beyond** the partner (or at a plain spot in space, as
  the official examples do).
- `WormHole:onTeleportation(function(wormhole, obj)` IS available in
  2024.12 (in the reference; not in some older examples) — it fires
  *after* the engine places the traveler, so the script can
  `obj:setPosition()` to override the drop: the only way to implement a
  per-ship transit cooldown. It is a `ScriptSimpleCallback` — the
  callback needs the `math.abs(0)` upvalue trick like `addCommsReply`.
- Wormholes are plain `SpaceObject`s: `isValid()`, `destroy()`, and
  custom script fields (`wh.lc_something`) all work.

