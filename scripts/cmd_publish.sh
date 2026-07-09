#!/usr/bin/env bash
# semantic-links: [[cmd設計品質ログ]]
# cmd_publish.sh — 起票サイクルの機械的ステップを一括実行
#
# Usage:
#   bash scripts/cmd_publish.sh <cmd_id> "<message>"
#
# Example:
#   bash scripts/cmd_publish.sh cmd_2405 "cmd_2405を書いた。GSL2 bunshin。配備せよ。"
#
# 実行内容:
#   1. status: on_hold は保持したまま cmd_save.sh でgate検証 → BLOCK/FAILなら停止
#   2. status: draft/on_hold → status: pending に昇格 (yaml_field_set)
#   4. cmd_delegate.sh で委任 (status=pending検証 + inbox_write + delegated_at)
#
# 設計思想:
#   将軍の「書く」(創造的) と「通す」(機械的) を分離。
#   このスクリプトは「通す」側を自動化し、品質ステップの抜け漏れを構造的に排除する。
#   cmd_save.sh BLOCKで全体が止まるため、gateを迂回することは不可能。

set -euo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: bash scripts/cmd_publish.sh <cmd_id> \"<message>\"" >&2
    exit 1
fi

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
PROJECT_DIR="${_self%/scripts/cmd_publish.sh}"

CMD_ID="$1"
MESSAGE="$2"
SHOGUN_TO_KARO="${CMD_PUBLISH_QUEUE_FILE:-$PROJECT_DIR/queue/shogun_to_karo.yaml}"
QUALITY_LOG_FILE="${CMD_PUBLISH_QUALITY_LOG_FILE:-$PROJECT_DIR/logs/cmd_design_quality.yaml}"
LAST_CMD_FILE="${CMD_PUBLISH_LAST_CMD_FILE:-$PROJECT_DIR/queue/cmd_save_last_cmd.txt}"
SHOGUN_LESSONS_FILE="${CMD_PUBLISH_SHOGUN_LESSONS_FILE:-$PROJECT_DIR/projects/infra/lessons_shogun.yaml}"
SHOGUN_LESSON_ACK_FILE="${CMD_PUBLISH_SHOGUN_LESSON_ACK_FILE:-$PROJECT_DIR/queue/shogun_lesson_ack.yaml}"
SHOGUN_LESSON_LIMIT="${CMD_PUBLISH_SHOGUN_LESSON_LIMIT:-35}"
CMD_SAVE_SCRIPT="${CMD_PUBLISH_CMD_SAVE_SCRIPT:-$PROJECT_DIR/scripts/cmd_save.sh}"
CMD_DELEGATE_SCRIPT="${CMD_PUBLISH_CMD_DELEGATE_SCRIPT:-$PROJECT_DIR/scripts/cmd_delegate.sh}"
SHOGUN_LESSON_ACK_SCRIPT="${CMD_PUBLISH_SHOGUN_LESSON_ACK_SCRIPT:-$PROJECT_DIR/scripts/shogun_lesson_ack.sh}"
CMD_PUBLISH_GIT_ROOT="${CMD_PUBLISH_GIT_ROOT:-$PROJECT_DIR}"

source "$PROJECT_DIR/scripts/lib/yaml_field_set.sh"

count_active_shogun_lessons() {
    [[ -f "$SHOGUN_LESSONS_FILE" ]] || {
        echo 0
        return 0
    }
    awk 'BEGIN { count = 0; skip = 0 } /^- id:/ { count++; skip = 0 } /superseded_by:/ { skip = 1; count-- } END { print (count > 0 ? count : 0) }' "$SHOGUN_LESSONS_FILE" 2>/dev/null || echo 0
}

count_cmd_save_blocks_for_cmd() {
    local target_cmd_id="${1:-}"
    [[ -n "$target_cmd_id" && -f "$QUALITY_LOG_FILE" ]] || {
        echo 0
        return 0
    }

    awk -v target="$target_cmd_id" '
        function strip(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            sub(/^["'\'']/, "", value)
            sub(/["'\'']$/, "", value)
            return value
        }
        function flush_entry() {
            if (cmd_id == target && gate_result == "BLOCK" && source == "cmd_save") {
                count++
            }
            cmd_id = ""
            gate_result = ""
            source = ""
        }
        BEGIN {
            count = 0
            in_entry = 0
            cmd_id = ""
            gate_result = ""
            source = ""
        }
        /^[[:space:]]*-[[:space:]]+cmd_id:[[:space:]]*/ {
            if (in_entry) {
                flush_entry()
            }
            in_entry = 1
            value = $0
            sub(/^[[:space:]]*-[[:space:]]+cmd_id:[[:space:]]*/, "", value)
            cmd_id = strip(value)
            next
        }
        in_entry && /^[[:space:]]+gate_result:[[:space:]]*/ {
            value = $0
            sub(/^[[:space:]]+gate_result:[[:space:]]*/, "", value)
            gate_result = strip(value)
            next
        }
        in_entry && /^[[:space:]]+source:[[:space:]]*/ {
            value = $0
            sub(/^[[:space:]]+source:[[:space:]]*/, "", value)
            source = strip(value)
            next
        }
        END {
            if (in_entry) {
                flush_entry()
            }
            print count
        }
    ' "$QUALITY_LOG_FILE" 2>/dev/null || echo 0
}

shogun_lesson_exists_for_cmd() {
    local source_cmd_id="${1:-}"
    [[ -n "$source_cmd_id" ]] || return 1

    if [[ -f "$SHOGUN_LESSON_ACK_FILE" ]] && grep -qE "^[[:space:]]*-[[:space:]]+cmd_id:[[:space:]]*['\"]?${source_cmd_id}['\"]?" "$SHOGUN_LESSON_ACK_FILE" 2>/dev/null; then
        return 0
    fi

    [[ -f "$SHOGUN_LESSONS_FILE" ]] || return 1

    if grep -qE "^[[:space:]]+source_cmd:[[:space:]]*['\"]?${source_cmd_id}['\"]?" "$SHOGUN_LESSONS_FILE" 2>/dev/null; then
        return 0
    fi
    grep -qE "(source_cmd|origin|detail):.*['\"]?${source_cmd_id}['\"]?([[:space:]]|$|['\"])" "$SHOGUN_LESSONS_FILE" 2>/dev/null
}

extract_nazenaze_from_cmd_yaml() {
    local yaml_file="${1:-}"
    local target_cmd="${2:-}"
    [[ -n "$target_cmd" && -f "$yaml_file" ]] || return 0

    awk -v cmd_id="$target_cmd" '
    function trim(s) { sub(/^[ \t\r\n]+/, "", s); sub(/[ \t\r\n]+$/, "", s); return s }
    function unquote(s) {
        if (length(s) >= 2) {
            if (substr(s,1,1) == "\"" && substr(s,length(s),1) == "\"") {
                s = substr(s, 2, length(s)-2)
            } else if (substr(s,1,1) == "\x27" && substr(s,length(s),1) == "\x27") {
                s = substr(s, 2, length(s)-2)
            }
        }
        return s
    }
    function leading_spaces(line,    i,cnt,c) {
        cnt = 0
        for (i = 1; i <= length(line); i++) {
            c = substr(line, i, 1)
            if (c == " ") cnt++; else break
        }
        return cnt
    }
    BEGIN { in_cmd = 0 }
    {
        stripped = $0
        sub(/^[[:space:]]*/, "", stripped)
        if (!in_cmd && stripped == cmd_id ":") {
            in_cmd = 1
            cmd_indent = leading_spaces($0)
            next
        }
        if (in_cmd) {
            if (trim($0) != "" && leading_spaces($0) <= cmd_indent) exit
            if (/nazenaze_root_cause:/) {
                value = $0
                sub(/.*nazenaze_root_cause:[[:space:]]*/, "", value)
                value = trim(unquote(value))
                if (value != "" && value != "null") print value
                exit
            }
        }
    }
    ' "$yaml_file"
}

ensure_cmd_publish_default_fields() {
    # Bug3修正: 2回の_yaml_field_get_in_blockを1回のawk走査に統合(~28ms→~14ms)
    local missing_fields
    missing_fields="$(awk -v cmd_id="$CMD_ID" '
        BEGIN { in_cmd=0; has_depends=0; has_origin=0 }
        { s=$0; sub(/^[[:space:]]*/,"",s) }
        !in_cmd && s == cmd_id ":" { in_cmd=1; next }
        in_cmd && s != "" && !/^[[:space:]]/ { exit }
        in_cmd && /depends_on:/ { has_depends=1 }
        in_cmd && /origin:/ { has_origin=1 }
        END { if(!has_depends) printf "depends_on "; if(!has_origin) printf "origin " }
    ' "$SHOGUN_TO_KARO" 2>/dev/null || true)"

    local field
    for field in $missing_fields; do
        yaml_field_set "$SHOGUN_TO_KARO" "$CMD_ID" "$field" "none" || {
            echo "ERROR: failed to set ${field}=none for $CMD_ID" >&2
            return 1
        }
        echo "OK: $CMD_ID ${field}未記入 → ${field}: none を自動挿入"
    done
}

run_cmd_save_with_block_summary() {
    local output summary_line line

    if output="$(bash "$CMD_SAVE_SCRIPT" "$CMD_ID" 2>&1)"; then
        printf '%s\n' "$output"
        return 0
    fi

    summary_line=""
    while IFS= read -r line; do
        case "$line" in
            BLOCK:*|保存確認NG:*|ERROR:*|WARNING:*)
                summary_line="$line"
                break
                ;;
        esac
    done <<< "$output"
    [ -n "$summary_line" ] || summary_line="cmd_save.sh failed for $CMD_ID"

    echo "BLOCK SUMMARY: ${summary_line}" >&2
    printf '%s\n' "$output" >&2
    return 1
}

run_publish_preflight() {
    local lesson_count lesson_threshold prev_cmd_id prev_block_count auto_ack_lesson

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

    auto_ack_lesson="${CMD_PUBLISH_DEFAULT_ACK_LESSON:-LS-A06}"
    echo "INFO: 前${prev_cmd_id}で${prev_block_count}回BLOCK — 教訓未ack検出。${auto_ack_lesson}で自動ack実行中..."
    if SHOGUN_LESSON_ACK_FILE="$SHOGUN_LESSON_ACK_FILE" \
       SHOGUN_LESSON_ACK_LESSONS_FILE="$SHOGUN_LESSONS_FILE" \
       SHOGUN_LESSON_ACK_QUALITY_LOG_FILE="$QUALITY_LOG_FILE" \
       bash "$SHOGUN_LESSON_ACK_SCRIPT" "$prev_cmd_id" "$auto_ack_lesson"; then
        echo "OK: 自動ack完了($prev_cmd_id → $auto_ack_lesson)。cmd_save.shへ進行する。"
    else
        echo "BLOCK: 自動ack失敗($prev_cmd_id → $auto_ack_lesson)。手動で実行せよ。" >&2
        echo "  例: bash scripts/lesson_write_shogun.sh \"${prev_cmd_id}のBLOCK教訓\" \"BLOCK理由: ... 原因: ... 修正: ...\" ${prev_cmd_id} \"gate/hook等の強制策\"" >&2
        echo "  既知パターンなら: bash scripts/shogun_lesson_ack.sh ${prev_cmd_id} ${auto_ack_lesson}" >&2
        return 1
    fi
}

extract_q11_evidence_paths() {
    local q11_value="${1:-}"

    [[ -n "${q11_value//[[:space:]]/}" ]] || return 0
    printf '%s\n' "$q11_value" | grep -qiE '(^|[^A-Za-z0-9_])(rg|grep)([^A-Za-z0-9_]|$)' || return 0

    printf '%s\n' "$q11_value" \
        | grep -oE '(^|[[:space:]"'\''`(])([A-Za-z0-9_.-]+/)?[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*\.(sh|py|md|yaml|yml|json|ts|tsx|js|jsx|rb|go|rs|sql|txt)' \
        | sed -E 's/^[[:space:]"'\''`(]+//' \
        | awk '!seen[$0]++'
}

get_cmd_publish_q11_value() {
    awk -v cmd_id="$CMD_ID" '
        function trim(s) {
            sub(/^[ \t\r\n]+/, "", s)
            sub(/[ \t\r\n]+$/, "", s)
            return s
        }
        function unquote(s) {
            if (length(s) >= 2) {
                if (substr(s, 1, 1) == "\"" && substr(s, length(s), 1) == "\"") {
                    s = substr(s, 2, length(s) - 2)
                    gsub(/\\"/, "\"", s)
                } else if (substr(s, 1, 1) == "'"'"'" && substr(s, length(s), 1) == "'"'"'") {
                    s = substr(s, 2, length(s) - 2)
                }
            }
            return s
        }
        function leading_spaces(line,    i,cnt,c) {
            cnt = 0
            for (i = 1; i <= length(line); i++) {
                c = substr(line, i, 1)
                if (c == " ") cnt++
                else break
            }
            return cnt
        }
        {
            stripped = $0
            sub(/^[[:space:]]*/, "", stripped)
            if (!in_cmd && stripped == cmd_id ":") {
                in_cmd = 1
                cmd_indent = leading_spaces($0)
                next
            }
            if (in_cmd) {
                indent = leading_spaces($0)
                if (trim($0) != "" && indent <= cmd_indent) {
                    exit 3
                }
                if (!in_qg && stripped == "quality_gate:") {
                    in_qg = 1
                    qg_indent = indent
                    next
                }
                if (in_qg) {
                    if (trim($0) != "" && indent <= qg_indent) {
                        in_qg = 0
                    } else if (stripped ~ /^q11_not_already_done:[[:space:]]*/) {
                        value = stripped
                        sub(/^q11_not_already_done:[[:space:]]*/, "", value)
                        print trim(unquote(value))
                        exit 0
                    }
                }
            }
        }
        END { exit 0 }
    ' "$SHOGUN_TO_KARO"
}

warn_if_q11_evidence_paths_changed() {
    local q11_value path diff_stat any_changed=false

    q11_value="$(get_cmd_publish_q11_value 2>/dev/null || true)"
    [[ -n "${q11_value//[[:space:]]/}" ]] || return 0

    if ! git -C "$CMD_PUBLISH_GIT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        return 0
    fi

    # Bug5修正: per-path git diff 2回ループ → 一括git diff 1回
    local paths_array=()
    while IFS= read -r path; do
        [[ -n "${path//[[:space:]]/}" ]] || continue
        [[ -e "$CMD_PUBLISH_GIT_ROOT/$path" ]] || continue
        paths_array+=("$path")
    done < <(extract_q11_evidence_paths "$q11_value")

    [[ ${#paths_array[@]} -gt 0 ]] || return 0

    local diff_stat
    diff_stat="$(git -C "$CMD_PUBLISH_GIT_ROOT" diff --stat HEAD -- "${paths_array[@]}" 2>/dev/null || true)"
    if [[ -n "${diff_stat//[[:space:]]/}" ]]; then
        echo "WARN: q11_not_already_done のgrep根拠ファイルに未コミット差分があります。起票時のgrep結果が陳腐化している可能性があります。" >&2
        printf '%s\n' "$diff_stat" | sed 's/^/  /' >&2
    fi
}

# --- Step 1: cmd_save.sh gate検証 ---
echo "=== [0/3] cmd_publish pre-flight: $CMD_ID ==="
run_publish_preflight

# --- Step 0.5: on_hold はcmd_save成功まで保持 ---
promoted_from_on_hold=false
current_status=$(_yaml_field_get_in_block "$SHOGUN_TO_KARO" "$CMD_ID" "status" 2>/dev/null) || {
    echo "ERROR: $CMD_ID not found in shogun_to_karo.yaml" >&2
    exit 1
}

if [ "$current_status" = "on_hold" ]; then
    echo "OK: $CMD_ID on_hold保持 — cmd_save成功後にpending昇格"
    promoted_from_on_hold=true
fi

ensure_cmd_publish_default_fields

echo "=== [1/3] cmd_save.sh gate検証: $CMD_ID ==="
if ! run_cmd_save_with_block_summary; then
    [ "$promoted_from_on_hold" = true ] && echo "KEEP: $CMD_ID status=on_hold"
    echo "BLOCK: cmd_save.sh failed for $CMD_ID. 修正してから再実行せよ。" >&2
    exit 1
fi

# --- Step 1.5: nazenaze_root_cause → lesson_write_shogun.sh 強制gate ---
_nazenaze_yaml_value="$(extract_nazenaze_from_cmd_yaml "$SHOGUN_TO_KARO" "$CMD_ID" 2>/dev/null || true)"
if [[ -n "${_nazenaze_yaml_value}" ]]; then
    if ! shogun_lesson_exists_for_cmd "$CMD_ID"; then
        echo "BLOCK: ${CMD_ID}にnazenaze_root_causeが記入済みだが、lesson_write_shogun.shによる教訓記録が未実行。" >&2
        echo "  根因分析を言語化しただけでは半パイプライン。教訓を環境に埋め込め。" >&2
        echo "  例: bash scripts/lesson_write_shogun.sh \"教訓タイトル\" \"詳細\" ${CMD_ID} \"enforcement記述\"" >&2
        echo "  既知パターンなら: bash scripts/shogun_lesson_ack.sh ${CMD_ID} LS-A05" >&2
        exit 1
    fi
    echo "OK: nazenaze_root_cause検出 + lesson記録確認済み(${CMD_ID})"
fi

# --- Step 2: draft → pending 昇格 ---
echo "=== [2/3] pending昇格: $CMD_ID ==="
# current_status は Step 0.5 (L368) で取得済み。再読み不要(Bug2修正: 28ms削減)

if [ "$current_status" = "pending" ] || [ "$current_status" = "delegated" ]; then
    echo "SKIP: $CMD_ID is already $current_status"
elif [ "$current_status" = "draft" ] || [ "$current_status" = "on_hold" ]; then
    yaml_field_set "$SHOGUN_TO_KARO" "$CMD_ID" "status" "pending" || {
        echo "ERROR: failed to set status=pending for $CMD_ID" >&2
        exit 1
    }
    echo "OK: $CMD_ID ${current_status} → pending"
else
    echo "ERROR: $CMD_ID status is '$current_status', expected 'draft' or 'on_hold'" >&2
    exit 1
fi

# --- Step 3: cmd_delegate.sh 委任 ---
echo "=== [3/3] cmd_delegate.sh 委任: $CMD_ID ==="
warn_if_q11_evidence_paths_changed
bash "$CMD_DELEGATE_SCRIPT" "$CMD_ID" "$MESSAGE"
