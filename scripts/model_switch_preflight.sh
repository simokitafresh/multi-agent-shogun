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
source "$SCRIPT_DIR/scripts/lib/cli_lookup.sh"

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

# 全忍者名リスト
ALL_NINJAS=(sasuke kirimaru hayate kagemaru hanzo saizo kotaro tobisaru)

# --- Check 1: ハードコードgrepスキャン ---

check_hardcodes() {
    echo -e "\n${BOLD}=== Check 1: ハードコードgrepスキャン ===${NC}"

    # SSOT・自分自身・CLI固有ドキュメントを除外するフィルタ
    # grep --exclude はWSL2環境で不安定なため、パイプフィルタで確実に除外
    local exclude_filter='cli_lookup\.sh|cli_profiles\.yaml|settings\.yaml|model_switch_preflight\.sh|cli_specific/|generated/'

    # 検索パターン
    local patterns=(
        'is_codex'
        'sasuke.*codex'
        'kirimaru.*codex'
        'gpt-5\.'
        'claude-opus'
        'claude-sonnet'
        'claude-haiku'
    )

    # 検索対象ディレクトリ
    local search_dirs=(
        "$SCRIPT_DIR/scripts/"
        "$SCRIPT_DIR/instructions/"
        "$SCRIPT_DIR/config/"
        "$SCRIPT_DIR/context/"
    )

    local total_hits=0
    local all_results=""

    for pattern in "${patterns[@]}"; do
        local found
        found=$(grep -rn \
            --include='*.sh' --include='*.yaml' --include='*.md' \
            "$pattern" "${search_dirs[@]}" 2>/dev/null \
            | grep -Ev "$exclude_filter" || true)

        if [[ -n "$found" ]]; then
            all_results+="  Pattern: ${pattern}\n${found}\n\n"
            local count
            count=$(echo "$found" | wc -l)
            total_hits=$((total_hits + count))
        fi
    done

    if [[ $total_hits -eq 0 ]]; then
        result_pass "ハードコード 0件"
    else
        result_fail "ハードコード ${total_hits}件検出"
        echo -e "$all_results"
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

    # settings.yaml の全agentを検証
    local check_result
    check_result=$(python3 -c "
import yaml, sys

with open('${settings_file}') as f:
    settings = yaml.safe_load(f) or {}
with open('${profiles_file}') as f:
    profiles_cfg = yaml.safe_load(f) or {}

cli = settings.get('cli', {})
agents = cli.get('agents', {}) if isinstance(cli, dict) else {}
default_type = cli.get('default', 'claude') if isinstance(cli, dict) else 'claude'
valid_profiles = list((profiles_cfg.get('profiles', {})).keys())

errors = []
warnings = []

for name, cfg in agents.items():
    if not isinstance(cfg, dict):
        errors.append(f'{name}: 設定が辞書型でない')
        continue

    # tier チェック
    tier = cfg.get('tier', '')
    if not tier:
        warnings.append(f'{name}: tier フィールド未定義')

    # type チェック（省略時はdefault使用 — 正当）
    agent_type = cfg.get('type', default_type)
    if agent_type not in valid_profiles:
        errors.append(f'{name}: type \"{agent_type}\" は cli_profiles.yaml に未定義 (有効: {valid_profiles})')

if errors:
    for e in errors:
        print(f'ERROR:{e}')
if warnings:
    for w in warnings:
        print(f'WARN:{w}')
if not errors and not warnings:
    print('OK:全agent定義が正常')
" 2>&1)

    local has_error=false
    local has_warn=false

    while IFS= read -r line; do
        if [[ "$line" == ERROR:* ]]; then
            result_fail "${line#ERROR:}"
            has_error=true
        elif [[ "$line" == WARN:* ]]; then
            result_warn "${line#WARN:}"
            has_warn=true
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
        status=$(python3 -c "
import yaml
with open('${task_file}') as f:
    data = yaml.safe_load(f) or {}
task = data.get('task', data)
print(task.get('status', 'unknown'))
" 2>/dev/null || echo "parse_error")

        case "$status" in
            idle|done|completed)
                result_pass "${ninja}: status=${status}（安全）"
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

    # cli_lookup.shをsourceすべきスクリプト一覧
    local dependent_scripts=(
        "scripts/ninja_monitor.sh"
        "scripts/inbox_watcher.sh"
    )

    local all_ok=true

    for script in "${dependent_scripts[@]}"; do
        local full_path="$SCRIPT_DIR/$script"
        if [[ ! -f "$full_path" ]]; then
            result_warn "${script}: ファイルが見つからない"
            all_ok=false
            continue
        fi

        # cli_lookup.sh を source しているか確認
        if grep -q 'source.*cli_lookup\.sh' "$full_path" 2>/dev/null; then
            echo -e "  ${GREEN}OK${NC}: ${script} — cli_lookup.sh を source 済み"
        else
            result_fail "${script}: cli_lookup.sh を source していない"
            all_ok=false
            continue
        fi

        # 旧式のインライン関数定義が残っていないか
        local inline_funcs
        inline_funcs=$(grep -n 'is_codex\s*()' "$full_path" 2>/dev/null || true)
        if [[ -n "$inline_funcs" ]]; then
            result_fail "${script}: インライン is_codex() 関数定義が残存"
            echo "    $inline_funcs"
            all_ok=false
        fi
    done

    if $all_ok; then
        result_pass "全依存スクリプトが cli_lookup.sh 経由"
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
