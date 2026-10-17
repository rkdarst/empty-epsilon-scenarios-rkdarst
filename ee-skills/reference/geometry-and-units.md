# Geometry, units and distances

## Units

* Script coordinates are **1000 script units = 1 displayed unit ("u")**. Define
  `U(u) = u * 1000` once at the top of the scenario, keep all tunables in u, and
  never write a bare 5-digit number in logic. `[ref]` `[obs]`
* Speeds: `setWarpSpeed(1000)` == 60 u/s; impulse values are sub-light. `[obs]`
* The engine's own defaults you will meet: short-range radar 5000 (5u),
  set in the `SpaceShip`/template constructors (`shipTemplateBasedObject.cpp`,
  `shipTemplate.cpp`). `[src]`

## The sector grid

* Sectors are 20 000 script units (20u) on a square grid; the client labels them
  **letters for rows (A at the top), numbers for columns (1 at the left)** —
  `C10` is row C, column 10. `[obs]`
* `sectorToXY("C10")` gives the **lower-left corner** of that square, so the
  centre is `x + 10000, y + 10000`. `[ref]` `[obs]`
* `getSectorName(x, y)` is the inverse and is what you should put in hint text.
* **Row letter and X are uncorrelated** (observed in engine seeding): letters
  cluster north, numbers spread both ways. Never promise "sector X is at
  coordinates Y" in prose; name the sector and add a drift margin instead. `[obs]`

## Station hulls

Station templates carry a model radius in the shipped `scripts/model_data.lua`;
the values that matter for placement:

| Template | Radius | In u |
|---|---|---|
| Small Station (`space_station_4`) | 300 | 0.3u |
| Medium Station | ~1000 | 1.0u |
| Large Station (`space_station_3`-class) | ~1300 | 1.3u |

Consequences, all observed:

* A **container ejected at a fixed 0.65u from a Medium station is inside the
  hull**, and since pickup is collision-based it can never be collected. Eject
  from `hull + 0.35u`. `[obs]`
* "Come alongside" must scale with the hull: a flat 1u gate is fine for a Small
  station and impossible to read at a Large one. Use
  `handover_u(st) = max(min_gate, hull_u + 0.4)`. `[obs]`
* `isDocked(target)` has **no distance tolerance** - it is a pure state check
  (`docking_state == DS_Docked && docking_target == target`, spaceship.h:339).
  Docking *completes* when a docking ship touches the target within 10° of
  alignment (spaceship.cpp `SpaceShip::collide`), and a dock can be requested
  from up to `1000 + target->getRadius()` (spaceship.cpp:1312). A docked ship
  rests just off the hull surface, so any distance gate tighter than `hull_u`
  must accept `isDocked` explicitly. `[src]`
* Spawning a ship at the station's exact position overlaps the hull; use a ring
  position outside it. `[obs]`
* Keep a `template -> radius` table in the scenario and set a custom field
  (`st.scen_template = tmpl`) at build time, because there is no
  "what template is this station" getter. `[obs]`

## Distances worth memorising

| Quantity | Value |
|---|---|
| 1 sector | 20u |
| Nebula cloud radius | ~5u |
| Short-range radar | 5u |
| Dock request range | 1u + target hull radius (dock *completion* is collision contact) |
| Container ejection ring | hull + 0.35u |
| Comfortable station spacing | >= 25u (a sector apart reads as "a trip") |
| Asteroid belt node spacing | 3-6u so it looks like a band |

## Practical geometry recipes

* **Ring around a station:** `x + cos(a)*U(r), y + sin(a)*U(r)` with
  `a = random(0, 6.283)`; use it for escort formations, container drops and
  decoy fields. `[obs]`
* **Search ring instead of a square:** scattering N nebulae on a ring of
  10-18u around a station keeps a search inside one sector and reads as a sweep;
  the same count in a +-25u square spreads it over 1-2 sectors and players give
  up. `[obs]`
* **Wormholes need offset exits.** The client's link test and the server's
  `Wormhole::getLinkedWormhole()` are collinearity tests, so two mouths at the
  same Y never link, and co-located mouths oscillate (the destination is
  "inside" the source on the next tick). Put each exit `3-4u` beyond the far
  mouth, aimed at the other mouth. `[src]` `[obs]`
