#!/bin/bash
# Shared paths; independent of the directory containing the checkout.
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_key="$(printf '%s' "$project_root" | shasum -a 256 | cut -c 1-12)"
build_root="${NARLY_BUILD_ROOT:-/private/tmp/narly-$(id -u)-$project_key}"
build_channel="${NARLY_CHANNEL:-release}"
case "$build_channel" in
    release) app_name="Narly"; bundle_id="app.narlymac"; configuration="release" ;;
    dev) app_name="Narly Dev"; bundle_id="app.narlymac.dev"; configuration="debug" ;;
    *) printf 'NARLY_CHANNEL must be release or dev.\n' >&2; exit 2 ;;
esac
app_path="$build_root/dist/$app_name.app"
archive_path="$project_root/dist/$app_name.zip"
diagnostic_directory="$project_root/work/diagnostics"
