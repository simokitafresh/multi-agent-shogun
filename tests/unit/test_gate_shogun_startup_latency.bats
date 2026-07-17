#!/usr/bin/env bats

setup() {
  TEST_TMP="$(mktemp -d)"
  export SHOGUN_STARTUP_LIB_ONLY=1
  source "$BATS_TEST_DIRNAME/../../scripts/gates/gate_shogun_startup.sh"
}

teardown() { rm -r "$TEST_TMP"; }

@test "cache hit is fast and emits machine-readable duration" {
  input="$TEST_TMP/input"; printf 'v1\n' > "$input"
  cache="$TEST_TMP/cache"; timing="$TEST_TMP/timing.tsv"
  SHOGUN_STARTUP_TIMING_FILE="$timing" SHOGUN_STARTUP_CHECK_NAME=fixture \
    SHOGUN_STARTUP_CACHE_INPUTS="$input" run_startup_short_cache "$cache" 60 bash -c 'sleep 0.05; printf "WARN: same\n"'
  SHOGUN_STARTUP_TIMING_FILE="$timing" SHOGUN_STARTUP_CHECK_NAME=fixture \
    SHOGUN_STARTUP_CACHE_INPUTS="$input" run_startup_short_cache "$cache" 60 bash -c 'exit 9'
  run awk -F '\t' 'END {print $1,$3,($4 ~ /^cache:hit=1,input=[0-9a-f]{64}$/)}' "$timing"
  [ "$status" -eq 0 ]
  [ "$output" = "fixture 0 1" ]
}

@test "input hash change invalidates cache without changing warning output" {
  input="$TEST_TMP/input"; printf 'v1\n' > "$input"
  cache="$TEST_TMP/cache"; timing="$TEST_TMP/timing.tsv"
  first=$(SHOGUN_STARTUP_TIMING_FILE="$timing" SHOGUN_STARTUP_CACHE_INPUTS="$input" run_startup_short_cache "$cache" 60 printf 'WARN: contract\n')
  printf 'v2\n' > "$input"
  second=$(SHOGUN_STARTUP_TIMING_FILE="$timing" SHOGUN_STARTUP_CACHE_INPUTS="$input" run_startup_short_cache "$cache" 60 printf 'WARN: contract\n')
  [ "$first" = "$second" ]
  run awk -F '\t' 'END {print ($4 ~ /^cache:hit=0,input=[0-9a-f]{64}$/)}' "$timing"
  [ "$output" = 1 ]
}

@test "startup timing contract has exactly 59 logical headings" {
  run awk '
    /^[[:space:]]*echo "■ / {
      line=$0; sub(/^.*echo "■ /, "", line); sub(/".*$/, "", line)
      if (line !~ /^DIGEST:/ && line !~ /^必読: projects\/infra\/lessons_shogun.yaml/ && line !~ /^必読: memory\/deepdive_why_chain_20260321.md/) count++
    }
    END { print count }
  ' "$BATS_TEST_DIRNAME/../../scripts/gates/gate_shogun_startup.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "59" ]
  run grep -c 'run_startup_short_cache ' "$BATS_TEST_DIRNAME/../../scripts/gates/gate_shogun_startup.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "7" ]
}

@test "common timing wrapper records normal warn and alert exits without gaps" {
  timing="$TEST_TMP/all.tsv"
  printf 'check\tduration_ms\trc\tinput_hash\n' > "$timing"
  SHOGUN_STARTUP_TIMING_FILE="$timing"
  overall=OK
  alerts=()
  _STARTUP_TIMING_ACTIVE=""; _STARTUP_TIMING_STARTED_MS=0; _STARTUP_TIMING_BASELINE=OK
  startup_timing_begin_check normal
  startup_timing_begin_check warn; overall=WARN; alerts+=(warn)
  startup_timing_begin_check alert; overall=ALERT; alerts+=(alert)
  startup_timing_close_check
  run awk -F '\t' 'NR>1 {print $1 ":" $3}' "$timing"
  [ "$status" -eq 0 ]
  [ "$output" = $'normal:0\nwarn:1\nalert:2' ]
}

@test "timeout signal flushes completed timing rows and partial coverage" {
  timing="$TEST_TMP/timeout.tsv"
  run timeout 1 bash -c '
    source "$1"
    SHOGUN_STARTUP_TIMING_FILE="$2"
    printf "check\tduration_ms\trc\tinput_hash\n" > "$2"
    _STARTUP_GATE_STARTED_MS=$(date +%s%3N)
    _STARTUP_TIMING_FINALIZED=0
    _STARTUP_TIMING_ACTIVE=""
    _STARTUP_TIMING_STARTED_MS=0
    _STARTUP_TIMING_BASELINE=OK
    overall=OK
    alerts=()
    trap startup_timing_signal_exit TERM
    startup_timing_begin_check completed_before_timeout
    sleep 10
  ' _ "$BATS_TEST_DIRNAME/../../scripts/gates/gate_shogun_startup.sh" "$timing"
  [ "$status" -eq 124 ]
  [[ "$output" == *"startup check timings (partial)"* ]]
  [[ "$output" == *"TIMING check=completed_before_timeout"*"rc=124"* ]]
  [[ "$output" == *"TIMING_COVERAGE measured=1 total=59"* ]]
  run awk -F '\t' 'NR == 2 { print ($1 == "completed_before_timeout" && $2 > 0 && $3 == 124) }' "$timing"
  [ "$status" -eq 0 ]
  [ "$output" = 1 ]
}
