# API quirk index

One line per question we have actually had to answer. Tags as in
[README.md](README.md); links go to the full write-up.

## Existence checks (things people try to call)

| Call | 2024.12.08 |
|---|---|
| `Player.get()` | **absent** `[obs]` |
| `setBeamDamage()` | **absent** - use `setBeamWeapon(i, arc, dir, range, cycle, damage)` `[obs]` |
| `obj:getName()` | **absent on SpaceObject** - `getTypeName()` / `getCallSign()` `[ref]` |
| `takeHullDamage()` | engine-side only, **not callable from scripts** `[obs]` |
| `getPreviousScriptError()` | **absent** `[obs]` |
| `getAllObjects()` | present, expensive `[ref]` |
| `getActivePlayerShips()` | present, destroyed ships leave no gaps `[ref]` |
| `getScenarioSetting(k)` | present; `getScenarioVariation()` is the deprecated alias `[ref]` |
| `setShortRangeRadarRange()` | present on stations (`pcall` it; 0 = dark, 5000 = default) `[obs]` |
| `victory(faction)` | present `[ref]` |

## Behaviour surprises

| Symptom | Real cause | Detail |
|---|---|---|
| Hook never ran after "killing" a ship | `destroy()` is hook-less; `onDestruction` is damage-only | [pitfalls #1](runtime-pitfalls.md) |
| Player's dialog click did nothing | the callback re-ran its page function, wiping its own result text | [pitfalls #2](runtime-pitfalls.md) |
| A notification never arrived | `sendCommsMessage` returns false while a dialog is open | [pitfalls #3](runtime-pitfalls.md) |
| Wormhole is one-way | the two mouths are not collinear with the traveller | [pitfalls #5](runtime-pitfalls.md) |
| Object ping-pongs at a wormhole | destination shares coordinates with the source | [pitfalls #5](runtime-pitfalls.md) |
| A friendly station shows up although "hidden" | same-faction contacts ignore radar shadowing | [sensors](sensors-and-visibility.md) |
| Container label never changes | artifacts have no scan-state machine | [pitfalls #7](runtime-pitfalls.md) |
| Crate impossible to pick up | it was ejected inside the station hull | [geometry](geometry-and-units.md) |
| Player ship stuck with no FTL | stock templates have no warp drive | [pitfalls #11](runtime-pitfalls.md) |
| Timer never fired | the world was paused, or `delta` was 0 that tick | [pitfalls #9](runtime-pitfalls.md) |
| Whole tick aborted, "index a nil value" | read a field of an object destroyed earlier that tick | [pitfalls #10](runtime-pitfalls.md) |
| Scenario listed under "Unknown" | header has no `Type:` line | [HEADER-FORMAT](../authoring/HEADER-FORMAT.md) |
| Syntax error not reported by the smoke test | the engine logs the loader's error on a separate pattern | [testing/runner-anatomy.md](../testing/runner-anatomy.md) |

## Where to look for an answer

1. `find vendor -name script_reference.html` → the vendored, version-correct
   reference. Search it before trusting memory or another project's scenario.
2. The release's own `scripts/scenario_*.lua` (~40 official examples, including
   the website tutorial as `scenario_05_beacon.lua` and a settings example as
   `scenario_99_battlefield.lua`) - the only *runnable* API examples there are.
3. `scripts/model_data.lua` / `scripts/shipTemplates.lua` in the same directory:
   model radii, hull sizes, template names, default equipment.
4. Engine source (`daid/EmptyEpsilon`, `src/**`) when behaviour and docs
   disagree. Most of the `[src]` tags in this package came from
   `ShipAI.cpp`, `SpaceObject.cpp`, `ScriptInterface.cpp`, `Science.cpp`.
