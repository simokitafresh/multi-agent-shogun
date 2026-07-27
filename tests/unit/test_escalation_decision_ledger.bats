#!/usr/bin/env bats
# test_necessity: 将軍判定台帳による同一内容エスカレーション抑止・内容変化再送・台帳なしfail-open契約を固定する。

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPDIR_CASE="$(mktemp -d)"
  STATE="$TMPDIR_CASE/state.tsv"
  ALERTS="$TMPDIR_CASE/alerts.txt"
  LEDGER="$TMPDIR_CASE/shogun_escalation_decisions.tsv"
  PY="$TMPDIR_CASE/transition.py"
  # Extract transition Python from gate (same extraction as test_gate_karo_startup.bats)
  sed -n '/^import os, re, sys, tempfile$/,/^os.replace(tmp, state_path)$/p' \
    "$ROOT/scripts/gates/gate_karo_startup.sh" > "$PY"
  RECORD_SH="$ROOT/scripts/record_escalation_decision.sh"
}

teardown() { rm -rf "$TMPDIR_CASE"; }

transition() {
  SHOGUN_ESCALATION_DECISION_LEDGER="$LEDGER" \
    python3 "$PY" "$STATE" "$ALERTS" "${1:-}" 0
}

@test "判定台帳にdismissがある同一keyは再送しない" {
  echo '先送りCRITICAL: スキル静的品質WARN: gate_skill が3セッション連続' > "$ALERTS"
  # First send (no ledger yet) → SEND
  run transition
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^SEND')" -eq 1 ]
  # Shogun judges: dismiss
  SHOGUN_ESCALATION_DECISION_LEDGER="$LEDGER" \
    bash "$RECORD_SH" "スキル静的品質WARN: gate_skill" dismiss 0 "一時的状態・起票不要"
  # Resolve and re-trigger → should NOT send again
  : > "$ALERTS"
  run transition; [ -z "$output" ]
  echo '先送りCRITICAL: スキル静的品質WARN: gate_skill が5セッション連続' > "$ALERTS"
  run transition
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "内容が変化した別keyは判定済みでも送信する" {
  echo '先送りCRITICAL: スキル静的品質WARN: gate_skill が3セッション連続' > "$ALERTS"
  run transition; [ "$(printf '%s\n' "$output" | grep -c '^SEND')" -eq 1 ]
  SHOGUN_ESCALATION_DECISION_LEDGER="$LEDGER" \
    bash "$RECORD_SH" "スキル静的品質WARN: gate_skill" dismiss 0 "一時的"
  # Different alert (different key)
  : > "$ALERTS"
  run transition; [ -z "$output" ]
  echo '先送りCRITICAL: レビュー品質スケール: WARN率 30% が3セッション連続' > "$ALERTS"
  run transition
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^SEND')" -eq 1 ]
}

@test "台帳ファイルが存在しない場合はfail-openでエスカレーションを送信する" {
  echo '先送りCRITICAL: 未処理 5件 が3セッション連続' > "$ALERTS"
  # No ledger file exists
  [ ! -f "$LEDGER" ]
  run transition
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^SEND')" -eq 1 ]
}

@test "expiry_hours指定の判定は期限切れ後に再送する" {
  echo '先送りCRITICAL: WAデータ品質 3件 が3セッション連続' > "$ALERTS"
  run transition; [ "$(printf '%s\n' "$output" | grep -c '^SEND')" -eq 1 ]
  # Dismiss with 0.0001 hours (near-zero, already expired)
  DECIDED_AT="$(python3 -c 'from datetime import datetime, timedelta; print((datetime.now().astimezone() - timedelta(hours=1)).isoformat(timespec="seconds"))')"
  printf '%s\t%s\t%s\t%s\t%s\n' "WAデータ品質 #" dismiss "$DECIDED_AT" "0.0001" "短期抑止テスト" > "$LEDGER"
  # Re-trigger after expiry → should send
  : > "$ALERTS"
  run transition; [ -z "$output" ]
  echo '先送りCRITICAL: WAデータ品質 7件 が4セッション連続' > "$ALERTS"
  run transition
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^SEND')" -eq 1 ]
}

@test "record_escalation_decision.shが台帳へ正しい形式で追記する" {
  SHOGUN_ESCALATION_DECISION_LEDGER="$LEDGER" \
    bash "$RECORD_SH" "テストkey" dismiss 24 "テスト理由"
  [ -f "$LEDGER" ]
  ENTRY="$(cat "$LEDGER")"
  [[ "$ENTRY" == "テストkey	dismiss	"* ]]
  [[ "$ENTRY" == *"	24	テスト理由" ]]
}
