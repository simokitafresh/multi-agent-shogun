#!/usr/bin/env bash
# semantic-links: [[cmd_4408_ext4移設]], [[可逆切替]], [[9p_git_flock_RPC待ち_本日停滞3系統]]
# Prepare a safe, reversible switch from the WSL /mnt/c tree to ext4.
set -euo pipefail

OLD_ROOT="${OLD_ROOT:-/mnt/c/tools/multi-agent-shogun}"
NEW_ROOT="${NEW_ROOT:-/home/simokitafresh/multi-agent-shogun}"
STATE_BACKUP="$NEW_ROOT/.migrate_to_ext4_crontab.backup"
MARKER="$OLD_ROOT/MIGRATED_TO_EXT4.txt"
DRY_RUN=false
PROGRESS_INTERVAL_SEC="${CUTOVER_PROGRESS_INTERVAL_SEC:-10}"

while (($#)); do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) printf '%s\n' "Usage: $0 [--dry-run]"; exit 0 ;;
    *) printf 'ERROR: unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

blocked() { printf 'CUTOVER_BLOCKED: %s\n' "$1" >&2; exit 2; }

progress_interval() {
  [[ "$PROGRESS_INTERVAL_SEC" =~ ^[1-9][0-9]*$ ]] || PROGRESS_INTERVAL_SEC=10
  printf '%s\n' "$PROGRESS_INTERVAL_SEC"
}

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
  # Codex CLI: prompt line "› Ask Codex to do anything" followed by a status line;
  # Claude CLI: "❯ " prompt followed by a "⏵⏵ bypass permissions" status line.
  # Neither CLI leaves the prompt marker on the last non-empty line, so inspect the
  # last 8 non-empty lines for a prompt marker and reject if any busy marker remains.
  local capture tail8
  capture="$(tmux capture-pane -t "$1" -p -J -S -30 2>/dev/null)" || return 1
  tail8="$(printf '%s\n' "$capture" | sed '/^[[:space:]]*$/d' | tail -8)"
  printf '%s\n' "$tail8" | grep -Eq 'esc to interrupt|Working \(|Do you want to proceed|Press enter to continue' && return 1
  printf '%s\n' "$tail8" | grep -Eq '^[[:space:]]*(›|❯)' && return 0
  printf '%s\n' "$tail8" | tail -1 | grep -Eq '^[[:space:]]*\$[[:space:]]*$'
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

run_rsync_with_progress() {
  local rsync_pid started elapsed interval
  interval="$(progress_interval)"
  started="$(date +%s)"
  rsync -a "$OLD_ROOT/" "$NEW_ROOT/" &
  rsync_pid=$!
  while [[ -r "/proc/$rsync_pid/stat" ]]; do
    [[ "$(awk '{print $3}' "/proc/$rsync_pid/stat" 2>/dev/null)" == "Z" ]] && break
    sleep "$interval"
    [[ -r "/proc/$rsync_pid/stat" ]] || break
    [[ "$(awk '{print $3}' "/proc/$rsync_pid/stat" 2>/dev/null)" == "Z" ]] && break
    elapsed=$(( $(date +%s) - started ))
    printf '[cutover] progress: rsync active elapsed=%ss interval=%ss\n' "$elapsed" "$interval"
  done
  wait "$rsync_pid"
  elapsed=$(( $(date +%s) - started ))
  printf '[cutover] progress: rsync complete elapsed=%ss\n' "$elapsed"
}

commit_relocated_changes() {
  local helper="$NEW_ROOT/scripts/ninja_scope_commit.sh"
  local -a changed_paths=()
  if [[ ! -f "$helper" ]]; then
    printf '[cutover] scope commit skipped: helper unavailable at %s\n' "$helper"
    return 0
  fi
  mapfile -t changed_paths < <(git -C "$NEW_ROOT" diff --name-only -- 2>/dev/null || true)
  if [[ "${#changed_paths[@]}" -eq 0 ]]; then
    printf '[cutover] scope commit skipped: relocate produced no tracked diff\n'
    return 0
  fi
  printf '[cutover] scope commit: %s tracked path(s)\n' "${#changed_paths[@]}"
  (cd "$NEW_ROOT" && bash "$helper" \
    -m 'cmd_karo_hotfix_t102_t91_ext4_cutover_complete_20260828: relocate old-root references' -- \
    "${changed_paths[@]}")
}

rebackup_ready_files() {
  local ready_dir="$NEW_ROOT/queue" archive_dir file moved=0
  archive_dir="$NEW_ROOT/queue/archive/stale_ready_$(date +%Y%m%d)"
  [[ -d "$ready_dir" ]] || return 0
  shopt -s nullglob
  local -a ready_files=("$ready_dir"/*_ready.yaml)
  shopt -u nullglob
  if [[ "${#ready_files[@]}" -eq 0 ]]; then
    printf '[cutover] ready rebackup: none\n'
    return 0
  fi
  mkdir -p "$archive_dir"
  for file in "${ready_files[@]}"; do
    mv -- "$file" "$archive_dir/"
    moved=$((moved + 1))
  done
  printf '[cutover] ready rebackup: moved=%s archive=%s\n' "$moved" "$archive_dir"
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
  run_rsync_with_progress
  printf '[cutover] relocate old-root references in NEW_ROOT: %s\n' "$NEW_ROOT"
  OLD_ROOT="$OLD_ROOT" NEW_ROOT="$NEW_ROOT" bash "$NEW_ROOT/scripts/migrate_to_ext4_relocate.sh"
  commit_relocated_changes
  rebackup_ready_files
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
  printf '%s\n' "DRY_RUN_SCOPE_COMMIT: would run ninja_scope_commit.sh after relocate; no files changed"
  printf '%s\n' "DRY_RUN_READY_REBACKUP: would move queue/*_ready.yaml to queue/archive/stale_ready_$(date +%Y%m%d); no files changed"
  printf '%s\n' "DRY_RUN_PROGRESS: would emit one rsync progress line every $(progress_interval)s"
  printf '%s\n' "DRY_RUN_NEXT: cd $NEW_ROOT && ./shutsujin_departure.sh"
  exit 0
fi
perform_cutover
