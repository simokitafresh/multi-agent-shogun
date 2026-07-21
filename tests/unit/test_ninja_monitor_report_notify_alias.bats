#!/usr/bin/env bats
# test_necessity: every canonical report completion alias is accepted as durable
# notification evidence, while a missing notification still blocks clear.

setup() {
  TEST_ROOT="$(mktemp -d)"
  mkdir -p "$TEST_ROOT/scripts/lib" "$TEST_ROOT/queue/tasks" "$TEST_ROOT/queue/reports" \
    "$TEST_ROOT/queue/inbox" "$TEST_ROOT/archive/inbox" "$TEST_ROOT/data"
  cp scripts/lib/report_completion_events.sh "$TEST_ROOT/scripts/lib/"
  cat > "$TEST_ROOT/queue/tasks/hayate.yaml" <<'YAML'
task:
  task_id: cmd_alias_normal
  parent_cmd: cmd_alias
  deployed_at: '2026-07-19T14:00:00+09:00'
YAML
  cat > "$TEST_ROOT/queue/reports/hayate_report_cmd_alias.yaml" <<'YAML'
task_id: cmd_alias_normal
parent_cmd: cmd_alias
timestamp: '2026-07-19T14:01:00+09:00'
YAML
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "completion alias SSOT contains all seven terminal event types" {
  run bash -c 'source scripts/lib/report_completion_events.sh; for t in report_received report_submitted task_done report_completed report_done report_ready task_failed; do report_completion_event_type "$t" || exit 1; done; [ "$(wc -w <<<"$REPORT_COMPLETION_EVENT_TYPES")" -eq 7 ]'
  [ "$status" -eq 0 ]
}

@test "monitor completion paths may source the shared contract twice" {
  run bash -c '
    # report_notification_completed source order in ninja_monitor.sh
    source scripts/lib/report_completion_events.sh
    first_types=$REPORT_COMPLETION_EVENT_TYPES
    first_regex=$(report_completion_event_types_regex)
    # scan_completed_reports source order in ninja_monitor.sh
    source scripts/lib/report_completion_events.sh
    [ "$REPORT_COMPLETION_EVENT_TYPES" = "$first_types" ]
    [ "$(report_completion_event_types_regex)" = "$first_regex" ]
    for t in report_received report_submitted task_done report_completed report_done report_ready task_failed; do
      report_completion_event_type "$t" || exit 1
    done
    [ "$(wc -w <<<"$REPORT_COMPLETION_EVENT_TYPES")" -eq 7 ]
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "monitor durable evidence uses shared completion alias contract" {
  run python3 - <<'PY'
from pathlib import Path
s=Path('scripts/ninja_monitor.sh').read_text()
assert 'completion_types = frozenset(sys.argv[4].split())' in s
assert 'not in completion_types' in s
assert 'for event_type in completion_types' in s
assert "completion_types=set(completion_event_types.split())" in s
PY
  [ "$status" -eq 0 ]
}

@test "inbox acceptance uses shared completion alias contract" {
  run bash -c "grep -q 'source.*report_completion_events.sh' scripts/inbox_write.sh && grep -q 'report_completion_event_type' scripts/inbox_write.sh"
  [ "$status" -eq 0 ]
}

@test "valid report_submitted evidence clears while a true missing notification blocks" {
  cat > "$TEST_ROOT/queue/inbox/karo.yaml" <<'YAML'
messages:
- type: report_submitted
  from: hayate
  timestamp: '2026-07-19T14:02:00+09:00'
  report_path: queue/reports/hayate_report_cmd_alias.yaml
  task_id: cmd_alias_normal
  parent_cmd: cmd_alias
YAML
  run env TEST_ROOT="$TEST_ROOT" PROJECT_ROOT="$PWD" bash -c '
    export NINJA_MONITOR_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
    SCRIPT_DIR="$TEST_ROOT"
    LOG="$TEST_ROOT/monitor.log"
    notify_karo_throttled(){ printf "FIRE\n" >> "$TEST_ROOT/fire.log"; }
    run_test_speed_completion_callback(){ return 0; }
    report_notification_completed hayate "$TEST_ROOT/queue/reports/hayate_report_cmd_alias.yaml" test
    : > "$TEST_ROOT/queue/inbox/karo.yaml"
    if report_notification_completed hayate "$TEST_ROOT/queue/reports/hayate_report_cmd_alias.yaml" test; then exit 9; fi
    [ "$(grep -c FIRE "$TEST_ROOT/fire.log")" -eq 1 ]
  '
  [ "$status" -eq 0 ]
  [ "$(grep -c 'REPORT-NOTIFY-MISSING-BLOCK' "$TEST_ROOT/monitor.log")" -eq 1 ]
}

@test "exact current task_failed evidence clears while stale identity remains missing" {
  cat > "$TEST_ROOT/queue/inbox/karo.yaml" <<'YAML'
messages:
- type: task_failed
  from: hayate
  timestamp: '2026-07-19T14:02:00+09:00'
  report_path: queue/reports/hayate_report_cmd_alias.yaml
  task_id: cmd_alias_normal
  parent_cmd: cmd_alias
YAML
  run env TEST_ROOT="$TEST_ROOT" PROJECT_ROOT="$PWD" bash -c '
    export NINJA_MONITOR_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
    SCRIPT_DIR="$TEST_ROOT"; LOG="$TEST_ROOT/monitor.log"
    notify_karo_throttled(){ printf "FIRE\n" >> "$TEST_ROOT/fire.log"; }
    run_test_speed_completion_callback(){ return 0; }
    report_notification_completed hayate "$TEST_ROOT/queue/reports/hayate_report_cmd_alias.yaml" current
    sed -i "s/cmd_alias_normal/cmd_stale_normal/; s/cmd_alias/cmd_stale/g" "$TEST_ROOT/queue/inbox/karo.yaml"
    if report_notification_completed hayate "$TEST_ROOT/queue/reports/hayate_report_cmd_alias.yaml" stale; then exit 9; fi
    [ "$(grep -c FIRE "$TEST_ROOT/fire.log")" -eq 1 ]
  '
  [ "$status" -eq 0 ]
}

@test "monitor repairs a persisted completed report through the canonical publisher" {
  cat >"$TEST_ROOT/queue/tasks/hayate.yaml" <<'YAML'
task:
  task_id: cmd_alias_normal
  parent_cmd: cmd_alias
  report_path: queue/reports/hayate_report_cmd_alias.yaml
  status: in_progress
YAML
  cat >>"$TEST_ROOT/queue/reports/hayate_report_cmd_alias.yaml" <<'YAML'
status: completed
worker_id: hayate
YAML
  cat >"$TEST_ROOT/fake_inbox.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_ROOT/events"
SH
  run env TEST_ROOT="$TEST_ROOT" PROJECT_ROOT="$PWD" bash -c '
    export NINJA_MONITOR_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
    SCRIPT_DIR="$TEST_ROOT"
    NINJA_NAMES=(hayate)
    REPORT_OUTBOX_INBOX_WRITE_PATH="$TEST_ROOT/fake_inbox.sh"
    export TEST_ROOT REPORT_OUTBOX_INBOX_WRITE_PATH
    repair_terminal_report_outboxes
  '
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$TEST_ROOT/events")" -eq 1 ]
  grep -q 'karo hayate報告完了.*report=hayate_report_cmd_alias.yaml report_received hayate notify_karo' "$TEST_ROOT/events"
}

@test "steady terminal task runs twenty monitor loops with zero publisher calls" {
  cat >"$TEST_ROOT/queue/tasks/hayate.yaml" <<'YAML'
task:
  task_id: cmd_alias_normal
  parent_cmd: cmd_alias
  report_path: queue/reports/hayate_report_cmd_alias.yaml
  status: done
YAML
  cat >>"$TEST_ROOT/queue/reports/hayate_report_cmd_alias.yaml" <<'YAML'
status: completed
worker_id: hayate
YAML
  cat >"$TEST_ROOT/fake_inbox.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_ROOT/events"
SH
  run env TEST_ROOT="$TEST_ROOT" PROJECT_ROOT="$PWD" bash -c '
    export NINJA_MONITOR_LIB_ONLY=1
    source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
    SCRIPT_DIR="$TEST_ROOT"
    NINJA_NAMES=(hayate)
    REPORT_OUTBOX_INBOX_WRITE_PATH="$TEST_ROOT/fake_inbox.sh"
    export TEST_ROOT REPORT_OUTBOX_INBOX_WRITE_PATH
    for _ in $(seq 1 20); do repair_terminal_report_outboxes; done
    [ ! -e "$TEST_ROOT/events" ]
  '
  [ "$status" -eq 0 ]
}
