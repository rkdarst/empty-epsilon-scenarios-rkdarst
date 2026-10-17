# Empty Epsilon Scenarios — Agent Guide

Do not do any git commits or git add.


This repository develops custom scenarios for [Empty Epsilon](https://github.com/daid/EmptyEpsilon),
an open-source multiplayer spaceship bridge simulator.

Scenario-authoring knowledge and tooling live in the portable package
**[ee-skills/](ee-skills/)** — read its
[AGENTS.md](ee-skills/AGENTS.md) before writing scenario code. This file covers
what is repo-specific.

## Golden rules

1. **A scenario is a single Lua file** named `scenario_<NN>_<name>.lua`.
   The game discovers scenarios with the glob `scenario_*.lua` (see
   `src/scenarioInfo.cpp` upstream). No other registration file is needed.
2. Every scenario needs the parsed `--` comment header (Name / Description /
   Type, optional Author / Setting[...] / options). If it is missing a `Type:`
   the game logs "No scenario category" and files it under *Unknown*.
   Exact grammar: [ee-skills/authoring/HEADER-FORMAT.md](ee-skills/authoring/HEADER-FORMAT.md).
3. Script code lives in two callbacks: `init()` (build the world, run once at
   scenario start) and `update(delta)` (runs every game tick; drive mission
   state and victory conditions here).
4. **Validate with the game itself**, not by eye:
   `./tools/smoke_test.sh scenarios/scenario_NN_name.lua` (boot check, ~25 s) and
   `./tools/func_test.sh scenarios/scenario_NN_name.lua` (full-mission assertion
   driver). Both are thin wrappers around [ee-skills/bin/](ee-skills/bin/) — the
   same tools work from a copy of that package alone
   (`ee-skills/bin/ee_selftest.sh` proves it).
5. The authoritative API reference is `script_reference.html` inside the
   downloaded release in `vendor/` (version-specific!):
   `find vendor -name script_reference.html`. Lookups and grep one-liners:
   [ee-skills/reference/sources.md](ee-skills/reference/sources.md).
6. Before inventing a "the players must not see this yet" / "this must always
   drop" mechanic, read
   [ee-skills/reference/runtime-pitfalls.md](ee-skills/reference/runtime-pitfalls.md):
   same-faction objects are always visible (nebulae only shadow the long-range
   radar), `onDestruction` fires only on damage kills, artifacts never advance
   scan states, and station hull radii set what "alongside" and "ejected clear"
   mean in units. Before adding a Gamemaster console layer, read
   [ee-skills/patterns/gm-console.md](ee-skills/patterns/gm-console.md): one
   `addGMFunction` call is one button, so paging is a script convention, a
   callback whose first upvalue is not the globals table fails at registration,
   and a button label gets about **20 characters** in a fixed-width cell that
   centers the text — longer labels lose the verb at both ends.
7. A scenario with real mechanics gets a design note next to it
   (`scenarios/scenario_NN_<name>.AGENTS-brief.txt`) and a driver in `tests/`.
   Never let a mechanic exist in the Lua with neither.

## Repository layout

| Path | Purpose |
|---|---|
| `scenarios/` | Our scenario files (`scenario_NN_*.lua`) + their authoring briefs (`*.AGENTS-brief.txt`). This is what gets deployed. |
| `tests/` | Test drivers, named `<scenario-name>.autotest.lua`; discovered automatically by `tools/func_test.sh`. |
| `ee-skills/` | The authoring + testing package: reference, patterns, tooling, templates, worked example. |
| `tools/*.sh` | Wrappers into `ee-skills/bin/` (kept for muscle memory), plus the DSL checker (`dsl_check.py`, `dsl_lang.py`) and `get_pyyaml.sh`. |
| `dsl/` | Mission DSL design sources: `dsl/DESIGN.md` (grammar + gap list) and `dsl/samples/*.yaml` (schema v0.1, not executable). |
| `notes/` | Original research / measurement records. Each one points at the ee-skills file that now carries the rule. |
| `vendor/` | Downloaded game + runtime libs (git-ignored, ~300 MB). |
| `ee.sif` | Built Apptainer image (git-ignored); recipe: `ee-skills/bin/ee.def`. |

Test drivers live in `tests/`, not in `tools/`: any `scenario_*.lua` placed in the
scenario directory would be loaded by the game as a real mission.

## Workflow

```sh
./tools/get_ee.sh                       # one-time: fetch release into vendor/
./tools/get_deps.sh                     # one-time on bare servers: SDL2 runtime libs
cp ee-skills/templates/scenario_skeleton.lua scenarios/scenario_90_myscenario.lua
# edit the header, then knobs -> init() -> update() -> dialogs -> probe hooks
./tools/smoke_test.sh scenarios/scenario_90_myscenario.lua
cp ee-skills/templates/autotest_driver.lua tests/scenario_90_myscenario.autotest.lua
./tools/func_test.sh  scenarios/scenario_90_myscenario.lua
./tools/ee_run.sh                       # play it (host $HOME hidden)
```

Useful knobs: `AUTOTEST=none` (boot and idle only), `EE_SETTINGS="Difficulty=Story"`
(inject scenario settings a headless boot cannot receive), `RUNTIME=N`,
`EE_VENDOR=/path/to/vendor`. Details:
[ee-skills/testing/runner-anatomy.md](ee-skills/testing/runner-anatomy.md).

## Rebuilding everything from zero (git clone + nothing else)

Everything outside this file's directory is either downloadable or scratch.
After a fresh clone (or if `vendor/` was deleted):

```sh
./ee-skills/bin/ee_bootstrap.sh   # game + runtime libs + boot check, all of it
# or step by step:
./tools/get_ee.sh                 # EE-2024.12.08 deb (~270 MB) -> vendor/EE-2024.12.08/
./tools/get_deps.sh               # SDL2/ALSA/Pulse -> vendor/libs/ (only if ldd complains)
SMOKE_TIMEOUT=25 ./tools/smoke_test.sh scenarios/scenario_90_template.lua  # must print OK
```

No credentials, no manual state, nothing in `~/.emptyepsilon` required: the
runners build their own throwaway HOME. Deployment for real play: copy scenario
files into `~/.emptyepsilon/scripts/` (a fallback content path the game scans
automatically — the game install is never modified). Inside containers, set
`HOME` or `EE_CONF_DIR` to a writable location.

## Where examples live

The game release in `vendor/` contains the game's own `scripts/` directory with
~40 official example scenarios (`scenario_00_basic.lua`, `scenario_05_beacon.lua`
= the website tutorial, `scenario_99_battlefield.lua` = settings example, ...).
Always prefer copying patterns from a shipped example over inventing API — and
see [ee-skills/examples/demo/](ee-skills/examples/demo/) for a small mission that
follows this repo's conventions, driver included.

## Version pin

We currently vendor **EE-2024.12.08** (latest stable release). Newer PR builds
exist (e.g. `EE-2025.06.12PR`, `EE-2026.09.22PR`) — the API can gain functions and
AI/radar behaviour can change. Check the vendored
`vendor/**/script_reference.html` before using anything you saw only in recent
examples, and re-run `./ee-skills/bin/ee_selftest.sh` after changing the pin.

