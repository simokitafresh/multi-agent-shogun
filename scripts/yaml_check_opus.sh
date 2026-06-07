#!/usr/bin/env bash
# yaml_check_opus.sh — YAML整合性チェック (cmd_317 R2 Opus実装)
# Usage: bash scripts/yaml_check_opus.sh <yaml_file>
# task形式(queue/tasks/*.yaml)とreport形式(queue/reports/*.yaml)を自動判定し、
# 必須フィールドの存在+型チェックを行う。

set -uo pipefail

# ── 定数 ──
readonly PASS="PASS"
readonly FAIL="FAIL"

# ── 引数チェック ──
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <yaml_file>"
    echo "  yaml_file: queue/tasks/*.yaml or queue/reports/*.yaml"
    exit 1
fi

TARGET="$1"

if [[ ! -f "$TARGET" ]]; then
    echo "[$FAIL] File not found: $TARGET"
    exit 1
fi

# ── ファイルを1回読み込み(全grep→bash正規表現マッチでsubprocess廃止) ──
# mapfileで行配列+join文字列の両方を用意(~40-50 subprocess → 0)
_yco_content=""
while IFS= read -r _yco_line || [[ -n "$_yco_line" ]]; do
    _yco_content+="${_yco_line}"$'\n'
done < "$TARGET"
_yco_lines_str="$_yco_content"

# ── 結果カウンタ ──
violations=0
warnings=0
declare -a violation_details=()
declare -a warning_details=()

add_violation() {
    violations=$((violations + 1))
    violation_details+=("  [VIOLATION] $1")
}

add_warning() {
    warnings=$((warnings + 1))
    warning_details+=("  [WARNING] $1")
}

# ── フィールド存在チェック (インデント考慮) ──
# bash ERE: [[ "$_yco_content" =~ pattern ]] — subprocess不要
check_field() {
    local pattern="$1"
    local name="$2"
    if [[ ! "$_yco_content" =~ $pattern ]]; then
        add_violation "Missing required field: $name"
        return 1
    fi
    return 0
}

# ── 配列フィールドチェック ──
check_array_field() {
    local field_pattern="$1"
    local name="$2"

    if [[ ! "$_yco_content" =~ $field_pattern ]]; then
        add_violation "Missing required array field: $name"
        return 1
    fi

    # マッチした行を抽出(行ループ — bash組込み, subprocess不要)
    local line="" line_num=0 found_num=0
    local _ln=0
    while IFS= read -r _l; do
        ((_ln++)) || true
        if [[ "$_l" =~ $field_pattern ]] && [[ "$found_num" -eq 0 ]]; then
            line="$_l"
            line_num="$_ln"
            found_num=1
        fi
    done <<< "$_yco_content"

    # field: [] 形式
    if [[ "$line" =~ \[\] ]]; then
        return 0
    fi

    # field: (値なし) → 次行を確認
    if [[ "$line" =~ :[[:space:]]*$ ]]; then
        local next_line=""
        local _ln2=0
        while IFS= read -r _l2; do
            ((_ln2++)) || true
            if [[ "$_ln2" -eq $(( line_num + 1 )) ]]; then
                next_line="$_l2"
                break
            fi
        done <<< "$_yco_content"
        if [[ "$next_line" =~ ^[[:space:]]*-[[:space:]] ]]; then
            return 0
        fi
        add_warning "Array field '$name' has no entries and is not empty array []"
        return 0
    fi

    # field: value (インライン値=型エラーの可能性)
    if [[ "$line" =~ :[[:space:]]+[^\[] ]] && [[ ! "$line" =~ :[[:space:]]*$ ]]; then
        add_warning "Array field '$name' appears to have a scalar value instead of array"
    fi

    return 0
}

# ── boolean フィールドチェック ──
check_boolean_field() {
    local field_pattern="$1"
    local name="$2"

    if [[ ! "$_yco_content" =~ $field_pattern ]]; then
        add_violation "Missing required boolean field: $name"
        return 1
    fi

    # bash変数展開でgrep+sed+trパイプを廃止
    local value="" matched_line=""
    while IFS= read -r _l; do
        if [[ "$_l" =~ $field_pattern ]]; then
            matched_line="$_l"
            break
        fi
    done <<< "$_yco_content"
    # "  found: true" → "true"
    value="${matched_line##*: }"
    value="${value//[[:space:]]/}"

    if [[ "$value" != "true" && "$value" != "false" ]]; then
        add_violation "Boolean field '$name' has non-boolean value: '$value'"
        return 1
    fi
    return 0
}

# ── 形式判定 ──
detect_format() {
    if [[ "$_yco_content" =~ (^|$'\n')task:[[:space:]]*($'\n'|$) ]]; then
        echo "task"
        return
    fi
    if [[ "$_yco_content" =~ (^|$'\n')worker_id:[[:space:]] ]]; then
        echo "report"
        return
    fi
    echo "unknown"
}

# ── task形式の検証 ──
validate_task() {
    echo "Format: task"
    echo "---"

    check_field $'(^|\n)[[:space:]]+task_id:' "task.task_id"
    check_field $'(^|\n)[[:space:]]+parent_cmd:' "task.parent_cmd"
    check_field $'(^|\n)[[:space:]]+task_type:' "task.task_type"
    check_field $'(^|\n)[[:space:]]+status:' "task.status"
    check_field $'(^|\n)[[:space:]]+command:' "task.command"

    if [[ ! "$_yco_content" =~ (^|$'\n')[[:space:]]+project: ]]; then
        add_warning "Optional field missing: task.project"
    fi
    if [[ ! "$_yco_content" =~ (^|$'\n')[[:space:]]+target_path: ]]; then
        add_warning "Optional field missing: task.target_path"
    fi

    check_array_field $'(^|\n)[[:space:]]+acceptance_criteria:' "task.acceptance_criteria"

    if [[ ! "$_yco_content" =~ (^|$'\n')[[:space:]]+related_lessons: ]]; then
        add_warning "Optional array field missing: task.related_lessons"
    fi
    if [[ ! "$_yco_content" =~ (^|$'\n')[[:space:]]+constraints: ]]; then
        add_warning "Optional array field missing: task.constraints"
    fi

    # task_type値チェック(bash変数展開でgrep+sed+tr廃止)
    local task_type="" _tl=""
    while IFS= read -r _tl; do
        if [[ "$_tl" =~ ^[[:space:]]+task_type: ]]; then
            task_type="${_tl##*task_type:}"
            task_type="${task_type//[[:space:]\"\']/}"
            break
        fi
    done <<< "$_yco_content"
    if [[ -n "$task_type" ]]; then
        case "$task_type" in
            impl|implement|review|recon|test|fix|design|refactor|deploy)
                ;;
            *)
                add_warning "Unusual task_type value: '$task_type' (expected: impl/implement/review/recon/test/fix/design/refactor/deploy)"
                ;;
        esac
    fi

    # status値チェック
    local status="" _sl=""
    while IFS= read -r _sl; do
        if [[ "$_sl" =~ ^[[:space:]]+status: ]]; then
            status="${_sl##*status:}"
            status="${status//[[:space:]\"\']/}"
            break
        fi
    done <<< "$_yco_content"
    if [[ -n "$status" ]]; then
        case "$status" in
            assigned|acknowledged|in_progress|done|blocked|cancelled|pending|completed)
                ;;
            *)
                add_warning "Unusual status value: '$status' (expected: assigned/acknowledged/in_progress/done/blocked/cancelled/pending)"
                ;;
        esac
    fi
}

# ── report形式の検証 ──
validate_report() {
    echo "Format: report"
    echo "---"

    check_field $'(^|\n)worker_id:' "worker_id"
    check_field $'(^|\n)task_id:' "task_id"
    check_field $'(^|\n)parent_cmd:' "parent_cmd"
    check_field $'(^|\n)timestamp:' "timestamp"
    check_field $'(^|\n)status:' "status"

    check_field $'(^|\n)result:' "result"
    if [[ "$_yco_content" =~ (^|$'\n')result: ]]; then
        if [[ ! "$_yco_content" =~ (^|$'\n')[[:space:]]+summary: ]]; then
            add_violation "Missing required field: result.summary"
        fi
    fi

    check_field $'(^|\n)lesson_candidate:' "lesson_candidate"
    if [[ "$_yco_content" =~ (^|$'\n')lesson_candidate: ]]; then
        check_boolean_field $'(^|\n)[[:space:]]+found:' "lesson_candidate.found"
    fi

    check_field $'(^|\n)skill_candidate:' "skill_candidate"
    if [[ "$_yco_content" =~ (^|$'\n')skill_candidate: ]]; then
        check_boolean_field $'(^|\n)[[:space:]]+found:' "skill_candidate.found"
    fi

    check_field $'(^|\n)decision_candidate:' "decision_candidate"
    if [[ "$_yco_content" =~ (^|$'\n')decision_candidate: ]]; then
        check_boolean_field $'(^|\n)[[:space:]]+found:' "decision_candidate.found"
    fi

    if [[ ! "$_yco_content" =~ (^|$'\n')lesson_referenced: ]]; then
        add_warning "Optional field missing: lesson_referenced"
    fi
}

# ── メイン ──
echo "========================================"
echo "YAML Integrity Check (Opus)"
echo "File: $TARGET"
echo "========================================"

format=$(detect_format)

case "$format" in
    task)
        validate_task
        ;;
    report)
        validate_report
        ;;
    unknown)
        echo "[$FAIL] Cannot determine format. Expected 'task:' (task format) or 'worker_id:' (report format) at root level."
        exit 1
        ;;
esac

# ── 結果出力 ──
echo ""
if [[ $violations -gt 0 ]]; then
    echo "Result: [$FAIL] — $violations violation(s), $warnings warning(s)"
    echo ""
    echo "Violations:"
    for v in "${violation_details[@]}"; do
        echo "$v"
    done
else
    echo "Result: [$PASS] — 0 violations, $warnings warning(s)"
fi

if [[ $warnings -gt 0 ]]; then
    echo ""
    echo "Warnings:"
    for w in "${warning_details[@]}"; do
        echo "$w"
    done
fi

echo ""
echo "========================================"

# 終了コード: violation=1, warning-only=0
if [[ $violations -gt 0 ]]; then
    exit 1
fi
exit 0
