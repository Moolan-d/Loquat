#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

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

codesign --force --deep --sign - "$APP"
"$ROOT/scripts/verify-adhoc-app.sh" "$APP"

echo "$APP"
