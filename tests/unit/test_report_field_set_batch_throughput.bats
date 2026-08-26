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
  export RFS_DISABLE_FAST_RECONCILER=1
  export RFS_TASK_FILE_PATH="$TMPDIR_CASE/task.yaml"
  cat >"$FAKE_INBOX" <<'SH'
#!/usr/bin/env bash
if [ -n "${RFS_PROCESS_ID_LOG:-}" ]; then
  ps -o sid=,pgid= -p $$ | tr -s ' ' | sed 's/^ //' >"$RFS_PROCESS_ID_LOG"
fi
printf '%s\n' "$*" >>"$RFS_EVENT_LOG"
SH
  cat >"$REPORT" <<'YAML'
worker_id: hanzo
parent_cmd: cmd_test
report_id: rpt-test
task_id: task-test
ac_version_read: abc
status: pending
commit_hash: '0000000000000000000000000000000000000000'
files_modified: [{path: queue/reports/test.yaml, change: fixture}]
lessons_useful: [{id: L625, useful: true, reason: covered}]
lesson_candidate: {found: false, no_lesson_reason: covered}
binary_checks:
  AC1: [{check: concrete check, result: ''}]
YAML
  cat >"$RFS_TASK_FILE_PATH" <<'YAML'
task:
  status: in_progress
YAML
}

teardown() { rm -rf "$TMPDIR_CASE"; }

@test "batch applies many fields with one atomic transition" {
  baseline_report="$TMPDIR_CASE/baseline.yaml"
  cp "$REPORT" "$baseline_report"
  baseline_start_ns="$(date +%s%N)"
  run bash -c 'printf "result.details.baseline: value\nbinary_checks.AC1[0].result: yes\n" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$baseline_report"
  baseline_ms="$(( ($(date +%s%N) - baseline_start_ns) / 1000000 ))"
  [ "$status" -eq 0 ]
  run bash -c 'for i in $(seq 1 49); do echo "result.details.f$i: value$i"; done; echo "binary_checks.AC1[0].result: yes"; done_marker=true' _
  payload="$output"
  start_ns="$(date +%s%N)"
  run bash -c 'printf "%s\n" "$3" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT" "$payload"
  elapsed_ms="$(( ($(date +%s%N) - start_ns) / 1000000 ))"
  [ "$status" -eq 0 ]
  incremental_ms="$((elapsed_ms - baseline_ms))"
  echo "BATCH_METRIC fields=50 baseline_ms=$baseline_ms elapsed_ms=$elapsed_ms incremental_ms=$incremental_ms atomic_publish=1" >&3
  # DrvFS/host contention changes the fixed bash+Python startup cost by more
  # than one second.  The throughput invariant is that adding 49 fields to one
  # atomic transaction costs less than one second over the measured two-field
  # baseline; an absolute wall threshold conflates startup with batch scaling.
  [ "$incremental_ms" -lt 1000 ]
  [[ "$output" == BATCH_OK*fields=50* ]]
  run python3 -c 'import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); assert len(d["result"]["details"])==49; assert d["verdict"]=="PASS"' "$REPORT"
  [ "$status" -eq 0 ]
}

@test "batch derives failed from a no check" {
  run bash -c 'echo "binary_checks.AC1[0].result: no" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT"
  [ "$status" -eq 0 ]
  run python3 -c 'import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); assert d["status"]=="failed" and d["verdict"]=="FAIL"' "$REPORT"
  [ "$status" -eq 0 ]
  run python3 -c 'import yaml,sys; assert yaml.safe_load(open(sys.argv[1]))["task"]["status"]=="failed"' "$RFS_TASK_FILE_PATH"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$RFS_EVENT_LOG")" -eq 1 ]
  grep -q 'karo hanzo未達報告.*report=report.yaml parent_cmd=cmd_test task_failed hanzo notify_karo' "$RFS_EVENT_LOG"
}

@test "terminal batch records completion time separately from authoring timestamp" {
  printf 'timestamp: 2026-08-24T00:00:00+09:00\n' >>"$REPORT"
  run bash -c 'printf "status: completed\\nbinary_checks.AC1[0].result: yes\\n" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT"
  [ "$status" -eq 0 ]
  run python3 - "$REPORT" <<'PY'
import datetime as dt
import sys
import yaml
data = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
completed = dt.datetime.fromisoformat(data['completed_at'].replace('Z', '+00:00'))
assert data['status'] == 'completed'
assert data['timestamp'].isoformat().startswith('2026-08-24T00:00:00')
assert completed.tzinfo is not None
PY
  [ "$status" -eq 0 ]
}

@test "batch rejects scalar structural fields atomically" {
  for field in files_modified lessons_useful binary_checks; do
    cp "$REPORT" "$TMPDIR_CASE/scalar.yaml"
    before="$(sha256sum "$TMPDIR_CASE/scalar.yaml" | awk '{print $1}')"
    run bash -c 'printf "%s: scalar\n" "$3" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$TMPDIR_CASE/scalar.yaml" "$field"
    [ "$status" -ne 0 ]
    [[ "$output" == *"scalar input is not auto-fixed"* ]]
    [ "$(sha256sum "$TMPDIR_CASE/scalar.yaml" | awk '{print $1}')" = "$before" ]
  done
}

@test "terminal readiness blocks incomplete completed report without mutation" {
  before="$(sha256sum "$REPORT" | awk '{print $1}')"
  run bash -c 'printf "status: completed\nbinary_checks.AC1[0].result: yes\ncommit_hash: bad\n" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT"
  [ "$status" -ne 0 ]
  [ "$(sha256sum "$REPORT" | awk '{print $1}')" = "$before" ]
}

@test "terminal readiness delegates operational no-code identity to shared contract" {
  tree="$(git -C "$ROOT" rev-parse HEAD^{tree})"
  cat >>"$REPORT" <<YAML
commit_contract: {required: true, reason: deploy default}
no_code_change_evidence: {tree_unchanged: true, before_tree: '$tree', after_tree: '$tree'}
YAML
  payload="$(cat <<'YAML'
status: completed
commit_hash: ''
binary_checks.AC1[0].result: yes
binary_checks.commit:
  - {check: no-commit operational report, result: "yes"}
YAML
)"
  run bash -c 'printf "%s\n" "$3" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT" "$payload"
  [ "$status" -eq 0 ]
  [[ "$output" == BATCH_OK* ]]
}

@test "terminal readiness keeps incomplete evidence and source paths fail closed" {
  tree="$(git -C "$ROOT" rev-parse HEAD^{tree})"
  for mutation in missing_evidence source_path missing_assertion; do
    cp "$REPORT" "$TMPDIR_CASE/$mutation.yaml"
    case "$mutation" in
      missing_evidence)
        extra="files_modified: [{path: queue/reports/test.yaml, change: fixture}]"
        ;;
      source_path)
        extra="files_modified: [{path: scripts/report_field_set.sh, change: forbidden}]
no_code_change_evidence: {tree_unchanged: true, before_tree: '$tree', after_tree: '$tree'}"
        ;;
      missing_assertion)
        extra="files_modified: [{path: queue/reports/test.yaml, change: fixture}]
no_code_change_evidence: {tree_unchanged: true, before_tree: '$tree', after_tree: '$tree'}"
        ;;
    esac
    printf '%s\n' "$extra" >>"$TMPDIR_CASE/$mutation.yaml"
    check="no-commit operational report"
    [ "$mutation" != missing_assertion ] || check="git commit completed"
    run bash -c 'printf "status: completed\ncommit_hash: \"\"\nbinary_checks.AC1[0].result: yes\nbinary_checks.commit:\n  - {check: \"%s\", result: \"yes\"}\n" "$3" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$TMPDIR_CASE/$mutation.yaml" "$check"
    [ "$status" -ne 0 ]
    [[ "$output" == *"shared no-code identity contract"* ]]
  done
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

@test "report gate serializes concurrent callers and quotes validated git pathspecs" {
  fp="$(sha256sum "$REPORT" | awk '{print $1}')"
  echo "$fp" > "$TMPDIR_CASE/fingerprints"
  outputs="$TMPDIR_CASE/concurrent.outputs"
  : >"$outputs"
  for _ in $(seq 1 8); do
    env GATE_FINGERPRINT_CACHE_FILE="$TMPDIR_CASE/fingerprints" \
      GATE_VALIDATED_FINGERPRINT="$fp" GATE_NO_LOG=1 \
      bash "$ROOT/scripts/gates/gate_report_format.sh" "$REPORT" >>"$outputs" &
  done
  wait
  [ "$(grep -c 'PASS (fingerprint reuse)' "$outputs")" -eq 8 ]
  [ -f "$REPORT.gate.lock" ]
  [ ! -e "$TMPDIR_CASE/index.lock" ]
  run python3 - "$ROOT/scripts/gates/gate_report_format.sh" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text(encoding="utf-8")
# cmd_karo_hotfix_singleflight_fail_misattribution_20260725 (provenance: 118dc5ff8): 30->60
assert 'flock -w "${GATE_SINGLEFLIGHT_TIMEOUT:-60}" 199' in text
assert "paths.append('__INVALID_REPORT_PATH__')" in text
assert 'git status --porcelain -- "${_CC_PATHS[@]}"' in text
assert "FAIL: malformed report path rejected before git status" in text
PY
  [ "$status" -eq 0 ]
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
  start_ns="$(date +%s%N)"
  parent_ids="$(ps -o sid=,pgid= -p $$ | tr -s ' ' | sed 's/^ //')"
  export RFS_PROCESS_ID_LOG="$TMPDIR_CASE/reconciler_ids"
  run env RFS_FAIL_AFTER_ATOMIC_REPLACE=1 RFS_DISABLE_FAST_RECONCILER=0 RFS_RECONCILE_DELAY=0.1 RFS_INBOX_WRITE_PATH="$FAKE_INBOX" RFS_EVENT_LOG="$RFS_EVENT_LOG" RFS_PROCESS_ID_LOG="$RFS_PROCESS_ID_LOG" bash -c 'printf "status: completed\nbinary_checks.AC1[0].result: yes\n" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT"
  [ "$status" -eq 86 ]
  run python3 -c 'import yaml,sys; assert yaml.safe_load(open(sys.argv[1]))["status"]=="completed"' "$REPORT"
  [ "$status" -eq 0 ]
  for _ in $(seq 1 40); do [ -s "$RFS_EVENT_LOG" ] && break; sleep 0.1; done
  [ "$(wc -l <"$RFS_EVENT_LOG")" -eq 1 ]
  [ -s "$RFS_PROCESS_ID_LOG" ]
  [ "$(cat "$RFS_PROCESS_ID_LOG")" != "$parent_ids" ]
  elapsed_ms="$(( ($(date +%s%N) - start_ns) / 1000000 ))"
  echo "FAILPOINT_REPAIR elapsed_ms=$elapsed_ms parent=1 child_contract=canonical" >&3
  [ "$elapsed_ms" -lt 5000 ]
}

# test_necessity: a detached 30-second reconciler must not retain the report or
# gate single-flight descriptors; a same-report revision and gate must finish
# below five seconds while exactly one delayed notification remains deliverable.
@test "delayed reconciler closes inherited single-flight descriptors before its thirty-second wait" {
  export RFS_DISABLE_FAST_RECONCILER=0
  fake_bin="$TMPDIR_CASE/fake-bin"
  delay_log="$TMPDIR_CASE/reconcile-delay"
  release_file="$TMPDIR_CASE/reconcile-release"
  mkdir "$fake_bin"
  cat >"$fake_bin/sleep" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" >"$RFS_DELAY_LOG"
while [ ! -e "$RFS_RELEASE_FILE" ]; do /bin/sleep 0.01; done
SH
  chmod +x "$fake_bin/sleep"
  run env PATH="$fake_bin:$PATH" RFS_DELAY_LOG="$delay_log" RFS_RELEASE_FILE="$release_file" \
    RFS_RECONCILE_DELAY=30 \
    RFS_INBOX_WRITE_PATH="$FAKE_INBOX" RFS_EVENT_LOG="$RFS_EVENT_LOG" \
    bash -c 'printf "status: completed\nbinary_checks.AC1[0].result: yes\n" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$RFS_EVENT_LOG")" -eq 1 ]
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -s "$delay_log" ] && break
    /bin/sleep 0.05
  done
  [ "$(cat "$delay_log")" = 30 ]

  gate_lock="$(realpath "$REPORT.gate.lock")"
  holder_count="$(
    for fd in /proc/[0-9]*/fd/*; do
      [ "$(readlink "$fd" 2>/dev/null || true)" = "$gate_lock" ] && printf '%s\n' "$fd"
    done | wc -l
  )"
  [ "$holder_count" -eq 0 ]

  sed -i 's/status: completed/status: revision_requested/' "$REPORT"
  : >"$RFS_EVENT_LOG"
  start_ns="$(date +%s%N)"
  run env RFS_DISABLE_FAST_RECONCILER=1 RFS_SINGLEFLIGHT_TIMEOUT=4 \
    bash -c 'printf "result.details: same-report revision\n" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$REPORT"
  [ "$status" -eq 0 ]
  update_success=1

  fp="$(sha256sum "$REPORT" | awk '{print $1}')"
  printf '%s\n' "$fp" >"$TMPDIR_CASE/fingerprints"
  run env GATE_SINGLEFLIGHT_TIMEOUT=4 GATE_FINGERPRINT_CACHE_FILE="$TMPDIR_CASE/fingerprints" \
    GATE_VALIDATED_FINGERPRINT="$fp" GATE_NO_LOG=1 \
    bash "$ROOT/scripts/gates/gate_report_format.sh" "$REPORT"
  [ "$status" -eq 0 ]
  gate_success=1
  wait_ms="$(( ($(date +%s%N) - start_ns) / 1000000 ))"
  [ "$wait_ms" -lt 5000 ]
  [ ! -s "$RFS_EVENT_LOG" ]

  touch "$release_file"
  for _ in $(seq 1 20); do
    [ -s "$RFS_EVENT_LOG" ] && break
    sleep 0.1
  done
  delayed_notifications="$(wc -l <"$RFS_EVENT_LOG")"
  [ "$delayed_notifications" -eq 1 ]
  echo "FD_LEAK_METRIC holders=$holder_count waiting_callers=1 wait_ms=$wait_ms timeout=0 update_success=$update_success gate_success=$gate_success delayed_notifications=$delayed_notifications fp=0 fn=0 fail=0 skip=0" >&3
}

@test "twenty isolated terminal publishes persist review-ready events under five seconds with no live inbox writes" {
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
  [ "$(grep -c '^karo hanzo報告完了' "$RFS_EVENT_LOG")" -eq 20 ]
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

# ─── cmd_karo_impl_report_publish_latency_20260725 ───
# publish経路の支配相は「公開済みバイト列の識別子を得るための再読込」だった
# (実測 avg 548ms = total 1043msの52.5%)。side-channelで消したが、識別子の
# 正しさと fallback は検査を1つも失わずに維持されねばならない。

publish_terminal() {
  run bash -c 'printf "status: completed\nbinary_checks.AC1[0].result: yes\n" | bash "$1/scripts/report_field_set.sh" --batch "$2"' _ "$ROOT" "$1"
}

@test "side-channel経由でもterminal識別子(worker/parent)が正しく束縛される" {
  : >"$RFS_EVENT_LOG"
  case_report="$TMPDIR_CASE/meta_fast.yaml"
  cp "$REPORT" "$case_report"
  publish_terminal "$case_report"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'hanzo報告完了' "$RFS_EVENT_LOG")" -eq 1 ]
  [ "$(grep -c 'parent_cmd=cmd_test' "$RFS_EVENT_LOG")" -eq 1 ]
  # side-channelの一時ファイルを残さない
  [ "$(find "$TMPDIR_CASE" -name 'meta_fast.yaml.meta.*' | wc -l)" -eq 0 ]
}

@test "side-channel不在でも従来の再読込fallbackで同じ識別子を束縛する" {
  : >"$RFS_EVENT_LOG"
  case_report="$TMPDIR_CASE/meta_fallback.yaml"
  cp "$REPORT" "$case_report"
  RFS_BATCH_META_DISABLE=1 publish_terminal "$case_report"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'hanzo報告完了' "$RFS_EVENT_LOG")" -eq 1 ]
  [ "$(grep -c 'parent_cmd=cmd_test' "$RFS_EVENT_LOG")" -eq 1 ]
}

# test_necessity: atomic publishの親時間を維持したまま、parse/validation/serialize・file fsync・replace syscallの子区分が既存台帳へ各1行以上記録される不変量を守る。
@test "publish経路の相別時間が既存台帳defense_overhead.jsonlへ記録される" {
  export DEFENSE_OVERHEAD_LEDGER="$TMPDIR_CASE/defense_overhead.jsonl"
  : >"$DEFENSE_OVERHEAD_LEDGER"
  case_report="$TMPDIR_CASE/telemetry.yaml"
  cp "$REPORT" "$case_report"
  publish_terminal "$case_report"
  [ "$status" -eq 0 ]
  expected_generation="$(
    PROJECT_ROOT="$ROOT" bash -c \
      'source "$1"; review_report_fingerprint "$2"' _ \
      "$ROOT/scripts/lib/review_approval.sh" "$case_report"
  )"
  [[ "$expected_generation" =~ ^[0-9a-f]{64}$ ]]
  for _ in $(seq 1 40); do
    phase_count="$(grep -Ec '"check_id":"(publish_total|terminal_meta|atomic_replace|atomic_parse_validate_serialize|atomic_flush_file_fsync|atomic_replace_syscall)"' "$DEFENSE_OVERHEAD_LEDGER" || true)"
    [ "$phase_count" -ge 6 ] && break
    sleep 0.5
  done
  grep -q '"source":"report_publish"' "$DEFENSE_OVERHEAD_LEDGER"
  grep -q '"check_id":"publish_total"' "$DEFENSE_OVERHEAD_LEDGER"
  grep -q '"check_id":"terminal_meta"' "$DEFENSE_OVERHEAD_LEDGER"
  grep -q '"check_id":"atomic_replace"' "$DEFENSE_OVERHEAD_LEDGER"
  grep -q '"check_id":"atomic_parse_validate_serialize"' "$DEFENSE_OVERHEAD_LEDGER"
  grep -q '"check_id":"atomic_flush_file_fsync"' "$DEFENSE_OVERHEAD_LEDGER"
  grep -q '"check_id":"atomic_replace_syscall"' "$DEFENSE_OVERHEAD_LEDGER"
  python3 - "$DEFENSE_OVERHEAD_LEDGER" "$expected_generation" <<'PY'
import json, sys
rows=[json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
publish=[row for row in rows if row["source"] == "report_publish"]
assert publish
assert all(row["cmd_id"] == "cmd_test" for row in publish)
assert all(row["generation"] == sys.argv[2] for row in publish)
PY
  # 新台帳を作らない: 書込み先は既存ledgerのみ
  [ "$(find "$TMPDIR_CASE" -name '*.jsonl' | wc -l)" -eq 1 ]
}

# test_necessity: commit_hash telemetryが旧schema fieldを維持しつつreport/task flow識別子を持ち、同一flow重複だけを検知できる不変量を守る。
@test "commit_hash telemetryはreport/task flow識別子で重複を分離する" {
  export DEFENSE_OVERHEAD_LEDGER="$TMPDIR_CASE/commit_hash_telemetry.jsonl"
  : >"$DEFENSE_OVERHEAD_LEDGER"
  first="$TMPDIR_CASE/flow_a.yaml"
  second="$TMPDIR_CASE/flow_b.yaml"
  cp "$REPORT" "$first"
  cp "$REPORT" "$second"
  sed -i 's/^report_id: .*/report_id: rpt-flow-a/; s/^task_id: .*/task_id: task-flow-a/' "$first"
  sed -i 's/^report_id: .*/report_id: rpt-flow-b/; s/^task_id: .*/task_id: task-flow-b/' "$second"

  run bash "$ROOT/scripts/report_field_set.sh" "$first" commit_hash 0000000000000000000000000000000000000000
  [ "$status" -eq 0 ]
  run bash "$ROOT/scripts/report_field_set.sh" "$first" commit_hash 0000000000000000000000000000000000000000
  [ "$status" -eq 0 ]
  run bash "$ROOT/scripts/report_field_set.sh" "$second" commit_hash 0000000000000000000000000000000000000000
  [ "$status" -eq 0 ]
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(grep -c '"check_id":"commit_hash"' "$DEFENSE_OVERHEAD_LEDGER")" -eq 3 ] && break
    sleep 0.3
  done

  python3 - "$DEFENSE_OVERHEAD_LEDGER" <<'PY'
import collections, json, sys
rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
assert len(rows) == 3
assert all({"timestamp", "source", "check_id", "wall_ms", "verdict", "event_id"} <= row.keys() for row in rows)
counts = collections.Counter((row["report_id"], row["task_id"]) for row in rows)
assert counts[("rpt-flow-a", "task-flow-a")] == 2
assert counts[("rpt-flow-b", "task-flow-b")] == 1
assert sum(count - 1 for count in counts.values()) == 1
assert len({row["event_id"] for row in rows}) == 3
PY
}
