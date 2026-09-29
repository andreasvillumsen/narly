#!/bin/bash
set -euo pipefail
export NARLY_CHANNEL="${NARLY_CHANNEL:-dev}"
source "$(dirname "$0")/paths.sh"
if [ ! -d "$app_path" ]; then
    printf 'Build first with: NARLY_CHANNEL=%s bash "%s/scripts/build.sh"\n' "$build_channel" "$project_root" >&2
    exit 1
fi
case "${1:-single}" in
    single) /usr/bin/open -a "$app_path" 'https://example.com/?narly-picker=external-test' ;;
    burst)
        for n in 1 2 3 4 5 6 7 8; do
            /usr/bin/open -a "$app_path" "https://example.com/?narly-picker=burst-$n"
        done
        /usr/bin/open -a "$app_path" 'https://example.com/?narly-picker=duplicate'
        /usr/bin/open -a "$app_path" 'https://example.com/?narly-picker=duplicate'
        ;;
    *) printf 'Usage: %s [single|burst]\n' "$0" >&2; exit 2 ;;
esac
