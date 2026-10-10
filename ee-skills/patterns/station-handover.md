# Station hand-over (give / take cargo)

**Problem.** "Deliver the part to the station" must be a *physical* condition the
player can see, not a script flag - and it has to work when the player is docked,
alongside, or (wrongly) 40u away.

**Facts.** Hull radii, `isDocked` tolerance and the eject ring:
[reference/geometry-and-units.md](../reference/geometry-and-units.md).

## Code

```lua
STATION_HULL_U = { ["Small Station"] = 0.3, ["Medium Station"] = 1.0, ["Large Station"] = 1.3 }

function station_hull_u(st) return STATION_HULL_U[st.scen_template] or 0.3 end

-- "Next to the hull": a flat minimum for small stations, growing with the hull.
function handover_u(st)
    local r = station_hull_u(st) + 0.4
    if r < HANDOVER_U then r = HANDOVER_U end
    return r
end

-- Docking always satisfies a range gate; otherwise plain distance.
function near_or_docked(a, b, u)
    if a == nil or b == nil then return false end
    local docked = false
    pcall(function() docked = a:isDocked(b) end)      -- strict: < 500 units
    if docked then return true end
    return d2(a, b) < U(u) ^ 2
end

-- The action, called from a dialog callback (see dialog-page.md).
function act_deliver(station, ship)
    if ship == nil or not ship:isValid() then return "Nobody is alongside." end
    if not near_or_docked(ship, station, handover_u(station)) then
        return "Come alongside the station to hand the cargo over."
    end
    local n = 0
    for _, name in ipairs(PART_NAMES) do
        local info = parts[name]
        if info and info.carried and info.carried == ship then
            info.carried = false
            info.delivered = true
            n = n + 1
        end
    end
    if n == 0 then return "Your cargo bay holds nothing we need." end
    return ("Received %d item(s); %d of %d accounted for."):format(
        n, delivered_count(), #PART_NAMES)
end
```

`st.scen_template` has to be set at build time - there is no "what template is
this" getter - and carrying is tracked as the *ship object*, so two ships cannot
both deliver the same crate. `[obs]`

## How to test it

Both directions, always - the refusal is the part that silently rots:

```lua
-- refused from open space, and it changed nothing
local d = ee_dlg_open(commsDepot, stations.depot, active_players()[1])
local m = ee_dlg_click(d, 2, stations.depot, active_players()[1])
ee_check(m[1]:find("alongside") ~= nil, "hand-over from open space is refused")
ee_check(delivered_count() == 0, "refused hand-over delivered nothing")

-- accepted from alongside (Medium station: hull 1.0u, so 1.2u is 'next to it')
probe_warp_to(-U(20) + U(1.2), 0)
m = ee_dlg_click(d, 2, stations.depot, active_players()[1])
ee_check(m[1]:find("Received") ~= nil, "hand-over from alongside is accepted")
```

And the geometry assertion on the *drop* side, so a crate can always be reached
from the hand-over position:

```lua
ee_eject_clear("core drop", crate, stations.depot,
               station_hull_u(stations.depot), handover_u(stations.depot))
```

## Variants and pitfalls

* **Take** (station gives cargo): same gate, and the station must refuse when the
  bay is full (`getMaxAttackWeapons`-style capacity checks are per-template; the
  simple version is one item per delivery action).
* **Ship-to-ship transfer**: no player-side menu exists in 2024.12, so implement
  it as "hail the other ship" from the *station* page or as a ship page with a
  distance gate (`d2(a,b) < U(2)^2`) between the two hulls. `[obs]`
* A gate tighter than ~0.7u is unreachable while docked unless you accept docking
  explicitly (this recipe does). A gate looser than ~5u triggers before the player
  believes they arrived.
