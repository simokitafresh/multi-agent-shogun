#!/usr/bin/env bats
# test_necessity: Nested aggregate runner fails closed while focused file mode remains allowed; violation is BLOCK.

setup() {
  # This file deliberately launches isolated aggregate runner fixtures.  They
  # are new checkpoint roots, not accidental children of the outer CI runner.
  # A full-suite parent exports its own runner/receipt/cache transport.  Those
  # values describe the parent repository and must not override the isolated
  # TMPROOT fixtures below (for example, RUN_TESTS_BATS_BIN bypasses TMPROOT/bin
  # and an inherited BATS_CACHE can silently turn an expected execution into a
  # cache hit).  Reset the complete parent-owned boundary once for every test.
  # RUN_TESTS_* is the parent runner's transport namespace.  Clear the prefix
  # instead of maintaining a partial list that goes stale whenever the runner
  # gains another exported manifest, receipt, or single-flight variable.
  while IFS= read -r run_tests_parent_var; do
    unset "$run_tests_parent_var"
  done < <(compgen -A variable RUN_TESTS_)
  unset BATS_TAP_OUTPUT
  unset BATS_CACHE BATS_CACHE_DIR BATS_SOURCE_FINGERPRINT
  unset TEST_TIMING_LEDGER TEST_SUITE_TIMING_LEDGER
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPROOT="$(mktemp -d)"
  mkdir -p "$TMPROOT/scripts/lib" "$TMPROOT/tests/unit" "$TMPROOT/bin" "$TMPROOT/logs"
  cp "$ROOT/scripts/run_tests.sh" "$ROOT/scripts/test_timing_ledger_write.sh" \
    "$ROOT/scripts/test_suite_timing_ledger_write.sh" "$ROOT/scripts/universal_shard.py" \
    "$ROOT/scripts/universal_shard_adapters.py" "$ROOT/scripts/run_with_receipt.sh" \
    "$ROOT/scripts/heavy_job_admission.sh" "$TMPROOT/scripts/"
  cp "$ROOT/scripts/lib/yaml_field_set.sh" "$TMPROOT/scripts/lib/"
  cp "$ROOT/scripts/report_field_set.sh" "$TMPROOT/scripts/"
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

# test_necessity: A nested test process must not inherit the outer public
# receipt identity; otherwise a nested runner can overwrite the outer
# selection/source identity and timing destinations.
@test "nested Bats and pytest processes do not inherit outer receipt identity" {
  export IDENTITY_ENV_LOG="$TMPROOT/identity-env.log"
  export REAL_PYTHON3="$(command -v python3)"
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
if [[ "${NESTED_INNER:-0}" != "1" ]]; then
  mkdir -p "$REPO_ROOT/logs/nested-receipts"
  nested_rc=0
  NESTED_INNER=1 RUN_TESTS_RECEIPT_DIR="$REPO_ROOT/logs/nested-receipts" \
    bash "$REPO_ROOT/scripts/run_tests.sh" file "$1" \
    >"$REPO_ROOT/logs/nested.stdout" 2>"$REPO_ROOT/logs/nested.stderr" || nested_rc=$?
  [ "$nested_rc" -eq 0 ] || exit "$nested_rc"
fi
printf 'bats' >>"$IDENTITY_ENV_LOG"
for name in RUN_TESTS_RECEIPT_PATH RUN_TESTS_RUN_ID RUN_TESTS_COMMIT_SHA RUN_TESTS_SOURCE_FINGERPRINT RUN_TESTS_PENDING_FILE_BATCH RUN_TESTS_PENDING_SUITE_BATCH RUN_TESTS_SELECTED_PATHS_FILE; do
  printf ' %s=%s' "$name" "${!name-<unset>}" >>"$IDENTITY_ENV_LOG"
done
printf '\n' >>"$IDENTITY_ENV_LOG"
printf '\n1..1\nok 1 sample\n'
SH
  cat >"$TMPROOT/bin/python3" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == -m && "${2:-}" == pytest ]]; then
  printf 'pytest' >>"$IDENTITY_ENV_LOG"
  for name in RUN_TESTS_RECEIPT_PATH RUN_TESTS_RUN_ID RUN_TESTS_COMMIT_SHA RUN_TESTS_SOURCE_FINGERPRINT RUN_TESTS_PENDING_FILE_BATCH RUN_TESTS_PENDING_SUITE_BATCH RUN_TESTS_SELECTED_PATHS_FILE; do
    printf ' %s=%s' "$name" "${!name-<unset>}" >>"$IDENTITY_ENV_LOG"
  done
  printf '\n' >>"$IDENTITY_ENV_LOG"
  printf '\n============================== 1 passed in 0.01s ==============================\n'
  exit 0
fi
exec "$REAL_PYTHON3" "$@"
SH
  chmod +x "$TMPROOT/bin/bats" "$TMPROOT/bin/python3"
  printf 'def test_owned():\n    assert True\n' >"$TMPROOT/tests/unit/owned.py"
  outer_env=(env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT"
    RUN_TESTS_RECEIPT_PATH="$TMPROOT/outer.json" RUN_TESTS_RUN_ID=outer-run
    RUN_TESTS_COMMIT_SHA=outer-commit RUN_TESTS_SOURCE_FINGERPRINT=outer-source
    RUN_TESTS_PENDING_FILE_BATCH="$TMPROOT/outer.timing"
    RUN_TESTS_PENDING_SUITE_BATCH="$TMPROOT/outer.suite-timing"
    RUN_TESTS_SELECTED_PATHS_FILE="$TMPROOT/outer.paths"
    IDENTITY_ENV_LOG="$IDENTITY_ENV_LOG" REAL_PYTHON3="$REAL_PYTHON3"
    BATS_CACHE=0 BATS_INNER_JOBS=1 SHOGUN_HEAVY_JOB_LOCK_HELD=1 NESTED_INNER=1)

  for split in 1 0; do
    : >"$IDENTITY_ENV_LOG"
    rc=0
    "${outer_env[@]}" BATS_SPLIT_FILES="$split" bash -c \
      'source "$1/scripts/run_tests.sh"; run_bats_files_parallel "$1/tests/unit/sample.bats"' \
      _ "$TMPROOT" || rc=$?
    [ "$rc" -eq 0 ]
    identity_lines="$(wc -l <"$IDENTITY_ENV_LOG")"
    [ "$identity_lines" -eq 1 ]
    grep -Fqx 'bats RUN_TESTS_RECEIPT_PATH=<unset> RUN_TESTS_RUN_ID=<unset> RUN_TESTS_COMMIT_SHA=<unset> RUN_TESTS_SOURCE_FINGERPRINT=<unset> RUN_TESTS_PENDING_FILE_BATCH=<unset> RUN_TESTS_PENDING_SUITE_BATCH=<unset> RUN_TESTS_SELECTED_PATHS_FILE=<unset>' "$IDENTITY_ENV_LOG"
  done

  : >"$IDENTITY_ENV_LOG"
  "${outer_env[@]}" bash -c \
    'source "$1/scripts/run_tests.sh"; run_task_test_paths "$1/tests/unit/owned.py"' \
    _ "$TMPROOT"
  [ "$(wc -l <"$IDENTITY_ENV_LOG")" -eq 1 ]
  grep -Fqx 'pytest RUN_TESTS_RECEIPT_PATH=<unset> RUN_TESTS_RUN_ID=<unset> RUN_TESTS_COMMIT_SHA=<unset> RUN_TESTS_SOURCE_FINGERPRINT=<unset> RUN_TESTS_PENDING_FILE_BATCH=<unset> RUN_TESTS_PENDING_SUITE_BATCH=<unset> RUN_TESTS_SELECTED_PATHS_FILE=<unset>' "$IDENTITY_ENV_LOG"

  outer_receipt="$TMPROOT/logs/outer.json"
  mkdir -p "$TMPROOT/logs/nested-receipts"
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" \
    RUN_TESTS_RECEIPT_PATH="$outer_receipt" RUN_TESTS_RECEIPT_DIR="$TMPROOT/logs" \
    RUN_TESTS_RUN_ID=outer-run RUN_TESTS_COMMIT_SHA=outer-commit \
    RUN_TESTS_SOURCE_FINGERPRINT=outer-source \
    RUN_TESTS_PENDING_FILE_BATCH="$TMPROOT/outer.timing" \
    RUN_TESTS_PENDING_SUITE_BATCH="$TMPROOT/outer.suite-timing" \
    RUN_TESTS_SELECTED_PATHS_FILE="$TMPROOT/outer.paths" \
    IDENTITY_ENV_LOG="$IDENTITY_ENV_LOG" REAL_PYTHON3="$REAL_PYTHON3" \
    BATS_CACHE=0 BATS_INNER_JOBS=1 SHOGUN_HEAVY_JOB_LOCK_HELD=1 NESTED_INNER=0 \
    bash "$TMPROOT/scripts/run_tests.sh" file "$TMPROOT/tests/unit/sample.bats"
  [ "$status" -eq 0 ]
  nested_receipt="$(find "$TMPROOT/logs/nested-receipts" -name '*.json' -type f | head -1)"
  [ -n "$nested_receipt" ]
  run python3 - "$outer_receipt" "$nested_receipt" <<'PY'
import json, sys
outer, nested = (json.load(open(path, encoding="utf-8")) for path in sys.argv[1:])
assert outer["test_paths"] == ["tests/unit/sample.bats"], outer
assert nested["test_paths"] == ["tests/unit/sample.bats"], nested
assert outer["run_id"] != nested["run_id"], (outer, nested)
assert outer["source_fingerprint"] != "outer-source", outer
PY
  [ "$status" -eq 0 ]
}

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

# test_necessity: External pytest's decoration-delimited terminal summary must
# preserve selected PASS/FAIL/SKIP counts, and FAIL/SKIP output must never be
# converted into a clean receipt.
@test "external pytest receipt adopts standard summary without false PASS" {
  receipt="$TMPROOT/logs/external-pytest.json"
  artifact="$TMPROOT/logs/external-pytest.output"
  paths="$TMPROOT/logs/external-pytest.paths"
  head="$(git -C "$TMPROOT" rev-parse HEAD)"
  printf 'external-project:%s\n' "$TMPROOT" >"$paths"

  _write_pytest_receipt() {
    printf '%s\n' "$1" >"$artifact"
    python3 - "$receipt" "$artifact" "$2" <<'PY'
import hashlib, json, sys
path, artifact, rc = sys.argv[1:]
raw = open(artifact, 'rb').read()
json.dump({
    "version": 2, "complete": True,
    "result": "PASS" if rc == "0" else "FAIL", "rc": int(rc),
    "duration_ms": 1, "output_sha256": hashlib.sha256(raw).hexdigest(),
    "declared_test_count": 0, "observed_test_count": 0, "skip_count": 0,
    "artifact": artifact, "signal": None, "command": ["pytest"],
}, open(path, "w"))
PY
    run env REPO_ROOT="$TMPROOT" bash -c '
      source "$1/scripts/run_tests.sh"
      publish_run_tests_metadata "$2" "$3" "$4" selector
      verify_run_tests_receipt "$2"
    ' _ "$TMPROOT" "$receipt" "$head" "$paths"
  }

  _write_pytest_receipt \
    '============================== 17 passed in 0.21s ==============================' 0
  [ "$status" -eq 0 ]
  [ "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["observed_test_count"], d["declared_test_count"], d["skip_count"], d["rc"])' "$receipt")" = "17 17 0 0" ]

  _write_pytest_receipt \
    '================== 1 failed, 15 passed, 1 skipped in 0.32s ==================' 1
  [ "$status" -ne 0 ]
  [ "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["observed_test_count"], d["declared_test_count"], d["skip_count"], d["rc"])' "$receipt")" = "17 17 1 1" ]
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
  awk -F'\t' 'NR==2 {exit !($4=="unit" && $9=="pass" && $11==0 && NF==15 && length($15)==64)}' "$TMPROOT/logs/ledger.tsv"
  awk -F'\t' 'NR==1 {exit !($5=="suite_wall_sec" && $6=="sum_file_sec" && NF==11)} NR==2 {exit !(NF==11 && $5>=0 && $6>=0 && length($11)==64)}' "$TMPROOT/logs/test_suite_timing_ledger.tsv"
  receipt="$(find "$TMPROOT/logs/test_receipts" -name '*.json' -type f | head -1)"
  python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["run_manifest"]["estimated_cost"]["suite_timeout_sec"] == 1800' "$receipt"
  receipt_id="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["run_id"],d["commit_sha"],d["source_fingerprint"],d["output_sha256"])' "$receipt")"
  file_id="$(awk -F'\t' 'NR==2 {print $1,$3,$12,$15}' "$TMPROOT/logs/ledger.tsv")"
  suite_id="$(awk -F'\t' 'NR==2 {print $1,$3,$9,$11}' "$TMPROOT/logs/test_suite_timing_ledger.tsv")"
  [ "$receipt_id" = "$file_id" ]
  [ "$receipt_id" = "$suite_id" ]
}

# test_necessity: A non-terminal-success run may publish its failure receipt,
# but must leave both timing ledgers absent so no exact identity join exists.
@test "failed run publishes no per-file or per-suite timing cohort" {
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '1..1\nnot ok 1 sample\n'
exit 7
SH
  chmod +x "$TMPROOT/bin/bats"

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    BATS_CACHE=0 BATS_SPLIT_FILES=1 TEST_TIMING_LEDGER="$TMPROOT/logs/failed-file.tsv" \
    TEST_SUITE_TIMING_LEDGER="$TMPROOT/logs/failed-suite.tsv" \
    bash "$TMPROOT/scripts/run_tests.sh" unit

  [ "$status" -eq 7 ]
  [ ! -e "$TMPROOT/logs/failed-file.tsv" ]
  [ ! -e "$TMPROOT/logs/failed-suite.tsv" ]
  receipt="$(find "$TMPROOT/logs/test_receipts" -name '*.json' -type f | head -1)"
  python3 - "$receipt" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["complete"] is True
assert d["result"] == "FAIL"
assert d["rc"] == 7
PY
}

# test_necessity: receipt/per-file/per-suiteは同じ4識別子を持つ3点結合だけを
# success序列候補とし、片側batch欠損は既存ledgerを1byteも公開変更しない。
@test "run identity paired publisher fails closed before one-sided publication" {
  file_batch="$TMPROOT/file.batch"; suite_batch="$TMPROOT/suite.batch"
  printf 'r1\trepo\t%s\tunit\tbats\ttests/unit/sample.bats\t1\t0.1\tpass\t0\t0\tfp\t2026-01-01T00:00:00Z\tmode=unit\n' "$(git -C "$TMPROOT" rev-parse HEAD)" >"$file_batch"
  before_file="$(sha256sum "$TMPROOT/logs/ledger.tsv" 2>/dev/null || printf absent)"
  before_suite="$(sha256sum "$TMPROOT/logs/test_suite_timing_ledger.tsv" 2>/dev/null || printf absent)"

  run env TEST_TIMING_LEDGER="$TMPROOT/logs/ledger.tsv" \
    TEST_SUITE_TIMING_LEDGER="$TMPROOT/logs/test_suite_timing_ledger.tsv" \
    bash "$TMPROOT/scripts/test_suite_timing_ledger_write.sh" --pair \
      "$file_batch" "$suite_batch" "$(printf output | sha256sum | cut -d' ' -f1)"

  [ "$status" -eq 2 ]
  [ "$(sha256sum "$TMPROOT/logs/ledger.tsv" 2>/dev/null || printf absent)" = "$before_file" ]
  [ "$(sha256sum "$TMPROOT/logs/test_suite_timing_ledger.tsv" 2>/dev/null || printf absent)" = "$before_suite" ]
}

# test_necessity: 4識別子列のschema追加は既存14/10列の全履歴を保持して移行し、
# header不一致を空ledgerへの初期化として扱わない。
@test "paired publisher migrates legacy timing schemas without dropping history" {
  file_batch="$TMPROOT/file.batch"; suite_batch="$TMPROOT/suite.batch"
  file_ledger="$TMPROOT/logs/legacy-file.tsv"; suite_ledger="$TMPROOT/logs/legacy-suite.tsv"
  head="$(git -C "$TMPROOT" rev-parse HEAD)"; sha="$(printf output | sha256sum | cut -d' ' -f1)"
  printf 'run_id\trepo\tcommit_sha\tsuite_root\trunner\ttest_file\ttest_id_count\twall_sec\tstatus\tskip_count\tcache_hit\tsource_fingerprint\tmeasured_at\tresource_tags\nold\trepo\t%s\tunit\tbats\told.bats\t1\t.1\tpass\t0\t0\tfp\tnow\ttag\n' "$head" >"$file_ledger"
  printf 'run_id\trepo\tcommit_sha\tmode\tsuite_wall_sec\tsum_file_sec\tfile_count\tstatus\tsource_fingerprint\tmeasured_at\nold\trepo\t%s\tunit\t.1\t.1\t1\tpass\tfp\tnow\n' "$head" >"$suite_ledger"
  printf 'new\trepo\t%s\tunit\tbats\tnew.bats\t1\t.1\tpass\t0\t0\tfp\tnow\ttag\n' "$head" >"$file_batch"
  printf 'new\trepo\t%s\tunit\t.1\t.1\t1\tpass\tfp\tnow\n' "$head" >"$suite_batch"

  run env TEST_TIMING_LEDGER="$file_ledger" TEST_SUITE_TIMING_LEDGER="$suite_ledger" \
    bash "$TMPROOT/scripts/test_suite_timing_ledger_write.sh" --pair "$file_batch" "$suite_batch" "$sha"

  [ "$status" -eq 0 ]
  [ "$(wc -l <"$file_ledger")" -eq 3 ]
  [ "$(wc -l <"$suite_ledger")" -eq 3 ]
  file_snapshot="$(find "$TMPROOT/logs" -name 'legacy-file.tsv.pre-schema-*.snapshot')"
  suite_snapshot="$(find "$TMPROOT/logs" -name 'legacy-suite.tsv.pre-schema-*.snapshot')"
  [ "$(wc -l <"$file_snapshot")" -eq 2 ]
  [ "$(wc -l <"$suite_snapshot")" -eq 2 ]
  [[ "$file_snapshot" == "$TMPROOT/logs/"* ]]
  [[ "$suite_snapshot" == "$TMPROOT/logs/"* ]]
  [ "$(sha256sum "$file_snapshot" | awk '{print $1}')" = "$(basename "${file_snapshot%.snapshot}" | sed 's/^legacy-file.tsv.pre-schema-//')" ]
  [ "$(sha256sum "$suite_snapshot" | awk '{print $1}')" = "$(basename "${suite_snapshot%.snapshot}" | sed 's/^legacy-suite.tsv.pre-schema-//')" ]
  awk -F'\t' 'NR==2 {exit !($1=="old" && NF==15 && $15=="")} NR==3 {exit !($1=="new" && $15!="")}' "$file_ledger"
  awk -F'\t' 'NR==2 {exit !($1=="old" && NF==11 && $11=="")} NR==3 {exit !($1=="new" && $11!="")}' "$suite_ledger"
}

# test_necessity: schema migration must preserve the old ledger byte-for-byte
# when snapshot creation, hash verification, row verification, or schema recognition fails.
@test "timing ledger migration snapshot guard fails closed in four adversarial cells" {
  file_batch="$TMPROOT/file.batch"
  head="$(git -C "$TMPROOT" rev-parse HEAD)"
  sha="$(printf output | sha256sum | cut -d' ' -f1)"
  printf 'new\trepo\t%s\tunit\tbats\tnew.bats\t1\t.1\tpass\t0\t0\tfp\tnow\ttag\n' "$head" >"$file_batch"

  for fault in snapshot_create hash_mismatch row_count_mismatch; do
    ledger="$TMPROOT/logs/${fault}.tsv"
    printf 'run_id\trepo\tcommit_sha\tsuite_root\trunner\ttest_file\ttest_id_count\twall_sec\tstatus\tskip_count\tcache_hit\tsource_fingerprint\tmeasured_at\tresource_tags\nold\trepo\t%s\tunit\tbats\told.bats\t1\t.1\tpass\t0\t0\tfp\tnow\ttag\n' "$head" >"$ledger"
    before="$(sha256sum "$ledger")"
    run env TEST_TIMING_LEDGER="$ledger" TIMING_LEDGER_SNAPSHOT_FAULT="$fault" \
      bash "$TMPROOT/scripts/test_timing_ledger_write.sh" "$file_batch"
    [ "$status" -eq 2 ]
    [ "$(sha256sum "$ledger")" = "$before" ]
  done

  ledger="$TMPROOT/logs/unknown.tsv"
  printf 'unknown\theader\nold\trow\n' >"$ledger"
  before="$(sha256sum "$ledger")"
  run env TEST_TIMING_LEDGER="$ledger" \
    bash "$TMPROOT/scripts/test_timing_ledger_write.sh" "$file_batch"
  [ "$status" -eq 2 ]
  [ "$(sha256sum "$ledger")" = "$before" ]
  [ "$(find "$TMPROOT/logs" -name '*.snapshot' | wc -l)" -eq 0 ]
  [ -n "$sha" ]
}

# test_necessity: 同一commit/source fingerprintの並行runでもrun_id+output hashを
# 含む4点完全一致だけを結合し、途中失敗・欠損・suite重複をsuccess序列から除外する。
@test "four-identity join prevents cross-run joins and excludes failed or partial runs" {
  head="$(git -C "$TMPROOT" rev-parse HEAD)"
  fp="$(printf source | sha256sum | cut -d' ' -f1)"
  out1="$(printf output-1 | sha256sum | cut -d' ' -f1)"
  out2="$(printf output-2 | sha256sum | cut -d' ' -f1)"
  file_ledger="$TMPROOT/logs/file.tsv"; suite_ledger="$TMPROOT/logs/suite.tsv"
  printf 'run_id\trepo\tcommit_sha\tsuite_root\trunner\ttest_file\ttest_id_count\twall_sec\tstatus\tskip_count\tcache_hit\tsource_fingerprint\tmeasured_at\tresource_tags\toutput_sha256\n' >"$file_ledger"
  printf 'run_id\trepo\tcommit_sha\tmode\tsuite_wall_sec\tsum_file_sec\tfile_count\tstatus\tsource_fingerprint\tmeasured_at\toutput_sha256\n' >"$suite_ledger"
  printf 'run-1\trepo\t%s\tunit\tbats\ta.bats\t1\t.1\tpass\t0\t0\t%s\tnow\ttag\t%s\n' "$head" "$fp" "$out1" >>"$file_ledger"
  printf 'run-2\trepo\t%s\tunit\tbats\ta.bats\t1\t.1\tpass\t0\t1\t%s\tnow\ttag\t%s\n' "$head" "$fp" "$out2" >>"$file_ledger"
  printf 'run-1\trepo\t%s\tunit\t.1\t.1\t1\tpass\t%s\tnow\t%s\n' "$head" "$fp" "$out1" >>"$suite_ledger"
  printf 'run-2\trepo\t%s\tunit\t.1\t.1\t1\tpass\t%s\tnow\t%s\n' "$head" "$fp" "$out2" >>"$suite_ledger"
  for n in 1 2; do
    out_var="out$n"; out="${!out_var}"
    python3 - "$TMPROOT/logs/r$n.json" "run-$n" "$head" "$fp" "$out" <<'PY'
import json,sys
p,r,h,f,o=sys.argv[1:]
json.dump({"run_id":r,"commit_sha":h,
 "source_fingerprint":f,"output_sha256":o,"result":"PASS","rc":0,"complete":True},open(p,"w"))
PY
    run env REPO_ROOT="$TMPROOT" bash -c 'source "$1/scripts/run_tests.sh"; validate_run_identity_join "$2" "$3" "$4"' _ \
      "$TMPROOT" "$TMPROOT/logs/r$n.json" "$file_ledger" "$suite_ledger"
    [ "$status" -eq 0 ]
  done

  python3 - "$TMPROOT/logs/r1.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["result"]="FAIL"; d["rc"]=1; json.dump(d,open(p,"w"))
PY
  run env REPO_ROOT="$TMPROOT" bash -c 'source "$1/scripts/run_tests.sh"; validate_run_identity_join "$2" "$3" "$4"' _ \
    "$TMPROOT" "$TMPROOT/logs/r1.json" "$file_ledger" "$suite_ledger"
  [ "$status" -ne 0 ]

  sed -i '/^run-2\t/d' "$suite_ledger"
  run env REPO_ROOT="$TMPROOT" bash -c 'source "$1/scripts/run_tests.sh"; validate_run_identity_join "$2" "$3" "$4"' _ \
    "$TMPROOT" "$TMPROOT/logs/r2.json" "$file_ledger" "$suite_ledger"
  [ "$status" -ne 0 ]
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

# test_necessity: the 281-case completion-gate contract must retain its measured
# four-job scheduler override so canonical pre-push cannot regress above 240s.
# regression_justification: serial execution reached rc124 at both 300s and
# 240s, while the same 281 cases completed 281/281 with SKIP0 in 201.085s at 4 jobs.
@test "completion gate contract receives four inner jobs without raising the host budget" {
  printf '@test "sample" { true; }\n' >"$TMPROOT/tests/unit/test_cmd_complete_gate.bats"
  export BATS_ARGS_LOG="$TMPROOT/bats.args"
  export BATS_SCHEDULER_TRACE="$TMPROOT/schedule.tsv"
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$BATS_ARGS_LOG"
printf '1..1\nok 1 sample\n'
SH
  chmod +x "$TMPROOT/bin/bats"

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" \
    BATS_ARGS_LOG="$BATS_ARGS_LOG" BATS_SCHEDULER_TRACE="$BATS_SCHEDULER_TRACE" \
    BATS_CACHE=0 BATS_INNER_JOBS=1 BATS_MAX_TEST_JOBS=8 bash -c '
      source "$1/scripts/run_tests.sh"
      run_bats_files_parallel "$1/tests/unit/test_cmd_complete_gate.bats"
  ' _ "$TMPROOT"

  [ "$status" -eq 0 ]
  grep -Fq -- '--jobs 4' "$BATS_ARGS_LOG"
  awk -F '\t' '$1=="test_cmd_complete_gate.bats" {found=1; if ($2!=4 || $3!=0) bad=1} END {exit !(found && !bad)}' "$BATS_SCHEDULER_TRACE"
}

@test "timing-regressed shared-resource fixtures receive the full aggregate weight" {
  for name in test_hook_dispatchers test_statusline test_sqlite3_cli_removal test_small_workflow_consolidated test_skill_recommend_metrics test_insight_write test_shogun_cli_switch_probe; do
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
        "$1/tests/unit/test_skill_recommend_metrics.bats" \
        "$1/tests/unit/test_insight_write.bats" \
        "$1/tests/unit/test_shogun_cli_switch_probe.bats"
    ' _ "$TMPROOT"

  [ "$status" -eq 0 ]
  [ "$(wc -l <"$BATS_SCHEDULER_TRACE")" -eq 7 ]
  [ "$(awk -F '\t' '$2 == 8 {count++} END {print count+0}' "$BATS_SCHEDULER_TRACE")" -eq 7 ]
  [ "$(awk -F '\t' '$3 == 0 {count++} END {print count+0}' "$BATS_SCHEDULER_TRACE")" -eq 7 ]
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

  grep -Eq '(export )?BATS_INNER_JOBS=1' "$workflow"
  grep -Eq '(export )?BATS_FILE_TIMEOUT_SECONDS=300' "$workflow"
  grep -Fq 'timeout-minutes: 12' "$workflow"
  grep -Fq 'group: test-${{ github.workflow }}-${{ github.ref }}' "$workflow"
  grep -Fq 'cancel-in-progress: false' "$workflow"
  grep -Fq '0.1.0 (Codex)' "$workflow"
  grep -Fq 'GITHUB_PATH' "$workflow"
  ! grep -Eq '(export )?BATS_INNER_JOBS=8' "$workflow"
  grep -Fq 'bash scripts/run_tests.sh push' "$workflow"
}

# test_necessity: CI shard assignment must consume the shared inventory/ledger
# planner so new zero-weight files are assigned exactly once and empty shards
# fail closed instead of becoming false-success jobs.
@test "CI shard assignment uses universal planner and rejects empty shards" {
  workflow="$ROOT/.github/workflows/test.yml"

  grep -Fq 'scripts/universal_shard.py' "$workflow"
  grep -Fq 'SHARD_INVENTORY' "$workflow"
  grep -Fq 'zero-assignment shard forbidden' "$workflow"
  grep -Fq 'measured": path not in missing_from_ledger' "$workflow"
  ! grep -Fq 'buckets = [(0.0, index, []) for index in range(shard_count)]' "$workflow"
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

# test_necessity: a directly invoked copied runner must execute only the
# fixture-local suite even when the caller exports the control repository as
# REPO_ROOT and keeps cwd there.
@test "direct fixture runner pins suite discovery to its own script root" {
  fixture="$TMPROOT/fixture-runner"
  mkdir -p "$fixture/tests/unit" "$fixture/scripts" "$fixture/logs/receipts"
  cp "$ROOT/scripts/run_tests.sh" "$ROOT/scripts/run_with_receipt.sh" \
    "$ROOT/scripts/heavy_job_admission.sh" "$ROOT/scripts/test_timing_ledger_write.sh" \
    "$ROOT/scripts/test_suite_timing_ledger_write.sh" "$fixture/scripts/"
  printf '@test "fixture-only" { true; }\n' >"$fixture/tests/unit/sample.bats"
  git -C "$fixture" init -q
  git -C "$fixture" config user.email test@example.com
  git -C "$fixture" config user.name test
  git -C "$fixture" add .
  git -C "$fixture" commit -qm initial
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$BATS_ARGS_LOG"
printf '1..1\nok 1 fixture-only\n'
SH
  chmod +x "$TMPROOT/bin/bats"

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" BATS_ARGS_LOG="$TMPROOT/bats.args" \
    RUN_TESTS_RECEIPT_DIR="$fixture/logs/receipts" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    BATS_CACHE=0 BATS_INNER_JOBS=1 bash -c 'cd "$1" && bash "$1/scripts/run_tests.sh" unit' _ "$fixture"

  [ "$status" -eq 0 ]
  [ "$(wc -l <"$TMPROOT/bats.args")" -eq 1 ]
  grep -Fxq "$fixture/tests/unit/sample.bats" "$TMPROOT/bats.args"
  receipt="$(find "$fixture/logs/receipts" -name '*.json' -type f | head -1)"
  [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["observed_test_count"])' "$receipt")" -eq 1 ]
}

# test_necessity: external TERM against run_tests.sh must drain a child bats
# process and its descendant before the wrapper returns.
@test "external TERM drains direct runner descendants" {
  fixture="$TMPROOT/term-runner"
  mkdir -p "$fixture/tests/unit" "$fixture/scripts" "$fixture/logs/receipts"
  cp "$ROOT/scripts/run_tests.sh" "$ROOT/scripts/run_with_receipt.sh" \
    "$ROOT/scripts/heavy_job_admission.sh" "$ROOT/scripts/test_timing_ledger_write.sh" \
    "$ROOT/scripts/test_suite_timing_ledger_write.sh" "$fixture/scripts/"
  printf '@test "term" { true; }\n' >"$fixture/tests/unit/sample.bats"
  git -C "$fixture" init -q
  git -C "$fixture" config user.email test@example.com
  git -C "$fixture" config user.name test
  git -C "$fixture" add .
  git -C "$fixture" commit -qm initial
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
(sleep 30) &
printf '%s\n' "$!" >"$CHILD_PID_FILE"
sleep 30
SH
  chmod +x "$TMPROOT/bin/bats"

  run timeout --signal=TERM --kill-after=5 1 env PATH="$TMPROOT/bin:$PATH" \
    CHILD_PID_FILE="$TMPROOT/term-child.pid" REPO_ROOT="$TMPROOT" BATS_CACHE=0 \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 RUN_TESTS_RECEIPT_DIR="$fixture/logs/receipts" \
    bash "$fixture/scripts/run_tests.sh" file "$fixture/tests/unit/sample.bats"

  [ "$status" -ne 0 ]
  child_pid="$(cat "$TMPROOT/term-child.pid")"
  ! ps -p "$child_pid" -o stat= | awk '$1 !~ /^Z/ { found=1 } END { exit found ? 0 : 1 }'
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

# test_necessity: affected selections must use suffix-owned engines so a Python
# contract cannot be sent to Bats and mixed selections cannot lose either lane.
# regression_justification: overlaps_existing=true; existing coverage exercised
# affected scheduling only with Bats paths and did not cover mixed engines.
@test "affected mode dispatches Python, Bats, and mixed selections once per engine" {
  printf 'def test_owned():\n    assert True\n' >"$TMPROOT/tests/unit/owned.py"
  printf '@test "owned" { true; }\n' >"$TMPROOT/tests/unit/owned.bats"
  export ENGINE_LOG="$TMPROOT/affected-engine.log"
  export REAL_PYTHON3="$(command -v python3)"
  cat >"$TMPROOT/scripts/test_select.sh" <<'SH'
#!/usr/bin/env bash
case "$SELECTION" in
  python) printf '%s\n' "$REPO_ROOT/tests/unit/owned.py" ;;
  bats) printf '%s\n' "$REPO_ROOT/tests/unit/owned.bats" ;;
  mixed)
    printf '%s\n' "$REPO_ROOT/tests/unit/owned.py"
    printf '%s\n' "$REPO_ROOT/tests/unit/owned.bats"
    ;;
esac
SH
  cat >"$TMPROOT/bin/python3" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == -m && "${2:-}" == pytest ]]; then
  printf 'pytest:%s\n' "$*" >>"$ENGINE_LOG"
  printf '1 passed in 0.01s\n'
  exit 0
fi
exec "$REAL_PYTHON3" "$@"
SH
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf 'bats:%s\n' "$*" >>"$ENGINE_LOG"
printf '1..1\nok 1 owned\n'
SH
  chmod +x "$TMPROOT/scripts/test_select.sh" "$TMPROOT/bin/python3" "$TMPROOT/bin/bats"

  for selection in python bats mixed; do
    : >"$ENGINE_LOG"
    run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" SELECTION="$selection" \
      ENGINE_LOG="$ENGINE_LOG" REAL_PYTHON3="$REAL_PYTHON3" \
      SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 BATS_MAX_TEST_JOBS=1 \
      bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner affected changed.file
    [ "$status" -eq 0 ]
    pytest_count=0
    bats_count=0
    [[ "$selection" != bats ]] && pytest_count=1
    [[ "$selection" != python ]] && bats_count=1
    [ "$(grep -c '^pytest:' "$ENGINE_LOG" || true)" -eq "$pytest_count" ]
    [ "$(grep -c '^bats:' "$ENGINE_LOG" || true)" -eq "$bats_count" ]
  done
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

# test_necessity: affected mode with non-empty selector records selection rationale (git_diff_changed_files) in the receipt so ninjas can compare iterative vs full duration_ms without re-running.
@test "affected nonempty selection records git_diff_changed_files rationale in receipt" {
  printf '@test "dummy" { true; }\n' >"$TMPROOT/tests/unit/dummy.bats"
  cat >"$TMPROOT/scripts/test_select.sh" <<'SH'
#!/usr/bin/env bash
printf '%s/tests/unit/dummy.bats\n' "$REPO_ROOT"
SH
  cat >"$TMPROOT/scripts/heavy_job_admission.sh" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" != "--" ] || shift
SHOGUN_HEAVY_JOB_LOCK_HELD=1 exec "$@"
SH
  chmod +x "$TMPROOT/scripts/test_select.sh" "$TMPROOT/scripts/heavy_job_admission.sh"

  run env -u SHOGUN_HEAVY_JOB_LOCK_HELD -u SHOGUN_HEAVY_JOB_ADMITTED \
    PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" \
    RUN_TESTS_RECEIPT_DIR="$TMPROOT/logs/test_receipts" \
    BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" affected

  [ "$status" -eq 0 ]
  receipt=$(python3 - "$TMPROOT/logs/test_receipts" <<'PY'
import glob,json,os,sys
receipts=sorted(glob.glob(os.path.join(sys.argv[1],'run_tests_*.json')),key=os.path.getmtime)
if receipts: print(receipts[-1])
PY
  )
  [ -n "$receipt" ]
  run python3 - "$receipt" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
reason=d.get('run_manifest',{}).get('estimated_cost',{}).get('selection_reason','')
assert reason == 'git_diff_changed_files', f'expected git_diff_changed_files got {reason!r}'
PY
  [ "$status" -eq 0 ]
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
  printf '@test "owned" { true; }\n' >"$TMPROOT/tests/unit/owned.bats"
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
  test_path: tests/unit/owned.bats
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
  [[ "$output" == *"TEST_SELECTION_REASON direct=1 transitive=0 source=task_explicit_contract"* ]]
  [ ! -e "$SELECT_ARGS_LOG" ]
}

# test_necessity: test_necessity is an explanatory contract, not a test path;
# natural-language descriptions must not fail task selection, while an
# explicit test_path must remain a direct execution request.
@test "task test_necessity description is excluded while explicit test_path remains selected" {
  mkdir -p "$TMPROOT/queue/tasks"
  cat >"$TMPROOT/scripts/test_select.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$TMPROOT/scripts/test_select.sh"

  cat >"$TMPROOT/queue/tasks/natural-language.yaml" <<'YAML'
task:
  task_id: natural-language-contract
  target_path: scripts/run_tests.sh
  test_necessity: "select the owned contract test only; do not treat this explanation as a filesystem path"
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/natural-language.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_SCOPE result=task files=1"* ]]
  [[ "$output" == *"TEST_SELECTION_REASON direct=0 transitive=0 source=dependency_map"* ]]
  [[ "$output" == *"TEST_SELECTION result=selected reason=task_scope_no_mapped_tests files=0"* ]]
  [[ "$output" != *"explicit test path has no supported engine"* ]]

  printf '@test "owned" { true; }\n' >"$TMPROOT/tests/unit/owned.bats"
  cat >"$TMPROOT/queue/tasks/explicit-path.yaml" <<'YAML'
task:
  task_id: explicit-path-contract
  target_path: scripts/run_tests.sh
  test_path: tests/unit/owned.bats
  test_necessity: "the explicit path above is the persistent contract test"
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/explicit-path.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_SELECTION_REASON direct=1 transitive=0 source=task_explicit_contract"* ]]
  [[ "$output" == *"TEST_SELECTION result=selected reason=task_scope files=1"* ]]
}

# test_necessity: terminal task receipts must carry the task YAML identity for
# report autolinking, while file-mode receipts must remain task-agnostic.
@test "task receipt carries task_id and non-task receipt omits it" {
  printf '@test "owned" { true; }\n' >"$TMPROOT/tests/unit/owned.bats"
  mkdir -p "$TMPROOT/queue/tasks" "$TMPROOT/task-receipts" "$TMPROOT/file-receipts"
  cat >"$TMPROOT/queue/tasks/owned.yaml" <<'YAML'
task:
  task_id: task-owned-receipt
  test_path: tests/unit/owned.bats
YAML
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '1..1\nok 1 owned\n'
SH
  chmod +x "$TMPROOT/bin/bats"

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" \
    RUN_TESTS_RECEIPT_DIR="$TMPROOT/task-receipts" BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" task "$TMPROOT/queue/tasks/owned.yaml"
  [ "$status" -eq 0 ]
  task_receipt="$(find "$TMPROOT/task-receipts" -name '*.json' -type f | head -1)"
  [ -n "$task_receipt" ]
  recorded_task_receipt="$(python3 - "$TMPROOT/queue/tasks/owned.yaml" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))['task']
print(task.get('test_receipt_path', ''))
PY
)"
  [ "$recorded_task_receipt" = "$(realpath "$task_receipt")" ]
  run python3 - "$task_receipt" <<'PY'
import json, sys
receipt = json.load(open(sys.argv[1], encoding='utf-8'))
assert receipt['task_id'] == 'task-owned-receipt', receipt
assert receipt['rc'] == 0, receipt
PY
  [ "$status" -eq 0 ]

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" \
    RUN_TESTS_RECEIPT_DIR="$TMPROOT/file-receipts" \
    BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" file "$TMPROOT/tests/unit/owned.bats"
  [ "$status" -eq 0 ]
  file_receipt="$(find "$TMPROOT/file-receipts" -name '*.json' -type f | head -1)"
  [ -n "$file_receipt" ]
  recorded_after_file="$(python3 - "$TMPROOT/queue/tasks/owned.yaml" <<'PY'
import sys, yaml
task = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))['task']
print(task.get('test_receipt_path', ''))
PY
)"
  [ "$recorded_after_file" = "$(realpath "$task_receipt")" ]
  run python3 - "$file_receipt" <<'PY'
import json, sys
receipt = json.load(open(sys.argv[1], encoding='utf-8'))
assert 'task_id' not in receipt, receipt
assert receipt['rc'] == 0, receipt
PY
  [ "$status" -eq 0 ]
}

# test_necessity: task-mode selected paths must reach their suffix-owned engine
# exactly once; missing and unowned suffixes must fail closed before execution.
@test "task mode dispatches Python Bats and mixed paths once and rejects unknown or missing" {
  mkdir -p "$TMPROOT/queue/tasks"
  printf 'def test_ok():\n    assert True\n' >"$TMPROOT/tests/unit/owned.py"
  printf '@test "owned" { true; }\n' >"$TMPROOT/tests/unit/owned.bats"
  printf 'not a test\n' >"$TMPROOT/tests/unit/owned.txt"
  export ENGINE_LOG="$TMPROOT/engine.log"
  export REAL_PYTHON3="$(command -v python3)"
  cat >"$TMPROOT/bin/python3" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == -m && "${2:-}" == pytest ]]; then
  printf 'pytest:%s\n' "$*" >>"$ENGINE_LOG"
  printf '1 passed in 0.01s\n'
  exit 0
fi
exec "$REAL_PYTHON3" "$@"
SH
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf 'bats:%s\n' "$*" >>"$ENGINE_LOG"
printf '1..1\nok 1 owned\n'
SH
  chmod +x "$TMPROOT/bin/python3" "$TMPROOT/bin/bats"

  for fixture in python bats mixed unknown missing; do
    case "$fixture" in
      python) paths='[tests/unit/owned.py]' ;;
      bats) paths='[tests/unit/owned.bats]' ;;
      mixed) paths='[tests/unit/owned.py, tests/unit/owned.bats]' ;;
      unknown) paths='[tests/unit/owned.txt]' ;;
      missing) paths='[tests/unit/missing.py]' ;;
    esac
    printf 'task:\n  test_path: %s\n' "$paths" >"$TMPROOT/queue/tasks/$fixture.yaml"
  done

  for fixture in python bats mixed; do
    : >"$ENGINE_LOG"
    run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" ENGINE_LOG="$ENGINE_LOG" REAL_PYTHON3="$REAL_PYTHON3" \
      SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
      bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/$fixture.yaml"
    [ "$status" -eq 0 ]
    [ "$(grep -c '^pytest:' "$ENGINE_LOG")" -eq "$([ "$fixture" = bats ] && echo 0 || echo 1)" ]
    [ "$(grep -c '^bats:' "$ENGINE_LOG")" -eq "$([ "$fixture" = python ] && echo 0 || echo 1)" ]
  done

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" ENGINE_LOG="$ENGINE_LOG" REAL_PYTHON3="$REAL_PYTHON3" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/unknown.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no task test engine for suffix"* ]]

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" ENGINE_LOG="$ENGINE_LOG" REAL_PYTHON3="$REAL_PYTHON3" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/missing.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK: explicit task tests could not be resolved"* ]]

  receipt_dir="$TMPROOT/logs/mixed-receipt"
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" ENGINE_LOG="$ENGINE_LOG" REAL_PYTHON3="$REAL_PYTHON3" \
    RUN_TESTS_RECEIPT_DIR="$receipt_dir" BATS_TAP_OUTPUT="$TMPROOT/mixed.tap" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" task "$TMPROOT/queue/tasks/mixed.yaml"
  [ "$status" -eq 0 ]
  receipt="$(find "$receipt_dir" -name '*.json' -type f | head -1)"
  run "$REAL_PYTHON3" - "$receipt" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
s = d["run_manifest"]["scope_identity"]
assert d["declared_test_count"] == d["observed_test_count"] == 2, d
assert s["selected_file_count"] == s["executed_file_count"] == 2, s
assert d["skip_count"] == 0, d
PY
  [ "$status" -eq 0 ]
  tap="${receipt%.json}.tap"
  [ "$(grep -c '^1..1$' "$tap")" -eq 2 ]

  receipt_dir="$TMPROOT/logs/python-receipt"
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" ENGINE_LOG="$ENGINE_LOG" REAL_PYTHON3="$REAL_PYTHON3" \
    RUN_TESTS_RECEIPT_DIR="$receipt_dir" SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" task "$TMPROOT/queue/tasks/python.yaml"
  [ "$status" -eq 0 ]
  receipt="$(find "$receipt_dir" -name '*.json' -type f | head -1)"
  run "$REAL_PYTHON3" - "$receipt" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
s = d["run_manifest"]["scope_identity"]
assert d["rc"] == 0, d
assert d["declared_test_count"] == d["observed_test_count"] == 1, d
assert s["selected_file_count"] == s["executed_file_count"] == 1, s
PY
  [ "$status" -eq 0 ]
}

# test_necessity: A frozen task selection must execute every selected file and
# publish exactly one terminal receipt whose rc matches PASS, FAIL, or BLOCK.
@test "task runner completes all nine selected files and emits one rc-matched terminal receipt" {
  mkdir -p "$TMPROOT/queue/tasks"
  for n in $(seq 1 9); do
    printf '@test "owned-%s" { true; }\n' "$n" >"$TMPROOT/tests/unit/owned-$n.bats"
  done
  cat >"$TMPROOT/queue/tasks/nine.yaml" <<'YAML'
task:
  test_path:
    - tests/unit/owned-1.bats
    - tests/unit/owned-2.bats
    - tests/unit/owned-3.bats
    - tests/unit/owned-4.bats
    - tests/unit/owned-5.bats
    - tests/unit/owned-6.bats
    - tests/unit/owned-7.bats
    - tests/unit/owned-8.bats
    - tests/unit/owned-9.bats
YAML
  export ENGINE_LOG="$TMPROOT/engine.log"
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$ENGINE_LOG"
printf '1..1\nok 1 owned\n'
SH
  chmod +x "$TMPROOT/bin/bats"

  for outcome in pass fail; do
    : >"$ENGINE_LOG"
    receipt_dir="$TMPROOT/receipts-$outcome"
    if [ "$outcome" = fail ]; then
      cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" >>"$ENGINE_LOG"
if [[ "$1" == *owned-1.bats ]]; then
  printf '1..1\nnot ok 1 owned\n'
  exit 7
fi
printf '1..1\nok 1 owned\n'
SH
      chmod +x "$TMPROOT/bin/bats"
    fi
    run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" ENGINE_LOG="$ENGINE_LOG" \
      RUN_TESTS_RECEIPT_DIR="$receipt_dir" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
      BATS_CACHE=0 BATS_INNER_JOBS=1 BATS_MAX_TEST_JOBS=2 \
      bash "$TMPROOT/scripts/run_tests.sh" task "$TMPROOT/queue/tasks/nine.yaml"
    expected_rc=0
    [ "$outcome" = pass ] || expected_rc=7
    [ "$status" -eq "$expected_rc" ]
    [ "$(wc -l <"$ENGINE_LOG")" -eq 9 ]
    [ "$(find "$receipt_dir" -name '*.json' -type f | wc -l)" -eq 1 ]
    receipt="$(find "$receipt_dir" -name '*.json' -type f)"
    [ "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["rc"], d["run_manifest"]["scope_identity"]["selected_file_count"], d["run_manifest"]["scope_identity"]["executed_file_count"])' "$receipt")" = "$expected_rc 9 9" ]
  done

  : >"$ENGINE_LOG"
  cat >"$TMPROOT/queue/tasks/zero.yaml" <<'YAML'
task:
  target_path: scripts/unmapped.sh
YAML
  cat >"$TMPROOT/scripts/test_select.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$TMPROOT/scripts/test_select.sh"
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" ENGINE_LOG="$ENGINE_LOG" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" task "$TMPROOT/queue/tasks/zero.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"files=0"* ]]
  [ ! -s "$ENGINE_LOG" ]

  printf 'task:\n  test_path: [tests/unit/missing.bats]\n' >"$TMPROOT/queue/tasks/invalid.yaml"
  invalid_receipts="$TMPROOT/receipts-invalid"
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" ENGINE_LOG="$ENGINE_LOG" \
    RUN_TESTS_RECEIPT_DIR="$invalid_receipts" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" task "$TMPROOT/queue/tasks/invalid.yaml"
  [ "$status" -eq 2 ]
  [ "$(find "$invalid_receipts" -name '*.json' -type f | wc -l)" -eq 1 ]
  receipt="$(find "$invalid_receipts" -name '*.json' -type f)"
  [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["rc"])' "$receipt")" -eq 2 ]
}

# test_necessity: Task selector must classify tests by path/extension contract;
# production scripts named test_*.sh are sources, never direct Bats targets.
@test "task mode excludes test-prefixed production shell scripts from direct tests" {
  mkdir -p "$TMPROOT/queue/tasks"
  export BATS_ARGS_LOG="$TMPROOT/bats.args"
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BATS_ARGS_LOG"
printf '1..1\nok 1 selector-contract\n'
SH
  chmod +x "$TMPROOT/bin/bats"
  cat >"$TMPROOT/scripts/test_select.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$REPO_ROOT/tests/unit/test_run_tests.bats"
SH
  chmod +x "$TMPROOT/scripts/test_select.sh"
  cat >"$TMPROOT/queue/tasks/tobisaru.yaml" <<'YAML'
task:
  files_modified:
    - scripts/test_timing_ledger_write.sh
    - scripts/test_suite_timing_ledger_write.sh
    - tests/unit/test_run_tests.bats
YAML

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" BATS_ARGS_LOG="$BATS_ARGS_LOG" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/tobisaru.yaml"

  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_SCOPE result=task files=3"* ]]
  [[ "$output" == *"TEST_SELECTION_REASON direct=1 transitive=0 source=task_explicit_contract"* ]]
  [ "$(wc -l <"$BATS_ARGS_LOG")" -eq 1 ]
  grep -Fq "test_run_tests.bats" "$BATS_ARGS_LOG"
  ! grep -Fq "test_timing_ledger_write.sh" "$BATS_ARGS_LOG"
  ! grep -Fq "test_suite_timing_ledger_write.sh" "$BATS_ARGS_LOG"
  echo "FIXTURE_METRICS selected=1 expected=1 false_positive=0 excluded_production=2"
}

# test_necessity: inferred commit_contract tests are ownership metadata, not
# direct execution requests; one explicit test_path must remain one selected
# file even when deployment inferred a 947-file test scope.
@test "task mode does not promote inferred planned tests to explicit execution" {
  printf '@test "owned" { true; }\n' >"$TMPROOT/tests/unit/owned.bats"
  mkdir -p "$TMPROOT/queue/tasks"
  {
    printf '%s\n' 'task:' '  target_path: scripts/run_tests.sh' \
      '  test_path: tests/unit/owned.bats' '  commit_contract:' \
      '    planned_paths:' '      - scripts/run_tests.sh'
    for i in $(seq 1 947); do
      printf '      - tests/unit/inferred_%04d.bats\n' "$i"
    done
  } >"$TMPROOT/queue/tasks/inferred.yaml"
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '1..1\nok 1 explicit-only\n'
SH
  chmod +x "$TMPROOT/bin/bats"

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/inferred.yaml"

  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_SCOPE result=task files=949"* ]]
  [[ "$output" == *"TEST_SELECTION_REASON direct=1 transitive=0 source=task_explicit_contract"* ]]
  [[ "$output" == *"PASS: 1 bats file(s)"* ]]
  [[ "$output" != *"inferred_0001.bats"* ]]
}

# test_necessity: A task-owned real test must always execute directly and must
# not disappear when a sibling source path lacks a dependency mapping; inferred
# tests remain behind the dependency-map boundary.
# regression_justification: overlaps_existing=true; existing explicit-contract
# coverage did not exercise a directly owned test mixed with an unmapped source.
@test "test-only task selects its complete scope without promoting mixed planned tests" {
  printf '@test "owned" { true; }\n' >"$TMPROOT/tests/unit/owned.bats"
  printf '@test "inferred" { true; }\n' >"$TMPROOT/tests/unit/inferred.bats"
  mkdir -p "$TMPROOT/queue/tasks"
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BATS_ARGS_LOG"
printf '1..1\nok 1 selected\n'
SH
  cat >"$TMPROOT/scripts/test_select.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$SELECT_ARGS_LOG"
SH
  chmod +x "$TMPROOT/bin/bats" "$TMPROOT/scripts/test_select.sh"
  cat >"$TMPROOT/queue/tasks/test-only.yaml" <<'YAML'
task:
  target_path:
    - tests/unit/owned.bats
    - tests/unit/inferred.bats
YAML
  cat >"$TMPROOT/queue/tasks/mixed.yaml" <<'YAML'
task:
  target_path:
    - tests/unit/owned.bats
    - scripts/unmapped.sh
YAML
  export BATS_ARGS_LOG="$TMPROOT/bats.args"
  export SELECT_ARGS_LOG="$TMPROOT/selector.args"

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" BATS_ARGS_LOG="$BATS_ARGS_LOG" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/test-only.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_SELECTION_REASON direct=2 transitive=0 source=task_test_only_scope"* ]]
  [ "$(wc -l <"$BATS_ARGS_LOG")" -eq 2 ]
  [ ! -e "$SELECT_ARGS_LOG" ]

  : >"$BATS_ARGS_LOG"
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" BATS_ARGS_LOG="$BATS_ARGS_LOG" \
    SELECT_ARGS_LOG="$SELECT_ARGS_LOG" SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/mixed.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_SELECTION_REASON direct=1 transitive=0 source=dependency_map"* ]]
  grep -Fxq "scripts/unmapped.sh" "$SELECT_ARGS_LOG"
  [ "$(wc -l <"$BATS_ARGS_LOG")" -eq 1 ]
  grep -Fq "owned.bats" "$BATS_ARGS_LOG"
  ! grep -Fq "inferred.bats" "$BATS_ARGS_LOG"
}

# test_necessity: 個別external backend taskが暗黙に全pytestへ拡大せず、
# 明示contractだけを選び、fixed-SHA wave最終checkpointだけが全量を許可される
# 三分岐の実行境界を守る。
@test "external backend task selects one nearby module test without a contract" {
  external="$TMPROOT/external-nearby"
  mkdir -p "$external/backend/tests" "$external/backend/app" \
    "$TMPROOT/projects" "$TMPROOT/queue/tasks"
  printf 'VALUE = 1\n' >"$external/backend/app/source.py"
  printf 'def test_source():\n    assert True\n' >"$external/backend/tests/test_source.py"
  printf 'def test_other():\n    assert True\n' >"$external/backend/tests/test_other.py"
  git -C "$external" init -q
  git -C "$external" config user.email test@example.invalid
  git -C "$external" config user.name test
  git -C "$external" add backend
  git -C "$external" commit -qm init
  export PYTEST_ARGS_LOG="$TMPROOT/nearby-pytest-args.log"
  cat >"$TMPROOT/bin/python3" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == -m && "${2:-}" == pytest ]]; then
  printf '%s\n' "$*" >>"$PYTEST_ARGS_LOG"
  printf '1 passed in 0.01s\n'
  exit 0
fi
exec /usr/bin/python3 "$@"
SH
  chmod +x "$TMPROOT/bin/python3"
  cat >"$TMPROOT/projects/external-nearby.yaml" <<YAML
project:
  path: $external
YAML
  cat >"$TMPROOT/queue/tasks/nearby.yaml" <<'YAML'
task:
  task_id: nearby
  project: external-nearby
  planned_paths: [backend/app/source.py]
YAML

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/nearby.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_SELECTION result=external runner=pytest scope=backend_nearby project_root=$external files=1"* ]]
  [[ "$output" != *"backend_contract"* ]]
  [[ "$output" != *"backend_full_unit_checkpoint"* ]]
  grep -Fq -- "tests/test_source.py" "$PYTEST_ARGS_LOG"
  ! grep -Fq -- "tests/test_other.py" "$PYTEST_ARGS_LOG"
}

@test "external backend task without nearby module test preserves the BLOCK" {
  external="$TMPROOT/external-no-nearby"
  mkdir -p "$external/backend/tests" "$external/backend/app" \
    "$TMPROOT/projects" "$TMPROOT/queue/tasks" "$TMPROOT/logs"
  printf 'VALUE = 1\n' >"$external/backend/app/missing.py"
  printf 'def test_other():\n    assert True\n' >"$external/backend/tests/test_other.py"
  git -C "$external" init -q
  git -C "$external" config user.email test@example.invalid
  git -C "$external" config user.name test
  git -C "$external" add backend
  git -C "$external" commit -qm init
  cat >"$TMPROOT/projects/external-no-nearby.yaml" <<YAML
project:
  path: $external
YAML
  cat >"$TMPROOT/queue/tasks/no-nearby.yaml" <<'YAML'
task:
  task_id: no-nearby
  project: external-no-nearby
  planned_paths: [backend/app/missing.py]
YAML

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" LOG_DIR="$TMPROOT/logs" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/no-nearby.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK: external backend task has no explicit contract tests"* ]]
  [[ "$output" != *"scope=backend_nearby"* ]]
}

@test "external backend task blocks implicit full unit and preserves explicit contract and checkpoint" {
  external="$TMPROOT/external"
  mkdir -p "$external/backend/tests" "$external/backend/app" \
    "$TMPROOT/projects" "$TMPROOT/queue/tasks" "$TMPROOT/logs"
  cat >"$TMPROOT/bin/python3" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == -m && "${2:-}" == pytest ]]; then
  printf '%s|%s\n' "$PWD" "${PYTHONPATH:-}" >>"$PYTEST_ENV_LOG"
  printf '1 passed in 0.01s\n'
  exit 0
fi
exec /usr/bin/python3 "$@"
SH
  chmod +x "$TMPROOT/bin/python3"
  printf 'VALUE = 1\n' >"$external/backend/app/source.py"
  printf 'def test_scope():\n    assert True\n' >"$external/backend/tests/test_scope.py"
  git -C "$external" init -q
  git -C "$external" config user.email test@example.invalid
  git -C "$external" config user.name test
  git -C "$external" add backend
  git -C "$external" commit -qm init
  external_head="$(git -C "$external" rev-parse HEAD)"
  export PYTEST_ENV_LOG="$TMPROOT/pytest-env.log"
  cat >"$TMPROOT/projects/external.yaml" <<YAML
project:
  path: $external
YAML

  cat >"$TMPROOT/queue/tasks/forbidden.yaml" <<'YAML'
task:
  task_id: forbidden
  project: external
  planned_paths: [backend/app/source.py]
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" LOG_DIR="$TMPROOT/logs" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/forbidden.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK: external backend task has no explicit contract tests"* ]]
  [ "$(grep -c 'gate: \"full_unit_scope_guard\", result: BLOCK' "$TMPROOT/logs/gate_fire_log.yaml")" -eq 1 ]

  cat >"$TMPROOT/queue/tasks/contract.yaml" <<'YAML'
task:
  task_id: contract
  project: external
  planned_paths:
    - backend/app/source.py
    - backend/tests/test_scope.py
  test_path: backend/tests/test_scope.py
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" LOG_DIR="$TMPROOT/logs" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/contract.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"scope=backend_contract"* ]]
  [[ "$output" == *"1 passed"* ]]
  [[ "$output" != *"backend_full_unit_checkpoint"* ]]
  IFS='|' read -r contract_pwd contract_pythonpath <"$PYTEST_ENV_LOG"
  [ "$contract_pwd" = "$external/backend" ]
  [[ ":$contract_pythonpath:" == *":$external:"* ]]

  cat >"$TMPROOT/queue/tasks/checkpoint.yaml" <<YAML
task:
  task_id: checkpoint
  project: external
  planned_paths: [backend/app/source.py]
  test_execution:
    full_unit_checkpoint:
      allowed: true
      wave_final: true
      fixed_sha: $external_head
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" LOG_DIR="$TMPROOT/logs" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/checkpoint.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"scope=backend_full_unit_checkpoint"* ]]
  [[ "$output" == *"1 passed"* ]]
  [ "$(grep -c 'gate: \"full_unit_scope_guard\", result: PASS' "$TMPROOT/logs/gate_fire_log.yaml")" -eq 1 ]
  echo "FIXTURE_METRICS forbidden_executed=0 forbidden_block=1 contract_scope_outside=0 checkpoint_selection_preserved=1 false_positive=0 detector_fp_rate=0/3"
}

# test_necessity: Cross-repository docs/data ownership must still execute one
# explicitly declared backend contract, while absent, escaping, missing, and
# unsupported declarations remain fail-closed instead of becoming 0-test PASS.
@test "external docs scope executes exact explicit contract and rejects invalid declarations" {
  external="$TMPROOT/external-docs"
  mkdir -p "$external/backend/tests" "$external/docs" \
    "$TMPROOT/projects" "$TMPROOT/queue/tasks"
  printf 'evidence\n' >"$external/docs/result.md"
  printf 'def test_scope():\n    assert True\n' >"$external/backend/tests/test_scope.py"
  git -C "$external" init -q
  git -C "$external" config user.email test@example.invalid
  git -C "$external" config user.name test
  git -C "$external" add .
  git -C "$external" commit -qm init
  cat >"$TMPROOT/projects/external-docs.yaml" <<YAML
project:
  path: $external
YAML
  export PYTEST_ARGS_LOG="$TMPROOT/pytest-args.log"
  cat >"$TMPROOT/bin/python3" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == -m && "${2:-}" == pytest ]]; then
  printf '%s\n' "$*" >>"$PYTEST_ARGS_LOG"
  printf '1 passed in 0.01s\n'
  exit 0
fi
exec /usr/bin/python3 "$@"
SH
  chmod +x "$TMPROOT/bin/python3"

  cat >"$TMPROOT/queue/tasks/explicit.yaml" <<'YAML'
task:
  project: external-docs
  target_path: docs/result.md
  test_path: backend/tests/test_scope.py
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" PYTEST_ARGS_LOG="$PYTEST_ARGS_LOG" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/explicit.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"scope=backend_contract"* ]]
  [[ "$output" == *"files=1"* ]]
  [[ "$output" == *"1 passed"* ]]
  [ "$(wc -l <"$PYTEST_ARGS_LOG")" -eq 1 ]
  grep -Fq 'tests/test_scope.py' "$PYTEST_ARGS_LOG"

  cat >"$TMPROOT/queue/tasks/absent.yaml" <<'YAML'
task:
  project: external-docs
  target_path: docs/result.md
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/absent.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"external_scope_no_mapped_tests"* ]]

  for fixture in traversal missing unsupported; do
    case "$fixture" in
      traversal) declared='../outside/test_bad.py' ;;
      missing) declared='backend/tests/test_missing.py' ;;
      unsupported) declared='docs/result.md' ;;
    esac
    printf 'task:\n  project: external-docs\n  target_path: docs/result.md\n  test_path: %s\n' "$declared" \
      >"$TMPROOT/queue/tasks/$fixture.yaml"
    run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
      bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/$fixture.yaml"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK:"* ]]
  done
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
  test_path: tests/unit/owned.bats
  planned_paths: [scripts/run_tests.sh, tests/unit/owned.bats]
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    BATS_CACHE=1 BATS_INNER_JOBS=1 \
    bash -c 'cd "$1" && bash scripts/run_tests.sh --receipt-inner task queue/tasks/top.yaml' _ "$TMPROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_SCOPE result=task files=2"* ]]
  [[ "$output" == *"TEST_SELECTION_REASON direct=1 transitive=0 source=task_explicit_contract"* ]]

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
  test_path: tests/unit/owned.bats
  commit_contract:
    required: true
    planned_paths: [scripts/run_tests.sh, tests/unit/owned.bats]
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/nested.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_SCOPE result=task files=2"* ]]
  [[ "$output" == *"TEST_SELECTION_REASON direct=1 transitive=0 source=task_explicit_contract"* ]]

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

# test_necessity: an undeclared top/nested planned_paths mismatch (no
# scope_expansion_reason) must keep BLOCKing exactly as before — a declared
# expansion path must never quietly widen undeclared scope grabs (bulletin
# blt_20260724_162804 (d): undeclared expansion stays BLOCKed).
@test "cmd_4161 AC1: undeclared planned_paths expansion stays BLOCKed and fires a gate_fire_log entry" {
  printf '@test "owned" { true; }\n' >"$TMPROOT/tests/unit/owned.bats"
  mkdir -p "$TMPROOT/queue/tasks"
  cat >"$TMPROOT/queue/tasks/undeclared.yaml" <<'YAML'
task:
  planned_paths: [scripts/run_tests.sh]
  commit_contract:
    required: true
    planned_paths: [scripts/run_tests.sh, tests/unit/owned.bats]
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" LOG_DIR="$TMPROOT/logs" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/undeclared.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK: task scope could not be resolved"* ]]
  [[ "$output" == *"SCOPE_EXPANSION status=undeclared"* ]]
  [ -f "$TMPROOT/logs/gate_fire_log.yaml" ]
  grep -q 'gate: "scope_expansion", result: BLOCK' "$TMPROOT/logs/gate_fire_log.yaml"
  grep -q 'status=undeclared' "$TMPROOT/logs/gate_fire_log.yaml"
}

# test_necessity: a declared expansion (non-empty scope_expansion_reason and
# a nested planned_paths superset of the top-level declaration) must pass the
# mismatch check, widen the resolved scope to the superset, and record a
# gate_fire_log PASS entry so detector_fp_rate can track it.
@test "cmd_4161 AC1: declared planned_paths expansion passes and widens resolved scope" {
  printf '@test "owned" { true; }\n' >"$TMPROOT/tests/unit/owned.bats"
  printf '@test "extra" { true; }\n' >"$TMPROOT/tests/unit/extra.bats"
  mkdir -p "$TMPROOT/queue/tasks"
  cat >"$TMPROOT/queue/tasks/declared.yaml" <<'YAML'
task:
  test_path: [tests/unit/owned.bats, tests/unit/extra.bats]
  planned_paths: [scripts/run_tests.sh, tests/unit/owned.bats]
  commit_contract:
    required: true
    planned_paths: [scripts/run_tests.sh, tests/unit/owned.bats, tests/unit/extra.bats]
    scope_expansion_reason: "target_path outgrew original scope during implementation"
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" LOG_DIR="$TMPROOT/logs" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/declared.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCOPE_EXPANSION status=declared"* ]]
  [[ "$output" == *"TEST_SCOPE result=task files=3"* ]]
  [[ "$output" == *"TEST_SELECTION_REASON direct=2 transitive=0 source=task_explicit_contract"* ]]
  [ -f "$TMPROOT/logs/gate_fire_log.yaml" ]
  grep -q 'gate: "scope_expansion", result: PASS' "$TMPROOT/logs/gate_fire_log.yaml"
  grep -q 'status=declared' "$TMPROOT/logs/gate_fire_log.yaml"

  # A reason that does not accompany a superset (nested drops an originally
  # declared path while adding another) must not be treated as a valid
  # declared expansion — it stays BLOCKed even though a reason is present.
  cat >"$TMPROOT/queue/tasks/partial.yaml" <<'YAML'
task:
  planned_paths: [scripts/run_tests.sh, tests/unit/owned.bats]
  commit_contract:
    required: true
    planned_paths: [scripts/run_tests.sh, tests/unit/extra.bats]
    scope_expansion_reason: "not a true superset"
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" LOG_DIR="$TMPROOT/logs" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/partial.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK: task scope could not be resolved"* ]]
  [[ "$output" == *"SCOPE_EXPANSION status=undeclared"* ]]
}

# test_necessity: declare_scope_expansion() is the only supported way to
# widen commit_contract.planned_paths. It must require a non-empty reason,
# merge new paths without duplicating existing ones, and record the reason
# on task.commit_contract.scope_expansion_reason (bulletin blt_20260724_162804
# (a): raw yaml_field_set nested-path writes corrupt the YAML instead).
@test "cmd_4161 AC1: declare-scope-expansion CLI requires a reason and merges planned_paths" {
  mkdir -p "$TMPROOT/queue/tasks"
  cat >"$TMPROOT/queue/tasks/expand.yaml" <<'YAML'
task:
  commit_contract:
    required: true
    reason: implementation_path_present
    planned_paths: [scripts/run_tests.sh]
YAML

  run env REPO_ROOT="$ROOT" LOG_DIR="$TMPROOT/logs" \
    bash "$TMPROOT/scripts/run_tests.sh" declare-scope-expansion \
    "$TMPROOT/queue/tasks/expand.yaml" "" tests/unit/extra.bats
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCK: scope expansion reason must be non-empty"* ]]

  run env REPO_ROOT="$ROOT" LOG_DIR="$TMPROOT/logs" \
    bash "$TMPROOT/scripts/run_tests.sh" declare-scope-expansion \
    "$TMPROOT/queue/tasks/expand.yaml" "need extra fixture" tests/unit/extra.bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: commit_contract.planned_paths expanded"* ]]

  run python3 -c '
import yaml
data = yaml.safe_load(open("'"$TMPROOT"'/queue/tasks/expand.yaml"))
contract = data["task"]["commit_contract"]
print(contract["planned_paths"])
print(contract["scope_expansion_reason"])
print(contract["reason"])
'
  [ "$status" -eq 0 ]
  [[ "$output" == *"['scripts/run_tests.sh', 'tests/unit/extra.bats']"* ]]
  [[ "$output" == *"need extra fixture"* ]]
  [[ "$output" == *"implementation_path_present"* ]]
  [ -f "$TMPROOT/logs/gate_fire_log.yaml" ]
  grep -q 'gate: "scope_expansion_declared", result: PASS' "$TMPROOT/logs/gate_fire_log.yaml"
  grep -q 'reason=need extra fixture' "$TMPROOT/logs/gate_fire_log.yaml"

  # Re-running with a path already present must not duplicate it.
  run env REPO_ROOT="$ROOT" LOG_DIR="$TMPROOT/logs" \
    bash "$TMPROOT/scripts/run_tests.sh" declare-scope-expansion \
    "$TMPROOT/queue/tasks/expand.yaml" "second call" tests/unit/extra.bats
  [ "$status" -eq 0 ]
  run python3 -c '
import yaml
data = yaml.safe_load(open("'"$TMPROOT"'/queue/tasks/expand.yaml"))
print(len(data["task"]["commit_contract"]["planned_paths"]))
'
  [ "$status" -eq 0 ]
  [[ "$output" == *"2"* ]]
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

# test_necessity: Absolute paths owned by the declared source repository may
# be present while execution is rooted in its isolated task worktree.  They
# must be excluded as a WARN-only boundary, while an unapproved relative path
# traversal remains a hard BLOCK.
@test "external source paths warn-and-exclude while unapproved traversal blocks" {
  external="$TMPROOT/external-project"
  worktree="$TMPROOT/worktree"
  mkdir -p "$external/src" "$worktree"
  printf 'source\n' >"$external/src/source.py"
  git -C "$external" init -q
  git -C "$external" config user.email test@example.invalid
  git -C "$external" config user.name test
  git -C "$external" add src/source.py
  git -C "$external" commit -qm init
  git -C "$worktree" init -q
  git -C "$worktree" config user.email test@example.invalid
  git -C "$worktree" config user.name test
  printf 'worktree\n' >"$worktree/README"
  git -C "$worktree" add README
  git -C "$worktree" commit -qm init
  mkdir -p "$TMPROOT/queue/tasks"

  cat >"$TMPROOT/queue/tasks/external-source.yaml" <<YAML
task:
  project: external-fixture
  task_worktree_path: $worktree
  task_worktree_repo: $external
  target_path: $external/src/source.py
YAML
  run env REPO_ROOT="$TMPROOT" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task \
      "$TMPROOT/queue/tasks/external-source.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: external task scope path excluded: $external/src/source.py"* ]]
  [[ "$output" == *"TEST_SELECTION result=selected reason=external_scope_paths_excluded files=0"* ]]
  [[ "$output" != *"BLOCK: task scope could not be resolved"* ]]

  cat >"$TMPROOT/queue/tasks/traversal.yaml" <<YAML
task:
  task_worktree_path: $worktree
  task_worktree_repo: $external
  target_path: ../outside/source.py
YAML
  run env REPO_ROOT="$TMPROOT" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task \
      "$TMPROOT/queue/tasks/traversal.yaml"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK: task scope could not be resolved"* ]]
  [[ "$output" == *"scope path outside repository: ../outside/source.py"* ]]
  echo "BOUNDARY_METRICS external_warn_exclude=1 traversal_block=1 pass=2 skip=0"
}

# test_necessity: directory ownership must select only concrete changed files;
# a literal directory would fan out through the dependency map to the whole repo.
@test "directory task scope expands concrete diffs and blocks empty directories" {
  eval "$(sed -n '/^expand_task_directory_scope()/,/^}/p' "$TMPROOT/scripts/run_tests.sh")"
  mkdir -p "$TMPROOT/app"
  printf 'a\n' >"$TMPROOT/app/one.sh"
  printf 'b\n' >"$TMPROOT/app/two.sh"
  git -C "$TMPROOT" add app && git -C "$TMPROOT" commit -qm app

  printf 'changed\n' >>"$TMPROOT/app/one.sh"
  run expand_task_directory_scope "$TMPROOT" app
  [ "$status" -eq 0 ]
  [ "$output" = "app/one.sh" ]

  printf 'changed\n' >>"$TMPROOT/app/two.sh"
  run expand_task_directory_scope "$TMPROOT" app
  [ "$status" -eq 0 ]
  [[ "$output" == *"app/one.sh"* && "$output" == *"app/two.sh"* ]]

  git -C "$TMPROOT" restore app/one.sh app/two.sh
  run expand_task_directory_scope "$TMPROOT" app
  [ "$status" -eq 2 ]
  [[ "$output" == *"no concrete changed files"* ]]

  run expand_task_directory_scope "$TMPROOT" scripts/run_tests.sh
  [ "$status" -eq 0 ]
  [ "$output" = "scripts/run_tests.sh" ]
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

# test_necessity: an inspection-only task may target another project without
# leaking the external-project selection sentinel into its zero-test receipt;
# the same external scope remains fail-closed for implementation ownership.
@test "external readonly recon emits zero-test receipt while implementation scope stays BLOCKed" {
  external_root="$TMPROOT/external-project"
  mkdir -p "$external_root/scripts" "$TMPROOT/queue/tasks" "$TMPROOT/receipts-readonly" "$TMPROOT/receipts-implementation"
  printf '# inspected\n' >"$external_root/scripts/inspected.sh"
  git -C "$external_root" init -q
  git -C "$external_root" config user.email test@example.invalid
  git -C "$external_root" config user.name test
  git -C "$external_root" add scripts/inspected.sh
  git -C "$external_root" commit -qm init

  cat >"$TMPROOT/queue/tasks/external-readonly.yaml" <<YAML
task:
  task_type: recon
  project: external-fixture
  inspection_path: '["$external_root/scripts"]'
  commit_contract:
    required: false
    repo_root: $external_root
    planned_paths: []
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" \
    RUN_TESTS_RECEIPT_DIR="$TMPROOT/receipts-readonly" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" task "$TMPROOT/queue/tasks/external-readonly.yaml"
  [ "$status" -eq 0 ]
  readonly_receipt="$(find "$TMPROOT/receipts-readonly" -name '*.json' -type f | head -1)"
  [ -n "$readonly_receipt" ]
  [ "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["rc"], d["declared_test_count"], d["observed_test_count"], d["skip_count"], d["test_paths"])' "$readonly_receipt")" = "0 0 0 0 []" ]

  cat >"$TMPROOT/queue/tasks/external-implementation.yaml" <<YAML
task:
  task_type: hotfix
  project: external-fixture
  target_path: scripts/inspected.sh
  commit_contract:
    required: true
    repo_root: $external_root
    planned_paths: [scripts/inspected.sh]
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" \
    RUN_TESTS_RECEIPT_DIR="$TMPROOT/receipts-implementation" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" task "$TMPROOT/queue/tasks/external-implementation.yaml"
  [ "$status" -eq 2 ]
  implementation_receipt="$(find "$TMPROOT/receipts-implementation" -name '*.json' -type f | head -1)"
  [ -n "$implementation_receipt" ]
  [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["rc"])' "$implementation_receipt")" -eq 2 ]
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
  [[ "$output" == *"TEST_SELECTION_REASON direct=1 transitive=0 source=task_explicit_contract"* ]]
  [[ "$output" != *"readonly_probe"* ]]
}

# test_necessity: task identity is stronger than a raw file selection, so task/file callers must not share a receipt while both preserve the concrete runner rc=7.
@test "task and file public callers remain identity-isolated and preserve failure rc" {
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
# Both public callers must overlap before either publishes its terminal
# receipt. A count barrier proves overlap directly; both public callers are
# launched back-to-back so readiness is synchronized by the fixture itself.
for _barrier_try in {1..3000}; do
  [ "$(cat "$HEAVY_COUNT" 2>/dev/null || printf 0)" -eq 2 ] && break
  sleep 0.01
done
[ "$(cat "$HEAVY_COUNT" 2>/dev/null || printf 0)" -eq 2 ] || exit 98
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
      "${common[@]}" bash "$TMPROOT/scripts/run_tests.sh" file "$TMPROOT/tests/unit/sample.bats" >"$TMPROOT/file.out" 2>"$TMPROOT/file.err" & p2=$!
    else
      "${common[@]}" bash "$TMPROOT/scripts/run_tests.sh" file "$TMPROOT/tests/unit/sample.bats" >"$TMPROOT/file.out" 2>"$TMPROOT/file.err" & p2=$!
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
    [ "$(find "$TMPROOT/receipts" -name '*.json' | wc -l)" -eq 2 ]
    [ "$(cat "$TMPROOT/count")" -eq 2 ]
    [ "$(grep -h -c 'SINGLE_FLIGHT_JOINED' "$TMPROOT/task.err" "$TMPROOT/file.err" | awk '{s+=$1} END{print s+0}')" -eq 0 ]
    ! grep -h -q 'joined=1' "$TMPROOT/task.out" "$TMPROOT/file.out"
    ! grep -h -q 'TEST_RECEIPT_PASS.*rc=7' "$TMPROOT/task.out" "$TMPROOT/file.out"
  done
}

# test_necessity: task-mode single-flight identity must include task realpath, task_id, and planned paths so distinct tasks selecting the same test can never consume each other's receipt.
@test "distinct task identities selecting the same test execute twice with cross-task JOIN zero" {
  mkdir -p "$TMPROOT/queue/tasks" "$TMPROOT/receipts" "$TMPROOT/sf"
  cat >"$TMPROOT/scripts/test_select.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$REPO_ROOT/tests/unit/sample.bats"
SH
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
exec 9>>"$TASK_COUNT.lock"
flock 9
count=$(cat "$TASK_COUNT" 2>/dev/null || printf 0)
printf '%s\n' "$((count + 1))" >"$TASK_COUNT"
flock -u 9
sleep 0.5
printf '1..1\nok 1 isolated-task\n'
SH
  chmod +x "$TMPROOT/scripts/test_select.sh" "$TMPROOT/bin/bats"
  for agent in alpha beta; do
    cat >"$TMPROOT/queue/tasks/$agent.yaml" <<YAML
task:
  task_id: task-$agent
  planned_paths: [scripts/run_tests.sh]
YAML
  done
  common=(env -u RUN_TESTS_ACTIVE -u SHOGUN_HEAVY_JOB_LOCK_HELD -u SHOGUN_HEAVY_JOB_ADMITTED
    PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" BATS_CACHE=0
    RUN_TESTS_RECEIPT_DIR="$TMPROOT/receipts" RUN_TESTS_SINGLEFLIGHT_DIR="$TMPROOT/sf"
    TASK_COUNT="$TMPROOT/task-count")
  "${common[@]}" bash "$TMPROOT/scripts/run_tests.sh" task "$TMPROOT/queue/tasks/alpha.yaml" >"$TMPROOT/alpha.out" 2>"$TMPROOT/alpha.err" & p1=$!
  "${common[@]}" bash "$TMPROOT/scripts/run_tests.sh" task "$TMPROOT/queue/tasks/beta.yaml" >"$TMPROOT/beta.out" 2>"$TMPROOT/beta.err" & p2=$!
  wait "$p1"
  wait "$p2"
  [ "$(cat "$TMPROOT/task-count")" -eq 2 ]
  [ "$(find "$TMPROOT/receipts" -name '*.json' -type f | wc -l)" -eq 2 ]
  [ "$(grep -h -c 'SINGLE_FLIGHT_JOINED' "$TMPROOT/alpha.err" "$TMPROOT/beta.err" | awk '{s+=$1} END{print s+0}')" -eq 0 ]
}

# test_necessity: external frontend task under persistent p9 must self-provision an ext4 checkout, apply the task-owned dirty patch, and publish source_head/commit_sha from the external repository.
@test "external p9 fallback provisions dirty source and receipt uses external HEAD" {
  external="$TMPROOT/external"
  mkdir -p "$external/frontend" "$TMPROOT/projects" "$TMPROOT/queue/tasks" "$TMPROOT/receipts" "$TMPROOT/sf"
  printf '{"scripts":{"test":"jest"}}\n' >"$external/frontend/package.json"
  printf 'committed\n' >"$external/frontend/source.ts"
  git -C "$external" init -q
  git -C "$external" config user.email test@example.invalid
  git -C "$external" config user.name test
  git -C "$external" add frontend
  git -C "$external" commit -qm init
  external_head="$(git -C "$external" rev-parse HEAD)"
  printf 'dirty\n' >>"$external/frontend/source.ts"
  cat >"$TMPROOT/projects/external.yaml" <<YAML
project:
  path: $external
YAML
  cat >"$TMPROOT/queue/tasks/external.yaml" <<'YAML'
task:
  task_id: external-dirty-task
  project: external
  planned_paths: [frontend/source.ts]
YAML
  cat >"$TMPROOT/bin/npm" <<'SH'
#!/usr/bin/env bash
case "$PWD" in
  /tmp/shogun-frontend-fallback.*/frontend) ;;
  *) echo "not ext4 fallback: $PWD" >&2; exit 9 ;;
esac
grep -qx dirty source.ts || { echo "dirty patch missing" >&2; exit 8; }
printf 'Test Suites: 1 passed, 1 total\nTests:       1 passed, 1 total\nSnapshots:   0 total\n'
SH
  chmod +x "$TMPROOT/bin/npm"
  run env -u RUN_TESTS_ACTIVE -u SHOGUN_HEAVY_JOB_LOCK_HELD -u SHOGUN_HEAVY_JOB_ADMITTED \
    PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" BATS_CACHE=0 RUN_TESTS_DRVFS_P9_DETECTED=1 \
    RUN_TESTS_RECEIPT_DIR="$TMPROOT/receipts" RUN_TESTS_SINGLEFLIGHT_DIR="$TMPROOT/sf" \
    bash "$TMPROOT/scripts/run_tests.sh" task "$TMPROOT/queue/tasks/external.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRVFS_EXT4_FALLBACK result=provisioned"* ]]
  receipt="$(find "$TMPROOT/receipts" -name '*.json' -type f | head -1)"
  [ -n "$receipt" ]
  run python3 - "$receipt" "$external_head" <<'PY'
import json, sys
d=json.load(open(sys.argv[1]))
assert d["source_head"] == sys.argv[2]
assert d["run_manifest"]["commit_sha"] == sys.argv[2]
PY
  [ "$status" -eq 0 ]
}

# test_necessity: cmd_karo_hotfix_run_tests_vitest_cli_20260804 — External
# frontend dispatch must never pass Jest-only CLI flags
# to Vitest, and its native terminal summary must produce a non-zero test count.
@test "external frontend Vitest uses engine-specific arguments and publishes count" {
  external="$TMPROOT/external-vitest"
  mkdir -p "$external/frontend" "$TMPROOT/projects" "$TMPROOT/queue/tasks" "$TMPROOT/receipts"
  printf '{"scripts":{"test":"vitest run"}}\n' >"$external/frontend/package.json"
  printf 'export const value = 1;\n' >"$external/frontend/source.ts"
  git -C "$external" init -q
  git -C "$external" add .
  git -C "$external" -c user.email=t@example.invalid -c user.name=t commit -qm init
  cat >"$TMPROOT/projects/external-vitest.yaml" <<YAML
project:
  path: $external
YAML
  cat >"$TMPROOT/queue/tasks/external-vitest.yaml" <<'YAML'
task:
  project: external-vitest
  planned_paths: [frontend/source.ts]
YAML
  export NPM_ARGS_LOG="$TMPROOT/npm.args"
  cat >"$TMPROOT/bin/npm" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$NPM_ARGS_LOG"
printf ' Test Files  1 passed (1)\n Tests  3 passed (3)\n'
SH
  chmod +x "$TMPROOT/bin/npm"

  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" BATS_CACHE=0 \
    NPM_ARGS_LOG="$NPM_ARGS_LOG" RUN_TESTS_DRVFS_P9_DETECTED=0 \
    RUN_TESTS_RECEIPT_DIR="$TMPROOT/receipts" \
    bash "$TMPROOT/scripts/run_tests.sh" task "$TMPROOT/queue/tasks/external-vitest.yaml"

  [ "$status" -eq 0 ]
  grep -Fqx 'test -- --passWithNoTests source.ts' "$NPM_ARGS_LOG"
  ! grep -q -- '--runInBand\|--findRelatedTests\|--related' "$NPM_ARGS_LOG"
  receipt="$(find "$TMPROOT/receipts" -name '*.json' -type f | head -1)"
  [ "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["observed_test_count"], d["rc"])' "$receipt")" = "3 0" ]
}

# test_necessity: an external repo_root may come from commit_contract, but its
# planned ownership remains distinct from the explicit test execution request.
@test "external commit_contract repo_root selects explicit nested test" {
  external="$TMPROOT/external-contract"
  mkdir -p "$external/backend/tests" "$external/.venv/bin" "$TMPROOT/queue/tasks"
  git -C "$external" init -q
  printf 'def test_owned():\n    assert True\n' >"$external/backend/tests/test_owned.py"
  git -C "$external" add .
  git -C "$external" -c user.email=t@example.invalid -c user.name=t commit -qm init
  cat >"$external/.venv/bin/python" <<'SH'
#!/usr/bin/env bash
if [[ "$1 $2" == "-c import pytest" ]]; then
  exit 64
fi
[[ "$1 $2 $3" == "-m pytest -q" ]] || exit 64
[[ "$4" == "tests/test_owned.py" ]] || exit 65
printf '1 passed in 0.01s\n'
SH
  chmod +x "$external/.venv/bin/python"
  real_python3="$(command -v python3)"
  cat >"$TMPROOT/bin/python3" <<SH
#!/usr/bin/env bash
if [[ "\$1 \$2" == "-m pytest" ]]; then
  exit 66
fi
exec "$real_python3" "\$@"
SH
  chmod +x "$TMPROOT/bin/python3"
  cat >"$TMPROOT/queue/tasks/external-contract.yaml" <<YAML
task:
  project: absent-from-registry
  commit_contract:
    repo_root: $external
    planned_paths: [backend/tests/test_owned.py]
  test_path: backend/tests/test_owned.py
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/external-contract.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"scope=backend_contract"* ]]
  [[ "$output" != *"files=0"* ]]
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

# test_necessity: the public task leader reads receipt rc under nounset; valid
# terminal rc values must survive exactly, while missing/malformed identities
# fail closed as rc=2 without an unbound-variable abort or false PASS.
@test "receipt rc reader is total for rc0 rc1 rc2 rc7 missing and malformed cells" {
  mkdir -p "$TMPROOT/receipts"
  for rc in 0 1 2 7; do
    printf '{"rc":%s}\n' "$rc" >"$TMPROOT/receipts/r${rc}.json"
    run env REPO_ROOT="$TMPROOT" bash -uc \
      'source "$1/scripts/run_tests.sh"; value=2; if parsed="$(read_run_tests_receipt_rc "$2")"; then value="$parsed"; fi; printf "%s\n" "$value"' \
      _ "$TMPROOT" "$TMPROOT/receipts/r${rc}.json"
    [ "$status" -eq 0 ]
    [ "$output" = "$rc" ]
    [[ "$output" != *"unbound variable"* ]]
  done

  for cell in missing malformed; do
    path="$TMPROOT/receipts/${cell}.json"
    [ "$cell" = malformed ] && printf '{bad\n' >"$path"
    run env REPO_ROOT="$TMPROOT" bash -uc \
      'source "$1/scripts/run_tests.sh"; value=2; if parsed="$(read_run_tests_receipt_rc "$2" 2>/dev/null)"; then value="$parsed"; fi; printf "%s\n" "$value"' \
      _ "$TMPROOT" "$path"
    [ "$status" -eq 0 ]
    [ "$output" = 2 ]
    [[ "$output" != *"unbound variable"* ]]
    [[ "$output" != *"TEST_RECEIPT_PASS"* ]]
  done
}

# test_necessity: an inner runner that exits before publishing its receipt must
# still produce an atomic, reasoned FAIL receipt so CI can distinguish runner
# infrastructure failure from an ordinary test failure.
# regression_justification: the compatibility shard previously reached its
# terminal verification boundary with no durable inner receipt in this exit path.
@test "missing inner receipt publishes a reasoned fail receipt" {
  cat >"$TMPROOT/scripts/run_with_receipt.sh" <<'SH'
#!/usr/bin/env bash
exit 23
SH
  chmod +x "$TMPROOT/scripts/run_with_receipt.sh"
  receipt_dir="$TMPROOT/logs/missing-receipt"
  run env REPO_ROOT="$TMPROOT" RUN_TESTS_RECEIPT_DIR="$receipt_dir" \
    SHOGUN_HEAVY_JOB_LOCK_HELD=1 BATS_CACHE=0 BATS_INNER_JOBS=1 \
    bash "$TMPROOT/scripts/run_tests.sh" file "$TMPROOT/tests/unit/sample.bats"
  [ "$status" -eq 23 ]
  receipt="$(find "$receipt_dir" -name '*.json' -type f | head -1)"
  [ -n "$receipt" ]
  artifact="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["artifact"])' "$receipt")"
  [ -s "$artifact" ]
  grep -Fq 'terminal receipt missing after inner runner exit' "$artifact"
  python3 - "$receipt" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["complete"] is True
assert data["result"] == "FAIL"
assert data["rc"] == 23
assert data["skip_count"] == 0
PY
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


# test_necessity: 受領証は「選択・発見・実行・完了」の4値を持ち、全数を完走していない実行が全数を名乗れない
@test "scope identity requires selected equals discovered equals executed and complete" {
  printf '@test "a" { true; }\n' >"$TMPROOT/tests/unit/a.bats"
  printf '@test "b" { true; }\n' >"$TMPROOT/tests/unit/b.bats"
  head="$(git -C "$TMPROOT" rev-parse HEAD)"
  artifact="$TMPROOT/scope.out"
  receipt="$TMPROOT/scope.json"
  paths="$TMPROOT/scope.paths"
  ls "$TMPROOT"/tests/unit/*.bats | sed "s|^$TMPROOT/||" >"$paths"

  # $1=complete, $2=実行ログに載せるファイル数(START+DONE)
  _mk_receipt() {
    : >"$artifact"
    local n="$2" i=0
    while read -r rel; do
      i=$((i + 1)); [ "$i" -le "$n" ] || break
      printf 'START: %s pid=1 weight=8 timeout=900s\nDONE: %s rc=0\n' "${rel##*/}" "${rel##*/}" >>"$artifact"
    done <"$paths"
    printf 'PASS: %s bats file(s) (%s run, 0 cached)\n1..1\nok 1 sample\n' "$n" "$n" >>"$artifact"
    python3 - "$receipt" "$artifact" "$1" <<'PY'
import hashlib, json, sys
path, artifact, complete = sys.argv[1:]
raw = open(artifact, 'rb').read()
json.dump({
    "version": 2, "complete": complete == "true", "result": "PASS", "rc": 0,
    "duration_ms": 1, "output_sha256": hashlib.sha256(raw).hexdigest(),
    "declared_test_count": 1, "observed_test_count": 1, "skip_count": 0,
    "artifact": artifact, "signal": None, "command": ["bats"],
}, open(path, "w"))
PY
  }
  _publish() {
    env REPO_ROOT="$TMPROOT" bash -c '
      source "$1/scripts/run_tests.sh"
      publish_run_tests_metadata "$2" "$3" "$4" selector "$5" "$1"
    ' _ "$TMPROOT" "$receipt" "$head" "$paths" "$1"
  }
  _scope() {
    python3 -c 'import json,sys; s=json.load(open(sys.argv[1]))["run_manifest"]["scope_identity"]; print(s["selected_file_count"], s["discovered_file_count"], s["executed_file_count"], s["complete"], s["full_scope"])' "$receipt"
  }

  # 陽性: 3本発見・3本選択・3本実行・complete=true → 全数
  _mk_receipt true 3
  _publish unit
  run _scope
  [ "$output" = "3 3 3 True True" ]
  run env REPO_ROOT="$TMPROOT" bash -c 'source "$1/scripts/run_tests.sh"; verify_run_tests_receipt "$2"' _ "$TMPROOT" "$receipt"
  [ "$status" -eq 0 ]

  # 敵対fixture: selected childが出した3組（selected名の重複1組+
  # scope外2組）は外側runのidentity/失敗へ混入しない。
  _mk_receipt true 3
  {
    printf 'START: a.bats pid=2 weight=1 timeout=900s\nDONE: a.bats rc=0\n'
    printf 'START: nested_slow.bats pid=3 weight=1 timeout=900s\nDONE: nested_slow.bats rc=0\n'
    printf 'START: nested_fail.bats pid=4 weight=1 timeout=900s\nDONE: nested_fail.bats rc=1\n'
  } >>"$artifact"
  python3 - "$receipt" "$artifact" <<'PY'
import hashlib, json, sys
receipt, artifact = sys.argv[1:]
d = json.load(open(receipt))
d["output_sha256"] = hashlib.sha256(open(artifact, "rb").read()).hexdigest()
json.dump(d, open(receipt, "w"))
PY
  _publish unit
  run _scope
  [ "$output" = "3 3 3 True True" ]
  run python3 -c 'import json,sys; s=json.load(open(sys.argv[1]))["run_manifest"]["scope_identity"]; print(s["started_file_count"], s["failed_file_count"], len(s["failed_files"]))' "$receipt"
  [ "$output" = "3 0 0" ]
  run env REPO_ROOT="$TMPROOT" bash -c 'source "$1/scripts/run_tests.sh"; verify_run_tests_receipt "$2"' _ "$TMPROOT" "$receipt"
  [ "$status" -eq 0 ]

  # 陰性1: 選択も発見も3だが実行は2(=今回の18:03と同型) → 全数ではない
  _mk_receipt true 2
  _publish unit
  run _scope
  [ "$output" = "3 3 2 True False" ]

  # 陰性2: 3本実行したが complete=false(打ち切り) → 全数ではない
  _mk_receipt false 3
  _publish unit
  run _scope
  [ "$output" = "3 3 3 False False" ]

  # 退化防止: affected/file等の正当な部分実行は full_scope_claimable=false であり誤BLOCKしない
  _mk_receipt true 3
  _publish affected
  run python3 -c 'import json,sys; s=json.load(open(sys.argv[1]))["run_manifest"]["scope_identity"]; print(s["mode"], s["full_scope_claimable"], s["full_scope"])' "$receipt"
  [ "$output" = "affected False False" ]
  run env REPO_ROOT="$TMPROOT" bash -c 'source "$1/scripts/run_tests.sh"; verify_run_tests_receipt "$2"' _ "$TMPROOT" "$receipt"
  [ "$status" -eq 0 ]

  # 変異注入1: full_scope を手で立てても検証器が否認する
  _mk_receipt true 2
  _publish unit
  python3 - "$receipt" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["run_manifest"]["scope_identity"]["full_scope"] = True
json.dump(d, open(sys.argv[1], "w"))
PY
  run env REPO_ROOT="$TMPROOT" bash -c 'source "$1/scripts/run_tests.sh"; verify_run_tests_receipt "$2"' _ "$TMPROOT" "$receipt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"scope_identity full_scope"* ]]

  # 変異注入2: executed を水増ししても complete と件数の突合で否認される
  _mk_receipt false 3
  _publish unit
  python3 - "$receipt" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["run_manifest"]["scope_identity"].update(executed_file_count=3, complete=True, full_scope=True)
json.dump(d, open(sys.argv[1], "w"))
PY
  run env REPO_ROOT="$TMPROOT" bash -c 'source "$1/scripts/run_tests.sh"; verify_run_tests_receipt "$2"' _ "$TMPROOT" "$receipt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"scope_identity complete"* ]]
}

# test_necessity: joinした受領証でも範囲identityが誰の実行のものか判別できる(B-1のtree identityと対をなす)
@test "joined receipt keeps the leader scope identity and marks the join" {
  head="$(git -C "$TMPROOT" rev-parse HEAD)"
  artifact="$TMPROOT/join.out"
  receipt="$TMPROOT/join.json"
  paths="$TMPROOT/join.paths"
  ls "$TMPROOT"/tests/unit/*.bats | sed "s|^$TMPROOT/||" >"$paths"
  : >"$artifact"
  while read -r rel; do
    printf 'START: %s pid=1 weight=8 timeout=900s\nDONE: %s rc=0\n' "${rel##*/}" "${rel##*/}" >>"$artifact"
  done <"$paths"
  printf 'PASS: 1 bats file(s) (1 run, 0 cached)\n1..1\nok 1 sample\n' >>"$artifact"
  python3 - "$receipt" "$artifact" <<'PY'
import hashlib, json, sys
path, artifact = sys.argv[1:]
raw = open(artifact, 'rb').read()
json.dump({
    "version": 2, "complete": True, "result": "PASS", "rc": 0,
    "duration_ms": 1, "output_sha256": hashlib.sha256(raw).hexdigest(),
    "declared_test_count": 1, "observed_test_count": 1, "skip_count": 0,
    "artifact": artifact, "signal": None, "command": ["bats"],
}, open(path, "w"))
PY
  run env REPO_ROOT="$TMPROOT" bash -c '
    source "$1/scripts/run_tests.sh"
    publish_run_tests_metadata "$2" "$3" "$4" selector unit "$1"
  ' _ "$TMPROOT" "$receipt" "$head" "$paths"
  [ "$status" -eq 0 ]

  run env REPO_ROOT="$TMPROOT" bash -c '
    source "$1/scripts/run_tests.sh"
    emit_run_tests_terminal_receipt "$2" joined=1
  ' _ "$TMPROOT" "$receipt"
  [ "$status" -eq 0 ]
  [ -f "$receipt.join_status.json" ]
  run python3 -c 'import json,sys; j=json.load(open(sys.argv[1]+".join_status.json")); s=json.load(open(sys.argv[1]))["run_manifest"]["scope_identity"]; print(j["joined"], j["leader_receipt"]==sys.argv[1], s["mode"], s["selected_file_count"], s["executed_file_count"], s["full_scope"])' "$receipt"
  [ "$output" = "True True unit 1 1 True" ]
}

# test_necessity: 件数の主張はそれ自身の列挙を伴い、切り捨てた出力から数え直させない
@test "scope identity enumerates every failing file next to its count" {
  printf '@test "a" { true; }\n' >"$TMPROOT/tests/unit/a.bats"
  printf '@test "b" { true; }\n' >"$TMPROOT/tests/unit/b.bats"
  head="$(git -C "$TMPROOT" rev-parse HEAD)"
  artifact="$TMPROOT/fail.out"
  receipt="$TMPROOT/fail.json"
  paths="$TMPROOT/fail.paths"
  ls "$TMPROOT"/tests/unit/*.bats | sed "s|^$TMPROOT/||" >"$paths"
  {
    printf 'START: a.bats pid=1 weight=8 timeout=900s\nDONE: a.bats rc=1\n'
    printf 'START: b.bats pid=2 weight=8 timeout=900s\nDONE: b.bats rc=0\n'
    printf 'START: sample.bats pid=3 weight=8 timeout=900s\nDONE: sample.bats rc=2\n'
    printf 'PASS: 3 bats file(s) (3 run, 0 cached)\n1..1\nok 1 sample\n'
  } >"$artifact"
  python3 - "$receipt" "$artifact" <<'PYEOF'
import hashlib, json, sys
path, artifact = sys.argv[1:]
raw = open(artifact, 'rb').read()
json.dump({
    "version": 2, "complete": True, "result": "PASS", "rc": 0,
    "duration_ms": 1, "output_sha256": hashlib.sha256(raw).hexdigest(),
    "declared_test_count": 1, "observed_test_count": 1, "skip_count": 0,
    "artifact": artifact, "signal": None, "command": ["bats"],
}, open(path, "w"))
PYEOF
  run env REPO_ROOT="$TMPROOT" bash -c '
    source "$1/scripts/run_tests.sh"
    publish_run_tests_metadata "$2" "$3" "$4" selector unit "$1"
    verify_run_tests_receipt "$2"
  ' _ "$TMPROOT" "$receipt" "$head" "$paths"
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; s=json.load(open(sys.argv[1]))["run_manifest"]["scope_identity"]; print(s["failed_file_count"], ",".join(s["failed_files"]))' "$receipt"
  [ "$output" = "2 a.bats,sample.bats" ]

  # 変異注入: 件数だけ切り下げても列挙との突合で否認される(head/tail由来の申告を通さない)
  python3 - "$receipt" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); d["run_manifest"]["scope_identity"]["failed_file_count"] = 1
json.dump(d, open(sys.argv[1], "w"))
PYEOF
  run env REPO_ROOT="$TMPROOT" bash -c 'source "$1/scripts/run_tests.sh"; verify_run_tests_receipt "$2"' _ "$TMPROOT" "$receipt"
  [ "$status" -ne 0 ]
  [[ "$output" == *"scope_identity failed_files"* ]]
}
