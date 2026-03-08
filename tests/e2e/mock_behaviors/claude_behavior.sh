#!/usr/bin/env bash

claude_startup_banner() {
    echo "Claude Code (mock)"
}

claude_handle_clear() {
    local agent_id="$1"
    local project_root="$2"
    echo "[mock] /clear received for ${agent_id}"
    [ -f "$project_root/queue/tasks/${agent_id}.yaml" ]
}
