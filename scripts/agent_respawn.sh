#!/usr/bin/env bash
# agent_respawn.sh — CLI種別を自動解決してrespawnする唯一の正規手段
# Usage: bash scripts/agent_respawn.sh <agent_name> [reason]
# 根拠: 2026-07-22 軍師がrespawn-pane直接実行→全忍者にClaude CLI決め打ち→type:codex忍者がClaude化
# 殿命令: 意志依存ではなく強制的にバグが再発しない仕組みを作れ
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/cli_lookup.sh"
source "$REPO_ROOT/scripts/lib/pane_lookup.sh"
source "$REPO_ROOT/scripts/lib/task_lifecycle.sh"

agent_name="${1:?Usage: agent_respawn.sh <agent_name> [reason]}"
reason="${2:-manual_respawn}"

# pane解決(pane_lookup.sh SSOT)
pane=$(pane_lookup "$agent_name" 2>/dev/null || true)
if [[ -z "$pane" ]]; then
    echo "ERROR: agent '$agent_name' pane not found" >&2
    exit 1
fi

# 作業中ガード(殿裁定2026-08-26 20:53「作業中をrespawnしても速くならない。respawnしたら将軍の思考回路がバグ」):
# 呼び手の目視判断に依存せず、(1)pane実態が作業中 (2)task YAMLが未終端 のどちらかなら拒否する。
# 明示 RESPAWN_FORCE=1 のみ通す(死亡pane復旧など。理由をログに残す)。構造型=手を動かすと自然に守られる。
respawn_task_file="$REPO_ROOT/queue/tasks/${agent_name}.yaml"
respawn_task_status=""
if [[ -f "$respawn_task_file" ]]; then
    respawn_task_status=$(grep -m1 -E '^\s*status:\s*' "$respawn_task_file" 2>/dev/null \
        | sed 's/.*status:[[:space:]]*//' | tr -d "\"'[:space:]" || true)
fi
respawn_pane_tail="$(tmux capture-pane -t "$pane" -p 2>/dev/null | tail -12 || true)"
respawn_busy_reason=""
case "$respawn_task_status" in
    assigned|acknowledged|in_progress) respawn_busy_reason="task_status=${respawn_task_status}" ;;
esac
if printf '%s' "$respawn_pane_tail" | grep -qE 'esc to interrupt|Working \(|Running [0-9]+ PreToolUse|Waiting for background terminal'; then
    respawn_busy_reason="${respawn_busy_reason:+${respawn_busy_reason},}pane_busy"
fi
if [[ -n "$respawn_busy_reason" && "${RESPAWN_FORCE:-0}" != "1" ]]; then
    echo "[agent_respawn] BLOCK: ${agent_name} is working (${respawn_busy_reason}). respawn discards in-flight work and is slower, not faster. Wait for task end, or RESPAWN_FORCE=1 with a reason." >&2
    exit 2
fi

# CLI種別を自動解決(cli_lookup.sh SSOT)
cli=$(cli_type "$agent_name" 2>/dev/null || echo "claude")
launch_cmd=$(cli_launch_cmd "$agent_name" 2>/dev/null || echo "")

if [[ "$cli" == "codex" ]] && [[ -n "$launch_cmd" ]]; then
    echo "[agent_respawn] ${agent_name} → codex: ${launch_cmd}"
    tmux respawn-pane -k -c "$REPO_ROOT" -t "$pane" "$launch_cmd"
    # Codex 0.152.1 can still show its update dialog even when the unsupported
    # check_for_update_on_startup=false setting is present.  Inspect only the
    # fresh visible pane; the helper sends Down Down Enter only for the exact
    # three-choice dialog and verifies the normal prompt afterwards.
    if ! codex_update_prompt_auto_skip "$pane"; then
        echo "[agent_respawn] BLOCK: ${agent_name} Codex update prompt was not verified after auto-skip" >&2
        exit 2
    fi
elif [[ "$cli" == "claude" ]]; then
    launch_cmd="${launch_cmd:-$HOME/bin/claude --effort high}"
    echo "[agent_respawn] ${agent_name} → claude: ${launch_cmd}"
    tmux respawn-pane -k -c "$REPO_ROOT" -t "$pane" "$launch_cmd"
else
    echo "ERROR: unknown cli type '$cli' for '$agent_name'" >&2
    exit 1
fi

# @agent_cli同期(cmd_karo_hotfix_agent_respawn_cli_sync_202609031435根治): 上のcli変数はcli_type()が
# respawn直前のpane_current_command(旧CLIプロセス)を優先するため、settings.type切替直後は
# stale値になりうる。@agent_cliはsettings.type(SSOT)を直接読み直し、respawn呼出しが成功して
# ここへ到達した場合にのみ焼き込む(set -euoにより失敗時はこの行へ到達せず旧値を保持する)。
respawn_settings_cli=$(_cli_lookup_settings_get "$agent_name" "type" "claude")
case "$respawn_settings_cli" in
    claude|codex|copilot|kimi) ;;
    *) respawn_settings_cli="claude" ;;
esac
tmux set-option -p -t "$pane" @agent_cli "$respawn_settings_cli" 2>/dev/null || true

# LS078根治: settings.yaml model_nameをそのまま@model_nameへ焼込み(バナーパース非経由)
apply_model_name_tag "$agent_name" "$pane" || true

# 通常respawnは次任務を受けられるようidleへ戻す。ただし正式FAIL-close後の
# failed taskは非配備状態そのものが終端契約なので保持する。ここでidle化すると
# auto-deployが旧任務停止直後の忍者を再選択できてしまう。
task_file="$REPO_ROOT/queue/tasks/${agent_name}.yaml"
task_status=""
if [[ -f "$task_file" ]]; then
    task_status=$(grep -m1 -E '^\s*status:\s*' "$task_file" 2>/dev/null \
        | sed 's/.*status:[[:space:]]*//' | tr -d "\"'[:space:]" || true)
fi
if [[ "$task_status" != "failed" ]]; then
    task_lifecycle_set_idle "$task_file" "agent_respawn" 2>/dev/null || true
fi

echo "[agent_respawn] ${agent_name} respawned (reason=${reason}, cli=${cli})"
