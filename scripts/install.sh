#!/bin/bash
set -euo pipefail
export NARLY_CHANNEL="${NARLY_CHANNEL:-release}"
source "$(dirname "$0")/paths.sh"
destination="/Applications/$app_name.app"
if [ ! -d "$app_path" ]; then
    bash "$project_root/scripts/build.sh"
fi
if [ -e "$destination" ]; then
    existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")"
    if [ "$existing_id" != "$bundle_id" ]; then
        printf 'Another app already exists at %s. Aborting.\n' "$destination" >&2
        exit 1
    fi
fi
codesign --verify --deep --strict "$app_path"
ditto --norsrc "$app_path" "$destination"
codesign --verify --deep --strict "$destination"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$destination"
printf 'Installed: %s\nChoose “Set as default browser” in %s’s settings when you are ready.\n' "$destination" "$app_name"
