# Guard respawn (slots that never duplicate)

**Problem.** A defended site should look defended all session, but respawn logic
written in a death hook either never runs (hook-less death) or fires every tick
(the classic "respawn conveyor" that eats the frame rate after ten minutes).

**Facts.** `onDestruction` is damage-only
([reference/runtime-pitfalls.md #1](../reference/runtime-pitfalls.md)); closures
and custom fields die with the object. `[src]` `[obs]`

## Code

```lua
guard_slots = {}

function mk_guard_slot(name, station, n, factory)
    table.insert(guard_slots, { name = name, station = station, timer = 0,
                                respawns_left = SC.respawns_max, ships = {}, n = n,
                                factory = factory })
end

function guard_update()                       -- called from update()
    for _, g in ipairs(guard_slots) do
        local alive = 0
        for i, s in ipairs(g.ships) do
            if s ~= "dead" and s ~= nil and s:isValid() then
                alive = alive + 1
            else
                g.ships[i] = "dead"           -- tombstone, never a hole
            end
        end
        if alive == 0 then
            if g.timer == 0 then g.timer = clock end
            if g.respawns_left > 0 and clock - g.timer >= SC.respawn_s then
                g.timer, g.respawns_left = 0, g.respawns_left - 1
                for i = 1, g.n do table.insert(g.ships, g.factory(g.station, i)) end
                print("guard slot " .. g.name .. " respawned (" .. g.respawns_left .. " left)")
            end
        else
            g.timer = 0                       -- partial replenish resets the clock
        end
    end
end
```

and the factory keeps spawn geometry honest:

```lua
function guard_factory(station, i)
    local x, y = eject_pos(station)                       -- clear of the hull
    local s = CpuShip():setTemplate("Adder MK5"):setFaction(station:getFaction())
        :setPosition(x, y)
    s:orderDefendLocation(x, y)                           -- leashed, not roaming
    return s
end
```

The three properties that make this safe:

* **The slot table is the truth**, so it survives the hull (`"dead"` tombstones
  keep indices stable and `ipairs` valid). `[obs]`
* **A single `timer` per slot** with `respawns_left`, so a site cannot be farmed
  and cannot spawn while anything lives.
* **`orderDefendLocation`** (or `orderDefendTarget(station)`) instead of `orderIdle`:
  parked guards are not engaged by AI attackers and end up invulnerable
  ([reference/ai-behaviour.md](../reference/ai-behaviour.md)).

## How to test it

```lua
-- a hook-less death must still respawn
ee_step(40, function()
    probe_kill_group("guards_home")
    ee_until("slot respawns after a hook-less wipe", SC.respawn_s + 20, function()
        return not all_dead(groups.guards_home)
    end)
end)
ee_step(80, function()
    -- the invariant, not the count: never more than n per slot, ever
    local alive = 0
    for _, s in ipairs(groups.guards_home) do if s:isValid() then alive = alive + 1 end end
    ee_check(alive <= SC.patrol_n, "no spawn conveyor: at most one full squad alive")
end)
```

`RUNTIME=600 AUTOTEST=none ee_func.sh <scenario>` (long idle, no driver) is the
companion check: grep the log and confirm the respawn line appears at most
`respawns_left` times.

## Variants and pitfalls

* **Respawn when partially destroyed**: change `alive == 0` to
  `alive < g.n` and gate on the timer only; keep `respawns_left` or you get the
  conveyor with extra steps.
* **The defended object can die**: if `station` is destroyed, stop the slot
  (`if g.station == nil or not g.station:isValid() then goto end end`) -
  respawning guards around a wreck reads as a bug.
* A slot whose ships are the *mission's* delivery mechanism must also be watched
  by a drop-watch; the respawn clock does not drop their cargo.
  ([guanteed-drop.md](guanteed-drop.md))
