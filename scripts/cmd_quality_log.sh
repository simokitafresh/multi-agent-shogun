#!/usr/bin/env bash
# cmd_quality_log.sh — cmd設計品質をlogs/cmd_design_quality.yamlに記録
# Usage: bash scripts/cmd_quality_log.sh <cmd_id> <gate_result> <karo_rework:yes/no> <supplementary_cmds:数値>
#
# 自動取得フィールド:
#   gunshi_verdict: queue/inbox/karo.yamlからcmd_idに該当する軍師verdict (APPROVE/REQUEST_CHANGES/unknown)
#   ninja_blockers: queue/reports/配下のparent_cmd=cmd_idかつstatus=blockedの件数
#   ac_count: shogun_to_karo.yamlの該当cmdのAC数(■ ACパターンをカウント)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$REPO_ROOT/logs/cmd_design_quality.yaml"
LOCK_FILE="/tmp/cmd_design_quality.lock"

# --- Argument validation ---
if [[ $# -ne 4 ]]; then
    echo "Usage: bash scripts/cmd_quality_log.sh <cmd_id> <gate_result> <karo_rework:yes/no> <supplementary_cmds:数値>" >&2
    echo "Example: bash scripts/cmd_quality_log.sh cmd_1100 CLEAR no 0" >&2
    exit 1
fi

CMD_ID="$1"
GATE_RESULT="$2"
KARO_REWORK="$3"
SUPPLEMENTARY_CMDS="$4"

if [[ -z "$CMD_ID" || -z "$GATE_RESULT" || -z "$KARO_REWORK" || -z "$SUPPLEMENTARY_CMDS" ]]; then
    echo "[cmd_quality_log] Error: All arguments must be non-empty" >&2
    exit 1
fi

# Validate gate_result
if [[ "$GATE_RESULT" != "CLEAR" && "$GATE_RESULT" != "FAIL" && "$GATE_RESULT" != "BLOCK" ]]; then
    echo "[cmd_quality_log] Error: gate_result must be CLEAR, FAIL, or BLOCK (got: $GATE_RESULT)" >&2
    exit 1
fi

# Validate karo_rework
if [[ "$KARO_REWORK" != "yes" && "$KARO_REWORK" != "no" ]]; then
    echo "[cmd_quality_log] Error: karo_rework must be yes or no (got: $KARO_REWORK)" >&2
    exit 1
fi

# Validate supplementary_cmds is a number
if ! [[ "$SUPPLEMENTARY_CMDS" =~ ^[0-9]+$ ]]; then
    echo "[cmd_quality_log] Error: supplementary_cmds must be a non-negative integer (got: $SUPPLEMENTARY_CMDS)" >&2
    exit 1
fi

# --- Auto-fetch: gunshi_verdict ---
# Search karo inbox for gunshi verdict messages matching cmd_id
fetch_gunshi_verdict() {
    local karo_inbox="$REPO_ROOT/queue/inbox/karo.yaml"
    if [[ ! -f "$karo_inbox" ]]; then
        echo "unknown"
        return
    fi
    # grep for lines containing both the cmd_id and "verdict:"
    # Pattern: gunshi sends "cmd_XXXX...verdict: APPROVE/REQUEST_CHANGES" to karo inbox
    local verdict_line
    verdict_line=$(grep -A1 "$CMD_ID" "$karo_inbox" 2>/dev/null | grep -oP 'verdict:\s*\K(APPROVE|REQUEST_CHANGES)' | tail -1) || true
    if [[ -z "$verdict_line" ]]; then
        # Try single-line match (content often spans one line)
        verdict_line=$(grep "$CMD_ID" "$karo_inbox" 2>/dev/null | grep -oP 'verdict:\s*\K(APPROVE|REQUEST_CHANGES)' | tail -1) || true
    fi
    if [[ -n "$verdict_line" ]]; then
        echo "$verdict_line"
    else
        echo "unknown"
    fi
}

# --- Auto-fetch: ninja_blockers ---
# Count reports with parent_cmd=cmd_id and status=blocked
fetch_ninja_blockers() {
    local reports_dir="$REPO_ROOT/queue/reports"
    local count=0
    if [[ ! -d "$reports_dir" ]]; then
        echo 0
        return
    fi
    for report in "$reports_dir"/*_report_*.yaml; do
        [[ -f "$report" ]] || continue
        local has_parent has_blocked
        has_parent=$(grep -c "^parent_cmd: $CMD_ID$" "$report" 2>/dev/null) || true
        if [[ "$has_parent" -gt 0 ]]; then
            has_blocked=$(grep -c "^status: blocked$" "$report" 2>/dev/null) || true
            if [[ "$has_blocked" -gt 0 ]]; then
                count=$((count + 1))
            fi
        fi
    done
    echo "$count"
}

# --- Auto-fetch: ac_count ---
# Count ■ AC lines in shogun_to_karo.yaml for this cmd
fetch_ac_count() {
    local stk="$REPO_ROOT/queue/shogun_to_karo.yaml"
    if [[ ! -f "$stk" ]]; then
        echo 0
        return
    fi
    # Use awk: find cmd block (2-space indent), count ■ AC lines until next cmd block
    awk "/^  ${CMD_ID}:/{found=1; next} found && /^  cmd_/{exit} found && /■ AC/{count++} END{print count+0}" "$stk"
}

GUNSHI_VERDICT=$(fetch_gunshi_verdict)
NINJA_BLOCKERS=$(fetch_ninja_blockers)
AC_COUNT=$(fetch_ac_count)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Append entry with flock ---
(
    flock -w 10 200 || { echo "[cmd_quality_log] Error: Failed to acquire lock" >&2; exit 1; }

    # Initialize file if it doesn't exist or is empty
    if [[ ! -f "$LOG_FILE" ]] || [[ ! -s "$LOG_FILE" ]]; then
        echo "entries:" > "$LOG_FILE"
    fi

    # Append entry
    cat >> "$LOG_FILE" <<EOF
  - cmd_id: "$CMD_ID"
    ac_count: $AC_COUNT
    gate_result: "$GATE_RESULT"
    karo_rework: "$KARO_REWORK"
    gunshi_verdict: "$GUNSHI_VERDICT"
    ninja_blockers: $NINJA_BLOCKERS
    supplementary_cmds: $SUPPLEMENTARY_CMDS
    timestamp: "$TIMESTAMP"
EOF

    echo "[cmd_quality_log] Logged: $CMD_ID | AC:$AC_COUNT | gate:$GATE_RESULT | rework:$KARO_REWORK | gunshi:$GUNSHI_VERDICT | blockers:$NINJA_BLOCKERS | supp_cmds:$SUPPLEMENTARY_CMDS"

) 200>"$LOCK_FILE"
