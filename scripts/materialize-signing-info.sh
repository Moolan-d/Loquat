#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
PLIST="${2:-}"
ACCESS_GROUP="${3:-}"

if [[ -z "$PLIST" ]]; then
    echo "usage: $0 adhoc|signed INFO_PLIST [VERIFIED_ACCESS_GROUP]" >&2
    exit 64
fi

case "$MODE" in
    adhoc)
        /usr/libexec/PlistBuddy \
            -c 'Delete :InstantTranslationSigningMode' \
            "$PLIST" >/dev/null 2>&1 || true
        /usr/libexec/PlistBuddy \
            -c 'Delete :InstantTranslationKeychainAccessGroup' \
            "$PLIST" >/dev/null 2>&1 || true
        /usr/libexec/PlistBuddy \
            -c 'Add :InstantTranslationSigningMode string adhoc' \
            "$PLIST"
        ;;
    signed)
        if [[ ! "$ACCESS_GROUP" =~ ^[A-Z0-9]+\.com\.instanttranslation\.macos$ ]]; then
            echo "error: signed mode requires the verified keychain access group" >&2
            exit 64
        fi
        /usr/libexec/PlistBuddy \
            -c 'Delete :InstantTranslationSigningMode' \
            "$PLIST" >/dev/null 2>&1 || true
        /usr/libexec/PlistBuddy \
            -c 'Delete :InstantTranslationKeychainAccessGroup' \
            "$PLIST" >/dev/null 2>&1 || true
        /usr/libexec/PlistBuddy \
            -c 'Add :InstantTranslationSigningMode string signed' \
            "$PLIST"
        /usr/libexec/PlistBuddy \
            -c "Add :InstantTranslationKeychainAccessGroup string $ACCESS_GROUP" \
            "$PLIST"
        ;;
    *)
        echo "error: mode must be 'adhoc' or 'signed'" >&2
        exit 64
        ;;
esac
