#!/usr/bin/env bats
# test_necessity: Nested aggregate runner fails closed while focused file mode remains allowed; violation is BLOCK.

setup() {
  # This file deliberately launches isolated aggregate runner fixtures.  They
  # are new checkpoint roots, not accidental children of the outer CI runner.
  unset RUN_TESTS_ACTIVE
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPROOT="$(mktemp -d)"
  mkdir -p "$TMPROOT/scripts" "$TMPROOT/tests/unit" "$TMPROOT/bin" "$TMPROOT/logs"
  cp "$ROOT/scripts/run_tests.sh" "$ROOT/scripts/test_timing_ledger_write.sh" \
    "$ROOT/scripts/test_suite_timing_ledger_write.sh" "$ROOT/scripts/universal_shard.py" \
    "$ROOT/scripts/universal_shard_adapters.py" "$ROOT/scripts/run_with_receipt.sh" \
    "$ROOT/scripts/heavy_job_admission.sh" "$TMPROOT/scripts/"
  printf '@test "sample" { true; }\n' >"$TMPROOT/tests/unit/sample.bats"
  printf '@test "root sample" { true; }\n' >"$TMPROOT/tests/root_sample.bats"
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '1..1\nok 1 sample in 5ms\n'
SH
  chmod +x "$TMPROOT/bin/bats"
  git -C "$TMPROOT" init -q
  git -C "$TMPROOT" config user.email test@example.invalid
  git -C "$TMPROOT" config user.name test
  git -C "$TMPROOT" add scripts tests
  git -C "$TMPROOT" commit -qm init
}

@test "nested aggregate runner fails closed while file mode isolates every selected file" {
  run env RUN_TESTS_ACTIVE=1 SHOGUN_HEAVY_JOB_LOCK_HELD=1 REPO_ROOT="$TMPROOT" \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner all
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK: nested aggregate run_tests invocation"* ]]

  export BATS_ARGS_LOG="$TMPROOT/file-mode.args"
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BATS_ARGS_LOG"
printf '1..1\nok 1 sample in 5ms\n'
SH
  chmod +x "$TMPROOT/bin/bats"
  run env RUN_TESTS_ACTIVE=1 SHOGUN_HEAVY_JOB_LOCK_HELD=1 REPO_ROOT="$TMPROOT" PATH="$TMPROOT/bin:$PATH" \
    BATS_ARGS_LOG="$BATS_ARGS_LOG" BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner file \
      "$TMPROOT/tests/unit/sample.bats" "$TMPROOT/tests/root_sample.bats"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$BATS_ARGS_LOG")" -eq 2 ]
  [ "$(grep -Fc "$TMPROOT/tests/unit/sample.bats" "$BATS_ARGS_LOG")" -eq 1 ]
  [ "$(grep -Fc "$TMPROOT/tests/root_sample.bats" "$BATS_ARGS_LOG")" -eq 1 ]

  rm -f "$BATS_ARGS_LOG"
  run env RUN_TESTS_ACTIVE=1 SHOGUN_HEAVY_JOB_LOCK_HELD=1 REPO_ROOT="$TMPROOT" PATH="$TMPROOT/bin:$PATH" \
    BATS_ARGS_LOG="$BATS_ARGS_LOG" BATS_CACHE=0 BATS_INNER_JOBS=1 \
    RUN_TESTS_RECEIPT_DIR="$TMPROOT/logs/test_receipts" \
    bash "$TMPROOT/scripts/run_tests.sh" file "$TMPROOT/tests/unit/sample.bats"
  [ "$status" -eq 0 ]
  receipt="$(find "$TMPROOT/logs/test_receipts" -name '*.json' -type f | head -1)"
  [ -n "$receipt" ]
  [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["test_paths"][0])' "$receipt")" = "tests/unit/sample.bats" ]
}

teardown() { rm -rf "$TMPROOT"; }

# test_necessity: External Jest output must publish its real terminal count and a selected external scope may never pass as 0/0.
@test "external Jest receipt adopts summary counts and fails closed when summary is absent" {
  receipt="$TMPROOT/logs/external.json"
  artifact="$TMPROOT/logs/external.output"
  paths="$TMPROOT/logs/external.paths"
  head="$(git -C "$TMPROOT" rev-parse HEAD)"
  printf 'external-project:%s\n' "$TMPROOT" >"$paths"
  printf 'Test Suites: 21 passed, 21 total\nTests:       126 passed, 126 total\nSnapshots:   0 total\n' >"$artifact"
  python3 - "$receipt" "$artifact" <<'PY'
import hashlib, json, sys
path, artifact = sys.argv[1:]
raw = open(artifact, 'rb').read()
json.dump({
    "version": 2, "complete": True, "result": "PASS", "rc": 0,
    "duration_ms": 1, "output_sha256": hashlib.sha256(raw).hexdigest(),
    "declared_test_count": 0, "observed_test_count": 0, "skip_count": 0,
    "artifact": artifact, "signal": None, "command": ["jest"],
}, open(path, "w"))
PY

  run env REPO_ROOT="$TMPROOT" bash -c '
    source "$1/scripts/run_tests.sh"
    publish_run_tests_metadata "$2" "$3" "$4" selector
    verify_run_tests_receipt "$2"
  ' _ "$TMPROOT" "$receipt" "$head" "$paths"
  [ "$status" -eq 0 ]
  [ "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["observed_test_count"])' "$receipt")" -eq 126 ]
  [ "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["declared_test_count"])' "$receipt")" -eq 126 ]

  printf 'runner completed without a parseable summary\n' >"$artifact"
  python3 - "$receipt" "$artifact" <<'PY'
import hashlib, json, sys
path, artifact = sys.argv[1:]
raw = open(artifact, 'rb').read()
json.dump({
    "version": 2, "complete": True, "result": "PASS", "rc": 0,
    "duration_ms": 1, "output_sha256": hashlib.sha256(raw).hexdigest(),
    "declared_test_count": 0, "observed_test_count": 0, "skip_count": 0,
    "artifact": artifact, "signal": None, "command": ["external-runner"],
}, open(path, "w"))
PY
  run env REPO_ROOT="$TMPROOT" bash -c '
    source "$1/scripts/run_tests.sh"
    publish_run_tests_metadata "$2" "$3" "$4" selector
    verify_run_tests_receipt "$2"
  ' _ "$TMPROOT" "$receipt" "$head" "$paths"
  [ "$status" -ne 0 ]
  [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["rc"])' "$receipt")" -eq 2 ]
}

# test_necessity: explicit all mode must include both unit and root-level bats files; omission silently weakens the full checkpoint.
@test "explicit all mode includes both unit and root-level bats files" {
  export BATS_ARGS_LOG="$TMPROOT/bats.args"
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$BATS_ARGS_LOG"
printf '1..1\nok 1 sample\n'
SH
  chmod +x "$TMPROOT/bin/bats"

  run env -u BATS_CACHE PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" BATS_ARGS_LOG="$BATS_ARGS_LOG" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" all

  [ "$status" -eq 0 ]
  grep -Fxq "$TMPROOT/tests/unit/sample.bats" "$BATS_ARGS_LOG"
  grep -Fxq "$TMPROOT/tests/root_sample.bats" "$BATS_ARGS_LOG"
  [ "$(wc -l <"$BATS_ARGS_LOG")" -eq 2 ]
}

@test "default all mode executes every file without pass cache reuse" {
  mkdir -p "$TMPROOT/.cache/bats"
  export BATS_ARGS_LOG="$TMPROOT/bats.args"
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$BATS_ARGS_LOG"
printf '1..1\nok 1 sample\n'
SH
  chmod +x "$TMPROOT/bin/bats"

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" BATS_ARGS_LOG="$BATS_ARGS_LOG" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_INNER_JOBS=1 bash "$TMPROOT/scripts/run_tests.sh" all

  [ "$status" -eq 0 ]
  [ "$(wc -l <"$BATS_ARGS_LOG")" -eq 2 ]
  [ "$(find "$TMPROOT/.cache/bats" -type f | wc -l)" -eq 0 ]
}

@test "non-all modes retain pass cache default" {
  run env -u BATS_CACHE REPO_ROOT="$TMPROOT" bash -c '
    source "$1/scripts/run_tests.sh"
    [ "$BATS_CACHE" -eq 1 ] && [ "$BATS_CACHE_EXPLICIT" -eq 0 ]
  ' _ "$TMPROOT"
  [ "$status" -eq 0 ]
}

_source_fp() {
  git -C "$TMPROOT" ls-files --format='%(objectname)' -- scripts lib tests/helpers ':!scripts/run_tests.sh' \
    | sha256sum | awk '{print $1}'
}

_write_lpt_ledger() {
  local fp="$1" commit="$2"
  shift 2
  printf 'run_id\trepo\tcommit_sha\tsuite_root\trunner\ttest_file\ttest_id_count\twall_sec\tstatus\tskip_count\tcache_hit\tsource_fingerprint\tmeasured_at\tresource_tags\n' >"$TMPROOT/logs/ledger.tsv"
  while [ "$#" -gt 0 ]; do
    printf 'r1\trepo\t%s\tunit\tbats\t%s\t1\t%s\tpass\t0\t0\t%s\t2026-07-14T00:00:00Z\tmode=unit;jobs=8\n' "$commit" "$1" "$2" "$fp" >>"$TMPROOT/logs/ledger.tsv"
    shift 2
  done
}

@test "unit normal path publishes completed non-cache timing row" {
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    BATS_CACHE=0 BATS_SPLIT_FILES=1 TEST_TIMING_LEDGER="$TMPROOT/logs/ledger.tsv" \
    bash "$TMPROOT/scripts/run_tests.sh" unit
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$TMPROOT/logs/ledger.tsv")" -eq 2 ]
  awk -F'\t' 'NR==2 {exit !($4=="unit" && $9=="pass" && $11==0 && NF==14)}' "$TMPROOT/logs/ledger.tsv"
  awk -F'\t' 'NR==1 {exit !($5=="suite_wall_sec" && $6=="sum_file_sec" && NF==10)} NR==2 {exit !(NF==10 && $5>=0 && $6>=0)}' "$TMPROOT/logs/test_suite_timing_ledger.tsv"
}

@test "file partial path does not update suite ledger" {
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    TEST_TIMING_LEDGER="$TMPROOT/logs/ledger.tsv" bash "$TMPROOT/scripts/run_tests.sh" file "$TMPROOT/tests/unit/sample.bats"
  [ "$status" -eq 0 ]
  [ ! -e "$TMPROOT/logs/ledger.tsv" ]
}

@test "split-file runner serializes each fixture while retaining the aggregate jobs 8 budget" {
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$BATS_ARGS_LOG"
printf '1..1\nok 1 sample\n'
SH
  chmod +x "$TMPROOT/bin/bats"
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" BATS_ARGS_LOG="$TMPROOT/bats.args" \
    BATS_CACHE=0 BATS_INNER_JOBS=1 BATS_MAX_TEST_JOBS=8 bash -c '
      source "$1/scripts/run_tests.sh"
      run_bats_files_parallel "$1/tests/unit/sample.bats"
  ' _ "$TMPROOT"
  [ "$status" -eq 0 ]
  grep -Fq -- '--jobs 1' "$TMPROOT/bats.args"
  run env REPO_ROOT="$TMPROOT" BATS_INNER_JOBS=1 BATS_MAX_TEST_JOBS=8 bash -c 'source "$1/scripts/run_tests.sh"; [ "$INNER_JOBS" -eq 1 ] && [ "$MAX_TEST_JOBS" -eq 8 ]' _ "$TMPROOT"
  [ "$status" -eq 0 ]
}

@test "timing-regressed shared-resource fixtures receive the full aggregate weight" {
  for name in test_hook_dispatchers test_statusline test_sqlite3_cli_removal test_small_workflow_consolidated test_skill_recommend_metrics; do
    printf '@test "sample" { true; }\n' >"$TMPROOT/tests/unit/$name.bats"
  done
  export BATS_SCHEDULER_TRACE="$TMPROOT/schedule.tsv"

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" BATS_CACHE=0 \
    BATS_INNER_JOBS=1 BATS_MAX_TEST_JOBS=8 BATS_SCHEDULER_TRACE="$BATS_SCHEDULER_TRACE" bash -c '
      source "$1/scripts/run_tests.sh"
      run_bats_files_parallel "$1/tests/unit/test_hook_dispatchers.bats" \
        "$1/tests/unit/test_statusline.bats" \
        "$1/tests/unit/test_sqlite3_cli_removal.bats" \
        "$1/tests/unit/test_small_workflow_consolidated.bats" \
        "$1/tests/unit/test_skill_recommend_metrics.bats"
    ' _ "$TMPROOT"

  [ "$status" -eq 0 ]
  [ "$(wc -l <"$BATS_SCHEDULER_TRACE")" -eq 5 ]
  [ "$(awk -F '\t' '$2 == 8 {count++} END {print count+0}' "$BATS_SCHEDULER_TRACE")" -eq 5 ]
  [ "$(awk -F '\t' '$3 == 0 {count++} END {print count+0}' "$BATS_SCHEDULER_TRACE")" -eq 5 ]
}

@test "campaign shard fixture exclusively owns scheduler budget" {
  printf '@test "sample" { true; }\n' >"$TMPROOT/tests/unit/test_campaign_lane_shard_item.bats"
  export BATS_SCHEDULER_TRACE="$TMPROOT/schedule.tsv"

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" BATS_CACHE=0 \
    BATS_INNER_JOBS=1 BATS_MAX_TEST_JOBS=8 BATS_SCHEDULER_TRACE="$BATS_SCHEDULER_TRACE" bash -c '
      source "$1/scripts/run_tests.sh"
      run_bats_files_parallel "$1/tests/unit/sample.bats" \
        "$1/tests/unit/test_campaign_lane_shard_item.bats"
  ' _ "$TMPROOT"

  [ "$status" -eq 0 ]
  awk -F '\t' '$1=="test_campaign_lane_shard_item.bats" {found=1; if ($2!=8 || $3!=0) bad=1} END {exit !(found && !bad)}' "$BATS_SCHEDULER_TRACE"
}

@test "default aggregate budget follows host CPUs and remains capped at eight" {
  cat >"$TMPROOT/bin/nproc" <<'SH'
#!/usr/bin/env bash
printf '2\n'
SH
  chmod +x "$TMPROOT/bin/nproc"
  run env -u BATS_MAX_TEST_JOBS PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" bash -c '
    source "$1/scripts/run_tests.sh"
    [ "$MAX_TEST_JOBS" -eq 2 ]
  ' _ "$TMPROOT"
  [ "$status" -eq 0 ]

  cat >"$TMPROOT/bin/nproc" <<'SH'
#!/usr/bin/env bash
printf '64\n'
SH
  chmod +x "$TMPROOT/bin/nproc"
  run env -u BATS_MAX_TEST_JOBS PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" bash -c '
    source "$1/scripts/run_tests.sh"
    [ "$MAX_TEST_JOBS" -eq 8 ]
  ' _ "$TMPROOT"
  [ "$status" -eq 0 ]
}

@test "CI pins file-internal jobs to one and leaves aggregate parallelism to run_tests" {
  workflow="$ROOT/.github/workflows/test.yml"

  grep -Fq 'BATS_INNER_JOBS=1 \' "$workflow"
  grep -Fq 'BATS_FILE_TIMEOUT_SECONDS=300 \' "$workflow"
  grep -Fq 'timeout-minutes: 5' "$workflow"
  grep -Fq 'group: test-${{ github.workflow }}-${{ github.ref }}' "$workflow"
  grep -Fq 'cancel-in-progress: true' "$workflow"
  ! grep -Fq 'BATS_INNER_JOBS=8 \' "$workflow"
  grep -Fq 'bash scripts/run_tests.sh push' "$workflow"
}

@test "CI failure evidence is bounded and receipts are always uploaded" {
  workflow="$ROOT/.github/workflows/test.yml"

  grep -Fq -- '- name: Report bounded test failure evidence' "$workflow"
  grep -Fq 'if: failure()' "$workflow"
  grep -Fq 'tail -n 120 "$artifact"' "$workflow"
  grep -Fq '"version", "complete", "result", "rc", "duration_ms"' "$workflow"
  ! grep -Fq 'cat "$artifact"' "$workflow"
  grep -Fq -- '- name: Upload test receipts' "$workflow"
  grep -Fq 'if: always()' "$workflow"
  grep -Fq 'logs/test_receipts/*.json' "$workflow"
  grep -Fq 'logs/test_receipts/*.output' "$workflow"
  grep -Fq 'if-no-files-found: error' "$workflow"
  grep -Fq -- '- name: Verify zero SKIPs (SKIP=FAIL policy)' "$workflow"
  grep -Fq 'path: test-results/*.tap' "$workflow"
}

@test "CI failure evidence reports the latest receipt and fails closed when absent" {
  workflow="$ROOT/.github/workflows/test.yml"
  python3 - "$workflow" "$TMPROOT/diagnose.sh" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
steps = data["jobs"]["unit-tests"]["steps"]
script = next(step["run"] for step in steps if step.get("name") == "Report bounded test failure evidence")
open(sys.argv[2], "w", encoding="utf-8").write(script)
PY
  mkdir -p "$TMPROOT/logs/test_receipts"
  printf 'old\n' >"$TMPROOT/logs/test_receipts/old.output"
  printf '%s\n' {1..121} >"$TMPROOT/logs/test_receipts/latest.output"
  python3 - "$TMPROOT/logs/test_receipts/latest.json" "$TMPROOT/logs/test_receipts/latest.output" <<'PY'
import json, sys
json.dump({"version": 1, "complete": False, "result": "FAIL", "rc": 1,
           "duration_ms": 7, "declared_test_count": 2, "observed_test_count": 1,
           "skip_count": 0, "artifact": sys.argv[2], "command": ["secret-command"]},
          open(sys.argv[1], "w", encoding="utf-8"))
PY

  run bash -c 'cd "$1" && bash diagnose.sh' _ "$TMPROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *'TEST_RECEIPT_SUMMARY'* ]]
  [[ "$output" == *$'\n2\n'* ]]
  [[ "$output" != *$'\n1\n'* ]]
  [[ "$output" != *'secret-command'* ]]

  rm "$TMPROOT/logs/test_receipts/latest.json" "$TMPROOT/logs/test_receipts/latest.output"
  run bash -c 'cd "$1" && bash diagnose.sh' _ "$TMPROOT"
  [ "$status" -ne 0 ]
  [[ "$output" == *'No test receipt JSON found'* ]]
}

@test "split-file runner fails closed with named evidence when a bats file times out" {
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
sleep 2
SH
  chmod +x "$TMPROOT/bin/bats"

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" BATS_CACHE=0 \
    BATS_FILE_TIMEOUT_SECONDS=1 bash -c '
      source "$1/scripts/run_tests.sh"
      run_bats_files_parallel "$1/tests/unit/sample.bats"
    ' _ "$TMPROOT"

  [ "$status" -ne 0 ]
  [[ "$output" == *"START: sample.bats"* ]]
  [[ "$output" == *"DONE: sample.bats rc=124"* ]]
  [[ "$output" == *"TIMEOUT: sample.bats exceeded 1s"* ]]
  [[ "$output" == *"==== $TMPROOT/tests/unit/sample.bats ===="* ]]
}

@test "source mode resolves repo root from run_tests path instead of caller argv zero" {
  run env -u REPO_ROOT bash -c '
    cd /
    source "$1/scripts/run_tests.sh"
    [ "$REPO_ROOT" = "$1" ]
  ' _ "$TMPROOT"

  [ "$status" -eq 0 ]
}

@test "affected mode uses the same file-isolated scheduler instead of direct bats jobs" {
  printf '@test "a" { true; }\n' >"$TMPROOT/tests/unit/a.bats"
  printf '@test "b" { true; }\n' >"$TMPROOT/tests/unit/b.bats"
  cat >"$TMPROOT/scripts/test_select.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$REPO_ROOT/tests/unit/a.bats" "$REPO_ROOT/tests/unit/b.bats"
SH
  chmod +x "$TMPROOT/scripts/test_select.sh"
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BATS_ARGS_LOG"
printf '1..1\nok 1 sample\n'
SH
  chmod +x "$TMPROOT/bin/bats"

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" BATS_ARGS_LOG="$TMPROOT/bats.args" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" affected changed.file

  [ "$status" -eq 0 ]
  [ "$(wc -l <"$TMPROOT/bats.args")" -eq 2 ]
  [ "$(grep -c -- '--jobs 1' "$TMPROOT/bats.args")" -eq 2 ]
  ! grep -q -- '--jobs 8' "$TMPROOT/bats.args"
}

# test_necessity: 忍者の反復は変更影響testを既定選択し、selector障害時だけunit全量へfail-safe fallbackする二段契約を守る。
@test "default mode selects affected tests and records its rationale" {
  printf '@test "a" { true; }\n' >"$TMPROOT/tests/unit/a.bats"
  cat >"$TMPROOT/scripts/test_select.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$REPO_ROOT/tests/unit/a.bats"
SH
  chmod +x "$TMPROOT/scripts/test_select.sh"
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '1..1\nok 1 sample\n'
SH
  chmod +x "$TMPROOT/bin/bats"

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    BATS_CACHE=0 BATS_INNER_JOBS=1 bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner

  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_SELECTION result=selected reason=changed_files files=1"* ]]
}

@test "affected selector failure falls back to unit suite and records reason" {
  printf '@test "a" { true; }\n' >"$TMPROOT/tests/unit/a.bats"
  printf '#!/usr/bin/env bash\nexit 7\n' >"$TMPROOT/scripts/test_select.sh"
  chmod +x "$TMPROOT/scripts/test_select.sh"
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '1..1\nok 1 sample\n'
SH
  chmod +x "$TMPROOT/bin/bats"

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    BATS_CACHE=0 BATS_INNER_JOBS=1 bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner affected scripts/foo.sh

  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_SELECTION result=fallback reason=selector_exit_7 target=unit"* ]]
}

# test_necessity: affected=0 must finish inside the public receipt wrapper without acquiring the host-wide heavy admission lock.
@test "affected zero skips admission while preserving terminal receipt" {
  cat >"$TMPROOT/scripts/test_select.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  cat >"$TMPROOT/scripts/heavy_job_admission.sh" <<'SH'
#!/usr/bin/env bash
printf 'called\n' >"$ADMISSION_MARKER"
exit 91
SH
  chmod +x "$TMPROOT/scripts/test_select.sh" "$TMPROOT/scripts/heavy_job_admission.sh"

  run env -u SHOGUN_HEAVY_JOB_LOCK_HELD -u SHOGUN_HEAVY_JOB_ADMITTED \
    PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" ADMISSION_MARKER="$TMPROOT/admission.called" \
    RUN_TESTS_RECEIPT_DIR="$TMPROOT/logs/test_receipts" \
    bash "$TMPROOT/scripts/run_tests.sh" affected no-tests.file

  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_RECEIPT_PASS"* ]]
  artifact=$(python3 - "$TMPROOT/logs/test_receipts" <<'PY'
import glob,json,os,sys
receipt=max(glob.glob(os.path.join(sys.argv[1], '*.json')), key=os.path.getmtime)
print(json.load(open(receipt))['artifact'])
PY
)
  grep -q "files=0 admission=skipped" "$artifact"
  [ ! -e "$TMPROOT/admission.called" ]
}

# test_necessity: non-empty and selector-error affected runs remain admitted, and the non-empty selector is consumed exactly once from a fixed manifest.
@test "affected nonempty and selector error retain admission with fixed selection" {
  cat >"$TMPROOT/scripts/heavy_job_admission.sh" <<'SH'
#!/usr/bin/env bash
printf 'called\n' >>"$ADMISSION_MARKER"
[ "${1:-}" != "--" ] || shift
SHOGUN_HEAVY_JOB_LOCK_HELD=1 exec "$@"
SH
  cat >"$TMPROOT/scripts/test_select.sh" <<'SH'
#!/usr/bin/env bash
count=$(cat "$SELECT_COUNT" 2>/dev/null || printf 0)
count=$((count + 1))
printf '%s\n' "$count" >"$SELECT_COUNT"
if [ "${SELECT_ERROR:-0}" = 1 ]; then exit 7; fi
printf '%s\n' "$REPO_ROOT/tests/unit/sample.bats"
SH
  chmod +x "$TMPROOT/scripts/test_select.sh" "$TMPROOT/scripts/heavy_job_admission.sh"

  run env -u SHOGUN_HEAVY_JOB_LOCK_HELD -u SHOGUN_HEAVY_JOB_ADMITTED \
    PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" ADMISSION_MARKER="$TMPROOT/admission.called" \
    SELECT_COUNT="$TMPROOT/select.count" BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner affected changed.file
  [ "$status" -eq 0 ]
  [ "$(cat "$TMPROOT/select.count")" -eq 1 ]
  [ "$(wc -l <"$TMPROOT/admission.called")" -eq 1 ]

  rm -f "$TMPROOT/select.count"
  run env -u SHOGUN_HEAVY_JOB_LOCK_HELD -u SHOGUN_HEAVY_JOB_ADMITTED \
    PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" ADMISSION_MARKER="$TMPROOT/admission.called" \
    SELECT_COUNT="$TMPROOT/select.count" SELECT_ERROR=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner affected changed.file
  [ "$status" -eq 0 ]
  [[ "$output" == *"selector_exit_7 target=unit"* ]]
  [ "$(wc -l <"$TMPROOT/admission.called")" -eq 2 ]
}

# test_necessity: an explicitly task-owned contract test is the task-lane
# checkpoint; dependency expansion belongs to the fixed-SHA integration lane.
@test "task mode selects the declared contract test without transitive expansion" {
  printf '@test "a" { true; }\n' >"$TMPROOT/tests/unit/a.bats"
  cat >"$TMPROOT/scripts/test_select.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$SELECT_ARGS_LOG"
printf '%s\n' "$REPO_ROOT/tests/unit/a.bats"
SH
  chmod +x "$TMPROOT/scripts/test_select.sh"
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '1..1\nok 1 sample\n'
SH
  chmod +x "$TMPROOT/bin/bats"
  mkdir -p "$TMPROOT/queue/tasks" "$TMPROOT/queue/reports"
  cat >"$TMPROOT/queue/tasks/kagemaru.yaml" <<'YAML'
task:
  target_path: scripts/lib/owned.sh
  files_to_modify: [tests/unit/owned.bats]
  report_path: queue/reports/kagemaru.yaml
YAML
  cat >"$TMPROOT/queue/reports/kagemaru.yaml" <<'YAML'
files_modified:
  - path: docs/research/owned.md
    change: evidence
YAML
  export SELECT_ARGS_LOG="$TMPROOT/selector.args"

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" SELECT_ARGS_LOG="$SELECT_ARGS_LOG" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/kagemaru.yaml"

  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_SCOPE result=task files=3"* ]]
  [[ "$output" == *"TEST_SELECTION_REASON direct=1 transitive=0 source=task_declared_contract"* ]]
  [ ! -e "$SELECT_ARGS_LOG" ]
}

# test_necessity: deployed planned_paths are the task ownership SSOT; both
# supported schema locations must select the declared contract test directly,
# while contradictory dual declarations fail closed before any selector runs.
@test "task mode normalizes planned_paths ownership and rejects contradictory SSOTs" {
  printf '@test "owned" { true; }\n' >"$TMPROOT/tests/unit/owned.bats"
  cat >"$TMPROOT/scripts/test_select.sh" <<'SH'
#!/usr/bin/env bash
echo "selector must not run" >&2
exit 91
SH
  chmod +x "$TMPROOT/scripts/test_select.sh"
  mkdir -p "$TMPROOT/queue/tasks"

  cat >"$TMPROOT/queue/tasks/top.yaml" <<'YAML'
task:
  planned_paths: [scripts/run_tests.sh, tests/unit/owned.bats]
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    BATS_CACHE=1 BATS_INNER_JOBS=1 \
    bash -c 'cd "$1" && bash scripts/run_tests.sh --receipt-inner task queue/tasks/top.yaml' _ "$TMPROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_SCOPE result=task files=2"* ]]
  [[ "$output" == *"TEST_SELECTION_REASON direct=1 transitive=0 source=task_declared_contract"* ]]

  mkdir -p "$TMPROOT/receipts" "$TMPROOT/sf"
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" \
    RUN_TESTS_RECEIPT_DIR="$TMPROOT/receipts" RUN_TESTS_SINGLEFLIGHT_DIR="$TMPROOT/sf" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=1 BATS_INNER_JOBS=1 \
    bash -c 'cd "$1" && bash scripts/run_tests.sh task queue/tasks/top.yaml' _ "$TMPROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: 1 bats file(s) (0 run, 1 cached)"* ]]
  [[ "$output" == *"TEST_RECEIPT_PASS"* ]]

  cat >"$TMPROOT/queue/tasks/nested.yaml" <<'YAML'
task:
  commit_contract:
    required: true
    planned_paths: [scripts/run_tests.sh, tests/unit/owned.bats]
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/nested.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_SCOPE result=task files=2"* ]]
  [[ "$output" == *"TEST_SELECTION_REASON direct=1 transitive=0 source=task_declared_contract"* ]]

  cat >"$TMPROOT/queue/tasks/mismatch.yaml" <<'YAML'
task:
  planned_paths: [scripts/run_tests.sh, tests/unit/owned.bats]
  commit_contract:
    required: true
    planned_paths: [scripts/run_tests.sh, tests/unit/different.bats]
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/mismatch.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK: task scope could not be resolved"* ]]
}

# test_necessity: an unresolved/empty task scope must fail closed instead of silently reverting to repository-wide git diff.
@test "task mode rejects empty scope instead of using global git diff" {
  mkdir -p "$TMPROOT/queue/tasks"
  printf 'task:\n  status: in_progress\n' >"$TMPROOT/queue/tasks/empty.yaml"

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/empty.yaml"

  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK: task scope is empty"* ]]
}

# test_necessity: inspection-only recon tasks must produce a successful
# zero-source-test receipt instead of expanding inspection references through
# the dependency selector and attributing unrelated failures to the recon.
@test "readonly recon task skips source selection and emits a zero-test receipt" {
  mkdir -p "$TMPROOT/queue/tasks" "$TMPROOT/receipts" "$TMPROOT/sf"
  cat >"$TMPROOT/queue/tasks/readonly.yaml" <<'YAML'
task:
  task_type: recon2
  commit_contract:
    required: false
  inspection_path: '["scripts/inspected.sh"]'
  readonly_refs: [scripts/other.sh]
YAML
  cat >"$TMPROOT/scripts/test_select.sh" <<'SH'
#!/usr/bin/env bash
echo "selector must not run" >&2
exit 91
SH
  chmod +x "$TMPROOT/scripts/test_select.sh"

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" \
    RUN_TESTS_RECEIPT_DIR="$TMPROOT/receipts" RUN_TESTS_SINGLEFLIGHT_DIR="$TMPROOT/sf" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" task "$TMPROOT/queue/tasks/readonly.yaml"

  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_SCOPE result=readonly_probe files=0"* ]]
  [[ "$output" == *"TEST_SELECTION result=selected reason=readonly_probe_no_source_tests files=0"* ]]
  [[ "$output" == *"TEST_RECEIPT_PASS"* ]]
  receipt="$(find "$TMPROOT/receipts" -name '*.json' -type f | head -1)"
  [ -n "$receipt" ]
  run python3 - "$receipt" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["rc"] == 0
assert d["declared_test_count"] == 0
assert d["observed_test_count"] == 0
assert d["skip_count"] == 0
assert d["test_paths"] == []
PY
  [ "$status" -eq 0 ]
}

# test_necessity: a recon with commit ownership remains an implementation task;
# readonly classification must not suppress its declared contract test.
@test "commit-required recon keeps implementation test selection" {
  printf '@test "owned" { true; }\n' >"$TMPROOT/tests/unit/owned.bats"
  mkdir -p "$TMPROOT/queue/tasks"
  cat >"$TMPROOT/queue/tasks/implementation.yaml" <<'YAML'
task:
  task_type: recon2
  commit_contract:
    required: true
  target_path: scripts/run_tests.sh
  test_path: tests/unit/owned.bats
  inspection_path: '["scripts/run_tests.sh"]'
YAML

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/implementation.yaml"

  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_SCOPE result=task files=2"* ]]
  [[ "$output" == *"TEST_SELECTION_REASON direct=1 transitive=0 source=task_declared_contract"* ]]
  [[ "$output" != *"readonly_probe"* ]]
}

# test_necessity: public task/file callers selecting the same test must share one terminal receipt; the task-leader fixture must include admission dependencies and preserve rc=7 (never 127 or collapsed rc=1). This guards both dependency closure and exit-code fidelity.
@test "task and file public callers single-flight the same selection and preserve failure rc" {
  mkdir -p "$TMPROOT/queue/tasks" "$TMPROOT/receipts" "$TMPROOT/sf"
  cat >"$TMPROOT/scripts/test_select.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$REPO_ROOT/tests/unit/sample.bats"
SH
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
exec 9>>"$HEAVY_LOG"
flock 9
count=$(cat "$HEAVY_COUNT" 2>/dev/null || printf 0)
printf '%s\n' "$((count + 1))" >"$HEAVY_COUNT"
flock -u 9
sleep 1
printf '1..1\nnot ok 1 sample\n'
exit 7
SH
  chmod +x "$TMPROOT/scripts/test_select.sh" "$TMPROOT/bin/bats"
  cat >"$TMPROOT/queue/tasks/saizo.yaml" <<'YAML'
task:
  target_path: scripts/run_tests.sh
YAML

  common=(env -u RUN_TESTS_ACTIVE -u SHOGUN_HEAVY_JOB_LOCK_HELD -u SHOGUN_HEAVY_JOB_ADMITTED PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" BATS_CACHE=0
    RUN_TESTS_RECEIPT_DIR="$TMPROOT/receipts" RUN_TESTS_SINGLEFLIGHT_DIR="$TMPROOT/sf"
    HEAVY_LOG="$TMPROOT/count.lock" HEAVY_COUNT="$TMPROOT/count")
  for trial in 1 2 3; do
    rm -f "$TMPROOT/receipts"/* "$TMPROOT/sf"/* "$TMPROOT/count"
    if [ $((trial % 2)) -eq 1 ]; then
      "${common[@]}" bash "$TMPROOT/scripts/run_tests.sh" task "$TMPROOT/queue/tasks/saizo.yaml" >"$TMPROOT/task.out" 2>"$TMPROOT/task.err" & p1=$!
      sleep 0.2
      "${common[@]}" bash "$TMPROOT/scripts/run_tests.sh" file "$TMPROOT/tests/unit/sample.bats" >"$TMPROOT/file.out" 2>"$TMPROOT/file.err" & p2=$!
    else
      "${common[@]}" bash "$TMPROOT/scripts/run_tests.sh" file "$TMPROOT/tests/unit/sample.bats" >"$TMPROOT/file.out" 2>"$TMPROOT/file.err" & p2=$!
      sleep 0.2
      "${common[@]}" bash "$TMPROOT/scripts/run_tests.sh" task "$TMPROOT/queue/tasks/saizo.yaml" >"$TMPROOT/task.out" 2>"$TMPROOT/task.err" & p1=$!
    fi
    rc1=0; wait "$p1" || rc1=$?
    rc2=0; wait "$p2" || rc2=$?
    echo "trial=$trial rc1=$rc1 rc2=$rc2 task_err=$(tr '\n' '|' <"$TMPROOT/task.err") file_err=$(tr '\n' '|' <"$TMPROOT/file.err")" >&3
    receipt_rc=$(python3 - "$TMPROOT/receipts" <<'PY'
import glob,json,os,sys
p=glob.glob(os.path.join(sys.argv[1], '*.json'))
print(json.load(open(p[0]))['rc'])
PY
)
    [ "$receipt_rc" -eq 7 ]
    [ "$rc1" -eq "$receipt_rc" ]
    [ "$rc2" -eq "$receipt_rc" ]
    [ "$(find "$TMPROOT/receipts" -name '*.json' | wc -l)" -eq 1 ]
    [ "$(grep -h -c 'SINGLE_FLIGHT_JOINED' "$TMPROOT/task.err" "$TMPROOT/file.err" | awk '{s+=$1} END{print s}')" -eq 1 ]
    grep -h -q 'TEST_RECEIPT_FAIL.*rc=7.*joined=1' "$TMPROOT/task.out" "$TMPROOT/file.out"
    ! grep -h -q 'TEST_RECEIPT_PASS.*rc=7' "$TMPROOT/task.out" "$TMPROOT/file.out"
  done
}

# test_necessity: every terminal receipt rc must determine both the public label and process exit code.
@test "terminal receipt emitter keeps label exit and receipt rc identical for rc0 rc1 rc2 rc7" {
  mkdir -p "$TMPROOT/receipts"
  for rc in 0 1 2 7; do
    artifact="$TMPROOT/receipts/r${rc}.output"; printf 'fixture rc=%s\n' "$rc" >"$artifact"
    python3 - "$TMPROOT/receipts/r${rc}.json" "$artifact" "$rc" <<'PY'
import hashlib,json,sys
p,a,rc=sys.argv[1],sys.argv[2],int(sys.argv[3]); raw=open(a,'rb').read()
json.dump(dict(version=2,complete=True,result='PASS' if rc==0 else 'FAIL',rc=rc,duration_ms=1,
 output_sha256=hashlib.sha256(raw).hexdigest(),declared_test_count=1,observed_test_count=1,
 skip_count=0,artifact=a,signal=None,command=['fixture'],source_head='0'*40,test_paths=['tests/unit/sample.bats']),open(p,'w'))
PY
    run env REPO_ROOT="$TMPROOT" bash -c 'source "$1/scripts/run_tests.sh"; emit_run_tests_terminal_receipt "$2" fixture=1' _ "$TMPROOT" "$TMPROOT/receipts/r${rc}.json"
    [ "$status" -eq "$rc" ]
    if [ "$rc" -eq 0 ]; then [[ "$output" == TEST_RECEIPT_PASS* ]]; else [[ "$output" == TEST_RECEIPT_FAIL* ]]; fi
    [[ "$output" == *"rc=$rc"* ]]
  done
}

# test_necessity: truncated tool output must be recoverable from selection or run identity without rerunning tests.
@test "receipt recovery resolves selection state and run identity without execution" {
  mkdir -p "$TMPROOT/receipts" "$TMPROOT/sf"
  artifact="$TMPROOT/receipts/recover.output"; printf 'terminal\n' >"$artifact"
  python3 - "$TMPROOT/receipts/recover.json" "$artifact" <<'PY'
import hashlib,json,sys
p,a=sys.argv[1:]; raw=open(a,'rb').read()
json.dump(dict(version=2,complete=True,result='FAIL',rc=7,duration_ms=1,
 output_sha256=hashlib.sha256(raw).hexdigest(),declared_test_count=1,observed_test_count=1,
 skip_count=0,artifact=a,signal=None,command=['fixture'],source_head='0'*40,test_paths=['tests/unit/sample.bats']),open(p,'w'))
PY
  printf '%s\n' "$TMPROOT/receipts/recover.json" >"$TMPROOT/sf/selection-id.state"
  run env REPO_ROOT="$TMPROOT" RUN_TESTS_RECEIPT_DIR="$TMPROOT/receipts" RUN_TESTS_SINGLEFLIGHT_DIR="$TMPROOT/sf" bash "$TMPROOT/scripts/run_tests.sh" receipt selection-id
  [ "$status" -eq 0 ]; [[ "$output" == *'path='*'/recover.json rc=7'* ]]
  run env REPO_ROOT="$TMPROOT" RUN_TESTS_RECEIPT_DIR="$TMPROOT/receipts" bash "$TMPROOT/scripts/run_tests.sh" receipt recover
  [ "$status" -eq 0 ]; [[ "$output" == *'path='*'/recover.json rc=7'* ]]
}

# test_necessity: distinct selected test sets must not false-positive as duplicates or serialize behind one selection lock.
@test "different file selections run concurrently under distinct single-flight keys" {
  printf '@test "other" { true; }\n' >"$TMPROOT/tests/unit/other.bats"
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
exec 9>>"$PARALLEL_LOCK"
flock 9
active=$(cat "$PARALLEL_ACTIVE" 2>/dev/null || printf 0); active=$((active + 1)); printf '%s\n' "$active" >"$PARALLEL_ACTIVE"
maximum=$(cat "$PARALLEL_MAX" 2>/dev/null || printf 0); [ "$active" -le "$maximum" ] || printf '%s\n' "$active" >"$PARALLEL_MAX"
flock -u 9
sleep 1
flock 9
active=$(cat "$PARALLEL_ACTIVE"); printf '%s\n' "$((active - 1))" >"$PARALLEL_ACTIVE"
flock -u 9
printf '1..1\nok 1 sample\n'
SH
  chmod +x "$TMPROOT/bin/bats"
  mkdir -p "$TMPROOT/receipts" "$TMPROOT/sf"
  common=(env -u RUN_TESTS_ACTIVE -u SHOGUN_HEAVY_JOB_LOCK_HELD -u SHOGUN_HEAVY_JOB_ADMITTED PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" RUN_TESTS_RECEIPT_DIR="$TMPROOT/receipts" RUN_TESTS_SINGLEFLIGHT_DIR="$TMPROOT/sf" PARALLEL_LOCK="$TMPROOT/parallel.lock" PARALLEL_ACTIVE="$TMPROOT/active" PARALLEL_MAX="$TMPROOT/max")
  "${common[@]}" bash "$TMPROOT/scripts/run_tests.sh" file "$TMPROOT/tests/unit/sample.bats" & p1=$!
  "${common[@]}" bash "$TMPROOT/scripts/run_tests.sh" file "$TMPROOT/tests/unit/other.bats" & p2=$!
  wait "$p1"
  wait "$p2"
  [ "$(find "$TMPROOT/receipts" -name '*.json' | wc -l)" -eq 2 ]
  [ "$(cat "$TMPROOT/max")" -eq 2 ]
}

@test "matching timing cohort orders measured files by LPT" {
  printf '@test "a" { true; }\n' >"$TMPROOT/tests/unit/a.bats"
  printf '@test "b" { true; }\n' >"$TMPROOT/tests/unit/b.bats"
  git -C "$TMPROOT" add tests && git -C "$TMPROOT" commit -qm files
  fp="$(_source_fp)"; commit="$(git -C "$TMPROOT" rev-parse HEAD)"
  _write_lpt_ledger "$fp" "$commit" "$TMPROOT/tests/unit/a.bats" 1 "$TMPROOT/tests/unit/b.bats" 9
  run env REPO_ROOT="$TMPROOT" TEST_TIMING_LEDGER="$TMPROOT/logs/ledger.tsv" bash -c '
    source "$1/scripts/run_tests.sh"
    mapfile -t got < <(order_bats_files_lpt "$2" "$1/tests/unit/a.bats" "$1/tests/unit/b.bats")
    [[ "${got[0]}" == */b.bats && "${got[1]}" == */a.bats ]]
  ' _ "$TMPROOT" "$fp"
  [ "$status" -eq 0 ]
}

@test "non-matching timing cohort preserves every requested file" {
  printf '@test "a" { true; }\n' >"$TMPROOT/tests/unit/a.bats"
  printf '@test "b" { true; }\n' >"$TMPROOT/tests/unit/b.bats"
  git -C "$TMPROOT" add tests && git -C "$TMPROOT" commit -qm files
  fp="$(_source_fp)"; commit="$(git -C "$TMPROOT" rev-parse HEAD)"
  _write_lpt_ledger stale-fingerprint "$commit" "$TMPROOT/tests/unit/a.bats" 1
  run env REPO_ROOT="$TMPROOT" TEST_TIMING_LEDGER="$TMPROOT/logs/ledger.tsv" bash -c '
    source "$1/scripts/run_tests.sh"
    mapfile -t got < <(order_bats_files_lpt "$2" "$1/tests/unit/a.bats" "$1/tests/unit/b.bats")
    [ "${#got[@]}" -eq 2 ]
    [[ " ${got[*]} " == *" $1/tests/unit/a.bats "* ]]
    [[ " ${got[*]} " == *" $1/tests/unit/b.bats "* ]]
  ' _ "$TMPROOT" "$fp"
  [ "$status" -eq 0 ]
}

@test "work-conserving queue bypasses a weight-8 head when a weight-4 file fits" {
  for name in test_normal_slow test_cmd_save test_normal_short; do printf '@test "x" { true; }\n' >"$TMPROOT/tests/unit/$name.bats"; done
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$(basename "$1")" >>"$BATS_START_LOG"
# Exit immediately so every child may finish before the scheduler reaches
# wait -n; this reproduces the rc=127 bookkeeping race deterministically.
printf '1..1\nok 1 pass\n'
SH
  chmod +x "$TMPROOT/bin/bats"
  git -C "$TMPROOT" add tests && git -C "$TMPROOT" commit -qm queue
  fp="$(_source_fp)"; commit="$(git -C "$TMPROOT" rev-parse HEAD)"
  _write_lpt_ledger "$fp" "$commit" \
    "$TMPROOT/tests/unit/test_normal_slow.bats" 30 \
    "$TMPROOT/tests/unit/test_cmd_save.bats" 20 \
    "$TMPROOT/tests/unit/test_normal_short.bats" 10
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" TEST_TIMING_LEDGER="$TMPROOT/logs/ledger.tsv" \
    BATS_START_LOG="$TMPROOT/start.log" BATS_SCHEDULER_TRACE="$TMPROOT/schedule.tsv" BATS_CACHE=0 \
    BATS_INNER_JOBS=4 BATS_HEAVY_INNER_JOBS=8 BATS_MAX_TEST_JOBS=8 bash -c '
      source "$1/scripts/run_tests.sh"
      run_bats_files_parallel "$1/tests/unit/test_normal_slow.bats" "$1/tests/unit/test_cmd_save.bats" "$1/tests/unit/test_normal_short.bats"
    ' _ "$TMPROOT"
  echo "$output" >&3
  [ "$status" -eq 0 ]
  mapfile -t started < <(cut -f1 "$TMPROOT/schedule.tsv")
  [ "${started[0]}" = test_normal_slow.bats ]
  [ "${started[1]}" = test_normal_short.bats ]
  [ "${started[2]}" = test_cmd_save.bats ]
  [ "$(sort -u "$TMPROOT/start.log" | wc -l)" -eq 3 ]
}

@test "single stream parser preserves TAP and counts skip abnormal and multi-plan" {
  printf '@test "one" { true; }\n@test "two" { true; }\n' >"$TMPROOT/tests/unit/parse.bats"
  printf '1..2\nok 1 one # skip reason\nnot ok 2 two\n1..1\nok 1 nested\n' >"$TMPROOT/out.tap"
  printf '7\t%s\t%s\t%s\t0\n' "$TMPROOT/tests/unit/parse.bats" "$TMPROOT/out.tap" "$TMPROOT/time" >"$TMPROOT/manifest"
  run env REPO_ROOT="$TMPROOT" BATS_TAP_OUTPUT="$TMPROOT/combined.tap" bash -c '
    source "$1/scripts/run_tests.sh"
    aggregate_bats_outputs "$1/manifest" "$1/stats"
  ' _ "$TMPROOT"
  [ "$status" -eq 0 ]
  cmp "$TMPROOT/out.tap" "$TMPROOT/combined.tap"
  awk -F '\t' 'NR==1 {exit !($1==7 && $3==2 && $4==1 && $5==1)}' "$TMPROOT/stats"
}
