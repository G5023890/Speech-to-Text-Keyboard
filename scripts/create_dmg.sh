#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="${APP_NAME:-Voice Input}"
APP_SOURCE="${APP_SOURCE:-${PROJECT_DIR}/dist/${APP_NAME}.app}"
OUTPUT_DIR="${OUTPUT_DIR:-${PROJECT_DIR}/dist}"
OUTPUT_DMG="${OUTPUT_DMG:-${OUTPUT_DIR}/${APP_NAME}.dmg}"

if [[ ! -d "$APP_SOURCE" ]]; then
  APP_SOURCE="/Applications/${APP_NAME}.app"
fi

if [[ ! -d "$APP_SOURCE" ]]; then
  echo "App bundle not found: $APP_SOURCE" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

VERSION="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_SOURCE}/Contents/Info.plist" 2>/dev/null || true
)"
if [[ -z "$VERSION" ]]; then
  VERSION="latest"
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/voice-input-dmg.XXXXXX")"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cp -R "$APP_SOURCE" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$OUTPUT_DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$OUTPUT_DMG" >/dev/null

echo "Created: $OUTPUT_DMG"
echo "Version: $VERSION"
