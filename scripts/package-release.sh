#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${INSTANT_TRANSLATION_BUILD_ROOT:-$ROOT/build}"
PACKAGE_APP_SCRIPT="${INSTANT_TRANSLATION_PACKAGE_APP_SCRIPT:-$ROOT/scripts/package-app.sh}"

APP_OUTPUT="$(INSTANT_TRANSLATION_BUILD_ROOT="$BUILD_ROOT" "$PACKAGE_APP_SCRIPT")"
APP="${APP_OUTPUT##*$'\n'}"
if [[ ! -d "$APP" ]]; then
    echo "error: package-app did not produce an application bundle" >&2
    exit 66
fi

RELEASE_DIR="$BUILD_ROOT/release"
ZIP_NAME="Loquat-macOS.zip"
mkdir -p "$RELEASE_DIR"
rm -f "$RELEASE_DIR/$ZIP_NAME" "$RELEASE_DIR/SHA256SUMS"

ditto \
    --norsrc \
    --noextattr \
    --noqtn \
    --noacl \
    -c -k --keepParent \
    "$APP" "$RELEASE_DIR/$ZIP_NAME"
(
    cd "$RELEASE_DIR"
    shasum -a 256 "$ZIP_NAME" >SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)

echo "$RELEASE_DIR/$ZIP_NAME"
