#!/usr/bin/env bats
# Purpose: archived reportの旧active pathを部分YAMLとして再生成しない。

setup() {
    export RFS_ARCHIVE_GUARD_ROOT
    RFS_ARCHIVE_GUARD_ROOT="$(mktemp -d "$BATS_TMPDIR/rfs_archive_guard.XXXXXX")"
    mkdir -p "$RFS_ARCHIVE_GUARD_ROOT/scripts/lib" "$RFS_ARCHIVE_GUARD_ROOT/queue/reports" "$RFS_ARCHIVE_GUARD_ROOT/archive/reports/completed"
    cp "$BATS_TEST_DIRNAME/../../scripts/report_field_set.sh" "$RFS_ARCHIVE_GUARD_ROOT/scripts/report_field_set.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/yaml_field_set.sh" "$RFS_ARCHIVE_GUARD_ROOT/scripts/lib/yaml_field_set.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/yaml_atomic.py" "$RFS_ARCHIVE_GUARD_ROOT/scripts/lib/yaml_atomic.py"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/report_commit_identity.py" "$RFS_ARCHIVE_GUARD_ROOT/scripts/lib/report_commit_identity.py"
    export RFS="$RFS_ARCHIVE_GUARD_ROOT/scripts/report_field_set.sh"
}

teardown() {
    rm -rf "$RFS_ARCHIVE_GUARD_ROOT"
}

write_complete_report() {
    local path="$1"
    cat > "$path" <<'YAML'
worker_id: kagemaru
parent_cmd: cmd_archive_guard
ac_version_read: abc12345
status: completed
result:
  summary: original
  details: preserved
purpose_validation:
  cmd_purpose: archive guard
  fit: true
files_modified:
  - path: scripts/report_field_set.sh
    change: guard
lesson_candidate:
  found: false
  no_lesson_reason: covered
lessons_useful:
  - id: L625
    useful: true
    reason: used
binary_checks:
  AC1:
    - check: archived report preserved
      result: yes
verdict: PASS
YAML
}

@test "missing active path with same-basename archive is blocked without residual file" {
    local active="$RFS_ARCHIVE_GUARD_ROOT/queue/reports/kagemaru_report_cmd_archive_guard.yaml"
    local archived="$RFS_ARCHIVE_GUARD_ROOT/archive/reports/completed/kagemaru_report_cmd_archive_guard.yaml"
    write_complete_report "$archived"

    run bash "$RFS" "$active" result.summary stale-write

    [ "$status" -ne 0 ]
    [[ "$output" == *"candidate archive path: $archived"* ]]
    [ ! -e "$active" ]
}

@test "explicit archive path update preserves required fields and line count" {
    local archived="$RFS_ARCHIVE_GUARD_ROOT/archive/reports/completed/kagemaru_report_cmd_archive_guard.yaml"
    write_complete_report "$archived"
    local before_lines
    before_lines="$(wc -l < "$archived")"

    run bash "$RFS" "$archived" result.summary canonical-update

    [ "$status" -eq 0 ]
    [ "$(wc -l < "$archived")" -eq "$before_lines" ]
    python3 - "$archived" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
for key in ("worker_id", "parent_cmd", "ac_version_read", "result", "purpose_validation", "files_modified", "lesson_candidate", "lessons_useful", "binary_checks", "verdict"):
    assert key in data, key
assert data["result"]["summary"] == "canonical-update"
assert data["result"]["details"] == "preserved"
PY
}

@test "existing active report remains writable" {
    local active="$RFS_ARCHIVE_GUARD_ROOT/queue/reports/kagemaru_report_cmd_active.yaml"
    # status: pending here (not completed) — this test exercises the archive
    # residual guard's non-interference with a normal in-progress write, which
    # is orthogonal to the completed-report immutability guard covered by
    # test_report_field_set_completed_immutability.bats.
    cat > "$active" <<'YAML'
worker_id: kagemaru
parent_cmd: cmd_archive_guard
ac_version_read: abc12345
status: pending
result:
  summary: original
  details: preserved
YAML

    run bash "$RFS" "$active" result.summary active-update

    [ "$status" -eq 0 ]
    grep -q 'summary: active-update' "$active"
}

@test "legacy missing noncanonical path still supports create-on-write" {
    local legacy="$RFS_ARCHIVE_GUARD_ROOT/legacy/new_report.yaml"
    mkdir -p "$(dirname "$legacy")"

    run bash "$RFS" "$legacy" result.summary legacy-create

    [ "$status" -eq 0 ]
    [ -f "$legacy" ]
    grep -q 'summary: legacy-create' "$legacy"
}
