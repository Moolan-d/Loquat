#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d -t instant-translation-packaging-tests)"
trap 'rm -rf "$TEMP_ROOT"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_fails_with() {
    local expected="$1"
    shift
    local output
    if output="$("$@" 2>&1)"; then
        fail "command unexpectedly succeeded: $*"
    fi
    if [[ "$output" != *"$expected"* ]]; then
        echo "$output" >&2
        fail "expected failure containing: $expected"
    fi
}

FAKE_APP="$TEMP_ROOT/Loquat.app"
mkdir -p "$FAKE_APP/Contents/MacOS"
printf 'fixture executable\n' >"$FAKE_APP/Contents/MacOS/InstantTranslation"

PACKAGE_MARKER="$TEMP_ROOT/package-app-called"
FAKE_PACKAGE_APP="$TEMP_ROOT/package-app-fixture.sh"
cat >"$FAKE_PACKAGE_APP" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
[[ -z "\${SIGNING_MODE+x}" ]]
[[ "\${DEVELOPMENT_TEAM:-}" == "EXPECTED123" ]]
[[ "\${CODE_SIGN_IDENTITY:-}" == "Developer ID Application: Example" ]]
touch "$PACKAGE_MARKER"
echo "$FAKE_APP"
SCRIPT
chmod +x "$FAKE_PACKAGE_APP"

TOOL_LOG="$TEMP_ROOT/tool.log"
FAKE_BIN="$TEMP_ROOT/bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/xcrun" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
echo "xcrun $*" >>"$TOOL_LOG"
SCRIPT
cat >"$FAKE_BIN/spctl" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
echo "spctl $*" >>"$TOOL_LOG"
SCRIPT
chmod +x "$FAKE_BIN/xcrun" "$FAKE_BIN/spctl"

BUILD_ROOT="$TEMP_ROOT/build"
assert_fails_with \
    "NOTARYTOOL_PROFILE" \
    env -u NOTARYTOOL_PROFILE \
        DEVELOPMENT_TEAM=EXPECTED123 \
        CODE_SIGN_IDENTITY="Developer ID Application: Example" \
        INSTANT_TRANSLATION_BUILD_ROOT="$BUILD_ROOT" \
        INSTANT_TRANSLATION_PACKAGE_APP_SCRIPT="$FAKE_PACKAGE_APP" \
        "$ROOT/scripts/package-release.sh"
[[ ! -e "$PACKAGE_MARKER" ]] || fail "missing notary profile invoked package-app"

PATH="$FAKE_BIN:$PATH" \
TOOL_LOG="$TOOL_LOG" \
NOTARYTOOL_PROFILE=loquat-notary \
DEVELOPMENT_TEAM=EXPECTED123 \
CODE_SIGN_IDENTITY="Developer ID Application: Example" \
INSTANT_TRANSLATION_BUILD_ROOT="$BUILD_ROOT" \
INSTANT_TRANSLATION_PACKAGE_APP_SCRIPT="$FAKE_PACKAGE_APP" \
    "$ROOT/scripts/package-release.sh" >/dev/null

RELEASE_DIR="$BUILD_ROOT/release"
[[ -f "$RELEASE_DIR/Loquat-macOS.zip" ]]
[[ -f "$RELEASE_DIR/SHA256SUMS" ]]
(cd "$RELEASE_DIR" && shasum -a 256 -c SHA256SUMS)
[[ "$(unzip -Z1 "$RELEASE_DIR/Loquat-macOS.zip" | head -1)" == "Loquat.app/" ]]
if unzip -Z1 "$RELEASE_DIR/Loquat-macOS.zip" | grep -Eq '(^|/)(\._|__MACOSX)'; then
    fail "release contains AppleDouble or resource-fork metadata"
fi

[[ "$(wc -l <"$TOOL_LOG" | tr -d ' ')" == 4 ]] || fail "expected four notarization verification calls"
[[ "$(sed -n '1p' "$TOOL_LOG")" == xcrun\ notarytool\ submit\ *\ --keychain-profile\ loquat-notary\ --wait ]]
[[ "$(sed -n '2p' "$TOOL_LOG")" == "xcrun stapler staple $FAKE_APP" ]]
[[ "$(sed -n '3p' "$TOOL_LOG")" == "xcrun stapler validate $FAKE_APP" ]]
[[ "$(sed -n '4p' "$TOOL_LOG")" == "spctl --assess --type execute $FAKE_APP" ]]

echo "packaging amendment regressions passed"
