#!/usr/bin/env bash
# Launch Empty Epsilon from the Apptainer image with the host HOME hidden.
#
# The isolation is the point of this script: it always passes
#   --contain --no-home
# so the caller's home directory (and CWD!) are NOT visible inside the
# container. Only three things are exposed, deliberately:
#   * scenarios/          -> /opt/eehome/.emptyepsilon/scripts (read-only)
#   * vendor/ee-state/    -> /opt/eehome/.emptyepsilon (persistent options.ini)
#   * /tmp/.X11-unix, /dev/dri, /dev/snd (for graphical play)
#
# Usage:
#   tools/ee_run.sh [game args...]            # graphical: mission menu etc.
#   tools/ee_run.sh headless=scenario_x.lua   # headless server boot
#   tools/ee_run.sh --exec CMD [ARGS...]      # run a shell command in the image
#   tools/ee_run.sh --build                   # (re)build the image first
#
# Env knobs:
#   EE_IMAGE=...                explicit path to a .sif or sandbox dir
#   EE_IMAGE_TYPE=sif|sandbox   force one form for --build (default: auto)
#   EE_APPTAINER=...            apptainer binary to use (default: on PATH)
#   EE_EXTRA_APPTAINER_ARGS=... extra apptainer CLI args (word-split)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() { sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

MODE=run
BUILD=0
GAME_ARGS=()
EXEC_CMD=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -b|--build) BUILD=1; shift ;;
        -e|--exec) MODE=exec; EXEC_CMD=("${@:2}"); [[ ${#EXEC_CMD[@]} -gt 0 ]] ||
                       { echo "ee_run.sh: --exec needs a command" >&2; exit 2; }; break ;;
        *) GAME_ARGS+=("$1"); shift ;;
    esac
done

APPTAINER="${EE_APPTAINER:-$(command -v apptainer || true)}"
if [[ -z "$APPTAINER" ]]; then
    echo "ee_run.sh: apptainer not found. Load it (e.g. 'module load apptainer')" >&2
    echo "  or set EE_APPTAINER=/path/to/apptainer. It is NOT installed by this repo." >&2
    exit 3
fi

# --- pick (or build) the image -------------------------------------------
IMAGE="${EE_IMAGE:-}"
if [[ -z "$IMAGE" ]]; then
    for c in "$ROOT/vendor/ee.sif" "$ROOT/vendor/ee-rootfs"; do
        [[ -e "$c" ]] && { IMAGE="$c"; break; }
    done
fi
if [[ $BUILD == 1 || -z "$IMAGE" ]]; then
    # auto: SIF when we can build+mount one; sandbox when rootless and the
    # kernel has no squashfs module (SIF files are then unmountable).
    kind="${EE_IMAGE_TYPE:-}"
    if [[ -z "$kind" ]]; then
        if [[ $EUID -eq 0 ]] || grep -qw squashfs /proc/filesystems; then
            kind=sif
        else
            kind=sandbox
        fi
    fi
    if [[ $kind == sif ]]; then
        target="$ROOT/vendor/ee.sif"
        extra=(--fakeroot)
        [[ $EUID -eq 0 ]] && extra=()
    else
        target="$ROOT/vendor/ee-rootfs"
        extra=(--sandbox)
    fi
    echo "ee_run.sh: building $kind image -> $target (first time takes minutes) ..."
    cd "$ROOT"
    "$APPTAINER" build "${extra[@]}" "$target" tools/ee.def
    IMAGE="$target"
fi

# --- the isolation policy + the three deliberate binds -------------------
STATE="$ROOT/vendor/ee-state"
mkdir -p "$STATE"

BASE_ARGS=( --contain --no-home --pwd /opt/eehome
    --bind "$STATE:/opt/eehome/.emptyepsilon"
    --bind "$ROOT/scenarios:/opt/eehome/.emptyepsilon/scripts:ro" )

# Graphical plumbing (harmless for headless boots).
[[ -d /tmp/.X11-unix ]] && BASE_ARGS+=( --bind /tmp/.X11-unix:/tmp/.X11-unix )
[[ -d /dev/dri ]]       && BASE_ARGS+=( --bind /dev/dri:/dev/dri )
[[ -d /dev/snd ]]       && BASE_ARGS+=( --bind /dev/snd:/dev/snd )
BASE_ARGS+=( --env "DISPLAY=${DISPLAY:-:0}" )
# X cookie: bind just the one auth file (the only home path ever exposed).
XAUTH="${XAUTHORITY:-$HOME/.Xauthority}"
if [[ -f "$XAUTH" ]]; then
    BASE_ARGS+=( --bind "$XAUTH:$XAUTH" --env "XAUTHORITY=$XAUTH" )
fi

if [[ -n "${EE_EXTRA_APPTAINER_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    BASE_ARGS+=( ${EE_EXTRA_APPTAINER_ARGS} )
fi

if [[ $MODE == exec ]]; then
    exec "$APPTAINER" exec "${BASE_ARGS[@]}" "$IMAGE" "${EXEC_CMD[@]}"
fi
exec "$APPTAINER" run "${BASE_ARGS[@]}" "$IMAGE" ${GAME_ARGS[@]+"${GAME_ARGS[@]}"}