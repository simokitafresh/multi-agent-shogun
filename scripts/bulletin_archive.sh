#!/usr/bin/env bash
# bulletin_archive.sh — 掲示板の古いエントリをアーカイブに退避
# Usage: bash scripts/bulletin_archive.sh [--max-keep N] [--max-age-hours H]
# Default: 直近30件保持、24h超+closed or requires_confirmation:false のエントリをアーカイブ
#
# アーカイブ先: queue/archive/bulletin_{YYYYMMDD}.yaml
# パターン: inbox_archive.sh準拠（flock+手動YAML構築+atomic replace）

set -euo pipefail

SCRIPT_DIR="${BULLETIN_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BULLETIN_FILE="$SCRIPT_DIR/queue/bulletin_board.yaml"

MAX_KEEP=30
MAX_AGE_HOURS=24

while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-keep) MAX_KEEP="$2"; shift 2 ;;
        --max-age-hours) MAX_AGE_HOURS="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ ! -f "$BULLETIN_FILE" ]]; then
    echo "[bulletin_archive] No bulletin file found" >&2
    exit 0
fi

ARCHIVE_DIR="$SCRIPT_DIR/queue/archive"
mkdir -p "$ARCHIVE_DIR"

DATE_STAMP=$(date +%Y%m%d)
ARCHIVE_FILE="$ARCHIVE_DIR/bulletin_${DATE_STAMP}.yaml"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/lock_path.sh" 2>/dev/null \
    || lock_path() { printf '/tmp/shogun_lock_%s.lock' "$(printf '%s' "$1" | md5sum | cut -c1-16)"; }

LOCKFILE="$(lock_path "$BULLETIN_FILE")"

attempt=0
max_attempts=3

while [[ $attempt -lt $max_attempts ]]; do
    if (
        flock -w 5 200 || exit 1

        MAX_KEEP_ENV="$MAX_KEEP" MAX_AGE_HOURS_ENV="$MAX_AGE_HOURS" \
        BULLETIN_PATH="$BULLETIN_FILE" ARCHIVE_PATH="$ARCHIVE_FILE" \
        DRY_RUN_ENV="${DRY_RUN:-0}" \
        python3 -c "
import os, sys, yaml, tempfile
from datetime import datetime, timedelta, timezone

bulletin_path = os.environ['BULLETIN_PATH']
archive_path = os.environ['ARCHIVE_PATH']
max_keep = int(os.environ['MAX_KEEP_ENV'])
max_age_hours = int(os.environ['MAX_AGE_HOURS_ENV'])
dry_run = os.environ['DRY_RUN_ENV'] == '1'

JST = timezone(timedelta(hours=9))
now = datetime.now(JST)
cutoff = now - timedelta(hours=max_age_hours)

with open(bulletin_path, encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}

entries = data.get('entries')
if not isinstance(entries, list):
    print('[bulletin_archive] No entries found')
    sys.exit(0)

total = len(entries)
if total <= max_keep:
    print(f'[bulletin_archive] {total} entries <= {max_keep} max_keep. Nothing to archive.')
    sys.exit(0)

# Classify: keep vs archive
# Archive conditions:
#   1. status == 'closed'
#   2. OR (age > max_age_hours AND (requires_confirmation == false OR all confirmations received))
keep = []
to_archive = []

for entry in entries:
    status = entry.get('status', 'open')
    posted_at_str = entry.get('posted_at', '')

    # Parse posted_at
    try:
        posted_at = datetime.fromisoformat(posted_at_str)
        if posted_at.tzinfo is None:
            posted_at = posted_at.replace(tzinfo=JST)
    except (ValueError, TypeError):
        posted_at = now  # Can't parse → treat as recent

    age_hours = (now - posted_at).total_seconds() / 3600
    is_old = age_hours > max_age_hours

    rc = entry.get('requires_confirmation', False)
    confirmed = entry.get('confirmed_by', [])

    # Determine if all confirmations are complete
    all_confirmed = False
    if rc is False or rc is None:
        all_confirmed = True  # No confirmation needed
    elif rc is True:
        # Need all agents — but we don't know the full list here
        # If it's old + closed, archive. If old + open + no confirms needed, archive
        all_confirmed = (status == 'closed')
    elif isinstance(rc, list):
        all_confirmed = all(a in confirmed for a in rc)

    should_archive = False
    if status == 'closed':
        should_archive = True
    elif is_old and all_confirmed:
        should_archive = True
    elif is_old and rc is False:
        should_archive = True

    if should_archive:
        to_archive.append(entry)
    else:
        keep.append(entry)

# If we still have too many, archive oldest beyond max_keep
if len(keep) > max_keep:
    # Sort by posted_at, keep newest max_keep
    keep.sort(key=lambda e: e.get('posted_at', ''), reverse=True)
    overflow = keep[max_keep:]
    keep = keep[:max_keep]
    to_archive.extend(overflow)

if not to_archive:
    print(f'[bulletin_archive] No entries eligible for archiving ({total} total, {len(keep)} kept)')
    sys.exit(0)

if dry_run:
    print(f'[bulletin_archive] DRY RUN: would archive {len(to_archive)}/{total} entries, keep {len(keep)}')
    for e in to_archive:
        print(f'  - {e.get(\"id\", \"?\")} posted={e.get(\"posted_at\",\"?\")} status={e.get(\"status\",\"?\")}')
    sys.exit(0)

# --- yaml.dump禁止: 手動YAML構築 (inbox_archive.sh準拠) ---
def sq(value):
    return str(value).replace(chr(39), chr(39)+chr(39))

def write_entries(fh, entries_list):
    if not entries_list:
        fh.write('entries: []\n')
        return
    fh.write('entries:\n')
    for entry in entries_list:
        fh.write(f\"- id: '{sq(entry.get('id', ''))}'\n\")
        fh.write('  content: |-\n')
        text = str(entry.get('content', ''))
        lines = text.splitlines() or ['']
        for line in lines:
            fh.write(f'    {line}\n')
        fh.write(f\"  posted_by: '{sq(entry.get('posted_by', ''))}'\n\")
        fh.write(f\"  posted_at: '{sq(entry.get('posted_at', ''))}'\n\")
        rc = entry.get('requires_confirmation')
        if isinstance(rc, list):
            fh.write('  requires_confirmation:\n')
            for agent_name in rc:
                fh.write(f\"    - '{sq(agent_name)}'\n\")
        elif rc:
            fh.write('  requires_confirmation: true\n')
        else:
            fh.write('  requires_confirmation: false\n')
        confirmed = entry.get('confirmed_by') or []
        if confirmed:
            fh.write('  confirmed_by:\n')
            for agent in confirmed:
                fh.write(f\"    - '{sq(agent)}'\n\")
        else:
            fh.write('  confirmed_by: []\n')
        fh.write(f\"  status: '{sq(entry.get('status', 'open'))}'\n\")

# Load existing archive
if os.path.exists(archive_path):
    with open(archive_path, encoding='utf-8') as f:
        archive_data = yaml.safe_load(f) or {}
    existing_archived = archive_data.get('entries', [])
    if not isinstance(existing_archived, list):
        existing_archived = []
else:
    existing_archived = []

# Merge: existing archive + new to_archive
all_archived = existing_archived + to_archive

# Write archive (atomic)
tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(archive_path), suffix='.tmp')
try:
    with os.fdopen(tmp_fd, 'w', encoding='utf-8') as f:
        f.write(f'# Bulletin archive — {os.path.basename(archive_path)}\n')
        f.write(f'# Entries: {len(all_archived)}\n')
        write_entries(f, all_archived)
    os.replace(tmp_path, archive_path)
except Exception:
    os.unlink(tmp_path)
    raise

# Rewrite bulletin with kept entries only (atomic)
tmp_fd2, tmp_path2 = tempfile.mkstemp(dir=os.path.dirname(bulletin_path), suffix='.tmp')
try:
    with os.fdopen(tmp_fd2, 'w', encoding='utf-8') as f:
        write_entries(f, keep)
    os.replace(tmp_path2, bulletin_path)
except Exception:
    os.unlink(tmp_path2)
    raise

print(f'[bulletin_archive] Archived {len(to_archive)}/{total} entries to {archive_path}. Kept {len(keep)}.')
" || exit 1

    ) 200>"$LOCKFILE"; then
        exit 0
    else
        attempt=$((attempt + 1))
        if [[ $attempt -lt $max_attempts ]]; then
            echo "[bulletin_archive] Lock timeout (attempt $attempt/$max_attempts), retrying..." >&2
            sleep 1
        else
            echo "[bulletin_archive] Failed to acquire lock after $max_attempts attempts" >&2
            exit 1
        fi
    fi
done
