# Empty Epsilon scenario dev environment

Write and test [Empty Epsilon](https://github.com/dalerank/emptyepsilon)
scenarios with **no build, no GUI, no root** — official Linux binary +
headless CLI boot + a smoke test.

Everything here is plain files: the repo tracks only docs, scripts and Lua
scenarios (~64 KB). The game itself (~580 MB) is downloaded by `tools/` on
demand into the git-ignored `vendor/` directory.

## Quickstart

Requirements: a plain x86_64 Linux box (dev host: Ubuntu 24.04) with
`curl`, `dpkg-deb`, `timeout`. Needs an internet connection once, to
download the game + runtime libs.

```sh
git clone <this repo> && cd empty-epsilon-scenarios-rkdarst
./tools/get_ee.sh       # downloads Empty Epsilon EE-2024.12.08 (~270 MB)
./tools/get_deps.sh     # vendored SDL2/Pulse libs, needed only if the next
                        # step reports "libSDL2-2.0.so.0: not found"
                        # (or simply: sudo apt install libsdl2-2.0-0)
./tools/smoke_test.sh scenarios/scenario_90_template.lua
# -> "OK: scenario 'scenario_90_template.lua' booted headless without script errors."
```

This exact procedure is verified to rebuild the environment from a bare
checkout (see notes/02 "Recovery from zero").

## How to work

```sh
cp templates/scenario_template.lua scenarios/scenario_90_myscenario.lua
# edit it ...
./tools/smoke_test.sh scenarios/scenario_90_myscenario.lua   # quick test loop
```

## Where to read

| File | Content |
|---|---|
| `AGENTS.md` | condensed cheatsheet + conventions |
| `notes/01-scenario-anatomy.md` | scenario structure, functions, ship types, scripting API, pitfalls |
| `notes/02-build-and-test.md` | headless testing, timing model, recovery-from-zero, limitations |
| `notes/03-docs-and-links.md` | upstream docs and link index |

## Layout

```
AGENTS.md, README.md
notes/                     the main documentation
scenarios/                 your scenarios (scenario_NN_name.lua)
templates/scenario_template.lua
tools/
  get_ee.sh                download+unpack official release -> vendor/EE-<tag>/
  get_deps.sh              download runtime .so deps -> vendor/libs/ (bare hosts)
  smoke_test.sh            headless boot + log assertion (exit 0/1)
  func_test.sh             headless functional run + assertion driver (exit 0/1)
  autotest/                self-driving test timelines, appended by func_test.sh
  ee.def                   optional Apptainer recipe (alternative to vendoring)
vendor/                    git-ignored, fully regrowable by the tools/ scripts
```
