# ee-skills — Empty Epsilon scenario authoring & testing

A portable knowledge + tooling package for writing [Empty Epsilon](https://github.com/daid/EmptyEpsilon)
scenarios with an agent in the loop: verified engine facts, a problem-per-recipe
pattern cookbook, a container-free test harness, and a worked example mission.

Verified against **EE-2024.12.08**. Every claim in `reference/` carries a
provenance tag (`[src]` / `[ref]` / `[obs]` / `[infer]`) — see
[reference/README.md](reference/README.md).

## 60-second start

```sh
bin/ee_bootstrap.sh                    # fetch the game + libs, then prove the setup
bin/ee_selftest.sh                     # prove the package works standalone (~3 min)
```

## Working on a scenario

```sh
cp templates/scenario_skeleton.lua scenarios/scenario_90_mine.lua   # edit the header!
bin/ee_smoke.sh  scenarios/scenario_90_mine.lua                     # ~25 s, every edit
bin/ee_func.sh   scenarios/scenario_90_mine.lua                     # full mission + asserts
bin/ee_play.sh                                                # play it (Apptainer)
```

`ee_func.sh` finds its driver at `<root>/tests/<scenario-name>.autotest.lua`, or
take one from `templates/autotest_driver.lua`. The scenario needs no test hooks:
the runner concatenates `scenario + lib/autotest.lua + driver` into one Lua chunk
so the driver sees the scenario's own globals and `probe_*` functions.

## Layout

| Path | What's in it |
|---|---|
| [reference/](reference/) | verified engine behaviour: scripting model, pitfalls, sensors, geometry, AI, quirk index |
| [patterns/](patterns/) | one recipe per recurring problem, each with code + test + pitfalls |
| [authoring/](authoring/) | header grammar, brief→code pipeline, flow diagrams, anti-softlock checklist |
| [testing/](testing/) | runner anatomy, writing drivers, runtime surprises, human acceptance |
| [templates/](templates/) | scenario skeleton, test driver, mission-brief template |
| [bin/](bin/) | bootstrap / get / deps / smoke / func / play / selftest + the container recipe |
| [lib/autotest.lua](lib/autotest.lua) | the generic assertion harness (appended at test time) |
| [examples/demo/](examples/demo/) | a complete mini-mission + its driver; the package's acceptance test |

## Where to start reading

* New to the engine → [reference/api-and-scripting.md](reference/api-and-scripting.md)
  then [reference/runtime-pitfalls.md](reference/runtime-pitfalls.md).
* Writing a mission now → [authoring/workflow.md](authoring/workflow.md), then
  [authoring/from-brief-to-code.md](authoring/from-brief-to-code.md), then copy
  [templates/scenario_skeleton.lua](templates/scenario_skeleton.lua).
* Something behaves wrong → [testing/runtime-surprises.md](testing/runtime-surprises.md),
  then [reference/api-quirk-index.md](reference/api-quirk-index.md).
* Mission can get stuck → [authoring/anti-softlock.md](authoring/anti-softlock.md).
* Writing tests → [testing/README.md](testing/README.md) then
  [testing/writing-drivers.md](testing/writing-drivers.md).

## What is verified right now (EE-2024.12.08)

| Check | Command | Status |
|---|---|---|
| package works from a copy alone | `bin/ee_selftest.sh` | 3/3 steps, 27/27 demo assertions (x2, incl. `EE_SETTINGS` pass) |
| templates work out of the box | skeleton + `templates/autotest_driver.lua` | 7/7, clean `init()` |
| our long mission | `tools/func_test.sh scenarios/scenario_40_lostcluster.lua` | 169 assertions, 0 fail (3 consecutive runs) |
| its DSL twin | same, `scenario_41_lostcluster_dsl.lua` | 17 assertions, 0 fail |
| boot check | `tools/smoke_test.sh scenarios/scenario_90_template.lua` | OK |
| DSL samples | `tools/dsl_check.py dsl/samples/*.yaml` | OK (warnings by design) |

Re-run them after touching `lib/`, `bin/` or the pinned version. Two runs cannot
share a machine at the same moment (headless EE binds port 35666), so the runners
queue on a lock — see
[testing/runner-anatomy.md](testing/runner-anatomy.md#one-run-at-a-time).

## Dropping this into an existing scenario repo

Copy the directory in, then from the repo root:

```sh
EE_ROOT=$PWD bin/ee_smoke.sh scenarios/scenario_<your one>.lua
EE_ROOT=$PWD bin/ee_func.sh  scenarios/scenario_<your one>.lua AUTOTEST=none
```

Vendor discovery looks in `$EE_VENDOR`, `<repo>/vendor`, `<pkg>/vendor` and
`~/.cache/ee-skills/vendor`, so a shared download directory works out of the box.

## Not included

* The game itself (`bin/ee_get.sh` downloads it; ~270 MB into `vendor/`).
* Apptainer (only `bin/ee_play.sh` needs it; never installed by this package).
* Any scenario-specific content — mission text, balance numbers and design docs
  belong to the project that uses the package.
