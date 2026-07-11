#!/usr/bin/env bash
# semantic-links: [[cmd設計品質ログ]]
# cmd_quality_log.sh — cmd設計品質をlogs/cmd_design_quality.yamlに記録
# Usage: bash scripts/cmd_quality_log.sh <cmd_id> <gate_result> <karo_rework:yes/no> <supplementary_cmds:数値> [notes]
#
# 自動取得フィールド:
#   gunshi_verdict: queue/inbox/karo.yamlからcmd_idに該当する軍師verdict (APPROVE/REQUEST_CHANGES/unknown)
#   ninja_blockers: queue/reports/配下のparent_cmd=cmd_idかつstatus=blockedの件数
#   ac_count: shogun_to_karo正本→parent_cmd一致task→対応reportの順で解決

set -euo pipefail

# SCRIPT_DIR: string ops instead of $(cd) subshells (~5ms savings on WSL2)
_cql_self="${BASH_SOURCE[0]:-$0}"
[[ "$_cql_self" != /* ]] && _cql_self="$PWD/$_cql_self"
SCRIPT_DIR="${_cql_self%/*}"
REPO_ROOT="${SCRIPT_DIR%/scripts}"
LOG_FILE="${CMD_QUALITY_LOG_FILE:-$REPO_ROOT/logs/cmd_design_quality.yaml}"
# yaml_auto_archive.sh uses this same per-file lock before replacing the hot
# log.  A separate lock allowed an append to race with archive's stale temp
# file and silently discard the appended entries.
LOCK_FILE="${LOG_FILE}.lock"
SOURCE_STAGE="${CMD_QUALITY_SOURCE:-cmd_complete_gate}"
DIAGNOSIS_TEXT="${CMD_QUALITY_DIAGNOSIS:-}"
FAST_METADATA="${CMD_QUALITY_FAST_METADATA:-0}"
PROJECT_ID="${CMD_QUALITY_PROJECT:-}"
CHECK_NAMES="${CMD_QUALITY_CHECK_NAMES:-}"
BLOCK_DURATION="${CMD_QUALITY_BLOCK_DURATION:-0}"
MEMORY_DB_LIVE_INSERT="${MEMORY_DB_LIVE_INSERT:-$REPO_ROOT/scripts/memory_db_live_insert_async.py}"
if [[ ! -f "$MEMORY_DB_LIVE_INSERT" ]]; then
    MEMORY_DB_LIVE_INSERT="$REPO_ROOT/scripts/memory_db_live_insert.py"
fi

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
if [[ "$GATE_RESULT" != "CLEAR" && "$GATE_RESULT" != "PASS" && "$GATE_RESULT" != "FAIL" && "$GATE_RESULT" != "BLOCK" && "$GATE_RESULT" != "WARN" ]]; then
    echo "[cmd_quality_log] Error: gate_result must be CLEAR, PASS, FAIL, BLOCK, or WARN (got: $GATE_RESULT)" >&2
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

        if grep -Fq "$CMD_ID" "$review_log" 2>/dev/null; then
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
        fi

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
# Optimization: use filename-based glob to avoid scanning all report files
# Report naming: {ninja}_report_{cmd_id}[_{timestamp}].yaml
# Opening all 102 files costs ~600ms on WSL2 NTFS; glob match costs ~10ms
fetch_ninja_blockers() {
    local reports_dir="$REPO_ROOT/queue/reports"
    if [[ ! -d "$reports_dir" ]]; then
        echo 0
        return
    fi

    local count=0
    local report
    for report in "$reports_dir"/*_report_${CMD_ID}.yaml \
                  "$reports_dir"/*_report_${CMD_ID}_*.yaml; do
        [[ -f "$report" ]] || continue
        # Secondary check: verify parent_cmd and status (handles edge-case glob overlaps)
        if grep -qF "parent_cmd: $CMD_ID" "$report" 2>/dev/null && \
           grep -q "^status: blocked$" "$report" 2>/dev/null; then
            count=$((count + 1))
        fi
    done
    echo "$count"
}

# --- Auto-fetch: ac_count ---
# Count acceptance_criteria items (- 'ACN: ...') in shogun_to_karo.yaml for this cmd
fetch_ac_count() {
    local stk="${CMD_QUALITY_COMMAND_FILE:-$REPO_ROOT/queue/shogun_to_karo.yaml}"
    local tasks_dir="${CMD_QUALITY_TASKS_DIR:-$REPO_ROOT/queue/tasks}"
    local reports_dir="${CMD_QUALITY_REPORTS_DIR:-$REPO_ROOT/queue/reports}"
    python3 - "$CMD_ID" "$stk" "$tasks_dir" "$reports_dir" <<'PY'
import glob, os, sys, yaml

cid, command_file, tasks_dir, reports_dir = sys.argv[1:]

def load(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return yaml.safe_load(fh) or {}
    except (OSError, yaml.YAMLError) as exc:
        print(f"[cmd_quality_log] ac_count diagnostic: unreadable YAML {path}: {exc}", file=sys.stderr)
        return None

def ac_len(value):
    return len(value) if isinstance(value, (dict, list)) else 0

# Normal commands retain their authoritative shogun_to_karo definition.
commands = load(command_file) if os.path.isfile(command_file) else {}
if isinstance(commands, dict):
    candidate = commands.get(cid)
    if isinstance(candidate, dict) and ac_len(candidate.get("acceptance_criteria")):
        print(ac_len(candidate["acceptance_criteria"]))
        raise SystemExit

task_matches = []
for path in sorted(glob.glob(os.path.join(tasks_dir, "*.yaml"))):
    data = load(path)
    task = data.get("task", data) if isinstance(data, dict) else None
    if isinstance(task, dict) and task.get("parent_cmd") == cid:
        task_matches.append((path, ac_len(task.get("acceptance_criteria"))))
if len(task_matches) == 1 and task_matches[0][1] > 0:
    print(task_matches[0][1])
    raise SystemExit
if len(task_matches) > 1:
    print(f"[cmd_quality_log] ac_count diagnostic: ambiguous tasks for {cid}: {len(task_matches)}", file=sys.stderr)
    print(0)
    raise SystemExit

report_matches = []
for path in sorted(glob.glob(os.path.join(reports_dir, "*.yaml"))):
    data = load(path)
    if isinstance(data, dict) and data.get("parent_cmd") == cid:
        checks = data.get("binary_checks")
        count = sum(1 for key in checks if str(key).upper().startswith("AC")) if isinstance(checks, dict) else 0
        report_matches.append((path, count))
if len(report_matches) == 1 and report_matches[0][1] > 0:
    print(report_matches[0][1])
elif len(report_matches) > 1:
    print(f"[cmd_quality_log] ac_count diagnostic: ambiguous reports for {cid}: {len(report_matches)}", file=sys.stderr)
    print(0)
else:
    print(f"[cmd_quality_log] ac_count diagnostic: no authoritative AC source for {cid}", file=sys.stderr)
    print(0)
PY
}

if [[ "$FAST_METADATA" == "1" ]]; then
    GUNSHI_VERDICT="unknown"
    NINJA_BLOCKERS=0
    AC_COUNT=0
else
    GUNSHI_VERDICT=$(fetch_gunshi_verdict)
    NINJA_BLOCKERS=$(fetch_ninja_blockers)
    AC_COUNT=$(fetch_ac_count)
fi
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Append entry with flock ---
append_status=0
(
    flock -w 10 200 || { echo "[cmd_quality_log] Error: Failed to acquire lock" >&2; exit 1; }

    # Initialize file if it doesn't exist or is empty
    if [[ ! -f "$LOG_FILE" ]] || [[ ! -s "$LOG_FILE" ]]; then
        echo "entries:" > "$LOG_FILE"
    else
        # Fix: 'entries: []' is invalid when appending list items — normalize to 'entries:'
        IFS= read -r _first_line < "$LOG_FILE"
        if [[ "$_first_line" == "entries: []" ]]; then
            sed -i '1s/^entries: \[\]$/entries:/' "$LOG_FILE"
        fi
    fi

    # cmd_complete_gate.sh already records CLEAR. Keep CLEAR logging idempotent so
    # cmd-complete retry/step overlap does not inflate quality metrics.
    if [[ "$GATE_RESULT" == "CLEAR" ]] && awk -v cid="$CMD_ID" -v gate="$GATE_RESULT" -v source="$SOURCE_STAGE" '
        function strip_value(s) {
            sub(/^[^:]+:[[:space:]]*/, "", s)
            gsub(/["'\'']/, "", s)
            sub(/[[:space:]]*$/, "", s)
            return s
        }
        function flush_entry() {
            if (entry_cmd == cid && entry_gate == gate && entry_source == source) {
                found = 1
            }
        }
        /^[[:space:]]*- cmd_id:/ {
            flush_entry()
            entry_cmd = strip_value($0)
            entry_gate = ""
            entry_source = ""
            next
        }
        entry_cmd != "" && /^[[:space:]]+gate_result:/ {
            entry_gate = strip_value($0)
            next
        }
        entry_cmd != "" && /^[[:space:]]+source:/ {
            entry_source = strip_value($0)
            next
        }
        END {
            flush_entry()
            exit found ? 0 : 1
        }
    ' "$LOG_FILE"; then
        echo "[cmd_quality_log] SKIP duplicate CLEAR: $CMD_ID | source:$SOURCE_STAGE"
        exit 10
    fi

    entry_indent="$(awk '
        /^entries:[[:space:]]*$/ { in_entries=1; next }
        in_entries && /^[[:space:]]*-/ {
            match($0, /^[[:space:]]*/)
            print substr($0, RSTART, RLENGTH)
            exit
        }
    ' "$LOG_FILE")"
    field_indent="${entry_indent}  "

    cat >> "$LOG_FILE" <<EOF
${entry_indent}- cmd_id: "$CMD_ID"
${field_indent}ac_count: $AC_COUNT
${field_indent}gate_result: "$GATE_RESULT"
${field_indent}karo_rework: "$KARO_REWORK"
${field_indent}gunshi_verdict: "$GUNSHI_VERDICT"
${field_indent}ninja_blockers: $NINJA_BLOCKERS
${field_indent}project: "$PROJECT_ID"
${field_indent}supplementary_cmds: $SUPPLEMENTARY_CMDS
${field_indent}source: "$SOURCE_STAGE"
${field_indent}timestamp: "$TIMESTAMP"
EOF

    if [[ -n "$CHECK_NAMES" ]]; then
        escaped_checks="${CHECK_NAMES//\\/\\\\}"
        escaped_checks="${escaped_checks//\"/\\\"}"
        echo "${field_indent}checks: \"$escaped_checks\"" >> "$LOG_FILE"
    fi

    if [[ "$BLOCK_DURATION" =~ ^[0-9]+$ ]] && (( BLOCK_DURATION > 0 )); then
        echo "${field_indent}block_duration_minutes: $BLOCK_DURATION" >> "$LOG_FILE"
    fi

    if [[ -n "$DIAGNOSIS_TEXT" ]]; then
        escaped_diagnosis="${DIAGNOSIS_TEXT//\\/\\\\}"
        escaped_diagnosis="${escaped_diagnosis//\"/\\\"}"
        echo "${field_indent}diagnosis: \"$escaped_diagnosis\"" >> "$LOG_FILE"
    fi

    # Append notes field only when provided (optional 5th argument)
    if [[ -n "$NOTES" ]]; then
        # Escape backslashes first, then double quotes to prevent YAML corruption
        escaped_notes="${NOTES//\\/\\\\}"
        escaped_notes="${escaped_notes//\"/\\\"}"
        echo "${field_indent}notes: \"$escaped_notes\"" >> "$LOG_FILE"
    fi

    echo "[cmd_quality_log] Logged: $CMD_ID | AC:$AC_COUNT | gate:$GATE_RESULT | rework:$KARO_REWORK | gunshi:$GUNSHI_VERDICT | blockers:$NINJA_BLOCKERS | supp_cmds:$SUPPLEMENTARY_CMDS | source:$SOURCE_STAGE${DIAGNOSIS_TEXT:+ | diagnosis:$DIAGNOSIS_TEXT}${NOTES:+ | notes:$NOTES}"

) 200>"$LOCK_FILE" || append_status=$?

if [[ "$append_status" -eq 10 ]]; then
    exit 0
elif [[ "$append_status" -ne 0 ]]; then
    exit "$append_status"
fi

SOURCE_FILE="${LOG_FILE#$REPO_ROOT/}"
if [[ "$SOURCE_FILE" == "$LOG_FILE" && "$LOG_FILE" = /* ]]; then
    SOURCE_FILE="$LOG_FILE"
fi
if [[ -f "$MEMORY_DB_LIVE_INSERT" && ( -n "${SHOGUN_MEMORY_DB:-}" || "$SOURCE_FILE" != /tmp/* ) ]]; then
    memory_db_args=(
        cmd_quality
        --cmd-id "$CMD_ID"
        --ts "$TIMESTAMP"
        --gate-result "$GATE_RESULT"
        --karo-rework "$KARO_REWORK"
        --gunshi-verdict "$GUNSHI_VERDICT"
        --ninja-blockers "$NINJA_BLOCKERS"
        --ac-count "$AC_COUNT"
        --supplementary-cmds "$SUPPLEMENTARY_CMDS"
        --project "$PROJECT_ID"
        --source "$SOURCE_STAGE"
        --diagnosis "$DIAGNOSIS_TEXT"
        --notes "$NOTES"
        --source-file "$SOURCE_FILE"
    )
    if [[ -n "${SHOGUN_MEMORY_DB:-}" ]]; then
        python3 "$MEMORY_DB_LIVE_INSERT" "${memory_db_args[@]}" >/dev/null 2>&1 || true
    else
        python3 "$MEMORY_DB_LIVE_INSERT" "${memory_db_args[@]}" >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi
fi
