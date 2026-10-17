# Anti-softlock checklist

A softlock is a state where the mission can no longer be completed and nothing
in the world can change that. Every one we have ever hit came from assuming an
event would fire that the engine does not guarantee. Run this list before
calling a scenario done.

## 1. Every "must exist" object

| Requirement | Naive implementation | Why it breaks | Fix |
|---|---|---|---|
| A crate from a killed guard | `onDestruction` → drop | `destroy()`/GM/collision deaths never fire it | polled drop-watch ([recipe](../patterns/guanteed-drop.md)) |
| A part that a killed carrier had | `onDestruction` → spill | same | script-side mirror of the carrier + respawn timer |
| A station's defence after a wipe | respawn in the kill hook | same | slot table with `timer`/`respawns_left` polled each tick |
| A hint the player can act on | one notification | dropped if the crew was in a dialog | notification queue with retry |
| FTL for a respawned ship | set it in `init()` | `init()` sees only the first hull | `ensure_ftl()` in the poll loop |

## 2. Every "must eventually happen" timer

* `clock = clock + delta` timers do not run while the game is paused, and a tick
  can carry a big `delta` after a stall. Add a wall-clock-ish floor
  (`if clock > last_seen + N`) so a stall cannot freeze the sequence. `[obs]`
* Anything gated on `getAllObjects()`/radius queries must tolerate a world where
  the object is momentarily not there.

## 3. Every "player must not be able to get stuck"

* **Wrong place at the right time**: a phase that triggers "when the player is
  near X" must also be reachable if the player arrives at X *before* the trigger
  was armed (arm it in the poll loop, not in a one-shot event).
* **Killed the wrong thing**: if a guard squad is also the delivery mechanism,
  the mission must remain solvable when it dies early (watchdog drop) *and* when
  it never dies (a hint line that names the sector after N minutes).
* **Delivered to the wrong station**: gate on the object, not on the player's
  belief.
* **Everyone died**: only declare a loss if there ever *was* a player
  (`ever_had_players`), and remember the GM can respawn ships - the mission
  should keep running until the GM says otherwise.

## 4. The two tests that find softlocks

```sh
# (a) hook-less death: destroy() every carrier/guard the mission depends on and
#     assert the required object still appears.
AUTOTEST=tests/x.autotest.lua ee-func.sh scenarios/x.lua     # a step calls probe_kill_group()

# (b) long idle: let the mission run with nobody acting for 10 minutes and check
#     that (i) nothing errored, (ii) no generator spam, (iii) the world census
#     line is stable.
RUNTIME=600 AUTOTEST=none ee-func.sh scenarios/x.lua
```

Test (b) also catches the classic "respawn every tick because the slot table was
never cleared" bug, which is invisible in a short run and destroys the frame rate
after ten minutes.

## 5. What headless cannot tell you

Radar/visibility feel, dialog UX, warp-transit timing, and whether a nebula
search is fun are client-side. Everything in
[testing/runtime-surprises.md](../testing/runtime-surprises.md)
needs the 30-minute human session.
