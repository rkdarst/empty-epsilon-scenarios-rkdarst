# shellcheck shell=bash
# ee_env.sh - shared discovery for every ee-skills script. Source, do not run.
#
# Everything is overridable by env so one copy of the package works in a
# scenario repo, in a scratch dir, or on a CI box:
#   EE_ROOT          project root (default: dir the package sits in)
#   EE_VENDOR        dir holding EE-<tag>/ (default: repo vendor, package
#                    vendor, ~/.cache/ee-skills/vendor - whichever has one)
#   EE_SCENARIO_DIR  dir with scenario_*.lua to expose to the game
#   EE_TAG           pin a vendored release (default: newest)
#   EE_LIBS          dir holding the SDL2 chain from ee_deps.sh

EE_PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -n "${EE_ROOT:-}" ]]; then
    EE_REPO="$EE_ROOT"
elif [[ -d "$EE_PKG_DIR/../vendor" || -d "$EE_PKG_DIR/../scenarios" || -d "$EE_PKG_DIR/../.git" ]]; then
    EE_REPO="$(cd "$EE_PKG_DIR/.." && pwd)"     # package dropped into a repo
else
    EE_REPO="$EE_PKG_DIR"                        # package IS the whole project
fi

_ee_find_vendor() {
    local c
    for c in "$EE_REPO/vendor" "$EE_PKG_DIR/vendor" "$HOME/.cache/ee-skills/vendor"; do
        if compgen -G "$c/EE-*/" > /dev/null 2>&1; then echo "$c"; return 0; fi
    done
    echo "$EE_REPO/vendor"          # for the "run ee_get.sh first" error path
}
EE_VENDOR="${EE_VENDOR:-$(_ee_find_vendor)}"
EE_LIBS="${EE_LIBS:-$EE_VENDOR/libs}"
EE_SCENARIO_DIR="${EE_SCENARIO_DIR:-$EE_REPO/scenarios}"

# ee_locate -> sets EE_BIN + EE_DATA (game resolves resources/ scripts/ packs/
# from the CWD, so the runner must cd to EE_DATA) or returns non-zero.
ee_locate() {
    local dest
    if [[ -n "${EE_TAG:-}" ]]; then
        dest="$EE_VENDOR/$EE_TAG"
    else
        dest="$(ls -d "$EE_VENDOR"/EE-*/ 2>/dev/null | sort | tail -1)"
    fi
    [[ -n "${dest:-}" && -d "$dest" ]] || { echo "ERROR: no vendored release in $EE_VENDOR - run ee_get.sh first." >&2; return 2; }
    EE_BIN="$(find "$dest" -type f \( -name 'emptyepsilon' -o -name 'EmptyEpsilon' \) -perm -u+x | head -1)"
    [[ -n "$EE_BIN" ]] || { echo "ERROR: no EmptyEpsilon binary under $dest" >&2; return 2; }
    local basic
    basic="$(find "$dest" -path '*/scripts/scenario_00_basic.lua' | head -1)"
    EE_DATA="$(dirname "$(dirname "$basic")")"
    [[ -n "$EE_DATA" && -d "$EE_DATA" ]] || { echo "ERROR: no data dir (scripts/+resources/) under $dest" >&2; return 2; }
    EE_LD=""
    while IFS= read -r d; do EE_LD+="${EE_LD:+:}$d"; done < <(find "$EE_LIBS" -type d \( -name 'x86_64-linux-gnu' -o -name 'pulseaudio' \) 2>/dev/null | sort)
    return 0
}

# EE 2024.12.08 ALWAYS binds TCP/UDP 35666 at boot (the server_port preference
# is not applied to the headless listener) and SEGFAULTS when the bind fails -
# e.g. a GUI game is open. Set EE_NS to a netns wrapper, or fail with exit 4.
ee_guard_port() {
    EE_NS=()
    # Serialize runners. Headless EE always binds 35666, so two runs started in
    # the same second both pass the "port free" probe below and the loser
    # segfaults on the bind. Take a machine-wide lock first (the fd stays open
    # for the rest of the script and is inherited by the game, so it is released
    # when the run ends) and give up rather than block forever.
    if command -v flock > /dev/null 2>&1; then
        EE_LOCK="${EE_LOCK:-${TMPDIR:-/tmp}/ee-headless.lock}"
        if ! eval "exec 9>\"\$EE_LOCK\"" 2>/dev/null; then return 0; fi
        if ! flock -w "${EE_LOCK_TIMEOUT:-1800}" 9; then
            echo "ERROR: another runner still holds $EE_LOCK after" >&2
            echo "       ${EE_LOCK_TIMEOUT:-1800}s - check for a stuck EmptyEpsilon process." >&2
            exit 4
        fi
    fi
    command -v python3 > /dev/null 2>&1 || return 0
    if python3 - <<'PYEOF'
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
    then return 0; fi
    if command -v unshare > /dev/null 2>&1; then
        echo "NOTE: port 35666 busy (another EE instance running?) - using a private netns" >&2
        # The trailing & is important: unshare exec()s its argument only AFTER
        # the netns exists, so the game would otherwise be a child of the
        # wrapper and outlive the kill -9 of its own pid (a survivor then owns
        # 35666 and poisons every later run). Background it inside the netns.
        EE_NS=(unshare -rn sh -c 'ip link set lo up 2>/dev/null || true; "$@" & child=$!; trap "kill -9 $child 2>/dev/null" EXIT; wait "$child"' ee-ns)
    else
        echo "ERROR: port 35666 is in use - another Empty Epsilon instance is running on" >&2
        echo "       this machine (headless EE always binds 35666 and crashes if it" >&2
        echo "       cannot). Close the other instance and retry." >&2
        exit 4
    fi
}
