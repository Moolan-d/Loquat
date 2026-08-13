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
    [[ "$output" == *"$expected"* ]] || fail "expected failure containing: $expected"
}

PLIST="$TEMP_ROOT/Info.plist"
cp "$ROOT/Config/Info.plist" "$PLIST"
"$ROOT/scripts/materialize-signing-info.sh" adhoc "$PLIST"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :InstantTranslationSigningMode' "$PLIST")" == "adhoc" ]]
assert_fails_with \
    "Does Not Exist" \
    /usr/libexec/PlistBuddy -c 'Print :InstantTranslationKeychainAccessGroup' "$PLIST"

"$ROOT/scripts/materialize-signing-info.sh" \
    signed "$PLIST" EXPECTED123.com.instanttranslation.macos
[[ "$(/usr/libexec/PlistBuddy -c 'Print :InstantTranslationSigningMode' "$PLIST")" == "signed" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :InstantTranslationKeychainAccessGroup' "$PLIST")" \
    == "EXPECTED123.com.instanttranslation.macos" ]]
assert_fails_with \
    "mode must be 'adhoc' or 'signed'" \
    "$ROOT/scripts/materialize-signing-info.sh" unknown "$PLIST"
assert_fails_with \
    "signed mode requires the verified keychain access group" \
    "$ROOT/scripts/materialize-signing-info.sh" signed "$PLIST"

FAKE_APP="$TEMP_ROOT/Loquat.app"
mkdir -p "$FAKE_APP/Contents/MacOS"
printf 'fixture executable\n' >"$FAKE_APP/Contents/MacOS/InstantTranslation"
xattr -w com.instanttranslation.packaging-fixture present \
    "$FAKE_APP/Contents/MacOS/InstantTranslation"
FAKE_PACKAGE_APP="$TEMP_ROOT/package-app-fixture.sh"
cat >"$FAKE_PACKAGE_APP" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
[[ "\${SIGNING_MODE:-}" == "adhoc" ]]
echo "$FAKE_APP"
SCRIPT
chmod +x "$FAKE_PACKAGE_APP"

BUILD_ROOT="$TEMP_ROOT/build"
SIGNING_MODE=adhoc \
INSTANT_TRANSLATION_BUILD_ROOT="$BUILD_ROOT" \
INSTANT_TRANSLATION_PACKAGE_APP_SCRIPT="$FAKE_PACKAGE_APP" \
    "$ROOT/scripts/package-release.sh" >/dev/null

RELEASE_DIR="$BUILD_ROOT/release"
[[ -f "$RELEASE_DIR/Loquat-macOS.zip" ]]
[[ -f "$RELEASE_DIR/SHA256SUMS" ]]
(cd "$RELEASE_DIR" && shasum -a 256 -c SHA256SUMS)
[[ "$(unzip -Z1 "$RELEASE_DIR/Loquat-macOS.zip" | head -1)" \
    == "Loquat.app/" ]]
if unzip -Z1 "$RELEASE_DIR/Loquat-macOS.zip" \
    | grep -Eq '(^|/)(\._|__MACOSX)'; then
    fail "release contains AppleDouble or resource-fork metadata"
fi

MARKER="$TEMP_ROOT/package-app-called"
REFUSING_PACKAGE_APP="$TEMP_ROOT/refusing-package-app.sh"
cat >"$REFUSING_PACKAGE_APP" <<SCRIPT
#!/usr/bin/env bash
touch "$MARKER"
SCRIPT
chmod +x "$REFUSING_PACKAGE_APP"
assert_fails_with \
    "release packaging accepts only SIGNING_MODE=adhoc" \
    env SIGNING_MODE=signed \
        INSTANT_TRANSLATION_BUILD_ROOT="$BUILD_ROOT" \
        INSTANT_TRANSLATION_PACKAGE_APP_SCRIPT="$REFUSING_PACKAGE_APP" \
        "$ROOT/scripts/package-release.sh"
[[ ! -e "$MARKER" ]] || fail "signed release invoked package-app"
assert_fails_with \
    "release packaging accepts only SIGNING_MODE=adhoc" \
    env -u SIGNING_MODE \
        INSTANT_TRANSLATION_BUILD_ROOT="$BUILD_ROOT" \
        INSTANT_TRANSLATION_PACKAGE_APP_SCRIPT="$REFUSING_PACKAGE_APP" \
        "$ROOT/scripts/package-release.sh"
[[ ! -e "$MARKER" ]] || fail "release without SIGNING_MODE invoked package-app"

echo "packaging amendment regressions passed"
