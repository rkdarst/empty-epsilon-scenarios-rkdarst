# Anti-softlock checklist

A softlock is a state where the mission can no longer be completed and nothing
in the world can change that. Every one we have ever hit came from assuming the
engine guarantees something it does not: that an event fires, that an object
stays alive and within reach, that a chance to act comes around again. Run this
list before calling a scenario done.

## 1. Every "must exist" object

| Requirement | Naive implementation | Why it breaks | Fix |
|---|---|---|---|
| A crate from a killed guard | `onDestruction` → drop | `destroy()`/GM/collision deaths never fire it | polled drop-watch ([recipe](../patterns/guanteed-drop.md)) |
| A part that a killed carrier had | `onDestruction` → spill | same | script-side mirror of the carrier + respawn timer |
| A required pickup that reappears when its carrier dies (scenario_60_captureFlag's flag) | `onDestroyed` → create new drop | the hook never fires on non-damage deaths, and the *dropped* object can itself be shot down afterwards | polled drop-watch that also watches the dropped object — the shipped flag scenario does neither, so a GM-removed carrier or a shot-up flag makes the game unwinnable |
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
* **Did it before being told to (out-of-order play)**: the mirror image. A crew
  can complete a later prerequisite *early* — hail the courier before ever
  reaching the relay, find the station before the briefing names it. A phase
  machine that assumes the briefed order parks forever. Worked example: a
  player-ship crew in this repo took the access codes at phase 1, so the relay
  arrival branch set phase 2 over it and the mission became unwinnable. `[obs]`
  Mitigations (all four, not one):
  - Gate every transition on an **observable world fact** (`codes`, `loaded`),
    never on "the player talked to X in the expected order".
  - Transitions **bump from any earlier phase** (`if phase < 3 then phase = 3`),
    and sampling branches *read* state instead of overwriting it.
  - Arm deadlines / watchdogs **only when the prerequisite is actually missing**
    — a crew that already has the codes must never inherit the penalty clock.
  - One **out-of-order regression driver** per ordering the brief promises
    (see `tests/scenario_42_feverrun.early-codes.autotest.lua`).
* **Killed the wrong thing**: if a guard squad is also the delivery mechanism,
  the mission must remain solvable when it dies early (watchdog drop) *and* when
  it never dies (a hint line that names the sector after N minutes).
* **Delivered to the wrong station**: gate on the object, not on the player's
  belief.
* **The gate keeper died**: a comms page that hands out state changes belongs to
  a station, and stations can be destroyed (by the crew, by splash damage, by
  the GM). If that station dies, the action it gated is unreachable. Either
  re-assign the role to another station, make the mission's defeat path fire, or
  provide a watchdog. The shipped scenario_47_scavenger carries a GM-diagnostic
  line that admits exactly this for its *optional* reward plot ("mission cannot
  be completed due to the destruction of the first mission station") - its
  required plot declares defeat on the same death. And a gate keeper only gates
  while it is still needed: scenario_07_gftp declares defeat on Black Site
  114's death only while `hacked == 0`. `[obs]`
* **Gates on `players[1]`**: a multi-ship crew's "first" ship changes as ships
  spawn, die and join. A handover gate that checks only `active_players()[1]`
  refuses the ship that is actually alongside. Loop over all players; the gate
  opens when *any* player satisfies it.
* **Everyone died**: only declare a loss if there ever *was* a player
  (`ever_had_players`), and remember the GM can respawn ships - the mission
  should keep running until the GM says otherwise.

## 4. Every phase has both a way forward and a way out

The scenario_05_beacon tutorial (the repo's gold standard here) gives *every*
destroyable mission object an explicit branch that **ends in a `victory()`** —
destroy the transport you were told to capture → defeat, station destroyed →
defeat, player dead → defeat. Even the branches its author was unsure of carry a
`-- TODO: What to do now?` *and* a terminal state. The one thing those branches
never do is nothing.

Run this per phase, and per mission-critical object:

| Question | Acceptable answers |
|---|---|
| What advances this phase? | a polled world fact, with a fallback for every hook |
| What if the gating object dies? | mission-recover (watchdog/respawn), story-branch (the tutorial's escape pod: diplomat dead, mission continues), or **explicit defeat** — never a hang |
| How does this mission end in defeat? | at least one reachable, tested defeat path (colony lost, crew lost, deadline missed) |
| What if the crew idles? | a hint line naming the next step after N minutes (knob, not magic number) — audit item 7 in [player-communication.md](player-communication.md) |
| What does the crew know right now? | every active objective answers what / where / how / did-it-work (the [player-communication audit](player-communication.md)) |

Two traps inside this rule:

* **`isValid()` cannot tell "collected" from "destroyed".** A pickupable object
  that an enemy shoots down reads the same as one the crew picked up
  (scenario_05 literally counts a destroyed pod as a rescue). Keep the state
  transition in *your* collect function and let a drop-watch handle destruction
  ([patterns/container-drop.md](../patterns/container-drop.md)).
* **After `victory()`, settle before stopping.** Combat bookkeeping, message
  queues and drop-watches must run on the final tick too, or the last kill's
  drop and the final notification silently vanish. Gate the *simulation* on
  `done`, not the bookkeeping.

## 5. Every micro-objective inside a phase stays completable

An order-proof phase machine can still hang, because a phase is usually
completed through several *micro-objectives* - scan this beacon, pick up that
case, load alongside the relay, take the codes from the courier. Each is a
mini-mission with the same failure surface as the whole scenario, at smaller
scale: the object it needs can die, drift, be missed or be spent by mistake
while the phase logic itself is flawless. The defeat rule of §4 applied at
phase scale ("if the colony dies, defeat fires") still leaves a vaccine case
adrift in an asteroid ring while phase 4 calmly polls `case_aboard`.

Run the §4 closure table per micro-objective, not only per phase. The
recurring classes:

* **The objective's object moved.** Adrift pickups keep their spawn velocity,
  dropped containers inherit the carrier's momentum, beacons drift. A phase
  polling `case_aboard` with no reachability check hangs when the case ends up
  40u out or inside a station's exclusion radius. Re-drop the instance at a
  rejection-sampled safe point when it leaves a bound, or give the phase an
  exit ([reference/runtime-pitfalls.md](../reference/runtime-pitfalls.md)).
* **The helper that fulfils the objective died - or is flying to a photograph.**
  Phases often wait on an NPC (a recovery team, a transport under tow).
  scenario_05_beacon's recovery phase waits for
  `distance(recovery_team, transport) < 1000` with **no branch for a destroyed
  recovery team** - Exuari attackers spawn every couple of minutes, so a dead
  RTRV hangs the flagship tutorial forever. The same phase orders the helper
  with `orderFlyTowardsBlind(transport:getPosition())` - a snapshot; if the
  transport drifts, the rendezvous may never fire even with the helper alive.
  Watch the helper's `isValid()` like any gate keeper, and re-issue the order
  against the live position every tick. `[obs]`
* **The window closed.** A comms option that exists only in range, only in one
  phase, or only while a station lives is a one-shot door - and crews are often
  mid-dialog elsewhere (a busy player makes `sendCommsMessage` silently fail).
  State-changing offers must stay on the page until consumed, and time-limited
  offers must reopen ([patterns/notify-queue.md](../patterns/notify-queue.md)).
  A window the crew cannot see is a trap, not a challenge - scenario_51_deliver
  Ambassador renders the mob deadline as a live console timer (`addCustomInfo`).
* **The objective was spent by mistake.** One cargo slot, one antidote, one
  dialog branch that consumes the item: a misclick or a stray explosion near
  the crate burns a micro-objective with no second instance. Any consumable a
  micro-objective depends on is either re-acquirable (drop-watch re-spawn,
  carrier re-spill - [patterns/container-drop.md](../patterns/container-drop.md))
  or its loss is a declared terminal state.
* **The objective can never complete.** Artifacts never advance scan states, so
  "scan the artifact" is unwinnable by construction. Verify the objective type
  against the engine before building a phase around it
  ([reference/runtime-pitfalls.md](../reference/runtime-pitfalls.md)).
* **The deadline started before the ability.** A watchdog armed when the phase
  opens can expire while the crew is still flying to the phase's *first*
  micro-objective. Arm penalty clocks only when the prerequisite is actually
  missing (§3) - the Fever Run override deadline starts at the relay, not
  at mission start.
* **Partial progress evaporates.** A "3 of 5 beacons" recomputed from live
  objects loses the ones that were scanned *and* destroyed - the mirror-table
  rule of §6 applies per micro-objective, not just to mission-level
  counters.

The review question, per micro-objective: *what single event makes this
impossible, and which of {re-acquire, reassign, skip, defeat} answers it?*
"Nothing can make it impossible" is almost always wrong - the crew can shoot
anything, and the GM can delete everything.

One calibration from the shipped scenarios: an **optional** micro-objective is
allowed to soft-fail, as long as it fails in fiction and the mission moves on.
scenario_47_scavenger's Jenny plot answers "the asteroid was destroyed" with
"Looks like I'll have to find another asteroid. Thanks for your help." and
closes - an exit, not a completion. Required objectives do not get this option;
the closure table of §4 applies to them in full.

## 6. Progress must survive the hull

Scan progress, partial delivery counts and timer deadlines that live only on
engine objects are erased the moment the object dies. The shipped
scenario_33_early mirrors every scan clock script-side (`scan_target.single_scan_clock`)
precisely so a destroyed scan target still counts as scanned. `[obs]`

* Any "the player must scan X" requirement: keep the scanned flag script-side
  the tick it flips, so X can die afterwards (and remember a *destroyed-before-
  scanning* X needs a watchdog — see §1 and §3).
* Any counting objective: the count lives in a script table keyed by name, never
  derived from which objects currently exist.
* If the scenario swaps the crew's hull (scripted ship change), migrate the
  record at the swap: scenario_53_escape explicitly copies its `debris1/2/3`
  pickup flags onto the replacement ship. A record stored on the player ship
  object dies with it.
* This is the same mirror-table rule as
  [flow-diagrams.md #5](flow-diagrams.md), applied to mission progress instead
  of hook data.

## 7. The order-proof review (the ten-minute walk-through)

Before calling a scenario done, walk the brief's beat graph and answer, per
**action** the mission asks for: *what is the earliest phase a stubborn crew can
complete this, and does the machine handle that?* Then per **phase**: entry,
exit, failure exit, idle hint. A mission with N beats has more than N-1 legal
orderings the moment any two beats are independent — enumerate the ones you
promise ("the relay can be skipped") and write the driver for each.

This is the single highest-yield review for AI-generated scenario code, which
tends to implement the *happy path ordering* faithfully and every other ordering
not at all.

## 8. The tests that find softlocks

```sh
# (a) hook-less death: destroy() every carrier/guard the mission depends on and
#     assert the required object still appears.
AUTOTEST=tests/x.autotest.lua ee-func.sh scenarios/x.lua     # a step calls probe_kill_group()

# (b) long idle: let the mission run with nobody acting for 10 minutes and check
#     that (i) nothing errored, (ii) no generator spam, (iii) the world census
#     line is stable.
RUNTIME=600 AUTOTEST=none ee-func.sh scenarios/x.lua

# (c) out-of-order: drive the orderings the brief promises. One driver per
#     ordering; the pattern is "complete a later prerequisite first", then assert
#     the phase machine followed (see tests/scenario_42_feverrun.early-codes.autotest.lua).
AUTOTEST=tests/x.early-codes.autotest.lua ee-func.sh scenarios/x.lua

# (d) defeat path: make the mission un-winnable on purpose (destroy the colony /
#     the escort target / all crew ships) and assert a terminal state is declared
#     instead of a hang.
AUTOTEST=tests/x.defeat.autotest.lua ee-func.sh scenarios/x.lua

# (e) mid-phase failure injection: with a phase open, remove the object one of
#     its micro-objectives needs (kill the courier or the helper NPC, shoot the
#     scan target, push the crate away) and assert the phase still exits -
#     re-acquired, reassigned or defeat - instead of polling forever.
AUTOTEST=tests/x.lost-case.autotest.lua ee-func.sh scenarios/x.lua
```

Test (b) also catches the classic "respawn every tick because the slot table was
never cleared" bug, which is invisible in a short run and destroys the frame rate
after ten minutes. Tests (c)-(e) catch the three hang classes a happy-path
driver is blind to: an ordering the machine did not expect, an ending it did
not implement, and a micro-objective that died while the phase watched.

## 9. What headless cannot tell you

Radar/visibility feel, dialog UX, warp-transit timing, and whether a nebula
search is fun are client-side. Everything in
[testing/runtime-surprises.md](../testing/runtime-surprises.md)
needs the 30-minute human session.
