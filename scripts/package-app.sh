#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

: "${DEVELOPMENT_TEAM:?error: Developer ID packaging requires DEVELOPMENT_TEAM}"
: "${CODE_SIGN_IDENTITY:?error: Developer ID packaging requires CODE_SIGN_IDENTITY}"
if [[ ! "$DEVELOPMENT_TEAM" =~ ^[A-Z0-9]+$ ]]; then
    echo "error: DEVELOPMENT_TEAM must contain only uppercase letters and digits" >&2
    exit 64
fi

BUILD_ROOT="${INSTANT_TRANSLATION_BUILD_ROOT:-$ROOT/build}"
swift build --disable-sandbox -c release
BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"
APP="$BUILD_ROOT/Loquat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/InstantTranslation" "$APP/Contents/MacOS/InstantTranslation"
cp "$ROOT/Config/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Config/Loquat.icns" ]]; then
    cp "$ROOT/Config/Loquat.icns" "$APP/Contents/Resources/Loquat.icns"
else
    echo "warning: Config/Loquat.icns not found; packaging without app icon" >&2
fi
find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

ENTITLEMENTS="$BUILD_ROOT/InstantTranslation.entitlements.plist"
"$ROOT/scripts/materialize-entitlements.sh" "$DEVELOPMENT_TEAM" "$ENTITLEMENTS"
codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$CODE_SIGN_IDENTITY" \
    "$APP"
"$ROOT/scripts/verify-signed-app.sh" "$APP" "$DEVELOPMENT_TEAM"

echo "$APP"
