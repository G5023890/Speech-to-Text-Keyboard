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
BUNDLED_MODEL_SOURCE="${BUNDLED_MODEL_SOURCE:-$HOME/Library/Application Support/Voice Input/Models/ggml-small-q8_0.bin}"
WHISPER_LIB_SOURCE="${WHISPER_LIB_SOURCE:-/opt/homebrew/opt/whisper-cpp/lib/libwhisper.1.dylib}"
GGML_LIB_SOURCE="${GGML_LIB_SOURCE:-/opt/homebrew/opt/ggml/lib/libggml.0.dylib}"
GGML_BASE_LIB_SOURCE="${GGML_BASE_LIB_SOURCE:-/opt/homebrew/opt/ggml/lib/libggml-base.0.dylib}"
WHISPER_CLI_SOURCE="${WHISPER_CLI_SOURCE:-/opt/homebrew/opt/whisper-cpp/bin/whisper-cli}"
RESOLVED_SIGN_IDENTITY=""
DERIVED_DATA_DIR=""
BUILD_APP_PATH=""

log() {
  echo "[build] $*"
}

require_file() {
  local path="$1"
  local label="$2"
  if [[ ! -f "$path" ]]; then
    echo "$label not found: $path" >&2
    exit 1
  fi
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

require_file "$WHISPER_LIB_SOURCE" "Bundled whisper library"
require_file "$GGML_LIB_SOURCE" "Bundled ggml library"
require_file "$GGML_BASE_LIB_SOURCE" "Bundled ggml-base library"
require_file "$WHISPER_CLI_SOURCE" "Bundled whisper-cli binary"
require_file "$BUNDLED_MODEL_SOURCE" "Bundled baseline model"

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

bundle_runtime_dependencies() {
  local app_path="$1"
  local frameworks_dir="$app_path/Contents/Frameworks"
  local resources_bin_dir="$app_path/Contents/Resources/bin"
  local resources_models_dir="$app_path/Contents/Resources/Models"
  local app_binary="$app_path/Contents/MacOS/VoiceInputApp"
  local bundled_cli_path="$resources_bin_dir/whisper-cli"
  local bundled_model_name
  bundled_model_name="$(basename "$BUNDLED_MODEL_SOURCE")"

  mkdir -p "$frameworks_dir"
  mkdir -p "$resources_bin_dir"
  mkdir -p "$resources_models_dir"

  cp -fL "$WHISPER_LIB_SOURCE" "$frameworks_dir/libwhisper.1.dylib"
  cp -fL "$GGML_LIB_SOURCE" "$frameworks_dir/libggml.0.dylib"
  cp -fL "$GGML_BASE_LIB_SOURCE" "$frameworks_dir/libggml-base.0.dylib"
  cp -fL "$WHISPER_CLI_SOURCE" "$bundled_cli_path"
  cp -fL "$BUNDLED_MODEL_SOURCE" "$resources_models_dir/$bundled_model_name"

  chmod u+w "$frameworks_dir/libwhisper.1.dylib" "$frameworks_dir/libggml.0.dylib" "$frameworks_dir/libggml-base.0.dylib"
  chmod u+w "$bundled_cli_path"
  chmod +x "$bundled_cli_path"
  chmod u+w "$resources_models_dir/$bundled_model_name"
  xattr -cr "$frameworks_dir" "$resources_bin_dir" "$resources_models_dir" || true

  install_name_tool -id "@rpath/libwhisper.1.dylib" "$frameworks_dir/libwhisper.1.dylib"
  install_name_tool -id "@rpath/libggml.0.dylib" "$frameworks_dir/libggml.0.dylib"
  install_name_tool -id "@rpath/libggml-base.0.dylib" "$frameworks_dir/libggml-base.0.dylib"

  install_name_tool -change "$WHISPER_LIB_SOURCE" "@executable_path/../Frameworks/libwhisper.1.dylib" "$app_binary"
  install_name_tool -change "$GGML_LIB_SOURCE" "@loader_path/libggml.0.dylib" "$frameworks_dir/libwhisper.1.dylib"
  install_name_tool -change "$GGML_BASE_LIB_SOURCE" "@loader_path/libggml-base.0.dylib" "$frameworks_dir/libwhisper.1.dylib"
  install_name_tool -change "@rpath/libggml-base.0.dylib" "@loader_path/libggml-base.0.dylib" "$frameworks_dir/libggml.0.dylib"
  install_name_tool -change "@rpath/libwhisper.1.dylib" "@executable_path/../../Frameworks/libwhisper.1.dylib" "$bundled_cli_path"
  install_name_tool -change "$GGML_LIB_SOURCE" "@executable_path/../../Frameworks/libggml.0.dylib" "$bundled_cli_path"
  install_name_tool -change "$GGML_BASE_LIB_SOURCE" "@executable_path/../../Frameworks/libggml-base.0.dylib" "$bundled_cli_path"
}

sign_app_bundle() {
  local app_path="$1"
  local frameworks_dir="$app_path/Contents/Frameworks"
  local bundled_cli_path="$app_path/Contents/Resources/bin/whisper-cli"
  chmod -R u+w "$app_path"
  xattr -cr "$app_path" || true
  if [[ -d "$frameworks_dir" ]]; then
    find "$frameworks_dir" -type f -name '*.dylib' -print0 | while IFS= read -r -d '' dylib_path; do
      codesign --force --sign "$RESOLVED_SIGN_IDENTITY" "$dylib_path"
    done
  fi
  if [[ -f "$bundled_cli_path" ]]; then
    codesign --force --sign "$RESOLVED_SIGN_IDENTITY" "$bundled_cli_path"
  fi
  codesign --force --sign "$RESOLVED_SIGN_IDENTITY" --deep --preserve-metadata=identifier,entitlements,requirements,flags "$app_path"
  codesign --verify --deep --strict "$app_path"
}

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

bundle_runtime_dependencies "$BUILD_APP_PATH"

mkdir -p "$(dirname "$APP_DIR")"
rm -rf "$APP_DIR"
/usr/bin/ditto --norsrc "$BUILD_APP_PATH" "$APP_DIR"

pkill -f "$INSTALL_DIR/Contents/MacOS/VoiceInputApp" || true
rm -rf "$INSTALL_DIR"
/usr/bin/ditto --norsrc "$BUILD_APP_PATH" "$INSTALL_DIR"
if [[ "$LEGACY_INSTALL_DIR" != "$INSTALL_DIR" ]]; then
  rm -rf "$LEGACY_INSTALL_DIR"
fi

sign_app_bundle "$INSTALL_DIR"

log "Built: $APP_DIR"
log "Installed: $INSTALL_DIR"
