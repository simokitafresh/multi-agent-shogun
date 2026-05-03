#!/usr/bin/env bash
# test_select.sh — git diff変更ファイルから対応テストファイルを特定
# affected_tests.sh のpre-push向け変種:
#   - 未知ファイルはWARN+スキップ (フォールバック全テスト実行なし)
#   - マッピングなしでも exit 0 (呼び出し元が空出力を判断)
#
# Usage: bash scripts/test_select.sh [file1] [file2] ...
#   引数なし: git diff (staged+unstaged) の変更ファイルから自動検出
#   引数あり: 指定ファイルの影響テストを特定
#
# Output (stdout): 影響テストファイルのリスト (1行1ファイル、batsに直接渡せる形式)
# Output (stderr): WARN/INFO メッセージ
# Exit: 0=正常

set -eo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$REPO_ROOT/tests/unit"

# --- 変更ファイル取得 ---
if [ $# -gt 0 ]; then
    CHANGED_FILES=("$@")
else
    mapfile -t CHANGED_FILES < <(
        cd "$REPO_ROOT"
        { git diff --name-only 2>/dev/null; git diff --cached --name-only 2>/dev/null; } | sort -u
    )
fi

if [ ${#CHANGED_FILES[@]} -eq 0 ]; then
    echo "[test_select] No changed files detected" >&2
    exit 0
fi

# --- テストマッピング構築 (3層マッチング) ---
declare -A TEST_MAP  # script_path → test_file(s)

# L1: 命名規則マッチ (test_foo.bats → scripts/foo.sh)
for test_file in "$TEST_DIR"/test_*.bats; do
    [ -f "$test_file" ] || continue
    base=$(basename "$test_file" .bats | sed 's/^test_//')
    for candidate in \
        "scripts/${base}.sh" \
        "scripts/gates/${base}.sh" \
        "scripts/gates/gate_${base}.sh" \
        "scripts/lib/${base}.sh" \
        "lib/${base}.sh"; do
        if [ -f "$REPO_ROOT/$candidate" ]; then
            TEST_MAP["$candidate"]+="$test_file "
        fi
    done
done

# L2: テスト内のsource/bash解析 (静的grep)
for test_file in "$TEST_DIR"/test_*.bats; do
    [ -f "$test_file" ] || continue
    while IFS= read -r script_ref; do
        script_base=$(echo "$script_ref" | sed 's|.*[/]||' | sed 's/["\x27]//g')
        [ -z "$script_base" ] && continue
        while IFS= read -r found; do
            rel_path="${found#"$REPO_ROOT"/}"
            TEST_MAP["$rel_path"]+="$test_file "
        done < <(find "$REPO_ROOT/scripts" "$REPO_ROOT/lib" -name "$script_base" 2>/dev/null)
    done < <(grep -ohE '(source|bash|\.) +[^ ]+\.sh' "$test_file" 2>/dev/null | sed 's/^[^ ]* //')
done

# --- 影響テスト特定 ---
declare -A AFFECTED_TESTS
UNMATCHED=()

for changed in "${CHANGED_FILES[@]}"; do
    matched=0

    # 変更ファイル自体がテストなら直接追加
    if [[ "$changed" == tests/unit/test_*.bats ]]; then
        full_path="$REPO_ROOT/$changed"
        if [ -f "$full_path" ]; then
            AFFECTED_TESTS["$full_path"]=1
            matched=1
        fi
        continue
    fi

    # L1+L2: マップから検索
    for key in "${!TEST_MAP[@]}"; do
        if [[ "$changed" == *"$key"* ]] || [[ "$key" == *"$(basename "$changed")"* ]]; then
            for tf in ${TEST_MAP[$key]}; do
                AFFECTED_TESTS["$tf"]=1
                matched=1
            done
        fi
    done

    # L3: scripts/gates/ 変更→gate関連テスト全体
    if [[ "$changed" == scripts/gates/* ]]; then
        gate_base=$(basename "$changed" .sh)
        for tf in "$TEST_DIR"/test_gate*.bats "$TEST_DIR"/test_"${gate_base}"*.bats; do
            if [ -f "$tf" ]; then
                AFFECTED_TESTS["$tf"]=1
                matched=1
            fi
        done
    fi

    # deploy_task.sh変更→全deploy_taskテスト
    if [[ "$changed" == *deploy_task* ]]; then
        for tf in "$TEST_DIR"/test_deploy_task*.bats; do
            if [ -f "$tf" ]; then
                AFFECTED_TESTS["$tf"]=1
                matched=1
            fi
        done
    fi

    # cmd_complete_gate.sh変更→全cmd_complete_gateテスト
    if [[ "$changed" == *cmd_complete_gate* ]]; then
        for tf in "$TEST_DIR"/test_cmd_complete_gate*.bats; do
            if [ -f "$tf" ]; then
                AFFECTED_TESTS["$tf"]=1
                matched=1
            fi
        done
    fi

    # cmd_save.sh変更→全cmd_saveテスト
    if [[ "$changed" == *cmd_save* ]]; then
        for tf in "$TEST_DIR"/test_cmd_save*.bats; do
            if [ -f "$tf" ]; then
                AFFECTED_TESTS["$tf"]=1
                matched=1
            fi
        done
    fi

    # report_field_set.sh変更→deploy_task+gate_report_formatテスト(間接依存)
    if [[ "$changed" == *report_field_set* ]]; then
        for tf in "$TEST_DIR"/test_deploy_task*.bats "$TEST_DIR"/test_gate_report_format*.bats; do
            if [ -f "$tf" ]; then
                AFFECTED_TESTS["$tf"]=1
                matched=1
            fi
        done
    fi

    # マッチなし → WARN対象
    if [ "$matched" -eq 0 ]; then
        UNMATCHED+=("$changed")
    fi
done

# --- 未知ファイルのWARN (全テスト実行しない) ---
for f in "${UNMATCHED[@]}"; do
    echo "[test_select] WARN: no test mapping for '${f}' — skipped" >&2
done
if [ ${#UNMATCHED[@]} -gt 0 ] && [ ${#AFFECTED_TESTS[@]} -eq 0 ]; then
    echo "[test_select] WARN: all changed files have no test mapping — skipping test run" >&2
fi

# --- 結果出力 ---
if [ ${#AFFECTED_TESTS[@]} -eq 0 ]; then
    exit 0
fi

count=${#AFFECTED_TESTS[@]}
total=$(find "$TEST_DIR" -maxdepth 1 -name 'test_*.bats' 2>/dev/null | wc -l)
echo "[test_select] Affected: ${count}/${total} test files" >&2
printf '%s\n' "${!AFFECTED_TESTS[@]}" | sort
