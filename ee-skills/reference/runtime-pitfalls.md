# Runtime pitfalls

The traps that cost the most debugging time. Each one is a *verified* engine
behaviour plus the rule it forces on a scenario.

## 1. `onDestruction` fires only on damage kills

`onDestruction(obj, instigator)` is emitted from the damage path
(`SpaceObject::takeHullDamage`). A **script `destroy()`**, a GM removal, or a
death that is not damage-driven never reaches that call site, so nothing a hook
would have done happens: no dropped container, no spill, no respawn. `[src]` `[obs]`

> **Rule.** Anything a mission *requires* to happen on a death must ALSO be
> driven by a polled watcher in `update()` that notices "this group is gone and
> the object is unaccounted for". Hooks are a fast path, never the truth.
> Recipe: [patterns/guanteed-drop.md](../patterns/guanteed-drop.md).

Scripts cannot create a damage event: there is no script-callable
`takeHullDamage`, and the one apparently-damage-taking constructor form
(`Missile(takeDamageFrom)`) does not run the kill path. `[obs]`

For tests the organic killer is a mercenary **Starhammer II** squad: that AI
fires only HVLI tubes (`ShipAI::runAttack` never fires beams), so give it warp
drive to catch fleeing targets. AI kills take ~20-45 s of game time, and the
engine never drops a stale attack order, so a driver must retarget and prevent
camping - see [testing/writing-drivers.md](../testing/writing-drivers.md). `[obs]`

## 2. A custom dialog action must not re-render its own page

The engine clears all replies, runs the clicked callback, and **every
`setCommsMessage` inside that callback replaces the message text**. A callback
that ends by re-running the page function therefore overwrites its own result
line with the page text - the click looks dead. `[src]` `[obs]`

> **Rule.** Split every dialog: `commsX(t, src)` sets text once and calls
> `commsX_replies(t, src)`, which only adds choices. A callback sets its result
> text and then calls `commsX_replies` - choices only. Assert the invariant "one
> rendered message per action" in the driver.

## 3. `sendCommsMessage` returns false when the crew is busy

It is a *now-or-never* call: if that player is inside another dialog it returns
false and the message is gone. `[ref]` `[obs]`

> **Rule.** Route every notification through a queue with a retry deadline and a
> per-recipient done-set. Recipe: [patterns/notify-queue.md](../patterns/notify-queue.md).

## 4. `Player.get()` does not exist; ship-side dialogs need a fallback

Comms *functions* receive only `comms_source`, and there is no `Player.get()` in
2024.12. Ship-to-ship dialogs also have no player-side menu entry. `[ref]` `[obs]`

> **Rule.** Bind the object in the closure, and fall back to
> `getActivePlayerShips()[1]`. Put *state-changing* transfer actions on the
> station page (one click instead of hail - open - click) and keep the ship page
> for receiving.

## 5. Two objects at the same coordinates are not a wormhole

The client draws a link only when its own position lies on the segment
`A.pos -> B.pos`; the server's `Wormhole::getLinkedWormhole()` uses the same
collinearity test. Parallel pairs and side-by-side pairs are silently one-way -
and a pair sharing coordinates makes the engine warp an object into itself, so
the next tick's "inside the wormhole" test teleports it back and the object
oscillates forever. `[src]` `[obs]`

> **Rule.** Give each mouth an offset exit 3-4u beyond its far side, aimed at the
> other mouth. Recipe: [patterns/world-seeding.md](../patterns/world-seeding.md).

## 6. `Nebula` is visual, not a radar shadow

Setting an object's radar signatures to zero hides it from *both* radar layers -
but a nebula on its own only blocks the **long-range** radar; the short-range
layer still paints everything. And objects of the crew's own faction are always
on their contact list regardless of any of that. `[src]` `[obs]`

> **Rule.** "Hidden from the crew" = faction neutrality (optionally plus a
> zeroed short-range radar while dark). Recipes:
> [patterns/hidden-station.md](../patterns/hidden-station.md),
> [patterns/radar-dark-tug.md](../patterns/radar-dark-tug.md).

## 7. Artifacts have no scan-state machine

Only ships advance through notscanned - simplescan - fullscan; artifacts are
created "fully scanned". Writing one scan state's description therefore does
nothing visible in the other states. `[src]` `[obs]`

> **Rule.** Write the current story text into the base description **and** all
> three scan states at once, then flip all four together on a scripted story
> transition. Recipe: [patterns/container-drop.md](../patterns/container-drop.md).


## 8. Station hull radius decides "alongside"

Hull radii come from the shipped `scripts/model_data.lua` templates (station
templates are roughly 0.3u / 1.0u / 1.3u for Small/Medium/Large; 1u = 1000
script units). A container ejected at a fixed 0.65u from a Medium station sits
*inside the hull* - and pickup is collision-based, so it can never be collected.
`isDocked()` is strict (within 500 units), so a distance test must also accept
docking. `[src]` `[obs]`

> **Rule.** Look hull radii up from data, derive the hand-over bubble from the
> hull, eject between the hull surface and that bubble, and let docking satisfy
> any range gate. Details: [geometry-and-units.md](geometry-and-units.md).

## 9. Timers need a tick floor

`update(delta)` is tick-driven and the log timestamps are wall-clock, so
"nothing happened for 28 s" can be an idle-paused world rather than a broken
timer. `clock = clock + delta` timers also never fire while the game is paused. `[obs]`

> **Rule.** Any timer that must be robust against tick jitter needs a
> `if clock > last_seen + N` floor, and any test of it must set `SMOKE_SETTLE`
> above the timer value.

## 10. `pcall` your way through dying objects

Reading a script field off an object that was destroyed in the same tick raises
"attempt to index a nil value"; one bare loop over stale references can kill a
whole tick. `[obs]`

> **Rule.** `local ok, v = pcall(function() return obj.field end)`, and keep a
> script-side mirror table (position, call sign, cargo, time of death) for
> anything a hook needs after the hull is gone.

## 11. Stock player hulls have no FTL

Templates including the Phobos M3P players spawn in with **no warp drive**, so a
multi-sector mission is unplayable after the first jump unless the scenario
installs one. `[obs]`

> **Rule.** `ensure_ftl()` in the poll loop, guarded by `hasWarpDrive()`, so late
> joiners and GM respawns are covered too.

## 12. Ambient generators need a budget

Seeding the world is the slow part of `init()`: ~2000 nebulae cost ~16 s of load
time. Cap the counts, prefer few large clouds, and log a seed census. `[obs]`

> **Rule.** Count and log everything you add (`... seeded nebulae=N ... total=M`) -
> that line doubles as the smoke test's world census. Recipe:
> [patterns/world-seeding.md](../patterns/world-seeding.md).

## 13. A headless run has players but no clients

A `PlayerSpaceship()` created by the scenario *is* an active player ship, but
nothing drives it: it never moves on its own, never opens a dialog, and - because
pickup is collision based - a scripted `setPosition()` onto a crate does **not**
fire `onPickUp`. `[obs]`

> **Rule.** Any mechanic that depends on real movement or on the client needs a
> probe hook that stands in for it (`probe_pickup`, `probe_warp_to`) while
> sharing the same bookkeeping function as the real path, plus a line on the
> human-acceptance checklist. See
> [testing/runtime-surprises.md](../testing/runtime-surprises.md).
