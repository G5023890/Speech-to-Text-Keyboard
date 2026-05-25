#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SNAPSHOT_DIR="${PROJECT_DIR}/.checkpoints/Stage-1.4"

if [[ ! -d "${SNAPSHOT_DIR}" ]]; then
  echo "Stage-1.4 snapshot not found: ${SNAPSHOT_DIR}" >&2
  exit 1
fi

rsync -a --delete \
  --exclude '.checkpoints' \
  "${SNAPSHOT_DIR}/" "${PROJECT_DIR}/"

echo "Restored project to Stage-1.4 snapshot."
