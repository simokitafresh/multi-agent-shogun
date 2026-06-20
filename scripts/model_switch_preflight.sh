#!/bin/bash
# model_switch_preflight.sh — モデル切替前の事前確認スクリプト
# cmd_151 Stage 4: モデル切替チェックリスト + preflight script
#
# Usage: bash scripts/model_switch_preflight.sh [target_agent]
#   target_agent を省略すると全忍者を対象にチェックする
#
# 4つのチェック:
#   1. ハードコードgrepスキャン — モデル名直書きの検出
#   2. settings.yamlスキーマ検証 — agent定義の整合性
#   3. 対象忍者のタスク状態確認 — 切替安全性
#   4. watcher/monitor依存チェック — cli_lookup.sh経由の確認
#
# 終了コード: 0=全PASS, 1=FAIL有り

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/model_family.sh"

TARGET="${1:-}"

# --- 色定義 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# --- ヘルパー ---

result_pass() {
    echo -e "  ${GREEN}PASS${NC}: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

result_fail() {
    echo -e "  ${RED}FAIL${NC}: $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

result_warn() {
    echo -e "  ${YELLOW}WARN${NC}: $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

# 全忍者名リスト（settings.yamlから動的取得 — cmd_1136）
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/agent_config.sh"
read -ra ALL_NINJAS <<< "$(get_ninja_names)"

# --- Check 1: ハードコードgrepスキャン ---

check_hardcodes() {
    echo -e "\n${BOLD}=== Check 1: ハードコードgrepスキャン ===${NC}"

    # 動的パターン: 全エージェント×非デフォルトCLI種別の直書き検出
    # settings.yaml/cli_profiles.yamlはexclude_filterで除外済み
    local _all_agents_arr
    read -ra _all_agents_arr <<< "$(get_all_agents)"
    local _agent_patterns=""
    for _agent in "${_all_agents_arr[@]}"; do
        _agent_patterns+="|${_agent}.*codex"
    done

    # 全パターンを単一正規表現に結合（11grep→1grep。WSL2 I/O 11x削減）
    local combined_pattern="(is_codex|${MODEL_FAMILY_TOKEN_GPT}-5\\.|claude-(${MODEL_FAMILY_OPUS}|${MODEL_FAMILY_TOKEN_SONNET}|${MODEL_FAMILY_HAIKU})-[0-9]${_agent_patterns})"

    local found
    found=$(rg -n \
        --glob '*.sh' --glob '*.yaml' --glob '*.md' \
        --glob '!scripts/lib/cli_lookup.sh' \
        --glob '!config/cli_profiles.yaml' \
        --glob '!config/settings.yaml' \
        --glob '!scripts/model_switch_preflight.sh' \
        --glob '!instructions/generated/**' \
        --glob '!instructions/cli_specific/**' \
        "$combined_pattern" \
        "$SCRIPT_DIR/scripts" "$SCRIPT_DIR/instructions" "$SCRIPT_DIR/config" "$SCRIPT_DIR/context" 2>/dev/null || true)

    if [[ -z "$found" ]]; then
        result_pass "ハードコード 0件"
    else
        local total_hits
        total_hits=$(echo "$found" | wc -l)
        result_fail "ハードコード ${total_hits}件検出"
        echo -e "$found"
    fi
}

# --- Check 2: settings.yamlスキーマ検証 ---

check_settings_schema() {
    echo -e "\n${BOLD}=== Check 2: settings.yamlスキーマ検証 ===${NC}"

    local settings_file="$SCRIPT_DIR/config/settings.yaml"
    local profiles_file="$SCRIPT_DIR/config/cli_profiles.yaml"

    if [[ ! -f "$settings_file" ]]; then
        result_fail "settings.yaml が見つからない: $settings_file"
        return
    fi
    if [[ ! -f "$profiles_file" ]]; then
        result_fail "cli_profiles.yaml が見つからない: $profiles_file"
        return
    fi

    # settings.yaml の全agentを検証（単純な固定schemaのみ確認するためawkでPython起動を回避）
    local check_result
    check_result=$(awk '
        FNR == 1 { file_index++ }
        file_index == 1 {
            if ($0 == "cli:") { in_cli=1; next }
            if (in_cli && $0 ~ /^  default:[[:space:]]*/) {
                default_type=$0
                sub(/^  default:[[:space:]]*/, "", default_type)
                gsub(/["'\''[:space:]\r]/, "", default_type)
                next
            }
            if (in_cli && $0 == "  agents:") { in_agents=1; next }
            if (in_agents && $0 ~ /^    [a-z][a-z_0-9]*:[[:space:]]*$/) {
                name=$0
                sub(/^[[:space:]]+/, "", name)
                sub(/:[[:space:]]*$/, "", name)
                agent_order[++agent_count]=name
                agent_type[name]=""
                next
            }
            if (in_agents && $0 ~ /^      type:[[:space:]]*/) {
                v=$0
                sub(/^      type:[[:space:]]*/, "", v)
                gsub(/["'\''[:space:]\r]/, "", v)
                agent_type[name]=v
                next
            }
            if (in_agents && $0 ~ /^[^[:space:]]/) { in_agents=0; in_cli=0 }
            next
        }
        file_index == 2 {
            if ($0 == "profiles:") { in_profiles=1; next }
            if (in_profiles && $0 ~ /^  [a-z][a-z_0-9]*:[[:space:]]*$/) {
                p=$0
                sub(/^[[:space:]]+/, "", p)
                sub(/:[[:space:]]*$/, "", p)
                profiles[p]=1
            }
        }
        END {
            if (default_type == "") default_type="claude"
            profile_list=""
            for (p in profiles) profile_list = profile_list (profile_list ? ", " : "") p
            for (i=1; i<=agent_count; i++) {
                name=agent_order[i]
                t=agent_type[name] != "" ? agent_type[name] : default_type
                if (!(t in profiles)) {
                    print "ERROR:" name ": type \"" t "\" は cli_profiles.yaml に未定義 (有効: [" profile_list "])"
                    errors++
                }
            }
            if (!errors) print "OK:全agent定義が正常"
        }
    ' "$settings_file" "$profiles_file" 2>&1)

    while IFS= read -r line; do
        if [[ "$line" == ERROR:* ]]; then
            result_fail "${line#ERROR:}"
        elif [[ "$line" == WARN:* ]]; then
            result_warn "${line#WARN:}"
        elif [[ "$line" == OK:* ]]; then
            result_pass "${line#OK:}"
        fi
    done <<< "$check_result"
}

# --- Check 3: 対象忍者のタスク状態確認 ---

check_task_status() {
    echo -e "\n${BOLD}=== Check 3: 対象忍者のタスク状態確認 ===${NC}"

    local targets=()
    if [[ -n "$TARGET" ]]; then
        targets=("$TARGET")
    else
        targets=("${ALL_NINJAS[@]}")
    fi

    for ninja in "${targets[@]}"; do
        local task_file="$SCRIPT_DIR/queue/tasks/${ninja}.yaml"
        if [[ ! -f "$task_file" ]]; then
            result_pass "${ninja}: タスクファイルなし（idle）"
            continue
        fi

        local status
        # awkでYAML statusを取得（python3起動コスト回避）
        status=$(awk '
            /^task:/ { in_task=1; next }
            in_task && /^  status:/ { print $2; exit }
            /^status:/ { print $2; exit }
        ' "$task_file" 2>/dev/null | head -1) || status="parse_error"
        [[ -z "$status" ]] && status="parse_error"

        case "$status" in
            idle|done|completed)
                result_pass "${ninja}: status=${status}（安全）"
                ;;
            acknowledged)
                result_warn "${ninja}: status=${status}（タスク認知済み・未着手 — 切替前に完了または中止を確認）"
                ;;
            assigned|in_progress)
                result_warn "${ninja}: status=${status}（タスク実行中 — 切替前に完了を待て）"
                ;;
            parse_error)
                result_warn "${ninja}: タスクYAMLパース失敗"
                ;;
            *)
                result_warn "${ninja}: status=${status}（不明）"
                ;;
        esac
    done
}

# --- Check 4: watcher/monitor依存チェック ---

check_cli_lookup_usage() {
    echo -e "\n${BOLD}=== Check 4: watcher/monitor依存チェック ===${NC}"

    # 動的検出: cli_lookup.shをsourceしている全スクリプトを発見
    # cli_lookup.sh自身・本スクリプト・テスト・一時ファイルを除外
    local exclude_pattern='cli_lookup\.sh|model_switch_preflight\.sh|\.tmp/|tests/'
    local dependent_scripts=()
    local inline_by_script=""

    # git grep 1回でsource検出と旧式inline関数検出を同時に行う（per-file grepを削減）
    local grep_result
    grep_result=$(git -C "$SCRIPT_DIR" grep -n -E 'source.*cli_lookup\.sh|is_codex[[:space:]]*\(\)' -- '*.sh' 2>/dev/null || true)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local git_path="${line%%:*}"
        [[ "$git_path" =~ $exclude_pattern ]] && continue
        if [[ "$line" == *source*cli_lookup.sh* ]]; then
            dependent_scripts+=("$git_path")
        elif [[ "$line" =~ is_codex[[:space:]]*\(\) ]]; then
            inline_by_script+="${line}"$'\n'
        fi
    done <<< "$grep_result"

    if [[ ${#dependent_scripts[@]} -eq 0 ]]; then
        result_warn "cli_lookup.sh をsourceするスクリプトが見つからない"
        return
    fi

    local all_ok=true

    for script in "${dependent_scripts[@]}"; do
        local full_path="$SCRIPT_DIR/$script"
        if [[ ! -f "$full_path" ]]; then
            result_warn "${script}: ファイルが見つからない"
            all_ok=false
            continue
        fi

        # 旧式のインライン関数定義が残っていないか
        local inline_funcs=""
        while IFS= read -r inline_line; do
            [[ "$inline_line" == "$script:"* ]] && inline_funcs+="${inline_line#"$script:"}"$'\n'
        done <<< "$inline_by_script"
        if [[ -n "$inline_funcs" ]]; then
            result_fail "${script}: インライン is_codex() 関数定義が残存"
            echo "    ${inline_funcs%$'\n'}"
            all_ok=false
        else
            result_pass "${script} — cli_lookup.sh 経由・インライン定義なし"
        fi
    done

    if $all_ok; then
        echo -e "  全依存スクリプト(${#dependent_scripts[@]}件)チェック完了"
    fi
}

# --- メイン ---

echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  モデル切替 Preflight チェック               ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"

if [[ -n "$TARGET" ]]; then
    echo -e "対象: ${BOLD}${TARGET}${NC}"
else
    echo -e "対象: ${BOLD}全忍者${NC}"
fi
echo -e "実行日時: $(date '+%Y-%m-%d %H:%M:%S')"

check_hardcodes
check_settings_schema
check_task_status
check_cli_lookup_usage

# --- サマリー ---

echo -e "\n${BOLD}=== サマリー ===${NC}"
echo -e "  ${GREEN}PASS${NC}: ${PASS_COUNT}"
echo -e "  ${RED}FAIL${NC}: ${FAIL_COUNT}"
echo -e "  ${YELLOW}WARN${NC}: ${WARN_COUNT}"

if [[ $FAIL_COUNT -gt 0 ]]; then
    echo -e "\n${RED}結果: FAIL — 切替前に上記の問題を解決せよ${NC}"
    exit 1
else
    if [[ $WARN_COUNT -gt 0 ]]; then
        echo -e "\n${YELLOW}結果: PASS（警告あり） — 警告を確認の上、切替を判断せよ${NC}"
    else
        echo -e "\n${GREEN}結果: ALL PASS — 切替可能${NC}"
    fi
    exit 0
fi
