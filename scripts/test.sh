#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/paths.sh"
export CLANG_MODULE_CACHE_PATH="$build_root/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_root/swift-cache"
xcrun swift test --package-path "$project_root" --scratch-path "$build_root/build" \
    --cache-path "$build_root/cache" --config-path "$build_root/config" \
    --security-path "$build_root/security" --disable-sandbox
