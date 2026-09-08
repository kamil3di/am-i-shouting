#!/bin/bash
# Builds "Am I Shouting.app" into dist/.
#
#   ./Scripts/build-app.sh                                  local build, ad-hoc signed
#   UNIVERSAL=1 ./Scripts/build-app.sh                      Intel + Apple Silicon
#   VERSION=0.2.0 ./Scripts/build-app.sh                     stamp a version
#   CODESIGN_IDENTITY="Developer ID Application: …" …        distributable signature
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# The bundle carries the pretty name; the binary inside keeps a plain one so
# it stays comfortable to invoke by hand (see --probe in the README).
APP_NAME="Am I Shouting"
BIN_NAME="AmIShouting"
BUNDLE_ID="dev.kamil3di.AmIShouting"
APP="dist/${APP_NAME}.app"
VERSION="${VERSION:-0.1.0}"
# A build number has to increase monotonically; the commit count does.
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

# ${ARR[@]+"${ARR[@]}"} keeps an empty array from expanding to an empty
# argument under `set -u`.
BUILD_ARGS=(-c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"})

echo "==> swift build ${BUILD_ARGS[*]}"
swift build "${BUILD_ARGS[@]}"
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/${BIN_NAME}"

echo "==> assembling ${APP} (${VERSION}, build ${BUILD_NUMBER})"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "$BIN" "${APP}/Contents/MacOS/${BIN_NAME}"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "${APP}/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "${APP}/Contents/Info.plist"
# Localised microphone prompt: the system dialog follows the user's macOS
# language, while the app's own UI language is chosen in the popover.
for lproj in Resources/*.lproj; do
    [[ -d "$lproj" ]] || continue
    cp -R "$lproj" "${APP}/Contents/Resources/"
done
printf 'APPL????' > "${APP}/Contents/PkgInfo"

# A stable signing identifier is what lets macOS remember the microphone grant
# across rebuilds instead of asking every time.
IDENTITY="${CODESIGN_IDENTITY:--}"
SIGN_ARGS=(
    --force
    --sign "$IDENTITY"
    --identifier "$BUNDLE_ID"
    --options runtime
    --entitlements Resources/AmIShouting.entitlements
)
if [[ "$IDENTITY" == "-" ]]; then
    echo "==> codesign (ad-hoc — fine locally, but Gatekeeper will block a download)"
    # An ad-hoc signature cannot carry a trusted timestamp.
    SIGN_ARGS+=(--timestamp=none)
else
    echo "==> codesign ($IDENTITY)"
    SIGN_ARGS+=(--timestamp)
fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --verbose=1 "$APP"

echo "==> done: ${ROOT}/${APP}"
