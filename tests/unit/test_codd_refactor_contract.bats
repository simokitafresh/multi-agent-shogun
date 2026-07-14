#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SKILL="$ROOT/skills/codd-refactor/SKILL.md"
}

@test "引数なし契約は専用bats loopを持たず14列台帳の非cache all/unit完走runを使う" {
  run grep -F 'for f in $(find tests/unit -name "*.bats"' "$SKILL"
  [ "$status" -ne 0 ]
  grep -q 'logs/test_timing_ledger.tsv' "$SKILL"
  grep -q 'cache_hit=0' "$SKILL"
  grep -q 'mode=all/unit' "$SKILL"
  grep -q 'wall_sec' "$SKILL"
  grep -q 'LATEST_RUN' "$SKILL"
}

@test "引数なし契約は専用runnerとtiming gateを起動しない" {
  grep -q '専用の `bats` loop、`scripts/run_tests.sh`、`scripts/gates/gate_test_health.sh --timing` は起動しない' "$SKILL"
  grep -q '専用計測runは禁止' "$SKILL"
}

@test "明示targetとspecは従来フローを維持し候補選定だけ台帳を使う" {
  grep -q '引数がスクリプトパスの場合.*候補選定には既存14列台帳を利用' "$SKILL"
  grep -q '引数がspec.mdの場合.*候補選定には既存14列台帳を利用' "$SKILL"
  grep -q 'scripts/test_select.sh' "$SKILL"
  grep -q 'codd_refactor_registry.md' "$SKILL"
}

@test "Phase5は同一対象のcommit_shaとrun_idを比較し欠損をfail-closedする" {
  grep -q '同一 `test_file`・同一 `suite_root`' "$SKILL"
  grep -q '`cache_hit=0`' "$SKILL"
  grep -q '`mode=all/unit`' "$SKILL"
  grep -q 'Before/Afterの `commit_sha` と `run_id`' "$SKILL"
  grep -q '欠損した場合は `UNVERIFIED` としてfail-closed' "$SKILL"
}
