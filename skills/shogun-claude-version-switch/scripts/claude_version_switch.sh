#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(pwd)"
ACTION="${1:-}"
DRY_RUN=false
SETTINGS_ONLY=false
TARGET_AGENT=""

PINNED_CMD="/home/simokitafresh/bin/claude --dangerously-skip-permissions"
LATEST_CMD="/home/simokitafresh/.local/bin/claude --dangerously-skip-permissions"
PINNED_BIN="/home/simokitafresh/bin/claude"
PINNED_BACKUP="/home/simokitafresh/.local/bin/claude.pinned"
PINNED_STABLE="/home/simokitafresh/claude-2.1.87-stable"
LATEST_BIN="/home/simokitafresh/.local/bin/claude"

usage() {
  cat <<'USAGE'
Usage: claude_version_switch.sh <status|pin-2.1.87|unpin-latest> [--agent <name>] [--repo <path>] [--dry-run] [--settings-only]

Actions:
  status         Show current launch_cmd, available binaries, and active Claude scope
  pin-2.1.87     Point launch_cmd at /home/simokitafresh/bin/claude and respawn Claude panes
  unpin-latest   Point launch_cmd at /home/simokitafresh/.local/bin/claude and respawn Claude panes

Options:
  --agent <name>     Target a single agent (pane-level switch via settings.yaml override)
  --repo <path>      Target multi-agent-shogun repository (default: current dir)
  --dry-run          Print actions only
  --settings-only    Update config only; do not respawn panes
USAGE
}

[[ -n "$ACTION" ]] || { usage >&2; exit 1; }
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
    --agent)
      [[ $# -lt 2 ]] && { echo "[ERROR] --agent requires a name" >&2; exit 1; }
      TARGET_AGENT="$2"
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
[[ -x "$SWITCH_SCRIPT" ]] || { echo "[ERROR] switch script not executable: $SWITCH_SCRIPT" >&2; exit 1; }

log() { echo "[claude-version] $*"; }

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

# --- per-agent override (settings.yaml) ---
SETTINGS_YAML="$REPO_ROOT/config/settings.yaml"

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
  if ! tmux has-session -t shogun 2>/dev/null; then
    log "No tmux session; config update only"
    return 0
  fi
  local pane
  pane=$(tmux list-panes -t shogun:2 -F '#{pane_index} #{@agent_id}' | awk -v a="$agent" '$2==a {print "shogun:2."$1}')
  if [[ -z "$pane" ]]; then
    log "Pane for $agent not found; skip respawn"
    return 0
  fi
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] respawn $pane with: $launch_cmd"
    return 0
  fi
  log "Respawning $agent ($pane) with: $launch_cmd"
  tmux respawn-pane -k -t "$pane" "cd $REPO_ROOT && $launch_cmd" 2>/dev/null || {
    log "Respawn failed for $agent"
    return 1
  }
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
