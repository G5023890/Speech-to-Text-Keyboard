#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/safe_cleanup.sh            # dry-run only
  scripts/safe_cleanup.sh --execute  # dry-run + confirmation + delete
EOF
}

to_human_from_kb() {
  awk -v kb="$1" 'BEGIN {
    b = kb * 1024
    split("B KB MB GB TB", u, " ")
    i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    printf "%.2f %s", b, u[i]
  }'
}

MODE="dry-run"
if [[ $# -gt 1 ]]; then
  usage
  exit 1
fi
if [[ $# -eq 1 ]]; then
  case "$1" in
    --execute) MODE="execute" ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
fi

ROOT="$(pwd -P)"
LIST_FILE="$(mktemp "${TMPDIR:-/tmp}/safe-cleanup-list.XXXXXX")"
REPORT_FILE="$(mktemp "${TMPDIR:-/tmp}/safe-cleanup-report.XXXXXX")"
trap 'rm -f "$LIST_FILE" "$REPORT_FILE"' EXIT

# Collect only approved targets, strictly inside current directory, excluding .git
find "$ROOT" \
  \( -path "$ROOT/.git" -o -path "$ROOT/.git/*" \) -prune -o \
  \( -type d \( \
      -name node_modules -o \
      -name dist -o \
      -name build -o \
      -name .cache -o \
      -name tmp -o \
      -name .tmp -o \
      -name .build -o \
      -name DerivedData -o \
      -name __pycache__ -o \
      -name .pytest_cache -o \
      -name .mypy_cache -o \
      -name target -o \
      -name pkg -o \
      -name CMakeFiles -o \
      -name .codex -o \
      -name .agent -o \
      -name xcuserdata \
    \) -print0 -prune \) -o \
  \( -type f \( \
      -name "*.log" -o \
      -name ".DS_Store" -o \
      -name "*.xcuserstate" -o \
      -name "*.pyc" -o \
      -name "CMakeCache.txt" \
    \) -print0 \) > "$LIST_FILE"

# Go: bin (only if it looks like build artifact, and only top-level ./bin)
if [[ -d "$ROOT/bin" ]]; then
  if find "$ROOT/bin" -type f -perm -111 | grep -q .; then
    printf '%s\0' "$ROOT/bin" >> "$LIST_FILE"
  fi
fi

PROJECT_KB="$(du -sk "$ROOT" | awk '{print $1}')"
PROJECT_HUMAN="$(to_human_from_kb "$PROJECT_KB")"

COUNT=0
TOTAL_KB=0
while IFS= read -r -d '' path; do
  [[ -e "$path" ]] || continue
  sz="$(du -sk "$path" | awk '{print $1}')"
  TOTAL_KB=$((TOTAL_KB + sz))
  COUNT=$((COUNT + 1))
  rel="${path#$ROOT/}"
  printf "%10s KB  %s\n" "$sz" "$rel" >> "$REPORT_FILE"
done < "$LIST_FILE"

TOTAL_HUMAN="$(to_human_from_kb "$TOTAL_KB")"

echo "Current project: $ROOT"
echo "Project size: $PROJECT_HUMAN"
echo "Found items to remove: $COUNT"
echo "Total to remove: $TOTAL_HUMAN"
echo
echo "Dry-run list:"
if [[ "$COUNT" -eq 0 ]]; then
  echo "  (nothing to remove)"
else
  cat "$REPORT_FILE"
fi

if [[ "$MODE" != "execute" ]]; then
  exit 0
fi

echo
read -r -p "Proceed with deletion? [y/N]: " answer
case "$answer" in
  y|Y|yes|YES) ;;
  *)
    echo "Cancelled. Nothing was deleted."
    exit 0
    ;;
esac

BEFORE_KB="$PROJECT_KB"
while IFS= read -r -d '' path; do
  [[ -e "$path" ]] || continue
  if [[ -d "$path" ]]; then
    rm -r -- "$path"
  else
    rm -f -- "$path"
  fi
done < "$LIST_FILE"

AFTER_KB="$(du -sk "$ROOT" | awk '{print $1}')"
FREED_KB=$((BEFORE_KB - AFTER_KB))
if [[ "$FREED_KB" -lt 0 ]]; then
  FREED_KB=0
fi

AFTER_HUMAN="$(to_human_from_kb "$AFTER_KB")"
FREED_HUMAN="$(to_human_from_kb "$FREED_KB")"

echo
echo "Cleanup completed."
echo "New project size: $AFTER_HUMAN"
echo "Freed space: $FREED_HUMAN"
