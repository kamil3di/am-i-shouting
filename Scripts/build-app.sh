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

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    # Build each slice separately and lipo them together. The obvious
    # `swift build --arch arm64 --arch x86_64` routes through the Xcode build
    # backend instead of SwiftPM's own, which fails with "unexpected duplicate
    # tasks" on some toolchains — including the GitHub macOS runners.
    echo "==> swift build -c release (universal)"
    SLICES=()
    for TRIPLE in arm64-apple-macosx x86_64-apple-macosx; do
        swift build -c release --triple "$TRIPLE"
        SLICES+=("$(swift build -c release --triple "$TRIPLE" --show-bin-path)/${BIN_NAME}")
    done
    mkdir -p .build/universal
    BIN=".build/universal/${BIN_NAME}"
    lipo -create -output "$BIN" "${SLICES[@]}"
    echo "==> $(lipo -archs "$BIN")"
else
    echo "==> swift build -c release"
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/${BIN_NAME}"
fi

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
