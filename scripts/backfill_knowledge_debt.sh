#!/bin/bash
# backfill_knowledge_debt.sh — 既存の知識債務(stale cmd status + 未追跡PD)を一掃するワンショットスクリプト
# Usage: bash scripts/backfill_knowledge_debt.sh [--dry-run|--execute]
# --dry-run (デフォルト): 変更予定を表示するのみ
# --execute: 実変更を適用

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
YAML_FILE="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
PD_FILE="$SCRIPT_DIR/queue/pending_decisions.yaml"
GATES_DIR="$SCRIPT_DIR/queue/gates"
TASKS_DIR="$SCRIPT_DIR/queue/tasks"

MODE="${1:---dry-run}"

if [[ "$MODE" != "--dry-run" && "$MODE" != "--execute" ]]; then
    echo "Usage: bash scripts/backfill_knowledge_debt.sh [--dry-run|--execute]" >&2
    exit 1
fi

echo "========================================="
echo "  backfill_knowledge_debt.sh"
echo "  Mode: $MODE"
echo "  $(date '+%Y-%m-%dT%H:%M:%S')"
echo "========================================="
echo ""

# ─── (a) Stale cmd検出+修正 ───
echo "=== (a) Stale cmd status検出 ==="

stale_count=0
stale_details=""
pd_count=0
pd_ids=""

analysis_output=""
if ! analysis_output=$(YAML_FILE="$YAML_FILE" PD_FILE="$PD_FILE" GATES_DIR="$GATES_DIR" TASKS_DIR="$TASKS_DIR" python3 - <<'PY' 2>&1
import os
import sys
import re
from pathlib import Path

skip_statuses = {"completed", "done", "superseded", "halted"}
yaml_file = Path(os.environ["YAML_FILE"])
pd_file = Path(os.environ["PD_FILE"])
gates_dir = Path(os.environ["GATES_DIR"])
tasks_dir = Path(os.environ["TASKS_DIR"])

def unquote(value):
    value = value.strip()
    if value and value[0] in "'\"" and value[-1:] == value[0]:
        return value[1:-1]
    return value

def iter_command_statuses(path):
    in_commands = False
    cid = ""
    status = ""
    with path.open(encoding="utf-8") as f:
        for line in f:
            if line.startswith("commands:"):
                in_commands = True
                continue
            if not in_commands:
                continue
            match = re.match(r"^  ([A-Za-z0-9_.-]+):\s*$", line)
            if match:
                if cid:
                    yield cid, status
                cid = match.group(1)
                status = ""
                continue
            if cid:
                status_match = re.match(r"^    status:\s*(.*?)\s*$", line)
                if status_match:
                    status = unquote(status_match.group(1))
        if cid:
            yield cid, status

def iter_task_parent_types(path):
    parent_cmd = ""
    task_type = ""
    with path.open(encoding="utf-8") as f:
        for line in f:
            parent_match = re.match(r"^  parent_cmd:\s*(.*?)\s*$", line)
            if parent_match:
                parent_cmd = unquote(parent_match.group(1))
                continue
            type_match = re.match(r"^  task_type:\s*(.*?)\s*$", line)
            if type_match:
                task_type = unquote(type_match.group(1))
    if parent_cmd:
        return parent_cmd, task_type
    return "", ""

def iter_untracked_pds(path):
    current_id = ""
    status = ""
    has_context_synced = False

    def flush():
        if current_id and status == "resolved" and not has_context_synced:
            return current_id
        return ""

    with path.open(encoding="utf-8") as f:
        for line in f:
            id_match = re.match(r"^- id:\s*(.*?)\s*$", line)
            if id_match:
                pd_id = flush()
                if pd_id:
                    yield pd_id
                current_id = unquote(id_match.group(1))
                status = ""
                has_context_synced = False
                continue
            if current_id:
                status_match = re.match(r"^  status:\s*(.*?)\s*$", line)
                if status_match:
                    status = unquote(status_match.group(1))
                    continue
                if re.match(r"^  context_synced:\s*", line):
                    has_context_synced = True
        pd_id = flush()
        if pd_id:
            yield pd_id

try:
    candidates = []
    for cid, status in iter_command_statuses(yaml_file):
        if not cid or status in skip_statuses:
            continue
        gate_dir = gates_dir / cid
        if not gate_dir.is_dir():
            continue
        candidates.append((cid, status, gate_dir))

    task_types_by_cmd = {}
    if candidates and tasks_dir.is_dir():
        candidate_ids = {cid for cid, _, _ in candidates}
        for task_path in tasks_dir.glob("*.yaml"):
            try:
                parent_cmd, task_type = iter_task_parent_types(task_path)
            except Exception as exc:
                print(f"WARN|TASK_PARSE|{task_path}|{exc}")
                continue
            if parent_cmd not in candidate_ids:
                continue
            task_types_by_cmd.setdefault(parent_cmd, []).append((task_type, str(task_path)))

    for cid, status, gate_dir in candidates:
        gates = ["archive", "lesson"]
        has_recon = False
        has_implement = False
        for task_type, task_path in task_types_by_cmd.get(cid, []):
            if task_type == "recon":
                has_recon = True
            elif task_type in ("implement", "impl"):
                has_implement = True
            elif task_type == "review":
                pass
            else:
                print(f"WARN|UNKNOWN_TASK_TYPE|{task_type}|{task_path}")
        if has_recon:
            gates.append("report_merge")
        if has_implement:
            gates.append("review_gate")
        if all((gate_dir / f"{gate}.done").is_file() for gate in gates):
            print(f"STALE|{cid}|{status}|{' '.join(gates)}")

    if pd_file.is_file():
        for pd_id in iter_untracked_pds(pd_file):
            print(f"PD|{pd_id}")
    else:
        print("INFO|PD_MISSING")
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PY
); then
    echo "  YAML parse error: $analysis_output"
    echo ""
else
    while IFS='|' read -r record_type field1 field2 field3; do
        case "$record_type" in
            STALE)
            cmd_id="$field1"
            cmd_status="$field2"
            all_gates="$field3"
            stale_count=$((stale_count + 1))
            stale_details="${stale_details}  ${cmd_id} | ${cmd_status} | completed\n"
            echo "  STALE: ${cmd_id} | current=${cmd_status} | should_be=completed | gates=[${all_gates}] all done"

            if [ "$MODE" = "--execute" ]; then
                # yaml.dump禁止(CLAUDE.md): yaml_field_set.shでフィールド単体更新
                if bash "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh" "$YAML_FILE" "${cmd_id}" "status" "completed"; then
                    echo "    FIXED: ${cmd_id} → completed"
                else
                    echo "    ERROR: yaml_field_set失敗 (${cmd_id})" >&2
                fi
            fi
            ;;
            PD)
            pd_id="$field1"
            pd_ids="${pd_ids}${pd_id}"$'\n'
            ;;
            WARN)
            if [ "$field1" = "UNKNOWN_TASK_TYPE" ]; then
                echo "[WARN] Unknown task_type: '$field2' in $field3" >&2
            else
                echo "[WARN] $field1 $field2 $field3" >&2
            fi
            ;;
            INFO)
            if [ "$field1" = "PD_MISSING" ]; then
                pd_missing=true
            fi
            ;;
        esac
    done <<< "$analysis_output"
fi

echo ""
echo "  Stale cmd count: ${stale_count}"
echo ""

# ─── (b) 未追跡PD検出+修正 ───
echo "=== (b) 未追跡PD(context_synced欠落)検出 ==="

if [ "${pd_missing:-false}" = "true" ]; then
    echo "  pending_decisions.yaml not found"
elif [ -n "$pd_ids" ]; then
    while IFS= read -r pd_id; do
        [ -z "$pd_id" ] && continue
        pd_count=$((pd_count + 1))
        echo "  UNTRACKED: ${pd_id} | status=resolved | context_synced=missing → false"

        if [ "$MODE" = "--execute" ]; then
            # yaml.dump禁止(CLAUDE.md): yaml_field_set.shでフィールド単体更新
            if bash "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh" "$PD_FILE" "${pd_id}" "context_synced" "false"; then
                echo "    FIXED: ${pd_id} → context_synced: false"
            else
                echo "    ERROR: yaml_field_set失敗 (${pd_id})" >&2
            fi
        fi
    done <<< "$pd_ids"
fi

echo ""
echo "  Untracked PD count: ${pd_count}"
echo ""

# ─── (c) 結果サマリ ───
echo "========================================="
echo "  Summary"
echo "========================================="
echo "  Stale cmd count:    ${stale_count}"
echo "  Untracked PD count: ${pd_count}"
echo "  Mode:               ${MODE}"
if [ "$MODE" = "--dry-run" ]; then
    echo ""
    echo "  (dry-run: no changes made. Use --execute to apply fixes)"
else
    echo ""
    echo "  (execute: all fixes applied)"
fi
echo "========================================="
