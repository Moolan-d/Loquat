#!/usr/bin/env bash
set -euo pipefail

APP="${1:-build/Loquat.app}"
if [[ ! -d "$APP" ]]; then
    echo "error: app bundle not found: $APP" >&2
    exit 66
fi

codesign --verify --deep --strict "$APP"
SIGNATURE_DETAILS="$(codesign -dvv "$APP" 2>&1)"
SIGNATURE="$(awk -F= '/^Signature=/{print substr($0, index($0, "=") + 1); exit}' <<<"$SIGNATURE_DETAILS")"
TEAM="$(awk -F= '/^TeamIdentifier=/{print substr($0, index($0, "=") + 1); exit}' <<<"$SIGNATURE_DETAILS")"

if [[ "$SIGNATURE" != "adhoc" ]]; then
    echo "error: expected an ad-hoc signature; found '$SIGNATURE'" >&2
    exit 65
fi
if [[ "$TEAM" != "not set" ]]; then
    echo "error: expected TeamIdentifier=not set; found '$TEAM'" >&2
    exit 65
fi

echo "verified ad-hoc signature"
