#!/usr/bin/env bash
# cmd_publish.sh — 起票サイクルの機械的ステップを一括実行
#
# Usage:
#   bash scripts/cmd_publish.sh <cmd_id> "<message>"
#
# Example:
#   bash scripts/cmd_publish.sh cmd_2405 "cmd_2405を書いた。GSL2 bunshin。配備せよ。"
#
# 実行内容:
#   1. status: on_hold なら draft に戻す (yaml_field_set)
#   2. cmd_save.sh でgate検証 → BLOCK/FAILなら停止
#   3. status: draft → status: pending に昇格 (yaml_field_set)
#   4. cmd_delegate.sh で委任 (status=pending検証 + inbox_write + delegated_at)
#
# 設計思想:
#   将軍の「書く」(創造的) と「通す」(機械的) を分離。
#   このスクリプトは「通す」側を自動化し、品質ステップの抜け漏れを構造的に排除する。
#   cmd_save.sh BLOCKで全体が止まるため、gateを迂回することは不可能。

set -euo pipefail

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
PROJECT_DIR="${_self%/scripts/cmd_publish.sh}"

if [ $# -lt 2 ]; then
    echo "Usage: bash scripts/cmd_publish.sh <cmd_id> \"<message>\"" >&2
    exit 1
fi

CMD_ID="$1"
MESSAGE="$2"
SHOGUN_TO_KARO="${CMD_PUBLISH_QUEUE_FILE:-$PROJECT_DIR/queue/shogun_to_karo.yaml}"
QUALITY_LOG_FILE="${CMD_PUBLISH_QUALITY_LOG_FILE:-$PROJECT_DIR/logs/cmd_design_quality.yaml}"
LAST_CMD_FILE="${CMD_PUBLISH_LAST_CMD_FILE:-$PROJECT_DIR/queue/cmd_save_last_cmd.txt}"
SHOGUN_LESSONS_FILE="${CMD_PUBLISH_SHOGUN_LESSONS_FILE:-$PROJECT_DIR/projects/infra/lessons_shogun.yaml}"
SHOGUN_LESSON_LIMIT="${CMD_PUBLISH_SHOGUN_LESSON_LIMIT:-35}"
CMD_SAVE_SCRIPT="${CMD_PUBLISH_CMD_SAVE_SCRIPT:-$PROJECT_DIR/scripts/cmd_save.sh}"
CMD_DELEGATE_SCRIPT="${CMD_PUBLISH_CMD_DELEGATE_SCRIPT:-$PROJECT_DIR/scripts/cmd_delegate.sh}"

source "$PROJECT_DIR/scripts/lib/yaml_field_set.sh"

count_active_shogun_lessons() {
    [[ -f "$SHOGUN_LESSONS_FILE" ]] || {
        echo 0
        return 0
    }
    grep -c '^- id:' "$SHOGUN_LESSONS_FILE" 2>/dev/null || echo 0
}

count_cmd_save_blocks_for_cmd() {
    local target_cmd_id="${1:-}"
    [[ -n "$target_cmd_id" && -f "$QUALITY_LOG_FILE" ]] || {
        echo 0
        return 0
    }

    CMD_PUBLISH_TARGET_CMD_ID="$target_cmd_id" \
    CMD_PUBLISH_QUALITY_LOG="$QUALITY_LOG_FILE" \
    python3 - <<'PY'
import os
import yaml

cmd_id = os.environ.get("CMD_PUBLISH_TARGET_CMD_ID", "")
log_path = os.environ.get("CMD_PUBLISH_QUALITY_LOG", "")
if not cmd_id or not log_path or not os.path.exists(log_path):
    print(0)
    raise SystemExit(0)

with open(log_path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

entries = (data.get("entries") or []) if isinstance(data, dict) else []
print(sum(
    1
    for entry in entries
    if isinstance(entry, dict)
    and entry.get("cmd_id") == cmd_id
    and entry.get("gate_result") == "BLOCK"
    and entry.get("source") == "cmd_save"
))
PY
}

shogun_lesson_exists_for_cmd() {
    local source_cmd_id="${1:-}"
    [[ -n "$source_cmd_id" && -f "$SHOGUN_LESSONS_FILE" ]] || return 1

    if grep -qE "^[[:space:]]+source_cmd:[[:space:]]*['\"]?${source_cmd_id}['\"]?" "$SHOGUN_LESSONS_FILE" 2>/dev/null; then
        return 0
    fi
    grep -qF "$source_cmd_id" "$SHOGUN_LESSONS_FILE" 2>/dev/null
}

run_publish_preflight() {
    local lesson_count lesson_threshold prev_cmd_id prev_block_count

    lesson_count="$(count_active_shogun_lessons)"
    [[ "$lesson_count" =~ ^[0-9]+$ ]] || lesson_count=0
    lesson_threshold=$((SHOGUN_LESSON_LIMIT - 2))
    if (( lesson_count >= lesson_threshold )); then
        echo "BLOCK: lessons_shogun.yaml が ${lesson_count}件。cmd_publish前に空きを2件以上確保せよ(上限${SHOGUN_LESSON_LIMIT}件)。" >&2
        echo "  解消: 既存LSを統合し、件数を${lesson_threshold}件未満にしてから再実行。" >&2
        echo "  参考: bash scripts/lesson_write_shogun.sh --supersedes LS旧 LS新 \"統合理由\"" >&2
        return 1
    fi

    [[ -f "$LAST_CMD_FILE" ]] || return 0
    prev_cmd_id="$(tr -d '[:space:]' < "$LAST_CMD_FILE" 2>/dev/null || true)"
    [[ -n "$prev_cmd_id" && "$prev_cmd_id" != "$CMD_ID" ]] || return 0

    prev_block_count="$(count_cmd_save_blocks_for_cmd "$prev_cmd_id")"
    [[ "$prev_block_count" =~ ^[0-9]+$ ]] || prev_block_count=0
    (( prev_block_count > 0 )) || return 0
    shogun_lesson_exists_for_cmd "$prev_cmd_id" && return 0

    echo "BLOCK: 前${prev_cmd_id}で${prev_block_count}回BLOCKされたが教訓未記録。cmd_publish前にlesson_write_shogun.shで記録せよ。" >&2
    echo "  例: bash scripts/lesson_write_shogun.sh \"${prev_cmd_id}のBLOCK教訓\" \"BLOCK理由: ... 原因: ... 修正: ...\" ${prev_cmd_id} \"gate/hook等の強制策\"" >&2
    return 1
}

# --- Step 1: cmd_save.sh gate検証 ---
echo "=== [0/3] cmd_publish pre-flight: $CMD_ID ==="
run_publish_preflight

# --- Step 0.5: on_hold → draft 復帰 ---
promoted_from_on_hold=false
current_status=$(_yaml_field_get_in_block "$SHOGUN_TO_KARO" "$CMD_ID" "status" 2>/dev/null) || {
    echo "ERROR: $CMD_ID not found in shogun_to_karo.yaml" >&2
    exit 1
}

if [ "$current_status" = "on_hold" ]; then
    yaml_field_set "$SHOGUN_TO_KARO" "$CMD_ID" "status" "draft" || {
        echo "ERROR: failed to set status=draft for $CMD_ID" >&2
        exit 1
    }
    echo "OK: $CMD_ID on_hold → draft"
    promoted_from_on_hold=true
fi

echo "=== [1/3] cmd_save.sh gate検証: $CMD_ID ==="
if ! bash "$CMD_SAVE_SCRIPT" "$CMD_ID"; then
    if [ "$promoted_from_on_hold" = true ]; then
        yaml_field_set "$SHOGUN_TO_KARO" "$CMD_ID" "status" "on_hold" || {
            echo "ERROR: failed to rollback status=on_hold for $CMD_ID" >&2
            exit 1
        }
        echo "ROLLBACK: $CMD_ID draft → on_hold"
    fi
    echo "BLOCK: cmd_save.sh failed for $CMD_ID. 修正してから再実行せよ。" >&2
    exit 1
fi

# --- Step 2: draft → pending 昇格 ---
echo "=== [2/3] pending昇格: $CMD_ID ==="
# 現在のstatusを確認
current_status=$(_yaml_field_get_in_block "$SHOGUN_TO_KARO" "$CMD_ID" "status" 2>/dev/null) || {
    echo "ERROR: $CMD_ID not found in shogun_to_karo.yaml" >&2
    exit 1
}

if [ "$current_status" = "pending" ] || [ "$current_status" = "delegated" ]; then
    echo "SKIP: $CMD_ID is already $current_status"
elif [ "$current_status" = "draft" ]; then
    yaml_field_set "$SHOGUN_TO_KARO" "$CMD_ID" "status" "pending" || {
        echo "ERROR: failed to set status=pending for $CMD_ID" >&2
        exit 1
    }
    echo "OK: $CMD_ID draft → pending"
else
    echo "ERROR: $CMD_ID status is '$current_status', expected 'draft'" >&2
    exit 1
fi

# --- Step 3: cmd_delegate.sh 委任 ---
echo "=== [3/3] cmd_delegate.sh 委任: $CMD_ID ==="
bash "$CMD_DELEGATE_SCRIPT" "$CMD_ID" "$MESSAGE"
