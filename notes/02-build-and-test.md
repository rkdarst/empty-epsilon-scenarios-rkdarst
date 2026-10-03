# 02 — Build & test (official release route)

Decision (2026-10): we use the **official release** (no source build), run
natively or wrapped in Apptainer. `tools/get_ee.sh` fetches it into `vendor/`.

## Getting the game

```sh
./tools/get_ee.sh                 # latest stable (EE-2024.12.08)
./tools/get_ee.sh EE-2025.06.12PR # a PR/pre-release build instead
./tools/get_deps.sh               # one-time on bare hosts: SDL2 runtime libs
```

It downloads `Linux_EmptyEpsilon_<tag>.deb` from GitHub releases (~270 MB) and
unpacks it with `dpkg-deb -x` into `vendor/EE-<tag>/` — no root needed.
Layout of the deb (verified for EE-2024.12.08): binary at
`usr/local/bin/EmptyEpsilon`, data (`scripts/`, `resources/`, `packs/`) at
`usr/local/share/emptyepsilon/`, and `script_reference.html` at
`usr/local/share/doc/EmptyEpsilon/`. `smoke_test.sh` finds all of this
automatically.

Two runtime gotchas (both verified on this Ubuntu 24.04 box):

- **The game resolves `resources/`, `scripts/`, `packs/` relative to the
  current working directory** — run it from the data dir, or symlink those
  three dirs into your run dir (`smoke_test.sh` does the symlink into a
  sandbox so we never pollute the vendor tree or each other).
- **The binary needs libSDL2 + its ALSA/Pulse chain.** On a bare server those
  are absent; `tools/get_deps.sh` extracts the needed Ubuntu deb payloads into
  `vendor/libs/` and `smoke_test.sh` adds them via `LD_LIBRARY_PATH` plus
  `SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy`. (In the Apptainer image this
  is unnecessary — apt installs them properly.)

## How the game starts a scenario (verified in `src/main.cpp`, `src/init/config.cpp`)

- Any command-line argument of the form `key=value` overrides an
  `options.ini` preference for that run (args without `=` are ignored).
  Config file: `$EE_CONF_DIR/options.ini`, else `$HOME/.emptyepsilon/options.ini`.
- `headless=scenario_xx.lua` → no windows are created; the game starts the
  scenario immediately, opens the server port, and **creates a `StdinLuaConsole`**
  (an `EE>` prompt: every line you write to stdin is executed as Lua in the
  running scenario). The GM screen is unavailable in this mode.
- `httpserver=8080` starts the HTTP script server **independent of headless
  mode** (it is initialized before the headless/window branch). Endpoints
  (wiki "HTTP Server" + `src/httpScriptAccess.cpp`):
  - `GET /get.lua?key=expr&key2=expr2` — evaluate expressions, JSON result;
    `_OBJECT_=getter()` selects the object (default `getPlayerShip(-1)`).
  - `GET /set.lua?setShieldsActive(true)&commandImpulse(0.75)` — call functions.
  - `POST /exec.lua` (≤2 KB body) — run arbitrary Lua; `return` values come
    back in the body. Broken Lua returns `{"ERROR": "Script error: ..."}`;
    worse failures can crash the server.
- Useful preferences for testing:

| Key | Effect |
|---|---|
| `headless=<file.lua>` | boot straight into a scenario, stdin console |
| `startpaused=1` | start paused (then `setGameSpeed`/unpause via console) |
| `server_port=35666` | game port (default 35666, TCP) |
| `scenario_settings=Key=Value;K2=V2` | scenario setting values |
| `httpserver=8080` | enable HTTP Lua API (unsafe on public nets!) |
| `headless_name/_password/_internet` | server listing options |
| `game_logs=1` | game-state JSON logs — only works in releases ≤ 2024.12.08 and needs a `logs/` subdir in the CWD |

## Validation ladder (cheap → expensive)

1. **Syntax**: `luac -p scenarios/scenario_NN_x.lua` if a lua interpreter
   exists (none installed on this box yet; `apt install lua5.4` or use the
   vendored binary anyway). Catches typos only — `scenario_*.lua` files are
   plain Lua, header comments are comments.
2. **Headless boot** (the real check):
   `emptyepsilon headless=scenario_NN_x.lua startpaused=1 server_port=35777`
   — Lua load/run errors and `LOG(WARNING)` header problems appear on stdout.
   `tools/smoke_test.sh` wraps this: throwaway `EE_CONF_DIR`, scenarios copied
   to a temp `~/.emptyepsilon/scripts`, probes piped to the `EE>` console,
   log grepped for `error|exception|attempt to`.
3. **HTTP inspection** (same run, add `httpserver=8093`) — verified live:
   ```sh
   curl -s --data 'return getPlayerShip(-1):getCallSign()' http://localhost:8093/exec.lua
   # -> "Epsilon"
   curl -s 'http://localhost:8093/get.lua?hull=getHull()&callsign=getCallSign()'
   # -> {"callsign": "Epsilon", "hull": 250.000}
   ```
   In `get.lua`/`set.lua` write documented function names as calls
   (`getHull()`, not `hull()` — they are invoked on `_OBJECT_`).
4. **In-game review** — copy the file to `~/.emptyepsilon/scripts/`, start a
   normal game, pick it under its `Type:` category, play/GM it.

## Apptainer

`tools/ee.def` wraps the vendored release in an Ubuntu base with SDL2 libs.

```sh
apptainer build vendor/ee.sif tools/ee.def
apptainer run --bind scenarios:/data/eehome/.emptyepsilon/scripts vendor/ee.sif \
    headless=scenario_90_myscenario.lua startpaused=1
```

Notes: set a writable `HOME`/`EE_CONF_DIR` inside the container (e.g.
`APPTAINERENV_HOME=/tmp/eehome`); bind-mount your `scenarios/` dir onto
`$HOME/.emptyepsilon/scripts` so fallback-path discovery works without
touching the image. Apptainer is not installed on this dev box — build the
`.sif` where it is available.

## Recovery from zero (verified 2026-10-02 by wiping vendor/)

State inventory — nothing outside this repo matters except caches:

| What | Where | Regrown by |
|---|---|---|
| Game release (deb + unpacked) | `vendor/` (git-ignored) | `./tools/get_ee.sh [TAG]` — pinned default `EE-2024.12.08` |
| SDL2/ALSA/Pulse runtime libs | `vendor/libs/` | `./tools/get_deps.sh` (Ubuntu noble x86_64; index cached in `$TMPDIR/noble_Packages`, refetched if absent) |
| Test run dirs / throwaway HOMEs | `/tmp/ee*`, `mktemp -d` | none needed — `smoke_test.sh` creates its own |
| `~/.emptyepsilon` | user home | never required by our tooling; only for real play |

Rebuild + prove recipe (exactly what was validated):

```sh
rm -rf vendor
./tools/get_ee.sh
./tools/get_deps.sh        # ends with "OK: ... resolves all shared libraries"
SMOKE_TIMEOUT=25 ./tools/smoke_test.sh scenarios/scenario_90_template.lua   # must print OK
```

Caveats when rebuilding elsewhere:
- `get_deps.sh` assumes Ubuntu 24.04 x86_64 + reachable archive.ubuntu.com.
  On a distro with SDL2 packaged, just `apt install libsdl2-2.0-0` (or the
  Apptainer image) instead.
- `smoke_test.sh` auto-picks the newest `vendor/EE-*/`; pin with `SMOKE_EE_TAG`.
- Script APIs can differ between releases: always re-check
  `vendor/EE-*/usr/local/share/doc/EmptyEpsilon/script_reference.html`
  of the version you actually vendored.

## Known limitations / gotchas

- Releases after 2024.12.08 do **not** write game-state logs (wiki note); the
  vendored 2024.12.08 deb does (`Opened game state log: logs/game_log_*.txt`).
  Prefer console/exec.lua probes for assertions in newer builds.
- `startpaused=1` freezes game time but `update(delta)` **is still called**
  (with `delta=0`) — observed: per-tick Lua errors repeat while paused.
- Headless has no GM screen and no GUI; use the stdin console or HTTP API.
- The scenario list is cached at startup — restart after edits (no hot reload).
- Client/server must run the same game version.
- `httpserver` executes arbitrary Lua with no auth — local test ports only.
