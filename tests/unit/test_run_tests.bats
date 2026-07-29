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
  grep -Fq 'timeout-minutes: 12' "$workflow"
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

# test_necessity: 個別external backend taskが暗黙に全pytestへ拡大せず、
# 明示contractだけを選び、fixed-SHA wave最終checkpointだけが全量を許可される
# 三分岐の実行境界を守る。
@test "external backend task blocks implicit full unit and preserves explicit contract and checkpoint" {
  external="$TMPROOT/external"
  mkdir -p "$external/backend/tests" "$external/backend/app" \
    "$TMPROOT/projects" "$TMPROOT/queue/tasks" "$TMPROOT/logs"
  cat >"$TMPROOT/bin/python3" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == -m && "${2:-}" == pytest ]]; then
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
YAML
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" LOG_DIR="$TMPROOT/logs" SHOGUN_HEAVY_JOB_LOCK_HELD=1 \
    bash "$TMPROOT/scripts/run_tests.sh" --receipt-inner task "$TMPROOT/queue/tasks/contract.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"scope=backend_contract"* ]]
  [[ "$output" == *"1 passed"* ]]
  [[ "$output" != *"backend_full_unit_checkpoint"* ]]

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
  printf '{"scripts":{"test":"fixture"}}\n' >"$external/frontend/package.json"
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
