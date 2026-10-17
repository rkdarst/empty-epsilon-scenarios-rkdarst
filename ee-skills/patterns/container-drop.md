# Container drop (cargo crates)

**Problem.** Cargo you can see, fly to, and pick up - with a label that means
something *before* and *after* the crew investigates it.

**Facts.** Artifacts have no scan-state machine; pickup is collision-based and
**fires for `PlayerSpaceship` collisions only** - an AI ship flying over a
pickupable crate can never take it (`Artifact::collide` casts the collider to
`P<PlayerSpaceship>` and ignores everything else), so ambient traders cannot
steal objectives. The engine destroys the artifact itself right after the
callback. Hull radii decide where a crate is reachable:
[reference/geometry-and-units.md](../reference/geometry-and-units.md),
[reference/runtime-pitfalls.md #7](../reference/runtime-pitfalls.md). `[src]` `[obs]`

## Code

```lua
containers = {}
LABEL_FAR = "An unmarked cargo container."

function container_text(a, text)
    a:setDescription(text)
    a:setDescriptionForScanState("notscanned", text)
    a:setDescriptionForScanState("simplescan", text)
    a:setDescriptionForScanState("fullscan", text)
end

function mk_container(desc, x, y, far)
    local a = Artifact():setModel("artifact6"):setPosition(x, y):setSpin(0.3)
    container_text(a, far or LABEL_FAR)
    local c = { a = a, desc = desc, far = far or LABEL_FAR, name = nil, revealed = false }
    table.insert(containers, c)
    return a, c
end

function reveal_container(c)
    c.revealed = true
    if c.a:isValid() then container_text(c.a, c.desc) end
    print("container revealed: " .. c.desc)
end

function mk_part(name, x, y)
    parts[name] = parts[name] or { carried = false, delivered = false }
    local a, c = mk_container("Cargo container: " .. name .. ". Fly over it to collect.", x, y)
    c.name = name
    parts[name].cont, parts[name].obj = c, a
    parts[name].drop_x, parts[name].drop_y = x, y
    parts[name].drop_sector = getSectorName(x, y)      -- so a hint can name the place
    a:allowPickup(true)
    a:onPickUp(function(art, ship)
        math.abs(0)
        if parts[name].obj == art and art:isValid() then art:destroy() end
        parts[name].carried = ship
        notify("Cargo bay secured: " .. name)
    end)
    a:setCommsFunction(function(comms_source, comms_target)
        math.abs(0)
        if c.revealed then
            setCommsMessage("Automated cargo container. Contents: " .. c.desc)
        else
            setCommsMessage("Automated cargo container. Come closer to read the label.")
        end
        return true
    end)
    return a
end
```

Reveal it in the poll loop, not in a hook:

```lua
for _, c in ipairs(containers) do
    if not c.revealed and c.a:isValid() then
        for _, p in ipairs(players) do
            if d2(p, c.a) < U(REVEAL_U) ^ 2 then reveal_container(c) break end
        end
    end
end
```

Where the crate is *placed* matters: use `eject_pos(station)` so it clears the
hull, and remember `drop_x/drop_y/drop_sector` so a hint line can say "the crate
was last seen near sector F8" instead of leaving it unrecoverable. `[obs]`

## How to test it

```lua
ee_check(probe_part("Nav core") == "adrift", "crate exists")
ee_eject_clear("core drop", parts["Nav core"].obj, stations.depot,
               station_hull_u(stations.depot), handover_u(stations.depot))

-- two-state label, both directions
probe_warp_to(x + U(REVEAL_U + 2), y)
ee_check(not c.revealed, "label unreadable beyond the reveal radius")
probe_warp_to(x + U(2), y)
ee_until("label resolves once alongside", 6, function() return c.revealed end)
```

**A teleported ship does not trigger `onPickUp`** (collision-based), so the driver
uses a probe hook that performs the same bookkeeping - and the real collision path
goes on the human-acceptance checklist. `[obs]`

## Variants and pitfalls

* **Decoys**: `mk_junk()` = same builder with `allowPickup(false)` and a junk
  label pair, so a search field has texture without inflating the objective count.
* **Blown-up crates**: a crate is destructible; treat "no longer valid and not
  carried" as *missing* and let the drop-watch re-drop it
  ([guanteed-drop.md](guanteed-drop.md)). Never assume the crate you dropped is
  the crate that ends the mission.
* **Two crates at one position** makes the pickup ambiguous in the log; offset by
  at least 0.5u.
* **Do not** rely on `isScannedBy` for artifacts - they are created fully scanned. `[src]`
