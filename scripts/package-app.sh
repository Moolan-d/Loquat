#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${SIGNING_MODE:-adhoc}"
BUILD_ROOT="${INSTANT_TRANSLATION_BUILD_ROOT:-$ROOT/build}"
PROFILE_PLIST=""
case "$MODE" in
    adhoc)
        ;;
    signed)
        : "${DEVELOPMENT_TEAM:?error: signed mode requires DEVELOPMENT_TEAM}"
        : "${CODE_SIGN_IDENTITY:?error: signed mode requires CODE_SIGN_IDENTITY}"
        : "${PROVISIONING_PROFILE:?error: signed mode requires PROVISIONING_PROFILE}"
        if [[ ! "$DEVELOPMENT_TEAM" =~ ^[A-Z0-9]+$ ]]; then
            echo "error: DEVELOPMENT_TEAM must contain only uppercase letters and digits" >&2
            exit 64
        fi
        if [[ ! -f "$PROVISIONING_PROFILE" ]]; then
            echo "error: provisioning profile not found: $PROVISIONING_PROFILE" >&2
            exit 66
        fi
        PROFILE_PLIST="$(mktemp -t instant-translation-profile).plist"
        trap 'rm -f "$PROFILE_PLIST"' EXIT
        if ! security cms -D -i "$PROVISIONING_PROFILE" -o "$PROFILE_PLIST"; then
            echo "error: PROVISIONING_PROFILE is not a decodable provisioning profile" >&2
            exit 65
        fi

        EXPECTED="$DEVELOPMENT_TEAM.com.instanttranslation.macos"
        PROFILE_TEAM="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$PROFILE_PLIST" 2>/dev/null || true)"
        PROFILE_APPLICATION_IDENTIFIER="$(
            /usr/libexec/PlistBuddy \
                -c 'Print :Entitlements:com.apple.application-identifier' \
                "$PROFILE_PLIST" 2>/dev/null \
            || /usr/libexec/PlistBuddy \
                -c 'Print :Entitlements:application-identifier' \
                "$PROFILE_PLIST" 2>/dev/null \
            || true
        )"

        if [[ "$PROFILE_TEAM" != "$DEVELOPMENT_TEAM" ]]; then
            echo "error: provisioning profile team '$PROFILE_TEAM' does not match DEVELOPMENT_TEAM '$DEVELOPMENT_TEAM'" >&2
            exit 65
        fi
        if [[ "$PROFILE_APPLICATION_IDENTIFIER" != "$EXPECTED" ]]; then
            echo "error: provisioning profile application identifier '$PROFILE_APPLICATION_IDENTIFIER' does not match '$EXPECTED'" >&2
            exit 65
        fi
        "$ROOT/scripts/verify-profile-keychain-group.sh" "$PROFILE_PLIST" "$EXPECTED"
        ;;
    *)
        echo "error: SIGNING_MODE must be 'adhoc' or 'signed'" >&2
        exit 64
        ;;
esac

swift build --disable-sandbox -c release
BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"
APP="$BUILD_ROOT/InstantTranslation.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/InstantTranslation" "$APP/Contents/MacOS/InstantTranslation"
cp "$ROOT/Config/Info.plist" "$APP/Contents/Info.plist"
find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

if [[ "$MODE" == "adhoc" ]]; then
    "$ROOT/scripts/materialize-signing-info.sh" adhoc "$APP/Contents/Info.plist"
    # ad-hoc 包使用文件型 Keychain，用户仍需通过“隐私与安全性”明确授权首次启动。
    echo "warning: ad-hoc mode; users may need to authorize the app with Open Anyway" >&2
    codesign --force --deep --sign - "$APP"
else
    # 只有 profile 的 TeamIdentifier、application identifier 与组校验全部通过后才写入 signed 元数据。
    "$ROOT/scripts/materialize-signing-info.sh" signed "$APP/Contents/Info.plist" "$EXPECTED"
    ENTITLEMENTS="$BUILD_ROOT/InstantTranslation.entitlements.plist"
    "$ROOT/scripts/materialize-entitlements.sh" "$DEVELOPMENT_TEAM" "$ENTITLEMENTS"
    cp "$PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
    codesign \
        --force \
        --deep \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$CODE_SIGN_IDENTITY" \
        "$APP"
    "$ROOT/scripts/verify-signed-app.sh" "$APP" "$DEVELOPMENT_TEAM"
fi

echo "$APP"
