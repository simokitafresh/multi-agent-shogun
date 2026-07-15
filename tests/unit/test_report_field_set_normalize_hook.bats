#!/usr/bin/env bats
# Purpose: report_field_set.shは報告がcompleted/doneへ遷移する同一原子書込みの内側で
# scripts/lib/normalize_report.shを実行する。これにより、レビュー承認(軍師LGTM/家老ACCEPT)が
# fingerprintを採取する時点で既に正規化済みとなり、cmd_complete_gate.shのB層post-approval
# normalizeは常にbyte不変のno-opになる(review_fingerprint_changed_after_normalize BLOCKが
# 二度と発火しない)。
# cmd_karo_hotfix_report_completed_immutability_202607121305 RC(normalize経路統一)

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/rfs_normalize_hook.XXXXXX")"
    mkdir -p "$TEST_ROOT/scripts/lib" "$TEST_ROOT/queue/reports"
    cp "$BATS_TEST_DIRNAME/../../scripts/report_field_set.sh" "$TEST_ROOT/scripts/report_field_set.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/yaml_field_set.sh" "$TEST_ROOT/scripts/lib/yaml_field_set.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/yaml_atomic.py" "$TEST_ROOT/scripts/lib/yaml_atomic.py"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/normalize_report.sh" "$TEST_ROOT/scripts/lib/normalize_report.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/review_approval.sh" "$TEST_ROOT/scripts/lib/review_approval.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/report_commit_identity.py" "$TEST_ROOT/scripts/lib/report_commit_identity.py"
    export RFS="$TEST_ROOT/scripts/report_field_set.sh"
    export REPORT="$TEST_ROOT/queue/reports/kagemaru_report_cmd_normhook.yaml"
    export NORMALIZE="$TEST_ROOT/scripts/lib/normalize_report.sh"
}

teardown() {
    rm -rf "$TEST_ROOT"
}

write_pending_report_with_legacy_candidates() {
    local path="$1"
    cat > "$path" <<'YAML'
worker_id: kagemaru
parent_cmd: cmd_normhook
ac_version_read: abc12345
status: pending
commit_hash: '3333333333333333333333333333333333333333'
result:
  summary: wip
purpose_validation:
  fit: true
files_modified:
  - path: scripts/report_field_set.sh
    change: regression fixture
lesson_candidate:
  - "legacy lesson entry"
lessons_useful:
  - id: L311
    useful: true
    reason: terminal readiness contract
decision_candidate:
  - "legacy decision entry"
binary_checks:
  AC1:
    - check: behavior verified
      result: yes
  commit:
    - check: git commit done
      result: yes
verdict: ""
YAML
}

_field_type() {
    python3 -c "import yaml, sys; d = yaml.safe_load(open(sys.argv[1])); print(type(d[sys.argv[2]]).__name__)" "$1" "$2"
}

# --- normalize fires at the completion transition, before any review can see the raw form ---

@test "verdict-triggered completion normalizes legacy list-form candidates in the same write" {
    write_pending_report_with_legacy_candidates "$REPORT"
    [ "$(_field_type "$REPORT" lesson_candidate)" = list ]

    run bash "$RFS" "$REPORT" verdict PASS

    [ "$status" -eq 0 ]
    [ "$(_field_type "$REPORT" lesson_candidate)" = dict ]
    [ "$(_field_type "$REPORT" decision_candidate)" = dict ]
    python3 -c "
import yaml
d = yaml.safe_load(open('$REPORT'))
assert d['status'] == 'completed'
assert d['lesson_candidate']['found'] is True
assert 'legacy lesson entry' in d['lesson_candidate']['detail']
"
}

@test "direct status completed write also normalizes (not only the verdict auto-transition path)" {
    # verdict is already PASS so the status=completed precondition check
    # (commit binary_checks) is satisfied without going through the verdict
    # auto-transition path (AUTO_COMPLETE_STATUS) — this exercises the other
    # way a report reaches completed: a direct `status completed` write.
    cat > "$REPORT" <<'YAML'
worker_id: kagemaru
parent_cmd: cmd_normhook
ac_version_read: abc12345
status: pending
commit_hash: '3333333333333333333333333333333333333333'
result:
  summary: wip
lesson_candidate:
  - "legacy lesson entry"
binary_checks:
  AC1:
    - check: behavior verified
      result: yes
  commit:
    - check: git commit done
      result: yes
verdict: PASS
YAML

    run bash "$RFS" "$REPORT" status completed

    [ "$status" -eq 0 ]
    [ "$(_field_type "$REPORT" lesson_candidate)" = dict ]
}

@test "already-normalized (dict-form) report completes without alteration" {
    cat > "$REPORT" <<'YAML'
worker_id: kagemaru
parent_cmd: cmd_normhook
ac_version_read: abc12345
status: pending
commit_hash: '3333333333333333333333333333333333333333'
result:
  summary: wip
purpose_validation:
  fit: true
files_modified:
  - path: scripts/report_field_set.sh
    change: regression fixture
lesson_candidate:
  found: false
  no_lesson_reason: covered
lessons_useful:
  - id: L311
    useful: true
    reason: terminal readiness contract
binary_checks:
  AC1:
    - check: behavior verified
      result: yes
  commit:
    - check: git commit done
      result: yes
verdict: ""
YAML

    run bash "$RFS" "$REPORT" verdict PASS

    [ "$status" -eq 0 ]
    python3 -c "
import yaml
d = yaml.safe_load(open('$REPORT'))
assert d['lesson_candidate'] == {'found': False, 'no_lesson_reason': 'covered'}
"
}

@test "pending (not-yet-completing) writes do not trigger normalize" {
    write_pending_report_with_legacy_candidates "$REPORT"

    run bash "$RFS" "$REPORT" result.summary "still working"

    [ "$status" -eq 0 ]
    [ "$(_field_type "$REPORT" lesson_candidate)" = list ]
}

# --- AC(1): post-approval normalize is now a byte-identical no-op ---

@test "normalize_report.sh run again after completion is a byte-identical no-op" {
    write_pending_report_with_legacy_candidates "$REPORT"
    bash "$RFS" "$REPORT" verdict PASS >/dev/null

    local before_hash after_hash
    before_hash="$(sha256sum "$REPORT" | awk '{print $1}')"

    run bash "$NORMALIZE" "$REPORT"

    [ "$status" -eq 1 ]  # normalize_report.sh contract: exit 1 = no modification needed
    after_hash="$(sha256sum "$REPORT" | awk '{print $1}')"
    [ "$before_hash" = "$after_hash" ]
}

# --- AC(2): the review_fingerprint_changed_after_normalize stall path can no longer fire ---

@test "review_report_fingerprint is unchanged by a post-approval normalize pass" {
    write_pending_report_with_legacy_candidates "$REPORT"
    bash "$RFS" "$REPORT" verdict PASS >/dev/null

    PROJECT_ROOT="$TEST_ROOT" source "$TEST_ROOT/scripts/lib/review_approval.sh"
    local fp_before fp_after
    fp_before="$(review_report_fingerprint "$REPORT")"

    bash "$NORMALIZE" "$REPORT" >/dev/null 2>&1 || true

    fp_after="$(review_report_fingerprint "$REPORT")"
    [ "$fp_before" = "$fp_after" ]
}

@test "regression: the OLD pre-hook behavior really did change the fingerprint (sanity check on the test harness itself)" {
    # This pins the bug this fix addresses: without the completion-time
    # normalize hook, a post-approval normalize pass used to change fingerprint
    # bytes. Verified here by running normalize_report.sh BEFORE report_field_set.sh
    # ever gets a chance to pre-normalize (i.e. directly on a freshly pending report,
    # emulating what happened when a legacy-list report reached review un-normalized
    # under the old code path where normalize only ran post-approval).
    write_pending_report_with_legacy_candidates "$REPORT"
    bash "$RFS" "$REPORT" verdict PASS >/dev/null
    # Force the pre-fix condition back: reintroduce a legacy list form directly
    # (bypassing report_field_set.sh, as normalize_report.sh's caller does),
    # simulating a completed report that reached review without having been
    # pre-normalized.
    python3 -c "
import yaml
from pathlib import Path
p = Path('$REPORT')
d = yaml.safe_load(p.read_text())
d['skill_candidate'] = ['legacy skill entry']
p.write_text(yaml.dump(d, sort_keys=False, allow_unicode=True))
"
    PROJECT_ROOT="$TEST_ROOT" source "$TEST_ROOT/scripts/lib/review_approval.sh"
    local fp_before fp_after
    fp_before="$(review_report_fingerprint "$REPORT")"

    run bash "$NORMALIZE" "$REPORT"
    [ "$status" -eq 0 ]  # this time it DOES find something to fix

    fp_after="$(review_report_fingerprint "$REPORT")"
    [ "$fp_before" != "$fp_after" ]
}

# --- AC(3): normalize_report.sh abnormal termination must fail-closed, not silently publish ---
# karo RC 202607121408: the first cut of this hook swallowed every non-zero exit
# with `|| true`. Only rc=0 (modified) and rc=1 (no-op) are a known-safe state
# for $tmp_file; rc=2 (usage/parse/not-a-dict error per normalize_report.sh's own
# contract) or a crash leave $tmp_file's true state unknown. Publishing it anyway
# would risk completing an unnormalized/corrupt report — reopening exactly the
# fingerprint stall path this whole hook exists to close.

install_broken_normalize() {
    local exit_code="$1"
    cat > "$NORMALIZE" <<SH
#!/usr/bin/env bash
echo "simulated abnormal termination (rc=$exit_code)" >&2
exit $exit_code
SH
    chmod +x "$NORMALIZE"
}

@test "normalize_report.sh exit 2 (parse/usage error) aborts the write: report_field_set.sh fails" {
    write_pending_report_with_legacy_candidates "$REPORT"
    install_broken_normalize 2

    run bash "$RFS" "$REPORT" verdict PASS

    [ "$status" -ne 0 ]
}

@test "normalize_report.sh exit 2 leaves the original report byte-identical (fail-closed, no silent publish)" {
    write_pending_report_with_legacy_candidates "$REPORT"
    local before_hash
    before_hash="$(sha256sum "$REPORT" | awk '{print $1}')"
    install_broken_normalize 2

    run bash "$RFS" "$REPORT" verdict PASS
    [ "$status" -ne 0 ]

    local after_hash
    after_hash="$(sha256sum "$REPORT" | awk '{print $1}')"
    [ "$before_hash" = "$after_hash" ]
    grep -q '^status: pending' "$REPORT"
}

@test "normalize_report.sh crash (exit 127, command not found style) also aborts and leaves report untouched" {
    write_pending_report_with_legacy_candidates "$REPORT"
    local before_hash
    before_hash="$(sha256sum "$REPORT" | awk '{print $1}')"
    install_broken_normalize 127

    run bash "$RFS" "$REPORT" verdict PASS

    [ "$status" -ne 0 ]
    local after_hash
    after_hash="$(sha256sum "$REPORT" | awk '{print $1}')"
    [ "$before_hash" = "$after_hash" ]
}

@test "normalize_report.sh exit 1 (legitimate no-op) still completes normally" {
    cat > "$REPORT" <<'YAML'
worker_id: kagemaru
parent_cmd: cmd_normhook
ac_version_read: abc12345
status: pending
commit_hash: '3333333333333333333333333333333333333333'
result:
  summary: wip
purpose_validation:
  fit: true
files_modified:
  - path: scripts/report_field_set.sh
    change: regression fixture
lesson_candidate:
  found: false
  no_lesson_reason: covered
lessons_useful:
  - id: L311
    useful: true
    reason: terminal readiness contract
binary_checks:
  AC1:
    - check: behavior verified
      result: yes
  commit:
    - check: git commit done
      result: yes
verdict: ""
YAML
    # NORMALIZE is the real (copied) normalize_report.sh here — already
    # normalized content genuinely triggers its own rc=1 no-op path.

    run bash "$RFS" "$REPORT" verdict PASS

    [ "$status" -eq 0 ]
    grep -q '^status: completed' "$REPORT"
}
