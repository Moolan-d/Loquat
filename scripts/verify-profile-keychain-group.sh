#!/usr/bin/env bash
set -euo pipefail

PROFILE_PLIST="${1:-}"
EXPECTED_GROUP="${2:-}"

if [[ -z "$PROFILE_PLIST" || -z "$EXPECTED_GROUP" ]]; then
    echo "usage: $0 DECODED_PROFILE_PLIST EXPECTED_KEYCHAIN_GROUP" >&2
    exit 64
fi
if [[ ! -f "$PROFILE_PLIST" ]]; then
    echo "error: decoded profile plist not found: $PROFILE_PLIST" >&2
    exit 66
fi

INDEX=0
while GROUP="$(
    /usr/libexec/PlistBuddy \
        -c "Print :Entitlements:keychain-access-groups:$INDEX" \
        "$PROFILE_PLIST" 2>/dev/null
)"; do
    if [[ "$GROUP" == "$EXPECTED_GROUP" ]]; then
        exit 0
    fi
    INDEX=$((INDEX + 1))
done

echo "error: profile does not grant exact keychain access group '$EXPECTED_GROUP'" >&2
exit 65
