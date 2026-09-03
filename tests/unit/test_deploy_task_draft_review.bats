#!/usr/bin/env bats
# test_necessity: Draft APPROVE must atomically bind an exact Gunshi receipt to the assigned task before one review_result notification; mismatch, stale state, races, and writer failure must leave task/notification state unchanged.
# cmd_karo_hotfix_rc_peer_report_redeploy_20260809: deployment no longer waits
# on this receipt (deploy_task_require_pre_implementation_review was removed —
# see test_deploy_task_pre_implementation_review.bats). This receipt is now
# purely an idempotent audit record of Gunshi's APPROVE, kept so a re-review
# does not produce a duplicate review_result notification.

setup() {
  export ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export F="$BATS_TEST_TMPDIR/f"
  mkdir -p "$F/bin"
  export TASK="$F/task.yaml" CALLS="$F/inbox.calls"
  export INBOX_WRITE_CMD="$F/bin/inbox"
  cat > "$INBOX_WRITE_CMD" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALLS"
SH
  chmod +x "$INBOX_WRITE_CMD"
  write_task assigned fp-new ""
}

write_task() {
  local status="$1" fp="$2" receipt="$3"
  cat > "$TASK" <<YAML
task:
  task_type: hotfix
  task_id: cmd-new
  ac_version: $fp
  status: $status
$receipt
YAML
}

approve() { bash "$ROOT/scripts/draft_review_approval.sh" "$TASK" cmd-new fp-new msg-proof; }
sha() { sha256sum "$TASK" | awk '{print $1}'; }

@test "exact assigned task records receipt before one notification" {
  run approve
  [ "$status" -eq 0 ]; [[ "$output" == *"APPROVAL_RECORDED"* ]]
  [ "$(wc -l < "$CALLS")" -eq 1 ]
  python3 - "$TASK" <<'PY'
import sys,yaml
r=yaml.safe_load(open(sys.argv[1]))['task']['pre_implementation_review']
assert r == {'reviewer':'gunshi','result':'LGTM','task_id':'cmd-new','task_fingerprint':'fp-new','evidence_message_id':'msg-proof'}
PY
}

# test_necessity: the review_result notice to karo must carry the commander identity
# envelope bound to the task parent_cmd, otherwise inbox_write rejects it after the
# receipt is already recorded (2026-09-04 07:29 real BLOCK on two approvals).
@test "notice carries commander envelope when task has parent_cmd" {
  printf '%s\n' '  parent_cmd: cmd_parent_x' >> "$TASK"
  run approve
  [ "$status" -eq 0 ]
  grep -q 'task_id=commander_directive subject_task_id=cmd-new parent_cmd=cmd_parent_x' "$CALLS"
}

@test "same exact receipt rerun is idempotent without duplicate notification" {
  approve
  before="$(sha)"
  run approve
  [ "$status" -eq 0 ]; [[ "$output" == *"APPROVAL_IDEMPOTENT"* ]]
  [ "$(sha)" = "$before" ]; [ "$(wc -l < "$CALLS")" -eq 1 ]
}

@test "task id fingerprint and empty evidence mismatches mutate and notify zero" {
  for args in 'cmd-other fp-new msg-proof' 'cmd-new fp-old msg-proof' 'cmd-new fp-new '; do
    before="$(sha)"
    # shellcheck disable=SC2086
    run bash "$ROOT/scripts/draft_review_approval.sh" "$TASK" $args
    [ "$status" -ne 0 ]; [ "$(sha)" = "$before" ]; [ ! -e "$CALLS" ]
  done
}

@test "non-reviewable statuses mutate and notify zero" {
  for state in done idle; do
    write_task "$state" fp-new ""; before="$(sha)"
    run approve
    [ "$status" -ne 0 ]; [ "$(sha)" = "$before" ]; [ ! -e "$CALLS" ]
  done
}

@test "in_progress task accepts approval for parallel review" {
  write_task in_progress fp-new ""
  run approve
  [ "$status" -eq 0 ]; [[ "$output" == *"APPROVAL_RECORDED"* ]]
}

@test "different existing receipt mutates and notifies zero" {
  write_task assigned fp-new $'  pre_implementation_review:\n    reviewer: gunshi\n    result: LGTM\n    task_id: cmd-new\n    task_fingerprint: fp-new\n    evidence_message_id: msg-other'
  before="$(sha)"; run approve
  [ "$status" -ne 0 ]; [ "$(sha)" = "$before" ]; [ ! -e "$CALLS" ]
}

@test "receipt writer failure mutates and notifies zero" {
  printf '#!/usr/bin/env bash\nexit 71\n' > "$F/bin/set-fail"; chmod +x "$F/bin/set-fail"
  before="$(sha)"
  run env YAML_FIELD_SET_CMD="$F/bin/set-fail" bash "$ROOT/scripts/draft_review_approval.sh" "$TASK" cmd-new fp-new msg-proof
  [ "$status" -ne 0 ]; [ "$(sha)" = "$before" ]; [ ! -e "$CALLS" ]
}

@test "two simultaneous approvals produce one receipt and one notification" {
  bash "$ROOT/scripts/draft_review_approval.sh" "$TASK" cmd-new fp-new msg-proof >"$F/a" & p1=$!
  bash "$ROOT/scripts/draft_review_approval.sh" "$TASK" cmd-new fp-new msg-proof >"$F/b" & p2=$!
  wait "$p1"; wait "$p2"
  [ "$(wc -l < "$CALLS")" -eq 1 ]
  [ "$(cat "$F/a" "$F/b" | grep -Ec 'APPROVAL_(RECORDED|IDEMPOTENT)')" -eq 2 ]
}

@test "cmd_4224 generation reset removes predecessor cmd_4228 receipt before publication" {
  mkdir -p "$F/queue/tasks"
  local reset_task="$F/queue/tasks/ninja.yaml"
  write_task assigned fp-new $'  pre_implementation_review:\n    reviewer: gunshi\n    result: LGTM\n    task_id: cmd_4228_full\n    task_fingerprint: eaafccca\n    evidence_message_id: msg-old'
  cp "$TASK" "$reset_task"
  SCRIPT_DIR="$F" DIRECT_MODE=false CMD_ID=cmd-new
  log() { :; }
  source <(sed -n '/^reset_stale_fields()/,/^}/p' "$ROOT/scripts/deploy_task.sh")
  run reset_stale_fields ninja
  [ "$status" -eq 0 ]
  ! grep -q 'pre_implementation_review\|cmd_4228_full\|eaafccca\|msg-old' "$reset_task"
  grep -q '^  task_id: cmd-new$' "$reset_task"
}
