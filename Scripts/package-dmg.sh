#!/bin/bash
# Packages the built app into a distributable DMG in dist/.
#
# Signs the DMG when CODESIGN_IDENTITY is a real identity, and notarises it
# when NOTARY_APPLE_ID / NOTARY_APP_PASSWORD / NOTARY_TEAM_ID are all present.
# Without those the DMG is still produced — it just triggers Gatekeeper on the
# machine that downloads it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Am I Shouting"
BIN_NAME="AmIShouting"
VERSION="${VERSION:-0.1.0}"
APP="dist/${APP_NAME}.app"
DMG_NAME="${BIN_NAME}-${VERSION}.dmg"
DMG="dist/${DMG_NAME}"

if [[ ! -d "$APP" ]]; then
    echo "no app at ${APP} — run ./Scripts/build-app.sh first" >&2
    exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

echo "==> staging"
cp -R "$APP" "$STAGING/"
# The customary drag-to-install target.
ln -s /Applications "$STAGING/Applications"

echo "==> creating ${DMG}"
rm -f "$DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov -format UDZO -quiet \
    "$DMG"

IDENTITY="${CODESIGN_IDENTITY:--}"
if [[ "$IDENTITY" != "-" ]]; then
    echo "==> signing the disk image"
    codesign --force --sign "$IDENTITY" --timestamp "$DMG"
fi

if [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_APP_PASSWORD:-}" && -n "${NOTARY_TEAM_ID:-}" ]]; then
    echo "==> notarising (this waits for Apple)"
    xcrun notarytool submit "$DMG" \
        --apple-id "$NOTARY_APPLE_ID" \
        --password "$NOTARY_APP_PASSWORD" \
        --team-id "$NOTARY_TEAM_ID" \
        --wait
    # Stapling lets the DMG verify offline, on a machine that has never seen it.
    xcrun stapler staple "$DMG"
    spctl -a -t open --context context:primary-signature -v "$DMG"
else
    echo "==> NOT notarised: no NOTARY_* credentials."
    echo "    The download will be blocked on first open until the user allows"
    echo "    it in System Settings → Privacy & Security."
fi

# Checksum with a bare filename, so it reads the same wherever it is verified.
( cd dist && shasum -a 256 "$DMG_NAME" > "${DMG_NAME}.sha256" )

echo "==> done: ${ROOT}/${DMG}"
cat "${DMG}.sha256"
