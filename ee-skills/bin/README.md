# bin/ — the tooling

Seven scripts, one shared library. Everything is POSIX-ish bash with no build
step; every path is discovered at runtime, so the package works from any
directory, from any repo, and from a copy on its own.

| Script | What it does |
|---|---|
| `ee_env.sh` | **sourced, not run**: vendor/tag/binaries discovery, `EE_CONF_DIR`, and the port-35666 guard (runs the game in a private netns when the port is busy) |
| `ee_get.sh` | download + unpack an official release into `<vendor>/EE-<tag>/` (~270 MB deb, no root) |
| `ee_deps.sh` | one-time on bare hosts: extract the SDL2/ALSA/Pulse runtime libs into `<vendor>/libs/` |
| `ee_smoke.sh <file.lua>` | boot check: throwaway config dir, `headless=<file> startpaused=1`, grep the log for script errors (~25 s) |
| `ee_func.sh <file.lua>` | full-mission run: concatenates `lib/autotest.lua` + a driver after the scenario, lets it play, greps assertion markers (1-4 min) |
| `ee_play.sh` | graphical play via Apptainer (`--contain --no-home`; builds `ee.sif` on first use) |
| `ee_bootstrap.sh` | get + deps + boot check, with clear skips when already present |
| `ee_selftest.sh` | proves the package is self-sufficient: copies itself to a temp dir, then runs boot / driver / story-mode passes |

## Environment knobs

| Var | Default | Meaning |
|---|---|---|
| `EE_VENDOR` | discovered | where `EE-*/` lives: `$EE_VENDOR`, `<repo>/vendor`, `<pkg>/vendor`, `~/.cache/ee-skills/vendor` |
| `EE_TAG` | `EE-2024.12.08` | release to use; `ee_get.sh` accepts the same value as `$1` |
| `EE_SCENARIO_DIR` | `<cwd>/scenarios` | scenario dir exposed to the game (`ee_smoke`/`ee_func` copy the tested file here) |
| `EE_ROOT` | package parent | project root, used for driver discovery (`$EE_ROOT/tests/<name>.autotest.lua`) |
| `EE_CONF_DIR` | throwaway `mktemp -d` | the game's HOME; set it only if you want persistent state |
| `EE_SETTINGS` | unset | `K=V;K2=V2` injected as `getScenarioSetting` overrides |
| `AUTOTEST` | discovered | driver path; `none` = boot and idle only |
| `RUNTIME` | driver's `-- ee_runtime: N`, else 60 | wall-clock seconds a func run may take; an explicit value wins |
| `SMOKE_TIMEOUT` / `SMOKE_SETTLE` / `GAP` | tuned defaults | timing |

## Exit codes

`0` OK · `1` script errors / failed assertions · `2` usage or missing file ·
`3` game missing (run `ee_get.sh`) · `4` port 35666 busy and no netns fallback.

## Notes

* The runners never write into your repo: scenarios are copied into a throwaway
  config dir, and the concatenated test file lives there too.
* A run keeps its log at `<EE_CONF_DIR>/logs/ee.log`; `ee_func.sh` prints the
  relevant excerpt on failure and a one-line `RESULT:` always.
* `ee_play.sh` is the only script that needs Apptainer, and the only place
  `ee.def` is used; nothing here installs anything.
