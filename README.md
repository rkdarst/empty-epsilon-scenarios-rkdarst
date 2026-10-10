# Empty Epsilon scenario dev environment

Write and test [Empty Epsilon](https://github.com/daid/EmptyEpsilon)
scenarios with **no build, no GUI, no root** — official Linux binary +
headless CLI boot + a smoke test + a full-mission assertion harness.

Everything here is plain files: the repo tracks only docs, scripts and Lua
scenarios. The game itself (~580 MB) is downloaded on demand into the
git-ignored `vendor/` directory. Scenario knowledge and tooling live in the
portable [ee-skills/](ee-skills/) package, which also works standalone.

## Quickstart

Requirements: a plain x86_64 Linux box (dev host: Ubuntu 24.04) with
`curl`, `dpkg-deb`, `timeout`. Needs an internet connection once, to
download the game + runtime libs.

```sh
git clone <this repo> && cd empty-epsilon-scenarios-rkdarst
./ee-skills/bin/ee_bootstrap.sh   # game + libs + boot check, all of it
# or step by step:
./tools/get_ee.sh       # downloads Empty Epsilon EE-2024.12.08 (~270 MB)
./tools/get_deps.sh     # vendored SDL2/Pulse libs, needed only if the next
                        # step reports "libSDL2-2.0.so.0: not found"
                        # (or simply: sudo apt install libsdl2-2.0-0)
./tools/smoke_test.sh scenarios/scenario_90_template.lua
# -> "OK: scenario 'scenario_90_template.lua' booted headless without script errors."
```

## How to work

```sh
cp ee-skills/templates/scenario_skeleton.lua scenarios/scenario_90_myscenario.lua
# edit the header, then knobs -> init() -> update() -> dialogs -> probe hooks
./tools/smoke_test.sh scenarios/scenario_90_myscenario.lua     # quick test loop
cp ee-skills/templates/autotest_driver.lua tests/scenario_90_myscenario.autotest.lua
./tools/func_test.sh  scenarios/scenario_90_myscenario.lua     # whole mission, asserted
```

## Where to read

| File | Content |
|---|---|
| `AGENTS.md` | repo conventions + the golden rules |
| `ee-skills/README.md` | the authoring + testing package: reference, patterns, tooling |
| `ee-skills/reference/runtime-pitfalls.md` | the engine traps that break missions |
| `ee-skills/patterns/` | one recipe per recurring mechanic |
| `ee-skills/examples/demo/` | a complete mission + driver, in our conventions |
| `notes/` | original research and measurement records |
| `dsl/DESIGN.md` | the mission DSL grammar and gap list |

## Layout

```
AGENTS.md, README.md
ee-skills/                 the authoring + testing package (portable)
  bin/                       ee_get/deps/smoke/func/play/selftest/bootstrap
  reference/ patterns/       verified engine facts, recipes
  templates/ examples/       skeleton, driver, worked example
  testing/ authoring/        how to test, how to design
scenarios/                 your scenarios + *.AGENTS-brief.txt design notes
tests/                     <scenario>.autotest.lua assertion drivers
tools/                     wrappers into ee-skills/bin + the DSL checker
dsl/                       DESIGN.md (grammar) + samples/*.yaml
notes/                     research notes (measurement records)
vendor/                    git-ignored, fully regrowable by the tools
```

## Graphical play via Apptainer (optional)

On a machine that has `apptainer` (this repo never installs it):

```sh
./tools/get_ee.sh && ./tools/ee_run.sh --build   # builds vendor/ee.sif (or
                                                 # ee-rootfs if kernel lacks squashfs)
./tools/ee_run.sh                              # play! window on $DISPLAY
```

The runner always uses `--contain --no-home`, so the game cannot see your
home directory: only `scenarios/` (read-only), `vendor/ee-state/` for
settings, and the X11/DRI/snd devices are exposed. Details:
[ee-skills/testing/runner-anatomy.md](ee-skills/testing/runner-anatomy.md).

