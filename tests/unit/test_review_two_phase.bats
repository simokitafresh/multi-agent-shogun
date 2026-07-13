#!/usr/bin/env bats

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  TMPROOT=$(mktemp -d)
  mkdir -p "$TMPROOT/queue/gates/cmd_test/review_approvals/reports"
  mkdir -p "$TMPROOT/queue/reports"
  mkdir -p "$TMPROOT/queue/tasks"
  mkdir -p "$TMPROOT/scripts/lib"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/review_approval.sh"
  cat > "$TMPROOT/scripts/bulletin_write.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${REVIEW_APPROVAL_ROOT:?}/bulletin_calls.log"
SH
  chmod +x "$TMPROOT/scripts/bulletin_write.sh"
  REPORT="$TMPROOT/queue/reports/ninja_report_cmd_test.yaml"
  printf 'worker_id: ninja\nparent_cmd: cmd_test\nstatus: completed\ncommit_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nresult:\n  summary: ok\n' > "$REPORT"
  PROJECT_ROOT="$TMPROOT"
  source "$ROOT/scripts/lib/review_approval.sh"
  KEY=$(review_report_key "${REPORT#"$TMPROOT"/}")
  APPROVALS="$TMPROOT/queue/gates/cmd_test/review_approvals/reports/$KEY"
  mkdir -p "$APPROVALS"
}

setup_rc_task() {
  mkdir -p "$TMPROOT/scripts/lib" "$TMPROOT/queue/inbox"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  cp "$ROOT/scripts/lib/yaml_field_set.sh" "$TMPROOT/scripts/lib/"
  cp "$ROOT/scripts/report_field_set.sh" "$TMPROOT/scripts/report_field_set.sh"
  cp "$ROOT/scripts/inbox_write.sh" "$TMPROOT/scripts/inbox_write.sh"
  cat > "$TMPROOT/queue/tasks/ninja.yaml" <<'YAML'
task:
  parent_cmd: cmd_test
  status: done
  deployed_at: "2026-01-01T00:00:00+09:00"
  acknowledged_at: "2026-07-11T09:59:00+09:00"
  completed_at: "2026-07-11T10:00:00+09:00"
  done_at: "2026-07-11T10:01:00+09:00"
YAML
}
teardown() { rm -rf "$TMPROOT"; }

approve() {
  REVIEW_APPROVAL_ROOT="$TMPROOT" REVIEW_APPROVAL_NO_TRIGGER=1 \
    bash "$ROOT/scripts/review_approval.sh" cmd_test "$1" "$2" "$3"
}

@test "gunshi LGTM alone is not CLEAR" {
  fp=$(review_report_fingerprint "$REPORT")
  printf 'result: LGTM\nfingerprint: %s\n' "$fp" > "$APPROVALS/gunshi.yaml"
  ! review_two_phase_ready cmd_test "$REPORT"
}

@test "formal gunshi LGTM automatically persists a Shogun completion-review notice" {
  approve gunshi LGTM "$REPORT"
  [ "$(wc -l < "$TMPROOT/bulletin_calls.log")" -eq 1 ]
  grep -q '^gunshi cmd_test 完了レビュー LGTM .*家老ACCEPT/GATE判定待ち。 false info$' "$TMPROOT/bulletin_calls.log"
}

@test "regenerated report does not duplicate the gunshi LGTM notice before RC" {
  approve gunshi LGTM "$REPORT"
  printf 'result:\n  summary: regenerated\n' > "$REPORT"
  printf 'worker_id: ninja\nparent_cmd: cmd_test\nstatus: completed\ncommit_hash: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n' >> "$REPORT"
  approve gunshi LGTM "$REPORT"
  [ "$(wc -l < "$TMPROOT/bulletin_calls.log")" -eq 1 ]
  [ -f "$APPROVALS/gunshi_notice.sent" ]
}

@test "formal gunshi LGTM fails closed when Shogun notice cannot persist" {
  cat > "$TMPROOT/scripts/bulletin_write.sh" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "$TMPROOT/scripts/bulletin_write.sh"
  run approve gunshi LGTM "$REPORT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Shogun notification persistence failed"* ]]
}

@test "karo RC blocks and stale approvals cannot be reused" {
  fp=$(review_report_fingerprint "$REPORT")
  printf 'result: LGTM\nfingerprint: %s\n' "$fp" > "$APPROVALS/gunshi.yaml"
  printf 'result: RC\nfingerprint: %s\n' "$fp" > "$APPROVALS/karo.yaml"
  ! review_two_phase_ready cmd_test "$REPORT"
  printf 'changed: true\n' >> "$REPORT"
  printf 'result: ACCEPT\nfingerprint: %s\n' "$fp" > "$APPROVALS/karo.yaml"
  ! review_two_phase_ready cmd_test "$REPORT"
}

@test "matching LGTM and ACCEPT CLEAR exactly one fingerprint" {
  fp=$(review_report_fingerprint "$REPORT")
  printf 'result: LGTM\nfingerprint: %s\n' "$fp" > "$APPROVALS/gunshi.yaml"
  printf 'result: ACCEPT\nfingerprint: %s\n' "$fp" > "$APPROVALS/karo.yaml"
  review_two_phase_ready cmd_test "$REPORT"
}

@test "commit_hash missing is fail-closed" {
  printf 'result:\n  summary: ok\n' > "$REPORT"
  ! review_report_fingerprint "$REPORT"
  ! review_two_phase_ready cmd_test "$REPORT"
}

@test "no-code SCOUT without commit_hash fingerprints and clears two-phase approval" {
  printf 'parent_cmd: cmd_test\ntask_type: scout\nfiles_modified: []\nbinary_checks:\n  AC1:\n    - {check: inspected, result: yes}\nresult:\n  summary: ok\n' > "$REPORT"
  fp=$(review_report_fingerprint "$REPORT")
  [[ "$fp" == *":no-code-change" ]]
  printf 'result: LGTM\nfingerprint: %s\n' "$fp" > "$APPROVALS/gunshi.yaml"
  printf 'result: ACCEPT\nfingerprint: %s\n' "$fp" > "$APPROVALS/karo.yaml"
  review_two_phase_ready cmd_test "$REPORT"
}

@test "no-code RECON without commit_hash fingerprints" {
  printf 'parent_cmd: cmd_test\ntask_type: recon\nfiles_modified: []\nbinary_checks: {}\n' > "$REPORT"
  review_report_fingerprint "$REPORT"
}

@test "deployed SCOUT report remains self-contained after task YAML is overwritten" {
  mkdir -p "$TMPROOT/scripts/lib"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  cat > "$TMPROOT/queue/tasks/ninja.yaml" <<'YAML'
task:
  parent_cmd: cmd_test
  task_type: scout
YAML
  cat > "$REPORT" <<YAML
parent_cmd: cmd_test
task_type: scout
status: completed
files_modified:
  - path: queue/reports/ninja_report_cmd_test.yaml
    change: report artifact
binary_checks:
  AC1:
    - {check: inspected, result: yes}
result:
  summary: scout complete
YAML
  cat > "$TMPROOT/queue/tasks/ninja.yaml" <<'YAML'
task:
  parent_cmd: cmd_next
  task_type: implement
YAML
  fp=$(review_report_fingerprint "$REPORT")
  [[ "$fp" == *":no-code-change" ]]
  approve gunshi LGTM "$REPORT"
  approve karo ACCEPT "$REPORT"
  review_two_phase_ready cmd_test "$REPORT"
}

@test "SCOUT with modified files cannot omit commit_hash" {
  printf 'parent_cmd: cmd_test\ntask_type: scout\nfiles_modified: [scripts/example.sh]\nbinary_checks: {}\n' > "$REPORT"
  ! review_report_fingerprint "$REPORT"
}

@test "SCOUT claiming commit=yes cannot omit commit_hash" {
  printf 'parent_cmd: cmd_test\ntask_type: scout\nfiles_modified: []\nbinary_checks:\n  commit:\n    - {check: committed, result: yes}\n' > "$REPORT"
  ! review_report_fingerprint "$REPORT"
}

@test "implementation report without full commit_hash stays fail-closed" {
  printf 'parent_cmd: cmd_test\ntask_type: implement\nfiles_modified: []\n' > "$REPORT"
  ! review_report_fingerprint "$REPORT"
  printf 'commit_hash: abc123\n' >> "$REPORT"
  ! review_report_fingerprint "$REPORT"
}

@test "F1 review followed by F2 update does not bind delayed notification to F2" {
  mkdir -p "$TMPROOT/queue/reports" "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  local r="$TMPROOT/queue/reports/ninja_report_cmd_test.yaml"
  approve gunshi LGTM "$r"
  printf 'changed: true\n' >> "$r"
  ! review_two_phase_ready cmd_test "$r"
}

@test "either approval order formalizes once after the second approval" {
  mkdir -p "$TMPROOT/queue/reports" "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  local r="$TMPROOT/queue/reports/ninja_report_cmd_test.yaml"
  approve karo ACCEPT "$r"
  [ ! -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
  approve gunshi LGTM "$r"
  [ -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
  find "$TMPROOT/queue/gates/cmd_test/review_approvals" -maxdepth 1 -name '.gate_triggered.*' | grep -q .
}

@test "changed manifest gets its own single trigger generation" {
  mkdir -p "$TMPROOT/queue/reports" "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  local r="$TMPROOT/queue/reports/ninja_report_cmd_test.yaml"
  approve gunshi LGTM "$r"; approve karo ACCEPT "$r"
  printf 'generation: 2\n' >> "$r"
  approve gunshi LGTM "$r"; approve karo ACCEPT "$r"
  [ "$(find "$TMPROOT/queue/gates/cmd_test/review_approvals" -maxdepth 1 -name '.gate_triggered.*' | wc -l)" -eq 2 ]
}

@test "two reports require approvals for both before formal marker" {
  mkdir -p "$TMPROOT/queue/reports" "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  rm "$REPORT"
  printf 'parent_cmd: cmd_test\nstatus: completed\ncommit_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' > "$TMPROOT/queue/reports/a_report_cmd_test.yaml"
  printf 'parent_cmd: cmd_test\nstatus: completed\ncommit_hash: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n' > "$TMPROOT/queue/reports/b_report_cmd_test.yaml"
  local a="$TMPROOT/queue/reports/a_report_cmd_test.yaml" b="$TMPROOT/queue/reports/b_report_cmd_test.yaml"
  approve gunshi LGTM "$a"; approve karo ACCEPT "$a"
  [ ! -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
  approve gunshi LGTM "$b"; approve karo ACCEPT "$b"
  [ -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
}

@test "RC invalidates report approval and formal marker" {
  mkdir -p "$TMPROOT/queue/reports" "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  setup_rc_task
  local r="$TMPROOT/queue/reports/ninja_report_cmd_test.yaml"
  approve gunshi LGTM "$r"; approve karo ACCEPT "$r"
  [ -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
  approve karo RC "$r"
  [ ! -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
  ! review_two_phase_ready cmd_test "$r"
}

@test "RC reopens done worker task, clears completion times, and persists task_start" {
  setup_rc_task
  approve karo RC "$REPORT"
  [ -f "$TMPROOT/queue/gates/cmd_test/review_approvals/karo_rework.seen" ]
  grep -q '^source: formal_karo_rc$' "$TMPROOT/queue/gates/cmd_test/review_approvals/karo_rework.seen"

  # A delayed Gunshi review must not recreate LGTM after RC changed the report
  # into revision_requested.
  run approve gunshi LGTM "$REPORT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"formal review requires status=completed"* ]]
  [ ! -f "$APPROVALS/gunshi.yaml" ]

  run python3 - "$TMPROOT/queue/tasks/ninja.yaml" <<'PY'
import sys, yaml
t = yaml.safe_load(open(sys.argv[1]))['task']
assert t['status'] == 'assigned'
assert t.get('deployed_at') and t['deployed_at'] != '2026-01-01T00:00:00+09:00'
assert t.get('acknowledged_at') in ('', None)
assert t.get('completed_at') in ('', None)
assert t.get('done_at') in ('', None)
PY
  [ "$status" -eq 0 ]
  run python3 - "$REPORT" <<'PY'
import sys, yaml
r = yaml.safe_load(open(sys.argv[1]))
assert r['status'] == 'revision_requested', r
PY
  [ "$status" -eq 0 ]
  run python3 - "$TMPROOT/queue/inbox/ninja.yaml" <<'PY'
import sys, yaml
messages = (yaml.safe_load(open(sys.argv[1])) or {}).get('messages') or []
assert any(m.get('action') == 'task_start' and m.get('type') == 'task_assigned' for m in messages)
PY
  [ "$status" -eq 0 ]
}

@test "RC fails closed for missing worker task or parent mismatch" {
  setup_rc_task
  sed -i 's/parent_cmd: cmd_test/parent_cmd: cmd_other/' "$TMPROOT/queue/tasks/ninja.yaml"
  run approve karo RC "$REPORT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"parent_cmd mismatch"* ]]
  rm "$TMPROOT/queue/tasks/ninja.yaml"
  run approve karo RC "$REPORT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"task not found"* ]]
}

@test "RC permits the same manifest to trigger once again" {
  mkdir -p "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  setup_rc_task
  approve gunshi LGTM "$REPORT"; approve karo ACCEPT "$REPORT"
  manifest=$(review_manifest_fingerprint "$REPORT")
  [ -e "$TMPROOT/queue/gates/cmd_test/review_approvals/.gate_triggered.$manifest" ]
  approve karo RC "$REPORT"
  [ ! -e "$TMPROOT/queue/gates/cmd_test/review_approvals/.gate_triggered.$manifest" ]
  bash "$TMPROOT/scripts/report_field_set.sh" "$REPORT" status completed
  revised_manifest=$(review_manifest_fingerprint "$REPORT")
  [ "$revised_manifest" = "$manifest" ]
  approve gunshi LGTM "$REPORT"; approve karo ACCEPT "$REPORT"
  [ -e "$TMPROOT/queue/gates/cmd_test/review_approvals/.gate_triggered.$revised_manifest" ]
  grep -q "^manifest: $revised_manifest$" "$TMPROOT/queue/gates/cmd_test/review_gate.done"
}

@test "RC clears the LGTM notice lifecycle marker" {
  setup_rc_task
  approve gunshi LGTM "$REPORT"
  [ -f "$APPROVALS/gunshi_notice.sent" ]
  local completion_notify="$TMPROOT/queue/gates/cmd_test/gunshi_report_review_notify_ninja.done"
  touch "$completion_notify"
  approve karo RC "$REPORT"
  [ ! -e "$APPROVALS/gunshi_notice.sent" ]
  [ ! -e "$completion_notify" ]
}

@test "cmd id, report boundary, and parent_cmd mismatch fail closed" {
  mkdir -p "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  run approve gunshi LGTM "$REPORT"; [ "$status" -eq 0 ]
  run env REVIEW_APPROVAL_ROOT="$TMPROOT" bash "$ROOT/scripts/review_approval.sh" bad gunshi LGTM "$REPORT"; [ "$status" -eq 2 ]
  cp "$REPORT" "$TMPROOT/outside.yaml"
  run env REVIEW_APPROVAL_ROOT="$TMPROOT" bash "$ROOT/scripts/review_approval.sh" cmd_test gunshi LGTM "$TMPROOT/outside.yaml"; [ "$status" -eq 2 ]
  sed -i 's/parent_cmd: cmd_test/parent_cmd: cmd_other/' "$REPORT"
  run approve gunshi LGTM "$REPORT"; [ "$status" -eq 2 ]
}

@test "real cmd_complete trigger runs exactly once for a manifest" {
  mkdir -p "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  cat > "$TMPROOT/scripts/cmd_complete_gate.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$REVIEW_TRIGGER_LOG"
SH
  chmod +x "$TMPROOT/scripts/cmd_complete_gate.sh"
  export REVIEW_TRIGGER_LOG="$TMPROOT/trigger.log"
  REVIEW_APPROVAL_ROOT="$TMPROOT" bash "$ROOT/scripts/review_approval.sh" cmd_test gunshi LGTM "$REPORT"
  REVIEW_APPROVAL_ROOT="$TMPROOT" bash "$ROOT/scripts/review_approval.sh" cmd_test karo ACCEPT "$REPORT"
  REVIEW_APPROVAL_ROOT="$TMPROOT" bash "$ROOT/scripts/review_approval.sh" cmd_test karo ACCEPT "$REPORT"
  for _ in {1..20}; do [ -f "$REVIEW_TRIGGER_LOG" ] && break; sleep 0.05; done
  [ "$(wc -l < "$REVIEW_TRIGGER_LOG")" -eq 1 ]
}

@test "silent trigger fixture: crashing cmd_complete_gate reports FAILED instead of a false triggered success (AC1)" {
  mkdir -p "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  cat > "$TMPROOT/scripts/cmd_complete_gate.sh" <<'SH'
#!/usr/bin/env bash
echo "Traceback (most recent call last): simulated offset-naive/aware TypeError" >&2
exit 1
SH
  chmod +x "$TMPROOT/scripts/cmd_complete_gate.sh"
  REVIEW_APPROVAL_ROOT="$TMPROOT" bash "$ROOT/scripts/review_approval.sh" cmd_test gunshi LGTM "$REPORT"
  run env REVIEW_APPROVAL_ROOT="$TMPROOT" bash "$ROOT/scripts/review_approval.sh" cmd_test karo ACCEPT "$REPORT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"cmd_complete_gate triggered: cmd_test"* ]]
  [[ "$output" == *"cmd_complete_gate trigger FAILED"* ]]
  local trigger_log="$TMPROOT/queue/gates/cmd_test/cmd_complete_gate.trigger.log"
  [ -f "$trigger_log" ]
  grep -q "simulated offset-naive/aware TypeError" "$trigger_log"
}

@test "durable dispatch survives caller process-group teardown (AC1/AC2 durable_cli)" {
  mkdir -p "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  cp "$ROOT/scripts/review_approval.sh" "$TMPROOT/scripts/review_approval.sh"
  cat > "$TMPROOT/scripts/cmd_complete_gate.sh" <<'SH'
#!/usr/bin/env bash
sleep 0.3
echo "gate ran pid=$$ at $(date -Iseconds)"
SH
  chmod +x "$TMPROOT/scripts/cmd_complete_gate.sh"

  REVIEW_APPROVAL_ROOT="$TMPROOT" bash "$TMPROOT/scripts/review_approval.sh" cmd_test gunshi LGTM "$REPORT" >/dev/null

  # 短命caller shellを、tool呼出しごとの隔離セッションに見立てて別セッションで起動する。
  cat > "$TMPROOT/caller.sh" <<EOF
#!/usr/bin/env bash
REVIEW_APPROVAL_ROOT="$TMPROOT" bash "$TMPROOT/scripts/review_approval.sh" cmd_test karo ACCEPT "$REPORT"
EOF
  chmod +x "$TMPROOT/caller.sh"

  setsid bash "$TMPROOT/caller.sh" > "$TMPROOT/caller.out" 2>&1 &
  caller_pid=$!
  wait "$caller_pid"

  # caller終了直後、harnessが行うようなプロセスグループ単位のクリーンアップを模す。
  # durable dispatch(setsid)が効いていればcallerのpgidは既に空でNo such processになる。
  kill -TERM -- -"$caller_pid" 2>/dev/null || true
  sleep 0.05
  kill -KILL -- -"$caller_pid" 2>/dev/null || true

  local trigger_log="$TMPROOT/queue/gates/cmd_test/cmd_complete_gate.trigger.log"
  for _ in {1..20}; do
    [ -s "$trigger_log" ] && break
    sleep 0.05
  done

  [[ "$(cat "$TMPROOT/caller.out")" == *"cmd_complete_gate triggered: cmd_test (pid="* ]]
  [ -s "$trigger_log" ]
  grep -q "^gate ran pid=" "$trigger_log"
}

@test "trigger success is only shown once launch is confirmed alive or exits cleanly (AC1)" {
  mkdir -p "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  cat > "$TMPROOT/scripts/cmd_complete_gate.sh" <<'SH'
#!/usr/bin/env bash
sleep 0.5
SH
  chmod +x "$TMPROOT/scripts/cmd_complete_gate.sh"
  REVIEW_APPROVAL_ROOT="$TMPROOT" bash "$ROOT/scripts/review_approval.sh" cmd_test gunshi LGTM "$REPORT"
  run env REVIEW_APPROVAL_ROOT="$TMPROOT" bash "$ROOT/scripts/review_approval.sh" cmd_test karo ACCEPT "$REPORT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd_complete_gate triggered: cmd_test (pid="* ]]
}

@test "canonical and dot report paths share one approval key" {
  mkdir -p "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  cp "$ROOT/scripts/lib/review_approval.sh" "$TMPROOT/scripts/lib/"
  approve gunshi LGTM "$TMPROOT/queue/reports/./ninja_report_cmd_test.yaml"
  approve karo ACCEPT "$REPORT"
  [ "$(find "$TMPROOT/queue/gates/cmd_test/review_approvals/reports" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]
  review_two_phase_ready cmd_test "$REPORT"
}

@test "global lock serializes late approval and RC; RC leaves no formal state" {
  mkdir -p "$TMPROOT/scripts/lib" "$TMPROOT/scripts"
  setup_rc_task
  approve gunshi LGTM "$REPORT"
  ready="$TMPROOT/ready" release="$TMPROOT/release"
  REVIEW_APPROVAL_ROOT="$TMPROOT" REVIEW_APPROVAL_NO_TRIGGER=1 REVIEW_APPROVAL_TEST_READY_FILE="$ready" REVIEW_APPROVAL_TEST_RELEASE_FILE="$release" \
    bash "$ROOT/scripts/review_approval.sh" cmd_test karo ACCEPT "$REPORT" >"$TMPROOT/accept.log" 2>&1 & accept_pid=$!
  for _ in {1..100}; do [ -e "$ready" ] && break; sleep 0.01; done
  [ -e "$ready" ]
  REVIEW_APPROVAL_ROOT="$TMPROOT" REVIEW_APPROVAL_NO_TRIGGER=1 \
    bash "$ROOT/scripts/review_approval.sh" cmd_test karo RC "$REPORT" >"$TMPROOT/rc.log" 2>&1 & rc_pid=$!
  : > "$release"
  wait "$accept_pid"; wait "$rc_pid"
  [ ! -e "$TMPROOT/queue/gates/cmd_test/review_gate.done" ]
  ! find "$TMPROOT/queue/gates/cmd_test/review_approvals" -maxdepth 1 -name '.gate_triggered.*' | grep -q .
  ! review_two_phase_ready cmd_test "$REPORT"
}
