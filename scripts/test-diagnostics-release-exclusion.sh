#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="$(mktemp -d -t instant-translation-diagnostics-release-tests)"
trap 'rm -rf "$TEMP_ROOT"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_rejected() {
    local expected="$1"
    local output
    if output="$("$ROOT/scripts/verify-diagnostics-release-exclusion.sh" "$APP" "$ZIP" "$EXTRACTED" 2>&1)"; then
        fail "contaminated release unexpectedly passed"
    fi
    [[ "$output" == *"$expected"* ]] || fail "expected rejection containing: $expected"
}

APP="$TEMP_ROOT/InstantTranslation.app"
EXTRACTED="$TEMP_ROOT/extracted"
ZIP="$TEMP_ROOT/InstantTranslation-macOS.zip"
mkdir -p "$APP/Contents/MacOS" "$EXTRACTED/InstantTranslation.app/Contents/MacOS"
printf 'production executable fixture\n' >"$APP/Contents/MacOS/InstantTranslation"
cp "$APP/Contents/MacOS/InstantTranslation" \
    "$EXTRACTED/InstantTranslation.app/Contents/MacOS/InstantTranslation"
ditto -c -k --keepParent "$APP" "$ZIP"

"$ROOT/scripts/verify-diagnostics-release-exclusion.sh" "$APP" "$ZIP" "$EXTRACTED"

printf 'diagnostics executable fixture\n' >"$APP/Contents/MacOS/InstantTranslationDiagnostics"
assert_rejected "InstantTranslationDiagnostics"
rm "$APP/Contents/MacOS/InstantTranslationDiagnostics"

printf 'scenario fixture: slow-request\n' \
    >"$EXTRACTED/InstantTranslation.app/Contents/diagnostics.txt"
assert_rejected "slow-request"
rm "$EXTRACTED/InstantTranslation.app/Contents/diagnostics.txt"

CONTAMINATED="$TEMP_ROOT/Contaminated.app"
mkdir -p "$CONTAMINATED/Contents"
printf 'DIAGNOSTIC_FIXTURE_GOOGLE_KEY\n' >"$CONTAMINATED/Contents/fixture.txt"
ditto -c -k --keepParent "$CONTAMINATED" "$ZIP"
assert_rejected "DIAGNOSTIC_FIXTURE_GOOGLE_KEY"

echo "diagnostics release exclusion regressions passed"
