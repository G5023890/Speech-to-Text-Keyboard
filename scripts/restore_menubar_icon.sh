#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC="${PROJECT_DIR}/Resources/backups/taskbar_Mic.original.png"
DST="${PROJECT_DIR}/Resources/taskbar_Mic.png"

if [[ ! -f "${SRC}" ]]; then
  echo "Backup icon not found: ${SRC}" >&2
  exit 1
fi

cp -f "${SRC}" "${DST}"
echo "Restored menu bar icon: ${DST}"
echo "Reinstall app to apply:"
echo "  ${PROJECT_DIR}/scripts/build_and_install_app.sh"
