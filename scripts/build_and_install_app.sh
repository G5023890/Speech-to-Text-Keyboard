#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$PROJECT_DIR"

APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-Voice Input}"
SCHEME_NAME="${SCHEME_NAME:-Voice Input}"
PROJECT_NAME="${PROJECT_NAME:-Voice Input.xcodeproj}"
BUNDLE_ID="${BUNDLE_ID:-com.grigorym.voiceinput}"
APP_DIR="${APP_DIR:-dist/${APP_DISPLAY_NAME}.app}"
INSTALL_DIR="${INSTALL_DIR:-/Applications/${APP_DISPLAY_NAME}.app}"
LEGACY_INSTALL_DIR="${LEGACY_INSTALL_DIR:-/Applications/SelectedTextOverlay.app}"
ICON_SOURCE="${ICON_SOURCE:-$PROJECT_DIR/assets/AppIcon.icns}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
DEVELOPER_DIR="${DEVELOPER_DIR:-}"
RESOLVED_SIGN_IDENTITY=""
DERIVED_DATA_DIR=""
BUILD_APP_PATH=""

log() {
  echo "[build] $*"
}

resolve_developer_dir() {
  if [[ -n "$DEVELOPER_DIR" ]]; then
    return 0
  fi

  local candidates=(
    "/Applications/Xcode-beta.app/Contents/Developer"
    "/Applications/Xcode.app/Contents/Developer"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -d "$candidate" ]]; then
      DEVELOPER_DIR="$candidate"
      return 0
    fi
  done

  DEVELOPER_DIR="$(xcode-select -p)"
}

resolve_sign_identity() {
  if [[ -n "$SIGN_IDENTITY" ]]; then
    RESOLVED_SIGN_IDENTITY="$SIGN_IDENTITY"
    return 0
  fi

  if [[ -d "$INSTALL_DIR" ]]; then
    local existing existing_info
    existing_info="$(codesign -dv --verbose=4 "$INSTALL_DIR" 2>&1 || true)"
    existing="$(printf '%s\n' "$existing_info" | awk -F= '/^Authority=Apple Development: /{print $2}' | sed -n '1p')"
    if [[ -n "$existing" ]]; then
      RESOLVED_SIGN_IDENTITY="$existing"
      return 0
    fi
  fi

  local identities_output first_available
  identities_output="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  first_available="$(printf '%s\n' "$identities_output" | awk -F '"' '/Apple Development: /{print $2; exit}')"
  if [[ -n "$first_available" ]]; then
    RESOLVED_SIGN_IDENTITY="$first_available"
  fi
}

resolve_developer_dir
export DEVELOPER_DIR
resolve_sign_identity

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required but not installed" >&2
  exit 1
fi

if [[ -z "$RESOLVED_SIGN_IDENTITY" ]]; then
  echo "No Apple Development signing identity found" >&2
  exit 1
fi

log "Using developer dir: $DEVELOPER_DIR"
log "Resolved signing identity: $RESOLVED_SIGN_IDENTITY"

xcodegen generate --spec "$PROJECT_DIR/project.yml" --project "$PROJECT_DIR"

DERIVED_DATA_DIR="$(mktemp -d "${TMPDIR:-/tmp}/voice-input-xcodebuild.XXXXXX")"
cleanup() {
  if [[ -n "$DERIVED_DATA_DIR" && -d "$DERIVED_DATA_DIR" ]]; then
    rm -rf "$DERIVED_DATA_DIR"
  fi
}
trap cleanup EXIT

xcodebuild \
  -project "$PROJECT_DIR/$PROJECT_NAME" \
  -scheme "$SCHEME_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$RESOLVED_SIGN_IDENTITY" \
  DEVELOPMENT_TEAM=8FJN73UDTT \
  clean build

BUILD_APP_PATH="$DERIVED_DATA_DIR/Build/Products/Release/${APP_DISPLAY_NAME}.app"
if [[ ! -d "$BUILD_APP_PATH" ]]; then
  echo "Built app not found: $BUILD_APP_PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$APP_DIR")"
rm -rf "$APP_DIR"
/usr/bin/ditto --norsrc "$BUILD_APP_PATH" "$APP_DIR"

rm -rf "$INSTALL_DIR"
/usr/bin/ditto --norsrc "$BUILD_APP_PATH" "$INSTALL_DIR"
if [[ "$LEGACY_INSTALL_DIR" != "$INSTALL_DIR" ]]; then
  rm -rf "$LEGACY_INSTALL_DIR"
fi

xattr -cr "$INSTALL_DIR" || true
codesign --verify --deep --strict "$INSTALL_DIR"

log "Built: $APP_DIR"
log "Installed: $INSTALL_DIR"
