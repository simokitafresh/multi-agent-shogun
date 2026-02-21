#!/bin/bash
# pending_decision_reconcile.sh — stale pending decisionの自動突合・resolve
# Usage: bash scripts/pending_decision_reconcile.sh
#
# 将軍復帰時に実行し、source_cmdが完了/吸収/中止済みのPDを一括resolve。
# resolveはpending_decision_write.sh経由（排他制御あり）。

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PD_FILE="$SCRIPT_DIR/queue/pending_decisions.yaml"
CL_FILE="$SCRIPT_DIR/queue/completed_changelog.yaml"
SK_FILE="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
PD_WRITE="$SCRIPT_DIR/scripts/pending_decision_write.sh"

# ── Edge case: pending_decisions.yaml未存在 ──
if [ ! -f "$PD_FILE" ]; then
    echo "[reconcile] No pending decisions file. Nothing to do."
    exit 0
fi

# ── python3で突合し、resolve対象を特定 ──
RECONCILE_RESULT=$(python3 -c "
import yaml, sys

pd_path = '$PD_FILE'
cl_path = '$CL_FILE'
sk_path = '$SK_FILE'

# Load pending decisions
try:
    with open(pd_path) as f:
        pd_data = yaml.safe_load(f)
except Exception as e:
    print(f'ERROR: Cannot read {pd_path}: {e}', file=sys.stderr)
    sys.exit(1)

if not pd_data or not pd_data.get('decisions'):
    print('NO_PENDING')
    sys.exit(0)

# Load completed_changelog (optional)
# Note: changelog may have malformed YAML (missing first list marker).
# Try YAML first, fall back to regex extraction.
cl_cmds = {}
try:
    with open(cl_path) as f:
        cl_data = yaml.safe_load(f)
    if cl_data and cl_data.get('entries'):
        for entry in cl_data['entries']:
            cmd_id = entry.get('id', '')
            status = entry.get('status', 'completed')
            cl_cmds[cmd_id] = status
except FileNotFoundError:
    pass  # changelog未存在はスキップ
except Exception:
    # YAML parse failed — fallback to regex extraction
    import re
    try:
        with open(cl_path) as f:
            content = f.read()
        # Extract 'id: cmd_XXX' entries
        for m in re.finditer(r'id:\s+(cmd_\d+)', content):
            cmd_id = m.group(1)
            # Check if there's a status field nearby (within 5 lines after id)
            pos = m.end()
            chunk = content[pos:pos+300]
            st = re.search(r'status:\s+(\S+)', chunk)
            cl_cmds[cmd_id] = st.group(1) if st else 'completed'
    except Exception as e2:
        print(f'WARN: changelog fallback also failed: {e2}', file=sys.stderr)

# Load shogun_to_karo (optional)
sk_cmds = {}
try:
    with open(sk_path) as f:
        sk_data = yaml.safe_load(f)
    if sk_data and sk_data.get('commands'):
        for cmd in sk_data['commands']:
            cmd_id = cmd.get('id', '')
            status = cmd.get('status', '')
            sk_cmds[cmd_id] = status
except FileNotFoundError:
    pass  # shogun_to_karo未存在はスキップ
except Exception as e:
    print(f'WARN: Cannot parse {sk_path}: {e}', file=sys.stderr)

# Terminal statuses in shogun_to_karo
TERMINAL_STATUSES = {'completed', 'absorbed', 'cancelled'}

resolved_count = 0
kept_count = 0

for d in pd_data['decisions']:
    if d.get('status') != 'pending':
        continue

    pd_id = d.get('id', '???')
    source_cmd = d.get('source_cmd', '')
    summary = d.get('summary', '')

    # Check changelog first
    if source_cmd in cl_cmds:
        cl_status = cl_cmds[source_cmd]
        reason = f'{source_cmd} {cl_status} (changelog)'
        print(f'RESOLVE|{pd_id}|auto-reconciled: {reason}')
        resolved_count += 1
        continue

    # Check shogun_to_karo
    if source_cmd in sk_cmds:
        sk_status = sk_cmds[source_cmd]
        if sk_status in TERMINAL_STATUSES:
            reason = f'{source_cmd} {sk_status} (shogun_to_karo)'
            print(f'RESOLVE|{pd_id}|auto-reconciled: {reason}')
            resolved_count += 1
            continue

    # Not resolved
    print(f'KEEP|{pd_id}|{source_cmd}|{summary}')
    kept_count += 1

print(f'SUMMARY|{resolved_count}|{kept_count}|{resolved_count + kept_count}')
")

# ── 結果がなければ終了 ──
if [ "$RECONCILE_RESULT" = "NO_PENDING" ]; then
    echo "[reconcile] No pending decisions found. Nothing to do."
    exit 0
fi

# ── 結果をパースし、resolve実行 ──
resolved=0
kept=0
total=0

while IFS='|' read -r action pd_id detail extra; do
    case "$action" in
        RESOLVE)
            bash "$PD_WRITE" resolve "$pd_id" "$detail" "reconcile"
            echo "[reconcile] $pd_id: auto-resolved ($detail)"
            resolved=$((resolved + 1))
            ;;
        KEEP)
            echo "[reconcile] $pd_id: kept (source $detail still pending)"
            kept=$((kept + 1))
            ;;
        SUMMARY)
            total="$extra"
            ;;
    esac
done <<< "$RECONCILE_RESULT"

echo "[reconcile] Summary: resolved=$resolved, kept=$kept, total=$((resolved + kept))"
