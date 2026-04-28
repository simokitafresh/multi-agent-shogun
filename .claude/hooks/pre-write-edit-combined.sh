#!/usr/bin/env bash
# Combined Write/Edit PreToolUse guard: config-guard + read-tracker + report-deny + workaround-deny
# cmd_1661: 4 hooks → 1 script. Eliminates 3 bash startup costs (~60ms each).
set -eu

payload="$(cat 2>/dev/null || true)"
case "$payload" in
    *[![:space:]]*) ;;
    *) exit 0 ;;
esac

# Fast-path: only process Write/Edit
case "$payload" in
    *'"Write"'*|*'"Edit"'*) ;;
    *) exit 0 ;;
esac

emit_deny() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
}

emit_context() {
    printf '%s' "$1" | jq -Rs '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":.}}'
}

# Single jq call to extract tool_name and file_path
_parsed="$(printf '%s' "$payload" | jq -r '[(.tool_name // .toolName // ""), ((.tool_input // .toolInput // {}) | .file_path // .filePath // .path // "")] | @tsv' 2>/dev/null)" || exit 0
tool_name="${_parsed%%	*}"
file_path="${_parsed#*	}"

[[ "$tool_name" != "Write" && "$tool_name" != "Edit" ]] && exit 0
[[ -z "$file_path" ]] && exit 0

# === Guard 0: shogun_to_karo.yaml起票前確認+リスト形式BLOCK ===
if [[ "$file_path" == *'/queue/shogun_to_karo.yaml' ]]; then
    # Guard 0a: リスト形式(- id: cmd_)をBLOCK。正しくは辞書形式(  cmd_XXXX:)
    _stk_content=""
    if [[ "$tool_name" == "Edit" ]]; then
        _stk_content="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .new_string // ""' 2>/dev/null)" || true
    elif [[ "$tool_name" == "Write" ]]; then
        _stk_content="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .content // ""' 2>/dev/null)" || true
    fi
    if printf '%s' "$_stk_content" | grep -qE '^\s*-\s+id:\s+cmd_'; then
        emit_deny "BLOCK: shogun_to_karo.yamlのcmdはリスト形式(- id: cmd_XXX)禁止。辞書形式(  cmd_XXX:)で書け。archive済みcmdを参照せよ(LS-A04(13))"
        exit 1
    fi
    if [[ "$tool_name" == "Edit" ]]; then
        emit_context "起票前確認5問:
1. 対象現物を確認したか？
2. 既存代替で足りないことを確認したか？
3. cmd_save.sh関連チェック名を確認したか？
4. project=dm-signalでcommandにgrid_search/walk_forwardを含む場合、ACにrun_077またはl1_alm_wf_engineのフルパスを含めたか？(LS023/LS027: 研究道具チェック累計昇格)
5. titleにパリティ/新規作成/new_fileを含まないか？diagnosisにもトリガーワードが残っていないか？(LS026/LS028: タイトル/diagnosis偽陽性)"
    fi
    exit 0
fi

# === Guard 1: config-guard (protected config files) ===
case "${file_path##*/}" in
    pyproject.toml|.eslintrc|.eslintrc.*|eslint.config*|biome.json|.prettierrc|.prettierrc.*|tsconfig.json|.ruff.toml|setup.cfg)
        emit_deny "ERROR: ${file_path##*/} is a protected config file.\\nWHY: Linter/formatter configs must not be modified to suppress violations.\\nFIX: Fix the code that triggered the violation, not the linter config."
        exit 1
        ;;
esac

# === Guard 2: read-tracker (Write/Edit must be preceded by Read) ===
# queue/tasks/*.yaml → unconditional deny
case "$file_path" in
    */queue/tasks/*.yaml)
        emit_deny "queue/tasks/*.yamlはWrite/Editで直接書くな。状態更新→bash scripts/lib/yaml_field_set.sh queue/tasks/{name}.yaml task {field} {value}。新規配備→deploy_task.sh。"
        exit 1
        ;;
    */queue/reports/*.yaml)
        emit_deny "queue/reports/*.yamlはWrite/Editで直接書くな。report_field_set.shを使え。"
        exit 1
        ;;
esac

# Check read log for existing files
if [ -f "$file_path" ]; then
    agent_id="$(tmux display-message -t "${TMUX_PANE:-}" -p '#{@agent_id}' 2>/dev/null || echo 'unknown')"
    [[ -z "$agent_id" ]] && agent_id="unknown"
    LOG_FILE="/tmp/claude_read_log_${agent_id}.txt"
    if ! { [ -f "$LOG_FILE" ] && grep -qFx "$file_path" "$LOG_FILE" 2>/dev/null; }; then
        emit_deny "このファイルはまだReadされていません。先にReadツールで読んでからWrite/Editしてください。"
        exit 1
    fi
fi

# === Guard 3: report-deny (Edit/Write to report YAML) ===
if [[ "$file_path" =~ queue/reports/[^/]*_report_[^/]*\.yaml$ ]]; then
    emit_deny "BLOCKED: 報告YAMLへの直接Edit/Write禁止。\\n対象: $file_path\\nWHY: report_field_set.sh経由でのみ更新可。flock排他制御+構造保全のため。\\nFIX: bash scripts/report_field_set.sh $file_path <dot.notation.key> <value>\\n例: bash scripts/report_field_set.sh $file_path result.summary 検証完了\\n例: bash scripts/report_field_set.sh $file_path binary_checks.AC1 [check: 確認内容, result: yes]\\n例: bash scripts/report_field_set.sh $file_path verdict PASS"
    exit 1
fi

# === Guard 4: workaround-deny (Edit/Write to karo_workarounds.yaml) ===
if [[ "$file_path" == *'logs/karo_workarounds.yaml' ]]; then
    emit_deny "BLOCKED: karo_workarounds.yamlへの直接Edit/Write禁止。\\nWHY: karo_workaround_log.sh経由でのみ記録可。ALERTメカニズム(3件同一カテゴリでntfy通知)が発火するために必須。\\nWA記録: bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> <修正内容> <根本原因>"
    exit 1
fi

# === Guard 5: lessons.yaml tags直接Edit禁止 (LK052: 同期不整合防止) ===
if [[ "$tool_name" == "Edit" && "$file_path" == *'/lessons.yaml' ]]; then
    old_string="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .old_string // ""' 2>/dev/null)" || true
    if [[ "$old_string" == *'tags:'* ]]; then
        emit_deny "BLOCKED: lessons.yamlのtags直接Edit禁止。\\nWHY: lessons.md←→lessons.yaml同期不整合が発生する(LK052実証済み)。\\nFIX: bash scripts/lesson_write.sh <project_id> --retag <lesson_id> --new-tags \\\"tag1,tag2\\\""
        exit 1
    fi
fi

# === Guard 6: lessons_shogun.yaml肥大化防止 (v2統合後: 上限35件) ===
# 件数が増えないEdit(既存エントリ修正・統合による削減)は許可する
if [[ "$file_path" == *'lessons_shogun.yaml' ]]; then
    _ls_count=$(grep -c '^- id:' "$file_path" 2>/dev/null || echo 0)
    if [ "$_ls_count" -ge 35 ]; then
        _new_string="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .new_string // ""' 2>/dev/null)" || true
        _old_string="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .old_string // ""' 2>/dev/null)" || true
        _new_ids=$(echo "$_new_string" | grep -c '^- id:' 2>/dev/null || echo 0)
        _old_ids=$(echo "$_old_string" | grep -c '^- id:' 2>/dev/null || echo 0)
        if [ "$_new_ids" -gt "$_old_ids" ]; then
            emit_deny "BLOCKED: lessons_shogun.yaml ${_ls_count}件(上限35件)。\\nWHY: 肥大化防止(v1: 97件→v2統合で21件に圧縮)。\\nFIX: 既存教訓を統合・パターン昇格してから追加せよ。\\n参考: docs/research/lessons_shogun_v1_archive.md"
            exit 1
        fi
    fi
fi

# === Guard 7: lessons_karo.yaml肥大化防止 (v2統合後: 上限35件) ===
# 件数が増えないEdit(既存エントリ修正・統合による削減)は許可する
if [[ "$file_path" == *'lessons_karo.yaml' ]]; then
    _lk_count=$(grep -c '^- id:' "$file_path" 2>/dev/null || echo 0)
    if [ "$_lk_count" -ge 35 ]; then
        _new_string="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .new_string // ""' 2>/dev/null)" || true
        _old_string="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .old_string // ""' 2>/dev/null)" || true
        _new_ids=$(echo "$_new_string" | grep -c '^- id:' 2>/dev/null || echo 0)
        _old_ids=$(echo "$_old_string" | grep -c '^- id:' 2>/dev/null || echo 0)
        if [ "$_new_ids" -gt "$_old_ids" ]; then
            emit_deny "BLOCKED: lessons_karo.yaml ${_lk_count}件(上限35件)。\\nWHY: 肥大化防止(v1: 92件→v2統合で22件に圧縮)。\\nFIX: 既存教訓を統合・パターン昇格してから追加せよ。\\n参考: docs/research/lessons_karo_v1_archive.md"
            exit 1
        fi
    fi
fi

# === Guard 8: lessons_gunshi.yaml肥大化防止 (上限35件) ===
# 件数が増えないEdit(既存エントリ修正・統合による削減)は許可する
if [[ "$file_path" == *'lessons_gunshi.yaml' ]]; then
    _lg_count=$(grep -c '^- id:' "$file_path" 2>/dev/null || echo 0)
    if [ "$_lg_count" -ge 35 ]; then
        _new_string="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .new_string // ""' 2>/dev/null)" || true
        _old_string="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .old_string // ""' 2>/dev/null)" || true
        _new_ids=$(echo "$_new_string" | grep -c '^- id:' 2>/dev/null || echo 0)
        _old_ids=$(echo "$_old_string" | grep -c '^- id:' 2>/dev/null || echo 0)
        if [ "$_new_ids" -gt "$_old_ids" ]; then
            emit_deny "BLOCKED: lessons_gunshi.yaml ${_lg_count}件(上限35件)。\\nWHY: 肥大化防止。\\nFIX: 既存教訓を統合・パターン昇格してから追加せよ。"
            exit 1
        fi
    fi
fi

exit 0
