# Player communication — the crew can always answer "what now?"

Anti-softlock work makes a mission *completable*. This makes it *completable by
players*: at every moment of the mission, some console must be able to answer
four questions — **what** is my next objective, **where** is it, **which
mechanic** completes it (dock / scan / shoot / pick up / hail / wait), and **how
do I know it worked**. A phase machine with flawless closure still fails if the
crew never learns that phase 3 exists. AI-generated scenario code reliably writes
the world logic and delivers one briefing message; this is the checklist for the
other half.

## 1. The contract, per moment

| Question | Weak answer (rejected) | Shipped-scenario answer |
|---|---|---|
| What now? | nothing after the briefing | 62 keeps `primaryOrders`/`secondaryOrders` strings updated per phase; every station page carries a *"What are my current orders?"* reply; 58 shows *"Immediate goal: race waypoint %i"* |
| Where? | bare coordinates mid-text | 51 stations answer *"Where is Ningling?"* by **adding a nav waypoint** (`commandAddWaypoint`, with 9-waypoint overflow handling); hint text uses `getSectorName()` ([reference/geometry-and-units.md](../reference/geometry-and-units.md)) |
| How? | an object with no learnable verb | 05: *"deliver the diplomat to Orion-5 in sector G3. Do this by docking with the station"* — action + place + verb in one line |
| Did it work? | silence; the world just changes | 05 announces every transition, success *and* failure (*"What the hell? I told you NOT to destroy the transport."* → defeat); 60's flag-grab event lands on **main screen and ship log** at once; 47 logs progress (contracts, cargo) to the ship log |

## 2. The channel ladder

Every objective needs **push, pull, and persist** — one event, one queryable
source, one persistent record. The engine channels and their traps:

| Channel | Property | Trap |
|---|---|---|
| `sendCommsMessage` | rich, from a named voice | **returns false and drops** when that player is in a dialog — route through the notification queue ([patterns/notify-queue.md](../patterns/notify-queue.md)) |
| `addToShipLog` | persistent, re-readable, survives dock cycles | no push — the crew must open it; tag entries (51 prefixes `[AMBGREMUS004]`) so they are findable |
| `globalMessage` | main screen, all ships | one line, no sender, easy to miss mid-combat; reserve for beats, never for state |
| `addCustomInfo` / `addCustomMessage` / `addCustomButton` | persistent per-console UI | per *hull* — dies with the ship (mirror rule, §6 of the anti-softlock checklist); 51 renders deadlines here |
| station comms pages | queryable, repeatable | need `setCommsFunction` + the one-render-per-action split ([patterns/dialog-page.md](../patterns/dialog-page.md)) |
| waypoints (`commandAddWaypoint`) | the strongest "where" | cap of 9; handle overflow (51 replaces waypoint 9) |
| science descriptions, radar signatures | discovery-tier info | only helps if the *verb* is learnable from what the science officer sees |

The scenario skeleton ships the notification queue and a `notify()` call per
beat ([templates/scenario_skeleton.lua](../templates/scenario_skeleton.lua)) —
push infrastructure is the default, not an add-on; the pull and persist layers
are what you must design in.

## 3. Tiered explicitness

How much you tell the crew is a design axis, and the shipped scenarios treat
**difficulty as a verbosity knob**, not only an enemy count:

* **Tutorial / story tier**: state action, place, and mechanic explicitly (05's
  delivery lines). 51 even promises it in the scenario description: *"If you get
  lost or forget your orders, check in with stations for information."*
* **Puzzle tier**: name the *mechanic*, withhold the *answer*. 07: *"find a back
  door using the frequency LEAST absorbed by their shields"* — the crew still
  must compute which frequency that is. 51's artifact reports give *"approximate
  heading 135 from Pangora"* — a clue, not a waypoint.
* **The knob**: 60_captureFlag's `Tracking[...]` header setting delivers the same
  flag drop/grab event at four verbosity tiers — `Easy` includes the carrier's
  callsign, `Normal` names only the team, `Hard` says bare *"Flag dropped"*,
  `Secret` says nothing. Note the coupling: the quieter tiers also *raise the
  difficulty* (the flag must be rescanned after a drop), so verbosity is a real
  design axis, not just cosmetic. Compose it with your `Difficulty` knob instead
  of a second setting where you can.
* **The floor, never below it**: every objective must be *discoverable* — stated,
  queryable, or inferable from a visible property. An objective whose mechanic
  nobody can name is not a puzzle; it is a softlock with extra steps
  ([anti-softlock.md §5, "can never complete"](anti-softlock.md)).

## 4. Queryable orders (the pull channel)

The push is gone the moment the crew dismisses it. What remains:

* Keep **one orders string per tier** (`primaryOrders`, `secondaryOrders`,
  `optionalOrders`) and rewrite it at every phase transition; expose it as a comms
  reply on every station page (62, 58, 47 all do).
* **Progressive disclosure**: unlock each answer when its objective becomes
  active (51 sets `location_help.askForNingLocation = "ready"` only when Ningling
  exists) — otherwise the pull channel spoils the push.
* Required destinations get waypoints; optional ones get heading clues. Tiering
  *within* the pull channel is exactly how 51 separates must-do from bonus.

## 5. The communication audit (run before calling it done)

Walk the brief's beat graph; per objective:

1. **Push** — an event announces it when it becomes active, through the queue.
2. **Pull** — some page still answers "what now? / where is it?" after the push.
3. **Persist** — ship log or orders string still shows it after a dock cycle and
   a ship swap.
4. **Locate** — sector name, waypoint, or a sensor trail the science console can
   actually follow.
5. **Mechanic** — the verb is stated or learnable from the science description.
6. **Feedback** — completing it announces the next beat; failing it announces the
   branch (story turn or defeat), never silence.
7. **Recovery** — an idle hint names the next step after N minutes, and audio
   lines have a replay button (51's `addCustomButton` voice-log pattern) — the
   same idle-hint rule the anti-softlock checklist requires per phase.

Items 1–7 are the communication half of the review in
[anti-softlock.md §7](anti-softlock.md); run them in the same pass.

## 6. What headless tests can check

Most of this is now directly testable — see
[../testing/communication-testing.md](../testing/communication-testing.md) for
the full channel × testability matrix and the patterns. In short:

* **Push** (notify queue): `ee_spy("notify")` + `ee_spy_seen` — assert the crew
  was *told*, at the same beat as the state change. Prefer the spy over reading
  `msgq` directly: it proves the write happened, not just that it was queued.
* **Pull** (orders / status pages): dialog walker + `ee_dlg_click_by_label`,
  asserting the rendered text.
* **Persist** (ship log): only through the `log()` choke point (`ee_spy("log")`)
  — there is no read API for the ship log headlessly.
* **Recovery hint**: shrink the idle knob from the driver and wait on the hint
  through the spy.
* **Descriptions**: `getDescription()` is readable; assert label flips at each
  beat (text-through-one-function convention).
* Everything else — did the line make sense, was the sector name readable at a
  glance, was the clue fair — belongs to the 30-minute human session
  ([testing/human-acceptance.md](../testing/human-acceptance.md)). A communication
  audit that never met a human crew is a draft.
