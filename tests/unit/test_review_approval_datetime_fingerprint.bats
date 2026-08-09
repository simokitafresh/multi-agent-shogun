#!/usr/bin/env bats
# test_necessity: review approval must preserve a stable fingerprint when
# PyYAML parses unquoted date/datetime scalars into native objects.
# invariant: both fingerprint entry points serialize nested date/datetime
# values deterministically, while a report without a real commit identity
# remains fail-closed at review_report_fingerprint.
# regression_justification: the pre-fix json.dumps call raised TypeError for
# valid YAML timestamps and the caller misreported the result as missing
# commit_hash.

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export REAL_COMMIT_HASH
    REAL_COMMIT_HASH="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
}

setup() {
    export FAKE_ROOT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$FAKE_ROOT/queue/reports" "$FAKE_ROOT/queue/tasks"
    ln -s "$PROJECT_ROOT/scripts" "$FAKE_ROOT/scripts"
}

_make_report() {
    local name="$1" scalar_style="$2"
    local report="$FAKE_ROOT/queue/reports/${name}.yaml"
    if [ "$scalar_style" = unquoted ]; then
        cat > "$report" <<YAML
parent_cmd: cmd_datetime_fingerprint_test
status: completed
commit_hash: $REAL_COMMIT_HASH
timestamp: 2026-08-09T18:00:00
result:
  summary: datetime fixture
  details:
    generated_at: 2026-08-09T18:00:00
    run_date: 2026-08-09
    windows:
      - started_at: 2026-08-09T17:00:00
        date: 2026-08-08
binary_checks:
  AC1:
    - check: "fingerprint generated"
      result: "yes"
files_modified:
  - path: scripts/lib/review_approval.sh
YAML
    else
        cat > "$report" <<YAML
parent_cmd: cmd_datetime_fingerprint_test
status: completed
commit_hash: "$REAL_COMMIT_HASH"
timestamp: "2026-08-09T18:00:00"
result:
  summary: datetime fixture
  details:
    generated_at: "2026-08-09T18:00:00"
    run_date: "2026-08-09"
    windows:
      - started_at: "2026-08-09T17:00:00"
        date: "2026-08-08"
binary_checks:
  AC1:
    - check: "fingerprint generated"
      result: "yes"
files_modified:
  - path: scripts/lib/review_approval.sh
YAML
    fi
    echo "$report"
}

_hash_pair() {
    local report="$1"
    PROJECT_ROOT="$FAKE_ROOT" bash -c '
        source "$1/scripts/lib/review_approval.sh"
        review_report_fingerprint "$2"
        review_report_payload_hash "$2"
    ' _ "$FAKE_ROOT" "$report"
}

@test "both fingerprint entry points accept nested unquoted YAML date and datetime values" {
    local report
    report="$(_make_report unquoted unquoted)"

    run _hash_pair "$report"
    if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&3; fi
    [ "$status" -eq 0 ]
    mapfile -t hashes <<< "$output"
    [ "${#hashes[@]}" -eq 2 ]
    [[ "${hashes[0]}" =~ ^[0-9a-f]{64}$ ]]
    [[ "${hashes[1]}" =~ ^[0-9a-f]{64}$ ]]
}

@test "quoted date and datetime strings have the same stable fingerprint" {
    local unquoted quoted
    unquoted="$(_make_report equivalent_unquoted unquoted)"
    quoted="$(_make_report equivalent_quoted quoted)"

    local unquoted_pair quoted_pair
    unquoted_pair="$(_hash_pair "$unquoted")"
    quoted_pair="$(_hash_pair "$quoted")"
    [ "$unquoted_pair" = "$quoted_pair" ]
}

@test "missing commit_hash remains a fail-closed fingerprint BLOCK" {
    local report
    report="$(_make_report missing_commit unquoted)"
    sed -i '/^commit_hash:/d' "$report"

    run bash -c '
        source "$1/scripts/lib/review_approval.sh"
        review_report_fingerprint "$2"
    ' _ "$FAKE_ROOT" "$report"
    [ "$status" -ne 0 ]
}
