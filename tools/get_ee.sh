#!/usr/bin/env bash
# Download and unpack an official Empty Epsilon Linux release into vendor/.
# Usage: tools/get_ee.sh [TAG]     (default: latest stable)
set -euo pipefail

TAG="${1:-EE-2024.12.08}"
REPO="daid/EmptyEpsilon"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/vendor"
DEB="$VENDOR/Linux_EmptyEpsilon_$TAG.deb"
DEST="$VENDOR/$TAG"

mkdir -p "$VENDOR"

if [[ ! -s "$DEB" ]]; then
    url="https://github.com/$REPO/releases/download/$TAG/Linux_EmptyEpsilon_$TAG.deb"
    echo "Downloading $url (~270 MB) ..."
    curl -fL --retry 3 -o "$DEB.part" "$url"
    mv "$DEB.part" "$DEB"
else
    echo "Using cached $(basename "$DEB")"
fi

if [[ ! -d "$DEST/usr" ]]; then
    echo "Unpacking into vendor/$TAG ..."
    mkdir -p "$DEST"
    dpkg-deb -x "$DEB" "$DEST"
else
    echo "Already unpacked: vendor/$TAG"
fi

echo "Executable(s):"
find "$DEST" -type f \( -name 'emptyepsilon' -o -name 'EmptyEpsilon' \) -perm -u+x
echo "Script dir:"
find "$DEST" -path '*/scripts/scenario_00_basic.lua' -printf '%h\n' 2>/dev/null || \
    find "$DEST" -path '*/scripts/scenario_00_basic.lua' | sed 's|/scenario_00_basic.lua||'
echo "API reference:"
find "$DEST" -name 'script_reference.html'
