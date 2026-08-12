#!/usr/bin/env bash
set -euo pipefail

APP="${1:-build/InstantTranslation.app}"
TEAM="${2:-${DEVELOPMENT_TEAM:-}}"

if [[ -z "$TEAM" ]]; then
    echo "usage: $0 APP_PATH DEVELOPMENT_TEAM" >&2
    exit 64
fi
if [[ ! "$TEAM" =~ ^[A-Z0-9]+$ ]]; then
    echo "error: DEVELOPMENT_TEAM must contain only uppercase letters and digits" >&2
    exit 64
fi
if [[ ! -d "$APP" ]]; then
    echo "error: app bundle not found: $APP" >&2
    exit 66
fi

ENTITLEMENTS="$(mktemp -t instant-translation-entitlements).plist"
trap 'rm -f "$ENTITLEMENTS"' EXIT
codesign --verify --deep --strict "$APP"
codesign -d --entitlements :- --xml "$APP" >"$ENTITLEMENTS" 2>/dev/null

SIGNATURE_DETAILS="$(codesign -dvv "$APP" 2>&1)"
ACTUAL_TEAM="$(
    awk -F= '/^TeamIdentifier=/{print substr($0, index($0, "=") + 1); exit}' \
        <<<"$SIGNATURE_DETAILS"
)"
if [[ "$ACTUAL_TEAM" != "$TEAM" ]]; then
    echo "error: actual signature TeamIdentifier is '$ACTUAL_TEAM'; expected '$TEAM'" >&2
    exit 65
fi

EXPECTED="$TEAM.com.instanttranslation.macos"
APPLICATION_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.application-identifier' "$ENTITLEMENTS")"
TEAM_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.team-identifier' "$ENTITLEMENTS")"
KEYCHAIN_GROUP="$(/usr/libexec/PlistBuddy -c 'Print :keychain-access-groups:0' "$ENTITLEMENTS")"

if [[ "$APPLICATION_IDENTIFIER" != "$EXPECTED" ]]; then
    echo "error: signed application identifier is '$APPLICATION_IDENTIFIER'; expected '$EXPECTED'" >&2
    exit 65
fi
if [[ "$TEAM_IDENTIFIER" != "$TEAM" ]]; then
    echo "error: signed team identifier is '$TEAM_IDENTIFIER'; expected '$TEAM'" >&2
    exit 65
fi
if [[ "$KEYCHAIN_GROUP" != "$EXPECTED" ]]; then
    echo "error: signed default keychain access group is '$KEYCHAIN_GROUP'; expected '$EXPECTED'" >&2
    exit 65
fi

echo "verified signed identifiers: $EXPECTED"
