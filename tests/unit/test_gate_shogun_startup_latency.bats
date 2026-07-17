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
  run awk -F '\t' 'END {print $1,$3,length($4)}' "$timing"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^fixture\ 1\ 64$ ]]
}

@test "input hash change invalidates cache without changing warning output" {
  input="$TEST_TMP/input"; printf 'v1\n' > "$input"
  cache="$TEST_TMP/cache"; timing="$TEST_TMP/timing.tsv"
  first=$(SHOGUN_STARTUP_TIMING_FILE="$timing" SHOGUN_STARTUP_CACHE_INPUTS="$input" run_startup_short_cache "$cache" 60 printf 'WARN: contract\n')
  printf 'v2\n' > "$input"
  second=$(SHOGUN_STARTUP_TIMING_FILE="$timing" SHOGUN_STARTUP_CACHE_INPUTS="$input" run_startup_short_cache "$cache" 60 printf 'WARN: contract\n')
  [ "$first" = "$second" ]
  run awk -F '\t' 'END {print $3}' "$timing"
  [ "$output" = 0 ]
}
