#!/usr/bin/env bats
# test_necessity: A fingerprint-bound Karo-accepted FAIL attempt is terminal and must not deadlock a successful sibling's two-phase completion manifest.
# regression_justification: cmd_4211 had one successful replacement report plus one formally closed failed attempt; the gate required impossible Gunshi LGTM for the failed report forever.

setup() {
    export PROJECT_ROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$PROJECT_ROOT/queue/reports" "$PROJECT_ROOT/queue/archive/reports" "$PROJECT_ROOT/queue/gates/cmd_mix/review_approvals/reports"
    ln -s "$BATS_TEST_DIRNAME/../../scripts" "$PROJECT_ROOT/scripts"
    source "$BATS_TEST_DIRNAME/../../scripts/lib/review_approval.sh"
    cat > "$PROJECT_ROOT/queue/reports/failed_report.yaml" <<'YAML'
report_id: rpt-failed
parent_cmd: cmd_mix
status: failed
verdict: FAIL
commit_hash: no-code-change
YAML
    cat > "$PROJECT_ROOT/queue/reports/pass_report.yaml" <<'YAML'
report_id: rpt-pass
parent_cmd: cmd_mix
status: completed
verdict: PASS
commit_hash: 0123456789012345678901234567890123456789
YAML
}

_make_rc_identity_fixture() {
    local cmd_id="$1" worker="$2"
    local report="$PROJECT_ROOT/queue/reports/${worker}_report_${cmd_id}.yaml"
    mkdir -p "$PROJECT_ROOT/queue/tasks" "$PROJECT_ROOT/queue/locks" \
        "$PROJECT_ROOT/queue/inbox" "$PROJECT_ROOT/logs"
    cat > "$PROJECT_ROOT/queue/tasks/${worker}.yaml" <<YAML
task:
  task_id: ${cmd_id}_normal
  parent_cmd: ${cmd_id}
  issued_cmd_id: ${cmd_id}
  report_filename: ${worker}_report_${cmd_id}.yaml
  report_id: rpt-22222222-2222-4222-8222-222222222222
  report_identity_version: 2
  status: done
  reviewed: true
  review_result: ACCEPT
  deployed_at: "2026-08-19T02:00:00+09:00"
  acknowledged_at: "2026-08-19T02:01:00+09:00"
  completed_at: "2026-08-19T02:02:00+09:00"
YAML
    cat > "$PROJECT_ROOT/queue/reports/${worker}_report_${cmd_id}.yaml" <<YAML
worker_id: ${worker}
task_id: ${cmd_id}_normal
parent_cmd: ${cmd_id}
report_id: rpt-22222222-2222-4222-8222-222222222222
report_identity_version: 2
status: completed
verdict: PASS
commit_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
binary_checks:
  commit:
    - check: committed
      result: yes
files_modified:
  - path: scripts/review_approval.sh
YAML
    _seed_generation_marker "$report" rpt-22222222-2222-4222-8222-222222222222
}

_seed_generation_marker() {
    local report="$1" report_id="$2"
    printf 'queue/reports/%s\t%s\t%s\t%s\n' \
        "$(basename "$report")" \
        1111111111111111111111111111111111111111111111111111111111111111 \
        2222222222222222222222222222222222222222222222222222222222222222 \
        "$report_id" > "$PROJECT_ROOT/queue/reports/.deploy_generation_$(basename "$report")"
}

_assert_yaml_equal() {
    python3 - "$1" "$2" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding="utf-8") as left, open(sys.argv[2], encoding="utf-8") as right:
    left_doc, right_doc = yaml.safe_load(left), yaml.safe_load(right)
    if left_doc != right_doc:
        print(f"before={left_doc!r}\nafter={right_doc!r}", file=sys.stderr)
        raise SystemExit(1)
PY
}

_seed_rc_markers() {
    local cmd_id="$1" worker="$2" report="$3" key base dir manifest
    key="$(PROJECT_ROOT="$PROJECT_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_key "${2#"$1"/}"' _ "$PROJECT_ROOT" "$report")"
    base="$PROJECT_ROOT/queue/gates/$cmd_id/review_approvals"
    dir="$base/reports/$key"
    mkdir -p "$dir"
    printf 'role: karo\nresult: ACCEPT\nold: true\n' > "$dir/karo.yaml"
    printf 'role: gunshi\nresult: LGTM\nold: true\n' > "$dir/gunshi.yaml"
    printf 'old-notice\n' > "$dir/gunshi_notice.sent"
    printf 'implementation\n' > "$dir/last_rc_scope"
    printf 'cccccccccccccccccccccccccccccccccccccccc\n' > "$dir/last_rc_commit"
    printf '/old/snapshot\n' > "$dir/last_rc_snapshot_dir"
    printf 'old-rework\n' > "$base/karo_rework.seen"
    printf 'old-review-gate\n' > "$PROJECT_ROOT/queue/gates/$cmd_id/review_gate.done"
    printf 'old-notify\n' > "$PROJECT_ROOT/queue/gates/$cmd_id/gunshi_report_review_notify_${worker}.done"
    manifest="$(PROJECT_ROOT="$PROJECT_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; mapfile -t reports < <(review_resolve_reports "$2"); review_manifest_fingerprint "${reports[@]}"' _ "$PROJECT_ROOT" "$cmd_id")"
    printf 'old-gate-triggered\n' > "$base/.gate_triggered.$manifest"
}

_marker_fingerprint() {
    local cmd_id="$1" worker="$2" report="$3" key base dir generation_marker
    key="$(PROJECT_ROOT="$PROJECT_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_key "${2#"$1"/}"' _ "$PROJECT_ROOT" "$report")"
    base="$PROJECT_ROOT/queue/gates/$cmd_id/review_approvals"
    dir="$base/reports/$key"
    generation_marker="$PROJECT_ROOT/queue/reports/.deploy_generation_$(basename "$report")"
    python3 - "$dir" "$base" "$PROJECT_ROOT/queue/gates/$cmd_id" "$worker" "$generation_marker" <<'PY'
import hashlib, pathlib, sys
directory, base, gate, worker, generation_marker = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]), sys.argv[4], pathlib.Path(sys.argv[5])
paths = [directory / name for name in (
    "karo.yaml", "gunshi.yaml", "gunshi_notice.sent", "last_rc_scope",
    "last_rc_commit", "last_rc_report_payload", "last_rc_snapshot_dir")]
paths += [base / "karo_rework.seen", gate / "review_gate.done", gate / f"gunshi_report_review_notify_{worker}.done"]
paths.append(generation_marker)
paths += sorted(base.glob(".gate_triggered.*"))
for path in paths:
    payload = path.read_bytes() if path.is_file() else b"<absent>"
    print(path.name, hashlib.sha256(payload).hexdigest())
PY
}

@test "mixed FAIL close and PASS sibling leaves only PASS in two-phase set" {
    local failed="$PROJECT_ROOT/queue/reports/failed_report.yaml"
    local pass="$PROJECT_ROOT/queue/reports/pass_report.yaml"
    local logical key dir fp
    logical=$(PROJECT_ROOT="$PROJECT_ROOT" review_report_logical_path "$failed")
    key=$(review_report_key "$logical")
    dir="$PROJECT_ROOT/queue/gates/cmd_mix/review_approvals/reports/$key"
    mkdir -p "$dir"
    fp=$(REVIEW_FAIL_CLOSE_IDENTITY_EXEMPT=1 review_report_fingerprint "$failed")
    cat > "$dir/karo.yaml" <<YAML
role: karo
result: ACCEPT
fingerprint: $fp
YAML

    run review_resolve_gate_reports cmd_mix "$failed" "$pass"
    [ "$status" -eq 0 ]
    [ "$output" = "$pass" ]

    printf '\nmutation: true\n' >> "$failed"
    run review_resolve_gate_reports cmd_mix "$failed" "$pass"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 2 ]
}

# test_necessity: a pre-v2 archived sibling must remain reviewable after its task slot is reused by a current v2 worker, without weakening duplicate-report rejection.
# regression_justification: compare-summary had a valid active v2 report, but an older archived sibling without report_id made the canonical registry return rc=1 and blocked SG7 generation.
@test "canonical registry accepts archived legacy sibling and still rejects duplicate basename" {
    mkdir -p "$PROJECT_ROOT/queue/tasks"
    cat > "$PROJECT_ROOT/queue/tasks/current.yaml" <<'YAML'
task:
  parent_cmd: cmd_legacy
  report_filename: current_report_cmd_legacy.yaml
YAML
    cat > "$PROJECT_ROOT/queue/reports/current_report_cmd_legacy.yaml" <<'YAML'
report_id: rpt-current
report_identity_version: 2
parent_cmd: cmd_legacy
status: completed
verdict: PASS
commit_hash: 0123456789012345678901234567890123456789
YAML
    cat > "$PROJECT_ROOT/queue/archive/reports/old_report_cmd_legacy_20260802.yaml" <<'YAML'
parent_cmd: cmd_legacy
status: failed
verdict: FAIL
commit_hash: no-code-change
YAML

    run review_resolve_reports cmd_legacy
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 2 ]

    cp "$PROJECT_ROOT/queue/archive/reports/old_report_cmd_legacy_20260802.yaml" \
        "$PROJECT_ROOT/queue/reports/old_report_cmd_legacy_20260802.yaml"
    cat > "$PROJECT_ROOT/queue/tasks/duplicate.yaml" <<'YAML'
task:
  parent_cmd: cmd_legacy
  report_filename: old_report_cmd_legacy_20260802.yaml
YAML
    run review_resolve_reports cmd_legacy
    [ "$status" -eq 1 ]
}

# test_necessity: a revised live report with a new v2 identity supersedes its
# immutable archived generation for approval, without deleting that history.
@test "canonical registry reviews only active v2 generation for same worker task" {
    mkdir -p "$PROJECT_ROOT/queue/tasks"
    cat > "$PROJECT_ROOT/queue/tasks/current.yaml" <<'YAML'
task:
  parent_cmd: cmd_revised
  report_filename: ninja_report_cmd_revised.yaml
YAML
    cat > "$PROJECT_ROOT/queue/reports/ninja_report_cmd_revised.yaml" <<'YAML'
worker_id: ninja
task_id: cmd_revised_full
report_id: rpt-current
report_identity_version: 2
parent_cmd: cmd_revised
status: completed
verdict: PASS
commit_hash: 0123456789012345678901234567890123456789
YAML
    cat > "$PROJECT_ROOT/queue/archive/reports/ninja_report_cmd_revised_20260810.yaml" <<'YAML'
worker_id: ninja
task_id: cmd_revised_full
report_id: rpt-archived
report_identity_version: 2
parent_cmd: cmd_revised
status: completed
verdict: PASS
commit_hash: 0123456789012345678901234567890123456789
YAML

    run review_resolve_reports cmd_revised
    [ "$status" -eq 0 ]
    [ "$output" = "$PROJECT_ROOT/queue/reports/ninja_report_cmd_revised.yaml" ]
    [ -f "$PROJECT_ROOT/queue/archive/reports/ninja_report_cmd_revised_20260810.yaml" ]
}

# test_necessity: formal Karo RC must rotate the live report identity together
# with the task slot so an immutable archived generation cannot keep the
# canonical registry blocked by a same-report_id ambiguity.
# regression_justification: cmd_karo_hotfix_gate_self_update_race_202608190202
# retained one report_id across archive+live generations; resolver rc=1 made
# the revised report permanently unreviewable despite distinct commits.
@test "formal RC rotates task and live report identity while preserving archive" {
    local cmd_id=cmd_karo_rc_identity worker=identityworker
    local report="$PROJECT_ROOT/queue/reports/${worker}_report_${cmd_id}.yaml"
    local archive="$PROJECT_ROOT/queue/archive/reports/${worker}_report_${cmd_id}_20260819.yaml"
    local task="$PROJECT_ROOT/queue/tasks/${worker}.yaml"
    mkdir -p "$PROJECT_ROOT/queue/tasks" "$PROJECT_ROOT/queue/locks" \
        "$PROJECT_ROOT/queue/inbox" "$PROJECT_ROOT/logs"
    cat > "$task" <<YAML
task:
  task_id: ${cmd_id}_normal
  parent_cmd: ${cmd_id}
  issued_cmd_id: ${cmd_id}
  report_filename: ${worker}_report_${cmd_id}.yaml
  report_id: rpt-11111111-1111-4111-8111-111111111111
  report_identity_version: 2
  status: done
  reviewed: true
  review_result: ACCEPT
  deployed_at: "2026-08-19T02:00:00+09:00"
YAML
    cat > "$report" <<YAML
worker_id: ${worker}
task_id: ${cmd_id}_normal
parent_cmd: ${cmd_id}
report_id: rpt-11111111-1111-4111-8111-111111111111
report_identity_version: 2
status: completed
verdict: PASS
commit_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
binary_checks:
  commit:
    - check: committed
      result: yes
files_modified:
  - path: scripts/review_approval.sh
YAML
    cp "$report" "$archive"
    sed -i 's/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/' "$archive"
    local archive_before old_id new_task_id new_report_id
    archive_before="$(sha256sum "$archive" | awk '{print $1}')"
    old_id=rpt-11111111-1111-4111-8111-111111111111
    _seed_generation_marker "$report" "$old_id"

    run bash "$PROJECT_ROOT/scripts/review_approval.sh" "$cmd_id" karo RC "$report" implementation
    echo "$output" >&3
    [ "$status" -eq 0 ]
    new_task_id="$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["task"]["report_id"])' "$task")"
    new_report_id="$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["report_id"])' "$report")"
    [ "$new_task_id" = "$new_report_id" ]
    [ "$new_report_id" != "$old_id" ]
    [ "$(awk -F '\t' '{print $4}' "$PROJECT_ROOT/queue/reports/.deploy_generation_$(basename "$report")")" = "$new_report_id" ]
    [ "$(sha256sum "$archive" | awk '{print $1}')" = "$archive_before" ]

    run bash -c 'source "$1/scripts/lib/review_approval.sh"; PROJECT_ROOT="$1" review_resolve_reports "$2"' _ "$PROJECT_ROOT" "$cmd_id"
    [ "$status" -eq 0 ]
    [ "$output" = "$report" ]

    run bash "$PROJECT_ROOT/scripts/review_approval.sh" "$cmd_id" karo RC_REVOKE "$report" "identity rotation rollback"
    echo "$output" >&3
    [ "$status" -eq 0 ]
    [ "$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["task"]["report_id"])' "$task")" = "$old_id" ]
    [ "$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["report_id"])' "$report")" = "$old_id" ]
}

# test_necessity: missing or malformed deployment metadata must fail closed
# regression_justification: cmd_karo_hotfix_deploy_generation_rc_sync_202609040724
# before an RC can publish a report/task split identity.
@test "formal RC blocks on missing or stale deployment-generation marker" {
    local cmd_id=cmd_karo_rc_identity_marker_guard worker=identitymarkerguard
    _make_rc_identity_fixture "$cmd_id" "$worker"
    local task="$PROJECT_ROOT/queue/tasks/${worker}.yaml"
    local report="$PROJECT_ROOT/queue/reports/${worker}_report_${cmd_id}.yaml"
    local marker="$PROJECT_ROOT/queue/reports/.deploy_generation_${worker}_report_${cmd_id}.yaml"
    cp "$task" "$BATS_TEST_TMPDIR/task.before"
    cp "$report" "$BATS_TEST_TMPDIR/report.before"
    rm -f "$marker"

    run bash "$PROJECT_ROOT/scripts/review_approval.sh" "$cmd_id" karo RC "$report" implementation
    [ "$status" -ne 0 ]
    _assert_yaml_equal "$BATS_TEST_TMPDIR/task.before" "$task"
    _assert_yaml_equal "$BATS_TEST_TMPDIR/report.before" "$report"
    [ ! -e "$marker" ]

    _seed_generation_marker "$report" rpt-stale-marker
    cp "$task" "$BATS_TEST_TMPDIR/task.before-invalid"
    cp "$report" "$BATS_TEST_TMPDIR/report.before-invalid"
    run bash "$PROJECT_ROOT/scripts/review_approval.sh" "$cmd_id" karo RC "$report" implementation
    [ "$status" -ne 0 ]
    _assert_yaml_equal "$BATS_TEST_TMPDIR/task.before-invalid" "$task"
    _assert_yaml_equal "$BATS_TEST_TMPDIR/report.before-invalid" "$report"
    [ "$(awk -F '\t' '{print $4}' "$marker")" = rpt-stale-marker ]
}

# test_necessity: every formal RC generation, including a repeated RC, must
# leave task, report, and marker identities equal.
# regression_justification: cmd_karo_hotfix_deploy_generation_rc_sync_202609040724
@test "repeated formal RC keeps task report and marker identities aligned" {
    local cmd_id=cmd_karo_rc_identity_marker_repeat worker=identitymarkerrepeat
    _make_rc_identity_fixture "$cmd_id" "$worker"
    local task="$PROJECT_ROOT/queue/tasks/${worker}.yaml"
    local report="$PROJECT_ROOT/queue/reports/${worker}_report_${cmd_id}.yaml"
    local marker="$PROJECT_ROOT/queue/reports/.deploy_generation_${worker}_report_${cmd_id}.yaml"
    run bash "$PROJECT_ROOT/scripts/review_approval.sh" "$cmd_id" karo RC "$report" implementation
    [ "$status" -eq 0 ]
    local first_id
    first_id="$(awk -F '\t' '{print $4}' "$marker")"
    [ "$first_id" = "$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["report_id"])' "$report")" ]
    bash "$PROJECT_ROOT/scripts/report_field_set.sh" "$report" status revision_requested
    bash "$PROJECT_ROOT/scripts/report_field_set.sh" "$report" commit_hash bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    bash "$PROJECT_ROOT/scripts/report_field_set.sh" "$report" status completed
    bash "$PROJECT_ROOT/scripts/lib/yaml_field_set.sh" "$task" task status done
    run bash "$PROJECT_ROOT/scripts/review_approval.sh" "$cmd_id" karo RC "$report" implementation
    [ "$status" -eq 0 ]
    local second_id task_id report_id marker_id
    task_id="$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["task"]["report_id"])' "$task")"
    report_id="$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["report_id"])' "$report")"
    marker_id="$(awk -F '\t' '{print $4}' "$marker")"
    [ "$task_id" = "$report_id" ]
    [ "$report_id" = "$marker_id" ]
    [ "$report_id" != "$first_id" ]
}

# test_necessity: a task publication failure after the live report rotates must
# restore every task/report field and clear the fence only after verification.
@test "formal RC task batch failure restores the complete prior generation" {
    local cmd_id=cmd_karo_rc_identity_task_fail worker=identityfailtask
    _make_rc_identity_fixture "$cmd_id" "$worker"
    local task="$PROJECT_ROOT/queue/tasks/${worker}.yaml"
    local report="$PROJECT_ROOT/queue/reports/${worker}_report_${cmd_id}.yaml"
    cp "$task" "$BATS_TEST_TMPDIR/task.before"
    cp "$report" "$BATS_TEST_TMPDIR/report.before"

    run env REVIEW_APPROVAL_TEST_RC_FAULT=task_batch \
        bash "$PROJECT_ROOT/scripts/review_approval.sh" "$cmd_id" karo RC "$report" implementation
    [ "$status" -ne 0 ]
    _assert_yaml_equal "$BATS_TEST_TMPDIR/task.before" "$task"
    _assert_yaml_equal "$BATS_TEST_TMPDIR/report.before" "$report"
    [ ! -e "$PROJECT_ROOT/queue/gates/$cmd_id/review_approvals/.rc_identity_transaction" ]
}

# test_necessity: a failure after task+report rotation but before the rotated
# fingerprint is durable must roll both files back, never leaving split IDs.
@test "formal RC post-rotation fingerprint failure restores both identities" {
    local cmd_id=cmd_karo_rc_identity_fp_fail worker=identityfailfp
    _make_rc_identity_fixture "$cmd_id" "$worker"
    local task="$PROJECT_ROOT/queue/tasks/${worker}.yaml"
    local report="$PROJECT_ROOT/queue/reports/${worker}_report_${cmd_id}.yaml"
    cp "$task" "$BATS_TEST_TMPDIR/task.before"
    cp "$report" "$BATS_TEST_TMPDIR/report.before"

    run env REVIEW_APPROVAL_TEST_RC_FAULT=rotated_fingerprint \
        bash "$PROJECT_ROOT/scripts/review_approval.sh" "$cmd_id" karo RC "$report" implementation
    [ "$status" -ne 0 ]
    _assert_yaml_equal "$BATS_TEST_TMPDIR/task.before" "$task"
    _assert_yaml_equal "$BATS_TEST_TMPDIR/report.before" "$report"
    [ ! -e "$PROJECT_ROOT/queue/gates/$cmd_id/review_approvals/.rc_identity_transaction" ]
}

# test_necessity: every exit after fence publication, including report-id
# generation failure, must restore the complete prior approval marker set.
@test "formal RC id generation failure restores reports tasks and markers" {
    local cmd_id=cmd_karo_rc_identity_id_fail worker=identityfailid
    _make_rc_identity_fixture "$cmd_id" "$worker"
    local task="$PROJECT_ROOT/queue/tasks/${worker}.yaml"
    local report="$PROJECT_ROOT/queue/reports/${worker}_report_${cmd_id}.yaml"
    _seed_rc_markers "$cmd_id" "$worker" "$report"
    cp "$task" "$BATS_TEST_TMPDIR/task.before"
    cp "$report" "$BATS_TEST_TMPDIR/report.before"
    local markers_before="$(_marker_fingerprint "$cmd_id" "$worker" "$report")"

    run env REVIEW_APPROVAL_TEST_RC_FAULT=id_generation \
        bash "$PROJECT_ROOT/scripts/review_approval.sh" "$cmd_id" karo RC "$report" implementation
    [ "$status" -ne 0 ]
    _assert_yaml_equal "$BATS_TEST_TMPDIR/task.before" "$task"
    _assert_yaml_equal "$BATS_TEST_TMPDIR/report.before" "$report"
    [ "$(_marker_fingerprint "$cmd_id" "$worker" "$report")" = "$markers_before" ]
    [ ! -e "$PROJECT_ROOT/queue/gates/$cmd_id/review_approvals/.rc_identity_transaction" ]
}

# test_necessity: report publication failure after status mutation must use the
# same transaction cleanup and restore the complete old marker generation.
@test "formal RC report publication failure restores reports tasks and markers" {
    local cmd_id=cmd_karo_rc_identity_publish_fail worker=identityfailpublish
    _make_rc_identity_fixture "$cmd_id" "$worker"
    local task="$PROJECT_ROOT/queue/tasks/${worker}.yaml"
    local report="$PROJECT_ROOT/queue/reports/${worker}_report_${cmd_id}.yaml"
    _seed_rc_markers "$cmd_id" "$worker" "$report"
    cp "$task" "$BATS_TEST_TMPDIR/task.before"
    cp "$report" "$BATS_TEST_TMPDIR/report.before"
    local markers_before="$(_marker_fingerprint "$cmd_id" "$worker" "$report")"

    run env REVIEW_APPROVAL_TEST_RC_FAULT=report_id \
        bash "$PROJECT_ROOT/scripts/review_approval.sh" "$cmd_id" karo RC "$report" implementation
    [ "$status" -ne 0 ]
    _assert_yaml_equal "$BATS_TEST_TMPDIR/task.before" "$task"
    _assert_yaml_equal "$BATS_TEST_TMPDIR/report.before" "$report"
    [ "$(_marker_fingerprint "$cmd_id" "$worker" "$report")" = "$markers_before" ]
    [ ! -e "$PROJECT_ROOT/queue/gates/$cmd_id/review_approvals/.rc_identity_transaction" ]
}

# test_necessity: successful RC must not disarm cleanup until fence deletion is
# verified; a deletion failure must roll the whole generation back.
@test "formal RC fence removal failure rolls back before active cleanup disarms" {
    local cmd_id=cmd_karo_rc_identity_fence_remove worker=identityfenceremove
    _make_rc_identity_fixture "$cmd_id" "$worker"
    local task="$PROJECT_ROOT/queue/tasks/${worker}.yaml"
    local report="$PROJECT_ROOT/queue/reports/${worker}_report_${cmd_id}.yaml"
    _seed_rc_markers "$cmd_id" "$worker" "$report"
    cp "$task" "$BATS_TEST_TMPDIR/task.before"
    cp "$report" "$BATS_TEST_TMPDIR/report.before"
    local markers_before="$(_marker_fingerprint "$cmd_id" "$worker" "$report")"

    run env REVIEW_APPROVAL_TEST_RC_FAULT=fence_remove \
        bash "$PROJECT_ROOT/scripts/review_approval.sh" "$cmd_id" karo RC "$report" implementation
    [ "$status" -ne 0 ]
    _assert_yaml_equal "$BATS_TEST_TMPDIR/task.before" "$task"
    _assert_yaml_equal "$BATS_TEST_TMPDIR/report.before" "$report"
    [ "$(_marker_fingerprint "$cmd_id" "$worker" "$report")" = "$markers_before" ]
    [ ! -e "$PROJECT_ROOT/queue/gates/$cmd_id/review_approvals/.rc_identity_transaction" ]
}

# test_necessity: an orphan fence left by termination without EXIT cleanup must
# be replayable by the next formal RC under the same locks.
@test "next formal RC recovers orphan fence then starts a fresh generation" {
    local cmd_id=cmd_karo_rc_identity_orphan worker=identityorphan
    _make_rc_identity_fixture "$cmd_id" "$worker"
    local task="$PROJECT_ROOT/queue/tasks/${worker}.yaml"
    local report="$PROJECT_ROOT/queue/reports/${worker}_report_${cmd_id}.yaml"
    local old_id=rpt-22222222-2222-4222-8222-222222222222
    _seed_rc_markers "$cmd_id" "$worker" "$report"
    cp "$task" "$BATS_TEST_TMPDIR/task.before"
    cp "$report" "$BATS_TEST_TMPDIR/report.before"
    local markers_before="$(_marker_fingerprint "$cmd_id" "$worker" "$report")"

    run env REVIEW_APPROVAL_TEST_RC_FAULT=orphan_exit \
        bash "$PROJECT_ROOT/scripts/review_approval.sh" "$cmd_id" karo RC "$report" implementation
    [ "$status" -eq 97 ]
    [ -e "$PROJECT_ROOT/queue/gates/$cmd_id/review_approvals/.rc_identity_transaction" ]
    run bash -c 'source "$1/scripts/lib/review_approval.sh"; PROJECT_ROOT="$1" review_resolve_reports "$2"' _ "$PROJECT_ROOT" "$cmd_id"
    [ "$status" -eq 1 ]

    run env REVIEW_APPROVAL_TEST_RC_FAULT=orphan_restored_stop \
        bash "$PROJECT_ROOT/scripts/review_approval.sh" "$cmd_id" karo RC "$report" implementation
    [ "$status" -eq 98 ]
    [ ! -e "$PROJECT_ROOT/queue/gates/$cmd_id/review_approvals/.rc_identity_transaction" ]
    cmp -s "$BATS_TEST_TMPDIR/task.before" "$task"
    cmp -s "$BATS_TEST_TMPDIR/report.before" "$report"
    [ "$(_marker_fingerprint "$cmd_id" "$worker" "$report")" = "$markers_before" ]

    run bash "$PROJECT_ROOT/scripts/review_approval.sh" "$cmd_id" karo RC "$report" implementation
    echo "$output" >&3
    [ "$status" -eq 0 ]
    [ ! -e "$PROJECT_ROOT/queue/gates/$cmd_id/review_approvals/.rc_identity_transaction" ]
    local task_id report_id
    task_id="$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["task"]["report_id"])' "$task")"
    report_id="$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["report_id"])' "$report")"
    [ "$task_id" = "$report_id" ]
    [ "$report_id" != "$old_id" ]
}

# test_necessity: a corrupted orphan snapshot must retain the fence and leave
# every operational YAML/marker byte untouched rather than partially restoring.
@test "orphan recovery corruption blocks before overwriting operational state" {
    local cmd_id=cmd_karo_rc_identity_orphan_corrupt worker=identityorphancorrupt
    _make_rc_identity_fixture "$cmd_id" "$worker"
    local task="$PROJECT_ROOT/queue/tasks/${worker}.yaml"
    local report="$PROJECT_ROOT/queue/reports/${worker}_report_${cmd_id}.yaml"
    _seed_rc_markers "$cmd_id" "$worker" "$report"

    run env REVIEW_APPROVAL_TEST_RC_FAULT=orphan_exit \
        bash "$PROJECT_ROOT/scripts/review_approval.sh" "$cmd_id" karo RC "$report" implementation
    [ "$status" -eq 97 ]
    local fence="$PROJECT_ROOT/queue/gates/$cmd_id/review_approvals/.rc_identity_transaction"
    local snapshot
    snapshot="$(python3 -c 'import sys,yaml; print(yaml.safe_load(open(sys.argv[1]))["snapshot_dir"])' "$fence")"
    printf 'not: [valid yaml\n' > "$snapshot/task.yaml"
    cp "$task" "$BATS_TEST_TMPDIR/task.partial"
    cp "$report" "$BATS_TEST_TMPDIR/report.partial"
    local markers_partial="$(_marker_fingerprint "$cmd_id" "$worker" "$report")"

    run bash "$PROJECT_ROOT/scripts/review_approval.sh" "$cmd_id" karo RC "$report" implementation
    [ "$status" -ne 0 ]
    [ -e "$fence" ]
    cmp -s "$BATS_TEST_TMPDIR/task.partial" "$task"
    cmp -s "$BATS_TEST_TMPDIR/report.partial" "$report"
    [ "$(_marker_fingerprint "$cmd_id" "$worker" "$report")" = "$markers_partial" ]
}

# test_necessity: lock-free canonical resolver callers must fail closed while
# the cross-file RC identity transaction fence is present.
@test "canonical resolver rejects an in-flight RC identity transaction" {
    local cmd_id=cmd_karo_rc_identity_fence worker=identityfence
    _make_rc_identity_fixture "$cmd_id" "$worker"
    local report="$PROJECT_ROOT/queue/reports/${worker}_report_${cmd_id}.yaml"
    bash "$PROJECT_ROOT/scripts/report_field_set.sh" "$report" status revision_requested
    bash "$PROJECT_ROOT/scripts/report_field_set.sh" "$report" report_id \
        rpt-33333333-3333-4333-8333-333333333333
    _seed_generation_marker "$report" rpt-33333333-3333-4333-8333-333333333333
    local fence="$PROJECT_ROOT/queue/gates/$cmd_id/review_approvals/.rc_identity_transaction"
    mkdir -p "${fence%/*}"
    printf 'cmd_id: %s\n' "$cmd_id" > "$fence"

    run bash -c 'source "$1/scripts/lib/review_approval.sh"; PROJECT_ROOT="$1" review_resolve_reports "$2"' _ "$PROJECT_ROOT" "$cmd_id"
    [ "$status" -eq 1 ]
    rm -f "$fence"
    run bash -c 'source "$1/scripts/lib/review_approval.sh"; PROJECT_ROOT="$1" review_resolve_reports "$2"' _ "$PROJECT_ROOT" "$cmd_id"
    [ "$status" -eq 0 ]
    [ "$output" = "$report" ]
}

# test_necessity: review_resolve_reports must ignore hidden deployment metadata
# that shares the .yaml suffix while retaining the task-owned visible report.
# regression_justification: pathlib.Path.glob("*.yaml") includes the TSV
# .deploy_generation marker and its tab character makes yaml.safe_load fail
# before the visible report can be resolved.
@test "canonical registry excludes hidden deployment TSV markers" {
    mkdir -p "$PROJECT_ROOT/queue/tasks"
    cat > "$PROJECT_ROOT/queue/tasks/current.yaml" <<'YAML'
task:
  parent_cmd: cmd_hidden_glob
  report_filename: current_report_cmd_hidden_glob.yaml
YAML
    cat > "$PROJECT_ROOT/queue/reports/current_report_cmd_hidden_glob.yaml" <<'YAML'
report_id: rpt-visible
report_identity_version: 2
parent_cmd: cmd_hidden_glob
status: completed
verdict: PASS
commit_hash: 0123456789012345678901234567890123456789
YAML
    printf '%s\t%s\t%s\t%s\n' \
        "$PROJECT_ROOT/queue/reports/current_report_cmd_hidden_glob.yaml" \
        content-sha commit-id rpt-visible \
        > "$PROJECT_ROOT/queue/reports/.deploy_generation_ninja_report_cmd_hidden_glob.yaml"

    run review_resolve_reports cmd_hidden_glob
    [ "$status" -eq 0 ]
    [ "$output" = "$PROJECT_ROOT/queue/reports/current_report_cmd_hidden_glob.yaml" ]
}
