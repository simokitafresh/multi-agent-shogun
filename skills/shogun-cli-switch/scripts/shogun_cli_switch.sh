#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(pwd)"
ACTION="${1:-}"
DRY_RUN=false
SETTINGS_ONLY=false
TARGET_AGENT=""
SCOPE="core"
PROBE_MODEL=""
PROBE_EFFORT=""
PROBE_TIER="default"
CODEX_BIN="${CODEX_BIN:-codex}"
OPUS46_1M_CMD="${OPUS46_1M_CMD:-$HOME/bin/claude --dangerously-skip-permissions --model 'claude-opus-4-6[1m]' --effort high}"

PINNED_CMD="${PINNED_CMD:-$HOME/bin/claude --dangerously-skip-permissions}"
LATEST_CMD="${LATEST_CMD:-$HOME/.local/bin/claude --dangerously-skip-permissions}"
PINNED_BIN="${PINNED_BIN:-$HOME/bin/claude}"
PINNED_BACKUP="${PINNED_BACKUP:-$HOME/.local/bin/claude.pinned}"
PINNED_STABLE="${PINNED_STABLE:-$HOME/claude-2.1.87-stable}"
LATEST_BIN="${LATEST_BIN:-$HOME/.local/bin/claude}"

usage() {
  cat <<'USAGE'
Usage: shogun_cli_switch.sh <status|pin-2.1.87|pin-opus-4.6-1m|unpin-latest|to-claude|to-codex|probe-codex> [--agent <name>] [--scope <core|all|csv>] [--repo <path>] [--dry-run] [--settings-only]

Actions:
  status         Show current launch_cmd, available binaries, and active Claude scope
  pin-2.1.87     Point launch_cmd at $HOME/bin/claude and respawn Claude panes
  pin-opus-4.6-1m
                 Pin one agent to Claude Code 2.1.87 + Opus 4.6 high + 1M context,
                 including /model default and runtime verification
  unpin-latest   Point launch_cmd at $HOME/.local/bin/claude and respawn Claude panes
  to-claude      Switch target agents to Claude CLI
  to-codex       Switch target agents to Codex CLI
  probe-codex    Probe a Codex model/effort in an ephemeral process; never respawn a worker pane

Options:
  --agent <name>     Target a single agent (pane-level switch via settings.yaml override)
  --scope <scope>    Target multiple agents for CLI switch: core, all, or comma-separated list
  --repo <path>      Target multi-agent-shogun repository (default: current dir)
  --dry-run          Print actions only
  --settings-only    Update config only; do not respawn panes
  --model <name>     Model for probe-codex
  --effort <level>   low|medium|high|xhigh for probe-codex
  --tier <tier>      default|auto|fast for probe-codex (default: default)
USAGE
}

if [[ -z "$ACTION" ]]; then
  usage >&2
  exit 1
fi
if [[ "$ACTION" == "-h" || "$ACTION" == "--help" ]]; then
  usage
  exit 0
fi
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -lt 2 ]] && { echo "[ERROR] --repo requires a path" >&2; exit 1; }
      REPO_ROOT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --settings-only)
      SETTINGS_ONLY=true
      shift
      ;;
    --model)
      [[ $# -lt 2 ]] && { echo "[ERROR] --model requires a name" >&2; exit 1; }
      PROBE_MODEL="$2"
      shift 2
      ;;
    --effort)
      [[ $# -lt 2 ]] && { echo "[ERROR] --effort requires a level" >&2; exit 1; }
      PROBE_EFFORT="$2"
      shift 2
      ;;
    --tier)
      [[ $# -lt 2 ]] && { echo "[ERROR] --tier requires a value" >&2; exit 1; }
      PROBE_TIER="$2"
      shift 2
      ;;
    --agent)
      [[ $# -lt 2 ]] && { echo "[ERROR] --agent requires a name" >&2; exit 1; }
      TARGET_AGENT="$2"
      shift 2
      ;;
    --scope)
      [[ $# -lt 2 ]] && { echo "[ERROR] --scope requires a value" >&2; exit 1; }
      SCOPE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

REPO_ROOT="$(realpath "$REPO_ROOT")"
CLI_PROFILES="$REPO_ROOT/config/cli_profiles.yaml"
SWITCH_SCRIPT="$REPO_ROOT/scripts/switch_cli_mode.sh"
RESTART_WATCHERS="$REPO_ROOT/scripts/restart_watchers.sh"

[[ -f "$CLI_PROFILES" ]] || { echo "[ERROR] cli_profiles not found: $CLI_PROFILES" >&2; exit 1; }
[[ -f "$SWITCH_SCRIPT" ]] || { echo "[ERROR] switch script not found: $SWITCH_SCRIPT" >&2; exit 1; }

log() { echo "[shogun-cli-switch] $*"; }

probe_codex_model() {
  [[ -n "$PROBE_MODEL" ]] || { echo "[ERROR] probe-codex requires --model" >&2; return 1; }
  case "$PROBE_EFFORT" in low|medium|high|xhigh) ;; *) echo "[ERROR] probe-codex requires --effort low|medium|high|xhigh" >&2; return 1 ;; esac
  case "$PROBE_TIER" in default|auto|fast) ;; *) echo "[ERROR] probe-codex --tier must be default|auto|fast" >&2; return 1 ;; esac

  local cfg="$HOME/.codex/config.toml" cfg_before="missing" cfg_after="missing"
  local panes_before="" panes_after="" output_file rc
  [[ -f "$cfg" ]] && cfg_before=$(sha256sum "$cfg" | awk '{print $1}')
  if tmux has-session -t shogun 2>/dev/null; then
    panes_before=$(tmux list-panes -a -F '#{pane_id}:#{pane_pid}' | sort)
  fi
  output_file=$(mktemp)
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] isolated probe: $CODEX_BIN exec --ephemeral --ignore-user-config --ignore-rules -m $PROBE_MODEL -c model_reasoning_effort=$PROBE_EFFORT -c service_tier=$PROBE_TIER"
    rm -f "$output_file"
    return 0
  fi

  set +e
  "$CODEX_BIN" exec --ephemeral --ignore-user-config --ignore-rules --skip-git-repo-check \
    -C "$REPO_ROOT" -m "$PROBE_MODEL" \
    -c "model_reasoning_effort=\"$PROBE_EFFORT\"" \
    -c "service_tier=\"$PROBE_TIER\"" --json \
    'Reply with exactly PROBE_OK. Do not call tools.' >"$output_file" 2>&1
  rc=$?
  set -e

  [[ -f "$cfg" ]] && cfg_after=$(sha256sum "$cfg" | awk '{print $1}')
  if tmux has-session -t shogun 2>/dev/null; then
    panes_after=$(tmux list-panes -a -F '#{pane_id}:#{pane_pid}' | sort)
  fi
  if [[ "$cfg_before" != "$cfg_after" || "$panes_before" != "$panes_after" ]]; then
    echo "[ERROR] isolated probe changed shared config or worker pane PID" >&2
    rm -f "$output_file"
    return 1
  fi
  if [[ $rc -ne 0 ]] || ! grep -q 'PROBE_OK' "$output_file"; then
    cat "$output_file" >&2
    rm -f "$output_file"
    return 1
  fi
  rm -f "$output_file"
  log "probe PASS model=$PROBE_MODEL effort=$PROBE_EFFORT tier=$PROBE_TIER config_unchanged=1 pane_pid_changes=0"
}

get_current_launch_cmd() {
  python3 - "$CLI_PROFILES" <<'PY'
import sys, yaml
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    cfg = yaml.safe_load(f) or {}
profiles = cfg.get("profiles", {})
claude = profiles.get("claude", {}) if isinstance(profiles, dict) else {}
print(claude.get("launch_cmd", ""))
PY
}

get_claude_scope() {
  REPO_ROOT="$REPO_ROOT" python3 - <<'PY'
import os, yaml
repo = os.environ["REPO_ROOT"]
settings_path = os.path.join(repo, "config", "settings.yaml")
with open(settings_path, "r", encoding="utf-8") as f:
    cfg = yaml.safe_load(f) or {}
cli = cfg.get("cli", {}) if isinstance(cfg, dict) else {}
default = cli.get("default", "claude") if isinstance(cli, dict) else "claude"
agents = cli.get("agents", {}) if isinstance(cli, dict) else {}

targets = ["shogun"]
for name in ["karo", "gunshi"]:
    row = agents.get(name, {})
    if isinstance(row, dict):
      kind = row.get("type", default)
    elif isinstance(row, str):
      kind = row
    else:
      kind = default
    if kind == "claude":
      targets.append(name)

for name, row in agents.items():
    if name in {"shogun", "karo", "gunshi"}:
        continue
    if isinstance(row, dict):
        kind = row.get("type", default)
    elif isinstance(row, str):
        kind = row
    else:
        kind = default
    if kind == "claude":
        targets.append(name)

seen = []
for name in targets:
    if name not in seen:
        seen.append(name)
print(",".join(seen))
PY
}

print_status() {
  local current scope
  current="$(get_current_launch_cmd)"
  scope="$(get_claude_scope)"

  echo "repo: $REPO_ROOT"
  echo "launch_cmd: $current"
  echo "claude_scope: ${scope:-<none>}"
  echo "pinned_bin: $PINNED_BIN"
  "$PINNED_BIN" --version 2>/dev/null || true
  echo "latest_bin: $LATEST_BIN"
  "$LATEST_BIN" --version 2>/dev/null || true
  if tmux has-session -t shogun 2>/dev/null; then
    echo "--- active panes ---"
    tmux list-panes -a -F '#S:#I.#P agent=#{@agent_id} cli=#{@agent_cli} model=#{@model_name}' | grep ' cli=claude ' || true
  fi
}

ensure_pinned_assets() {
  if [[ -x "$PINNED_BIN" ]]; then
    return 0
  fi
  if [[ -x "$PINNED_BACKUP" ]]; then
    log "Restoring $PINNED_BIN from $PINNED_BACKUP"
    [[ "$DRY_RUN" == true ]] || cp "$PINNED_BACKUP" "$PINNED_BIN"
  elif [[ -x "$PINNED_STABLE" ]]; then
    log "Restoring $PINNED_BIN from $PINNED_STABLE"
    [[ "$DRY_RUN" == true ]] || cp "$PINNED_STABLE" "$PINNED_BIN"
  else
    echo "[ERROR] No pinned 2.1.87 asset found" >&2
    exit 1
  fi
  [[ "$DRY_RUN" == true ]] || chmod +x "$PINNED_BIN"
}

pin_opus46_1m() {
  [[ -n "$TARGET_AGENT" ]] || {
    echo "[ERROR] pin-opus-4.6-1m requires --agent <name>" >&2
    return 1
  }
  [[ "$SETTINGS_ONLY" == false ]] || {
    echo "[ERROR] pin-opus-4.6-1m cannot use --settings-only; /model default runtime verification is mandatory" >&2
    return 1
  }
  ensure_pinned_assets

  local version pane state yaml_set respawn_script capture process_args pane_pid
  version=$("$PINNED_BIN" --version 2>/dev/null || true)
  [[ "$version" == "2.1.87 (Claude Code)" ]] || {
    echo "[ERROR] pinned binary is not Claude Code 2.1.87: ${version:-unreadable}" >&2
    return 1
  }
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] $TARGET_AGENT type=claude"
    log "[dry-run] $TARGET_AGENT model_name=claude-opus-4-6"
    log "[dry-run] $TARGET_AGENT launch_cmd=$OPUS46_1M_CMD"
    log "[dry-run] respawn $TARGET_AGENT, send /model default, require two 1M confirmations"
    return 0
  fi
  pane=$(agent_pane_target "$TARGET_AGENT" 2>/dev/null || true)
  [[ -n "$pane" ]] || {
    echo "[ERROR] pane not found for agent: $TARGET_AGENT" >&2
    return 1
  }
  pane_pid=$(tmux display-message -t "$pane" -p '#{pane_pid}' 2>/dev/null || true)
  capture=$(tmux capture-pane -t "$pane" -p -S -40 2>/dev/null || true)
  process_args=$(ps -o args= -g "$pane_pid" 2>/dev/null || true)

  # Idempotent O(1) fast path: never respawn or send a command when the live
  # pane already proves the requested state.
  if [[ "$capture" == *"Claude Code v2.1.87"* &&
        "$capture" == *"Opus 4.6 (1M context) with high effort"* &&
        "$process_args" == *"$PINNED_BIN"* &&
        "$process_args" == *--model*claude-opus-4-6* &&
        "$process_args" == *"--effort high"* ]]; then
    log "PASS agent=$TARGET_AGENT version=2.1.87 model='Opus 4.6' context=1M effort=high confirmations=2/2 fast_path=already_correct"
    return 0
  fi

  state=$(agent_runtime_state "$TARGET_AGENT" "$pane")
  if [[ "$state" != idle:* ]]; then
    if check_agent_busy "$pane" "$TARGET_AGENT"; then
      log "Treating stale tmux state as idle after prompt verification: $TARGET_AGENT ($state)"
    else
      echo "[ERROR] refusing Opus 4.6 1M pin while $TARGET_AGENT is busy ($state)" >&2
      return 1
    fi
  fi

  yaml_set="$REPO_ROOT/scripts/lib/yaml_field_set.sh"
  respawn_script="$REPO_ROOT/scripts/agent_respawn.sh"
  [[ -x "$yaml_set" && -x "$respawn_script" ]] || {
    echo "[ERROR] required settings/respawn script is missing" >&2
    return 1
  }

  bash "$yaml_set" "$SETTINGS_YAML" "$TARGET_AGENT" type claude
  bash "$yaml_set" "$SETTINGS_YAML" "$TARGET_AGENT" model_name claude-opus-4-6
  bash "$yaml_set" "$SETTINGS_YAML" "$TARGET_AGENT" launch_cmd "$OPUS46_1M_CMD"

  # If the live process is already the pinned Opus command, do not respawn.
  # Otherwise mark this as a CLI switch so SessionStart skips heavy Recovery.
  if [[ "$process_args" != *"$PINNED_BIN"* ||
        "$process_args" != *--model*claude-opus-4-6* ||
        "$process_args" != *"--effort high"* ]]; then
    tmux set-option -p -t "$pane" @agent_state idle >/dev/null 2>&1 || true
    tmux set-option -p -t "$pane" @cli_switch_pending true >/dev/null 2>&1 || true
    bash "$respawn_script" "$TARGET_AGENT" cli-switch-opus46-1m

    local ready=0
    for _ in {1..80}; do
      capture=$(tmux capture-pane -t "$pane" -p -S -40 2>/dev/null || true)
      if [[ "$capture" == *"Claude Code v2.1.87"* &&
            "$capture" == *"Opus 4.6 with high effort"* &&
            "$capture" == *"❯"* ]] &&
            check_agent_busy "$pane" "$TARGET_AGENT"; then
        ready=1
        break
      fi
      sleep 0.25
    done
    [[ "$ready" -eq 1 ]] || {
      echo "[ERROR] pinned Opus 4.6 prompt did not become ready within 20s" >&2
      return 1
    }
  fi

  # This wrapper provides the same flock-protected command delivery boundary as
  # inbox_watcher, without direct tmux send-keys.
  # shellcheck source=/dev/null
  source "$REPO_ROOT/scripts/lib/tmux_utils.sh"
  safe_send_keys_atomic "$pane" "/model default" 0.3

  local verified=0
  for _ in {1..40}; do
    capture=$(tmux capture-pane -t "$pane" -p -S -40 2>/dev/null || true)
    if [[ "$capture" == *"Opus 4.6 (1M context) with high effort"* &&
          "$capture" == *"Set model to Opus 4.6 (1M context) (default)"* ]]; then
      verified=1
      break
    fi
    sleep 0.25
  done
  [[ "$verified" -eq 1 ]] || {
    echo "[ERROR] Opus 4.6 1M verification failed within 10s; both banner and /model result are required" >&2
    return 1
  }

  process_args=$(ps -o args= -g "$(tmux display-message -t "$pane" -p '#{pane_pid}')" 2>/dev/null || true)
  [[ "$process_args" == *"$PINNED_BIN"* &&
        "$process_args" == *--model*claude-opus-4-6* &&
        "$process_args" == *"--effort high"* ]] || {
    echo "[ERROR] runtime process does not match pinned Opus 4.6 high command" >&2
    return 1
  }
  log "PASS agent=$TARGET_AGENT version=2.1.87 model='Opus 4.6' context=1M effort=high confirmations=2/2"
}

set_launch_cmd() {
  local new_cmd="$1"
  local backup_path
  backup_path="${CLI_PROFILES}.bak.$(date +%Y%m%d_%H%M%S)"

  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] launch_cmd -> $new_cmd"
    return 0
  fi

  cp "$CLI_PROFILES" "$backup_path"
  log "Backup created: $backup_path"

  CLI_PROFILES="$CLI_PROFILES" NEW_CMD="$new_cmd" python3 - <<'PY'
import os, re
path = os.environ["CLI_PROFILES"]
new_cmd = os.environ["NEW_CMD"]

with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()

out = []
in_profiles = False
in_claude = False
replaced = False

for line in lines:
    stripped = line.rstrip()
    indent = len(line) - len(line.lstrip())
    if not in_profiles:
        if re.match(r'^profiles\s*:', stripped):
            in_profiles = True
        out.append(line)
        continue
    if not in_claude:
        if re.match(r'^  claude\s*:', stripped):
            in_claude = True
        out.append(line)
        continue
    # inside claude block
    if indent >= 4 or line.strip() == "" or line.strip().startswith("#"):
        if line.strip().startswith("launch_cmd:"):
            out.append(f"    launch_cmd: {new_cmd}\n")
            replaced = True
            continue
        out.append(line)
        continue
    else:
        if not replaced:
            out.append(f"    launch_cmd: {new_cmd}\n")
            replaced = True
        in_claude = False
        out.append(line)
        continue

if in_claude and not replaced:
    out.append(f"    launch_cmd: {new_cmd}\n")

with open(path, "w", encoding="utf-8") as f:
    f.writelines(out)
PY
}

# --- runtime / per-agent helpers ---
SETTINGS_YAML="$REPO_ROOT/config/settings.yaml"

source "$REPO_ROOT/lib/agent_state.sh"

resolve_window_target() {
  local named_target="$1"
  local indexed_target="$2"
  if tmux list-panes -t "$named_target" >/dev/null 2>&1; then
    echo "$named_target"
  else
    echo "$indexed_target"
  fi
}

find_agent_pane() {
  local agent="$1"
  local agents_window
  agents_window=$(resolve_window_target "shogun:agents" "shogun:2")

  local pane_idx
  pane_idx=$(tmux list-panes -t "$agents_window" -F '#{pane_index} #{@agent_id}' 2>/dev/null \
    | awk -v a="$agent" '$2==a {print $1; exit}')
  if [[ -n "$pane_idx" ]]; then
    echo "${agents_window}.${pane_idx}"
    return 0
  fi

  return 1
}

agent_pane_target() {
  local agent="$1"
  if [[ "$agent" == "shogun" ]]; then
    resolve_window_target "shogun:main" "shogun:1"
    return 0
  fi
  find_agent_pane "$agent"
}

agent_runtime_state() {
  local agent="$1"
  local pane="$2"
  local tmux_state task_status

  tmux_state=$(tmux display-message -t "$pane" -p '#{@agent_state}' 2>/dev/null || true)
  task_status=$(python3 - "$REPO_ROOT" "$agent" <<'PY'
import os, sys, yaml
repo, agent = sys.argv[1], sys.argv[2]
path = os.path.join(repo, "queue", "tasks", f"{agent}.yaml")
try:
    with open(path, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    task = data.get("task", data) if isinstance(data, dict) else {}
    print(task.get("status", ""))
except Exception:
    print("")
PY
)

  case "$tmux_state" in
    active|bash_running) echo "busy:${tmux_state}:${task_status}"; return 0 ;;
  esac
  case "$task_status" in
    assigned|acknowledged|in_progress|pending) echo "busy:${tmux_state:-unknown}:${task_status}"; return 0 ;;
  esac
  if check_agent_busy "$pane" "$agent"; then
    echo "idle:${tmux_state:-unknown}:${task_status:-none}"
  else
    echo "busy:${tmux_state:-unknown}:${task_status:-unknown}"
  fi
}

safe_respawn_agent() {
  local agent="$1" launch_cmd="$2"
  if ! tmux has-session -t shogun 2>/dev/null; then
    log "No tmux session; config update only"
    return 0
  fi
  local pane
  pane=$(agent_pane_target "$agent" 2>/dev/null || true)
  if [[ -z "$pane" ]]; then
    log "Pane for $agent not found; skip respawn"
    return 0
  fi
  local state
  state=$(agent_runtime_state "$agent" "$pane")
  if [[ "$state" != idle:* ]]; then
    log "SKIP respawn $agent ($pane): not idle ($state)"
    return 0
  fi
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] respawn $pane with: $launch_cmd"
    return 0
  fi
  log "Respawning idle $agent ($pane) with: $launch_cmd"
  tmux set-option -p -t "$pane" @agent_state active 2>/dev/null || true
  tmux respawn-pane -k -t "$pane" "cd $REPO_ROOT && $launch_cmd" 2>/dev/null || {
    log "Respawn failed for $agent"
    return 1
  }
}

set_agent_launch_cmd() {
  local agent="$1" new_cmd="$2"
  local backup_path
  backup_path="${SETTINGS_YAML}.bak.$(date +%Y%m%d_%H%M%S)"

  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] settings.yaml $agent launch_cmd -> $new_cmd"
    return 0
  fi

  cp "$SETTINGS_YAML" "$backup_path"
  log "Backup: $backup_path"

  SETTINGS_YAML="$SETTINGS_YAML" AGENT="$agent" NEW_CMD="$new_cmd" python3 - <<'PY'
import os, re
path = os.environ["SETTINGS_YAML"]
agent = os.environ["AGENT"]
new_cmd = os.environ["NEW_CMD"]

with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()

out = []
in_agent = False
agent_indent = ""
inserted = False
for i, line in enumerate(lines):
    stripped = line.rstrip()
    # Detect target agent block start
    if re.match(rf"^    {agent}:$", stripped) or re.match(rf"^    {agent}: ", stripped):
        in_agent = True
        agent_indent = "      "
        out.append(line)
        continue
    if in_agent:
        # Still inside agent block?
        if line.startswith(agent_indent) or line.strip() == "":
            # Replace existing launch_cmd
            if line.strip().startswith("launch_cmd:"):
                if new_cmd:
                    out.append(f"{agent_indent}launch_cmd: {new_cmd}\n")
                # else: remove the line (revert to default)
                inserted = True
                continue
            out.append(line)
            continue
        else:
            # Exiting agent block - insert launch_cmd if not yet inserted
            if not inserted and new_cmd:
                out.append(f"{agent_indent}launch_cmd: {new_cmd}\n")
                inserted = True
            in_agent = False
            out.append(line)
            continue
    out.append(line)

# Edge case: agent is last block
if in_agent and not inserted and new_cmd:
    out.append(f"{agent_indent}launch_cmd: {new_cmd}\n")

with open(path, "w", encoding="utf-8") as f:
    f.writelines(out)
PY
  log "settings.yaml $agent launch_cmd -> ${new_cmd:-<removed>}"
}

remove_agent_launch_cmd() {
  local agent="$1"
  local backup_path
  backup_path="${SETTINGS_YAML}.bak.$(date +%Y%m%d_%H%M%S)"

  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] settings.yaml $agent launch_cmd -> <removed>"
    return 0
  fi

  cp "$SETTINGS_YAML" "$backup_path"
  # Remove launch_cmd line from agent block
  SETTINGS_YAML="$SETTINGS_YAML" AGENT="$agent" python3 - <<'PY'
import os, re
path = os.environ["SETTINGS_YAML"]
agent = os.environ["AGENT"]

with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()

out = []
in_agent = False
for line in lines:
    stripped = line.rstrip()
    if re.match(rf"^    {agent}:$", stripped) or re.match(rf"^    {agent}: ", stripped):
        in_agent = True
        out.append(line)
        continue
    if in_agent:
        if line.startswith("      "):
            if line.strip().startswith("launch_cmd:"):
                continue  # skip = remove
            out.append(line)
            continue
        in_agent = False
    out.append(line)

with open(path, "w", encoding="utf-8") as f:
    f.writelines(out)
PY
  log "settings.yaml $agent launch_cmd removed (revert to profile default)"
}

respawn_single_agent() {
  local agent="$1" launch_cmd="$2"
  safe_respawn_agent "$agent" "$launch_cmd"
}

apply_runtime() {
  local scope="$1"
  [[ -n "$scope" ]] || { log "No Claude agents resolved; skip respawn"; return 0; }

  if ! tmux has-session -t shogun 2>/dev/null; then
    log "No tmux session 'shogun' found; config update only"
    return 0
  fi

  local extra=()
  [[ "$DRY_RUN" == true ]] && extra+=(--dry-run)

  log "Respawning Claude scope: $scope"
  bash "$SWITCH_SCRIPT" claude --scope "$scope" "${extra[@]}"

  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] skip watcher restart"
    return 0
  fi

  if [[ -x "$RESTART_WATCHERS" ]]; then
    log "Restarting inbox watchers"
    bash "$RESTART_WATCHERS"
  fi
}

apply_cli_switch() {
  local target_cli="$1"
  local switch_scope
  if [[ -n "$TARGET_AGENT" ]]; then
    switch_scope="$TARGET_AGENT"
  else
    switch_scope="$SCOPE"
  fi

  local args=()
  [[ "$DRY_RUN" == true ]] && args+=(--dry-run)
  [[ "$SETTINGS_ONLY" == true ]] && args+=(--no-relaunch)

  log "Switching CLI: target=${target_cli} scope=${switch_scope}"
  bash "$SWITCH_SCRIPT" "$target_cli" --scope "$switch_scope" "${args[@]}"
}

case "$ACTION" in
  status)
    print_status
    if [[ -n "$TARGET_AGENT" ]]; then
      echo "--- agent override ---"
      _override=$(grep -A8 "    ${TARGET_AGENT}:" "$SETTINGS_YAML" 2>/dev/null | grep 'launch_cmd:' | head -1 | sed 's/.*launch_cmd: //')
      echo "  $TARGET_AGENT override: ${_override:-<none (using profile default)>}"
    fi
    exit 0
    ;;
  to-claude)
    apply_cli_switch claude
    ;;
  to-codex)
    apply_cli_switch codex
    ;;
  probe-codex)
    probe_codex_model
    ;;
  pin-opus-4.6-1m)
    pin_opus46_1m
    ;;
  pin-2.1.87)
    ensure_pinned_assets
    if [[ -n "$TARGET_AGENT" ]]; then
      remove_agent_launch_cmd "$TARGET_AGENT"
      if [[ "$SETTINGS_ONLY" == false ]]; then
        respawn_single_agent "$TARGET_AGENT" "$PINNED_CMD"
      fi
    else
      set_launch_cmd "$PINNED_CMD"
      if [[ "$SETTINGS_ONLY" == false ]]; then
        apply_runtime "$(get_claude_scope)"
      fi
    fi
    ;;
  unpin-latest)
    [[ -x "$LATEST_BIN" ]] || { echo "[ERROR] Latest Claude binary not found: $LATEST_BIN" >&2; exit 1; }
    if [[ -n "$TARGET_AGENT" ]]; then
      set_agent_launch_cmd "$TARGET_AGENT" "$LATEST_CMD"
      if [[ "$SETTINGS_ONLY" == false ]]; then
        respawn_single_agent "$TARGET_AGENT" "$LATEST_CMD"
      fi
    else
      set_launch_cmd "$LATEST_CMD"
      if [[ "$SETTINGS_ONLY" == false ]]; then
        apply_runtime "$(get_claude_scope)"
      fi
    fi
    ;;
  *)
    echo "[ERROR] Unknown action: $ACTION" >&2
    usage >&2
    exit 1
    ;;
esac

echo
echo "Verification:"
echo "  tmux list-panes -a -F '#S:#I.#P agent=#{@agent_id} cli=#{@agent_cli} model=#{@model_name}'"
echo "  $PINNED_BIN --version"
echo "  $LATEST_BIN --version"
