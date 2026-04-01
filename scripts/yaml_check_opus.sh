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
# $1=パターン(grep正規表現), $2=フィールド名(表示用)
check_field() {
    local pattern="$1"
    local name="$2"
    if ! grep -qE "$pattern" "$TARGET"; then
        add_violation "Missing required field: $name"
        return 1
    fi
    return 0
}

# ── 配列フィールドチェック ──
# YAML配列は "field:" の次行が "- " で始まるか、"field: []" の形式
# $1=フィールド名(インデント付きgrep用), $2=表示名
check_array_field() {
    local field_pattern="$1"
    local name="$2"

    if ! grep -qE "$field_pattern" "$TARGET"; then
        add_violation "Missing required array field: $name"
        return 1
    fi

    # 値が空配列 [] か、次行に - がある場合はOK
    local line
    line=$(grep -E "$field_pattern" "$TARGET" | head -1)

    # field: [] 形式
    if echo "$line" | grep -qE '\[\]'; then
        return 0
    fi

    # field: (値なし) → 次行を確認
    if echo "$line" | grep -qE ':\s*$'; then
        local line_num
        line_num=$(grep -nE "$field_pattern" "$TARGET" | head -1 | cut -d: -f1)
        local next_line
        next_line=$(sed -n "$((line_num + 1))p" "$TARGET")
        if echo "$next_line" | grep -qE '^\s*-\s'; then
            return 0
        fi
        add_warning "Array field '$name' has no entries and is not empty array []"
        return 0
    fi

    # field: value (インライン値=型エラーの可能性)
    # Note: grep -q suppresses stdout, so piping to another grep is broken (always empty).
    # Use && with separate invocations instead.
    if echo "$line" | grep -qE ':\s+[^\[]+' && ! echo "$line" | grep -qE ':\s*$'; then
        add_warning "Array field '$name' appears to have a scalar value instead of array"
    fi

    return 0
}

# ── boolean フィールドチェック ──
check_boolean_field() {
    local field_pattern="$1"
    local name="$2"

    if ! grep -qE "$field_pattern" "$TARGET"; then
        add_violation "Missing required boolean field: $name"
        return 1
    fi

    local value
    value=$(grep -E "$field_pattern" "$TARGET" | head -1 | sed 's/.*:\s*//' | tr -d '[:space:]')

    if [[ "$value" != "true" && "$value" != "false" ]]; then
        add_violation "Boolean field '$name' has non-boolean value: '$value'"
        return 1
    fi
    return 0
}

# ── 形式判定 ──
detect_format() {
    # task形式: 最初のレベルに "task:" キーがある
    if grep -qE '^task:' "$TARGET"; then
        echo "task"
        return
    fi

    # report形式: ルートレベルに "worker_id:" がある
    if grep -qE '^worker_id:' "$TARGET"; then
        echo "report"
        return
    fi

    echo "unknown"
}

# ── task形式の検証 ──
validate_task() {
    echo "Format: task"
    echo "---"

    # 必須スカラーフィールド (task: 配下なのでインデント有)
    check_field '^\s+task_id:' "task.task_id"
    check_field '^\s+parent_cmd:' "task.parent_cmd"
    check_field '^\s+task_type:' "task.task_type"
    check_field '^\s+status:' "task.status"
    check_field '^\s+command:' "task.command"

    # 準必須スカラーフィールド (存在しなければwarning)
    if ! grep -qE '^\s+project:' "$TARGET"; then
        add_warning "Optional field missing: task.project"
    fi
    if ! grep -qE '^\s+target_path:' "$TARGET"; then
        add_warning "Optional field missing: task.target_path"
    fi

    # 配列フィールド
    check_array_field '^\s+acceptance_criteria:' "task.acceptance_criteria"

    # 準必須配列フィールド (存在しなければwarning)
    if ! grep -qE '^\s+related_lessons:' "$TARGET"; then
        add_warning "Optional array field missing: task.related_lessons"
    fi
    if ! grep -qE '^\s+constraints:' "$TARGET"; then
        add_warning "Optional array field missing: task.constraints"
    fi

    # task_type の値チェック
    local task_type
    task_type=$(grep -E '^\s+task_type:' "$TARGET" | head -1 | sed "s/.*task_type:\s*//" | tr -d '[:space:]"'"'"'')
    if [[ -n "$task_type" ]]; then
        case "$task_type" in
            impl|implement|review|recon|test|fix|design|refactor|deploy)
                ;;
            *)
                add_warning "Unusual task_type value: '$task_type' (expected: impl/implement/review/recon/test/fix/design/refactor/deploy)"
                ;;
        esac
    fi

    # status の値チェック
    local status
    status=$(grep -E '^\s+status:' "$TARGET" | head -1 | sed "s/.*status:\s*//" | tr -d '[:space:]"'"'"'')
    if [[ -n "$status" ]]; then
        case "$status" in
            assigned|acknowledged|in_progress|done|blocked|cancelled|pending)
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

    # 必須スカラーフィールド (ルートレベル)
    check_field '^worker_id:' "worker_id"
    check_field '^task_id:' "task_id"
    check_field '^parent_cmd:' "parent_cmd"
    check_field '^timestamp:' "timestamp"
    check_field '^status:' "status"

    # 必須オブジェクトフィールド
    check_field '^result:' "result"
    if grep -qE '^result:' "$TARGET"; then
        # result.summary の存在チェック
        if ! grep -qE '^\s+summary:' "$TARGET"; then
            add_violation "Missing required field: result.summary"
        fi
    fi

    check_field '^lesson_candidate:' "lesson_candidate"
    if grep -qE '^lesson_candidate:' "$TARGET"; then
        check_boolean_field '^\s+found:' "lesson_candidate.found"
    fi

    check_field '^skill_candidate:' "skill_candidate"
    if grep -qE '^skill_candidate:' "$TARGET"; then
        check_boolean_field '^\s+found:' "skill_candidate.found"
    fi

    check_field '^decision_candidate:' "decision_candidate"
    if grep -qE '^decision_candidate:' "$TARGET"; then
        check_boolean_field '^\s+found:' "decision_candidate.found"
    fi

    # lesson_referenced は配列(省略可能だがあるべき)
    if ! grep -qE '^lesson_referenced:' "$TARGET"; then
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
