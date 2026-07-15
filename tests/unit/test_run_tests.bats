#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPROOT="$(mktemp -d)"
  mkdir -p "$TMPROOT/scripts" "$TMPROOT/tests/unit" "$TMPROOT/bin" "$TMPROOT/logs"
  cp "$ROOT/scripts/run_tests.sh" "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/scripts/"
  printf '@test "sample" { true; }\n' >"$TMPROOT/tests/unit/sample.bats"
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

teardown() { rm -rf "$TMPROOT"; }

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
    BATS_CACHE=0 BATS_INNER_JOBS=1 bash -c '
      source "$1/scripts/run_tests.sh"
      run_bats_files_parallel "$1/tests/unit/sample.bats"
    ' _ "$TMPROOT"
  [ "$status" -eq 0 ]
  grep -Fq -- '--jobs 1' "$TMPROOT/bats.args"
  run env REPO_ROOT="$TMPROOT" bash -c 'source "$1/scripts/run_tests.sh"; [ "$INNER_JOBS" -eq 1 ] && [ "$MAX_TEST_JOBS" -eq 8 ]' _ "$TMPROOT"
  [ "$status" -eq 0 ]
}

@test "CI pins file-internal jobs to one and leaves aggregate parallelism to run_tests" {
  workflow="$ROOT/.github/workflows/test.yml"

  grep -Fq 'BATS_INNER_JOBS=1 \' "$workflow"
  grep -Fq 'BATS_FILE_TIMEOUT_SECONDS=900 \' "$workflow"
  grep -Fq 'timeout-minutes: 45' "$workflow"
  grep -Fq 'group: test-${{ github.workflow }}-${{ github.ref }}' "$workflow"
  grep -Fq 'cancel-in-progress: true' "$workflow"
  ! grep -Fq 'BATS_INNER_JOBS=8 \' "$workflow"
  grep -Fq 'bash scripts/run_tests.sh unit' "$workflow"
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
sleep 0.15
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
