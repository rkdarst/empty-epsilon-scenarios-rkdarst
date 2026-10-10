#!/usr/bin/env bash
# ee_selftest.sh - prove that THIS package is self-sufficient: it copies itself
# into a scratch dir (so nothing outside the package can be relied on by
# accident) and runs the whole loop on the bundled demo scenario - boot check,
# then a self-driving assertion timeline. Exit 0 = the package alone can build
# and test a scenario, with no repo scenarios/, tests/ or notes/ present.
#
# Usage: ee_selftest.sh        env: EE_VENDOR (defaults to the repo's vendor)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "${BASH_SOURCE[0]}")/ee_env.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
if command -v rsync > /dev/null 2>&1; then
    rsync -a --exclude vendor --exclude .git "$HERE/../" "$TMP/ee-skills/"
else
    mkdir -p "$TMP/ee-skills" && cp -r "$HERE/.." "$TMP/ee-skills"/ 2>/dev/null
    rm -rf "$TMP/ee-skills/ee-skills/vendor"
fi
PKG="$TMP/ee-skills/bin"
DEMO="$TMP/ee-skills/examples/demo"
[[ -d "$PKG" && -f "$DEMO/scenario_95_demo.lua" ]] || { echo "selftest: package copy incomplete"; exit 2; }

export EE_VENDOR="${EE_VENDOR:-$EE_VENDOR}"
export EE_SCENARIO_DIR="$DEMO"

echo "=== 1/3 boot check (ee_smoke.sh) =========================================="
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-35}" "$PKG/ee_smoke.sh" "$DEMO/scenario_95_demo.lua" || exit 1

echo "=== 2/3 assertion timeline (ee_func.sh, explicit AUTOTEST) ================="
RUNTIME="${RUNTIME:-240}" AUTOTEST="$DEMO/autotest.lua" \
    "$PKG/ee_func.sh" "$DEMO/scenario_95_demo.lua" || exit 1

echo "=== 3/3 driver discovery + settings prelude (EE_ROOT=$TMP) ================="
mkdir -p "$TMP/tests"
cp "$DEMO/autotest.lua" "$TMP/tests/scenario_95_demo.autotest.lua"
RUNTIME="${RUNTIME:-240}" EE_ROOT="$TMP" EE_SETTINGS="Difficulty=Story" \
    "$PKG/ee_func.sh" "$DEMO/scenario_95_demo.lua" || exit 1

echo
echo "SELFTEST OK - the package built and self-tested a scenario from scratch."
