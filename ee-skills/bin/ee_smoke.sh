#!/usr/bin/env bash
# ee_smoke.sh - the 20-second check: boot a scenario headless PAUSED, let
# init() and a few update() ticks run, then grep the log for script errors.
# Catches: syntax errors, nil API calls, bad scenario headers. It does NOT
# drive the mission - that is ee_func.sh.
#
# Usage: ee_smoke.sh path/to/scenario_NN_name.lua [extra EE args...]
#   SMOKE_TIMEOUT=30   max seconds to wait for the scenario to load
#   SMOKE_SETTLE=4     extra run-time after load (so update() errors surface)
#   SMOKE_PORT=35777   preferred (ignored by EE) game port
#   EE_TAG / EE_VENDOR / EE_SCENARIO_DIR   see ee_env.sh
# Exit: 0 clean | 1 script errors | 2 setup problem | 4 game port 35666 busy
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/ee_env.sh"

SCEN="${1:?usage: ee_smoke.sh <scenario.lua> [extra EE args...]}"
ee_guard_port
shift || true
[[ -f "$SCEN" ]] || { echo "not a file: $SCEN" >&2; exit 2; }
BASE="$(basename "$SCEN")"
[[ "$BASE" == scenario_*.lua ]] || echo "WARNING: $BASE does not match scenario_*.lua; the game would never list it!" >&2
ee_locate || exit 2

EEHOME="$(mktemp -d)"; trap 'rm -rf "$EEHOME"' EXIT
mkdir -p "$EEHOME/.emptyepsilon/scripts" "$EEHOME/run/logs"
# sibling scenarios (they also land in the fallback content path), then ours
[[ -d "$EE_SCENARIO_DIR" ]] && cp "$EE_SCENARIO_DIR"/scenario_*.lua "$EEHOME/.emptyepsilon/scripts/" 2>/dev/null || true
cp "$SCEN" "$EEHOME/.emptyepsilon/scripts/"

TIMEOUT="${SMOKE_TIMEOUT:-30}"; SETTLE="${SMOKE_SETTLE:-4}"
echo "==> $EE_BIN headless=$BASE startpaused=1  (load timeout ${TIMEOUT}s)"
for d in resources scripts packs; do [[ -e "$EE_DATA/$d" ]] && ln -sfn "$EE_DATA/$d" "$EEHOME/run/$d"; done
cd "$EEHOME/run"
HOME="$EEHOME" EE_CONF_DIR="$EEHOME/.emptyepsilon" \
LD_LIBRARY_PATH="${EE_LD}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-dummy}" SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-dummy}" \
${EE_NS[@]+"${EE_NS[@]}"} \
"$EE_BIN" headless="$BASE" server_port="${SMOKE_PORT:-35777}" "$@" \
    <<< 'return "smoke-probe: ok"' > "$EEHOME/run/ee.log" 2>&1 &
pid=$!

LOG="$EEHOME/run/ee.log"
loaded=0
for ((t=0; t<TIMEOUT*2; t++)); do
    kill -0 "$pid" 2>/dev/null || break           # exited on its own
    grep -q "Load script: $BASE" "$LOG" && { loaded=1; break; }
    sleep 0.5
done
[[ $loaded -eq 1 ]] && { sleep "$SETTLE"; grep -q "Load script: $BASE" "$LOG" || loaded=2; }
kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null

status=0
[[ $loaded -eq 1 ]] || { echo "ERROR: scenario '$BASE' was never loaded within ${TIMEOUT}s. Last log lines:"; tail -20 "$LOG"; exit 1; }

# The classic fatal + noisy log patterns. "Unknown scenario meta data" /
# "No scenario category" mean a broken or missing header block (notes: the
# header is parsed by src/scenarioInfo.cpp before the Lua runs at all).
if errors="$(grep -inE 'script error|attempt to (call|index|perform)|error loading|Unknown scenario meta data|No scenario category' "$LOG")"; then
    echo "SCRIPT ERRORS found:"; echo "$errors" | head -20
    status=1
fi
warns="$(grep -inE 'warning' "$LOG" | grep -viE 'potentially a risk|invalid server_port' | head -5)" || true
[[ -n "$warns" ]] && echo "Warnings:" && echo "$warns"

[[ $status -eq 0 ]] && echo "OK: scenario '$BASE' booted headless without script errors."
echo "--- log excerpt -----------------------------------------------------------"
grep -inE 'scenario|lua|error|warning' "$LOG" | head -25 || true
exit $status
