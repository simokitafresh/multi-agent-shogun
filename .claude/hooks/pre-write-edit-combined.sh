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

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PREFLIGHT_AUTOLEARN_FILE="${PREFLIGHT_AUTOLEARN_FILE:-$SCRIPT_DIR/logs/preflight_autolearn.txt}"
CMD_DESIGN_QUALITY_FILE="${CMD_DESIGN_QUALITY_FILE:-$SCRIPT_DIR/logs/cmd_design_quality.yaml}"

cmd_save_block_top3() {
    [[ -s "$CMD_DESIGN_QUALITY_FILE" ]] || return 0
    CMD_DESIGN_QUALITY_FILE="$CMD_DESIGN_QUALITY_FILE" python3 - <<'PY' 2>/dev/null || true
import collections
import os
import re
import yaml

path = os.environ.get("CMD_DESIGN_QUALITY_FILE", "")
try:
    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
except Exception:
    raise SystemExit(0)

entries = data.get("entries") or []
blocks = [
    entry for entry in entries
    if isinstance(entry, dict)
    and entry.get("source") == "cmd_save"
    and entry.get("gate_result") == "BLOCK"
][-50:]

def normalize(note):
    note = str(note or "").strip()
    if not note:
        return "notesなし"
    match = re.search(r"WARN累計昇格:\s*「([^」]+)」", note)
    if match:
        return "WARN累計昇格: " + match.group(1).strip()
    return note.split("|", 1)[0].strip()

counter = collections.Counter(normalize(entry.get("notes", "")) for entry in blocks)
for index, (pattern, count) in enumerate(counter.most_common(3), 1):
    print(f"{index}. {pattern} ({count}件)")
PY
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
    # Guard 0b: on_hold禁止。cmdは直列でdraft→publishせよ。配備順序は家老が判断する(殿裁定2026-05-03)
    if printf '%s' "$_stk_content" | grep -qE 'status:\s*on_hold'; then
        emit_deny "BLOCK: status: on_hold禁止。cmdは直列でdraft→publishせよ。配備順序の制御は家老の仕事。on_holdは将軍がステート管理を抱え込む迂回(殿裁定2026-05-03)"
        exit 1
    fi
    # Guard 0c: preflight_autolearnで昇格済みのcmd本文パイプ警告をpre-writeでBLOCK。
    # cmd_save.shのcheck_cmd_text_pipe_dangerと同じ対象(purpose/command)だけを見る。
    if [[ -s "$PREFLIGHT_AUTOLEARN_FILE" ]] && grep -q 'check=check_cmd_text_pipe_danger' "$PREFLIGHT_AUTOLEARN_FILE" 2>/dev/null; then
        _cmd_text_for_pipe_check="$(printf '%s\n' "$_stk_content" | awk '
            /^[[:space:]]*purpose:[[:space:]]*/ {
                line = $0
                sub(/^[[:space:]]*purpose:[[:space:]]*/, "", line)
                print line
                next
            }
            /^[[:space:]]*command:[[:space:]]*[|>][+-]?([[:space:]]*#.*)?$/ {
                in_command = 1
                next
            }
            /^[[:space:]]*command:[[:space:]]*/ {
                line = $0
                sub(/^[[:space:]]*command:[[:space:]]*/, "", line)
                print line
                next
            }
            in_command && /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]*/ {
                in_command = 0
                next
            }
            in_command { print }
        ' || true)"
        if [[ "$_cmd_text_for_pipe_check" == *"|"* ]]; then
            emit_deny "BLOCK: cmd本文のpurpose/commandにパイプ文字(|)を検出。check_cmd_text_pipe_dangerはpreflight_autolearnで昇格済み。引用・別表現・手順分割でシェル/YAML解釈リスクを除去せよ。"
            exit 1
        fi
    fi
    if [[ "$tool_name" == "Edit" ]]; then
        _dynamic_checks=""
        if [[ -s "$PREFLIGHT_AUTOLEARN_FILE" ]]; then
            _dynamic_checks="$(tail -n 10 "$PREFLIGHT_AUTOLEARN_FILE" 2>/dev/null | awk '
                NF {
                    check = ""; count = ""; warn = ""
                    for (i = 1; i <= NF; i++) {
                        if ($i ~ /^check=/) { check = substr($i, 7) }
                        else if ($i ~ /^count=/) { count = substr($i, 7) }
                        else if ($i ~ /^warn=/) { warn = substr($i, 6) }
                    }
                    if (check != "") {
                        seen[check] = check " count=" count " warn=" warn
                    }
                }
                END {
                    for (check in seen) {
                        print "- " seen[check]
                    }
                }
            ')"
        fi
        _checklist="起票前確認8問:
1. 対象現物を確認したか？
2. 既存代替で足りないことを確認したか？
3. cmd_save.sh関連チェック名を確認したか？
4. project=dm-signalでcommandにgrid_search/walk_forwardを含む場合、ACにrun_077またはl1_alm_wf_engineのフルパスを含めたか？(LS023/LS027: 研究道具チェック累計昇格)
5. titleにパリティ/新規作成/new_fileを含まないか？diagnosisにもトリガーワードが残っていないか？(LS026/LS028: タイトル/diagnosis偽陽性)
6. command欄のステップ数≦AC数か？各ステップの成果物がACに対応しているか？(command_steps_over_ac 10回累計BLOCK)
7. CMD全文に目視確認/セルフレビュー/自問を含まないか？「現物確認」「grep確認」等の客観表現に置換せよ(self_reread 4回累計BLOCK)
8. q11にgrep/rg結果(コマンド+件数)を含めたか？特にスクリプト変更cmdはgate/hook追加と判定される(q11_existing_alternative_verification 17回累計BLOCK)"
        if [[ -n "$_dynamic_checks" ]]; then
            _checklist="${_checklist}

動的追加確認(preflight_autolearn):
${_dynamic_checks}"
        fi
        _cmd_save_block_top3="$(cmd_save_block_top3)"
        if [[ -n "$_cmd_save_block_top3" ]]; then
            _checklist="${_checklist}

直近cmd_save BLOCK TOP3(cmd_design_quality.yaml直近50件):
${_cmd_save_block_top3}"
        fi
        emit_context "$_checklist"
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
