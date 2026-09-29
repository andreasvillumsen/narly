#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/paths.sh"
mkdir -p "$build_root" "$project_root/dist" "$project_root/Assets" "$diagnostic_directory"
export CLANG_MODULE_CACHE_PATH="$build_root/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_root/swift-cache"
xcrun swift build --package-path "$project_root" --scratch-path "$build_root/build" \
    --cache-path "$build_root/cache" --config-path "$build_root/config" \
    --security-path "$build_root/security" --disable-sandbox -c "$configuration"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$project_root/LICENSE" "$app_path/Contents/Resources/LICENSE"
binary_root="$(xcrun swift build --package-path "$project_root" --scratch-path "$build_root/build" \
    --cache-path "$build_root/cache" --config-path "$build_root/config" \
    --security-path "$build_root/security" --disable-sandbox -c "$configuration" --show-bin-path)"
cp "$binary_root/Narly" "$app_path/Contents/MacOS/$app_name"
# The GUI app localizes through Bundle.main; SwiftPM tests use Bundle.module.
for localization in "$project_root"/Sources/PickerKit/Resources/*.lproj; do
    ditto "$localization" "$app_path/Contents/Resources/$(basename "$localization")"
done
"$binary_root/NarlyIconExporter" "$build_root/Narly.iconset" "$project_root/Assets/Narly-AppIcon.png"
cp "$project_root/Assets/Narly-AppIcon.png" "$app_path/Contents/Resources/Narly-AppIcon.png"
cp "$project_root/Assets/Narly-MenuBar.png" "$app_path/Contents/Resources/Narly-MenuBar.png"
# Package an explicit native icon. A standalone legacy ICNS makes macOS place
# the already-rounded artwork inside a second, gray enclosure.
mkdir -p "$build_root/Narly.icon/Assets"
cp "$project_root/Assets/Narly.icon.json" "$build_root/Narly.icon/icon.json"
cp "$project_root/Assets/Narly-AppIcon.png" "$build_root/Narly.icon/Assets/Narly-AppIcon.png"
xcrun actool "$build_root/Narly.icon" \
    --compile "$app_path/Contents/Resources" \
    --platform macosx --minimum-deployment-target 26.0 --app-icon Narly \
    --output-partial-info-plist "$build_root/Narly-icon-info.plist"
cp "$build_root/Narly.iconset/icon_512x512@2x.png" "$project_root/Assets/Narly-AppIcon-Preview.png"
python3 - "$app_path" "$project_root" "$app_name" "$bundle_id" "$build_channel" <<'PY'
import hashlib, pathlib, plistlib, sys
app, source = map(pathlib.Path, sys.argv[1:3])
name, bundle_id, channel = sys.argv[3:]
h = hashlib.sha256()
inputs = [source / 'LICENSE', source / 'Package.swift', source / 'Assets/Narly-AppIcon.png', source / 'Assets/Narly.icon.json', source / 'Assets/Narly-MenuBar.png'] + list((source / 'Sources').rglob('*.swift')) + list((source / 'Sources').rglob('*.strings')) + list((source / 'scripts').glob('*.sh'))
for p in sorted(inputs):
    h.update(p.relative_to(source).as_posix().encode())
    h.update(p.read_bytes())
plist = {
    'CFBundleExecutable': name,
    'CFBundleIdentifier': bundle_id,
    'CFBundleName': name,
    'CFBundleDevelopmentRegion': 'en', 'CFBundleLocalizations': ['en', 'da'],
    'CFBundleDisplayName': name,
    'CFBundlePackageType': 'APPL', 'CFBundleIconFile': 'Narly',
    'CFBundleIconName': 'Narly',
    'CFBundleShortVersionString': '0.2.0', 'CFBundleVersion': '26',
    'LSApplicationCategoryType': 'public.app-category.utilities',
    'LSMinimumSystemVersion': '26.0', 'LSUIElement': True,
    'NSPrincipalClass': 'NSApplication', 'NSHighResolutionCapable': True,
    'NSQuitAlwaysKeepsWindows': False,
    'CFBundleURLTypes': [{'CFBundleURLName': 'Web link', 'CFBundleTypeRole': 'Viewer',
                          'CFBundleURLSchemes': ['http', 'https']}],
    'CFBundleDocumentTypes': [
        {'CFBundleTypeName': 'HTML document', 'CFBundleTypeRole': 'Viewer',
         'LSHandlerRank': 'Default', 'LSItemContentTypes': ['public.html']},
        {'CFBundleTypeName': 'XHTML document', 'CFBundleTypeRole': 'Viewer',
         'LSHandlerRank': 'Default', 'LSItemContentTypes': ['public.xhtml']},
    ],
    'NarlyBuildID': 'narly-' + channel + '-' + h.hexdigest()[:12],
    'NarlyBuildChannel': channel,
}
with (app / 'Contents/Info.plist').open('wb') as f:
    plistlib.dump(plist, f)
print('Build:', plist['NarlyBuildID'])
PY
codesign --force --sign - --options runtime "$app_path"
codesign --verify --deep --strict "$app_path"
# A ZIP keeps iCloud from adding FinderInfo to the signed bundle itself.
ditto -c -k --norsrc --keepParent "$app_path" "$archive_path"
printf 'App: %s\n' "$app_path"
printf 'Archive: %s\n' "$archive_path"
