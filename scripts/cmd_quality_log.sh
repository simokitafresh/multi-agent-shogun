#!/usr/bin/env bash
# cmd_quality_log.sh — cmd設計品質をlogs/cmd_design_quality.yamlに記録
# Usage: bash scripts/cmd_quality_log.sh <cmd_id> <gate_result> <karo_rework:yes/no> <supplementary_cmds:数値> [notes]
#
# 自動取得フィールド:
#   gunshi_verdict: queue/inbox/karo.yamlからcmd_idに該当する軍師verdict (APPROVE/REQUEST_CHANGES/unknown)
#   ninja_blockers: queue/reports/配下のparent_cmd=cmd_idかつstatus=blockedの件数
#   ac_count: shogun_to_karo.yamlの該当cmdのAC数(acceptance_criteria配下の'ACN:'リスト項目をカウント)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$REPO_ROOT/logs/cmd_design_quality.yaml"
LOCK_FILE="/tmp/cmd_design_quality.lock"

# --- Argument validation ---
if [[ $# -lt 4 || $# -gt 5 ]]; then
    echo "Usage: bash scripts/cmd_quality_log.sh <cmd_id> <gate_result> <karo_rework:yes/no> <supplementary_cmds:数値> [notes]" >&2
    echo "Example: bash scripts/cmd_quality_log.sh cmd_1100 CLEAR no 0" >&2
    echo "Example: bash scripts/cmd_quality_log.sh cmd_1100 BLOCK no 0 'reason1|reason2'" >&2
    exit 1
fi

CMD_ID="$1"
GATE_RESULT="$2"
KARO_REWORK="$3"
SUPPLEMENTARY_CMDS="$4"
NOTES="${5:-}"

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
# Search gunshi_review_log.yaml first (persistent), then karo inbox (fallback)
# Priority: draft verdict (APPROVE/REQUEST_CHANGES) > report verdict (LGTM/FAIL) > inbox > unknown
fetch_gunshi_verdict() {
    local review_log="$REPO_ROOT/logs/gunshi_review_log.yaml"
    local karo_inbox="$REPO_ROOT/queue/inbox/karo.yaml"

    # Primary source: gunshi_review_log.yaml (persistent, not affected by inbox archive)
    if [[ -f "$review_log" ]]; then
        local draft_verdict=""
        local report_verdict=""

        # Scan all entries for this cmd_id, classify by review_type
        # awk outputs: review_type<TAB>verdict (rtype defaults to "draft" when absent)
        while IFS=$'\t' read -r _rtype _rverdict; do
            case "$_rtype" in
                draft)
                    [[ -z "$draft_verdict" ]] && draft_verdict="$_rverdict"
                    ;;
                report)
                    [[ -z "$report_verdict" ]] && report_verdict="$_rverdict"
                    ;;
            esac
        done < <(awk -v cid="$CMD_ID" '
            /^- cmd_id:/ || /^-  *cmd_id:/ {
                if (match_cmd && verdict != "") {
                    print (rtype == "" ? "draft" : rtype) "\t" verdict
                }
                match_cmd = 0; rtype = ""; verdict = ""
                sub(/.*cmd_id:[[:space:]]*/, "")
                gsub(/["'"'"']/, ""); gsub(/[[:space:]]*$/, "")
                if ($0 == cid) match_cmd = 1
                next
            }
            match_cmd && /review_type:/ {
                sub(/.*review_type:[[:space:]]*/, "")
                gsub(/["'"'"']/, ""); gsub(/[[:space:]]*$/, "")
                rtype = $0
            }
            match_cmd && /report_verdict:/ {
                sub(/.*report_verdict:[[:space:]]*/, "")
                gsub(/["'"'"']/, ""); gsub(/[[:space:]]*$/, "")
                verdict = $0
            }
            match_cmd && !/report_verdict:/ && /verdict:/ {
                sub(/.*verdict:[[:space:]]*/, "")
                gsub(/["'"'"']/, ""); gsub(/[[:space:]]*$/, "")
                if (verdict == "") verdict = $0
            }
            END {
                if (match_cmd && verdict != "") {
                    print (rtype == "" ? "draft" : rtype) "\t" verdict
                }
            }
        ' "$review_log" 2>/dev/null)

        # Priority: draft verdict > report verdict
        if [[ -n "$draft_verdict" ]]; then
            echo "$draft_verdict"
            return
        fi
        if [[ -n "$report_verdict" ]]; then
            echo "$report_verdict"
            return
        fi
    fi

    # Fallback: karo inbox (may be archived)
    if [[ -f "$karo_inbox" ]]; then
        local verdict_line
        verdict_line=$(grep -A1 "$CMD_ID" "$karo_inbox" 2>/dev/null | grep -oP 'verdict:\s*\K(APPROVE|REQUEST_CHANGES)' | tail -1) || true
        if [[ -z "$verdict_line" ]]; then
            verdict_line=$(grep "$CMD_ID" "$karo_inbox" 2>/dev/null | grep -oP 'verdict:\s*\K(APPROVE|REQUEST_CHANGES)' | tail -1) || true
        fi
        if [[ -n "$verdict_line" ]]; then
            echo "$verdict_line"
            return
        fi
    fi

    echo "unknown"
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
# Count acceptance_criteria items (- 'ACN: ...') in shogun_to_karo.yaml for this cmd
fetch_ac_count() {
    local stk="$REPO_ROOT/queue/shogun_to_karo.yaml"
    if [[ ! -f "$stk" ]]; then
        echo 0
        return
    fi
    # Find cmd block, then acceptance_criteria section, count "- 'ACN:" list items
    awk -v cid="$CMD_ID" '
        $0 ~ "^  " cid ":" { found=1; next }
        found && /^  cmd_/ { exit }
        found && /^    acceptance_criteria:/ { in_ac=1; next }
        found && in_ac && /^    [a-zA-Z_]/ { in_ac=0 }
        found && in_ac && /^    - .AC[0-9]/ { count++ }
        END { print count+0 }
    ' "$stk"
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

    # Append notes field only when provided (optional 5th argument)
    if [[ -n "$NOTES" ]]; then
        echo "    notes: \"$NOTES\"" >> "$LOG_FILE"
    fi

    echo "[cmd_quality_log] Logged: $CMD_ID | AC:$AC_COUNT | gate:$GATE_RESULT | rework:$KARO_REWORK | gunshi:$GUNSHI_VERDICT | blockers:$NINJA_BLOCKERS | supp_cmds:$SUPPLEMENTARY_CMDS${NOTES:+ | notes:$NOTES}"

) 200>"$LOCK_FILE"
