#!/bin/bash
# gate_pd_sync.sh — PD解決後のcontext反映チェックゲート（BLOCK）
# Usage: bash scripts/gates/gate_pd_sync.sh <pd_id>
#
# - pending_decisions.yamlから未反映PD(context_synced: false)を全件確認
# - 1件でも存在すればBLOCK表示 + pd_unsync.logに追記 + exit 1
# - 未反映が0件なら該当PD状態を表示してexit 0

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
        print('')
        sys.exit(0)

    unsynced_ids = []
    target_result = 'NOT_FOUND'

    for d in data['decisions']:
        if d.get('context_synced') is False:
            did = d.get('id')
            if did:
                unsynced_ids.append(did)

        if d.get('id') == pd_id:
            synced = d.get('context_synced')
            target_result = 'SYNCED' if synced is True else 'NOT_SYNCED'

    print(target_result)
    print(','.join(unsynced_ids))
except Exception as e:
    print(f'ERROR:{e}', file=sys.stderr)
    print('ERROR')
    print('')
")

TIMESTAMP=$(date "+%Y-%m-%dT%H:%M:%S")
RESULT_STATUS=$(printf '%s\n' "$RESULT" | sed -n '1p')
UNSYNCED_IDS_RAW=$(printf '%s\n' "$RESULT" | sed -n '2p')

if [ -n "$UNSYNCED_IDS_RAW" ]; then
    BLOCK_MSG="$TIMESTAMP  BLOCK: context未反映PDあり: $UNSYNCED_IDS_RAW"
    echo "[gate_pd_sync] $BLOCK_MSG" >&2
    echo "$BLOCK_MSG" >> "$UNSYNC_LOG"
    exit 1
fi

case "$RESULT_STATUS" in
    SYNCED)
        echo "[gate_pd_sync] $PD_ID: context_synced=true (OK)"
        ;;
    NOT_SYNCED)
        echo "[gate_pd_sync] BLOCK: $PD_ID context_synced=false" >&2
        exit 1
        ;;
    NOT_FOUND)
        echo "[gate_pd_sync] WARNING: $PD_ID not found in pending_decisions.yaml" >&2
        ;;
    *)
        echo "[gate_pd_sync] ERROR checking $PD_ID" >&2
        exit 1
        ;;
esac

exit 0
