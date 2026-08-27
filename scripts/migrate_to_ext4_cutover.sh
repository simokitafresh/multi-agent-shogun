#!/usr/bin/env bash
# semantic-links: [[cmd_4408_ext4移設]], [[可逆切替]], [[9p_git_flock_RPC待ち_本日停滞3系統]]
# Prepare a safe, reversible switch from the WSL /mnt/c tree to ext4.
set -euo pipefail

OLD_ROOT="${OLD_ROOT:-/mnt/c/tools/multi-agent-shogun}"
NEW_ROOT="${NEW_ROOT:-/home/simokitafresh/multi-agent-shogun}"
STATE_BACKUP="$NEW_ROOT/.migrate_to_ext4_crontab.backup"
MARKER="$OLD_ROOT/MIGRATED_TO_EXT4.txt"
DRY_RUN=false

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) printf '%s\n' "Usage: $0 [--dry-run]"; exit 0 ;;
    *) printf 'ERROR: unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

blocked() { printf 'CUTOVER_BLOCKED: %s\n' "$1" >&2; exit 2; }

task_statuses_are_idle() {
  local result
  result="$(python3 - "$OLD_ROOT/queue/tasks" <<'PY'
import glob, os, sys, yaml
bad = []
for path in sorted(glob.glob(os.path.join(sys.argv[1], "*.yaml"))):
    try:
        data = yaml.safe_load(open(path, encoding="utf-8")) or {}
        task = data.get("task", data)
        status = task.get("status")
    except Exception as exc:
        bad.append(f"{os.path.basename(path)}:parse_error:{exc}")
        continue
    if status != "idle":
        bad.append(f"{os.path.basename(path)}:{status}")
if bad:
    print("\n".join(bad))
    raise SystemExit(1)
PY
)" || { printf 'non_idle_tasks:\n%s\n' "$result" >&2; return 1; }
}

pane_for_agent() {
  tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}|#{@agent_id}' 2>/dev/null \
    | awk -F'|' -v wanted="$1" '$2 == wanted { print $1; exit }'
}

pane_is_input_waiting() {
  local capture last
  capture="$(tmux capture-pane -t "$1" -p -J -S -30 2>/dev/null)" || return 1
  last="$(printf '%s\n' "$capture" | sed '/^[[:space:]]*$/d' | tail -1)"
  [[ "$last" =~ (›|❯)[[:space:]]*$ ]] || [[ "$last" =~ ^[[:space:]]*\$[[:space:]]*$ ]]
}

management_panes_are_waiting() {
  local agent pane
  for agent in karo gunshi; do
    pane="$(pane_for_agent "$agent")"
    [[ -n "$pane" ]] || { printf 'missing_pane:%s\n' "$agent" >&2; return 1; }
    pane_is_input_waiting "$pane" || {
      printf 'pane_not_waiting:%s:%s\n' "$agent" "$pane" >&2
      return 1
    }
  done
}

cron_contains_old_root() {
  [[ "$1" == *"$OLD_ROOT"* ]]
}

preflight() {
  [[ -d "$OLD_ROOT" ]] || blocked "old root missing: $OLD_ROOT"
  [[ -d "$OLD_ROOT/queue/tasks" ]] || blocked "task directory missing: $OLD_ROOT/queue/tasks"
  [[ -d "$NEW_ROOT" ]] || blocked "new root missing: $NEW_ROOT"
  [[ ! -e "$MARKER" ]] || blocked "migration marker already exists: $MARKER"
  task_statuses_are_idle || blocked "all ninja task YAML statuses must be idle"
  management_panes_are_waiting || blocked "karo and gunshi panes must be input-waiting"
  local cron_text
  cron_text="$(crontab -l 2>/dev/null || true)"
  cron_contains_old_root "$cron_text" || blocked "crontab old-root entries not found"
}

perform_cutover() {
  local cron_text rewritten cron_tmp memory_src memory_dst
  cron_text="$(crontab -l 2>/dev/null || true)"
  cron_contains_old_root "$cron_text" || blocked "crontab changed after preflight"
  printf '[cutover] final rsync: %s -> %s\n' "$OLD_ROOT" "$NEW_ROOT"
  rsync -a "$OLD_ROOT/" "$NEW_ROOT/"
  printf '[cutover] relocate old-root references in NEW_ROOT: %s\n' "$NEW_ROOT"
  OLD_ROOT="$OLD_ROOT" NEW_ROOT="$NEW_ROOT" bash "$NEW_ROOT/scripts/migrate_to_ext4_relocate.sh"
  umask 077
  printf '%s\n' "$cron_text" > "$STATE_BACKUP"
  rewritten="${cron_text//"$OLD_ROOT"/$NEW_ROOT}"
  cron_tmp="$(mktemp)"
  trap 'rm -f -- "$cron_tmp"' RETURN
  printf '%s\n' "$rewritten" > "$cron_tmp"
  crontab "$cron_tmp"
  memory_src="${HOME:?}/.claude/projects/-mnt-c-tools-multi-agent-shogun"
  memory_dst="${HOME:?}/.claude/projects/-home-simokitafresh-multi-agent-shogun"
  if [[ -d "$memory_src" ]]; then
    mkdir -p "$memory_dst"
    cp -a "$memory_src/." "$memory_dst/"
    printf '[cutover] auto-memory copied: %s -> %s\n' "$memory_src" "$memory_dst"
  else
    printf '[cutover] auto-memory source absent; copy skipped: %s\n' "$memory_src"
  fi
  {
    printf 'READ_ONLY=true\n'
    printf 'migrated_at=%s\n' "$(date --iso-8601=seconds)"
    printf 'old_root=%s\nnew_root=%s\n' "$OLD_ROOT" "$NEW_ROOT"
    printf 'rollback_backup=%s\n' "$STATE_BACKUP"
  } > "$MARKER"
  printf '%s\n' "[cutover] old tree marked read-only: $MARKER"
  printf '%s\n' "cd $NEW_ROOT && ./shutsujin_departure.sh"
}

preflight
if "$DRY_RUN"; then
  printf '%s\n' 'DRY_RUN: preflight PASS; no rsync, crontab, auto-memory, marker, tmux restart, or agent launch performed'
  printf '%s\n' "DRY_RUN_RELOCATE: would run after final rsync in $NEW_ROOT; no files changed"
  printf '%s\n' "DRY_RUN_NEXT: cd $NEW_ROOT && ./shutsujin_departure.sh"
  exit 0
fi
perform_cutover
