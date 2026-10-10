# World seeding (ambient density, belts, wormholes, load time)

**Problem.** A sector that is empty except for objectives plays like a menu. Filling
it costs load time and, if generated carelessly, breaks the mission (unwinnable
geometry, invisible hazards).

## Budget first, generate second

Measure once: ~2000 nebulae ≈ 16 s of `init()`. `[obs]` So:

```lua
AMBIENT = { nebula_frac = 0.10, nebula_max = 260, belts = 6,
            belt_dust = 4, belt_rocks = 2, mine_fields = 5, wrecks = 7,
            traders = 6, wormholes = true }
```

and always print the census, which doubles as the smoke test's world check:

```lua
print(("ambient seeded nebulae=%d dust=%d rocks=%d mines=%d wrecks=%d traders=%d " ..
       "wormholes=%d total=%d"):format(...))
```

Prefer `VisualAsteroid` (decoration, no collision, no physics) for gravel and
real `Asteroid` only where the hazard should be real. Cap everything derived from
a fraction — a bigger map must not silently double the load.

## Belts

A belt reads as a *band*: a line of nodes with jitter, 3-6u apart, each node a
handful of rocks and a dozen VisualAsteroids. Randomly scattered rocks of the
same count read as noise, not as terrain.

```lua
for i = 1, AM.belts do
    local bx, by = lerp(box.x0, box.x1, i / (AM.belts + 1)), box.y0 + random(-U(5), U(5))
    for j = 1, AM.belt_rocks do
        Asteroid():setPosition(bx + random(-U(3), U(3)), by + random(-U(3), U(3)))
    end
    for j = 1, AM.belt_dust do
        VisualAsteroid():setPosition(bx + random(-U(4), U(4)), by + random(-U(4), U(4)))
    end
end
```

## Nebulae

`Nebula():setPosition(x, y)` has no size argument; the cloud is ~5u in radius. `[obs]`
Two rules:

* For a *search area*, place N clouds on a ring (10-18u radius, even bearing
  spacing + jitter) rather than in a square - a ring keeps the sweep inside one
  sector and reads as "search this region". `[obs]`
* A nebula shadows only the long-range layer; it does not hide anything from a
  ship that flies into it. For actual hiding use
  [hidden-station.md](hidden-station.md) / [radar-dark-tug.md](radar-dark-tug.md). `[src]`

## Wormholes: the geometry is the whole recipe

Both the client's link line and the server's `Wormhole::getLinkedWormhole()` are
**collinearity tests** against the segment between the two mouths. Therefore: `[src]`

* two mouths at the same Y (or X) are **not** connected for anything that is not
  exactly on that line - it looks like a broken feature;
* two mouths at the *same coordinates* oscillate: the warp destination is
  "inside" the source, so the next tick warps it back;
* the working shape is a pair of mouths with an **offset exit** 3-4u beyond the
  far mouth, aimed at the other mouth, so an object arriving from any direction
  is nearly collinear with the link.

```lua
function link_pair(a, b, offset)
    local ax, ay = a:getPosition(); local bx, by = b:getPosition()
    local dx, dy = bx - ax, by - ay
    local d = math.sqrt(dx * dx + dy * dy)
    -- exit of a: beyond b, 3.5u past it, pointing back through b
    a:setExitLocation(bx + dx / d * U(offset), by + dy / d * U(offset))
    b:setExitLocation(ax - dx / d * U(offset), ay - dy / d * U(offset))
end
```

Then assert it in a driver: `getDistance(a, b)` and the two exit points must not
coincide with any mouth, and (best) put a ship at the mouth and poll for its
position changing.

## Mines, wrecks, traders

* **Mines** are invisible until scanned at short range and one-shot a hull; a
  derelict ringed with mines is a great hazard with no code. Ring radius ~1u so it
  reads as "do not dock here". `[obs]`
* **Wrecks** = `CpuShip` with a destroyed template or a VisualAsteroid cluster;
  a wreck with a call sign and no crew is a comms object, which is a nice free
  flavour beat.
* **Traders** make the sector feel inhabited *and* are your free objective
  carrier. Give them `orderFlyTowards` legs between two stations and a
  `respawn_s`; the spill/respawn logic is in
  [guanteed-drop.md](guanteed-drop.md). `[obs]`

## How to test it

* The census line must match the knobs (an assertion, not a comment).
* Nothing may spawn inside a station hull or inside another generator's hazard:
  a 20-line loop over `getAllObjects()` that reports pairs closer than 0.4u is
  the cheapest quality gate you will ever write. `[obs]`
* Keep the load-time budget in the smoke test's timeout: if `init()` gets slower,
  the boot check should be the thing that notices.
