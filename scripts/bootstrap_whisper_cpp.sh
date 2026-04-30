#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT_DIR/Vendor"
WHISPER_DIR="$VENDOR_DIR/whisper.cpp"

mkdir -p "$VENDOR_DIR"

if [[ ! -d "$WHISPER_DIR/.git" ]]; then
  git clone https://github.com/ggml-org/whisper.cpp.git "$WHISPER_DIR"
else
  git -C "$WHISPER_DIR" pull --ff-only
fi

cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build" \
  -DGGML_METAL=ON \
  -DGGML_COREML=OFF \
  -DWHISPER_COREML=OFF \
  -DCMAKE_BUILD_TYPE=Release

cmake --build "$WHISPER_DIR/build" --config Release -j"$(sysctl -n hw.ncpu)"

echo "whisper.cpp built at $WHISPER_DIR/build"
