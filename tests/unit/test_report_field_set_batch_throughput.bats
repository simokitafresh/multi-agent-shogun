#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPDIR_CASE="$(mktemp -d)"
  REPORT="$TMPDIR_CASE/report.yaml"
  cat >"$REPORT" <<'YAML'
worker_id: hanzo
parent_cmd: cmd_test
ac_version_read: abc
status: pending
commit_hash: no-code-change
files_modified: [queue/reports/test.yaml]
lessons_useful: [{id: L625, useful: true, reason: covered}]
lesson_candidate: {found: false, no_lesson_reason: covered}
binary_checks:
  AC1: [{check: concrete check, result: ''}]
YAML
}

teardown() { rm -rf "$TMPDIR_CASE"; }

@test "batch applies many fields with one atomic transition" {
  run bash -c 'for i in $(seq 1 40); do echo "result.details.f$i: value$i"; done; echo "binary_checks.AC1[0].result: yes"; done_marker=true' _
  payload="$output"
  run bash -c 'printf "%s\n" "$3" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT" "$payload"
  [ "$status" -eq 0 ]
  [[ "$output" == BATCH_OK*fields=41* ]]
  run python3 -c 'import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); assert len(d["result"]["details"])==40; assert d["verdict"]=="PASS"' "$REPORT"
  [ "$status" -eq 0 ]
}

@test "batch derives failed from a no check" {
  run bash -c 'echo "binary_checks.AC1[0].result: no" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT"
  [ "$status" -eq 0 ]
  run python3 -c 'import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); assert d["status"]=="failed" and d["verdict"]=="FAIL"' "$REPORT"
  [ "$status" -eq 0 ]
}

@test "terminal readiness blocks incomplete completed report without mutation" {
  before="$(sha256sum "$REPORT" | awk '{print $1}')"
  run bash -c 'printf "status: completed\nbinary_checks.AC1[0].result: yes\ncommit_hash: bad\n" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT"
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$REPORT" | awk '{print $1}')" = "$before" ]
}

@test "gate reuses exact validated fingerprint and rejects stale fingerprint" {
  fp="$(sha256sum "$REPORT" | awk '{print $1}')"
  echo "$fp" > "$TMPDIR_CASE/fingerprints"
  run env GATE_FINGERPRINT_CACHE_FILE="$TMPDIR_CASE/fingerprints" GATE_VALIDATED_FINGERPRINT="$fp" bash "$ROOT/scripts/gates/gate_report_format.sh" "$REPORT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fingerprint reuse"* ]]
  echo '# changed' >>"$REPORT"
  run env GATE_FINGERPRINT_CACHE_FILE="$TMPDIR_CASE/fingerprints" GATE_VALIDATED_FINGERPRINT="$fp" GATE_NO_LOG=1 bash "$ROOT/scripts/gates/gate_report_format.sh" "$REPORT"
  [[ "$output" != *"fingerprint reuse"* ]]
}
