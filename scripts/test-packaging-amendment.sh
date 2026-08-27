#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d -t instant-translation-packaging-tests)"
trap 'rm -rf "$TEMP_ROOT"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

FAKE_APP="$TEMP_ROOT/Loquat.app"
mkdir -p "$FAKE_APP/Contents/MacOS"
printf 'fixture executable\n' >"$FAKE_APP/Contents/MacOS/InstantTranslation"

FAKE_PACKAGE_APP="$TEMP_ROOT/package-app-fixture.sh"
cat >"$FAKE_PACKAGE_APP" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
echo "$FAKE_APP"
SCRIPT
chmod +x "$FAKE_PACKAGE_APP"

FORBIDDEN_TOOL_MARKER="$TEMP_ROOT/forbidden-tool-called"
FAKE_BIN="$TEMP_ROOT/bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/xcrun" <<'SCRIPT'
#!/usr/bin/env bash
touch "$FORBIDDEN_TOOL_MARKER"
exit 99
SCRIPT

cat >"$FAKE_BIN/spctl" <<'SCRIPT'
#!/usr/bin/env bash
touch "$FORBIDDEN_TOOL_MARKER"
exit 99
SCRIPT

chmod +x "$FAKE_BIN/xcrun" "$FAKE_BIN/spctl"

BUILD_ROOT="$TEMP_ROOT/build"
env -u DEVELOPMENT_TEAM \
    -u CODE_SIGN_IDENTITY \
    -u PROVISIONING_PROFILE \
    -u NOTARYTOOL_PROFILE \
    PATH="$FAKE_BIN:$PATH" \
    FORBIDDEN_TOOL_MARKER="$FORBIDDEN_TOOL_MARKER" \
    INSTANT_TRANSLATION_BUILD_ROOT="$BUILD_ROOT" \
    INSTANT_TRANSLATION_PACKAGE_APP_SCRIPT="$FAKE_PACKAGE_APP" \
    "$ROOT/scripts/package-release.sh" >/dev/null

RELEASE_DIR="$BUILD_ROOT/release"
[[ -f "$RELEASE_DIR/Loquat-macOS.zip" ]] || fail "release ZIP missing"
[[ -f "$RELEASE_DIR/SHA256SUMS" ]] || fail "release checksum missing"
(cd "$RELEASE_DIR" && shasum -a 256 -c SHA256SUMS)
[[ "$(unzip -Z1 "$RELEASE_DIR/Loquat-macOS.zip" | head -1)" == "Loquat.app/" ]] \
    || fail "release ZIP does not start with Loquat.app/"
if unzip -Z1 "$RELEASE_DIR/Loquat-macOS.zip" | grep -Eq '(^|/)(\._|__MACOSX)'; then
    fail "release contains AppleDouble or resource-fork metadata"
fi
[[ ! -e "$FORBIDDEN_TOOL_MARKER" ]] \
    || fail "release packaging invoked a notarization tool"

echo "packaging amendment regressions passed"
