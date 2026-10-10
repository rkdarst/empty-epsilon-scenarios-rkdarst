# Flow diagrams

Reference diagrams for the mental model behind every recipe. ASCII so it survives
a grep and diffs cleanly; `ee-skills/examples/demo/` implements the first two.

## 1. How a scenario runs

```
 game boot
     |
     |-- parse header comments ----> mission list entry (Type missing -> "Unknown")
     |-- concatenate scenario_*.lua + scripts dir  (ONE Lua chunk)
     |-- run chunk top level  ...... knobs, helpers, tables  (no objects yet!)
     |-- init() ................... build the world, register hooks/pages
     |
     +--> tick loop ------------- update(delta) -----------------------+
     |                            |  clock += delta (0 while paused!)  |
     |                            |  ensure_ftl / pump_messages        |
     |                            |  per-object watchers (new hulls)   |
     |                            |  watchers: reveal / drop / respawn |
     |                            |  phase_check -> victory()          |
     |                            +------------------------------------+
     |                                  ^                    |
     |                                  +--------------------+
     |                            (every tick; state lives in tables)
     |
     +-- callbacks, whenever the engine decides:
           setCommsFunction  -> dialog page / reply callback
           onDestruction     -> ONLY from takeHullDamage (damage kills)
           onPickUp          -> collision-based, needs real movement
```

The single most common bug this diagram explains: logic in the chunk's top level
runs **before** `init()`, so anything reading world objects there sees nil. `[obs]`

## 2. Dialog click, as the engine executes it

```
 player clicks choice #i
     |
     |-- clear all replies
     |-- clear message text ? (no: previous text stays until overwritten)
     |-- run callback i
     |      |
     |      |-- setCommsMessage(A)          <- your result text
     |      |-- addCommsReply(...)          <- re-add choices
     |      |-- (if you also re-run the PAGE function:
     |      |     setCommsMessage(page text) -> OVERWRITES A. Click looks dead.)
     |      `-- return true
     +-- client renders: one message + the choices
```

Hence the two rules in [patterns/dialog-page.md](../patterns/dialog-page.md) and
the assertion `#rendered_messages == 1` in every driver. `[src]` `[obs]`

## 3. "The crate must exist" - hook vs watcher

```
 guard squad alive ------ every tick: remember last known position
     |
     +-- killed by beams/tubes ----> onDestruction(ship, killer) --> mk_part(x,y)  [fast path]
     |
     +-- destroyed by script/GM ----> (no hook at all)
                                              |
     every tick, all guards invalid ----------> v
        part_accounted("X") ?  -- yes --> nothing to do
                              \-- no  --> clock - last_alive >= grace ?
                                              yes --> mk_part(last_x, last_y)  [once]
```

Both arrows converge on the same `mk_part`, which is idempotent because
`part_accounted()` gates it. That is the whole anti-softlock story in one picture
([patterns/guanteed-drop.md](../patterns/guanteed-drop.md)).

## 4. Testing pyramid

```
                 +------------------------+
                 | 30-min human session   |  client-side: feel, visibility, UX
                 +------------------------+
              +------+ ee_play.sh -------+
              | full-mission driver      |  phases, dialogs, geometry, softlock
              +--------------------------+   ee_func.sh (1-4 min, ~100 asserts)
            +-+ smoke check             +-+
            | boot + init + a few ticks |   ee_smoke.sh (~25 s)
            +---------------------------+
```

Every level catches what the ones below it cannot; the cost per run grows upward,
so run the bottom one on every edit. ([testing/runner-anatomy.md](../testing/runner-anatomy.md))

## 5. Where mission state should live

```
   engine object          script-side mirror table
  +----------------+      +--------------------------+
  | hull, position |      | x, y, call sign          |
  | custom fields  |----->| cargo, death time        |
  | closures       | dies | respawns_left, timers    |
  +----------------+  ===>+--------------------------+
        |                    survives the hull
        v
   destroyed  ----------> fields and closures GONE
```

Any decision a hook makes after the death must therefore be readable from the
mirror, not from the object. `[obs]`
