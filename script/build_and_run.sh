#!/bin/bash
set -euo pipefail
export NARLY_CHANNEL=dev
source "$(dirname "$0")/../scripts/paths.sh"
# Only the local development app is built; no installation or defaults change.
pkill -x "$app_name" >/dev/null 2>&1 || true
bash "$project_root/scripts/build.sh"
/usr/bin/open -n "$app_path"
if [[ "${1:-}" == "--verify" ]]; then
    sleep 1
    pgrep -x "$app_name" >/dev/null
fi
