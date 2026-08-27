#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEAM="${1:-}"
OUTPUT="${2:-}"

if [[ -z "$TEAM" || -z "$OUTPUT" ]]; then
    echo "usage: $0 DEVELOPMENT_TEAM OUTPUT_PLIST" >&2
    exit 64
fi
if [[ ! "$TEAM" =~ ^[A-Z0-9]+$ ]]; then
    echo "error: DEVELOPMENT_TEAM must contain only uppercase letters and digits" >&2
    exit 64
fi

IDENTIFIER="$TEAM.com.instanttranslation.macos"
mkdir -p "$(dirname "$OUTPUT")"
cp "$ROOT/Config/InstantTranslation.entitlements.template.plist" "$OUTPUT"
/usr/libexec/PlistBuddy -c "Set :com.apple.application-identifier $IDENTIFIER" "$OUTPUT"
/usr/libexec/PlistBuddy -c "Set :com.apple.developer.team-identifier $TEAM" "$OUTPUT"
plutil -lint "$OUTPUT" >/dev/null
