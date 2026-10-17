# Hidden station (and its reveal)

**Problem.** "A station our people built, but the crew must not know it is there
until they arrive." The intuitive implementation - park it in a nebula and zero
its radar - does not work for a friendly station: on the relay radar every
friendly object is always drawn (it seeds its own sight bubble), and nebulae
only shadow the science/main long-range radar. `[src]` `[obs]`

**Facts.** [reference/sensors-and-visibility.md](../reference/sensors-and-visibility.md).

## Code

```lua
-- Build it as what it really is (ours), then take it off the map by taking away
-- the thing that makes it visible: its faction identity.
function hide_station(st, reveal_to)
    st.scen_hidden = true
    st.scen_reveal_to = reveal_to          -- faction it adopts when found
    st:setFaction("Independent")
    pcall(st.setShortRangeRadarRange, st, 0)   -- also invisible on the local radar
    return st
end

-- One-way and idempotent: the crew found it by flying close enough to see it.
function reveal_station(st)
    if st == nil or not st:isValid() then return end
    if not st.scen_hidden or st.scen_revealed then return end
    st.scen_revealed = true
    if st.scen_reveal_to then st:setFaction(st.scen_reveal_to) end
    pcall(st.setShortRangeRadarRange, st, 5000)     -- the engine default
end

-- In update(): the trigger is proximity, not scanning.
if not found[name] then
    for _, p in ipairs(players) do
        if d2(p, stations[name]) < U(FIND_U) ^ 2 then
            found[name] = true
            reveal_station(stations[name])
            notify("We are getting a friendly IFF from a station that was not there a minute ago.",
                   stations[name])
            break
        end
    end
end
```

`FIND_U` should sit just outside the short-range radar radius (5u): by the time
the reveal fires the crew has *already* seen the hull on their scope, so nothing
feels like cheating. 6u is a good default. `[obs]`

**Variants.**
* *Hostile-looking*: keep it `Independent` permanently and let the story explain
  it; the reveal is then only a notification.
* *Ambush on arrival*: use the hidden station as the trigger point and spawn the
  ambush group in the same branch - a faction flip is the cleanest way to make the
  fight legible on the radar.

## How to test it

```lua
ee_step(6, function()
    ee_check(stations.relay:getFaction() == "Independent",
        "hidden station boots without our transponder")
end)
ee_step(8, function()
    probe_warp_to(U(28), 0)
    ee_until("flips to our faction when reached", 10,
        function() return stations.relay:getFaction() == "Human Navy" end)
end)
```

Also assert it **did not** flip early (the `ee_check` at t=6 is exactly that),
otherwise a knob slip turns the whole mission into an open map and the suite
still goes green.

## Variants and pitfalls

* A hidden station must not be a comms contact before the reveal: `Independent`
  handles that, but so does forgetting to attach the page function until the
  reveal - do the latter if the station has real dialogue.
* Zeroing the radar range on a station you *want* visible across the sector is
  wrong: only the local radar is affected. Use the faction flip only. `[src]`
* Reveal on `isScannedBy(player)` instead of distance if the reveal should be
  earned by the science officer; in that case the poll needs a player-object
  check and cannot be tested headless without a probe hook.
