#!/bin/bash
# Create a local drag-to-Applications disk image. No Apple signing or notarization.
set -euo pipefail
export NARLY_CHANNEL=release
source "$(dirname "$0")/paths.sh"
bash "$project_root/scripts/build.sh"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")"
architecture="$(uname -m)"
image_path="$project_root/dist/Narly-$version-$build-$architecture.dmg"
staging="$(mktemp -d "$build_root/dmg.XXXXXX")"
mount_path="$staging/mounted"
cleanup() {
    if /sbin/mount | /usr/bin/grep -Fq " on $mount_path ("; then
        hdiutil detach "$mount_path" >/dev/null || return
    fi
    rm -rf "$staging"
}
trap cleanup EXIT
mkdir -p "$staging/contents"
ditto --norsrc "$app_path" "$staging/contents/Narly.app"
cp "$project_root/LICENSE" "$staging/contents/LICENSE"
ln -s /Applications "$staging/contents/Applications"
codesign --verify --deep --strict "$staging/contents/Narly.app"
# Set the volume icon on the actual filesystem before compressing the image.
hdiutil create -volname Narly -srcfolder "$staging/contents" -format UDRW "$staging/writable.dmg"
hdiutil attach -nobrowse -mountpoint "$mount_path" "$staging/writable.dmg"
cp "$app_path/Contents/Resources/Narly.icns" "$mount_path/.VolumeIcon.icns"
xcrun SetFile -a C "$mount_path"
hdiutil detach "$mount_path"
hdiutil convert "$staging/writable.dmg" -format UDZO -o "$staging/Narly.dmg"
hdiutil verify "$staging/Narly.dmg"
# Finder and Quick Look use the file's custom icon before the image is mounted.
xcrun swift -module-cache-path "$build_root/swift-cache" \
    "$project_root/scripts/set-file-icon.swift" \
    "$app_path/Contents/Resources/Narly.icns" "$staging/Narly.dmg"
mv -f "$staging/Narly.dmg" "$image_path"
(cd "$(dirname "$image_path")" && shasum -a 256 "$(basename "$image_path")") > "$image_path.sha256"
printf 'DMG: %s\n' "$image_path"
