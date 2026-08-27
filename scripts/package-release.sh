#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${INSTANT_TRANSLATION_BUILD_ROOT:-$ROOT/build}"
PACKAGE_APP_SCRIPT="${INSTANT_TRANSLATION_PACKAGE_APP_SCRIPT:-$ROOT/scripts/package-app.sh}"

: "${NOTARYTOOL_PROFILE:?error: release packaging requires NOTARYTOOL_PROFILE}"
: "${DEVELOPMENT_TEAM:?error: release packaging requires DEVELOPMENT_TEAM}"
: "${CODE_SIGN_IDENTITY:?error: release packaging requires CODE_SIGN_IDENTITY}"

APP_OUTPUT="$(INSTANT_TRANSLATION_BUILD_ROOT="$BUILD_ROOT" "$PACKAGE_APP_SCRIPT")"
APP="${APP_OUTPUT##*$'\n'}"
if [[ ! -d "$APP" ]]; then
    echo "error: package-app did not produce an application bundle" >&2
    exit 66
fi

RELEASE_DIR="$BUILD_ROOT/release"
NOTARY_DIR="$BUILD_ROOT/notarization"
ZIP_NAME="Loquat-macOS.zip"
NOTARY_ZIP="$NOTARY_DIR/$ZIP_NAME"
mkdir -p "$RELEASE_DIR" "$NOTARY_DIR"
rm -f "$NOTARY_ZIP" "$RELEASE_DIR/$ZIP_NAME" "$RELEASE_DIR/SHA256SUMS"

# 公证提交的是 Developer ID 签名后的临时归档；成功后将票据装订回 .app。
ditto \
    --norsrc \
    --noextattr \
    --noqtn \
    --noacl \
    -c -k --keepParent \
    "$APP" "$NOTARY_ZIP"
xcrun notarytool submit \
    "$NOTARY_ZIP" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute "$APP"

# 最终发布包从已装订票据且通过 Gatekeeper 评估的 .app 生成。
ditto \
    --norsrc \
    --noextattr \
    --noqtn \
    --noacl \
    -c -k --keepParent \
    "$APP" "$RELEASE_DIR/$ZIP_NAME"
(
    cd "$RELEASE_DIR"
    shasum -a 256 "$ZIP_NAME" >SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)

echo "$RELEASE_DIR/$ZIP_NAME"
