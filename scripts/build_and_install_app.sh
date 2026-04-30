#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Local STT"
EXEC_NAME="LocalSTT"
BUNDLE_ID="com.grigorym.LocalSTT"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Resources/STT.entitlements"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp ".build/release/$EXEC_NAME" "$APP_PATH/Contents/MacOS/$EXEC_NAME"
cp "$INFO_PLIST" "$APP_PATH/Contents/Info.plist"
cp "$ENTITLEMENTS" "$APP_PATH/Contents/Resources/STT.entitlements"

if [[ -x "$ROOT_DIR/Vendor/whisper.cpp/build/bin/whisper-cli" ]]; then
  cp "$ROOT_DIR/Vendor/whisper.cpp/build/bin/whisper-cli" "$APP_PATH/Contents/Resources/whisper-cli"
elif [[ -x "$ROOT_DIR/Vendor/whisper.cpp/build/bin/main" ]]; then
  cp "$ROOT_DIR/Vendor/whisper.cpp/build/bin/main" "$APP_PATH/Contents/Resources/whisper-cli"
fi

if [[ -x "$APP_PATH/Contents/Resources/whisper-cli" ]]; then
  mkdir -p "$APP_PATH/Contents/Resources/whisper-lib"
  find "$ROOT_DIR/Vendor/whisper.cpp/build" -name '*.dylib' -maxdepth 5 -exec cp -P {} "$APP_PATH/Contents/Resources/whisper-lib/" \;
  install_name_tool -add_rpath "@executable_path/whisper-lib" "$APP_PATH/Contents/Resources/whisper-cli" 2>/dev/null || true
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $EXEC_NAME" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_PATH/Contents/Info.plist"

SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '\"' '/Apple Development/ { print $2; exit }')"
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP_PATH"
else
  codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP_PATH"
fi

rm -rf "$INSTALL_PATH"
cp -R "$APP_PATH" "$INSTALL_PATH"

echo "Installed $INSTALL_PATH"
echo "Bundle id: $BUNDLE_ID"
