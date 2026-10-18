# Writing an autotest driver

A driver is a Lua file appended after [lib/autotest.lua](../lib/autotest.lua).
It runs in the same chunk as the scenario, so it can call the scenario's own
functions - that is the whole design: **the scenario stays production-clean, the
driver reaches inside.**

## Shape

```lua
ee_finish_at = 240                -- hard end even if a phase never completes
local d = {}                      -- scratch shared between steps

ee_step(2, function()             -- t is GAME seconds since boot
    probe_state()
    ee_check(probe_part("Coolant core") == "adrift", "core starts adrift")
end)

ee_step(20, function()
    ee_until("escorts wiped", 90, function() return all_dead(d.pool) end)
end)

function ee_on_finish()           -- runs once, just before the end marker
    ee_check(part_count_delivered() == 2, "final: both cores delivered")
    ee_merc_retire()
end
```

| Helper | Use |
|---|---|
| `ee_step(t, fn)` | one action at game-second `t`, inside a pcall |
| `ee_wait(msg, deadline, fn, cont)` | poll like `ee_until`, then run `cont()` **once on success** — put outcome-dependent assertions in `cont` (the engine strips the coroutine library, so nothing truly blocks) `[obs]` |
| `ee_until(msg, deadline, fn)` | **async** poll `fn()` every tick; PASS when true, FAIL at `deadline` game seconds |
| `ee_check(cond, msg)` | one assertion line |
| `ee_invariant(msg, fn)` | `fn()` must hold on EVERY tick from now to run end; first false fails (anti-softlock as runtime maths) |
| `ee_spy(name)` / `ee_spy_seen(name, pattern, since)` | record calls to a scenario global (choke point) and match against them — see [communication-testing.md](communication-testing.md) |
| `ee_expect_victory(faction)` | assert the faction the mission ends for (win vs defeat) |
| `ee_dlg_open(page_fn, target, source)` / `ee_dlg_click(d, i, target, source)` / `ee_dlg_click_by_label(d, label, ...)` | drive the real dialog functions; prefer the label variant |
| `ee_merc_squad(fac, x, y, target, pool, n)` / `ee_merc_retire()` / `ee_merc_dump(tag)` | organic kills |
| `ee_eject_clear(msg, obj, station, hull_u, reach_u)` | container geometry assertion |
| `ee_finish(reason)` / `ee_on_finish()` | end the run; `ee_finish_at` is the safety net |

## The three rules

1. **Poll, never sample.** An AI kill, a warp transit or a respawn is done when
   the *world* says so, not when your timeline says so. `ee_wait`/`ee_until`
   with a generous deadline; `ee_check` only for instantaneous invariants.
   **Both are async** (the engine strips the coroutine library, so nothing can
   block): they register a poll and return immediately — assertions that depend
   on the outcome go in `ee_wait`'s `cont`, or in a *later* step. A same-step
   `ee_check` after `ee_until` races the poll and can fail spuriously. `[obs]`
   **Arm a wait AFTER its trigger when the deadline could land on the trigger
   tick**: the harness pollers run *before* the scenario's `update()`, so a
   top-level `ee_wait` whose deadline equals the triggering step's time fails
   one tick before the world can react. Registering inside the step (deadline
   counted from there) removes the race. `[obs]`
2. **One timeline step per beat.** A step that both triggers a phase and asserts
   its outcome is a step that fails for the wrong reason. Trigger, then verify
   via `ee_wait(..., cont)` in the next step.
3. **Print your state at every step boundary.** `probe_state()` /
   `ee_merc_dump()` lines are what make a failure readable in a 20 000-line log.

## Communication assertions

For asserting what the crew was *told* (push / persist / pull / descriptions /
idle hints) — the spy-on-choke-point pattern, the click-by-label pattern and
the honest headless limits — see
[communication-testing.md](communication-testing.md).


## Organic killing

The engine fires `onDestruction` only on damage kills, so hook-driven behaviour
can only be tested by actually destroying ships. The proven tool is a mercenary
**Starhammer II** squad (its AI fires only HVLI tubes - `ShipAI::runAttack` never
uses beams - so it needs warp drive to catch fleeing targets):

```lua
local pool = {}
pool[1] = CpuShip():setTemplate("Adder MK5"):setFaction("Exuari")
    :setPosition(U(40), U(6)):orderFlyTowards(U(90), U(50))
ee_merc_squad("Human Navy", U(40), U(6), pool[1], pool, 3)
ee_until("squad wiped the target", 170, function() return all_dead(pool) end)
```

Three things the harness handles for you, and you must replicate if you roll your
own killer (`[obs]` throughout):

* **The AI camps.** Against a fleeing target the mercs can park out of range
  forever; the lib drops one merc ~2u in front of the target after ~90 stale
  ticks. Teleport *spam* is worse than camping (the engine resets its pursuit
  geometry every time), hence the long cooldown.
* **Dead orders persist.** The engine never clears an attack order on a destroyed
  target, so the mercs must be re-targeted from the live pool.
* **An idle target is not engaged** - see
  [reference/ai-behaviour.md](../reference/ai-behaviour.md). Give the target
  flight orders.

Budget 20-45 s of game time per kill; a 3-ship squad against a fleeing target is
the sweet spot we measured.

## Driving dialogs

```lua
local d = ee_dlg_open(commsDepot, stations.depot, active_players()[1])
ee_check(#d.msgs == 1, "page renders exactly one message")     -- contract, not taste
local msgs = ee_dlg_click_by_label(d, "Hand over the components", stations.depot, active_players()[1])
ee_check(#msgs == 1, "action renders one message")
ee_check(msgs[1]:find("Received") ~= nil, "action took effect")
```

Click **by label**, not by index: reply order is unstable while authoring, and
an index click then hits the wrong reply silently (new replies must append
after the originals). Assert the *text* of the reply, not just that the click
ran — a dead click passes "runs without error" and fails the player.

The walker stubs `setCommsMessage`/`addCommsReply` and invokes the *same* Lua
functions the engine's dialog UI invokes, so a driver failure here is a real
scenario bug (usually pitfall
[#2](../reference/runtime-pitfalls.md)). `[obs]`

## Forcing scenario settings

Scenario settings cannot be *chosen* headlessly (the choice UI is the GUI; a
plain headless boot applies only the `|Default` value), so the runner can inject
any value:

```sh
EE_SETTINGS="Difficulty=Story" ee-func.sh scenarios/scenario_40_lostcluster.lua
```

which shadows `getScenarioSetting` before the scenario's top level runs. Run your
suite once per meaningful setting combination.

## Making the scenario testable

Add read-mostly hooks near the end of the scenario - they cost nothing in play
and are the difference between a driver and a guessing game:

```lua
function probe_state() print(("STATE done=%s delivered=%d/%d t=%.1f")
    :format(tostring(done), delivered_count(), #PART_NAMES, clock)) end
function probe_part(name) return ... end          -- "adrift"|"carried"|"delivered"|"missing"
function probe_kill_group(name) ... end           -- hook-less teardown, on purpose
function probe_deliver_all() ... end              -- for endgame-only assertions
```

Keep them idempotent and side-effect-free (except the ones whose job is a side
effect). `[obs]`
