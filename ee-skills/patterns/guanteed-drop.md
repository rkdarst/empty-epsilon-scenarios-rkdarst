# Guaranteed drop (hook-less deaths must not softlock)

**Problem.** A guard / carrier / escort group is supposed to leave a cargo
container behind when it dies. Implemented with `onDestruction` alone, the mission
becomes unsolvable whenever that group dies in a way the engine does not treat as
a damage kill — a script `destroy()`, the GM removing a ship, or a collision-only
death. `onDestruction` is emitted only from the damage path. `[src]` `[obs]`

**Facts it comes from.** [reference/runtime-pitfalls.md #1](../reference/runtime-pitfalls.md).

## Code

```lua
drop_watches = {}

-- Poll `group`; when every member is gone and the object is unaccounted for,
-- hand the last known position to on_drop(x, y). `grace` lets the real hook win.
function mk_drop_watch(key, group, on_drop, grace)
    local w = { key = key, group = group, on_drop = on_drop,
                grace = grace or 10, drops = 0, done = false }
    table.insert(drop_watches, w)
    return w
end

function drop_watch()
    for _, w in ipairs(drop_watches) do drop_watch_run(w) end
end

function drop_watch_run(w)
    if w.done then return end
    for _, s in ipairs(w.group) do
        if s:isValid() then                 -- somebody is still out there
            w.x, w.y = s:getPosition()
            w.alive_at = clock
            return
        end
    end
    if accounted(w.key) then return end
    w.alive_at = w.alive_at or clock
    if clock - w.alive_at < w.grace then return end
    w.drops = w.drops + 1
    if w.drops >= 2 then w.done = true end  -- never spam crates every tick
    w.on_drop(w.x or 0, w.y or 0)
    print("drop watchdog fired for " .. w.key)
end

-- "Handled" = delivered, in a cargo bay, or a crate that still exists. A crate
-- destroyed before anyone reached it is NOT handled.
function accounted(key)
    local info = parts[key]
    if info == nil then return false end
    if info.delivered or info.carried then return true end
    if info.obj == nil then return false end
    local ok, valid = pcall(function() return info.obj:isValid() end)
    if ok == false or valid then return true end
    return false
end
```

Call `drop_watch()` from `update()`. Wire the hook as usual too — the hook is the
fast path and gives the nicer `instigator`-aware message; the watcher only covers
for the engine's silence.

**Variants.**
* Carrier-with-cargo: keep a script-side slot per hull (position, call sign,
  cargo, `dead_at`) and drive both the spill and the respawn from it — the hook
  data dies with the ship.
* Multiple watchers on the same key are safe because `accounted()` is the gate.

## How to test it

```lua
ee_step(16, function()
    probe_kill_group("patrol")            -- destroy(), i.e. deliberately hook-less
    ee_until("watchdog drops the crate after a hook-less kill", grace + 15,
        function() return probe_part("Nav core") == "adrift" end)
end)
```

Then prove the *other* half too, or the watcher will silently replace the hook:
spawn a fresh group, kill it **organically** with the merc squad, and assert the
crate count did not increase (`drops` and `accounted()` are what keep it at one).

## Variants and pitfalls

* **Never** assert the drop at a fixed time — an AI kill takes ~20-45 s. Poll. `[obs]`
* A watcher whose group *never spawns* fires at `grace` after start: initialise
  `alive_at` when the group is created if you want "never spawned" to mean
  "nothing to drop", or seed `w.x/w.y` with the intended coordinates.
* Cap `drops` at 1-2. An uncapped watcher plus a crate the crew cannot reach (see
  [container-drop.md](container-drop.md)) means an endless crate conveyor.
* The merc squad that provides the organic kill camps on radar-dark or
  fast-fleeing targets; the retarget + one-clean-drop-in logic in
  [testing/writing-drivers.md](../testing/writing-drivers.md) is part of this
  recipe, not a test detail.
