#!/usr/bin/env bash

codex_startup_banner() {
    echo "Codex CLI (mock)"
    echo "? for shortcuts                100% context left"
}

codex_handle_clear() {
    local agent_id="$1"
    local project_root="$2"
    echo "[mock] /new received for ${agent_id}"
    [ -f "$project_root/queue/tasks/${agent_id}.yaml" ]
}
