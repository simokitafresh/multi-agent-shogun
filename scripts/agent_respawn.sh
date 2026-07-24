#!/usr/bin/env bash
# agent_respawn.sh — CLI種別を自動解決してrespawnする唯一の正規手段
# Usage: bash scripts/agent_respawn.sh <agent_name> [reason]
# 根拠: 2026-07-22 軍師がrespawn-pane直接実行→全忍者にClaude CLI決め打ち→type:codex忍者がClaude化
# 殿命令: 意志依存ではなく強制的にバグが再発しない仕組みを作れ
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/cli_lookup.sh"
source "$REPO_ROOT/scripts/lib/pane_lookup.sh"

agent_name="${1:?Usage: agent_respawn.sh <agent_name> [reason]}"
reason="${2:-manual_respawn}"

# pane解決(pane_lookup.sh SSOT)
pane=$(pane_lookup "$agent_name" 2>/dev/null || true)
if [[ -z "$pane" ]]; then
    echo "ERROR: agent '$agent_name' pane not found" >&2
    exit 1
fi

# CLI種別を自動解決(cli_lookup.sh SSOT)
cli=$(cli_type "$agent_name" 2>/dev/null || echo "claude")
launch_cmd=$(cli_launch_cmd "$agent_name" 2>/dev/null || echo "")

if [[ "$cli" == "codex" ]] && [[ -n "$launch_cmd" ]]; then
    echo "[agent_respawn] ${agent_name} → codex: ${launch_cmd}"
    tmux respawn-pane -k -t "$pane" "$launch_cmd"
elif [[ "$cli" == "claude" ]]; then
    launch_cmd="${launch_cmd:-$HOME/bin/claude --effort high}"
    echo "[agent_respawn] ${agent_name} → claude: ${launch_cmd}"
    tmux respawn-pane -k -t "$pane" "$launch_cmd"
else
    echo "ERROR: unknown cli type '$cli' for '$agent_name'" >&2
    exit 1
fi

# LS078根治: settings.yaml model_nameをそのまま@model_nameへ焼込み(バナーパース非経由)
apply_model_name_tag "$agent_name" "$pane" || true

# task statusをidle化
bash "$REPO_ROOT/scripts/lib/yaml_field_set.sh" "queue/tasks/${agent_name}.yaml" task status idle 2>/dev/null || true

echo "[agent_respawn] ${agent_name} respawned (reason=${reason}, cli=${cli})"
