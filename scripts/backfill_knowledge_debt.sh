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

# shogun_to_karo.yamlからcmd一覧を取得（id + status）
cmd_entries=""
if ! cmd_entries=$(YAML_FILE="$YAML_FILE" python3 - <<'PY' 2>&1
import os
import sys

import yaml

try:
    with open(os.environ["YAML_FILE"], encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    commands = data.get("commands") or []
    if not isinstance(commands, list):
        raise TypeError("commands must be a list")
    for cmd in commands:
        if not isinstance(cmd, dict):
            continue
        cid = cmd.get("id", "")
        status = cmd.get("status", "")
        print(f"{cid}|{status}")
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PY
); then
    echo "  YAML parse error: $cmd_entries"
    echo ""
else
    while IFS='|' read -r cmd_id cmd_status; do
        [ -z "$cmd_id" ] && continue

        # completed/done は対象外
        if [[ "$cmd_status" == "completed" || "$cmd_status" == "done" ]]; then
            continue
        fi

        # superseded/halted も対象外（完了ではないが別理由）
        if [[ "$cmd_status" == "superseded" || "$cmd_status" == "halted" ]]; then
            continue
        fi

        # ゲートディレクトリの存在確認
        gate_dir="$GATES_DIR/$cmd_id"
        if [ ! -d "$gate_dir" ]; then
            continue
        fi

        # 必須ゲートの確認（cmd_complete_gate.shと同じロジック）
        always_required=("archive" "lesson")
        conditional=()

        # task_type検出
        has_recon=false
        has_implement=false
        for task_file in "$TASKS_DIR"/*.yaml; do
            [ -f "$task_file" ] || continue
            if grep -q "parent_cmd: ${cmd_id}" "$task_file" 2>/dev/null; then
                ttype=$(grep 'task_type:' "$task_file" 2>/dev/null | head -1 | sed 's/.*task_type: *//' | tr -d '[:space:]')
                case "$ttype" in
                    recon) has_recon=true ;;
                    implement|impl) has_implement=true ;;
                    review) ;; # 既知の種別
                    *) echo "[WARN] Unknown task_type: '$ttype' in $task_file" >&2 ;;
                esac
            fi
        done

        if [ "$has_recon" = "true" ]; then
            conditional+=("report_merge")
        fi
        if [ "$has_implement" = "true" ]; then
            conditional+=("review_gate")
        fi

        all_gates=("${always_required[@]}" "${conditional[@]}")

        # 全ゲートが.doneか確認
        all_done=true
        for gate in "${all_gates[@]}"; do
            if [ ! -f "$gate_dir/${gate}.done" ]; then
                all_done=false
                break
            fi
        done

        if [ "$all_done" = true ]; then
            stale_count=$((stale_count + 1))
            stale_details="${stale_details}  ${cmd_id} | ${cmd_status} | completed\n"
            echo "  STALE: ${cmd_id} | current=${cmd_status} | should_be=completed | gates=[${all_gates[*]}] all done"

            if [ "$MODE" = "--execute" ]; then
                # yaml.dump禁止(CLAUDE.md): yaml_field_set.shでフィールド単体更新
                if bash "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh" "$YAML_FILE" "${cmd_id}" "status" "completed"; then
                    echo "    FIXED: ${cmd_id} → completed"
                else
                    echo "    ERROR: yaml_field_set失敗 (${cmd_id})" >&2
                fi
            fi
        fi
    done <<< "$cmd_entries"
fi

echo ""
echo "  Stale cmd count: ${stale_count}"
echo ""

# ─── (b) 未追跡PD検出+修正 ───
echo "=== (b) 未追跡PD(context_synced欠落)検出 ==="

pd_count=0

if [ ! -f "$PD_FILE" ]; then
    echo "  pending_decisions.yaml not found"
else
    # resolved PDでcontext_syncedフィールドがないものを検出
    untracked_pds=""
    if ! untracked_pds=$(PD_FILE="$PD_FILE" python3 - <<'PY' 2>&1
import os
import sys

import yaml

try:
    with open(os.environ["PD_FILE"], encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    decisions = data.get("decisions") or []
    if not isinstance(decisions, list):
        raise TypeError("decisions must be a list")
    for d in decisions:
        if not isinstance(d, dict):
            continue
        if d.get("status") == "resolved" and "context_synced" not in d:
            pd_id = d.get("id", "???")
            print(pd_id)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
PY
); then
        echo "  YAML parse error: $untracked_pds"
    elif [ -n "$untracked_pds" ]; then
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
        done <<< "$untracked_pds"
    fi
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
