#!/usr/bin/env bash
# ee_bootstrap.sh - get a working test environment from nothing. Fetch the game
# release (and, on a bare host, its SDL2 runtime libs), then PROVE the setup by
# booting the package's own demo scenario. Idempotent: re-running is cheap.
#
# Usage: ee_bootstrap.sh [TAG]        (default EE-2024.12.08)
# Needs once: curl, dpkg-deb, timeout, an internet route to GitHub releases.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "${BASH_SOURCE[0]}")/ee_env.sh"

"$HERE/ee_get.sh" "${1:-}"

BIN="$(find "$EE_VENDOR"/EE-*/usr/local/bin -type f -perm -u+x 2>/dev/null | sed -n '1p' || true)"
ee_locate >/dev/null 2>&1 || true      # sets EE_LD from vendor/libs if present
if [[ -n "$BIN" ]]; then
    missing="$(LD_LIBRARY_PATH="$EE_LD" ldd "$BIN" 2>/dev/null | grep 'not found' | sort -u || true)"
    if [[ -n "$missing" ]]; then
        echo "==> runtime libs missing, fetching them:"; echo "$missing"
        "$HERE/ee_deps.sh"
    else
        echo "==> runtime libraries already resolve"
    fi
fi

echo "==> proving the setup with the bundled demo scenario"
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-35}" "$HERE/ee_smoke.sh" "$EE_PKG_DIR/examples/demo/scenario_95_demo.lua"
echo "==> environment is ready (now try ee_func.sh on the demo for assertions)"
