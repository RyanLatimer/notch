#!/usr/bin/env bash
# Builds dist/Notch.app and dist/Notch.zip. Runs on macOS (GitHub Actions or locally with
# just the Command Line Tools — Xcode is not required).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"

APP_NAME="Notch"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
ADAPTER_REPO="https://github.com/ungive/mediaremote-adapter.git"
ADAPTER_REF="29718252613a5b0e210bdc64de0bd944ab379706"

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
VENDOR="$ROOT/.build/vendor"
ADAPTER="$VENDOR/mediaremote-adapter"

rm -rf "$DIST"
mkdir -p "$DIST" "$VENDOR"

echo "==> Compiling $APP_NAME (arm64 + x86_64)"
swift build -c release --arch arm64
swift build -c release --arch x86_64
ARM_BIN="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"
X86_BIN="$(swift build -c release --arch x86_64 --show-bin-path)/$APP_NAME"

echo "==> Building MediaRemote adapter @ ${ADAPTER_REF:0:10}"
if [ ! -d "$ADAPTER/.git" ]; then
  git clone --quiet "$ADAPTER_REPO" "$ADAPTER"
fi
git -C "$ADAPTER" fetch --quiet origin "$ADAPTER_REF" || true
git -C "$ADAPTER" checkout --quiet "$ADAPTER_REF"
cmake -S "$ADAPTER" -B "$ADAPTER/build" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$ADAPTER/build" --config Release >/dev/null

echo "==> Assembling bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
lipo -create -output "$APP/Contents/MacOS/$APP_NAME" "$ARM_BIN" "$X86_BIN"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"

ditto "$ADAPTER/build/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
cp "$ADAPTER/build/MediaRemoteAdapterTestClient" "$APP/Contents/MacOS/MediaRemoteAdapterTestClient"
cp "$ADAPTER/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/mediaremote-adapter.pl"
cp "$ADAPTER/LICENSE" "$APP/Contents/Resources/MediaRemoteAdapter-LICENSE.txt"

echo "==> Rendering icon"
ICONSET="$VENDOR/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
swift "$ROOT/scripts/make-icon.swift" "$VENDOR/icon_1024.png" >/dev/null
for pt in 16 32 128 256 512; do
  sips -z $pt $pt "$VENDOR/icon_1024.png" --out "$ICONSET/icon_${pt}x${pt}.png" >/dev/null
  px=$((pt * 2))
  sips -z $px $px "$VENDOR/icon_1024.png" --out "$ICONSET/icon_${pt}x${pt}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing (ad-hoc)"
codesign --force --sign - "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign --force --sign - "$APP/Contents/MacOS/MediaRemoteAdapterTestClient"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Packaging"
ditto -c -k --keepParent "$APP" "$DIST/$APP_NAME.zip"
echo "Built $DIST/$APP_NAME.zip ($VERSION build $BUILD_NUMBER)"
