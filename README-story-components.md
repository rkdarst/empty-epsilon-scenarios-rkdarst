# Story components

Abstract building blocks for investigation-style scenarios: things players
investigate, talk to, and combine. Each block lists the console it exercises
and the engine primitive it runs on (all verified against the EE-2024.12.08
source and `script_reference.html`). Mix and match; nothing here assumes a
particular story. Each console's list is sorted most-interesting first — the
tail items are support acts, not filler.

## Engine primitives worth designing around

- **Probes** — relay-launched, stock 8, 10 s recharge. Each is a 5u short-range
  radar bubble, linkable to the science radar; `on_probe_launch` exists for
  scripting. A limited stock turns scouting into an economy.
- **Scan states** — simple/deep scan per object; poll `isScannedBy` from
  `update()` (there is no `onScan` callback). `setScanStateByFaction` both
  marks evidence as "read by the crew" and **pre-grants intel**: start the
  crew with a partially scanned contact and the dossier already covers it.
- **Custom science databases** — `ScienceDatabase():addEntry()` /
  `addKeyValue()`. An in-fiction registry the science officer actually browses,
  red herrings included.
- **Radar signatures** — `setRadarSignatureInfo(gravity, electrical,
  biological)` gives every blip a fingerprint on the science console's raw
  scanner plot; it does **not** gate radar visibility in 2024.12.08.
- **Reputation economy** — pay or earn rep through comms
  (`takeReputationPoints`); station services (probe replenishment, supply
  drops, escorts) are the standard sinks. Rep makes every console's output
  fungible.
- **Hazards** — mines, black holes, warp jammers, wormholes, nebulae are all
  engine-native and cheap to seed.
- **Territory zones** — `Zone(...)` overlays faction territory on long-range
  radar. The political map becomes readable information: where it is safe to
  hail, who is trespassing where.
- **NPC ship orders** — `orderFlyTowards`, `orderDefendLocation`,
  `orderStandGround`, `orderRoaming`: stage traffic, escorts, blockades and
  fleeing witnesses. (Leash them to an anchor or they wander into hazards.)
- **Two-stage scans** — the server's scanning-complexity setting (Normal or
  Advanced) makes key evidence a simple scan followed by a deep scan. Standing
  still through a long deep scan is its own dramatic beat.
- **Docking as a gate** — `isDocked` is a plain state check; face-to-face
  conversations, handovers and repair windows can all require it.
- **Station capability toggles** — `setRestocksScanProbes`,
  `setRepairDocked`, `setSharesEnergyWithDocked`, `setRestocksMissiles`:
  stations can be *incomplete*. Repair here, probes only there — geography
  starts to matter.
- **Ship log** — `addToShipLog(text, color)`: a persistent, re-readable
  channel. Speaker-tagged lines ("[CMDR](Commander Reyes) …") read like radio
  transcripts — briefings and breadcrumbs that don't vanish the way comms do.
- **Waypoints** — relay's waypoints are script-readable (`getWaypoint`), so the
  scenario can verify a route the crew plotted.
- **Gated comms trees** — `setCommsMessage`/`addCommsReply` with scenario-state
  conditions: any completed task anywhere can unlock a dialogue branch.
- **Mine storage** — mines are a weapon type: a mine-layer ship can *seed*
  fields, so area denial becomes a player verb instead of set dressing.
- **Disguised contacts** — an `Artifact` with a borrowed callsign and its own
  comms function impersonates a facility: fake HQs, ambush bait, ghosts.

## Activities by console

### Relay (comms + map)

- **Probe triangulation** — a periodic signal, probes dropped near likely
  sectors, the script reports a bearing per probe. Triangulating from bearings
  is the relay officer's own puzzle, and the 8-probe stock makes it an economy.
- **Border watch** — while the crew is busy talking, hostile scouts slip
  between nebulae on long-range radar. Hail a station in time and it raises
  shields; miss it and it burns. Keeps the map alive between conversations.
- **Traffic control** — the ship becomes sector traffic control: sequence
  freighters through a danger zone, hold one at a marker, wave another through.
  NPC orders + comms; the map fills with ships that matter.
- **State-gated interviews** — witnesses answer only after proof exists: a scan
  completed, cargo aboard, a fee paid, a lane cleared. Disclosure becomes the
  reward for other consoles' work.
- **Go-dark discipline** — crossing a watched zone means signal silence: no
  comms, no probes, or interceptors come. The scenario punishes probe use in
  watched sectors, so relay must decide when to talk and when to listen.
- **Interrogation ladders** — testimony contradicts physical evidence; a
  second-stage question unlocks once the contradiction is in hand. Turns
  "collect clues" into "evaluate clues".
- **Broadcast psy-ops** — a `globalMessage` broadcast that NPCs react to: a
  false distress call pulls raiders off a station, a rumor shifts a convoy's
  route. The broadcast itself is a tool with side effects.
- **Reputation as pacing** — evidence sells, services cost. Every console's
  deliverable can be priced. Support act, not a puzzle.

### Science (forensics)

- **Inside-the-cloud eyes** — deep in a nebula field the relay map is blind (no
  friendly sight bubbles out there) while science's short-range radar still
  sees. One relay-blind search forces science to call contacts
  out loud while relay logs them. Zero new code, maximum table-talk.
- **Counter-science maskers** — ships whose transponder lies: registry says
  freighter, emissions say cruiser. Only the deep scan reveals the truth, so
  "unknown, scan it" becomes a real decision instead of a chore.
- **Comparative forensics** — two objects that mean nothing alone; the script
  unlocks the comparison only once both are scanned ("plating matches the
  sector-7 wreckage"). The comparison is the combination.
- **The black box** — an artifact that must be scanned by a player (artifacts
  never advance through probes or AI). Its text is deliberately incomplete:
  coordinates relative to something comms must identify.
- **Two-stage evidence scans** — with scanning complexity Normal/Advanced, the
  deep scan is a long, stationary affair: dodge mines or fend skirmishers while
  the bar fills. Weapons and science working the same ten seconds.
- **Registry cross-reference** — scanned transponders looked up in a custom
  science database. Only the combination of a scan and a comms detail
  identifies the right entry.
- **Signature triage & search patterns** — traffic sorted by
  gravity/electrical/biological signature, or a spiral search for biological
  signatures around a last-known position. Deciding who to scan first is the
  game.
- **Deep-scan forensics** — derelicts whose scan text (via `setDescriptions`,
  gated on `isScannedBy`) yields registries, damage patterns, timelines. The
  generic version; dress it per story.
- **Scan-state clearance & the living database** — stations open branches only
  to crews whose scan states show they examined the evidence, and the science
  database itself grows as the crew discovers — the DB becomes the mission log.

### Weapons (investigation-shaped combat)

- **Disable-don't-destroy** — a runner carries the objective: beams
  system-targeted at engines, hull intact. Breach it and the cargo dies with
  it (artifact `onDestruction`). Precision gunnery with an investigative stake.
- **Rules of engagement** — firing on neutrals costs reputation. A "hold fire
  until science confirms" loop makes gunnery depend on the investigation.
- **Denial ring** — a warp jammer pins the runner inside a ring (jammers are
  engine-native and scriptable): no warp escape, so weapons has time to work
  the engines while comms stalls.
- **Mine-laying** — the crew seeds the field themselves, on the lanes the enemy
  is predicted to use: predictive, engineering-forward, and the payoff is
  watching the plan work (as in the shipped "Close the Gaps").
- **Standoff management** — an armed ship parks on the objective. Shields up
  while comms negotiates; if talks fail, a goal-shifted fight: kill their
  weapons system, not the ship.
- **Inspection & boarding beats** — patrol-and-seize gameplay: hail, demand
  compliance; an NPC "boarding maneuver" countdown forces an immediate gunnery
  or helm decision (as in the shipped "Ghost from the Past").
- **Danger-close escort** — protect a fragile NPC (freighter, prisoner
  transport) that the enemy targets first. The escort target is the
  investigation, and it dies easily.
- **Bait-and-ambush** — the player ship plays lure to pull raiders into a
  prepared kill zone: relay-seeded mines, a timed engineering power spike,
  weapons executes. The trap was set by the whole crew.
- **Perimeter suppression** — during a scan or handoff, weapons sweeps
  approach vectors (missiles, drones) while science works. Simultaneous but
  asymmetric load — one console keeps the other's clock running.
- **Minefield corridor** — probes map which lanes are real, weapons shoots the
  mines, helm flies the line. Three consoles, strictly sequential
  dependencies.

## Mission structures & pacing

- **Dispatch-office loop** — a station comms hub hands out the next assignment
  and offers "stand down or continue" between them: episodic pacing with no
  timers, just a counter on the wall (shipped "Unwanted Visitors").
- **Tension meter** — a scripted escalation number driven by provocations; the
  crew is ordered to *hold the peace* inside a marked neutral zone while the
  gauge climbs (shipped "Borderline Fever"). ROE pressure made visible.
- **VIP itinerary** — a passenger with a multi-leg schedule: pick up within
  range, attend a meeting, onward under threat. Plot state, not cargo physics
  (shipped "Deliver Ambassador Gremus").
- **Mission menu with GM override** — pick the next mission at random unless a
  GM intervenes; replayability without scripting a campaign (shipped
  "Shoreline").
- **Achievements as hint dispensers** — optional objectives whose comms
  entries double as an in-fiction hint system (shipped "Broken Glass").
- **Interaction thresholds** — stage gates on "N meaningful interactions done,
  plus a reputation floor", not just story flags (shipped "Kessler").
- **Soft-fail escalation** — failure makes the situation worse (more debris
  spawns) instead of ending the run; a clock replaces the game-over (shipped
  "Kessler").
- **Randomness knob** — a `Setting[...]` that biases the RNG toward or against
  the crew, a third difficulty axis beside enemy stats (shipped "Escape" and
  its Murphy setting).
- **Symmetric generation** — mirrored procedural terrain so PvP starts are
  fair (shipped "Chaos of War").
- **GM as character** — brief the GM to deliver secrets in person and in
  character (shipped "The Omicron Plague" includes GM notes saying exactly
  that).

## Scifi-inspired story elements

Episode-shaped beats from the genre rather than console mechanics. Grouped by
the console that carries the scene, but most need the whole crew — and none
need engine features beyond what the sections above already cover.

**Engineering**

- **Power triage** — the reactor never covers every request: shields, sensors,
  or warp? Keep the crew underpowered and every console's wish becomes a
  negotiation.
- **Damage-control ladder** — breaches, fires, and coolant leaks during combat;
  engineering sets the triage order while the crew buys time between hits. The
  mirror of the disable-don't-destroy list.
- **The overheat countdown** — the reactor runs hot and must be vented on a
  schedule, or the running fight becomes an evacuation.
- **The gas-giant hide** — power down and drift in a nebula or upper atmosphere
  while the hunter's sweeps pass; one console's mistake ends it.
- **One more jump** — a jury-rigged repair under fire buys exactly one warp
  exit: a capability the crew earns by defending a window, not one they start
  with.
- **Intermittent systems** — a system that only works in cycles (cloak
  recharge, failing sensors) makes engineering's clock everyone's plan.

**Helm**

- **Precision station-keeping** — hold position exactly: over a disaster site,
  alongside a drifting wreck, inside a small safe bubble during a storm.
  Navigation becomes fine motor control.
- **Match course and speed** — hold formation with an NPC for a mid-flight
  transfer or tow; every wobble costs.
- **Thread the needle** — fly the uncharted debris field with sensors down;
  science calls hazards from the raw plot, helm flies it blind.
- **The pursuit** — a tail-chase against a faster or cloaked runner; weapons
  only gets firing windows when helm earns them.
- **Moving windows** — a wormhole or gate traversable only on a schedule; the
  whole mission bends around helm's timetable.

**Science**

- **Sensor ghosts** — phantoms and echoes that must be proven false — or true.
  The science officer becomes the crew's lie detector.
- **Staged decoding** — an alien signal that decodes scan by scan, each stage
  unlocking a new comms branch.
- **The periodic ping** — the hidden thing is visible only every N seconds;
  stealth becomes rhythm, and timing the sweep is the skill.
- **Forecasting** — sample the storm/eruption/plague curve and predict it; the
  forecast sets every other console's deadline.
- **Quarantine decisions** — identify the vector, decide who gets isolated,
  live with the cost. The medical episode without a sickbay console.

**Relay / comms**

- **The summit** — broker between three factions with contradictory wants;
  every concession to one costs standing with another. The win condition is a
  treaty, not a kill.
- **Distress triage** — simultaneous maydays, some genuine, some bait;
  choosing what to answer is the episode.
- **Hostage negotiation** — concessions versus stalling on a timer, with a
  hijacker who reacts to tone.
- **The tribunal** — the crew presents its gathered evidence at a formal
  hearing; the verdict is computed from evidence completeness. A capstone for
  the whole investigation kit.
- **Interpreter comms** — every word goes through a limited third party; the
  message budget forces precision.
- **Evacuation coordination** — shepherd transports out on a timer: lanes,
  escorts, and slots, with soft-fail escalation when one is lost.

**Weapons**

- **The fighting withdrawal** — hold the line just long enough, then disengage;
  survival with a clock instead of a kill count.
- **Capture, don't kill** — take the enemy ship intact for salvage or evidence
  (boarding support is thin in this pin; the disable-and-dock variant works
  today).
- **The duel** — a one-on-one challenge where outside interference voids it:
  ROE with a referee.
- **The weak point** — science finds the unshielded seam and the capital ship
  can only be hurt there. Anatomy, not identity.

**Whole crew**

- **The prime-directive dilemma** — intervene or not, with observable
  consequences either way and no combat solution.
- **The bluff** — stake the ship on a lie, and script how far it carries.
- **Enemy mine** — a timed, betrayable alliance with yesterday's foe against a
  shared threat.
- **The groundhog loop** — a time loop where only the ship log persists; the
  log becomes the only progress bar.
- **Booby-trapped salvage** — claim the derelict, tow it home, discover the
  trap inside.

## Combination patterns (the glue)

- **Split keys** — one console holds half an answer, another the other half
  (a database names a destination; a witness names which of three sites is
  real). Neither can act alone.
- **Triangulation pipeline** — a bearing from comms, a bearing from a scanned
  beacon, the intersection probed, then flown. Sequential by nature: the
  puzzle shape itself staggers the consoles.
- **Proof-of-work gates** — comms branches requiring flags only another
  console's completed task can set.
- **Two-source verification** — a rule, stated in-fiction: no accusation is
  acted on without evidence from two different kinds of source (a scan and a
  witness, a manifest and a wreck). Prevents the run from being one lucky
  conversation.
- **Time locks** — evidence expires: a witness leaves port at a set time, a
  wreck drifts toward a black hole, a station's shield window opens for two
  minutes. Prioritization becomes the puzzle.
- **Proximity testimony** — some witnesses only talk face-to-face: fly to
  them, dock, or hold position alongside while they talk. Helm's position is
  the comms unlock.
- **The map as evidence** — plot bearings and waypoints; the pattern on the
  relay map is the insight. Costs nothing but information design.
- **Contradiction ladders** — timeline evidence vs. testimony; someone is
  lying, and the second interrogation is the payoff.
- **Designed false positive** — one database entry or witness fits too well;
  only a second source exposes the mismatch. Teaches crews to verify before
  they burn reputation.
- **Silence as signal** — a station that stops answering is itself a clue;
  map the comms failures and the pattern points somewhere.
- **Economic coupling** — evidence from any console converts to reputation,
  which buys services every console consumes.
- **Split instruments** — with several player ships, capabilities live on
  different hulls: the carrier parks and recharges, the fighters scout, some
  evidence must be scanned by a *specific* ship (shipped "Escape", "Carriers
  and turrets"). Docked-state gating makes formation part of the puzzle.

## Design cautions

- Friendly objects are always drawn on the relay map (each seeds a sight
  bubble): "hidden" things need a non-crew faction, distance, or nebulae,
  plus a proximity reveal.
- **Relay sight bubbles vs. nebula shadowing** — the relay map shows only what
  friendly ships/stations and your probes (5u bubbles) reveal; the science/main
  long-range radar shows everything except nebula-shadowed contacts. Design the
  relay/science split around that difference rather than against it.
- Artifacts advance scan states only on real player scans.
- No `onScan` callback exists; poll scan state in `update()`.
- Two-stage scans are a server setting (`scanning_complexity`), not a
  per-object script call in this pin — plan around the setting, not per-target
  tuning.
- Comms callbacks may arrive without a usable source argument on some engine
  paths; keep a fallback player lookup.
- NPC ships given orders will wander into hazards unless leashed to an anchor.
