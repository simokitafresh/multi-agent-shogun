#!/usr/bin/env bats
# test_necessity: report-only RC notifications must not pre-decide whether prior
# measurements remain valid or whether recalculation/reimplementation is forbidden;
# that decision belongs exclusively to the concrete review instructions.

setup_file() {
    export REVIEW_APPROVAL_SCRIPT
    REVIEW_APPROVAL_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/scripts/review_approval.sh"
}

setup_ledger_fallback_fixture() {
    export LEDGER_ROOT="$BATS_TEST_TMPDIR/review-log-ledger-root"
    export LEDGER_STATE="$BATS_TEST_TMPDIR/review-log-ledger-state"
    mkdir -p "$LEDGER_ROOT/logs" "$LEDGER_ROOT/queue/reports" "$LEDGER_STATE/ledger_inbox/review_log"
    cat > "$LEDGER_ROOT/queue/reports/worker_report_cmd_ledger_fixture.yaml" <<'YAML'
worker_id: worker
task_id: cmd_ledger_fixture_normal
report_id: rpt-ledger-fixture
report_identity_version: 2
YAML
    export LEDGER_ENTRY="- cmd_id: cmd_ledger_fixture\n  verdict: LGTM\n  report: queue/reports/worker_report_cmd_ledger_fixture.yaml\n  report_task_id: cmd_ledger_fixture_normal\n  report_id: rpt-ledger-fixture\n  report_identity_version: 2\n"
}

review_log_fallback_lookup() {
    REVIEW_LOG_SOURCE_REMOTE_REF=origin/main SHOGUN_STATE_DIR="$LEDGER_STATE" \
      bash -c 'source "$1"; review_log_has_identity "$2" cmd_ledger_fixture "$2/queue/reports/worker_report_cmd_ledger_fixture.yaml" fp gen' \
      _ "$REVIEW_APPROVAL_SCRIPT_DIR/scripts/lib/review_approval.sh" "$LEDGER_ROOT"
}

# test_necessity: review approval must accept the publisher's four durable
# review-log locations while binding every candidate to the current report.
@test "review log fallback accepts root, origin, applied, and pending identities" {
    export REVIEW_APPROVAL_SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    setup_ledger_fallback_fixture

    printf '%b' "$LEDGER_ENTRY" > "$LEDGER_ROOT/logs/gunshi_review_log.yaml"
    run review_log_fallback_lookup
    [ "$status" -eq 0 ]

    printf '[]\n' > "$LEDGER_ROOT/logs/gunshi_review_log.yaml"
    git init -q -b main "$LEDGER_ROOT"
    git -C "$LEDGER_ROOT" config user.email test@example.com
    git -C "$LEDGER_ROOT" config user.name test
    blob="$(printf '%b' "$LEDGER_ENTRY" | git -C "$LEDGER_ROOT" hash-object -w --stdin)"
    logs_tree="$(printf '100644 blob %s\tgunshi_review_log.yaml\n' "$blob" | git -C "$LEDGER_ROOT" mktree)"
    root_tree="$(printf '040000 tree %s\tlogs\n' "$logs_tree" | git -C "$LEDGER_ROOT" mktree)"
    commit="$(printf 'origin fixture\n' | git -C "$LEDGER_ROOT" commit-tree "$root_tree")"
    git -C "$LEDGER_ROOT" update-ref refs/remotes/origin/main "$commit"
    run review_log_fallback_lookup
    [ "$status" -eq 0 ]

    cat > "$LEDGER_STATE/ledger_inbox/review_log/applied.yaml" <<YAML
op: append
ledger: review_log
entry_text: |
  - cmd_id: cmd_ledger_fixture
    verdict: LGTM
    report: queue/reports/worker_report_cmd_ledger_fixture.yaml
    report_task_id: cmd_ledger_fixture_normal
    report_id: rpt-ledger-fixture
    report_identity_version: 2
YAML
    git -C "$LEDGER_ROOT" update-ref -d refs/remotes/origin/main
    run review_log_fallback_lookup
    [ "$status" -eq 0 ]

    cp "$LEDGER_STATE/ledger_inbox/review_log/applied.yaml" "$LEDGER_STATE/ledger_inbox/review_log/pending.yaml"
    rm -f "$LEDGER_STATE/ledger_inbox/review_log/applied.yaml"
    run review_log_fallback_lookup
    [ "$status" -eq 0 ]
}

# test_necessity: stale or absent review evidence must remain fail-closed even
# when the command id alone matches.
@test "review log fallback rejects identity mismatch and missing sources" {
    export REVIEW_APPROVAL_SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    setup_ledger_fallback_fixture
    printf '[]\n' > "$LEDGER_ROOT/logs/gunshi_review_log.yaml"
    mismatch='- cmd_id: cmd_ledger_fixture
  verdict: LGTM
  report: queue/reports/other_report.yaml
  report_task_id: other_task
  report_id: other-report
  report_identity_version: 9
'
    printf '%s' "$mismatch" > "$LEDGER_STATE/ledger_inbox/review_log/pending.yaml"
    run review_log_fallback_lookup
    [ "$status" -eq 1 ]

    rm -f "$LEDGER_STATE/ledger_inbox/review_log/pending.yaml"
    run review_log_fallback_lookup
    [ "$status" -eq 1 ]
}

setup_resolve_fixture() {
    export RESOLVE_ROOT="$BATS_TEST_TMPDIR/resolve-root"
    mkdir -p "$RESOLVE_ROOT/queue/reports" "$RESOLVE_ROOT/queue/archive/reports" \
        "$RESOLVE_ROOT/queue/tasks"
    cat > "$RESOLVE_ROOT/queue/tasks/hayate.yaml" <<'YAML'
task:
  task_id: cmd_registry_hayate_normal
  parent_cmd: cmd_registry
  report_filename: hayate_report_cmd_registry.yaml
  status: done
YAML
    cat > "$RESOLVE_ROOT/queue/reports/hayate_report_cmd_registry.yaml" <<'YAML'
worker_id: hayate
task_id: cmd_registry_hayate_normal
report_id: rpt-registry-hayate
report_identity_version: 2
parent_cmd: cmd_registry
status: completed
YAML
    cat > "$RESOLVE_ROOT/queue/reports/kagemaru_report_cmd_registry.yaml" <<'YAML'
worker_id: kagemaru
task_id: cmd_registry_kagemaru_normal
report_id: rpt-registry-kagemaru
report_identity_version: 2
parent_cmd: cmd_registry
status: completed
YAML
    printf 'queue/reports/kagemaru_report_cmd_registry.yaml\t%s\t%s\trpt-registry-kagemaru\n' \
        "$(printf '%064d' 1)" "$(printf '%064d' 2)" \
        > "$RESOLVE_ROOT/queue/reports/.deploy_generation_kagemaru_report_cmd_registry.yaml"
}

resolve_fixture_reports() {
    PROJECT_ROOT="$RESOLVE_ROOT" bash -c \
        'source "$(dirname "$1")/lib/review_approval.sh"; review_resolve_reports cmd_registry' _ \
        "$REVIEW_APPROVAL_SCRIPT"
}

# test_necessity: report identity registry is the durable owner for a completed
# report after its task slot is overwritten; without this, split AC completion
# loses one report and cannot construct the canonical SG7 set.
@test "resolver keeps claimed report after task slot overwrite and excludes unclaimed" {
    setup_resolve_fixture
    cat > "$RESOLVE_ROOT/queue/reports/unclaimed_report_cmd_registry.yaml" <<'YAML'
worker_id: unclaimed
task_id: cmd_registry_unclaimed_normal
report_id: rpt-registry-unclaimed
report_identity_version: 2
parent_cmd: cmd_registry
status: completed
YAML

    run resolve_fixture_reports
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 2 ]
    [[ "$output" == *"hayate_report_cmd_registry.yaml"* ]]
    [[ "$output" == *"kagemaru_report_cmd_registry.yaml"* ]]
    [[ "$output" != *"unclaimed_report_cmd_registry.yaml"* ]]
}

# test_necessity: a registry claim must authenticate both report_id and
# parent_cmd; accepting either mismatch would bind approvals to another report
# generation or command.
@test "resolver blocks claimed report identity mismatch and reuse" {
    setup_resolve_fixture
    sed -i 's/^parent_cmd: cmd_registry$/parent_cmd: cmd_other/' \
        "$RESOLVE_ROOT/queue/reports/kagemaru_report_cmd_registry.yaml"
    run resolve_fixture_reports
    [ "$status" -ne 0 ]

    setup_resolve_fixture
    cat > "$RESOLVE_ROOT/queue/reports/other_report_cmd_registry.yaml" <<'YAML'
worker_id: other
task_id: cmd_registry_other_normal
report_id: rpt-registry-other
report_identity_version: 2
parent_cmd: cmd_registry
status: completed
YAML
    printf 'queue/reports/other_report_cmd_registry.yaml\t%s\t%s\trpt-registry-kagemaru\n' \
        "$(printf '%064d' 3)" "$(printf '%064d' 4)" \
        > "$RESOLVE_ROOT/queue/reports/.deploy_generation_other_report_cmd_registry.yaml"
    run resolve_fixture_reports
    [ "$status" -ne 0 ]

    setup_resolve_fixture
    cp "$RESOLVE_ROOT/queue/reports/kagemaru_report_cmd_registry.yaml" \
        "$RESOLVE_ROOT/queue/archive/reports/kagemaru_report_cmd_registry.yaml"
    run resolve_fixture_reports
    [ "$status" -ne 0 ]
}

@test "report-only RC notification keeps recalculation decision neutral" {
    run grep -c '前報告の実測・成果物は有効\|再計算・再実装は禁止' "$REVIEW_APPROVAL_SCRIPT"
    [ "$status" -eq 1 ]
    [ "$output" -eq 0 ]

    run grep -c '現task YAMLとRC指摘を正本として再読' "$REVIEW_APPROVAL_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    run grep -c '再計算・再実装の要否はレビュー指示に従え' "$REVIEW_APPROVAL_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# test_necessity: the asynchronous completion gate must never inherit the
# report-approval flock descriptor after the durable review transaction ends.
@test "completion trigger closes approval lock fd before asynchronous execution" {
    run grep -E -c 'setsid nohup bash -c' "$REVIEW_APPROVAL_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]

    run grep -E -c '200>&- &' "$REVIEW_APPROVAL_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

setup_trigger_fixture() {
    export TRIGGER_ROOT="$BATS_TEST_TMPDIR/trigger-root"
    mkdir -p "$TRIGGER_ROOT/queue/reports" "$TRIGGER_ROOT/queue/archive/reports" \
        "$TRIGGER_ROOT/queue/tasks" "$TRIGGER_ROOT/queue/gates" "$TRIGGER_ROOT/scripts" \
        "$TRIGGER_ROOT/logs"
    ln -s "$BATS_TEST_DIRNAME/../../scripts/review_approval.sh" \
        "$TRIGGER_ROOT/scripts/review_approval.sh"
    ln -s "$BATS_TEST_DIRNAME/../../scripts/lib" "$TRIGGER_ROOT/scripts/lib"
    cat > "$TRIGGER_ROOT/scripts/cmd_complete_gate.sh" <<'GATE'
#!/usr/bin/env bash
set -u
log_target=$(readlink "/proc/$$/fd/1" 2>/dev/null || true)
case "$log_target" in
    *cmd_complete_gate.trigger.log) ;;
    *) exit 0 ;;
esac
n=0
if [ -f "$STUB_GATE_STATE" ]; then
    n=$(cat "$STUB_GATE_STATE")
fi
n=$((n + 1))
printf '%s\n' "$n" > "$STUB_GATE_STATE"
if [ "$STUB_GATE_MODE" = retry ] && [ "$n" -eq 1 ]; then
    exit 75
fi
if [ "$STUB_GATE_MODE" = block ]; then
    exit 1
fi
exit 0
GATE
    chmod +x "$TRIGGER_ROOT/scripts/cmd_complete_gate.sh"
    cat > "$TRIGGER_ROOT/queue/tasks/worker.yaml" <<'TASK'
task:
  task_id: cmd_trigger_full
  parent_cmd: cmd_trigger
  report_filename: worker_report_cmd_trigger.yaml
  task_type: full
TASK
    cat > "$TRIGGER_ROOT/queue/reports/worker_report_cmd_trigger.yaml" <<'REPORT'
worker_id: worker
task_id: cmd_trigger_full
report_id: rpt-trigger
report_identity_version: 2
parent_cmd: cmd_trigger
status: completed
verdict: PASS
commit_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
result:
  summary: trigger fixture
REPORT
    export STUB_GATE_STATE="$TRIGGER_ROOT/gate-count"
    export REVIEW_APPROVAL_ROOT="$TRIGGER_ROOT"
    export REVIEW_APPROVAL_NO_NOTIFY=1
    : > "$STUB_GATE_STATE"
}

record_trigger_approvals() {
    local report="$TRIGGER_ROOT/queue/reports/worker_report_cmd_trigger.yaml"
    REVIEW_APPROVAL_SKIP_LEDGER_CHECK=1 \
      bash "$TRIGGER_ROOT/scripts/review_approval.sh" cmd_trigger gunshi LGTM "$report"
    bash "$TRIGGER_ROOT/scripts/review_approval.sh" cmd_trigger karo ACCEPT "$report"
}

# test_necessity: after both approvals, a transient gate lock (exit 75) must
# be retried in the detached trigger process until a terminal result is
# published, without allowing the terminal marker to be created early.
@test "completion trigger retries lock busy and publishes CLEAR after terminal retry" {
    setup_trigger_fixture
    export STUB_GATE_MODE=retry
    record_trigger_approvals

    local gate_dir="$TRIGGER_ROOT/queue/gates/cmd_trigger"
    local approvals="$gate_dir/review_approvals"
    local manifest
    manifest=$(awk '$1 == "manifest:" {print $2; exit}' "$gate_dir/review_gate.done")
    [ -n "$manifest" ]
    [ ! -e "$approvals/.gate_triggered.$manifest" ]
    sleep 0.2
    [ ! -e "$approvals/.gate_triggered.$manifest" ]
    for i in $(seq 1 140); do
        [ -f "$approvals/.gate_triggered.$manifest" ] && break
        sleep 0.05
    done
    [ -n "$manifest" ]
    local log="$gate_dir/cmd_complete_gate.trigger.log"
    [ "$(cat "$STUB_GATE_STATE")" -eq 2 ]
    [ "$(grep -c '^attempt=' "$log")" -eq 2 ]
    grep -q '^attempt=1 rc=75 ' "$log"
    grep -q '^attempt=2 rc=0 ' "$log"
    grep -q '^result: 0$' "$approvals/.gate_triggered.$manifest"
    [ ! -e "$approvals/.gate_triggering.$manifest" ]
}

# test_necessity: normal dual approval must dispatch exactly one detached gate
# flight after both durable approval records exist.
@test "completion trigger launches once after normal dual approval" {
    setup_trigger_fixture
    export STUB_GATE_MODE=normal
    record_trigger_approvals

    local gate_dir="$TRIGGER_ROOT/queue/gates/cmd_trigger"
    local approvals="$gate_dir/review_approvals"
    local manifest
    manifest=$(awk '$1 == "manifest:" {print $2; exit}' "$gate_dir/review_gate.done")
    [ -n "$manifest" ]
    for i in $(seq 1 140); do
        [ -f "$approvals/.gate_triggered.$manifest" ] && break
        sleep 0.05
    done
    [ "$(cat "$STUB_GATE_STATE")" -eq 1 ]
    [ "$(grep -c '^attempt=' "$gate_dir/cmd_complete_gate.trigger.log")" -eq 1 ]
    grep -q '^result: 0$' "$approvals/.gate_triggered.$manifest"
    [ ! -e "$approvals/.gate_triggering.$manifest" ]
}

# test_necessity: a terminal BLOCK result must stop the detached trigger after
# one invocation and must never enter the transient-lock retry lane.
@test "completion trigger stops on terminal BLOCK without retry" {
    setup_trigger_fixture
    export STUB_GATE_MODE=block
    record_trigger_approvals

    local gate_dir="$TRIGGER_ROOT/queue/gates/cmd_trigger"
    local approvals="$gate_dir/review_approvals"
    local manifest
    manifest=$(awk '$1 == "manifest:" {print $2; exit}' "$gate_dir/review_gate.done")
    [ -n "$manifest" ]
    for i in $(seq 1 140); do
        [ -f "$approvals/.gate_triggered.$manifest" ] && break
        sleep 0.05
    done
    [ -n "$manifest" ]
    local log="$gate_dir/cmd_complete_gate.trigger.log"
    [ "$(cat "$STUB_GATE_STATE")" -eq 1 ]
    [ "$(grep -c '^attempt=' "$log")" -eq 1 ]
    grep -q '^attempt=1 rc=1 ' "$log"
    grep -q '^result: 1$' "$approvals/.gate_triggered.$manifest"
    [ ! -e "$approvals/.gate_triggering.$manifest" ]
}

setup_fail_close_fixture() {
    export FAIL_CLOSE_ROOT="$BATS_TEST_TMPDIR/fail-close-root"
    mkdir -p "$FAIL_CLOSE_ROOT/queue/reports" "$FAIL_CLOSE_ROOT/queue/gates" \
        "$FAIL_CLOSE_ROOT/queue/tasks" "$FAIL_CLOSE_ROOT/queue/inbox" "$FAIL_CLOSE_ROOT/logs"
    ln -s "$BATS_TEST_DIRNAME/../../scripts" "$FAIL_CLOSE_ROOT/scripts"
}

make_fail_close_task() {
    local worker="$1" cmd_id="$2"
    cat > "$FAIL_CLOSE_ROOT/queue/tasks/${worker}.yaml" <<YAML
task:
  task_id: ${cmd_id}_normal
  parent_cmd: ${cmd_id}
  issued_cmd_id: ${cmd_id}
  status: done
  reviewed: true
  review_result: ACCEPT
  deployed_at: "2026-08-11T00:00:00"
  acknowledged_at: "2026-08-11T00:01:00"
  completed_at: "2026-08-11T00:10:00"
  done_at: "2026-08-11T00:10:00"
YAML
}

make_fail_close_report() {
    local worker="$1" cmd_id="$2"
    local report="$FAIL_CLOSE_ROOT/queue/reports/${worker}_report_${cmd_id}.yaml"
    cat > "$report" <<YAML
worker_id: ${worker}
task_id: ${cmd_id}_normal
parent_cmd: ${cmd_id}
task_type: hotfix
status: completed
verdict: PASS
commit_hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
binary_checks:
  commit:
    - check: "implementation commit exists"
      result: "yes"
files_modified:
  - path: scripts/foo.sh
YAML
    printf '%s\n' "$report"
}

fail_close_review() {
    REVIEW_APPROVAL_ROOT="$FAIL_CLOSE_ROOT" \
    REVIEW_APPROVAL_SKIP_LEDGER_CHECK=1 \
    REVIEW_APPROVAL_NO_TRIGGER=1 \
    REVIEW_APPROVAL_NO_NOTIFY=1 \
    bash "$FAIL_CLOSE_ROOT/scripts/review_approval.sh" "$@"
}

seed_fail_close_gunshi_lgtm() {
    local cmd_id="$1" report="$2" key fingerprint approval_dir
    key="$(PROJECT_ROOT="$FAIL_CLOSE_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_key "${2#"$1"/}"' _ "$FAIL_CLOSE_ROOT" "$report")"
    fingerprint="$(PROJECT_ROOT="$FAIL_CLOSE_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_fingerprint "$2"' _ "$FAIL_CLOSE_ROOT" "$report")"
    approval_dir="$FAIL_CLOSE_ROOT/queue/gates/$cmd_id/review_approvals/reports/$key"
    mkdir -p "$approval_dir"
    printf 'timestamp: 2026-08-11T00:11:00+09:00\nrole: gunshi\nresult: LGTM\nfingerprint: %s\nreport: queue/reports/%s\n' \
        "$fingerprint" "$(basename "$report")" > "$approval_dir/gunshi.yaml"
}

setup_pair_fixture() {
    export PAIR_ROOT="$BATS_TEST_TMPDIR/pair-root"
    mkdir -p "$PAIR_ROOT/queue/reports" "$PAIR_ROOT/queue/archive/reports" \
        "$PAIR_ROOT/queue/tasks" "$PAIR_ROOT/queue/inbox" "$PAIR_ROOT/archive/inbox" \
        "$PAIR_ROOT/queue/gates" "$PAIR_ROOT/logs" "$PAIR_ROOT/scripts"
    ln -s "$BATS_TEST_DIRNAME/../../scripts/review_approval.sh" "$PAIR_ROOT/scripts/review_approval.sh"
    ln -s "$BATS_TEST_DIRNAME/../../scripts/lib" "$PAIR_ROOT/scripts/lib"
    for script in report_field_set.sh report_unique_identity.py inbox_write.sh; do
        ln -s "$BATS_TEST_DIRNAME/../../scripts/$script" "$PAIR_ROOT/scripts/$script"
    done
}

make_pair_report() {
    local worker="$1" cmd_id="$2"
    local report="$PAIR_ROOT/queue/reports/${worker}_report_${cmd_id}.yaml"
    cat > "$report" <<YAML
worker_id: ${worker}
task_id: ${cmd_id}_normal
report_id: rpt-22222222-2222-4222-8222-222222222222
report_identity_version: 2
parent_cmd: ${cmd_id}
task_type: hotfix
status: completed
verdict: PASS
commit_hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
result:
  summary: initial report fingerprint
binary_checks:
  commit:
    - check: implementation commit exists
      result: yes
files_modified:
  - path: scripts/review_approval.sh
YAML
    printf '%s\n' "$report"
}

make_pair_task() {
    local worker="$1" cmd_id="$2"
    cat > "$PAIR_ROOT/queue/tasks/${worker}.yaml" <<YAML
task:
  task_id: ${cmd_id}_normal
  parent_cmd: ${cmd_id}
  issued_cmd_id: ${cmd_id}
  report_filename: ${worker}_report_${cmd_id}.yaml
  task_type: hotfix
  status: done
  reviewed: true
  review_result: ACCEPT
  deployed_at: "2026-08-28T00:00:00+09:00"
  acknowledged_at: "2026-08-28T00:01:00+09:00"
  completed_at: "2026-08-28T00:10:00+09:00"
  done_at: "2026-08-28T00:10:00+09:00"
YAML
}

pair_review() {
    REVIEW_APPROVAL_ROOT="$PAIR_ROOT" \
    REVIEW_APPROVAL_SKIP_LEDGER_CHECK=1 \
    REVIEW_APPROVAL_NO_TRIGGER=1 \
    REVIEW_APPROVAL_NO_NOTIFY=1 \
    bash "$PAIR_ROOT/scripts/review_approval.sh" "$@"
}

# test_necessity: a failed report formally accepted by Karo after a report-only
# RC is a terminal failure close, not a fresh report correction requiring a new
# Gunshi LGTM.
# regression_justification: cmd_karo_hotfix_fail_close_after_report_rc_202608110653
@test "report-only RC followed by failed Karo ACCEPT is the fail-close boundary" {
    setup_fail_close_fixture
    local cmd_id=cmd_karo_fail_close_report_rc worker=failcloseworker
    make_fail_close_task "$worker" "$cmd_id"
    local report
    report="$(make_fail_close_report "$worker" "$cmd_id")"

    run fail_close_review "$cmd_id" karo RC "$report" report
    [ "$status" -eq 0 ]
    bash "$FAIL_CLOSE_ROOT/scripts/report_field_set.sh" "$report" result.summary "failed after report-only RC"
    sed -i 's/^status: revision_requested/status: failed/; s/^verdict: PASS/verdict: FAIL/' "$report"

    run fail_close_review "$cmd_id" karo ACCEPT "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"fail-close review recorded"* ]]
}

# test_necessity: a non-failed report-only correction still requires a fresh
# Gunshi approval bound to the corrected payload.
# regression_justification: the fail-close exception must not weaken the
# existing report-only fingerprint review boundary.
@test "completed report-only correction still requires current Gunshi LGTM" {
    setup_fail_close_fixture
    local cmd_id=cmd_karo_report_correction_guard worker=reportguardworker
    make_fail_close_task "$worker" "$cmd_id"
    local report
    report="$(make_fail_close_report "$worker" "$cmd_id")"

    run fail_close_review "$cmd_id" karo RC "$report" report
    [ "$status" -eq 0 ]
    bash "$FAIL_CLOSE_ROOT/scripts/report_field_set.sh" "$report" result.summary "corrected report payload"
    bash "$FAIL_CLOSE_ROOT/scripts/report_field_set.sh" "$report" status completed

    run fail_close_review "$cmd_id" karo ACCEPT "$report"
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires current Gunshi LGTM"* ]]
}

# test_necessity: Karo ACCEPT is only terminal when the exact report
# fingerprint already has a canonical Gunshi LGTM, and repeated approvals for
# one generation retain the first approval boundary timestamp.
# regression_justification: Karo could be recorded before Gunshi, and a retry
# of the same Gunshi decision moved the boundary used by reversed-pair
# telemetry; an RC generation must still receive a fresh boundary.
@test "review approval pairing is fail-closed and timestamp-idempotent" {
    setup_pair_fixture
    local cmd_id=cmd_karo_review_pair_idempotency worker=pairworker
    make_pair_task "$worker" "$cmd_id"
    local report
    report="$(make_pair_report "$worker" "$cmd_id")"

    run pair_review "$cmd_id" karo ACCEPT "$report"
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires current Gunshi LGTM"* ]]
    local key approval_dir first second third
    key="$(PROJECT_ROOT="$PAIR_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_key "${2#"$1"/}"' _ "$PAIR_ROOT" "$report")"
    approval_dir="$PAIR_ROOT/queue/gates/$cmd_id/review_approvals/reports/$key"
    [ ! -f "$approval_dir/karo.yaml" ]

    run pair_review "$cmd_id" gunshi LGTM "$report"
    echo "$output" >&3
    [ "$status" -eq 0 ]
    first="$(sed -n 's/^timestamp: //p' "$approval_dir/gunshi.yaml")"
    sleep 1
    run pair_review "$cmd_id" gunshi LGTM "$report"
    [ "$status" -eq 0 ]
    second="$(sed -n 's/^timestamp: //p' "$approval_dir/gunshi.yaml")"
    [ "$second" = "$first" ]

    bash "$PAIR_ROOT/scripts/report_field_set.sh" "$report" status revision_requested
    bash "$PAIR_ROOT/scripts/report_field_set.sh" "$report" result.summary "new report fingerprint"
    bash "$PAIR_ROOT/scripts/report_field_set.sh" "$report" status completed
    sleep 1
    run pair_review "$cmd_id" gunshi LGTM "$report"
    [ "$status" -eq 0 ]
    third="$(sed -n 's/^timestamp: //p' "$approval_dir/gunshi.yaml")"
    [ "$third" != "$first" ]

    run pair_review "$cmd_id" karo RC "$report"
    [ "$status" -eq 0 ]
    bash "$PAIR_ROOT/scripts/report_field_set.sh" "$report" commit_hash bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    bash "$PAIR_ROOT/scripts/report_field_set.sh" "$report" status completed
    run pair_review "$cmd_id" gunshi LGTM "$report"
    [ "$status" -eq 0 ]
    [ "$(sed -n 's/^timestamp: //p' "$approval_dir/gunshi.yaml")" != "$third" ]
}

# test_necessity: a same-fingerprint Gunshi retry after a newly delivered
# same-generation review request must publish a new approval epoch, while a
# retry without a new request retains the original epoch.
# regression_justification: the old idempotency rule only compared result and
# fingerprint, so a 04:46 review request after the 04:15 LGTM still reused the
# old epoch and produced reversed_report_done_to_review_request telemetry.
@test "same fingerprint gets a new epoch only after a new review request" {
    setup_pair_fixture
    local cmd_id=cmd_karo_review_request_epoch worker=epochworker
    make_pair_task "$worker" "$cmd_id"
    local report
    report="$(make_pair_report "$worker" "$cmd_id")"
    local report_base raw_generation
    report_base="${report#"$PAIR_ROOT"/}"
    raw_generation="$(sha256sum "$report" | awk '{print $1}')"
    cat > "$PAIR_ROOT/queue/inbox/gunshi.yaml" <<YAML
messages:
  - type: report_review
    report_id: rpt-22222222-2222-4222-8222-222222222222
    report_identity_version: 2
    report_fingerprint: $raw_generation
    report_path: $report_base
    task_id: ${cmd_id}_normal
    parent_cmd: $cmd_id
    timestamp: '2026-08-28T09:10:10+09:00'
YAML

    local key approval_dir first duplicate second retry
    run pair_review "$cmd_id" gunshi LGTM "$report"
    [ "$status" -eq 0 ]
    key="$(PROJECT_ROOT="$PAIR_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_key "${2#"$1"/}"' _ "$PAIR_ROOT" "$report")"
    approval_dir="$PAIR_ROOT/queue/gates/$cmd_id/review_approvals/reports/$key"
    first="$(sed -n 's/^timestamp: //p' "$approval_dir/gunshi.yaml")"

    sleep 1
    run pair_review "$cmd_id" gunshi LGTM "$report"
    [ "$status" -eq 0 ]
    duplicate="$(sed -n 's/^timestamp: //p' "$approval_dir/gunshi.yaml")"
    [ "$duplicate" = "$first" ]

    sleep 1
    cat > "$PAIR_ROOT/queue/inbox/gunshi.yaml" <<YAML
messages:
  - type: report_review
    report_id: rpt-22222222-2222-4222-8222-222222222222
    report_identity_version: 2
    report_fingerprint: $raw_generation
    report_path: $report_base
    task_id: ${cmd_id}_normal
    parent_cmd: $cmd_id
    timestamp: '$(date -Iseconds)'
YAML
    sleep 1
    run pair_review "$cmd_id" gunshi LGTM "$report"
    [ "$status" -eq 0 ]
    second="$(sed -n 's/^timestamp: //p' "$approval_dir/gunshi.yaml")"
    [ "$second" != "$first" ]

    sleep 1
    run pair_review "$cmd_id" gunshi LGTM "$report"
    [ "$status" -eq 0 ]
    retry="$(sed -n 's/^timestamp: //p' "$approval_dir/gunshi.yaml")"
    [ "$retry" = "$second" ]
}

# test_necessity: archived review requests and offset-less JST timestamps are
# part of the durable review history; omitting either source can resurrect an
# old LGTM epoch or shift the epoch comparison by nine hours.
# regression_justification: the first implementation only read active
# queue/inbox/gunshi.yaml and interpreted naive timestamps as UTC.
@test "archived review request uses JST and refreshes the same fingerprint epoch" {
    setup_pair_fixture
    local cmd_id=cmd_karo_review_archive_epoch worker=archiveepochworker
    make_pair_task "$worker" "$cmd_id"
    local report
    report="$(make_pair_report "$worker" "$cmd_id")"
    local report_base raw_generation key approval_dir normalized
    report_base="${report#"$PAIR_ROOT"/}"
    raw_generation="$(sha256sum "$report" | awk '{print $1}')"
    key="$(PROJECT_ROOT="$PAIR_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_key "${2#"$1"/}"' _ "$PAIR_ROOT" "$report")"
    approval_dir="$PAIR_ROOT/queue/gates/$cmd_id/review_approvals/reports/$key"
    mkdir -p "$approval_dir"
    normalized="$(PROJECT_ROOT="$PAIR_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_fingerprint "$2"' _ "$PAIR_ROOT" "$report")"
    printf 'timestamp: 2026-09-02T00:30:00+00:00\nrole: gunshi\nresult: LGTM\nfingerprint: %s\nreport: %s\n' \
        "$normalized" "$report_base" > "$approval_dir/gunshi.yaml"

    cat > "$PAIR_ROOT/archive/inbox/gunshi_20260902.yaml" <<YAML
messages:
  - type: report_review
    report_id: rpt-22222222-2222-4222-8222-222222222222
    report_identity_version: 2
    report_fingerprint: $raw_generation
    report_path: $report_base
    task_id: ${cmd_id}_normal
    parent_cmd: $cmd_id
    timestamp: '2026-09-02T05:00:00'
YAML
    run pair_review "$cmd_id" gunshi LGTM "$report"
    [ "$status" -eq 0 ]
    [ "$(sed -n 's/^timestamp: //p' "$approval_dir/gunshi.yaml")" = '2026-09-02T00:30:00+00:00' ]

    cat > "$PAIR_ROOT/archive/inbox/gunshi_20260902.yaml" <<YAML
messages:
  - type: report_review
    report_id: rpt-22222222-2222-4222-8222-222222222222
    report_identity_version: 2
    report_fingerprint: $raw_generation
    report_path: $report_base
    task_id: ${cmd_id}_normal
    parent_cmd: $cmd_id
    timestamp: '2026-09-02T10:00:00+09:00'
YAML
    run pair_review "$cmd_id" gunshi LGTM "$report"
    [ "$status" -eq 0 ]
    [ "$(sed -n 's/^timestamp: //p' "$approval_dir/gunshi.yaml")" != '2026-09-02T00:30:00+00:00' ]
}

setup_rc_revoke_generation_fixture() {
    export RC_REVOKE_ROOT="$BATS_TEST_TMPDIR/rc-revoke-generation-root"
    mkdir -p "$RC_REVOKE_ROOT/queue/reports" "$RC_REVOKE_ROOT/queue/archive/reports" \
      "$RC_REVOKE_ROOT/queue/tasks" "$RC_REVOKE_ROOT/queue/inbox" \
      "$RC_REVOKE_ROOT/queue/gates" "$RC_REVOKE_ROOT/logs"
    ln -s "$BATS_TEST_DIRNAME/../../scripts" "$RC_REVOKE_ROOT/scripts"
    cat > "$RC_REVOKE_ROOT/queue/tasks/worker.yaml" <<'TASK'
task:
  task_id: cmd_karo_rc_revoke_generation_normal
  parent_cmd: cmd_karo_rc_revoke_generation
  issued_cmd_id: cmd_karo_rc_revoke_generation
  report_filename: worker_report_cmd_karo_rc_revoke_generation.yaml
  task_type: hotfix
  status: done
  reviewed: true
  review_result: ACCEPT
  deployed_at: "2026-08-18T00:00:00"
  acknowledged_at: "2026-08-18T00:01:00"
  completed_at: "2026-08-18T00:10:00"
  done_at: "2026-08-18T00:10:00"
TASK
    cat > "$RC_REVOKE_ROOT/queue/reports/worker_report_cmd_karo_rc_revoke_generation.yaml" <<'REPORT'
worker_id: worker
task_id: cmd_karo_rc_revoke_generation_normal
report_id: rpt-rc-revoke-generation-v1
report_identity_version: 2
parent_cmd: cmd_karo_rc_revoke_generation
task_type: hotfix
status: completed
verdict: PASS
commit_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
result:
  summary: generation one
binary_checks:
  commit:
    - check: implementation commit exists
      result: yes
files_modified:
  - path: scripts/review_approval.sh
REPORT
    export RC_REVOKE_REPORT="$RC_REVOKE_ROOT/queue/reports/worker_report_cmd_karo_rc_revoke_generation.yaml"
    export REVIEW_APPROVAL_ROOT="$RC_REVOKE_ROOT"
    export REVIEW_APPROVAL_SKIP_LEDGER_CHECK=1
    export REVIEW_APPROVAL_NO_NOTIFY=1
    export REVIEW_APPROVAL_NO_TRIGGER=1
}

# test_necessity: RC_REVOKE must not restore an older report/task snapshot over
# a newer completed/PASS generation; the current generation remains eligible
# for the normal Gunshi LGTM and Karo ACCEPT boundary.
# regression_justification: cmd_karo_hotfix_rc_revoke_generation_20260818
@test "RC_REVOKE retires only the RC when the current report generation changed" {
    setup_rc_revoke_generation_fixture

    run bash "$RC_REVOKE_ROOT/scripts/review_approval.sh" \
      cmd_karo_rc_revoke_generation karo RC "$RC_REVOKE_REPORT" implementation
    [ "$status" -eq 0 ]
    grep -q '^status: revision_requested$' "$RC_REVOKE_REPORT"

    bash "$RC_REVOKE_ROOT/scripts/report_field_set.sh" "$RC_REVOKE_REPORT" \
      result.summary "generation two"
    bash "$RC_REVOKE_ROOT/scripts/report_field_set.sh" "$RC_REVOKE_REPORT" status completed
    bash "$RC_REVOKE_ROOT/scripts/lib/yaml_field_set.sh" \
      "$RC_REVOKE_ROOT/queue/tasks/worker.yaml" task status done
    report_before=$(sha256sum "$RC_REVOKE_REPORT" | awk '{print $1}')
    task_before=$(sha256sum "$RC_REVOKE_ROOT/queue/tasks/worker.yaml" | awk '{print $1}')

    run bash "$RC_REVOKE_ROOT/scripts/review_approval.sh" \
      cmd_karo_rc_revoke_generation karo RC_REVOKE "$RC_REVOKE_REPORT" \
      "revoke stale RC only"
    [ "$status" -eq 0 ]
    [[ "$output" == *"without restoring newer report generation"* ]]
    [ "$(sha256sum "$RC_REVOKE_REPORT" | awk '{print $1}')" = "$report_before" ]
    [ "$(sha256sum "$RC_REVOKE_ROOT/queue/tasks/worker.yaml" | awk '{print $1}')" = "$task_before" ]
    grep -q '^status: completed$' "$RC_REVOKE_REPORT"
    grep -q '^  summary: generation two$' "$RC_REVOKE_REPORT"
    grep -q '^  status: done$' "$RC_REVOKE_ROOT/queue/tasks/worker.yaml"
    [ "$(find "$RC_REVOKE_ROOT/queue/gates/cmd_karo_rc_revoke_generation" -name last_rc_snapshot_dir -type f | wc -l)" -eq 0 ]

    local key fingerprint approval_dir
    key="$(PROJECT_ROOT="$RC_REVOKE_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_key "${2#"$1"/}"' _ "$RC_REVOKE_ROOT" "$RC_REVOKE_REPORT")"
    fingerprint="$(PROJECT_ROOT="$RC_REVOKE_ROOT" bash -c 'source "$1/scripts/lib/review_approval.sh"; review_report_fingerprint "$2"' _ "$RC_REVOKE_ROOT" "$RC_REVOKE_REPORT")"
    approval_dir="$RC_REVOKE_ROOT/queue/gates/cmd_karo_rc_revoke_generation/review_approvals/reports/$key"
    mkdir -p "$approval_dir"
    printf 'timestamp: 2026-08-18T00:11:00+09:00\nrole: gunshi\nresult: LGTM\nfingerprint: %s\nreport: queue/reports/%s\n' \
      "$fingerprint" "$(basename "$RC_REVOKE_REPORT")" > "$approval_dir/gunshi.yaml"

    run bash "$RC_REVOKE_ROOT/scripts/review_approval.sh" \
      cmd_karo_rc_revoke_generation karo ACCEPT "$RC_REVOKE_REPORT"
    [ "$status" -eq 0 ]
}

# test_necessity: same-generation RC_REVOKE retains the pre-RC restoration
# contract while the newer-generation branch above protects current state.
@test "RC_REVOKE restores the snapshot for the same report generation" {
    setup_rc_revoke_generation_fixture

    run bash "$RC_REVOKE_ROOT/scripts/review_approval.sh" \
      cmd_karo_rc_revoke_generation karo RC "$RC_REVOKE_REPORT" implementation
    [ "$status" -eq 0 ]
    bash "$RC_REVOKE_ROOT/scripts/review_approval.sh" \
      cmd_karo_rc_revoke_generation karo RC_REVOKE "$RC_REVOKE_REPORT" \
      "revoke same generation"
    grep -q '^status: completed$' "$RC_REVOKE_REPORT"
    grep -q '^  summary: generation one$' "$RC_REVOKE_REPORT"
}

setup_legacy_rc_revoke_fixture() {
    export LEGACY_RC_ROOT="$BATS_TEST_TMPDIR/legacy-rc-revoke-root"
    mkdir -p "$LEGACY_RC_ROOT/queue/reports" "$LEGACY_RC_ROOT/queue/archive/reports" \
      "$LEGACY_RC_ROOT/queue/tasks" "$LEGACY_RC_ROOT/queue/inbox" \
      "$LEGACY_RC_ROOT/queue/gates" "$LEGACY_RC_ROOT/logs"
    ln -s "$BATS_TEST_DIRNAME/../../scripts" "$LEGACY_RC_ROOT/scripts"
    cat > "$LEGACY_RC_ROOT/queue/tasks/worker.yaml" <<'TASK'
task:
  task_id: cmd_4353_normal
  parent_cmd: cmd_4353
  report_filename: worker_report_cmd_4353.yaml
  task_type: hotfix
  status: done
  reviewed: true
  review_result: ACCEPT
  deployed_at: "2026-08-18T00:00:00"
  acknowledged_at: "2026-08-18T00:01:00"
  completed_at: "2026-08-18T00:10:00"
  done_at: "2026-08-18T00:10:00"
TASK
    cat > "$LEGACY_RC_ROOT/queue/reports/worker_report_cmd_4353.yaml" <<'REPORT'
worker_id: worker
task_id: cmd_4353_normal
report_id: rpt-cmd-4353-legacy
report_identity_version: 2
parent_cmd: cmd_4353
task_type: hotfix
status: completed
verdict: PASS
commit_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
result:
  summary: generation one
binary_checks:
  commit:
    - check: implementation commit exists
      result: yes
files_modified:
  - path: scripts/review_approval.sh
REPORT
    export LEGACY_RC_REPORT="$LEGACY_RC_ROOT/queue/reports/worker_report_cmd_4353.yaml"
    export REVIEW_APPROVAL_ROOT="$LEGACY_RC_ROOT"
    export REVIEW_APPROVAL_SKIP_LEDGER_CHECK=1
    export REVIEW_APPROVAL_NO_NOTIFY=1
    export REVIEW_APPROVAL_NO_TRIGGER=1
}

legacy_rc_snapshot_paths() {
    local pointer
    pointer=$(find "$LEGACY_RC_ROOT/queue/gates" -name last_rc_snapshot_dir -type f | head -n 1)
    printf '%s\n%s\n' "$pointer" "$(head -n 1 "$pointer")"
}

# test_necessity: legacy RC snapshots must reproduce the cmd_4353 generation
# mismatch and preserve the current report/task instead of restoring old state.
# regression_justification: cmd_karo_hotfix_rc_revoke_legacy_generation_20260818
@test "legacy RC marker fingerprint preserves a newer cmd_4353 generation" {
    setup_legacy_rc_revoke_fixture
    run bash "$LEGACY_RC_ROOT/scripts/review_approval.sh" \
      cmd_4353 karo RC "$LEGACY_RC_REPORT" implementation
    [ "$status" -eq 0 ]

    mapfile -t snapshot_paths < <(legacy_rc_snapshot_paths)
    snapshot_pointer=${snapshot_paths[0]}
    snapshot_dir=${snapshot_paths[1]}
    [ -f "$snapshot_pointer" ]
    old_fingerprint=$(awk -F': ' '$1 == "fingerprint" {print $2; exit}' \
      "$(dirname "$snapshot_pointer")/karo.yaml")
    [ -n "$old_fingerprint" ]
    rm -f "$snapshot_dir/report_fingerprint" "$snapshot_dir/report_generation"

    bash "$LEGACY_RC_ROOT/scripts/report_field_set.sh" "$LEGACY_RC_REPORT" \
      result.summary "generation two"
    bash "$LEGACY_RC_ROOT/scripts/report_field_set.sh" "$LEGACY_RC_REPORT" status completed
    bash "$LEGACY_RC_ROOT/scripts/lib/yaml_field_set.sh" \
      "$LEGACY_RC_ROOT/queue/tasks/worker.yaml" task status done
    report_before=$(sha256sum "$LEGACY_RC_REPORT" | awk '{print $1}')
    task_before=$(sha256sum "$LEGACY_RC_ROOT/queue/tasks/worker.yaml" | awk '{print $1}')

    run bash "$LEGACY_RC_ROOT/scripts/review_approval.sh" \
      cmd_4353 karo RC_REVOKE "$LEGACY_RC_REPORT" "revoke legacy stale RC"
    [ "$status" -eq 0 ]
    [[ "$output" == *"without restoring newer report generation"* ]]
    [ "$(sha256sum "$LEGACY_RC_REPORT" | awk '{print $1}')" = "$report_before" ]
    [ "$(sha256sum "$LEGACY_RC_ROOT/queue/tasks/worker.yaml" | awk '{print $1}')" = "$task_before" ]
    grep -q '^status: completed$' "$LEGACY_RC_REPORT"
    grep -q '^  summary: generation two$' "$LEGACY_RC_REPORT"
    grep -q '^  status: done$' "$LEGACY_RC_ROOT/queue/tasks/worker.yaml"
    [ ! -e "$snapshot_pointer" ]
}

# test_necessity: a legacy marker from another report identity must not be used
# as a fallback fingerprint or mutate the current generation.
@test "legacy RC marker identity mismatch fails closed" {
    setup_legacy_rc_revoke_fixture
    run bash "$LEGACY_RC_ROOT/scripts/review_approval.sh" \
      cmd_4353 karo RC "$LEGACY_RC_REPORT" implementation
    [ "$status" -eq 0 ]
    mapfile -t snapshot_paths < <(legacy_rc_snapshot_paths)
    snapshot_pointer=${snapshot_paths[0]}
    snapshot_dir=${snapshot_paths[1]}
    rm -f "$snapshot_dir/report_fingerprint"
    marker_dir=$(dirname "$snapshot_pointer")
    sed -i 's|^report: .*|report: queue/reports/other.yaml|' "$marker_dir/karo.yaml"
    report_before=$(sha256sum "$LEGACY_RC_REPORT" | awk '{print $1}')

    run bash "$LEGACY_RC_ROOT/scripts/review_approval.sh" \
      cmd_4353 karo RC_REVOKE "$LEGACY_RC_REPORT" "reject mismatched legacy marker"
    [ "$status" -ne 0 ]
    [[ "$output" == *"legacy RC marker report identity mismatch"* ]]
    [ "$(sha256sum "$LEGACY_RC_REPORT" | awk '{print $1}')" = "$report_before" ]
    [ -f "$snapshot_pointer" ]
}

# test_necessity: a legacy marker without a valid fingerprint must fail closed
# before any report/task or RC archive mutation.
@test "legacy RC marker without fingerprint fails closed" {
    setup_legacy_rc_revoke_fixture
    run bash "$LEGACY_RC_ROOT/scripts/review_approval.sh" \
      cmd_4353 karo RC "$LEGACY_RC_REPORT" implementation
    [ "$status" -eq 0 ]
    mapfile -t snapshot_paths < <(legacy_rc_snapshot_paths)
    snapshot_pointer=${snapshot_paths[0]}
    snapshot_dir=${snapshot_paths[1]}
    rm -f "$snapshot_dir/report_fingerprint"
    sed -i '/^fingerprint:/d' "$(dirname "$snapshot_pointer")/karo.yaml"

    run bash "$LEGACY_RC_ROOT/scripts/review_approval.sh" \
      cmd_4353 karo RC_REVOKE "$LEGACY_RC_REPORT" "reject missing legacy fingerprint"
    [ "$status" -ne 0 ]
    [[ "$output" == *"legacy RC marker fingerprint missing or invalid"* ]]
    [ -f "$snapshot_pointer" ]
}

# test_necessity: an implementation-scope RC cannot be closed by resubmitting
# the same implementation commit, even though the fail-close lane is exempt.
# regression_justification: the exception is keyed to failed+FAIL+Karo ACCEPT,
# not to every post-RC acceptance.
@test "implementation correction still rejects an unchanged commit" {
    setup_fail_close_fixture
    local cmd_id=cmd_karo_implementation_guard worker=implementationguard
    make_fail_close_task "$worker" "$cmd_id"
    local report
    report="$(make_fail_close_report "$worker" "$cmd_id")"

    run fail_close_review "$cmd_id" karo RC "$report"
    [ "$status" -eq 0 ]
    sed -i 's/^status: revision_requested/status: completed/' "$report"
    seed_fail_close_gunshi_lgtm "$cmd_id" "$report"

    run fail_close_review "$cmd_id" karo ACCEPT "$report"
    [ "$status" -ne 0 ]
    [[ "$output" == *"implementation commit unchanged since Karo RC"* ]]
}
