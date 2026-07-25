#!/usr/bin/env bats
# test_necessity: promotion loop must count CLEAR reflux_promotion rows written with a
# literal backslash-t separator (not just a real tab byte), and must alert on stock
# growth measured against a >=grace-hour-old baseline snapshot, not only the single
# immediately-adjacent snapshot which silently misses sustained multi-run growth.

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  T="$BATS_TEST_TMPDIR"
  mkdir -p "$T/logs" "$T/queue"
  env_common=(
    LOOP_LEDGER_ROOT="$T"
    LOOP_LEDGER_NOW="2026-01-15T12:00:00Z"
    LOOP_LEDGER_OUT="$T/logs/loop_ledger.yaml"
    LOOP_LEDGER_LESSON_IMPACT="$T/logs/lesson_impact.tsv"
    LOOP_LEDGER_INSIGHTS_FILE="$T/queue/insights.yaml"
    LOOP_LEDGER_DB="$T/data/nonexistent.db"
    LOOP_LEDGER_SKILL_RECOMMEND_LOG="$T/logs/skill_recommend_log.yaml"
    LOOP_LEDGER_SKILL_EXECUTION_LOG="$T/logs/skill_execution_log.yaml"
    LOOP_LEDGER_STARTUP_ALERT_HISTORY="$T/logs/shogun_startup_alert_history.tsv"
  )
}

@test "literal backslash-t CLEAR reflux_promotion row is still counted as consumed" {
  printf '2026-01-15T11:00:00Z\tcmd_reflux_promotion_test_healthy\tCLEAR\n' > "$T/logs/gate_metrics.log"
  printf '2026-01-15T11:05:00Z\\tcmd_reflux_promotion_test_corrupted\\tCLEAR\n' >> "$T/logs/gate_metrics.log"
  run env "${env_common[@]}" LOOP_LEDGER_GATE_METRICS_LOG="$T/logs/gate_metrics.log" bash "$ROOT/scripts/loop_ledger_update.sh"
  [[ "$output" == *"promotion: produced=0 consumed=2 stock=0"* ]]
}

@test "promotion stock alert compares against grace-hour-old baseline not the adjacent snapshot" {
  printf '' > "$T/logs/gate_metrics.log"
  mkdir -p "$T/scripts/gates"
  cat > "$T/scripts/gates/gate_lesson_enforcement_level.sh" <<'EOF'
#!/usr/bin/env bash
echo "##ENFORCEMENT_LEVEL_BELOW4_COUNT##"
echo "150"
EOF
  chmod +x "$T/scripts/gates/gate_lesson_enforcement_level.sh"
  cat > "$T/logs/loop_ledger.yaml" <<'EOF'
snapshots:
- generated_at: "2026-01-14T09:00:00Z"
  window_days: 14
  loops:
    promotion:
      produced: 0
      consumed: 0
      stock: 100
      last_consumption_ts: null
      stalled: false
- generated_at: "2026-01-15T11:55:00Z"
  window_days: 14
  loops:
    promotion:
      produced: 0
      consumed: 0
      stock: 150
      last_consumption_ts: null
      stalled: false
alerts: []
EOF
  # Adjacent-only comparison (150 vs 150) would see no growth; only the >=24h-old
  # baseline (100) reveals the real trend.
  run env "${env_common[@]}" LOOP_LEDGER_GATE_METRICS_LOG="$T/logs/gate_metrics.log" bash "$ROOT/scripts/loop_ledger_update.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ALERT: promotion: 在庫超過(24h以上前100→今回150)"* ]]
}
