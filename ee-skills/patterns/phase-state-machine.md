# Phase state machine

**Problem.** "When does the mission advance, and what if it never can?" A phase
machine that only advances on scripted events stalls the moment a player does
something unexpected; one that advances on a sampled condition races with the
world.

**Facts.** Polling and organic-event timing:
[reference/runtime-pitfalls.md](../reference/runtime-pitfalls.md).

## Code

```lua
-- ========================= mission state =========================
clock = 0
phase = 1
done = false

function phase_check()
    if phase == 1 and delivered_count() >= #PART_NAMES then
        phase = 2
        notify("All components are in. Now the freighters - three carry Ansible Playbooks.",
               stations.home)
    elseif phase == 2 and playbook_count() >= #BOOK_NAMES then
        phase = 3
        notify("Intel: the enemy is coming here. Get back and dig in.", stations.home)
    elseif phase == 3 and threat_dead() and playbook_count() >= #BOOK_NAMES then
        done = true
        victory("Human Navy")
    end
end

function update(delta)
    clock = clock + delta
    if done then return end
    -- ... world simulation: watchers, respawns, position bookkeeping ...
    phase_check()
end
```

**Contract:**

* Exactly one `phase_check()`, called last in `update()`, so everything it reads
  is already settled for this tick.
* Every condition is an *observable world fact* (delivered count, all-dead group),
  never "the player talked to X" - unless talking is genuinely the requirement.
* Transition side effects (notifications, spawns) happen inside the branch, once,
  guarded by the `phase` assignment itself.
* `if done then return end` right after the clock: a finished mission must stop
  simulating, or the next tick can declare victory again.
* A "we are being attacked" phase also needs an escape: if the trigger group dies
  before the trigger fires, the watcher pattern
  ([guanteed-drop.md](guanteed-drop.md)) arms the phase anyway.

## Timers inside a phase

```lua
if phase == 2 and not hint_armed and clock > hint_after then
    hint_armed = true
    notify("Nothing found yet. Try the nebula cluster near " .. hint_sector(...), stations.home)
end
```

Two knobs (`hint_after`, plus any repeat interval) instead of a magic number in
the middle of logic, and a `*_armed` flag so the poll cannot fire twice. Remember
that `clock` advances only while the game runs (see pitfall #9).

## How to test it

One step per transition, with an `ee_until` for the world event that causes it:

```lua
ee_step(20, function()
    ee_until("phase 2 armed by the last delivery", 30, function() return phase == 2 end)
end)
```

Also assert the *negative*: at t=2 `ee_check(phase == 1, "mission starts in phase 1")`,
and in `ee_on_finish` assert `done == true` so a run that silently ended early is
still a failure.

## Variants and pitfalls

* **Optional objectives** need a *count* condition (`delivered >= required`), not
  a boolean, and the status page must show the count. ([status-page.md](status-page.md))
* **Branching** (`lut_state = "friendly" | "hostile" | "liberated"`) is a second,
  orthogonal state variable - keep it out of `phase` and gate phase conditions on
  it instead.
* **Never** advance a phase from inside a dialog callback *and* from the poll
  loop without a guard: two advances in one tick double-spawn the next phase's
  ships. `[obs]`
