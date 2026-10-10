#!/usr/bin/env bash
# ee_play.sh - run Empty Epsilon graphically from an Apptainer image, with the
# host HOME hidden. This is the real-play / human-acceptance path; automated
# checks use ee_smoke.sh and ee_func.sh (no container needed).
#
# The isolation is the point: it always passes --contain --no-home, so neither
# your home nor your CWD is visible inside. Exactly three things are exposed:
#   * $EE_SCENARIO_DIR -> /opt/eehome/.emptyepsilon/scripts (read-only)
#   * $EE_VENDOR/ee-state -> /opt/eehome/.emptyepsilon (persistent options.ini)
#   * /tmp/.X11-unix, /dev/dri, /dev/snd (graphical play)
#
# Usage:
#   ee_play.sh [game args...]              # graphical: mission menu etc.
#   ee_play.sh headless=scenario_x.lua     # headless server boot
#   ee_play.sh --exec CMD [ARGS...]        # shell command inside the image
#   ee_play.sh --build                     # (re)build the image first
# Env: EE_IMAGE, EE_IMAGE_TYPE=sif|sandbox, EE_APPTAINER, EE_EXTRA_APPTAINER_ARGS
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/ee_env.sh"

usage() { sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

MODE=run; BUILD=0; GAME_ARGS=(); EXEC_CMD=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -b|--build) BUILD=1; shift ;;
        -e|--exec) MODE=exec; EXEC_CMD=("${@:2}"); [[ ${#EXEC_CMD[@]} -gt 0 ]] ||
                       { echo "ee_play.sh: --exec needs a command" >&2; exit 2; }; break ;;
        *) GAME_ARGS+=("$1"); shift ;;
    esac
done

APPTAINER="${EE_APPTAINER:-$(command -v apptainer || true)}"
if [[ -z "$APPTAINER" ]]; then
    echo "ee_play.sh: apptainer not found. Load it (e.g. 'module load apptainer')" >&2
    echo "  or set EE_APPTAINER=/path/to/apptainer. This package never installs it." >&2
    exit 3
fi

IMAGE="${EE_IMAGE:-}"
if [[ -z "$IMAGE" ]]; then
    for c in "$EE_VENDOR/ee.sif" "$EE_VENDOR/ee-rootfs"; do
        [[ -e "$c" ]] && { IMAGE="$c"; break; }
    done
fi
if [[ $BUILD == 1 || -z "$IMAGE" ]]; then
    kind="${EE_IMAGE_TYPE:-}"
    if [[ -z "$kind" ]]; then
        if [[ $EUID -eq 0 ]] || grep -qw squashfs /proc/filesystems; then kind=sif; else kind=sandbox; fi
    fi
    if [[ $kind == sif ]]; then
        target="$EE_VENDOR/ee.sif"; extra=(--fakeroot)
        [[ $EUID -eq 0 ]] && extra=()
    else
        target="$EE_VENDOR/ee-rootfs"; extra=(--sandbox)
    fi
    echo "ee_play.sh: building $kind image -> $target (first time takes minutes) ..."
    cd "$EE_REPO"          # %files paths in ee.def are CWD-relative
    "$APPTAINER" build "${extra[@]}" "$target" "$EE_PKG_DIR/bin/ee.def"
    IMAGE="$target"
fi

STATE="$EE_VENDOR/ee-state"
mkdir -p "$STATE"
BASE_ARGS=( --contain --no-home --pwd /opt/eehome
    --bind "$STATE:/opt/eehome/.emptyepsilon" )
[[ -d "$EE_SCENARIO_DIR" ]] && BASE_ARGS+=( --bind "$EE_SCENARIO_DIR:/opt/eehome/.emptyepsilon/scripts:ro" )

[[ -d /tmp/.X11-unix ]] && BASE_ARGS+=( --bind /tmp/.X11-unix:/tmp/.X11-unix )
[[ -d /dev/dri ]]       && BASE_ARGS+=( --bind /dev/dri:/dev/dri )
[[ -d /dev/snd ]]       && BASE_ARGS+=( --bind /dev/snd:/dev/snd )
BASE_ARGS+=( --env "DISPLAY=${DISPLAY:-:0}" )
XAUTH="${XAUTHORITY:-$HOME/.Xauthority}"     # the one home FILE ever exposed
[[ -f "$XAUTH" ]] && BASE_ARGS+=( --bind "$XAUTH:$XAUTH" --env "XAUTHORITY=$XAUTH" )
# shellcheck disable=SC2206
[[ -n "${EE_EXTRA_APPTAINER_ARGS:-}" ]] && BASE_ARGS+=( ${EE_EXTRA_APPTAINER_ARGS} )

if [[ $MODE == exec ]]; then
    exec "$APPTAINER" exec "${BASE_ARGS[@]}" "$IMAGE" "${EXEC_CMD[@]}"
fi
exec "$APPTAINER" run "${BASE_ARGS[@]}" "$IMAGE" ${GAME_ARGS[@]+"${GAME_ARGS[@]}"}
