# EE Scenario: The lost cluster

## Basics

This scenario is suitable for any number of player ships.

Units here are in game units, where a sector is 20u across, and the
typical scanner range is 5u.

## Scenario script

### Phase 1

(1) It starts in a home station area (Station name: Lumina 1), where
there are various patrolling ships near nebula, mines, asteroids, etc.
The station hails you and asks for you to pick up some computing
hardware from station Kajaani 1, which is on the other side of the map.

Upon hailing Kajaani 1 (which can happen even when not close to it),
they say that they have been looted and the supercomputer is missing
They request help investigating so ask you to come to them.  Once you
arrive there, they suggest calling stations LUT 1, Turku 1, Tampere 1.
There are the following parts (despite being plural, each is only one
object):

- (A) AMD compute nodes
- (B) Intel compute nodes
- (C) H200 GPU nodes
- (D) B300 GPU nodes
- (E) Lustre fileserver
- (F) Infiniband switches

We can’t see where the others are, but Lumina 1 will give a sector and
the station will be within 50u of that point (not exact locations) where
they might be and the players have to explore, including inside some
nebulas.

When Tampere 1 is hailed from afar, they say they have the H200 GPU
nodes.  When approaching Tampere 1, three relative weak enemy ships
appear and have to be fought off.  If you try to hail Tampere, they will
respond that they are under attack and request that you defeat the ships
near it before they talk.  After that, Tampere 1 also will say that the
B300 GPU nodes were stolen by some enemy ships that were headed towards
sector C10.  If you go to the sector, you can find them (just hanging
out patrolling in a pattern).  If you defeat them, they will drop the
B300 GPU nodes and you can pick them up.

When approaching station LUT 1, the station suddenly turns into an
enemy station and 3x the current total number of player ships appear.
These ships stay around the station (even as the player ships retreat),
and it is expected that the player ships need to group up and attack all
together.  Each time a player approaches within 20u alone (not all
player ships within 30u of the station), the enemy will hail the player
ship and taunt them “Alone you are weak and we will be victorious!  Come
back with more people, or stay away“.  LUT 1 itself appears as hostile
but doesn’t attack the player.  The enemy ships nearby don’t leave LUT 1
but stay within a sector of it.  Once the ships are gone, station LUT 1
can be hailed and then it will turn friendly again and they will provide
the AMD compute nodes.

When approaching station Turku 1, they say that they have been attacked
and they have hidden the data in several nearby nebulas, but the ship
doing the hiding got destroyed on the way back.  So, you have to go
search those nebulas to find the data.  There are seven nebulas randomly
placed nearby (same and adjoining sectors) and the Intel compute nodes
and Lustre fileservers are randomly hidden in two different of the
nebulas.  These components appear as cargo containers or similar; their
shipping labels can only be read up close (fly within 5u).  There are
some decoy containers with junk in and around the nebulas.

When someone returns to station Lumina 1 with cluster components and
hail it, you can give them the objects you found.  Lumina 1 then says
that the Infiniband switches are still missing and there has been a hint
that they are within a 5-sector area in the middle of the map (for
example around sectors A-E, 8-13).  Players must collectively search
this to find the switches.

### Phase 2

Starts when all components are delivered to Lumina 1.

If all the components are given to station Lumina 1, they will hail all
ships and say “Thanks for recovering all the hardware.  However, we have
lost our Ansible Playbooks.  We think they have been loaded onto a
civilian transport going between our stations.  Can you find them?“  One
has to go find all these various transports (say, total of 10 randomly
going between stations), approach and scan them.  The deep scan will
report if the ship has a playbook.  If they do, they can be hailed to be
told to stop to allow a transfer.  If asked to stop, they will stop, we
can pull along side and hail again to transfer (the ships will say "pull
along side, stop, and hail us to initiate the transfer").  This will
take dividing up and exploring.  There will be easy battles as you find
enemy ships in these areas (more enemy ships will be spawned if they are
already destroyed).  There are three Ansible Playbooks with names such
as “Ansible Playbook 1 (of 3)”.

Once the Ansible Playbooks are found, approach it, pick it up, and bring
it back to Lumina 1.

### Phase 3

However, there is a catch!  Once the player ships leave Lumina 1, they
get hailed and told a large number of enemies have been detected
approaching the station, and players must report back for defense.  One
wave comes, it must be defeated (all destroyed), and then players win.

## Locations

A1 is at the top left and M20 is at bottom right.  (1-20 goes
horizontally)

- Station Lumina 1.  This is the home base and spawn point.  It is
  around sector E3 and has plenty of supplies for us.  Hailing it will
  always tell us the latest mission status and gives hints on what is
  needed to do next to advance the mission. It doesn't replace the hints
  of other stations, but it can tell you who to ask if necessary.
- Station Kajaani 1 is around sector H20.  It is friendly and will tell
  us news even if we are not nearby.
- Station Tampere 1 is around sector H5.  Not visible at the start but
  Kajaani 1 can tell you where it is.
- Station Turku 1 is around sector B2.  Not visible at the start but
  Kajaani 1 can tell you where it is.
- Station LUT 1 is around sector L3.  Not visible at the start but
  station Tampere 1 can tell you where it is.  However, it says that
  LUT's location is confidential information and you must be within 10u
  of Tampere 1 to get its information.  When you approach LUT 1, it
  becomes hostile, as if it was a trap and had been taken over by
  enemies.  The station itself can’t be destroyed and doesn’t fight
  back, but once the enemies around it are destroyed it gets reverted to
  friendly control.
- The middle of the map has various friendly and enemy ships, which will
  attack if we get too close but if we stay away (or run away, outside
  their area) they continue with whatever orders they had
  before.

In all areas there is interesting randomly-generated terrain: nebulas,
asteroids, mines, and other ships.  Some sectors are more dense than
others.

## Ambient world (implementation)

The environment is seeded in `init()` by `seed_ambient()`, after the
mission geometry, from the `AMBIENT` constants table near the world
state (every generator scales from it):

- **Nebula clouds** — `nebula_frac` (default 0.10) of the playable box
  (the 5 stations' bounding box + 15u margin) is covered. Nebulae are
  engine-fixed 5U blobs, so coverage -> count uses the box-area formula
  `n = -ln(1-frac) * area / (pi * 5^2)` (~120 clouds at default;
  0.20 would need ~255 — capped by `nebula_max`). They blind
  *long-range radar* only (verified in the 2024.12 reference: no warp or
  weapon effects), which also makes the "search the nebulas" beats
  harder - a feature. ~45 % are jittered around cluster centers so the
  sky clumps instead of being uniform.
- **Dust belts** — `belts` sine-wiggling lines across the middle: mostly
  `VisualAsteroid` (off-plane decoration, zero collision cost, this is
  what makes space feel dense) with a thin spine of real `Asteroid`.
- **Derelict minefields** — `mine_fields` rings of 6 mines (Independent
  faction, triggered by anyone).
- **Wreck sites** — `wrecks` damaged Independent hulks
  (`setHullMax(50); setHull(4)`, `orderStandGround`) with a
  VisualAsteroid debris halo; the first `wreck_mines` sites are ringed
  by 4 mines (salvage hazard).
- **Traffic** — `traders` extra Independent freighters roaming the box
  (Neutral to both sides, like the init shuttles).
- **Wormhole pair** — `wormholes = true` links two far corners of the
  box (`setTargetPosition`), 12u+ from any station: shortcuts turn the
  empty middle into a lived-in map. No black hole: it would eat any
  station within 5U.

Keep-outs: nothing ambient spawns within 5u of a station (8u around
Lumina 1, so the home radar stays clean); mines demand 8u. All counts
land in `ambient_stats` and every ambient mine in `ambient_mines`; the
autotest asserts the census and the mine keep-out.

## Other notes:

- In general, there shouldn’t be a way to completely die or lock the
  scenario.  If a player ship is destroyed, it should drop its objects
  and a new player ship can be spawned by the GM and resume the
  scenario.
- Ships carrying objects drop the objects if destroyed.  Dropped objects
  appear as cargo containers in space.
- To transfer objects, ships or objects must be within 2u and
  stationary.
- To pick up an object, one has to go close to it and hail it.  One
  option is “We would like to pick you up.“
- To transfer an object, one has to approach the other ship and hail it.
  If it is a non-player ship, it will have an option “Please transfer
  \[object\] to us“.  If it is a player ship, it will have an option “We
  would like to transfer \[object\] to you.”
- To turn in an object to Lumina 1, one must hail it and an option will
  be to hand over the cargo.
- Stations can be hailed from anywhere, if it is visible.  Some are not
  immediately visible until they are found.
- Friendly stations, civilian ships, and anything required for victory
  should not be destroyable and enemies will not attack them.
- Non-depending objectives can happen in any order.
- You must be stationary to pick up or transfer cargo.  There are
  options to hail the NPC ships to request they stop for the transfer.
- Undiscovered stations are not hailable until they are found (approach
  within 5u on the radar).


---

## Tuning defaults (edit freely)

Feasibility pass through the brief: everything above is implementable.
These recommendations fill the few gaps left open in the prose and are the
values the first Lua implementation will use. All are knobs — adjust to
taste.

### Scale and coordinates

- 1 in-game displayed unit = 1000 script units (verified empirically:
  sector = 20u = 20000 script units, scanner range 5u = 5000). All
  distances in this document are in-game units.
- Sector names are the engine's own scheme (`getSectorName()` /
  `sectorToXY()`): letters are rows top-to-bottom (A..M), numbers are
  columns left-to-right (1..20), cells are 20u squares. So the map
  A1..M20 is exactly the built-in grid — no custom coordinate work.
- **Travel**: stock EE ship templates (players spawn in a Phobos M3P) ship
  with **no FTL at all** — the engine would seal players in their starting
  sector. The scenario therefore installs warp drives (`setWarpDrive`,
  speed 1 ≈ one sector/second, so the whole map is ~20 s of warp) on all
  player ships and transports; warp via the warp dialog is the intended
  way to move between sectors. No jump drives by design.

### Factions

- Players: **Human Navy**, spawning near Lumina 1.
- One hostile faction for the whole story: **Kraylor** (Tampere ambush,
  LUT garrison, B300 pirates, central-map hostiles, Phase 3 invasion).
- Transports: **Human Navy** freighters (friendly; hostile AI ignores
  them, per the brief).

### Ship tiers and enemy groups

Tiers (template names verified against the shipped scenarios): light =
Adder MK5 / Phobos T3, medium = Piranha F12, heavy = Starhammer II,
civilian freighter = Atlantis.

| Group | Where / when | Composition (default) | Behaviour |
|---|---|---|---|
| Tampere ambush | Warps in when a player first comes within 20u of Tampere 1 | 3 light | Engages within 20u; no respawn |
| B300 pirates | Static in sector C10, patrol loop | 2 medium + 2 light | Holds the area; drops the B300 when killed |
| LUT garrison | Warps in when a player first approaches LUT 1 | 3x player ship count (min 2), medium | Never farther than 1 sector (20u) from LUT 1 |
| Central traffic | Rows E-J x columns 6-15 | Static friendly + hostile patrol routes | Aggressive within 8u, otherwise ignores players |
| Playbook guards (Phase 2) | Near playbook-carrying transports | 2 light per guarded transport | One respawns 60s after destruction, max 2 re-spawns; stop after that transport's playbook is delivered |
| Phase 3 invasion | Warps in heading for Lumina 1 | 1 heavy + 1 medium per player ship | Converge on the station; all destroyed = win |

### Counts, timers, and triggers

- Turku search: 7 nebulas (5u radius); Intel and Lustre in 2 random
  different nebulas; 4 decoys in the remaining nebulas + 3 loose nearby.
  Decoys scan as "junk (spare parts)".
- Infiniband search area: rows A-E x columns 8-13 (the mid-map 5-sector
  box); the switches are one artifact hidden in a nebula/field inside it.
- Phase 2: 10 transports shuttle between the 5 stations; exactly 3 of
  them (random) carry one playbook each.
- LUT taunt: fires when a player ship is within 20u of LUT 1 while no
  other player ship is within 30u; re-arms once that ship has been >40u
  away again.
- Phase 3 trigger: after the third playbook is delivered, the first time
  any player ship is >=40u from Lumina 1; the hail is immediate, the
  invasion warps in 3 minutes later.
- Win: Phase 3 invasion destroyed -> `victory("Human Navy")`.
- Player death: GM spawns a replacement (in-game "Spawn player ship"
  allowed); cargo drops as protected containers at the loss spot.

### Implementation notes (brief prose -> engine mechanics)

- Stations auto-hail players at scenario start and at milestones;
  everything else is player-initiated hailing.
- "Cargo" = physical pickup objects (`Artifact()`), name carried in the
  description; a destroyed carrier drops its cargo.
- "Scan to see contents" = **proximity reveal**: the engine never
  advances an `Artifact` through the scan states (only `SpaceShip`s go
  through them; artifacts are "created fully scanned"), so containers
  show generic descriptions in *all* scan states and the script flips
  base + every scan-state description once a player ship comes within
  5u ("fly close enough to read the shipping label"). Decoys always
  reveal "junk (spare parts)".
- Notification hails are sent by the *speaking* station (Tampere 1
  reports its own clearance, LUT 1 its liberation); only fleet-wide
  intel comes from Lumina 1. Messages are queued and retried while the
  player is inside another comms dialog, so nothing is dropped.
- Hidden stations = invisible to long-range radar until found (a player
  within 40u, or revealed by the hint chain).
- "Cannot be destroyed" = respawn guards: protected ships/objects that
  are destroyed re-dock or re-drop on the spot, so the mission can never
  become unwinnable.
- All hail->choice interactions = scripted comms with reply buttons
  (`setCommsFunction()` + `addCommsReply()`).

### Still to confirm

1. Difficulty: are the group sizes above right for the intended crew?
2. Phase 3: single final battle (current default), or several attrition
   waves?
