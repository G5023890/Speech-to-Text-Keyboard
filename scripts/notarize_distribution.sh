#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Local STT"
TEAM_ID="${TEAM_ID:-9FP39GTDT5}"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME.dmg"
APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Missing $DMG_PATH. Run ./scripts/package_for_distribution.sh first." >&2
  exit 1
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
elif [[ -n "${APPLE_ID:-}" && -n "${APP_SPECIFIC_PASSWORD:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --wait
else
  cat >&2 <<EOF
Provide notarization credentials one of these ways:

1. Existing keychain profile:
   NOTARY_PROFILE=<profile-name> ./scripts/notarize_distribution.sh

2. Apple ID + app-specific password:
   APPLE_ID=<apple-id> APP_SPECIFIC_PASSWORD=<password> ./scripts/notarize_distribution.sh

To create a reusable keychain profile:
   xcrun notarytool store-credentials <profile-name> --apple-id <apple-id> --team-id $TEAM_ID
EOF
  exit 2
fi

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

if [[ -d "$APP_PATH" ]]; then
  xcrun stapler staple "$APP_PATH" || true
  xcrun stapler validate "$APP_PATH" || true
fi

spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

echo "Notarized distribution is ready:"
echo "  $DMG_PATH"
