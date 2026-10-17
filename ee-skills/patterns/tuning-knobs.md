# Tuning knobs

**Problem.** A scenario that plays wrong is usually a scenario with the right
logic and the wrong numbers. Numbers scattered through logic cannot be re-tuned
under time pressure, and a "quick" change deep in a loop is how you break an
untested invariant.

## The block

One block at the top of the file, every number in it justified in a comment,
grouped by concept, named in game units via `U()`:

```lua
-- ========================= scale & knobs =========================
-- 1 displayed unit == 1000 script units. Sector grid is the engine native one:
-- letters are rows (A at the top), numbers are columns (1 at the left).
function U(u) return u * 1000 end

SC = {
    find_u      = 6,    -- a hidden station stops hiding here. The crew's short-
                        -- range radar is 5u and nebulae only blind the LONG-range
                        -- layer, so ~6u is where it shows up anyway. (Was 40u,
                        -- which flagged stations as found while they were still
                        -- supposed to be lost.)
    handover_u  = 1,    -- minimum reach for a hand-over; grows with hull radius.
                        -- Docking always counts, whatever this says.
    reveal_u    = 5,    -- container labels resolve here
    grace_s     = 10,   -- drop-watch grace: let the real hook win first
    respawn_s   = 30,   -- guard slot respawn delay
    respawns_max = 2,   -- per slot, so the mission cannot be farmed
    hint_after_s = 240, -- idle hint line after this long stuck in a phase
    patrol_n    = 2,    -- guards per defended site
}
```

**Conventions that pay for themselves**

* Distances in `*_u`, times in `*_s`, counts in `*_n`, fractions in `*_frac`.
* Table form (`SC.find_u`) beats a hundred globals: it prints, it diffs, and a
  status page can dump it in one line.
* Keep history *in* the comment. "Was 40u, which flagged stations as found" is the
  reason nobody changes it back.
* Anything a GM might want to change mid-session is a knob. Anything that would
  break an invariant if changed is **not** (hull radii live in a data table, not
  here - see [reference/geometry-and-units.md](../reference/geometry-and-units.md)).

## Ambient density knobs

A generator block wants ratios plus caps, because the right count depends on the
area you are covering:

```lua
AMBIENT = {
    nebula_frac = 0.10,   -- fraction of the playable box under nebula clouds
    nebula_max  = 260,    -- hard cap: load time is ~8 ms per cloud (measured)
    belts       = 6,
    belt_dust   = 4,      -- VisualAsteroid gravel per node (decoration, free)
    belt_rocks  = 2,      -- real Asteroids per node (collidable, costs)
    traders     = 6,
}
```

`nebula_max` exists because a percentage of a bigger map silently doubles the
load time. Log the resulting census from `init()` - the line
`ambient seeded nebulae=120 ... total=1637` is what the smoke test reads as the
world's health check, and what you diff when a rebalance changes the map. `[obs]`

## Difficulty as a knob, not an if-chain

```lua
DIFFICULTY = getScenarioSetting("Difficulty")
if DIFFICULTY == nil or DIFFICULTY == "" then DIFFICULTY = "Normal" end  -- headless
STORY_MODE = DIFFICULTY == "Story"
```

then scale from the mode in one place (`enemy_multiplier`, `respawns_max`), never
`if STORY_MODE` inside gameplay logic. The `""` guard is not paranoia: a headless
boot applies only the header's `|Default` value (and `""` for an unmarked
setting); every *other* value arrives only from the GUI or from an injected
`EE_SETTINGS` override - so every setting read must have a default or the test
run silently exercises a third difficulty level. `[src]` `[obs]`

## How to test the knobs

A knob is a bug if changing it silently invalidates an assertion. Two cheap
guards in the driver:

```lua
ee_check(handover_u(stations.depot) >= station_hull_u(stations.depot),
    "hand-over bubble is at least as big as the hull")     -- invariant, not value
ee_until("beat completes inside its knob window", SC.respawn_s + 20, ...)
```

Invariants between knobs catch the change that breaks the mission; tying a poll
deadline to the knob means a retune updates the test for free.
