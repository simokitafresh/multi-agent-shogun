#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  REPORT="$BATS_TEST_TMPDIR/report.yaml"
  cat > "$REPORT" <<'YAML'
worker_id: kagemaru
status: pending
result: {summary: done}
purpose_validation: {fit: true}
files_modified: [{path: scripts/x.sh, change: changed}]
lesson_candidate: {found: false, no_lesson_reason: known}
lessons_useful: [{id: L1, useful: false, reason: 未参照}]
memory_references: [{id: M1, reason: ''}]
binary_checks:
  AC1: [{check: concrete acceptance check, result: yes}]
  commit: [{check: scope commit complete, result: yes}]
verdict: PASS
commit_hash: ''
YAML
}

# test_necessity: a report outside queue/reports must not inherit a live worker task contract.
@test "commit_hash does not terminalize report while lesson and memory feedback remain unwritten" {
  [[ "$REPORT" != */queue/reports/* ]]
  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" commit_hash 0123456789abcdef0123456789abcdef01234567
  [ "$status" -eq 0 ]
  run python3 - "$REPORT" <<'PY'
import sys, yaml
d=yaml.safe_load(open(sys.argv[1]))
assert d['status'] == 'pending', d['status']
PY
  [ "$status" -eq 0 ]

  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" lessons_useful.0.reason "具体的に参照した"
  [ "$status" -eq 0 ]
  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" memory_references.0.reason "仕様探索に使用"
  [ "$status" -eq 0 ]
  run bash "$ROOT/scripts/report_field_set.sh" "$REPORT" status completed
  [ "$status" -eq 0 ]
}
