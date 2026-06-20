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
    printf '%s\n' "$1" >&2
}

emit_context() {
    local text="$1"
    text="${text//\\/\\\\}"
    text="${text//\"/\\\"}"
    text="${text//$'\t'/\\t}"
    text="${text//$'\r'/\\r}"
    text="${text//$'\n'/\\n}"
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$text"
}

_pre_write_self="${BASH_SOURCE[0]:-$0}"
[[ "$_pre_write_self" != /* ]] && _pre_write_self="$PWD/$_pre_write_self"
SCRIPT_DIR="${_pre_write_self%/.claude/hooks/pre-write-edit-combined.sh}"
unset _pre_write_self
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

auto_q11_script_grep_results() {
    local cmd_text="$1"
    local script_paths

    script_paths="$(printf '%s\n' "$cmd_text" \
        | grep -oE '(\.claude/hooks|scripts/(gates|hooks))/[A-Za-z0-9_.-]+\.sh' \
        | sort -u || true)"
    [[ -n "$script_paths" ]] || return 0

    printf '自動grep結果(q11コピー用):\n'
    while IFS= read -r script_path; do
        [[ -n "$script_path" ]] || continue
        local count hits
        count="$(timeout 2s rg -nF "$script_path" "$SCRIPT_DIR" \
            --glob '!queue/**' \
            --glob '!logs/**' \
            --glob '!tests/test_helper/**' \
            2>/dev/null | wc -l | tr -d '[:space:]')"
        hits="$(timeout 2s rg -nF "$script_path" "$SCRIPT_DIR" \
            --glob '!queue/**' \
            --glob '!logs/**' \
            --glob '!tests/test_helper/**' \
            2>/dev/null | head -5 || true)"
        printf -- '- %s\n' "$script_path"
        printf '  command: rg -nF "%s" . --glob '"'"'!queue/**'"'"' --glob '"'"'!logs/**'"'"' --glob '"'"'!tests/test_helper/**'"'"'\n' "$script_path"
        printf '  count: %s\n' "${count:-0}"
        if [[ -n "$hits" ]]; then
            printf '  hits:\n'
            printf '%s\n' "$hits" | sed "s#^$SCRIPT_DIR/##" | sed 's/^/    /'
        else
            printf '  hits: none\n'
        fi
    done <<< "$script_paths"
}

memory_db_fts5_top3() {
    local cmd_text="$1"
    local title purpose

    title="$(printf '%s\n' "$cmd_text" | awk '/^[[:space:]]*title:[[:space:]]*/ { sub(/^[[:space:]]*title:[[:space:]]*/, ""); gsub(/["'"'"']/, ""); print; exit }')"
    purpose="$(printf '%s\n' "$cmd_text" | awk '/^[[:space:]]*purpose:[[:space:]]*/ { sub(/^[[:space:]]*purpose:[[:space:]]*/, ""); gsub(/["'"'"']/, ""); print; exit }')"

    [[ -n "$title" || -n "$purpose" ]] || return 0

    local query="${title:+$title }${purpose:+$purpose}"
    query="${query# }"
    query="${query% }"
    [[ -n "$query" ]] || return 0

    local db_path="$SCRIPT_DIR/data/multi_agent_shogun_memory.db"
    local results
    results="$(timeout 5s python3 "$SCRIPT_DIR/scripts/hooks/memory_db_fts5_preflight.py" "$db_path" "$query" 2>/dev/null)" || return 0
    [[ -n "$results" ]] || return 0

    printf '三層記憶FTS5検索(title+purpose → 上位3件):\n'
    printf '%s\n' "$results" | awk -F'\t' '{
        summary = substr($6, 1, 80)
        cmd = ($4 != "" ? $4 : "n/a")
        ts = substr($2, 1, 10)
        printf "  %d. [%s] %s (%s, %s)\n", NR, cmd, summary, ts, $5
    }'
}

quality_gate_field_pair_warnings() {
    local cmd_text="$1"
    printf '%s\n' "$cmd_text" | awk '
        function ltrim(value) {
            sub(/^[[:space:]]+/, "", value)
            return value
        }
        function rtrim(value) {
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        function clean_value(line, value) {
            value = line
            sub(/^[^:]*:[[:space:]]*/, "", value)
            sub(/[[:space:]]*#.*/, "", value)
            value = rtrim(ltrim(value))
            return value
        }
        function is_filled(value) {
            return value != "" && value != "\"\"" && value != "''" && value != "null" && value != "~"
        }
        function flush_qg() {
            if (in_qg && q5_present && !q5_verified_source_filled) {
                print "WARN(q5_verified_source必須フィールド対): quality_gate.q5 が記入済みだが q5_verified_source が空/未記入。cmd_save.sh到達前に q5_verified_source: \"structure_verified — 確認方法と対象\" を記入せよ。"
            }
            q5_present = 0
            q5_verified_source_filled = 0
        }
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        {
            indent = match($0, /[^[:space:]]/) - 1
            if ($0 ~ /^[[:space:]]*quality_gate:[[:space:]]*$/) {
                flush_qg()
                in_qg = 1
                qg_indent = indent
                next
            }
            if (in_qg && indent <= qg_indent) {
                flush_qg()
                in_qg = 0
            }
            if (in_qg) {
                if ($0 ~ /^[[:space:]]+q5:[[:space:]]*/) {
                    if (is_filled(clean_value($0))) {
                        q5_present = 1
                    }
                } else if ($0 ~ /^[[:space:]]+q5_verified_source:[[:space:]]*/) {
                    if (is_filled(clean_value($0))) {
                        q5_verified_source_filled = 1
                    }
                }
            }
        }
        END { flush_qg() }
    ' | sort -u
}

# Extract tool_name and file_path without jq/awk on the hot path.
json_string_after() {
    local line="$1" key="$2" rest c result i
    rest="${line#*\""$key"\"}"
    [[ "$rest" != "$line" ]] || return 0
    rest="${rest#*:}"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    [[ "${rest:0:1}" == '"' ]] || return 0
    rest="${rest:1}"
    result=""
    for ((i = 0; i < ${#rest}; i++)); do
        c="${rest:i:1}"
        if [[ "$c" == "\\" && $((i + 1)) -lt ${#rest} ]]; then
            result+="${rest:i:2}"
            ((i++))
            continue
        fi
        [[ "$c" == '"' ]] && break
        result+="$c"
    done
    printf '%s' "$result"
}
tool_name="$(json_string_after "$payload" "tool_name")"
[[ -n "$tool_name" ]] || tool_name="$(json_string_after "$payload" "toolName")"
file_path="$(json_string_after "$payload" "file_path")"
[[ -n "$file_path" ]] || file_path="$(json_string_after "$payload" "filePath")"
[[ -n "$file_path" ]] || file_path="$(json_string_after "$payload" "path")"

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
        emit_deny "BLOCK: shogun_to_karo.yamlのcmdはリスト形式(- id: cmd_XXX)禁止。辞書形式(  cmd_XXX:)で書け。archive済みcmd形式を参照せよ。"
        exit 2
    fi
    # Guard 0d: inbox未読時はcmd起票BLOCK (LS048: 読まずに既読するな。起動時と同じ態度で正しく深く読め)
    # gate_clearのみ(情報通知)なら起票許可。指示系typeが1件でもあればBLOCK (cmd_3349)
    _inbox_file="${GUARD_0D_INBOX_OVERRIDE:-$SCRIPT_DIR/queue/inbox/shogun.yaml}"
    if [[ -f "$_inbox_file" ]]; then
        _unread_count=$(grep -cE '^[[:space:]]*read:[[:space:]]*false' "$_inbox_file" 2>/dev/null || echo 0)
        if [[ "$_unread_count" -gt 0 ]]; then
            _non_gate_clear=$(INBOX_FILE="$_inbox_file" python3 -c '
import yaml, os
with open(os.environ["INBOX_FILE"], encoding="utf-8") as f:
    data = yaml.safe_load(f) or {}
non_gc = [msg for msg in data.get("messages", [])
          if msg.get("read") is False and msg.get("type") != "gate_clear"]
print(len(non_gc))
' 2>/dev/null || echo 99)
            if [[ "$_non_gate_clear" -gt 0 ]]; then
                emit_deny "BLOCK: inbox未読${_unread_count}件(うち指示系${_non_gate_clear}件)。Read toolで全文読み、作業への影響を自問し、対処してからcmd起票せよ。"
                exit 2
            fi
        fi
    fi
    # Guard 0b: on_hold禁止。cmdは直列でdraft→publishせよ。配備順序は家老が判断する(殿裁定2026-05-03)
    if printf '%s' "$_stk_content" | grep -qE 'status:\s*on_hold'; then
        emit_deny "BLOCK: status: on_hold禁止。cmdは直列でdraft→publishせよ。配備順序の制御は家老の仕事。on_holdは将軍がステート管理を抱え込む迂回になる。"
        exit 2
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
            exit 2
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
        _checklist="★起票は雛形から始めよ: bash scripts/cmd_skeleton.sh \"タイトル\" project で全必須フィールド入り雛形を生成→FILL_THISを埋めて貼れ(記憶からの作文はBLOCK往復の元)。保存前検証: cmd_save.sh --preflight <id> (書込みなし)。保存後フロー: cmd_save.sh <id> → cmd_delegate.sh cmd_<id> \"<msg>\"

起票前確認11問:
1. 対象現物を確認したか？
2. 既存代替で足りないことを確認したか？
3. cmd_save.sh関連チェック名を確認したか？
4. project=dm-signalでcommandにgrid_search/walk_forwardを含む場合、ACにrun_077またはl1_alm_wf_engineのフルパスを含めたか？
5. titleにパリティ/新規作成/new_fileを含まないか？diagnosisにもトリガーワードが残っていないか？
6. command欄のステップ数≦AC数か？各ステップの成果物がACに対応しているか？(command_steps_over_ac 10回累計BLOCK)
7. CMD全文に目視確認/セルフレビュー/自問を含まないか？「現物確認」「grep確認」等の客観表現に置換せよ(self_reread 4回累計BLOCK)
8. q11にgrep/rg結果(コマンド+件数)を含めたか？特にスクリプト変更cmdはgate/hook追加と判定される(q11_existing_alternative_verification 17回累計BLOCK)
9. environment_changeのpatternを対象fileでgrep確認したか？例: rg -nF \"pattern文字列\" \"対象ファイル\" → 1件以上(environment_change未実装pattern累計BLOCK)
10. semantic_search.shで関連概念を検索したか？未実行ならここで止まり bash scripts/semantic_search.sh \"cmd主題または対象概念\" を実行し、既知キーワードgrepだけでは見落とす関連概念を確認せよ。
11. gate/script修正cmdは、起票前に対象gate/scriptを実行し、q5_verified_sourceへ実行コマンド・exit code・出力要点を記録したか？

quality_gate template (cmd_save.sh必須フィールド):
  q1_firefighting: \"\"
  q2_learning: \"\"
  q3_next_quality: \"\"
  q4_depth: \"shallow|medium|deep — 理由\"
  q5_verified_source: \"\"
  q6_not_hiding: \"\"
  q7_definition_verified: \"\"
  q8_why_what: \"WHY:  / WHAT:  / WHEN:  / WHERE:  / WHO:  / HOW:  / 複利: \"
  q9_firefighting_root_cause: \"\"
  q10_knowledge_boundary: \"\"
  q11_not_already_done: \"\"
  q_ambiguity: \"\"
  timeout_minutes: \"\"  # 計測/研究/見積/探索cmdの場合は想定実行時間上限(分)を記入
  diagnosis: \"BLOCK理由: ... 対策: ...\"  # 初回起票でも2部構成必須

environment_change template (cmd_save.sh構造化形式):
  environment_change: \"type=gate|lesson|hook; file=対象ファイルパス; pattern=grepで検証可能な既存文字列\"
  注意:
  - 1行テキスト形式必須。block scalar(|)や複数行にしない
  - patternは実装済みの既存文字列のみ。予定・説明文・未実装文字列を書かない
  - patternにバックスラッシュ・パイプ禁止。grep検証で誤解釈される文字を避ける

cmd-level required fields (quality_gate外。cmd直下に配置):
  timeout_minutes: 30  # quality_gate内ではなくcmd直下
  depends_on: none  # or cmd_XXXX
  origin: \"[[発端]] -> [[原因]] -> [[結果]]\"  # none禁止。最低1つの[[リンク]]必須"
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
        _auto_q11_grep_results="$(auto_q11_script_grep_results "$_stk_content")"
        if [[ -n "$_auto_q11_grep_results" ]]; then
            _checklist="${_checklist}

${_auto_q11_grep_results}"
        fi
        _qg_pair_warnings="$(quality_gate_field_pair_warnings "$_stk_content")"
        if [[ -n "$_qg_pair_warnings" ]]; then
            _checklist="${_checklist}

${_qg_pair_warnings}"
        fi
        _memory_db_fts5="$(memory_db_fts5_top3 "$_stk_content")"
        if [[ -n "$_memory_db_fts5" ]]; then
            _checklist="${_checklist}

${_memory_db_fts5}"
        fi
        emit_context "$_checklist"
    fi
    exit 0
fi

# === Guard 1: config-guard (protected config files) ===
case "${file_path##*/}" in
    pyproject.toml|.eslintrc|.eslintrc.*|eslint.config*|biome.json|.prettierrc|.prettierrc.*|tsconfig.json|.ruff.toml|setup.cfg)
        emit_deny "ERROR: ${file_path##*/} is a protected config file.\\nWHY: Linter/formatter configs must not be modified to suppress violations.\\nFIX: Fix the code that triggered the violation, not the linter config."
        exit 2
        ;;
esac

# === Guard 2: read-tracker (Write/Edit must be preceded by Read) ===
# queue/tasks/*.yaml → unconditional deny
report_yaml_deny_reason="BLOCKED: 報告YAMLへの直接Write/Edit禁止。\\n対象: $file_path\\nWHY: report_field_set.sh経由でのみ更新可。flock排他制御+構造保全のため。\\nFIX: bash scripts/report_field_set.sh $file_path <dot.notation.key> <value>\\n例: bash scripts/report_field_set.sh $file_path result.summary 検証完了\\n例: bash scripts/report_field_set.sh $file_path binary_checks.AC1 '[{check: 確認内容, result: yes}]'\\n例: bash scripts/report_field_set.sh $file_path verdict PASS"
case "$file_path" in
    */queue/tasks/*.yaml)
        emit_deny "queue/tasks/*.yamlはWrite/Editで直接書くな。状態更新→bash scripts/lib/yaml_field_set.sh queue/tasks/{name}.yaml task {field} {value}。新規配備→deploy_task.sh。"
        exit 2
        ;;
    */queue/reports/*.yaml)
        emit_deny "$report_yaml_deny_reason"
        exit 2
        ;;
esac

# Check read log for existing files
if [ -f "$file_path" ]; then
    agent_id="$(tmux display-message -t "${TMUX_PANE:-}" -p '#{@agent_id}' 2>/dev/null || echo 'unknown')"
    [[ -z "$agent_id" ]] && agent_id="unknown"
    LOG_FILE="/tmp/claude_read_log_${agent_id}.txt"
    if ! { [ -f "$LOG_FILE" ] && grep -qFx "$file_path" "$LOG_FILE" 2>/dev/null; }; then
        emit_deny "このファイルはまだReadされていません。先にReadツールで読んでからWrite/Editしてください。"
        exit 2
    fi
fi

# === Guard 3: report-deny (Edit/Write to report YAML) ===
if [[ "$file_path" =~ queue/reports/[^/]*_report_[^/]*\.yaml$ ]]; then
    emit_deny "$report_yaml_deny_reason"
    exit 2
fi

# === Guard 4: workaround-deny (Edit/Write to karo_workarounds.yaml) ===
if [[ "$file_path" == *'logs/karo_workarounds.yaml' ]]; then
    emit_deny "BLOCKED: karo_workarounds.yamlへの直接Edit/Write禁止。\\nWHY: karo_workaround_log.sh経由でのみ記録可。ALERTメカニズム(3件同一カテゴリでntfy通知)が発火するために必須。\\nWA記録: bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> <修正内容> <根本原因>"
    exit 2
fi

# === Guard 5: lessons.yaml tags直接Edit禁止 (LK052: 同期不整合防止) ===
if [[ "$tool_name" == "Edit" && "$file_path" == *'/lessons.yaml' ]]; then
    old_string="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .old_string // ""' 2>/dev/null)" || true
    if [[ "$old_string" == *'tags:'* ]]; then
        emit_deny "BLOCKED: lessons.yamlのtags直接Edit禁止。\\nWHY: lessons.md←→lessons.yaml同期不整合が発生する。\\nFIX: bash scripts/lesson_write.sh <project_id> --retag <lesson_id> --new-tags \\\"tag1,tag2\\\""
        exit 2
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
            exit 2
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
            exit 2
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
            exit 2
        fi
    fi
fi

# === Guard 9: LG026 S0セルフレビュー リマインダー (高リスクファイル編集時) ===
if [[ "$file_path" =~ (hooks/|gates/gate_.*_startup|gates/gate_gunshi_|CLAUDE\.md|instructions/|\.claude/settings|config/settings\.yaml|gunshi_review_log\.yaml) ]]; then
    _agent_id=$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || echo "unknown")
    if [[ "$_agent_id" == "gunshi" ]]; then
        echo "INFO: 高リスクファイル編集検出。S0セルフレビュー6項目を実施せよ(前提/数値/シミュレーション/検死/検証/NorthStar)。commit messageにS0記録必須。" >&2
    fi
fi

# === Guard 11: observations必須リマインダー (review_log新エントリ追記時) ===
if [[ "$file_path" == *'gunshi_review_log.yaml' ]]; then
    _new_string="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .new_string // ""' 2>/dev/null)" || true
    if echo "$_new_string" | grep -q '^\- cmd_id:' && echo "$_new_string" | grep -q 'review_type:' && ! echo "$_new_string" | grep -q 'observations:'; then
        echo "WARN(observations必須): review_logエントリにobservationsなし。最低1つの具体的事実を記載せよ(計測データが深さの唯一の証拠)。" >&2
    fi
fi

# === Guard 10: LG020 数値実測リマインダー (軍師設計書保存時) ===
if [[ "$file_path" == *'docs/research/gunshi_'* ]]; then
    _agent_id="${_agent_id:-$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || echo "unknown")}"
    if [[ "$_agent_id" == "gunshi" ]]; then
        echo "INFO: 設計書保存検出。数値は全て入力データからwc -l/head実測で再計算せよ。推定値は未実測と明記。" >&2
        # LG028: 計算量推定で内部ループ計上漏れ防止
        _content="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .new_string // .content // ""' 2>/dev/null)" || true
        if printf '%s' "$_content" | grep -qiE '(秒|ms|WF|combo|ループ|loop|計算量|推定|パターン)'; then
            echo "INFO: 計算量記述検出。外側ループ×内側ループ×単位時間で推定せよ。外側のみの見積もりは過小評価になりやすい。" >&2
        fi
    fi
fi

# === Guard 12: LG023/032 新機構作成リマインダー (既存活用優先) ===
if [[ "$tool_name" == "Write" && "$file_path" =~ (scripts/gates/|scripts/hooks/|\.claude/hooks/) ]]; then
    _agent_id="${_agent_id:-$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || echo "unknown")}"
    if [[ "$_agent_id" == "gunshi" ]]; then
        echo "INFO: 新スクリプト作成検出。既存の仕組み(startup gate/stop hook/inbox/既存Guard)に乗せて解決できないか先に確認せよ。" >&2
    fi
fi

# Guard 15: 削除(2026-06-20)。各論パッチ(5フレーズのみ検出)はバグ。
# 原理的解決=SessionContext(Step 1.7)がlord_conversation実際発言を自動表示。

# === Guard 17: settings.yaml CLI/model変更は /shogun-cli-switch 経由必須 (殿裁定2026-06-20) ===
# 手動Edit禁止。スキルが settings.yaml を変更→respawn→検証まで一貫実行する
if [[ "$file_path" =~ config/settings\.yaml ]]; then
    _write_content="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .new_string // .content // ""' 2>/dev/null)" || true
    if printf '%s' "$_write_content" | grep -qE 'type:[[:space:]]*(claude|codex)|model_name:'; then
        echo "BLOCK: settings.yaml CLI/model変更は /shogun-cli-switch スキルを使え。手動Edit禁止 (殿裁定: スキル100%使用。意志依存はバグ)" >&2
        exit 2
    fi
fi

# === Guard 16: 操作的オントロジー — 定義元(SSOT)がある値の直書き検出 (2026-06-20) ===
# 殿裁定: オントロジー=三層記憶と同列の前提。定義が1箇所に集約され変更が自動伝播する。しないのはバグ
# テーブル駆動: 新概念追加 = 5並列配列に1要素追加するだけ
# 列: _G16_CONCEPTS / _G16_MIN_COUNTS / _G16_EXEMPTS / _G16_FNS / _G16_SSOTS
if [[ "$file_path" =~ \.(sh|py|md)$ ]]; then
    _g16_content="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .new_string // .content // ""' 2>/dev/null)" || true
    if [ -n "$_g16_content" ]; then

        # ── 検出関数 (content=$1, stdout=count) ────────────────────────────────
        _g16_count_agent_names() {
            local _names _cnt=0 _n
            _names="$(source "$SCRIPT_DIR/scripts/lib/agent_config.sh" 2>/dev/null \
                && get_ninja_names 2>/dev/null)" || true
            [ -n "$_names" ] || { printf '0'; return; }
            for _n in $_names; do
                printf '%s' "$1" | grep -q "$_n" && ((_cnt++)) || true
            done
            printf '%s' "$_cnt"
        }
        _g16_count_repo_path() {
            local _rp="$SCRIPT_DIR"
            [[ -n "$_rp" ]] || { printf '0'; return; }
            printf '%s' "$1" | grep -cF "$_rp" 2>/dev/null || printf '0'
        }
        _g16_count_home_path() {
            local _hp="${HOME:-}"
            [[ -n "$_hp" ]] || { printf '0'; return; }
            printf '%s' "$1" | grep -cF "$_hp" 2>/dev/null || printf '0'
        }
        # ───────────────────────────────────────────────────────────────────────

        # ── オントロジーテーブル (並列配列) ────────────────────────────────────
        # 新概念追加: 以下5配列に対応インデックスで1要素ずつ追加するだけ
        # _G16_CONCEPTS    : 概念ラベル (エラーメッセージに使用)
        # _G16_MIN_COUNTS  : 直書き検出の最小閾値
        # _G16_EXEMPTS     : 免除パターン (ERE; マッチすれば該当概念スキップ)
        # _G16_FNS         : 検出関数名 (content=$1 でcount返す)
        # _G16_SSOTS       : SSOTポインタ (エラーメッセージ内)
        _G16_CONCEPTS=( "エージェント名" "repoルートパス" "user-homeパス" )
        _G16_MIN_COUNTS=( 3 1 1 )
        _G16_EXEMPTS=(
            'get_ninja_names|get_all_agents|get_allowed_targets|os\.environ\.get|\$\{.*:-'
            'SCRIPT_DIR|repo_root|git rev-parse'
            '\$HOME|\$\{HOME\}|~/'
        )
        _G16_FNS=( "_g16_count_agent_names" "_g16_count_repo_path" "_g16_count_home_path" )
        _G16_SSOTS=(
            'config/settings.yaml → agent_config.sh get_ninja_names()/get_all_agents()'
            'scripts/lib/repo_root.sh → repo_root()'
            '$HOME 環境変数'
        )
        # ───────────────────────────────────────────────────────────────────────

        _g16_i=0
        for _g16_concept in "${_G16_CONCEPTS[@]}"; do
            _g16_min="${_G16_MIN_COUNTS[$_g16_i]}"
            _g16_exempt="${_G16_EXEMPTS[$_g16_i]}"
            _g16_fn="${_G16_FNS[$_g16_i]}"
            _g16_ssot="${_G16_SSOTS[$_g16_i]}"
            ((_g16_i++)) || true

            # 免除パターンにマッチすれば該当概念はスキップ
            if printf '%s' "$_g16_content" | grep -qE "$_g16_exempt"; then
                continue
            fi

            # 検出関数で直書き件数を取得
            _g16_cnt="$("$_g16_fn" "$_g16_content")" || _g16_cnt=0

            if [ "${_g16_cnt:-0}" -ge "$_g16_min" ]; then
                echo "BLOCK: 操作的オントロジー違反 — ${_g16_concept}${_g16_cnt}件を直書き。SSOT=${_g16_ssot} を使え。" >&2
                exit 2
            fi
        done

        unset _g16_content _g16_concept _g16_min _g16_exempt _g16_fn _g16_ssot _g16_cnt _g16_i
        unset _G16_CONCEPTS _G16_MIN_COUNTS _G16_EXEMPTS _G16_FNS _G16_SSOTS
        unset -f _g16_count_agent_names _g16_count_repo_path _g16_count_home_path
    fi
fi

exit 0
