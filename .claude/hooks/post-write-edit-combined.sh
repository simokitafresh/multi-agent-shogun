#!/usr/bin/env bash
# Combined Write/Edit PostToolUse guard: shellcheck + report-guard + instruction-consistency
# cmd_1661: 3 hooks → 1 script. Eliminates 2 bash startup costs (~60ms each).
# GP-095: crash耐性 — PostToolUse hookは非ゼロ終了禁止
# Guard 0: replace_all確認 (LS069 — 2026-04-21殿裁定)

# cmd_2074: Read stdin without spawning cat subprocess
# Note: read -d '' returns non-zero on EOF; use || true to preserve data read
IFS='' read -r -d '' payload || true
case "$payload" in
    *[![:space:]]*) ;;
    *) exit 0 ;;
esac
case "$payload" in
    *'"Write"'*|*'"Edit"'*) ;;
    *) exit 0 ;;
esac

emit_context() {
    printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$1"
}
# Emit arbitrary text safely as JSON (handles newlines/special chars via jq)
emit_context_raw() {
    printf '%s' "$1" | jq -Rs '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":.}}' 2>/dev/null || true
}

# Extract file_path with jq (single call for all guards)
file_path="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .file_path // .filePath // .path // empty' 2>/dev/null)" || exit 0
[[ -z "$file_path" ]] && exit 0

# PROJECT_ROOT via string ops (no subshell)
_PROJECT_ROOT="${BASH_SOURCE[0]%/.claude/hooks/*}"
[[ -z "$_PROJECT_ROOT" || "$_PROJECT_ROOT" == "${BASH_SOURCE[0]}" ]] && \
    _PROJECT_ROOT="/mnt/c/tools/multi-agent-shogun"

case "$file_path" in
    *queue/reports/*_report_*.yaml) ;;
    *.sh|*.bash) ;;
    *CLAUDE.md|*instructions/*) ;;
    *) ;; # continue to replace_all check for all files
esac

# === Guard 0: replace_all confirmation (LS069 — 2026-04-21殿裁定) ===
_replace_all="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .replace_all // false' 2>/dev/null)" || true
if [[ "$_replace_all" == "true" ]]; then
    _old_string="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .old_string // empty' 2>/dev/null)" || true
    if [[ -n "$_old_string" ]]; then
        _short="${_old_string:0:50}"
        emit_context "★ replace_all=true 使用。適用件数を確認せよ: grep -c '${_short//\"/\\\"}' ${file_path}"
    fi
fi

# === Guard 1: report-guard (WARN + YAML parse check) ===
if [[ "$file_path" =~ queue/reports/[^/]*_report_[^/]*\.yaml$ ]]; then
    emit_context "WARNING: 報告YAMLへの直接Edit/Write検出。\\nWHY: 報告YAMLはreport_field_set.sh経由で更新せよ。flock排他制御+構造保全のため。\\nFIX: bash scripts/report_field_set.sh <report_path> <dot.notation.key> <value>"
    # GP-197: YAML構文検証。parse errorなら即通知(忍者が壊れたYAMLに気づける)
    if [[ -f "$file_path" ]]; then
        parse_err="$(python3 -c "
import yaml,sys
try:
    yaml.safe_load(open(sys.argv[1]))
except yaml.YAMLError as e:
    print(str(e).replace(chr(10),' ')[:200])
    sys.exit(1)
" "$file_path" 2>/dev/null)" || \
            emit_context "ERROR: 報告YAML構文エラー。gate BLOCKされる。修正せよ: ${parse_err//\"/\\\"}"
    fi
fi

# === Guard 2: shellcheck (only for .sh/.bash files) — pure bash, no Python ===
if [[ "${file_path##*/}" == *.sh || "${file_path##*/}" == *.bash ]]; then
    # Resolve absolute path
    [[ "$file_path" != /* ]] && _abs_path="$_PROJECT_ROOT/$file_path" || _abs_path="$file_path"
    # Security: verify path is within project root
    case "$_abs_path" in
        "$_PROJECT_ROOT"/*) ;;
        *) _abs_path="" ;;
    esac
    if [[ -n "$_abs_path" && -f "$_abs_path" ]]; then
        _rel_path="${_abs_path#"$_PROJECT_ROOT"/}"
        _sc_out=$(shellcheck "$_rel_path" 2>&1); _sc_exit=$?
        if [[ $_sc_exit -ne 0 && -n "$_sc_out" ]]; then
            # Append simplified violation log (no agent_id tmux call)
            _ts=$(printf '%(%Y-%m-%dT%H:%M:%SZ)T' -1 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
            _log="$_PROJECT_ROOT/logs/hook_violations.jsonl"
            printf '{"timestamp":"%s","file_path":"%s","tool":"shellcheck","violations_summary":"%s"}\n' \
                "$_ts" "$_rel_path" "${_sc_out%%$'\n'*}" >> "$_log" 2>/dev/null || true
            # Emit JSON with proper escaping via jq
            _msg=$(printf 'ERROR: ShellCheck violations in %s\nWHY: Shell script lint violations must be resolved before proceeding.\nFIX: 1) Read violations below. 2) Fix in %s. 3) ShellCheck re-checks on save.\n4) For CRLF (SC1017): sed -i '"'"'s/\\r$//'"'"' %s\n\n%s' \
                "$_rel_path" "$_rel_path" "$_rel_path" "$_sc_out")
            emit_context_raw "$_msg"
        fi
    fi
fi

# === Guard 3: instruction-hook-consistency (only for instruction/hook files) — bash grep ===
if [[ "$file_path" == *'CLAUDE.md'* || "$file_path" == *'instructions/'* || "$file_path" == *'.claude/hooks/'* ]]; then
    _hook_dir="$_PROJECT_ROOT/.claude/hooks"
    _has_task_deny=false
    _has_report_deny=false
    # Detect deny patterns across all hook files
    grep -ql "queue/tasks/.*deny" "$_hook_dir"/*.sh 2>/dev/null && _has_task_deny=true
    grep -ql "queue/reports/.*deny" "$_hook_dir"/*.sh 2>/dev/null && _has_report_deny=true

    if [[ "$_has_task_deny" == true || "$_has_report_deny" == true ]]; then
        # Collect instruction files to scan
        _inst_files=("$_PROJECT_ROOT/CLAUDE.md")
        while IFS= read -r _f; do _inst_files+=("$_f"); done < \
            <(find "$_PROJECT_ROOT/instructions" -maxdepth 1 -name "*.md" 2>/dev/null)

        _conflicts=()
        for _inst in "${_inst_files[@]}"; do
            [[ -f "$_inst" ]] || continue
            _base="${_inst##*/}"
            # Check for 'Edit task' conflicts (excluding deploy_task/hook/saytask context)
            if [[ "$_has_task_deny" == true ]]; then
                while IFS= read -r _match; do
                    [[ "$_match" == *deploy_task* || "${_match,,}" == *hook* || "${_match,,}" == *saytask* ]] && continue
                    _line_num="${_match%%:*}"
                    _conflicts+=("${_base}:${_line_num}: 'Edit task' conflicts with task-deny hook.")
                done < <(grep -in '\bEdit\b.*\btask\b' "$_inst" 2>/dev/null | grep -v "deploy_task\|hook\|saytask")
            fi
            # Check for 'Edit/Write report' conflicts
            if [[ "$_has_report_deny" == true ]]; then
                while IFS= read -r _match; do
                    [[ "${_match,,}" == *report_field_set* || "${_match,,}" == *hook* ]] && continue
                    _line_num="${_match%%:*}"
                    _conflicts+=("${_base}:${_line_num}: 'Edit/Write report' conflicts with report-deny hook.")
                done < <(grep -inE '\b(Edit|Write)\b.*\breport\b' "$_inst" 2>/dev/null | grep -v "report_field_set\|hook")
            fi
        done

        if [[ ${#_conflicts[@]} -gt 0 ]]; then
            _warn="WARNING: 指示-hook整合性チェック検出。\nWHY: hookのdenyパターンと指示内のツール参照が矛盾している可能性。\n"
            for _c in "${_conflicts[@]}"; do _warn+="  ⚠ ${_c}\n"; done
            _warn+="\nFIX: 指示を修正してhookと整合させよ。"
            emit_context_raw "$(printf '%b' "$_warn")"
        fi
    fi
fi

exit 0
