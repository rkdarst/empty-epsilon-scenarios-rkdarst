# 04 — How scenarios run and where state lives

Compiled 2026-10 from a census of the 35 shipped `scenario_*.lua`: the
engine calls nothing at scenario level except `init()`/`update()` — no
top-level event handlers exist in any shipped scenario (the single
top-level `onError` in `scenario_59_border.lua` is that file's own
`xpcall` trap, not an engine callback). Helper functions are of course
defined at top level; they're just never called by the engine.
Sources: `script_reference.html` @ EE-2024.12.08; line refs under
`vendor/EE-2024.12.08/usr/local/share/emptyepsilon/scripts/`.
Provenance caveats at the end.

## Execution model

- One Lua environment per running scenario on the server. Two lifecycle
  entry points: `init()` runs once at start; `update(delta)` runs every
  tick (delta in seconds). Timers are numbers decremented by `delta`,
  there is no scheduler.
- **There are no scenario-level events.** `onPlayerJoin`, `onMissionStart`
  etc. do not exist; everything must be expressed as polling in `update()`
  or as hooks attached to a concrete object.
- The accurate model: **the game world is the authoritative state
  machine; the script is a thin reactive controller** that seeds the world
  in `init()`, compares world-queries against expectations in `update()`,
  and pokes the world (spawn/warp/message/win/lose).
- Everything is event-*sorted*: hooks and `update()` run sequentially;
  script code never runs concurrently with itself.

## Event hooks that do exist (per-object, from the 2024.12 reference)

`SpaceObject:onDestroyed(cb)`, `onTakingDamage(cb)`, `onCollision(cb)`,
`onGMClick(cb)`, `onNewPlayerShip(cb)`, `onTeleportation(cb)` (WormHole),
`onPickUp(cb)`, `onArrival(cb)`, `onExpiration(cb)`, `onNext(cb)` (jump),
`onProbeLaunch/onProbeLink/onProbeUnlink(cb)`, plus the comms pair
`setCommsFunction`/`setCommsScript` (semantics in note 01). All take a
`ScriptSimpleCallback` and are attached to one specific object — shipped
scenarios use them sparingly and prefer polling.

## Where state can live

| Store | Lives in | Survives tick | save/load | restart | Example |
|---|---|---|---|---|---|
| **The world itself** (derive: counts, cargo, distance) | engine objects | ✅ | ✅ | ✅ | `scenario_03_waves.lua:236-251` recounts `enemy:isValid()` per tick instead of a "wave cleared" flag |
| **Per-object custom fields** (`station.probe_fail_reason`, `ship.comms_data = {}`) | the object's script storage | ✅ | ✅ saved *with the object*, dies with it | ❌ | `comms_station.lua` keeps the whole dialog state in `ship.comms_data` |
| **Data globals** (`goods = {}`, `stationList = {}`) | the script env table | ✅ | ✅ for plain data | ❌ | `scenario_53_escape.lua:25-33` |
| **Function-valued globals** (state = a function) | script env | ✅ | ⚠️ **nil after load** | ❌ | `scenario_53_escape.lua:3877-3891` |
| **`getScriptStorage()`** key/value JSON at `~/.emptyepsilon/scriptstorage.json` | disk | ✅ | ✅ | ✅ | (documented; unused by shipped scenarios) |

Save/load rule of thumb: plain data in globals and object fields survives;
functions and closures do **not** — see the `plotX ~= nil` fingerprint
below. Recheck upstream before relying on edge cases (see note 03).

## Three idioms for driving a mission

### A. Flag + poll (the workhorse — use this by default)

Coarse phase scalar + booleans; `update()` derives progress from world
queries every tick. `scenario_03_waves.lua:223-252`:

```lua
function update(delta)
    if spawnWaveDelay ~= nil then                 -- timer = data, not a scheduler
        spawnWaveDelay = spawnWaveDelay - delta
        if spawnWaveDelay < 5 then globalMessage(math.ceil(spawnWaveDelay)) end
        if spawnWaveDelay < 0 then spawnWave(); spawnWaveDelay = nil end
        return
    end
    -- ... recount isValid() over enemyList/friendlyList ...
    if enemy_count == 0 then spawnWaveDelay = 15.0 end   -- transition = world predicate
end
```

Self-healing: if a GM destroys/respawns something, the predicate
re-evaluates and reality wins.

### B. Timed script / timeline

`mission_time = mission_time + delta; if mission_time > 120 and phase == 1`
— linear cutscene pacing. Simple, but fragile when players are elsewhere.
Use only for flavor beats.

### C. Function-as-state (true FSM, Lua dialect — least save-safe)

State *is* a function variable; transitions reassign it
(`scenario_53_escape.lua`, 71 top-level functions, one per story beat):

```lua
-- scenario_53_escape.lua:3877-3891, update() dispatches to the current plot
if plotSuffocate ~= nil then plotSuffocate(delta) end
if plot1 ~= nil then plot1(delta) end
```

The `~= nil` guards are a save/load fingerprint: function values cannot be
serialized, so after loading a save the plot functions are gone while
their *data* globals came back. Lesson: **never keep state in functions or
closures** — keep data, and re-derive function-valued state in a
first-tick guard. Nobody but `scenario_53_escape` uses this idiom.


## House heuristics

1. **Derive first, mirror second.** If the world can answer the question
   (alive? carrying? in range?), ask the world. Mirror only what the world
   can't know (hint-given, price-paid, story-beat-fired).
2. **Mirror near the thing.** Object field > global table:
   `tr.lc_book` beats `transport_state[tr_id]` — saved with the object,
   no stale ids.
3. **One scalar `phase` per storyline + a flat flag table** — big enough
   to assert in the autotest, small enough to reason about.
4. **Make every transition idempotent.** Hooks can double-fire, GMs
   rebuild objects, late joiners appear in `update()` but never in
   `init()`. Guard flags (`if not x.lc_watched then … end`) are the
   standard vaccine.
5. **Never let a global registry be the sole owner of truth** — pair it
   with a world-scan fallback (`lc_watched` re-scan pattern), or a
   GM-respawned object silently disconnects from the story.
6. **Budget `update()`** — accumulate `delta` and poll expensive scans
   every N seconds once the world is big (our ~1900-piece asteroid belts
   are exactly why).

## Lost Cluster mapping / DSL implications

`scenario_40_lostcluster.lua` already runs idiom A + dialog state-on-
objects: `MISSION.phase` + per-subsystem flag tables + `lc_*` object
fields + world predicates — the save-safest combination; the autotest
asserts against exactly these. A mission DSL built on this analysis falls
out naturally: `phases:` = idiom-A predicates, `objects:` carry `fields:`
(object-field state), `dialogs:` = per-station page/replies mini-FSMs
(schema-enforced split, see note 01), and a codegen rule: **generated code
never stores closures in globals** (or must emit the `~= nil` guards).

## Evidence provenance

- Hook list, `ScriptStorage`, and the `isValid()` semantics: read from the
  vendored `script_reference.html` (2024.12). The 35-scenario census:
  local grep, reproducible via the one-liner in note 03.
- Save/load serialization of globals/object fields: inferred from the
  `plotX ~= nil` guard pattern and `comms_data`-on-object usage — *not*
  re-read from C++ this round. Before the DSL freeze, confirm against
  `src/` (sparse clone, note 03).
- The wormhole & comms internals in note 01 were verified against the
  pinned C++ in an earlier session from a local mirror that no longer
  exists on disk; re-verify with the sparse clone if you need to build on
  them.
