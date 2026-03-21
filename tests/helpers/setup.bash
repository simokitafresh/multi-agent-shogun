#!/usr/bin/env bash
# Shared setup/teardown helpers for isolated E2E tests.

E2E_SESSION_NAME="${E2E_SESSION_NAME:-e2e_test_$$}"
E2E_MOCK_DELAY="${E2E_MOCK_DELAY:-1}"
E2E_DEFAULT_AGENTS=("karo" "sasuke" "kirimaru")
E2E_DEFAULT_CLIS=("claude" "codex" "codex")

e2e_preflight() {
    command -v tmux >/dev/null 2>&1 || {
        echo "tmux not found" >&2
        return 1
    }
    command -v python3 >/dev/null 2>&1 || {
        echo "python3 not found" >&2
        return 1
    }
    python3 -c "import yaml" >/dev/null 2>&1 || {
        echo "python3-yaml not found" >&2
        return 1
    }
    return 0
}

pane_target() {
    local pane_idx="$1"
    echo "${E2E_SESSION}:agents.${pane_idx}"
}

setup_e2e_session() {
    local num_panes="${1:-3}"
    e2e_preflight || return 1

    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

    mkdir -p "$PROJECT_ROOT/.tmp"
    export E2E_ROOT
    E2E_ROOT="$(mktemp -d "$PROJECT_ROOT/.tmp/e2e_env.XXXXXX")"

    export E2E_QUEUE="$E2E_ROOT"
    mkdir -p "$E2E_QUEUE/queue"/{inbox,tasks,reports,metrics}
    mkdir -p "$E2E_QUEUE/scripts"
    export SHOGUN_STATE_DIR="$E2E_ROOT/state"
    mkdir -p "$SHOGUN_STATE_DIR"
    # E2Eテストはテスト用エージェント名(sasuke等)を使うため、
    # inbox_write.shの本番エージェント名検証をスキップ
    export INBOX_WRITE_TEST=1

    cp "$PROJECT_ROOT/scripts/inbox_write.sh" "$E2E_QUEUE/scripts/"
    cp "$PROJECT_ROOT/scripts/inbox_watcher.sh" "$E2E_QUEUE/scripts/"
    chmod +x "$E2E_QUEUE/scripts/inbox_write.sh" "$E2E_QUEUE/scripts/inbox_watcher.sh"

    if [ -d "$PROJECT_ROOT/scripts/lib" ]; then
        cp -R "$PROJECT_ROOT/scripts/lib" "$E2E_QUEUE/scripts/"
    fi
    if [ -d "$PROJECT_ROOT/lib" ]; then
        cp -R "$PROJECT_ROOT/lib" "$E2E_QUEUE/"
    fi
    if [ -d "$PROJECT_ROOT/config" ]; then
        cp -R "$PROJECT_ROOT/config" "$E2E_QUEUE/"
    fi
    if [ -d "$PROJECT_ROOT/.venv" ]; then
        ln -s "$PROJECT_ROOT/.venv" "$E2E_QUEUE/.venv"
    fi

    local inbox_agents=("${E2E_DEFAULT_AGENTS[@]}" "shogun")
    for agent in "${inbox_agents[@]}"; do
        echo "messages: []" > "$E2E_QUEUE/queue/inbox/${agent}.yaml"
    done

    export E2E_SESSION="$E2E_SESSION_NAME"
    tmux kill-session -t "$E2E_SESSION" 2>/dev/null || true
    tmux new-session -d -s "$E2E_SESSION" -n agents -x 220 -y 60
    # Keep deterministic pane IDs for tests regardless of user's tmux config.
    tmux set-option -t "${E2E_SESSION}:agents" pane-base-index 0

    local i
    for ((i = 1; i < num_panes; i++)); do
        tmux split-window -h -t "${E2E_SESSION}:agents"
    done
    tmux select-layout -t "${E2E_SESSION}:agents" tiled

    local mock_cli="${E2E_MOCK_CLI_PATH:-$PROJECT_ROOT/tests/e2e/mock_cli.sh}"
    for ((i = 0; i < num_panes && i < ${#E2E_DEFAULT_AGENTS[@]}; i++)); do
        local agent_id="${E2E_DEFAULT_AGENTS[$i]}"
        local cli_type="${E2E_DEFAULT_CLIS[$i]}"
        tmux set-option -p -t "${E2E_SESSION}:agents.${i}" @agent_id "$agent_id"
        tmux set-option -p -t "${E2E_SESSION}:agents.${i}" @agent_cli "$cli_type"
        if [ -f "$mock_cli" ]; then
            tmux send-keys -t "${E2E_SESSION}:agents.${i}" \
                "SHOGUN_STATE_DIR=$SHOGUN_STATE_DIR MOCK_CLI_TYPE=$cli_type MOCK_AGENT_ID=$agent_id MOCK_PROCESSING_DELAY=$E2E_MOCK_DELAY MOCK_PROJECT_ROOT=$E2E_QUEUE bash $mock_cli" \
                Enter
        fi
    done

    sleep 2
}

teardown_e2e_session() {
    tmux kill-session -t "${E2E_SESSION:-$E2E_SESSION_NAME}" 2>/dev/null || true
    if [ -n "${E2E_ROOT:-}" ] && [ -d "$E2E_ROOT" ]; then
        local real_path
        real_path="$(realpath "$E2E_ROOT")"
        # D002 guard: only delete if path is under PROJECT_ROOT/.tmp/
        if [[ "$real_path" == "$(realpath "${PROJECT_ROOT:-.}")/.tmp/"* ]]; then
            rm -rf "$E2E_ROOT"
        else
            echo "teardown: REFUSED rm -rf on '$real_path' (not under .tmp/)" >&2
        fi
    fi
}

reset_queues() {
    local agents=("${E2E_DEFAULT_AGENTS[@]}" "shogun")
    for agent in "${agents[@]}"; do
        echo "messages: []" > "$E2E_QUEUE/queue/inbox/${agent}.yaml"
    done
    rm -f "$E2E_QUEUE"/queue/tasks/*.yaml
    rm -f "$E2E_QUEUE"/queue/reports/*.yaml
}

start_inbox_watcher() {
    local agent_id="$1"
    local pane_idx="$2"
    local cli_type="${3:-claude}"
    local target
    target="$(pane_target "$pane_idx")"
    local log_file="$E2E_ROOT/inbox_watcher_${agent_id}.log"

    INOTIFY_TIMEOUT="${E2E_INOTIFY_TIMEOUT:-5}" \
    BACKOFF_SEC="${E2E_BACKOFF_SEC:-20}" \
    SHOGUN_STATE_DIR="${SHOGUN_STATE_DIR:-$E2E_ROOT/state}" \
    bash "$E2E_QUEUE/scripts/inbox_watcher.sh" "$agent_id" "$target" "$cli_type" >"$log_file" 2>&1 &

    echo "$!"
}

stop_inbox_watcher() {
    local pid="$1"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}
