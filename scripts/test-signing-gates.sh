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

BUILD_ROOT="$TEMP_ROOT/build"
FAKE_RELEASE_BIN="$TEMP_ROOT/bin/release"
FAKE_BIN="$TEMP_ROOT/bin"
mkdir -p "$FAKE_BIN" "$FAKE_RELEASE_BIN"

cat >"$FAKE_BIN/swift" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"--show-bin-path"* ]]; then
    echo "$FAKE_RELEASE_BIN"
fi
SCRIPT

cat >"$FAKE_BIN/codesign" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"--verify"* ]]; then
    exit 0
fi
if [[ "$*" == *"-dvv"* ]]; then
    echo "Signature=${FAKE_SIGNATURE:-adhoc}" >&2
    echo "TeamIdentifier=${FAKE_TEAM:-not set}" >&2
    exit 0
fi
echo "$*" >>"$CODESIGN_LOG"
SCRIPT

chmod +x "$FAKE_BIN/swift" "$FAKE_BIN/codesign"
printf 'fixture executable\n' >"$FAKE_RELEASE_BIN/InstantTranslation"
chmod +x "$FAKE_RELEASE_BIN/InstantTranslation"

CODESIGN_LOG="$TEMP_ROOT/codesign.log"
env \
    PATH="$FAKE_BIN:$PATH" \
    FAKE_RELEASE_BIN="$FAKE_RELEASE_BIN" \
    CODESIGN_LOG="$CODESIGN_LOG" \
    INSTANT_TRANSLATION_BUILD_ROOT="$BUILD_ROOT" \
    "$ROOT/scripts/package-app.sh" >/dev/null

[[ -d "$BUILD_ROOT/Loquat.app" ]] || fail "package-app did not build an app bundle"
[[ "$(cat "$CODESIGN_LOG")" == "--force --deep --sign - $BUILD_ROOT/Loquat.app" ]] \
    || fail "package-app did not apply a single ad-hoc signature"

APP="$BUILD_ROOT/Loquat.app"
env PATH="$FAKE_BIN:$PATH" CODESIGN_LOG="$CODESIGN_LOG" \
    "$ROOT/scripts/verify-adhoc-app.sh" "$APP" >/dev/null

assert_fails_with \
    "expected an ad-hoc signature" \
    env PATH="$FAKE_BIN:$PATH" CODESIGN_LOG="$CODESIGN_LOG" \
        FAKE_SIGNATURE="Developer ID Application: Example" \
        "$ROOT/scripts/verify-adhoc-app.sh" "$APP"

assert_fails_with \
    "expected TeamIdentifier=not set" \
    env PATH="$FAKE_BIN:$PATH" CODESIGN_LOG="$CODESIGN_LOG" \
        FAKE_TEAM="TEAMID123" \
        "$ROOT/scripts/verify-adhoc-app.sh" "$APP"

MISSING_APP_LOG="$TEMP_ROOT/missing-app-codesign.log"
assert_fails_with \
    "app bundle not found" \
    env PATH="$FAKE_BIN:$PATH" CODESIGN_LOG="$MISSING_APP_LOG" \
        "$ROOT/scripts/verify-adhoc-app.sh" "$TEMP_ROOT/does-not-exist.app"
[[ ! -e "$MISSING_APP_LOG" ]] || fail "missing app still invoked codesign"

echo "signing gate regressions passed"
