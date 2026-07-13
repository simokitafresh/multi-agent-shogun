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
