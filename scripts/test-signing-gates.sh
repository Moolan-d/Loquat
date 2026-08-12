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

make_entitlements() {
    local team="$1"
    local destination="$2"
    cat >"$destination" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>com.apple.application-identifier</key>
  <string>$team.com.instanttranslation.macos</string>
  <key>com.apple.developer.team-identifier</key>
  <string>$team</string>
  <key>keychain-access-groups</key>
  <array><string>$team.com.instanttranslation.macos</string></array>
</dict></plist>
PLIST
}

APP="$TEMP_ROOT/InstantTranslation.app"
mkdir -p "$APP"
ENTITLEMENTS="$TEMP_ROOT/entitlements.plist"
make_entitlements EXPECTED123 "$ENTITLEMENTS"

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
    echo "TeamIdentifier=${FAKE_TEAM:-WRONGTEAM}" >&2
    exit 0
fi
exit 2
SCRIPT
chmod +x "$FAKE_BIN/codesign"

assert_fails_with \
    "actual signature TeamIdentifier is 'WRONGTEAM'; expected 'EXPECTED123'" \
    env PATH="$FAKE_BIN:$PATH" FAKE_ENTITLEMENTS="$ENTITLEMENTS" \
    "$ROOT/scripts/verify-signed-app.sh" "$APP" EXPECTED123

env PATH="$FAKE_BIN:$PATH" \
    FAKE_ENTITLEMENTS="$ENTITLEMENTS" \
    FAKE_TEAM=EXPECTED123 \
    "$ROOT/scripts/verify-signed-app.sh" "$APP" EXPECTED123 >/dev/null

PROFILE="$TEMP_ROOT/profile.plist"
cat >"$PROFILE" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>Entitlements</key>
  <dict>
    <key>keychain-access-groups</key>
    <array>
      <string>EXPECTED123.com.instanttranslation.macos.other</string>
    </array>
  </dict>
</dict></plist>
PLIST

assert_fails_with \
    "profile does not grant exact keychain access group 'EXPECTED123.com.instanttranslation.macos'" \
    "$ROOT/scripts/verify-profile-keychain-group.sh" \
    "$PROFILE" EXPECTED123.com.instanttranslation.macos

/usr/libexec/PlistBuddy \
    -c 'Set :Entitlements:keychain-access-groups:0 EXPECTED123.com.instanttranslation.macos' \
    "$PROFILE"
"$ROOT/scripts/verify-profile-keychain-group.sh" \
    "$PROFILE" EXPECTED123.com.instanttranslation.macos

echo "signing gate regressions passed"
