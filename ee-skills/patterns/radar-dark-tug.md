# Radar-dark tug (a needle in the haystack)

**Problem.** "Something is out there, go look for it" needs an object the crew
cannot see at range, cannot shoot before they find it, and can actually catch. A
station cannot do this (fixed position, always a contact for its own faction); a
normal ship cannot (radar paints it across the sector).

**Facts.** Radar visibility is the signature triple; nebulae shadow only the
long-range layer; a parked ship is not engaged by AI. `[src]` `[obs]`

## Code

```lua
-- The decoy: slow, tiny signature, harmless, and the only way to find the payload.
function mk_dark_tug(x, y)
    local s = CpuShip():setTemplate("Tug"):setFaction("Independent")
        :setPosition(x, y):orderRoaming()
    s:setRadarSignatureBiological(0)
    s:setRadarSignatureElectrical(0)
    s:setRadarSignatureGravity(0)
    s:setHull(20)                       -- one HVLI hit; it must never be the puzzle
    s:setCallSign("Salvage tender")
    s:setCommsFunction(function(comms_source, comms_target)
        math.abs(0)
        setCommsMessage([[Derelict-looking tender, no crew response on any channel.
Its cargo manifest display reads: "cache beacons - see station register".]])
        return true
    end)
    return s
end
```

Three properties, each one load-bearing:

* **Zeroed signatures** take it off both radar layers, so it appears only inside
  visual range - the hunt is the point. `[obs]`
* **`orderRoaming()`** keeps it moving (catchable, and it never gets stuck behind
  an asteroid) while remaining *unarmed*, so a reckless approach is not punished.
* **Independent faction**: not on the crew's contact list, and it will not attack.

Give it a *hint* payload (a comms line, a coordinate) rather than the objective
itself, so finding it is a step and not the finish.

## Pairing it with a decoy field

A search is only fun if a failure is informative. Scatter 2-3 real-but-worthless
containers with `allowPickup(false)` and a junk label
([container-drop.md](container-drop.md)) around the same region, so "nothing here"
is a conclusion the crew can reach rather than a guess.

## How to test it

```lua
ee_step(30, function()
    local ok, sig = pcall(function() return tug:getRadarSignatureElectrical() end)
    ee_check(not ok or sig == 0, "decoy has no electrical signature")     -- API varies
    ee_check(tug:isValid(), "decoy still exists at t=30")
end)
```

Whether the object is *actually invisible on screen* is a client-side property and
belongs to the 30-minute human session
([testing/human-acceptance.md](../testing/human-acceptance.md)) - headless can
only prove the signature values are what the recipe claims. `[obs]`

## Variants and pitfalls

* **Need it invisible to torpedoes too?** Zeroed signatures do that as a side
  effect (no lock), which is usually desirable for a decoy and fatal for an
  enemy - test which one you built.
* **Need it findable by the science scanner?** Then zero only the *electrical*
  signature; biological/gravity returns give the scanner something to bite on. `[obs]`
* Do **not** hide a friendly station this way - use the faction flip
  ([hidden-station.md](hidden-station.md)). A zero-signature friendly station is
  invisible to the crew *and* to their torpedoes, which reads as a bug.
