#!/bin/bash
# Builds "Am I Shouting.app" into dist/.
# UNIVERSAL=1 ./Scripts/build-app.sh  -> Intel + Apple Silicon binary
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# The bundle carries the pretty name; the binary inside keeps a plain one so
# it stays comfortable to invoke by hand (see --probe in the README).
APP_NAME="Am I Shouting"
BIN_NAME="AmIShouting"
BUNDLE_ID="dev.kamil3di.AmIShouting"
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
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/${BIN_NAME}"

echo "==> assembling ${APP}"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "$BIN" "${APP}/Contents/MacOS/${BIN_NAME}"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
# Localised microphone prompt: the system dialog follows the user's macOS
# language, while the app's own UI language is chosen in the popover.
for lproj in Resources/*.lproj; do
    [[ -d "$lproj" ]] || continue
    cp -R "$lproj" "${APP}/Contents/Resources/"
done
printf 'APPL????' > "${APP}/Contents/PkgInfo"

# Ad-hoc signature with a stable identifier, so macOS remembers the microphone
# grant across rebuilds instead of asking every time.
echo "==> codesign (ad-hoc)"
codesign --force --sign - --identifier "$BUNDLE_ID" --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP"

echo "==> done: ${ROOT}/${APP}"
