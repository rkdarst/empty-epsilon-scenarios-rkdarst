# Empty Epsilon Scenarios — Agent Guide

Do not do any git commits or git add.


This repository develops custom scenarios for [Empty Epsilon](https://github.com/daid/EmptyEpsilon),
an open-source multiplayer spaceship bridge simulator.

## Golden rules

1. **A scenario is a single Lua file** named `scenario_<NN>_<name>.lua`.
   The game discovers scenarios with the glob `scenario_*.lua` (see
   `src/scenarioInfo.cpp` upstream). No other registration file is needed.
2. Every scenario needs the parsed `--` comment header (Name / Description /
   Type, optional Author / Setting[...] / options). If it is missing a `Type:`
   the game logs "No scenario category" and files it under *Unknown*.
   Exact grammar: [notes/01-scenario-anatomy.md](notes/01-scenario-anatomy.md).
3. Script code lives in two callbacks: `init()` (build the world, run once at
   scenario start) and `update(delta)` (runs every game tick; drive mission
   state and victory conditions here).
4. **Validate with the game itself**, not by eye. The real syntax/runtime
   check is booting the scenario headless:
   `EmptyEpsilon headless=scenario_NN_name.lua` (see
   [notes/02-build-and-test.md](notes/02-build-and-test.md)).
   `./tools/smoke_test.sh scenarios/scenario_NN_name.lua` automates this.
5. The authoritative API reference is `script_reference.html` inside the
   downloaded release in `vendor/` (version-specific!). Online copy of the
   current build: <http://daid.eu/dump/script_reference.html>.

## Repository layout

| Path | Purpose |
|---|---|
| `scenarios/` | Our scenario files (`scenario_NN_*.lua`). This is what gets deployed. |
| `templates/scenario_template.lua` | Skeleton with a valid parsed header — copy to start a new scenario. |
| `tools/get_ee.sh` | Downloads + unpacks an official Empty Epsilon release into `vendor/`. |
| `tools/get_deps.sh` | One-time on bare servers: extracts the SDL2 runtime libs the game binary needs into `vendor/libs/` (no root). |
| `tools/smoke_test.sh` | Boots a scenario headless in a throwaway config dir and greps the log for script errors (boot/syntax check). |
| `tools/func_test.sh` | Boots a scenario headless *unpaused* and lets it run; if `tools/autotest/lc_autotest.lua` exists it is appended to a copy of the scenario as a timed assertion driver that walks the whole mission (exit 0 = all assertions passed). |
| `tools/ee.def` | Apptainer recipe: Docker-Hub `debian:stable` base that **installs** the official EE deb (self-contained SDL2/GL stack). Build from the repo root. |
| `tools/ee_run.sh` | Play/run the image graphically with the host `$HOME` hidden (`--contain --no-home`; only scenarios, `vendor/ee-state` and X11/DRI are exposed). |
| `dsl/` | Mission DSL design sources — `dsl/samples/*.yaml` (schema v0.1, not executable; grammar in notes/05 + `tools/dsl_lang.py`). |
| `tools/dsl_check.py` | Schema/cross-reference checker for DSL files (no codegen yet; needs PyYAML — `tools/get_pyyaml.sh` fetches it rootless into `vendor/pylibs`). |
| `vendor/` | Downloaded game (git-ignored, ~300 MB). |
| `notes/` | Deeper research notes; read before writing scenario code. |

## Workflow

```sh
./tools/get_ee.sh                       # one-time: fetch release into vendor/
./tools/get_deps.sh                     # one-time on bare servers: SDL2 runtime libs
cp templates/scenario_template.lua scenarios/scenario_90_myscenario.lua
# edit ...
./tools/smoke_test.sh scenarios/scenario_90_myscenario.lua
```

## Rebuilding everything from zero (git clone + nothing else)

Everything outside this file's directory is either downloadable or scratch.
After a fresh clone (or if `vendor/` was deleted):

```sh
./tools/get_ee.sh      # downloads EE-2024.12.08 deb (~270 MB) -> vendor/EE-2024.12.08/
./tools/get_deps.sh    # SDL2/ALSA/Pulse debs -> vendor/libs/ (only needed if the
                       #   binary's ldd shows "not found" on this host)
SMOKE_TIMEOUT=25 ./tools/smoke_test.sh scenarios/scenario_90_template.lua  # must print OK
```

Verified by wiping `vendor/` and re-running exactly these steps (see
notes/02 "Recovery from zero"). No credentials, no manual state, nothing in
`~/.emptyepsilon` required: the smoke test builds its own throwaway HOME.

Deployment for real play: copy scenario files into `~/.emptyepsilon/scripts/`
(a fallback content path the game scans automatically — the game install is
never modified). Inside containers, set `HOME` or `EE_CONF_DIR` to a writable
location.

## Where examples live

The game release in `vendor/` contains the game's own `scripts/` directory with
~40 official example scenarios (`scenario_00_basic.lua`, `scenario_05_beacon.lua`
= the website tutorial, `scenario_99_battlefield.lua` = settings example, ...).
Always prefer copying patterns from a shipped example over inventing API.

## Version pin

We currently vendor **EE-2024.12.08** (latest stable release). Newer PR builds
exist (e.g. `EE-2025.06.12PR`, `EE-2026.09.22PR`) — the API can gain functions;
check `vendor/**/script_reference.html` of the vendored version before using
anything you saw only in recent examples.
