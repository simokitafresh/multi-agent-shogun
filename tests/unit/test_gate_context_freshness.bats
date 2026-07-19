#!/usr/bin/env bats
# test_necessity: context freshness更新cmdがlast_updatedだけの消火を許さず、検証済みsource_commit境界と未解消差分0件を完了条件にする不変量を守る。

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  FIXTURE_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$FIXTURE_ROOT/context" "$FIXTURE_ROOT/scripts" "$BATS_TEST_TMPDIR/state"
  printf '<!-- last_updated: 2026-07-19 cmd_fixture -->\n' > "$FIXTURE_ROOT/context/infrastructure.md"
  cat > "$FIXTURE_ROOT/scripts/check.sh" <<'SH'
#!/usr/bin/env bash
echo 'ALERT: context/infrastructure.md source commits 1件 since last_updated=2026-07-19; latest: abc1234 fixture'
SH
}

@test "ALERT template requires source commit boundary and zero unresolved commits" {
  run env \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"AC2: scripts/context_source_commit_set.sh"* ]]
  [[ "$output" == *"last_updatedだけの更新は禁止"* ]]
  [[ "$output" == *"未解消source commit=0件かつALERT=0件"* ]]
  [[ "$output" != *"先頭の last_updated を 2026-07-20"* ]]
}

@test "normal checker output produces zero false-positive alerts" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FIXTURE_ROOT/scripts/check.sh"

  run env \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"総合判定: OK"* ]]
  [[ "$output" != *"ALERT:"* ]]
}
