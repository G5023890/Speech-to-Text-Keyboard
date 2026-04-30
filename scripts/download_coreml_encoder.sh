#!/usr/bin/env bash
set -euo pipefail

MODEL="${1:-small}"
MODELS_DIR="${2:-$HOME/Library/Application Support/LocalSTT/Models}"
ZIP_NAME="ggml-${MODEL}-encoder.mlmodelc.zip"
ENCODER_DIR="$MODELS_DIR/ggml-${MODEL}-encoder.mlmodelc"
URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$ZIP_NAME"

mkdir -p "$MODELS_DIR"

if [[ -d "$ENCODER_DIR" ]]; then
  echo "Core ML encoder already installed: $ENCODER_DIR"
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading $URL"
curl -L --fail --progress-bar "$URL" -o "$TMP_DIR/$ZIP_NAME"

echo "Unpacking Core ML encoder"
unzip -q "$TMP_DIR/$ZIP_NAME" -d "$TMP_DIR/unpacked"

FOUND="$(find "$TMP_DIR/unpacked" -maxdepth 2 -type d -name "ggml-${MODEL}-encoder.mlmodelc" | head -1)"
if [[ -z "$FOUND" ]]; then
  echo "Could not find ggml-${MODEL}-encoder.mlmodelc in downloaded zip" >&2
  exit 1
fi

rm -rf "$ENCODER_DIR"
mv "$FOUND" "$ENCODER_DIR"

echo "Installed Core ML encoder: $ENCODER_DIR"
