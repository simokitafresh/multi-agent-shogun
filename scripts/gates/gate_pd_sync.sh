#!/bin/bash
# gate_pd_sync.sh — PD解決後のcontext反映チェックゲート（WARNING only）
# Usage: bash scripts/gates/gate_pd_sync.sh <pd_id>
#
# - pending_decisions.yamlから該当PDのcontext_syncedを確認
# - context_synced が true 以外 → WARNING表示 + pd_unsync.logに追記
# - ブロックはしない（WARNING only）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DATA_FILE="$SCRIPT_DIR/queue/pending_decisions.yaml"
ALERT_DIR="$SCRIPT_DIR/queue/alerts"
UNSYNC_LOG="$ALERT_DIR/pd_unsync.log"

PD_ID="$1"

if [ -z "$PD_ID" ]; then
    echo "Usage: gate_pd_sync.sh <pd_id>" >&2
    exit 1
fi

if [ ! -f "$DATA_FILE" ]; then
    echo "[gate_pd_sync] WARNING: $DATA_FILE not found" >&2
    exit 0
fi

mkdir -p "$ALERT_DIR"

# Check context_synced for the given PD
RESULT=$(python3 -c "
import yaml, sys

data_path = '$DATA_FILE'
pd_id = '$PD_ID'

try:
    with open(data_path) as f:
        data = yaml.safe_load(f)

    if not data or not data.get('decisions'):
        print('NOT_FOUND')
        sys.exit(0)

    for d in data['decisions']:
        if d.get('id') == pd_id:
            synced = d.get('context_synced')
            if synced is True:
                print('SYNCED')
            else:
                print('NOT_SYNCED')
            sys.exit(0)

    print('NOT_FOUND')
except Exception as e:
    print(f'ERROR:{e}', file=sys.stderr)
    print('ERROR')
")

TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S")

case "$RESULT" in
    SYNCED)
        echo "[gate_pd_sync] $PD_ID: context_synced=true (OK)"
        ;;
    NOT_SYNCED)
        WARNING_MSG="$TIMESTAMP  WARNING: context未反映: $PD_ID"
        echo "[gate_pd_sync] $WARNING_MSG"
        echo "$WARNING_MSG" >> "$UNSYNC_LOG"
        ;;
    NOT_FOUND)
        echo "[gate_pd_sync] WARNING: $PD_ID not found in pending_decisions.yaml" >&2
        ;;
    *)
        echo "[gate_pd_sync] ERROR checking $PD_ID" >&2
        ;;
esac

# Always exit 0 — this is a warning gate, not a blocker
exit 0
