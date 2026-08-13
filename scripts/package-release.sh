#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${SIGNING_MODE:-}"
BUILD_ROOT="${INSTANT_TRANSLATION_BUILD_ROOT:-$ROOT/build}"
PACKAGE_APP_SCRIPT="${INSTANT_TRANSLATION_PACKAGE_APP_SCRIPT:-$ROOT/scripts/package-app.sh}"

if [[ "$MODE" != "adhoc" ]]; then
    echo "error: release packaging accepts only SIGNING_MODE=adhoc" >&2
    exit 64
fi

APP_OUTPUT="$(
    SIGNING_MODE=adhoc \
    INSTANT_TRANSLATION_BUILD_ROOT="$BUILD_ROOT" \
        "$PACKAGE_APP_SCRIPT"
)"
APP="${APP_OUTPUT##*$'\n'}"
if [[ ! -d "$APP" ]]; then
    echo "error: package-app did not produce an application bundle" >&2
    exit 66
fi

RELEASE_DIR="$BUILD_ROOT/release"
ZIP_NAME="Loquat-macOS.zip"
mkdir -p "$RELEASE_DIR"
rm -f "$RELEASE_DIR/$ZIP_NAME" "$RELEASE_DIR/SHA256SUMS"

# release 只归档已签名的 .app；不遍历仓库，因此不会夹带缓存、凭据或本地签名输入。
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
