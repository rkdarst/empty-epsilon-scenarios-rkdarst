#!/usr/bin/env bash
# Functional test: boot a scenario headless (unpaused) and let it run.
# If tools/autotest/lc_autotest.lua exists it is dropped into the throwaway
# scripts dir, where the scenario's guarded require picks it up and drives a
# timed assertion walk through all phases. Optional second argument: a file of
# raw console commands fed with GAP spacing (best-effort; headless stdin may
# be ignored by the engine).
#
# Usage: tools/func_test.sh scenarios/scenario_NN_x.lua [cmds.txt]
#   RUNTIME=60 game seconds   GAP=4 between console cmds   SMOKE_TIMEOUT=40 load wait
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCEN="${1:?usage: func_test.sh <scenario.lua> [cmds.txt]}"

# EE 2024.12.08 always listens on TCP/UDP 35666 at boot and SEGFAULTS when the
# bind fails; if another instance owns the port, run the game in a private
# network namespace (or fail early with a hint).
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
        echo "       this machine. Close it and retry (exit 4)." >&2
        exit 4
    fi
fi
CMDS="${2:-}"
[[ -f "$SCEN" ]] || { echo "not a file: $SCEN" >&2; exit 2; }
BASE="$(basename "$SCEN")"
if [[ -n "${SMOKE_EE_TAG:-}" ]]; then DEST="$ROOT/vendor/$SMOKE_EE_TAG"; else
    DEST="$(ls -d "$ROOT"/vendor/EE-*/ 2>/dev/null | sort | tail -1)"; fi
[[ -n "${DEST:-}" && -d "$DEST" ]] || { echo "no vendored release in vendor/" >&2; exit 2; }
BIN="$(find "$DEST" -type f \( -name 'emptyepsilon' -o -name 'EmptyEpsilon' \) -perm -u+x | head -1)"
DATA="$(dirname "$(dirname "$(find "$DEST" -path '*/scripts/scenario_00_basic.lua' | head -1)")")"
[[ -n "$DATA" ]] || { echo "no data dir" >&2; exit 2; }
LD_PATH=""
while IFS= read -r d; do LD_PATH+="${LD_PATH:+:}$d"; done < <(find "$ROOT/vendor/libs" -type d \( -name 'x86_64-linux-gnu' -o -name 'pulseaudio' \) 2>/dev/null | sort)

EEHOME="$(mktemp -d)"; trap 'rm -rf "$EEHOME" "$EEHOME.fifo"' EXIT
mkdir -p "$EEHOME/.emptyepsilon/scripts" "$EEHOME/run"
DRIVER="${AUTOTEST:-$ROOT/tools/autotest/lc_autotest.lua}"
PRE="${SCEN_PRE:-}"   # optional file cat'd BEFORE the scenario (e.g. tools/autotest/story_pre.lua)
[[ -z "$PRE" || -f "$PRE" ]] || { echo "not a file: SCEN_PRE=$PRE" >&2; exit 2; }
if [[ -f "$DRIVER" ]]; then
    cat ${PRE:+"$PRE"} "$SCEN" "$DRIVER" > "$EEHOME/.emptyepsilon/scripts/$BASE"
else
    cat ${PRE:+"$PRE"} "$SCEN" > "$EEHOME/.emptyepsilon/scripts/$BASE"
fi
for d in resources scripts packs; do [[ -e "$DATA/$d" ]] && ln -sfn "$DATA/$d" "$EEHOME/run/$d"; done

RUNTIME="${RUNTIME:-60}"; TIMEOUT="${SMOKE_TIMEOUT:-40}"; GAP="${GAP:-4}"
FIFO="$EEHOME.fifo"; mkfifo "$FIFO" || exit 2
cd "$EEHOME/run"
HOME="$EEHOME" EE_CONF_DIR="$EEHOME/.emptyepsilon" \
LD_LIBRARY_PATH="${LD_PATH}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
${EE_NS[@]+"${EE_NS[@]}"} \
"$BIN" headless="$BASE" server_port="${SMOKE_PORT:-35781}" < "$FIFO" > ee.log 2>&1 &
pid=$!
exec 3>"$FIFO"
loaded=0
for ((t=0; t<TIMEOUT*2; t++)); do
    kill -0 "$pid" 2>/dev/null || { echo "ERROR: game exited early"; break; }
    grep -q "Load script: $BASE" ee.log && { loaded=1; break; }
    sleep 0.5
done
[[ $loaded -eq 1 ]] || { tail -20 ee.log; exit 1; }

if [[ -n "$CMDS" && -f "$CMDS" ]]; then
    while IFS= read -r cmd; do
        [[ -z "$cmd" || "$cmd" == \#* ]] && continue
        echo "$cmd" >&3 || break
        sleep "$GAP"
    done < "$CMDS"
fi

# let the autotest timeline play out
for ((t=0; t<RUNTIME*2; t++)); do
    kill -0 "$pid" 2>/dev/null || break
    grep -qa "LC-AUTOTEST done\|mission complete - victory declared" ee.log && { sleep 3; break; }
    sleep 0.5
done
kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null

echo "--- script output ---------------------------------------------------------"
grep -aE 'LUA:|ERROR' ee.log | sed -E 's/^(INFO: )?LUA:/LUA:/'
if grep -qa "LC-ASSERT FAIL\|LC-ASSERT ERROR" ee.log; then
    echo "RESULT: FAILURES PRESENT"; exit 1
elif grep -qa "LC-AUTOTEST done\|mission complete - victory declared" ee.log; then
    echo "RESULT: AUTOTEST PASSED"; exit 0
fi
echo "RESULT: autotest driver never finished (or is absent) - check script output"; exit 1
