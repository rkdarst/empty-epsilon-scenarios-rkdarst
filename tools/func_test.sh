#!/usr/bin/env bash
# Thin wrapper -> ee-skills/bin/ee_func.sh (all logic and env knobs live there;
# see ee-skills/testing/runner-anatomy.md). Kept so existing muscle memory works.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ee-skills/bin/ee_func.sh" "$@"
