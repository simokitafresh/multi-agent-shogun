#!/bin/bash
# affected_tests.sh — 変更ファイルから影響テストを自動特定
# おしお殿CoDD impact概念の将軍システム版: 変更→影響分析→最小テスト
#
# Usage: bash scripts/affected_tests.sh [file1] [file2] ...
#   引数なし: git diffの変更ファイルから自動検出
#   引数あり: 指定ファイルの影響テストを特定
#
# Output: 影響テストファイルのリスト（batsに直接渡せる形式）
# Exit: 0=影響テスト特定成功, 1=エラー

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$REPO_ROOT/tests/unit"

# --- 変更ファイル取得 ---
if [ $# -gt 0 ]; then
    CHANGED_FILES=("$@")
else
    # git diff でunstaged+staged変更を検出
    mapfile -t CHANGED_FILES < <(
        cd "$REPO_ROOT"
        { git diff --name-only 2>/dev/null; git diff --cached --name-only 2>/dev/null; } | sort -u
    )
fi

if [ ${#CHANGED_FILES[@]} -eq 0 ]; then
    echo "# No changed files detected" >&2
    echo "$TEST_DIR"  # フォールバック: 全テスト
    exit 0
fi

# --- テストマッピング構築 ---
# 戦略: 3層マッチング
#   L1: テスト名→スクリプト名の直接対応 (test_foo.bats → scripts/foo.sh)
#   L2: テスト内のsource/bash呼出しを解析 (grep)
#   L3: scripts/gates/ 配下→ gate系テスト全体

declare -A TEST_MAP  # script_basename → test_file
declare -A SCRIPT_PATHS_BY_BASENAME
declare -A SCRIPT_EXISTS

while IFS= read -r script_path; do
    script_base="${script_path##*/}"
    rel_path="${script_path#"$REPO_ROOT"/}"
    SCRIPT_PATHS_BY_BASENAME["$script_base"]+="$rel_path "
    SCRIPT_EXISTS["$rel_path"]=1
done < <(find "$REPO_ROOT/scripts" "$REPO_ROOT/lib" -name '*.sh' 2>/dev/null)

# L1: 命名規則マッチ
for test_file in "$TEST_DIR"/test_*.bats; do
    [ -f "$test_file" ] || continue
    _base_file="${test_file##*/}"
    base="${_base_file%.bats}"
    base="${base#test_}"
    # スクリプト候補
    for candidate in \
        "scripts/${base}.sh" \
        "scripts/gates/${base}.sh" \
        "scripts/gates/gate_${base}.sh" \
        "scripts/lib/${base}.sh" \
        "lib/${base}.sh"; do
        if [[ -n "${SCRIPT_EXISTS[$candidate]+x}" ]]; then
            TEST_MAP["$candidate"]+="$test_file "
        fi
    done
done

# L2: テスト内のsource/bash解析（静的grep）
while IFS= read -r line; do
    test_file="${line%%:*}"
    match="${line#*:}"
    script_ref="${match#* }"
    script_base="${script_ref##*/}"
    script_base="${script_base//\"/}"
    script_base="${script_base//\'/}"
    [ -z "$script_base" ] && continue
    for rel_path in ${SCRIPT_PATHS_BY_BASENAME[$script_base]:-}; do
        [ -n "$rel_path" ] || continue
        TEST_MAP["$rel_path"]+="$test_file "
    done
done < <(grep -rH -oE '(source|bash|\.) +[^ ]+\.sh' "$TEST_DIR"/test_*.bats 2>/dev/null)

# --- 影響テスト特定 ---
declare -A AFFECTED_TESTS

for changed in "${CHANGED_FILES[@]}"; do
    changed_base="${changed##*/}"
    # 変更ファイル自体がテストなら直接追加
    if [[ "$changed" == tests/unit/*.bats ]]; then
        full_path="$REPO_ROOT/$changed"
        [ -f "$full_path" ] && AFFECTED_TESTS["$full_path"]=1
        continue
    fi

    # L1+L2: マップから検索
    for key in "${!TEST_MAP[@]}"; do
        if [[ "$changed" == *"$key"* ]] || [[ "$key" == *"$changed_base"* ]]; then
            for tf in ${TEST_MAP[$key]}; do
                AFFECTED_TESTS["$tf"]=1
            done
        fi
    done

    # L3: scripts/gates/ 変更→gate関連テスト全体
    if [[ "$changed" == scripts/gates/* ]]; then
        gate_base=$(basename "$changed" .sh)
        for tf in "$TEST_DIR"/test_gate*.bats "$TEST_DIR"/test_"${gate_base}"*.bats; do
            [ -f "$tf" ] && AFFECTED_TESTS["$tf"]=1
        done
    fi

    # deploy_task.sh変更→全deploy_taskテスト
    if [[ "$changed" == *deploy_task* ]]; then
        for tf in "$TEST_DIR"/test_deploy_task*.bats; do
            [ -f "$tf" ] && AFFECTED_TESTS["$tf"]=1
        done
    fi

    # cmd_complete_gate.sh変更→全cmd_complete_gateテスト
    if [[ "$changed" == *cmd_complete_gate* ]]; then
        for tf in "$TEST_DIR"/test_cmd_complete_gate*.bats; do
            [ -f "$tf" ] && AFFECTED_TESTS["$tf"]=1
        done
    fi

    # cmd_save.sh変更→全cmd_saveテスト
    if [[ "$changed" == *cmd_save* ]]; then
        for tf in "$TEST_DIR"/test_cmd_save*.bats; do
            [ -f "$tf" ] && AFFECTED_TESTS["$tf"]=1
        done
    fi

    # CLAUDE.md/instructions変更→build_systemテスト
    if [[ "$changed" == CLAUDE.md ]] || [[ "$changed" == instructions/* ]]; then
        [ -f "$TEST_DIR/test_build_system.bats" ] && AFFECTED_TESTS["$TEST_DIR/test_build_system.bats"]=1
    fi
done

# --- 結果出力 ---
count=0
for _affected_test in "${!AFFECTED_TESTS[@]}"; do
    count=$((count + 1))
done

if [ "$count" -eq 0 ]; then
    echo "# No affected tests found for: ${CHANGED_FILES[*]}" >&2
    echo "# Falling back to full test suite" >&2
    echo "$TEST_DIR"
else
    total=$(find "$TEST_DIR" -maxdepth 1 -name 'test_*.bats' 2>/dev/null | wc -l)
    echo "# Affected: $count/$total test files ($(( (total - count) * 100 / total ))% skipped)" >&2
    printf '%s\n' "${!AFFECTED_TESTS[@]}" | sort
fi
