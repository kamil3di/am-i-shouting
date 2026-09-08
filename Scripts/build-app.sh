#!/bin/bash
# Builds ShoutMeter.app into dist/.
# UNIVERSAL=1 ./Scripts/build-app.sh  -> Intel + Apple Silicon binary
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="ShoutMeter"
BUNDLE_ID="dev.kamil3di.ShoutMeter"
APP="dist/${APP_NAME}.app"

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

# ${ARR[@]+"${ARR[@]}"} keeps an empty array from expanding to an empty
# argument under `set -u`.
BUILD_ARGS=(-c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"})

echo "==> swift build ${BUILD_ARGS[*]}"
swift build "${BUILD_ARGS[@]}"
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/${APP_NAME}"

echo "==> assembling ${APP}"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "$BIN" "${APP}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
printf 'APPL????' > "${APP}/Contents/PkgInfo"

# Ad-hoc signature with a stable identifier, so macOS remembers the microphone
# grant across rebuilds instead of asking every time.
echo "==> codesign (ad-hoc)"
codesign --force --sign - --identifier "$BUNDLE_ID" --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP"

echo "==> done: ${ROOT}/${APP}"
