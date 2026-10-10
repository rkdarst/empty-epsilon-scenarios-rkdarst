#!/usr/bin/env bash
# ee_get.sh - download + unpack an official Empty Epsilon release (no root).
# Usage: ee_get.sh [TAG]        (default: EE-2024.12.08, the version this
#                                package's facts are verified against)
# Result: $EE_VENDOR/Linux_EmptyEpsilon_<TAG>.deb + $EE_VENDOR/<TAG>/
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/ee_env.sh"

TAG="${1:-EE-2024.12.08}"
REPO="daid/EmptyEpsilon"
DEB="$EE_VENDOR/Linux_EmptyEpsilon_$TAG.deb"
DEST="$EE_VENDOR/$TAG"
mkdir -p "$EE_VENDOR"

if [[ ! -s "$DEB" ]]; then
    url="https://github.com/$REPO/releases/download/$TAG/Linux_EmptyEpsilon_$TAG.deb"
    echo "Downloading $url (~270 MB) ..."
    curl -fL --retry 3 -o "$DEB.part" "$url"
    mv "$DEB.part" "$DEB"
else
    echo "Using cached $(basename "$DEB")"
fi

if [[ ! -d "$DEST/usr" ]]; then
    echo "Unpacking into $DEST ..."
    mkdir -p "$DEST"
    dpkg-deb -x "$DEB" "$DEST"
else
    echo "Already unpacked: $DEST"
fi

echo "Executable:   $(find "$DEST" -type f \( -name 'emptyepsilon' -o -name 'EmptyEpsilon' \) -perm -u+x)"
echo "Script dir:   $(find "$DEST" -path '*/scripts/scenario_00_basic.lua' -printf '%h\n' 2>/dev/null | head -1)"
echo "API reference: $(find "$DEST" -name 'script_reference.html' | head -1)"
echo "Shipped examples: $(find "$DEST" -path '*/scripts/scenario_*.lua' | wc -l) scenario_*.lua files to mine for API usage"
