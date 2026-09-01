#!/usr/bin/env bats
# test_necessity: A failed task generation with unreviewed work must never be
# respawned before archive.done or its generation-exact terminal FAIL report closes it.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TEST_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$TEST_ROOT/queue/tasks" "$TEST_ROOT/queue/reports" \
    "$TEST_ROOT/queue/gates" "$TEST_ROOT/state"
  SCRIPT_DIR="$TEST_ROOT"
  STATE_DIR="$TEST_ROOT/state"
  LOG="$TEST_ROOT/monitor.log"
  EPOCHSECONDS=100
  source <(sed -n '/^_failed_task_has_matching_karo_fail_close()/,/^report_notification_completed()/p' \
    "$ROOT/scripts/ninja_monitor.sh" | sed '$d')
  yaml_field_get() {
    python3 - "$1" "$2" <<'PY'
import sys,yaml
d=yaml.safe_load(open(sys.argv[1])) or {}
for p in sys.argv[2].split('.'): d=d.get(p, {}) if isinstance(d,dict) else {}
print(d if not isinstance(d,(dict,list)) else "")
PY
  }
  log() { printf '%s\n' "$*" >>"$LOG"; }
  notify_count=0
  notify_karo_durable() { notify_count=$((notify_count+1)); return "${NOTIFY_RC:-0}"; }
  _failed_respawn_generation_fingerprint() {
    yaml_field_get "$SCRIPT_DIR/queue/tasks/$1.yaml" task_id
  }
  find_matching_report_file() {
    local p="$SCRIPT_DIR/queue/reports/$1.yaml"
    [ -f "$p" ] && printf '%s\n' "$p"
  }
  review_report_key() { printf 'report-key\n'; }
  review_report_fingerprint() { sha256sum "$1" | awk '{print $1}'; }
  review_approval_value() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 1
    awk -F': ' -v key="$key" '$1 == key {sub(/^[^:]*: /, ""); print; exit}' "$file"
  }
}

write_task() {
  local id="${1:-generation-a}"
  printf 'task_id: %s\nparent_cmd: cmd_x\nstatus: failed\ntarget_path: [owned.sh]\n' "$id" \
    >"$SCRIPT_DIR/queue/tasks/saizo.yaml"
}

write_fail_report() {
  local status="${1:-completed}"
  printf 'task_id: generation-a\nparent_cmd: cmd_x\nstatus: %s\nverdict: FAIL\n' "$status" >"$SCRIPT_DIR/queue/reports/saizo.yaml"
}

write_karo_approval() {
  local fp="${1:-$(sha256sum "$SCRIPT_DIR/queue/reports/saizo.yaml" | awk '{print $1}')}"
  local report="${2:-queue/reports/saizo.yaml}"
  mkdir -p "$SCRIPT_DIR/queue/gates/cmd_x/review_approvals/reports/report-key"
  printf 'role: karo\nresult: ACCEPT\nreport: %s\nfingerprint: %s\n' "$report" "$fp" \
    >"$SCRIPT_DIR/queue/gates/cmd_x/review_approvals/reports/report-key/karo.yaml"
}

@test "failed+dirty+pending blocks respawn and notifies once" {
  write_task
  printf dirty >"$TEST_ROOT/owned.sh"
  run _failed_task_preserve_before_respawn saizo
  [ "$status" -eq 0 ]
  run _failed_task_preserve_before_respawn saizo
  [ "$status" -eq 0 ]
  [ "$(grep -c '^generation-a$' "$STATE_DIR/failed_task_preserve_saizo.fp")" -eq 1 ]
}

@test "failed+clean+pending also blocks respawn" {
  write_task
  run _failed_task_preserve_before_respawn saizo
  [ "$status" -eq 0 ]
}

@test "archive.done formally closes failed generation and permits respawn" {
  write_task
  mkdir -p "$SCRIPT_DIR/queue/gates/cmd_x"
  touch "$SCRIPT_DIR/queue/gates/cmd_x/archive.done"
  run _failed_task_preserve_before_respawn saizo
  [ "$status" -eq 1 ]
}

@test "bare terminal FAIL report remains pending without Karo fail-close" {
  write_task
  write_fail_report
  REPORT_ACCEPTED_RC=0
  run _failed_task_preserve_before_respawn saizo
  [ "$status" -eq 0 ]
}

@test "matching Karo ACCEPT formally closes failed generation" {
  write_task
  write_fail_report failed
  write_karo_approval
  run _failed_task_preserve_before_respawn saizo
  [ "$status" -eq 1 ]
}

@test "status failed plus matching Karo ACCEPT formally closes failed generation" {
  write_task
  write_fail_report failed
  write_karo_approval
  run _failed_task_preserve_before_respawn saizo
  [ "$status" -eq 1 ]
}

@test "mismatched terminal FAIL report does not close current task generation" {
  write_task
  write_fail_report
  sed -i 's/task_id: generation-a/task_id: stale-generation/' "$SCRIPT_DIR/queue/reports/saizo.yaml"
  run _failed_task_preserve_before_respawn saizo
  [ "$status" -eq 0 ]
}

@test "redeploy generation gets a distinct exactly-once notification marker" {
  write_task generation-a
  _failed_task_preserve_before_respawn saizo
  write_task generation-b
  _failed_task_preserve_before_respawn saizo
  [ "$(cat "$STATE_DIR/failed_task_preserve_saizo.fp")" = generation-b ]
}

@test "notification persistence failure leaves generation retryable" {
  write_task
  NOTIFY_RC=1
  run _failed_task_preserve_before_respawn saizo
  [ "$status" -eq 0 ]
  [ ! -e "$STATE_DIR/failed_task_preserve_saizo.fp" ]
  NOTIFY_RC=0
  run _failed_task_preserve_before_respawn saizo
  [ "$status" -eq 0 ]
  [ -e "$STATE_DIR/failed_task_preserve_saizo.fp" ]
}
