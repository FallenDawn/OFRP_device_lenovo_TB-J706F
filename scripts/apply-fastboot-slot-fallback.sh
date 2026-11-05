#!/usr/bin/env bash
set -euo pipefail

# Run from the Android/OrangeFox source root.
SOURCE_ROOT="$(pwd -P)"
DEVICE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PATCH_FILE="$DEVICE_DIR/patches/fastboot-slot-fallback.patch"
CORE_DIR="$SOURCE_ROOT/system/core"

if [[ ! -f "$CORE_DIR/fastboot/device/fastboot_device.cpp" || ! -f "$CORE_DIR/fastboot/device/variables.cpp" ]]; then
    echo "ERROR: system/core fastboot sources not found under: $CORE_DIR" >&2
    echo "Run this script from the Android/OrangeFox source root." >&2
    exit 2
fi

if git -C "$CORE_DIR" apply --reverse --check "$PATCH_FILE" >/dev/null 2>&1; then
    echo "Already applied: $PATCH_FILE"
    exit 0
fi

git -C "$CORE_DIR" apply --check "$PATCH_FILE"
git -C "$CORE_DIR" apply "$PATCH_FILE"
git -C "$CORE_DIR" diff --check
echo "Applied fastboot slot fallback patch to $CORE_DIR"
