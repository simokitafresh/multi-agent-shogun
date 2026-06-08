#!/usr/bin/env bash
# PostToolUse hook: Skill tool実行後にskill_execution_log.shを自動呼出し。
# cmd_3228 Phase1: 全スキルの実行結果を自動記録する共通基盤。
# L164: set -eu only for Claude hook shell scripts.
set -eu

if [ -n "${HOOK_PAYLOAD+x}" ]; then
    payload="$HOOK_PAYLOAD"
else
    payload="$(cat 2>/dev/null || true)"
fi
[[ -z "${payload//[[:space:]]/}" ]] && exit 0
[[ "$payload" != *'"Skill"'* ]] && exit 0

REPO="/mnt/c/tools/multi-agent-shogun"

# --- スキル名を抽出 (jq不要: awk) ---
skill_name="$(printf '%s' "$payload" | awk '
    match($0, /"skill"[[:space:]]*:[[:space:]]*"/) {
        s = substr($0, RSTART + RLENGTH)
        n = length(s); result = ""
        for (i = 1; i <= n; i++) {
            c = substr(s, i, 1)
            if (c == "\\" && i < n) { result = result substr(s, i, 2); i++; continue }
            if (c == "\"") break
            result = result c
        }
        print result
        exit
    }
')"
[[ -z "$skill_name" ]] && exit 0

# --- 重複排除: gate連携済みスキルはスキップ ---
# これらのスキルはgate_report_format.sh/cmd_complete_gate.sh/dashboard_update.sh内で
# skill_execution_log.shを直接呼出しており、PASS/FAIL判定がgateに基づくためより正確。
# PostToolUse hookで二重記録しない。
case "$skill_name" in
    report-write|verdict-check|cmd-complete|dashboard-update)
        exit 0
        ;;
esac

# --- executor取得 (tmux agent_id) ---
executor=""
if [ -n "${TMUX_PANE:-}" ]; then
    cache="/tmp/shogun_aid_${TMUX_PANE}"
    if [ -r "$cache" ]; then
        IFS= read -r executor < "$cache" || true
    fi
    if [ -z "$executor" ]; then
        executor="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
    fi
fi
[ -n "$executor" ] || executor="unknown"

# --- 結果判定: tool_resultからPASS/FAILヒューリスティクス ---
# PostToolUseのtool_resultはスキル展開後のプロンプト。
# 明示的FAILシグナル(exit 2によるBLOCK等)がなければINVOKEDとして記録。
result="PASS"
stumbling_points=""

# tool_resultにBLOCKやエラーが含まれるか確認
if printf '%s' "$payload" | grep -qiE '"(BLOCK|ERROR|FAIL)[^"]*"' 2>/dev/null; then
    result="FAIL"
    # stumbling_pointsとして最初のエラーメッセージ片を取得
    stumbling_points="$(printf '%s' "$payload" | grep -oiE '(BLOCK|ERROR|FAIL)[^"]{0,80}' 2>/dev/null | head -1 || true)"
fi

# --- skill_pathを導出 ---
skill_path=""
if [ -f "$REPO/skills/$skill_name/SKILL.md" ]; then
    skill_path="$REPO/skills/$skill_name/SKILL.md"
fi

# --- source (cmd_id) 取得: タスクYAML冒頭のcmd_idを取得 ---
source_id=""
if [ -n "${TMUX_PANE:-}" ] && [ "$executor" != "unknown" ] && [ "$executor" != "shogun" ]; then
    task_file="$REPO/queue/tasks/${executor}.yaml"
    if [ -f "$task_file" ]; then
        source_id="$(grep -m1 'cmd_id:' "$task_file" 2>/dev/null | awk '{print $2}' | tr -d ' "'"'" || true)"
    fi
fi

# --- skill_execution_log.sh 呼出 (非同期: hookレイテンシ最小化) ---
log_script="$REPO/scripts/skill_execution_log.sh"
if [ -x "$log_script" ]; then
    if [ "${SKILL_LOG_SYNC:-0}" = "1" ]; then
        bash "$log_script" \
            "$skill_name" \
            "$executor" \
            "$result" \
            "$stumbling_points" \
            "" \
            "$source_id" \
            "$skill_path" >/dev/null 2>&1 || true
    else
        bash "$log_script" \
            "$skill_name" \
            "$executor" \
            "$result" \
            "$stumbling_points" \
            "" \
            "$source_id" \
            "$skill_path" >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi
fi

exit 0
