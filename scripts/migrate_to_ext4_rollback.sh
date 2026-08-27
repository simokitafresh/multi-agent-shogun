#!/usr/bin/env bash
# semantic-links: [[cmd_4408_ext4移設]], [[可逆切替]]
# Restore only cutover's crontab backup and migration marker.
set -euo pipefail

OLD_ROOT="${OLD_ROOT:-/mnt/c/tools/multi-agent-shogun}"
NEW_ROOT="${NEW_ROOT:-/home/simokitafresh/multi-agent-shogun}"
STATE_BACKUP="$NEW_ROOT/.migrate_to_ext4_crontab.backup"
MARKER="$OLD_ROOT/MIGRATED_TO_EXT4.txt"
DRY_RUN=false

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) printf '%s\n' "Usage: $0 [--dry-run]"; exit 0 ;;
    *) printf 'ERROR: unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ ! -f "$STATE_BACKUP" ]]; then
  if "$DRY_RUN"; then
    printf '%s\n' 'DRY_RUN: rollback backup absent; no changes performed'
    exit 0
  fi
  printf 'ROLLBACK_BLOCKED: crontab backup missing: %s\n' "$STATE_BACKUP" >&2
  exit 2
fi

if "$DRY_RUN"; then
  printf '%s\n' "DRY_RUN: would restore crontab from $STATE_BACKUP and remove $MARKER; no changes performed"
  exit 0
fi

crontab "$STATE_BACKUP"
if [[ -e "$MARKER" ]]; then
  rm -f -- "$MARKER"
fi
printf '%s\n' 'ROLLBACK_PASS: crontab restored and migration marker removed'
