#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Local STT"
APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"
ZIP_PATH="$ROOT_DIR/dist/$APP_NAME.zip"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME.dmg"

cd "$ROOT_DIR"

./scripts/build_and_install_app.sh

rm -f "$ZIP_PATH" "$DMG_PATH"

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"

SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '\"' '/Developer ID Application/ { print $2; exit }')"
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH" || true

echo "Distribution artifacts:"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
echo
echo "For a clean Mac without Gatekeeper warnings, notarize one artifact, then staple the app or DMG:"
echo "  xcrun notarytool submit \"$ZIP_PATH\" --apple-id <apple-id> --team-id 9FP39GTDT5 --password <app-specific-password> --wait"
echo "  xcrun stapler staple \"$APP_PATH\""
echo "  xcrun stapler validate \"$APP_PATH\""
