# Patterns — one recipe per recurring problem

Each file is a self-contained recipe: **the problem → the verified facts it comes
from → the code → how to test it → variants and pitfalls.** Code is complete
enough to paste into a scenario; naming follows the demo scenario
(`stations.*`, `parts.*`, `probe_*`) so you can cross-read it against
[examples/demo/scenario_95_demo.lua](../examples/demo/scenario_95_demo.lua).

| Recipe | Solves | Verified against |
|---|---|---|
| [phase-state-machine.md](phase-state-machine.md) | "when does the mission advance, and can it get stuck?" | 2024.12.08 `[src]` `[obs]` |
| [dialog-page.md](dialog-page.md) | dialogs whose clicks actually do something | `[src]` `[obs]` |
| [station-handover.md](station-handover.md) | giving/taking cargo at a station without lying about distance | `[src]` `[obs]` |
| [container-drop.md](container-drop.md) | cargo crates with two-state labels | `[src]` `[obs]` |
| [guanteed-drop.md](guanteed-drop.md) | "the crate must exist" even for hook-less deaths | `[src]` `[obs]` |
| [hidden-station.md](hidden-station.md) | hiding (and revealing) a station | `[src]` `[obs]` |
| [radar-dark-tug.md](radar-dark-tug.md) | a needle-in-a-haystack search object | `[src]` `[obs]` |
| [guard-respawn.md](guard-respawn.md) | station defences that respawn without duplicating | `[obs]` |
| [gm-console.md](gm-console.md) | paged GM controls a human at the table can use (labels: 20 chars, centered) | `[src]` `[obs]` |
| [notify-queue.md](notify-queue.md) | news that must reach the crew | `[ref]` `[obs]` |
| [status-page.md](status-page.md) | the "where do I go now" dialog | `[obs]` |
| [tuning-knobs.md](tuning-knobs.md) | a knob block you can actually re-tune | `[obs]` |
| [world-seeding.md](world-seeding.md) | ambient density, belts, wormholes, load time | `[src]` `[obs]` |

Cross-cutting rules that show up in almost every recipe:

* **Poll, don't sample.** Organic events (AI kills, warp transits, respawns)
  happen on their own schedule; every expectation is a poll with a deadline, and
  every mission-critical effect has a polled fallback.
  ([testing/writing-drivers.md](../testing/writing-drivers.md))
* **Geometry, not flags.** A gate that says "deliver at the station" must be
  implemented as a distance/docking test, and the number must come from the hull
  radius. ([reference/geometry-and-units.md](../reference/geometry-and-units.md))
* **A hook is a fast path.** `onDestruction` is damage-only, so treat hooks as
  optimisations of a polled watcher. ([reference/runtime-pitfalls.md](../reference/runtime-pitfalls.md))
* **Everything that can die is re-found from a script-side table**, because
  closures and custom fields die with the object.
* **One rendered message per action.** Assert it in every dialog test.
