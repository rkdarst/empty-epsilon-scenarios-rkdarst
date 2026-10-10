> **Status:** promoted into the package as
> [ee-skills/reference/sensors-and-visibility.md](../ee-skills/reference/sensors-and-visibility.md)
> and [ee-skills/reference/geometry-and-units.md](../ee-skills/reference/geometry-and-units.md),
> with recipes in [ee-skills/patterns/](../ee-skills/patterns/). This note stays as
> the original measurement record (it is where the numbers came from).

# 06 — Sensors, visibility and geometry (engine facts we verify in code)

Everything here was read out of the EE-2024.12.08 source (`src/`) or the
shipped data scripts, and then confirmed by behaviour in a headless run. When a
scenario needs "the players must not see X yet", this is the page to check
before inventing a mechanism.

## Scale

| Quantity | Script units | Notes |
|---|---|---|
| 1 in-game unit ("U" on the player's ruler) | 1000 | scenario helper `U(u) = u * 1000` |
| Sector | 20000 × 20000 = 20 × 20 u | `sectorToXY("E3")` returns the lower-left corner, centre = +10000 |
| Small station (`space_station_4`) | radius 300 = 0.3 u | `scripts/model_data.lua`, collision box 400 × 400 |
| Medium station (`space_station_3`) | radius 1000 = 1.0 u | collision box 1200 × 1000 |
| Large station (`space_station_2`) | radius 1300 = 1.3 u | |

So a station-to-station "hand over" that uses a fixed 1 u bubble is *inside* a
Medium station's hull: size the interaction after the hull, e.g.
`handover_u = max(1.0, hull + 0.4)`, and eject crates at `hull + 0.35`.

## Radar and nebulae

Defaults straight out of `script_reference.html` (2024.12):

| Radar | Default | Used by |
|---|---|---|
| Long-range | 30000 = 30 U | science + operations screens; CpuShip target detection |
| Short-range | 5000 = 5 U | helm/weapons/single-pilot screens; **the shared radius on the relay screen for friendly ships and stations**; how far *into* a nebula a ship can still detect |

* A `Nebula` is terrain with a **5 U radius** that "blocks long-range radar, but
  not short-range radar", hiding objects inside it *and* behind it.
* So a nebula is a "you cannot see through this" tool, never invisibility: fly
  within 5 U and it is painted anyway. Nebulae are replicated per client
  (only clouds near a client are sent to it), which is why far-away clouds show
  up on the GM screen only.
* `SpaceStation`/`CpuShip` also carry `setShortRangeRadarRange` (default 5000):
  what the object itself detects and re-broadcasts into the relay picture.
  Zeroing it makes a hidden object locally deaf as well as quiet.

## Faction telemetry — the one that bites

`playerSpaceship.cpp` builds the player's contact list from
`SpaceObject::getObjectsInSpace()`: an object is shown if

1. it is inside the player's own radar range, **or**
2. `getFaction() == playerFaction` — same-faction objects are *always* listed,
   regardless of distance or nebulae (the in-game comms text says the same:
   "friendly units share their sensor data with you"; shipped example
   `scripts/comms/comms_scenario_utility.lua` states it too).

Consequences:

* A **hidden Human Navy station is not hidden at all** — it shows as a friendly
  contact at any range, and its 5 u telemetry bubble reveals the neighbourhood.
* To hide a friendly outpost: spawn it as `Independent`, then flip it to
  `Human Navy` when a player gets close enough to have seen it anyway. The
  Kraylor are only at war with the Human Navy, so an Independent station is left
  alone by both sides (`scripts/factionInfo.lua`).
* A hidden station must also not be a *docking target* the players can already
  select; neutrality handles that too.

## Destruction hooks

`onDestruction(callback)` is installed from `SpaceObject::takeHullDamage()` only
— it fires when hull damage kills the object. `SpaceObject::destroy()` (script
call, GM "remove", scenario cleanup) removes the object **without** running the
callback, and inside a real hook the dying object can still answer
`isValid() == true`.

Therefore any "X drops Y when destroyed" logic must be:

1. hook = fast path (correct position, correct killer credit), **and**
2. a polled watcher over the same group ("is the whole group gone and Y still
   unaccounted for? then drop it, once, after a grace period").

Keep the drop bookkeeping in script-side tables, not on the dying object:
custom per-object fields die with it ([04-state-and-driving.md]).

## Artifacts (cargo containers)

* Artifacts are created "fully scanned": there is **no** scan-state progression
  for them (`artifact.cpp` has no scan state machine, unlike
  `spaceShip.cpp:setScannedState`). A reveal keyed to
  `setDescriptionForScanState("fullscan", ...)` alone may never surface.
* So write the *current story text* into the base description **and** all three
  scan states (`notscanned`, `simplescan`, `fullscan`) every time the state
  changes; whichever the UI consults, it reads the same thing.
* Pickup is a physical overlap: `allowPickup(true)` + `onPickUp`. A crate
  spawned inside a station's collision box can never be reached — hence the
  ejection geometry above.

## Weapon storage

`getWeaponStorage(name)` / `getWeaponStorageMax(name)` / `setWeaponStorage(name,
value)` on any Ship. "Refill homing missiles" is exactly one call:
`ship:setWeaponStorage("Homing", ship:getWeaponStorageMax("Homing"))`.
Templates without tubes return max 0 (`scripts/shipTemplates/*.lua` — e.g. the
Phobos M3P carries 10 homing missiles), so always test for `max == 0` and say
so rather than staying silent.

## Scenario 40 check-list (what each fact is used for)

| Fact | Where it shows up in `scenario_40_lostcluster.lua` |
|---|---|
| friendly objects always visible | `hide_station()` / `station_reveal()`, `LC_FIND_U = 6` |
| nebula = long-range shadow only | Turku nebula ring, "sweep with short-range sensors" tip |
| hookless deaths | `mk_drop_watch()` + `drop_watch_run()`, freighter slot mirror |
| artifact scan quirk | `lc_container_text()` writes base + 3 scan states |
| station collider sizes | `STATION_HULL_U`, `handover_u()`, `eject_pos()` |
| weapon storage API | `act_replenish()` (free homings) |
