#!/usr/bin/env bats
# Purpose: status completed/done後の報告は内容変更をfail-closed BLOCKする(fingerprint不変性)。
# 抜け道は revision_requested への明示遷移と、既存値と同値の冪等writeのみ。
# 既存verdict->completed自動遷移は壊れない。
# cmd_karo_hotfix_report_completed_immutability_202607121305

setup() {
    export TEST_ROOT
    TEST_ROOT="$(mktemp -d "$BATS_TMPDIR/rfs_completed_immutability.XXXXXX")"
    mkdir -p "$TEST_ROOT/scripts/lib" "$TEST_ROOT/queue/reports" "$TEST_ROOT/archive/reports/completed"
    cp "$BATS_TEST_DIRNAME/../../scripts/report_field_set.sh" "$TEST_ROOT/scripts/report_field_set.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/yaml_field_set.sh" "$TEST_ROOT/scripts/lib/yaml_field_set.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/yaml_atomic.py" "$TEST_ROOT/scripts/lib/yaml_atomic.py"
    export RFS="$TEST_ROOT/scripts/report_field_set.sh"
    export REPORT="$TEST_ROOT/queue/reports/kagemaru_report_cmd_immut.yaml"
}

teardown() {
    rm -rf "$TEST_ROOT"
}

write_completed_report() {
    local path="$1"
    cat > "$path" <<'YAML'
worker_id: kagemaru
parent_cmd: cmd_immut
ac_version_read: abc12345
status: completed
commit_hash: '0000000000000000000000000000000000000000'
result:
  summary: original summary
  details: original details
lesson_candidate:
  found: false
  no_lesson_reason: covered
lessons_useful:
  - id: L001
    useful: true
    reason: used
binary_checks:
  AC1:
    - check: behavior verified
      result: yes
  commit:
    - check: git commit done
      result: yes
verdict: PASS
YAML
}

write_pending_report() {
    local path="$1"
    cat > "$path" <<'YAML'
worker_id: kagemaru
parent_cmd: cmd_immut
ac_version_read: abc12345
status: pending
result:
  summary: wip
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

_status() {
    python3 -c "import yaml, sys; print(yaml.safe_load(open(sys.argv[1]))['status'])" "$1"
}

# --- AC2: completed後の内容変更はfail-closed BLOCK ---

@test "completed report: result.summary change is BLOCKED" {
    write_completed_report "$REPORT"

    run bash "$RFS" "$REPORT" result.summary tampered

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
    [[ "$output" == *"revision_requested"* ]]
    grep -q 'summary: original summary' "$REPORT"
}

@test "done report: content change is BLOCKED (same as completed)" {
    write_completed_report "$REPORT"
    sed -i 's/^status: completed/status: done/' "$REPORT"

    run bash "$RFS" "$REPORT" result.details tampered

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK"* ]]
    grep -q 'details: original details' "$REPORT"
}

@test "completed report: re-verdict with a different value is BLOCKED" {
    write_completed_report "$REPORT"

    run bash "$RFS" "$REPORT" verdict FAIL

    [ "$status" -ne 0 ]
    grep -q '^verdict: PASS' "$REPORT"
}

@test "completed report: status jump directly to pending is BLOCKED (not a valid unlock)" {
    write_completed_report "$REPORT"

    run bash "$RFS" "$REPORT" status pending

    [ "$status" -ne 0 ]
    [ "$(_status "$REPORT")" = completed ]
}

@test "no per-field allowlist: files_modified write on completed report is also BLOCKED" {
    write_completed_report "$REPORT"

    run bash "$RFS" "$REPORT" files_modified.0.change "rewritten"

    [ "$status" -ne 0 ]
}

# --- fingerprint invariant: a BLOCKed attempt leaves file bytes untouched ---

@test "BLOCKed write leaves report content byte-identical (fingerprint invariant)" {
    write_completed_report "$REPORT"
    local before_hash
    before_hash="$(sha256sum "$REPORT" | awk '{print $1}')"

    run bash "$RFS" "$REPORT" result.summary tampered
    [ "$status" -ne 0 ]

    local after_hash
    after_hash="$(sha256sum "$REPORT" | awk '{print $1}')"
    [ "$before_hash" = "$after_hash" ]
}

# --- AC3: explicit unlock via status -> revision_requested ---

@test "completed report: status -> revision_requested is ALLOWED (explicit unlock)" {
    write_completed_report "$REPORT"

    run bash "$RFS" "$REPORT" status revision_requested

    [ "$status" -eq 0 ]
    [ "$(_status "$REPORT")" = revision_requested ]
}

@test "revision_requested report: normal field edit PASSes" {
    write_completed_report "$REPORT"
    bash "$RFS" "$REPORT" status revision_requested

    run bash "$RFS" "$REPORT" result.details "fixed after RC"

    [ "$status" -eq 0 ]
    grep -q 'details: fixed after RC' "$REPORT"
}

@test "revision_requested report: verdict rewrite auto-completes status again (round-trip intact)" {
    write_completed_report "$REPORT"
    bash "$RFS" "$REPORT" status revision_requested

    run bash "$RFS" "$REPORT" verdict FAIL

    [ "$status" -eq 0 ]
    [ "$(_status "$REPORT")" = completed ]
    grep -q '^verdict: FAIL' "$REPORT"
}

# --- AC3: idempotent same-value writes must not be blocked ---

@test "completed report: idempotent same-value scalar write PASSes" {
    write_completed_report "$REPORT"

    run bash "$RFS" "$REPORT" result.summary "original summary"

    [ "$status" -eq 0 ]
}

@test "completed report: idempotent status=completed re-write PASSes" {
    write_completed_report "$REPORT"

    run bash "$RFS" "$REPORT" status completed

    [ "$status" -eq 0 ]
    [ "$(_status "$REPORT")" = completed ]
}

@test "completed report: idempotent verdict re-write with same value PASSes" {
    write_completed_report "$REPORT"

    run bash "$RFS" "$REPORT" verdict PASS

    [ "$status" -eq 0 ]
}

# --- AC4: pending report, normal edit PASSes (unaffected by guard) ---

@test "pending report: normal edit PASSes" {
    write_pending_report "$REPORT"

    run bash "$RFS" "$REPORT" result.summary "updated wip"

    [ "$status" -eq 0 ]
    grep -q 'summary: updated wip' "$REPORT"
}

# --- AC3: existing verdict->completed auto-transition is not broken ---

@test "pending report: verdict PASS still auto-completes status" {
    write_pending_report "$REPORT"

    run bash "$RFS" "$REPORT" verdict PASS

    [ "$status" -eq 0 ]
    [[ "$output" == *"status = completed (auto after verdict)"* ]]
    [ "$(_status "$REPORT")" = completed ]
}

# --- archived reports are out of guard scope (no live fingerprint to protect) ---

@test "archived report (outside queue/reports/): content change remains ALLOWED" {
    local archived="$TEST_ROOT/archive/reports/completed/kagemaru_report_cmd_immut.yaml"
    write_completed_report "$archived"

    run bash "$RFS" "$archived" result.summary "post-archive fix"

    [ "$status" -eq 0 ]
    grep -q 'summary: post-archive fix' "$archived"
}
