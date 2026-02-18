#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/Users/grigorymordokhovich/Documents/Develop/Voice input"
SNAPSHOT_DIR="${PROJECT_DIR}/.checkpoints/Stage-1.4"

if [[ ! -d "${SNAPSHOT_DIR}" ]]; then
  echo "Stage-1.4 snapshot not found: ${SNAPSHOT_DIR}" >&2
  exit 1
fi

rsync -a --delete \
  --exclude '.checkpoints' \
  "${SNAPSHOT_DIR}/" "${PROJECT_DIR}/"

echo "Restored project to Stage-1.4 snapshot."
