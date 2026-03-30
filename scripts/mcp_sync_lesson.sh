#!/usr/bin/env bash
# ============================================================
# mcp_sync_lesson.sh — MCP [share:ninja] observations → lessons.yaml 自動同期
#
# MCP Memoryはスクリプトから直接アクセス不可のため、
# 将軍がsearch_nodes("[share:ninja]")結果をstaging fileに書き出し、
# 本スクリプトで一括同期する。
#
# Usage:
#   bash scripts/mcp_sync_lesson.sh [staging_file]
#
# Staging file format (YAML):
#   entries:
#     - observation: "[share:ninja] UIのボタン色は#1a73e8を基調にせよ"
#       entity: shogun_core
#       project: infra        # optional, default: infra
#       tags: "mcp-shared,ui-design"  # optional, default: mcp-shared
#     - observation: "[share:ninja] 本番DBのtimeout=30s"
#       entity: dm_signal_decisions
#       project: dm-signal
#       tags: "mcp-shared,db"
#
# Default staging file: queue/mcp_sync_staging.yaml
#
# Outputs:
#   - lessons.yaml (via lesson_write.sh)
#   - queue/mcp_sync_tracker.yaml (同期済みトラッキング)
#   - logs/mcp_sync.log (同期ログ — gate_shogun_memory.shが鮮度検査)
#
# Exit code: 0=成功, 1=エラー
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGING_FILE="${1:-$SCRIPT_DIR/queue/mcp_sync_staging.yaml}"
TRACKER_FILE="$SCRIPT_DIR/queue/mcp_sync_tracker.yaml"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/mcp_sync.log"

# Ensure directories
mkdir -p "$LOG_DIR"

# Validate staging file
if [ ! -f "$STAGING_FILE" ]; then
    echo "ERROR: Staging file not found: $STAGING_FILE" >&2
    echo "将軍がsearch_nodes(\"[share:ninja]\")結果をstaging fileに書き出してから実行せよ" >&2
    exit 1
fi

# Initialize tracker if not exists
if [ ! -f "$TRACKER_FILE" ]; then
    echo "synced: []" > "$TRACKER_FILE"
fi

# Process staging file
export SCRIPT_DIR STAGING_FILE TRACKER_FILE LOG_FILE
python3 << 'PYEOF'
import yaml, hashlib, subprocess, sys, os, json, tempfile
from datetime import datetime

script_dir = os.environ["SCRIPT_DIR"]
staging_file = os.environ["STAGING_FILE"]
tracker_file = os.environ["TRACKER_FILE"]
log_file = os.environ["LOG_FILE"]

# Read staging file
with open(staging_file, encoding='utf-8') as f:
    staging = yaml.safe_load(f) or {}

entries = staging.get('entries', [])
if not entries:
    print("INFO: No entries in staging file")
    # Still write log for gate freshness check
    with open(log_file, 'a', encoding='utf-8') as f:
        f.write(f"{datetime.now().isoformat()} | synced=0 skipped=0 errors=0 (empty staging)\n")
    sys.exit(0)

# Read tracker
with open(tracker_file, encoding='utf-8') as f:
    tracker = yaml.safe_load(f) or {}

synced_hashes = set()
for item in tracker.get('synced', []) or []:
    if isinstance(item, dict) and 'hash' in item:
        synced_hashes.add(item['hash'])

synced_count = 0
skipped_count = 0
error_count = 0
new_synced = list(tracker.get('synced', []) or [])

for entry in entries:
    obs = entry.get('observation', '')
    if not obs:
        continue

    project = entry.get('project', 'infra')

    # Compute hash for duplicate tracking (AC2)
    # Include project in hash so same observation can sync to multiple projects
    obs_hash = hashlib.sha256(f"{project}:{obs}".encode('utf-8')).hexdigest()[:16]

    if obs_hash in synced_hashes:
        print(f"SKIP(tracked): {obs[:60]}...")
        skipped_count = skipped_count + 1
        continue

    # Strip [share:ninja] marker for clean content
    clean_obs = obs.replace('[share:ninja]', '').strip()

    # Generate title (first sentence or first 60 chars)
    title = clean_obs
    for sep in ['。', '．', '. ']:
        idx = clean_obs.find(sep)
        if 0 < idx < 60:
            title = clean_obs[:idx + len(sep)]
            break
    else:
        if len(title) > 60:
            title = title[:60]
    tags = entry.get('tags', 'mcp-shared')
    if 'mcp-shared' not in tags:
        tags = f"mcp-shared,{tags}"
    entity = entry.get('entity', 'unknown')

    # Call lesson_write.sh
    cmd = [
        'bash', f'{script_dir}/scripts/lesson_write.sh',
        project, title, clean_obs, f'mcp-sync({entity})', 'shogun', '',
        '--tags', tags
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            print(f"SYNCED: {title[:50]}...")
            synced_count = synced_count + 1
            new_synced.append({
                'hash': obs_hash,
                'observation': clean_obs[:100],
                'synced_at': datetime.now().strftime('%Y-%m-%d'),
                'entity': entity
            })
            synced_hashes.add(obs_hash)
        else:
            stderr = result.stderr.strip()
            if '類似教訓あり' in stderr:
                print(f"SKIP(similar): {title[:50]}...")
                skipped_count = skipped_count + 1
                # Track to avoid retrying (AC2)
                new_synced.append({
                    'hash': obs_hash,
                    'observation': clean_obs[:100],
                    'synced_at': datetime.now().strftime('%Y-%m-%d'),
                    'entity': entity,
                    'note': 'skipped-similar-exists'
                })
                synced_hashes.add(obs_hash)
            else:
                print(f"ERROR: {title[:50]}... — {stderr}", file=sys.stderr)
                error_count = error_count + 1
    except subprocess.TimeoutExpired:
        print(f"ERROR: Timeout: {title[:50]}...", file=sys.stderr)
        error_count = error_count + 1

# Update tracker (yaml.dump禁止 — CLAUDE.md YAML書込み安全規則準拠)
# 手動YAML書出し + atomic rename でデータ消失を防止
tmp_fd, tmp_path = tempfile.mkstemp(
    dir=os.path.dirname(tracker_file), suffix='.tmp'
)
try:
    with os.fdopen(tmp_fd, 'w', encoding='utf-8') as tmp:
        tmp.write("synced:\n")
        for item in new_synced:
            tmp.write(f"- hash: {item['hash']}\n")
            tmp.write(f"  observation: {json.dumps(item.get('observation', ''), ensure_ascii=False)}\n")
            tmp.write(f"  synced_at: \"{item['synced_at']}\"\n")
            tmp.write(f"  entity: {item['entity']}\n")
            if 'note' in item:
                tmp.write(f"  note: {item['note']}\n")
    os.replace(tmp_path, tracker_file)
except Exception:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    raise

# Write log (AC3: gate_shogun_memory.sh checks this for freshness)
with open(log_file, 'a', encoding='utf-8') as f:
    f.write(f"{datetime.now().isoformat()} | synced={synced_count} skipped={skipped_count} errors={error_count}\n")

print(f"\n--- Summary ---")
print(f"Synced: {synced_count}")
print(f"Skipped: {skipped_count}")
print(f"Errors: {error_count}")

if error_count > 0:
    sys.exit(1)
PYEOF
