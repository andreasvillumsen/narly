#!/bin/bash
set -euo pipefail
export NARLY_CHANNEL=dev
launch=true
for argument in "$@"; do
    case "$argument" in
        --release) export NARLY_CHANNEL=release ;;
        --build-only) launch=false ;;
        *) printf 'Usage: %s [--release] [--build-only]\n' "$0" >&2; exit 2 ;;
    esac
done
source "$(dirname "$0")/paths.sh"
bash "$project_root/scripts/build.sh"
qa_path="$build_root/dist/Narly QA.app"
mkdir -p "$qa_path/Contents/MacOS"
xcrun swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macos26.0" -module-cache-path "$build_root/clang-cache" \
    "$project_root/Tests/Manual/NarlyQA.swift" -o "$qa_path/Contents/MacOS/NarlyQA"
python3 - "$qa_path" <<'PY'
import pathlib, plistlib, sys
path = pathlib.Path(sys.argv[1]) / 'Contents/Info.plist'
with path.open('wb') as output:
    plistlib.dump({'CFBundleIdentifier': 'app.narlymac.qa', 'CFBundleName': 'Narly QA',
                  'CFBundleExecutable': 'NarlyQA', 'CFBundlePackageType': 'APPL',
                  'NSPrincipalClass': 'NSApplication', 'LSMinimumSystemVersion': '26.0'}, output)
PY
codesign --force --sign - "$qa_path"
codesign --verify --deep --strict "$qa_path"
if "$launch"; then
    /usr/bin/open -n "$qa_path" --args --app-path "$app_path"
fi
printf 'QA bundle: %s\nTarget: %s\n' "$qa_path" "$app_path"
