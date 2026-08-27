#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d -t instant-translation-signing-tests)"
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

assert_fails_with \
    "DEVELOPMENT_TEAM" \
    env -u DEVELOPMENT_TEAM -u CODE_SIGN_IDENTITY "$ROOT/scripts/package-app.sh"
assert_fails_with \
    "CODE_SIGN_IDENTITY" \
    env -u CODE_SIGN_IDENTITY DEVELOPMENT_TEAM=EXPECTED123 "$ROOT/scripts/package-app.sh"

GENERATED_ENTITLEMENTS="$TEMP_ROOT/generated-entitlements.plist"
"$ROOT/scripts/materialize-entitlements.sh" EXPECTED123 "$GENERATED_ENTITLEMENTS"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "$GENERATED_ENTITLEMENTS")" \
    == "EXPECTED123.com.instanttranslation.macos" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.team-identifier' "$GENERATED_ENTITLEMENTS")" \
    == "EXPECTED123" ]]
assert_fails_with \
    "Does Not Exist" \
    /usr/libexec/PlistBuddy -c 'Print :keychain-access-groups' "$GENERATED_ENTITLEMENTS"

APP="$TEMP_ROOT/Loquat.app"
mkdir -p "$APP"

FAKE_BIN="$TEMP_ROOT/bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/codesign" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$*" == *"--verify"* ]]; then
    exit 0
fi
if [[ "$*" == *"--entitlements"* ]]; then
    cat "$FAKE_ENTITLEMENTS"
    exit 0
fi
if [[ "$*" == *"-dvv"* ]]; then
    echo "Authority=${FAKE_AUTHORITY:-Developer ID Application: Example}" >&2
    echo "TeamIdentifier=${FAKE_TEAM:-WRONGTEAM}" >&2
    exit 0
fi
exit 2
SCRIPT
chmod +x "$FAKE_BIN/codesign"

assert_fails_with \
    "actual signature TeamIdentifier is 'WRONGTEAM'; expected 'EXPECTED123'" \
    env PATH="$FAKE_BIN:$PATH" FAKE_ENTITLEMENTS="$GENERATED_ENTITLEMENTS" \
    "$ROOT/scripts/verify-signed-app.sh" "$APP" EXPECTED123

env PATH="$FAKE_BIN:$PATH" \
    FAKE_ENTITLEMENTS="$GENERATED_ENTITLEMENTS" \
    FAKE_TEAM=EXPECTED123 \
    "$ROOT/scripts/verify-signed-app.sh" "$APP" EXPECTED123 >/dev/null

assert_fails_with \
    "expected Developer ID Application" \
    env PATH="$FAKE_BIN:$PATH" \
        FAKE_ENTITLEMENTS="$GENERATED_ENTITLEMENTS" \
        FAKE_TEAM=EXPECTED123 \
        FAKE_AUTHORITY="Apple Development: Example" \
        "$ROOT/scripts/verify-signed-app.sh" "$APP" EXPECTED123

ENTITLEMENTS_WITH_SHARING="$TEMP_ROOT/entitlements-with-sharing.plist"
cp "$GENERATED_ENTITLEMENTS" "$ENTITLEMENTS_WITH_SHARING"
/usr/libexec/PlistBuddy \
    -c 'Add :keychain-access-groups array' \
    -c 'Add :keychain-access-groups:0 string EXPECTED123.com.instanttranslation.macos' \
    "$ENTITLEMENTS_WITH_SHARING"
assert_fails_with \
    "signed app must not declare keychain-access-groups" \
    env PATH="$FAKE_BIN:$PATH" \
        FAKE_ENTITLEMENTS="$ENTITLEMENTS_WITH_SHARING" \
        FAKE_TEAM=EXPECTED123 \
        "$ROOT/scripts/verify-signed-app.sh" "$APP" EXPECTED123

echo "signing gate regressions passed"
