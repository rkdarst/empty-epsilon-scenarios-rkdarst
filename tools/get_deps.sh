#!/usr/bin/env bash
# Fetch the runtime shared libraries the official EE deb needs (SDL2 chain)
# and extract them under vendor/libs/ so the vendored binary runs on a host
# without those packages (no root needed). Ubuntu 24.04 (noble) x86_64 only.
# Idempotent-ish: re-running re-extracts over vendor/libs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIBS="$ROOT/vendor/libs"
INDEX="${TMPDIR:-/tmp}/noble_Packages"

if [[ ! -s "$INDEX" ]]; then
    echo "Fetching Ubuntu noble package index ..."
    curl -sL --max-time 90 http://archive.ubuntu.com/ubuntu/dists/noble/main/binary-amd64/Packages.gz \
        | gzip -dc > "$INDEX"
fi

PKGS=(
    libsdl2-2.0-0 libpulse0 libasyncns0 libsndfile1 libapparmor1 libsystemd0
    libdbus-1-3 libdecor-0-0 libsamplerate0 libxss1 libflac12t64 libvorbis0a
    libvorbisenc2 libogg0 libopus0 libwavpack1 libmp3lame0 libmpg123-0t64
    liblzma5 libzstd1 liblz4-1 libcap2 libgcrypt20 libgpg-error0 libblkid1
    libmount1 libselinux1 libseccomp2 liburing2 libgl1 libglvnd0 libgles2
)

mkdir -p "$LIBS"
cd "$ROOT/vendor"
for p in "${PKGS[@]}"; do
    fn="$(awk -v pkg="$p" '$0=="Package: "pkg{f=1} f && /^Filename:/{print $2; exit}' "$INDEX")"
    if [[ -z "$fn" ]]; then echo "MISS $p (not in main; check universe)"; continue; fi
    curl -fsL --max-time 120 -o tmp.deb "http://archive.ubuntu.com/ubuntu/$fn"
    dpkg-deb -x tmp.deb libs && rm -f tmp.deb
    echo "got $p"
done

LD_PATH="$(find "$LIBS" -type d \( -name 'x86_64-linux-gnu' -o -name 'pulseaudio' \) | paste -sd:)"
echo
echo "Use:  LD_LIBRARY_PATH=$LD_PATH"

# Verify against a vendored binary if one is present (run tools/get_ee.sh first).
BIN="$(find "$ROOT"/vendor/EE-*/usr/local/bin -type f -perm -u+x 2>/dev/null | sed -n '1p' || true)"
if [[ -n "$BIN" ]]; then
    missing="$(LD_LIBRARY_PATH="$LD_PATH" ldd "$BIN" 2>/dev/null | grep 'not found' | sort -u || true)"
    if [[ -n "$missing" ]]; then
        echo "WARNING - still unresolved:"; echo "$missing"
    else
        echo "OK: $BIN resolves all shared libraries."
    fi
fi
