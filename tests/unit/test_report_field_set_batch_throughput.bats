#!/usr/bin/env bats
# test_necessity: terminal batch publication must synchronously emit one
# fingerprint-deduplicated lifecycle parent whose child review is repairable
# from the persisted completed report after an interrupted publisher.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPDIR_CASE="$(mktemp -d)"
  REPORT="$TMPDIR_CASE/report.yaml"
  FAKE_INBOX="$TMPDIR_CASE/inbox_write.sh"
  export RFS_INBOX_WRITE_PATH="$FAKE_INBOX"
  export RFS_EVENT_LOG="$TMPDIR_CASE/events"
  cat >"$FAKE_INBOX" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RFS_EVENT_LOG"
SH
  cat >"$REPORT" <<'YAML'
worker_id: hanzo
parent_cmd: cmd_test
ac_version_read: abc
status: pending
commit_hash: '0000000000000000000000000000000000000000'
files_modified: [queue/reports/test.yaml]
lessons_useful: [{id: L625, useful: true, reason: covered}]
lesson_candidate: {found: false, no_lesson_reason: covered}
binary_checks:
  AC1: [{check: concrete check, result: ''}]
YAML
}

teardown() { rm -rf "$TMPDIR_CASE"; }

@test "batch applies many fields with one atomic transition" {
  run bash -c 'for i in $(seq 1 49); do echo "result.details.f$i: value$i"; done; echo "binary_checks.AC1[0].result: yes"; done_marker=true' _
  payload="$output"
  start_ns="$(date +%s%N)"
  run bash -c 'printf "%s\n" "$3" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT" "$payload"
  elapsed_ms="$(( ($(date +%s%N) - start_ns) / 1000000 ))"
  [ "$status" -eq 0 ]
  echo "BATCH_METRIC fields=50 elapsed_ms=$elapsed_ms atomic_publish=1" >&3
  [ "$elapsed_ms" -lt 1000 ]
  [[ "$output" == BATCH_OK*fields=50* ]]
  run python3 -c 'import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); assert len(d["result"]["details"])==49; assert d["verdict"]=="PASS"' "$REPORT"
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

@test "completed revision batch unlocks and republishes terminal once" {
  sed -i "s/status: pending/status: completed/; s/result: ''/result: yes/; \$a verdict: PASS" "$REPORT"
  before_inode="$(stat -c %i "$REPORT")"
  run bash -c 'printf "status: revision_requested\nresult.summary: revised once\nbinary_checks.AC1[0].result: yes\n" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT"
  [ "$status" -eq 0 ]
  [[ "$output" == BATCH_OK*fields=3* ]]
  [ "$(stat -c %i "$REPORT")" != "$before_inode" ]
  run python3 -c 'import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); assert d["status"]=="completed"; assert d["verdict"]=="PASS"; assert d["result"]["summary"]=="revised once"' "$REPORT"
  [ "$status" -eq 0 ]
}

@test "completed batch without explicit revision remains immutable" {
  sed -i "s/status: pending/status: completed/; s/result: ''/result: yes/; \$a verdict: PASS" "$REPORT"
  before="$(sha256sum "$REPORT" | awk '{print $1}')"
  run bash -c 'printf "result.summary: forbidden\nbinary_checks.AC1[0].result: yes\n" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT"
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$REPORT" | awk '{print $1}')" = "$before" ]
}

@test "failed completed revision batch rolls back every field" {
  sed -i "s/status: pending/status: completed/; s/result: ''/result: yes/; \$a verdict: PASS" "$REPORT"
  before="$(sha256sum "$REPORT" | awk '{print $1}')"
  run bash -c 'printf "status: revision_requested\nresult.summary: must rollback\nbinary_checks.AC1[0].result: maybe\n" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT"
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

@test "report-write skill makes one batch transaction the canonical completion path" {
  run python3 - "$ROOT/skills/report-write/SKILL.md" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text(encoding="utf-8")
step2 = text.split("### Step 2:", 1)[1].split("### Step 3:", 1)[0]
assert 'report_field_set.sh --batch "$REPORT"' in step2
assert 'commit_hash:' in step2 and 'status: completed' in step2
assert step2.count('bash scripts/report_field_set.sh "$REPORT"') == 0
assert "revision_requested" in step2
PY
  [ "$status" -eq 0 ]
}

@test "terminal batch publishes canonical completion synchronously and nonterminal writes publish nothing" {
  run env RFS_INBOX_WRITE_PATH="$FAKE_INBOX" RFS_EVENT_LOG="$RFS_EVENT_LOG" bash -c 'printf "status: completed\nbinary_checks.AC1[0].result: yes\n" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$RFS_EVENT_LOG")" -eq 1 ]
  grep -q 'karo hanzo報告完了.*report=report.yaml parent_cmd=cmd_test report_received hanzo notify_karo' "$RFS_EVENT_LOG"

  sed -i 's/status: completed/status: revision_requested/' "$REPORT"
  : >"$RFS_EVENT_LOG"
  run env RFS_INBOX_WRITE_PATH="$FAKE_INBOX" RFS_EVENT_LOG="$RFS_EVENT_LOG" bash -c 'printf "result.details: nonterminal\n" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT"
  [ "$status" -eq 0 ]
  [ ! -s "$RFS_EVENT_LOG" ]
}

@test "persisted terminal report survives publish failpoint as durable outbox" {
  run env RFS_FAIL_AFTER_ATOMIC_REPLACE=1 RFS_INBOX_WRITE_PATH="$FAKE_INBOX" RFS_EVENT_LOG="$RFS_EVENT_LOG" bash -c 'printf "status: completed\nbinary_checks.AC1[0].result: yes\n" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT"
  [ "$status" -eq 86 ]
  [ ! -e "$RFS_EVENT_LOG" ]
  run python3 -c 'import yaml,sys; assert yaml.safe_load(open(sys.argv[1]))["status"]=="completed"' "$REPORT"
  [ "$status" -eq 0 ]
}

@test "twenty isolated terminal publishes persist review-ready events under five seconds with no live inbox writes" {
  live_before="$(sha256sum "$ROOT/queue/inbox/karo.yaml" | awk '{print $1}')"
  : >"$RFS_EVENT_LOG"
  durations="$TMPDIR_CASE/durations"
  for i in $(seq 1 20); do
    case_report="$TMPDIR_CASE/report_$i.yaml"
    cp "$REPORT" "$case_report"
    start_ns="$(date +%s%N)"
    run bash -c 'printf "status: completed\nbinary_checks.AC1[0].result: yes\n" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$case_report"
    [ "$status" -eq 0 ]
    end_ns="$(date +%s%N)"
    echo $((end_ns-start_ns)) >>"$durations"
    [ "$(stat -c %Y "$case_report")" -le "$(date +%s)" ]
  done
  [ "$(wc -l <"$RFS_EVENT_LOG")" -eq 20 ]
  [ "$(sha256sum "$ROOT/queue/inbox/karo.yaml" | awk '{print $1}')" = "$live_before" ]
  run python3 - "$durations" <<'PY'
import sys
xs=sorted(int(x)/1e9 for x in open(sys.argv[1]))
p50=xs[9]; p95=xs[18]
print(f"PUBLISH_METRIC n=20 p50={p50:.3f}s p95={p95:.3f}s fp=0 fn=0 skip=0")
assert p50 < 5 and p95 < 5
PY
  [ "$status" -eq 0 ]
  echo "$output" >&3
}
