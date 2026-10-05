#!/usr/bin/env bash
# Smoke-test a scenario: boot the vendored Empty Epsilon headless with the
# scenario, let init() run for a few ticks, then kill it and scan the log for
# script errors. (Note: the headless server ignores stdin; probe it via
# tools/func_test.sh + tools/autotest drivers instead.)
#
# Usage: tools/smoke_test.sh scenarios/scenario_NN_name.lua [extra EE args...]
#   SMOKE_TIMEOUT=25   seconds to keep the game running (default 20)
#   SMOKE_EE_TAG=EE-... pin the vendored release (default: newest in vendor/)
#
# Exit codes: 0 = no errors found; 1 = script errors in log; 2 = setup problem;
#             4 = the game's listen port 35666 is already in use (another
#                 Empty Epsilon instance is running on this machine).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCEN="${1:?usage: smoke_test.sh <scenario.lua> [extra args...]}"

# EE 2024.12.08 always listens on TCP/UDP 35666 at boot (the server_port
# preference is not applied to the headless listener) and SEGFAULTS when the
# bind fails. If another instance owns the port, run the game inside a private
# network namespace instead; if that is unavailable, fail early with a hint.
EE_NS=()
if command -v python3 >/dev/null 2>&1 && ! python3 - <<'PYEOF'
import socket, sys
for t in (socket.SOCK_STREAM, socket.SOCK_DGRAM):
    s = socket.socket(socket.AF_INET, t)
    try:
        s.bind(('', 35666))
    except OSError:
        sys.exit(1)
    finally:
        s.close()
sys.exit(0)
PYEOF
then
    if command -v unshare >/dev/null 2>&1; then
        echo "NOTE: port 35666 busy (another EE instance running?) - using a private netns" >&2
        EE_NS=(unshare -rn sh -c 'ip link set lo up 2>/dev/null || true; exec "$@"' ee-ns)
    else
        echo "ERROR: port 35666 is in use - another Empty Epsilon instance is running on" >&2
        echo "       this machine (the headless game always binds 35666 and crashes if" >&2
        echo "       it can't). Close the other instance (GUI game / container) and retry." >&2
        exit 4
    fi
fi
shift || true
[[ -f "$SCEN" ]] || { echo "not a file: $SCEN" >&2; exit 2; }
BASE="$(basename "$SCEN")"
[[ "$BASE" == scenario_*.lua ]] || echo "WARNING: $BASE does not match scenario_*.lua; the game would not list it!" >&2

# --- locate vendored release -------------------------------------------------
if [[ -n "${SMOKE_EE_TAG:-}" ]]; then
    DEST="$ROOT/vendor/$SMOKE_EE_TAG"
else
    DEST="$(ls -d "$ROOT"/vendor/EE-*/ 2>/dev/null | sort | tail -1)"
fi
[[ -n "${DEST:-}" && -d "$DEST" ]] || { echo "No vendored release found in vendor/ - run tools/get_ee.sh first." >&2; exit 2; }
BIN="$(find "$DEST" -type f \( -name 'emptyepsilon' -o -name 'EmptyEpsilon' \) -perm -u+x | head -1)"
[[ -n "$BIN" ]] || { echo "No EmptyEpsilon binary under $DEST" >&2; exit 2; }
# data dir: contains scripts/ + resources/ (the game resolves these from CWD)
DATA="$(dirname "$(dirname "$(find "$DEST" -path '*/scripts/scenario_00_basic.lua' | head -1)")")"
[[ -n "$DATA" && -d "$DATA" ]] || { echo "Could not locate data dir under $DEST" >&2; exit 2; }

# extra shared libs fetched by tools/get_deps.sh (extracted under vendor/libs)
LD_PATH=""
while IFS= read -r d; do LD_PATH+="${LD_PATH:+:}$d"; done < <(find "$ROOT/vendor/libs" -type d \( -name 'x86_64-linux-gnu' -o -name 'pulseaudio' \) 2>/dev/null | sort)

# --- throwaway HOME / EE_CONF_DIR ----------------------------------------------
EEHOME="$(mktemp -d)"
trap 'rm -rf "$EEHOME"' EXIT
mkdir -p "$EEHOME/.emptyepsilon/scripts" "$EEHOME/run/logs"
# our scenarios win over (and supplement) the vendored ones via the fallback path
cp "$ROOT"/scenarios/scenario_*.lua "$EEHOME/.emptyepsilon/scripts/" 2>/dev/null || true
cp "$SCEN" "$EEHOME/.emptyepsilon/scripts/"

# --- run ---------------------------------------------------------------------
PORT="${SMOKE_PORT:-35777}"
TIMEOUT="${SMOKE_TIMEOUT:-30}"     # max seconds to wait for scenario load
SETTLE="${SMOKE_SETTLE:-4}"        # extra seconds of run-time after load
echo "==> $BIN headless=$BASE startpaused=1 server_port=$PORT  (load timeout ${TIMEOUT}s)"
for d in resources scripts packs; do
    [[ -e "$DATA/$d" ]] && ln -sfn "$DATA/$d" "$EEHOME/run/$d"
done
mkdir -p "$EEHOME/run/logs"
cd "$EEHOME/run"
HOME="$EEHOME" EE_CONF_DIR="$EEHOME/.emptyepsilon" \
LD_LIBRARY_PATH="${LD_PATH}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-dummy}" SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-dummy}" \
${EE_NS[@]+"${EE_NS[@]}"} \
"$BIN" headless="$BASE" startpaused=1 server_port="$PORT" "$@" \
    <<< 'return "smoke-probe: ok"' > "$EEHOME/run/ee.log" 2>&1 &
game_pid=$!

LOG="$EEHOME/run/ee.log"
loaded=0
for ((t=0; t<TIMEOUT*2; t++)); do
    kill -0 "$game_pid" 2>/dev/null || break          # exited on its own
    grep -q "Load script: $BASE" "$LOG" && { loaded=1; break; }
    sleep 0.5
done
if [[ $loaded -eq 1 ]]; then
    sleep "$SETTLE"        # let update()/transitions run a bit so errors surface
    grep -q "Load script: $BASE" "$LOG" || loaded=2   # sanity: still true
fi
kill -9 "$game_pid" 2>/dev/null
wait "$game_pid" 2>/dev/null
rc=$?
# rc 124 = killed by timeout, i.e. the game ran fine until we stopped it.

# --- analyze -----------------------------------------------------------------
status=0
[[ $loaded -eq 1 ]] || { echo "ERROR: scenario '$BASE' was never loaded within ${TIMEOUT}s. Last log lines:"; tail -20 "$LOG"; exit 1; }

if errors="$(grep -inE 'script error|attempt to (call|index|perform)|error loading|Unknown scenario meta data|No scenario category' "$LOG")"; then
    echo "SCRIPT ERRORS found:"; echo "$errors" | head -20
    status=1
fi
warns="$(grep -inE 'warning' "$LOG" | grep -viE 'potentially a risk|invalid server_port' | head -5)" || true
if [[ -n "$warns" ]]; then
    echo "Warnings:"; echo "$warns"
fi

if [[ $status -eq 0 ]]; then
    echo "OK: scenario '$BASE' booted headless without script errors."
fi
echo "--- log excerpt -----------------------------------------------------------"
grep -inE 'scenario|lua|error|warning' "$LOG" | head -25 || true
exit $status
