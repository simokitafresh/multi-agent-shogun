#!/usr/bin/env bash
# semantic-links: [[テスト品質統合フレームワーク]]
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
declare -A SCRIPT_PATHS_BY_BASENAME
# perf: hash set for O(1) script existence check (replaces 805 NTFS -f stat calls in L1)
declare -A SCRIPT_EXISTS

# perf: basename subshell → bash param expansion (saves 246 subprocess forks on NTFS)
# perf: find → git ls-files (git index経由でNTFS I/O回避: 117ms → 37ms)
while IFS= read -r rel_path; do
    script_base="${rel_path##*/}"
    SCRIPT_PATHS_BY_BASENAME["$script_base"]+="$rel_path "
    SCRIPT_EXISTS["$rel_path"]=1
done < <(git -C "$REPO_ROOT" ls-files -- 'scripts/' 'lib/' 2>/dev/null | grep '\.sh$')

# L1: 命名規則マッチ (test_foo.bats → scripts/foo.sh)
# perf: basename+sed subshell → bash param expansion (saves 161 subprocess forks × 2)
# perf: -f stat check → hash set lookup (saves ~805 NTFS stat calls)
for test_file in "$TEST_DIR"/test_*.bats; do
    [ -f "$test_file" ] || continue
    _b="${test_file##*/}"; base="${_b%.bats}"; base="${base#test_}"
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

# L2: テスト内のsource/bash解析 — single grep -rH pass
# perf: replaces 161×grep + 507×(echo|sed|sed) with one process (~13s → ~0.3s)
# perf: grep -rH → git grep (git index経由でNTFS I/O回避: 875ms → 299ms)
while IFS= read -r line; do
    test_file="$REPO_ROOT/${line%%:*}"
    match="${line#*:}"
    script_ref="${match#* }"      # strip "source " / "bash " / ". " prefix
    script_base="${script_ref##*/}"
    script_base="${script_base//\"/}"
    script_base="${script_base//\'/}"
    [ -z "$script_base" ] && continue
    for rel_path in ${SCRIPT_PATHS_BY_BASENAME[$script_base]:-}; do
        [ -n "$rel_path" ] || continue
        TEST_MAP["$rel_path"]+="$test_file "
    done
done < <(git -C "$REPO_ROOT" grep -H -oE '(source|bash|\.) +[^ ]+\.sh' -- 'tests/unit/test_*.bats' 2>/dev/null)

# --- 影響テスト特定 ---
declare -A AFFECTED_TESTS
UNMATCHED=()

add_test_if_exists() {
    local tf
    for tf in "$@"; do
        if [ -f "$tf" ]; then
            AFFECTED_TESTS["$tf"]=1
            matched=1
        fi
    done
}

for changed in "${CHANGED_FILES[@]}"; do
    matched=0
    # perf: pre-compute basename once (replaces $(basename "$changed") subshell per key in inner loop)
    ch_base="${changed##*/}"

    # 変更ファイル自体がテストなら直接追加
    if [[ "$changed" == tests/unit/test_*.bats ]]; then
        full_path="$REPO_ROOT/$changed"
        if [ -f "$full_path" ]; then
            AFFECTED_TESTS["$full_path"]=1
            matched=1
        fi
        continue
    fi

    # skills/*/SKILL.md は実行コードではなくCodex/Claudeの手順文書。
    # 個別テストが存在しないため、既知のテスト不要対象としてWARNなしでスキップする。
    if [[ "$changed" == skills/*/SKILL.md ]]; then
        matched=1
        continue
    fi

    # context/*.md changes affect context freshness and Vercel-style reference gates.
    # They are documentation, but not test-free: stale metadata or broken links can
    # break startup/completion gates, so select the focused context gate tests.
    if [[ "$changed" == context/*.md ]]; then
        for tf in \
            "$TEST_DIR"/test_context_freshness_check.bats \
            "$TEST_DIR"/test_gate_context_freshness.bats \
            "$TEST_DIR"/test_gate_vercel_phase.bats; do
            if [ -f "$tf" ]; then
                AFFECTED_TESTS["$tf"]=1
                matched=1
            fi
        done
    fi

    # docs/rule/*.md は運用ルールの正本。実行コードではないが、索引/参照層の
    # ドリフトはgate品質に影響するため、未知ファイルWARNではなく焦点テストへ送る。
    if [[ "$changed" == docs/rule/*.md ]]; then
        for tf in \
            "$TEST_DIR"/test_semantic_index_update.bats \
            "$TEST_DIR"/test_context_freshness_check.bats; do
            if [ -f "$tf" ]; then
                AFFECTED_TESTS["$tf"]=1
                matched=1
            fi
        done
    fi

    # docs/research/*.md は設計・分析の保存先。実行コードではないが、
    # context索引やsemantic indexから参照されるため、未知ファイルWARNではなく
    # 参照/索引の軽量テストへ送る。
    if [[ "$changed" == docs/research/*.md ]]; then
        for tf in \
            "$TEST_DIR"/test_semantic_index_update.bats \
            "$TEST_DIR"/test_gate_vercel_phase.bats; do
            if [ -f "$tf" ]; then
                AFFECTED_TESTS["$tf"]=1
                matched=1
            fi
        done
    fi

    # 軍師instruction正本はCLI選択・軍師gate・semantic索引に影響する。
    if [[ "$changed" == instructions/gunshi.md ]]; then
        for tf in \
            "$TEST_DIR"/test_cli_adapter.bats \
            "$TEST_DIR"/test_gate_gunshi_cs_checklist.bats \
            "$TEST_DIR"/test_semantic_index_update.bats; do
            if [ -f "$tf" ]; then
                AFFECTED_TESTS["$tf"]=1
                matched=1
            fi
        done
    fi

    # L1+L2: マップから検索
    for key in "${!TEST_MAP[@]}"; do
        if [[ "$changed" == *"$key"* ]] || [[ "$key" == *"$ch_base"* ]]; then
            for tf in ${TEST_MAP[$key]}; do
                AFFECTED_TESTS["$tf"]=1
                matched=1
            done
        fi
    done

    # .claude/hooks/ 変更→hookベース名でテスト検索
    if [[ "$changed" == .claude/hooks/* ]]; then
        hook_base=$(basename "$changed" .sh | sed 's/^pre-/pre_/;s/^post-/post_/;s/-/_/g')
        for tf in "$TEST_DIR"/test_"${hook_base}"*.bats "$TEST_DIR"/test_pre_bash*.bats; do
            if [ -f "$tf" ]; then
                AFFECTED_TESTS["$tf"]=1
                matched=1
            fi
        done
    fi

    # scripts/hooks/ 変更→hookベース名でテスト検索(.claude/hooks/と同構造)
    if [[ "$changed" == scripts/hooks/* ]]; then
        hook_base="${changed##*/}"
        hook_base="${hook_base%.sh}"; hook_base="${hook_base%.py}"
        hook_base="${hook_base//-/_}"
        for tf in "$TEST_DIR"/test_"${hook_base}"*.bats "$TEST_DIR"/test_hook_dispatchers*.bats; do
            if [ -f "$tf" ]; then
                AFFECTED_TESTS["$tf"]=1
                matched=1
            fi
        done
    fi

    # L3: scripts/gates/ 変更→直接テスト。
    # 旧実装は単一gate変更でも test_gate*.bats + test_cmd_complete_gate*.bats を
    # 全選択し、pre-pushが30秒を超えた。startup系テストは子gateをmockするため、
    # 子gate実装変更の検証にはならない。
    if [[ "$changed" == scripts/gates/* ]]; then
        gate_file="${changed##*/}"
        gate_base="${gate_file%.sh}"

        add_test_if_exists "$TEST_DIR"/test_"${gate_base}"*.bats

        if rg -qF "$gate_file" "$REPO_ROOT/scripts/cmd_complete_gate.sh" 2>/dev/null; then
            add_test_if_exists "$TEST_DIR"/test_cmd_complete_gate*.bats
        fi

        case "$gate_file" in
            gate_report_format.sh|gate_report_autofix.sh|gate_dc_duplicate.sh|gate_diagnose_check.sh)
                add_test_if_exists \
                    "$TEST_DIR"/test_cmd_complete_gate*.bats \
                    "$TEST_DIR"/test_gate_small_consolidated.bats
                ;;
        esac
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

    # memory_db_import.py / memory_db_query.sh / semantic_search.sh 変更→関連テスト
    if [[ "$changed" == *memory_db_import* ]] || [[ "$changed" == *memory_db_query* ]] || [[ "$changed" == *semantic_search* ]]; then
        for tf in "$TEST_DIR"/test_memory_db*.bats "$TEST_DIR"/test_semantic*.bats "$TEST_DIR"/test_cmd_quality_memory_db*.bats; do
            if [ -f "$tf" ]; then
                AFFECTED_TESTS["$tf"]=1
                matched=1
            fi
        done
    fi

    # causal_index.sh変更→Guard18 backlink context tests。
    if [[ "$changed" == *causal_index.sh ]]; then
        add_test_if_exists "$TEST_DIR"/test_write_edit_combined_hooks.bats
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

    # L4: ベース名部分一致フォールバック (test_foo*.bats for scripts/foo*.sh)
    if [ "$matched" -eq 0 ]; then
        script_stem=$(basename "$changed" .sh | sed 's/_[a-z]*$//')  # karo_workaround_log → karo_workaround
        if [ -n "$script_stem" ]; then
            for tf in "$TEST_DIR"/test_"${script_stem}"*.bats; do
                if [ -f "$tf" ]; then
                    AFFECTED_TESTS["$tf"]=1
                    matched=1
                fi
            done
        fi
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
