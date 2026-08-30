#!/usr/bin/env bats

# test_necessity: cleanup後発計測を採用し、容量raceをPASSへ取りこぼさない不変量を守る。
# regression_justification: 初回scan後に容量が増えた場合も最終判定がWARNになる契約を固定する。

setup() {
  fixture_root="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$fixture_root/scripts/gates" "$fixture_root/cache" "$fixture_root/logs/state" "$fixture_root/data"
  cp "$BATS_TEST_DIRNAME/../../scripts/gates/gate_three_layer_health.sh" "$fixture_root/scripts/gates/"
  cleanup="$fixture_root/scripts/cleanup_mock.sh"
  db="$fixture_root/data/test.db"
  python3 - "$db" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.executescript("""
CREATE TABLE events(state TEXT, raw_content TEXT);
INSERT INTO events VALUES ('obsidian_candidate', 'raw');
CREATE TABLE search_logs(ts TEXT, created_at TEXT);
INSERT INTO search_logs VALUES (datetime('now'), datetime('now'));
""")
db.commit()
PY
  export SHOGUN_MEMORY_DB_CACHE_PATH="$db"
  export SHOGUN_MEMORY_DB_CACHE_DIR="$fixture_root/cache"
  export SHOGUN_THREE_LAYER_CLEANUP_SCRIPT="$cleanup"
  export THREE_LAYER_CHAIN_LOG="$fixture_root/logs/missing.log"
  export THREE_LAYER_CHAIN_STATE_DIR="$fixture_root/logs/state"
}

write_cleanup() {
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\n' "$1" > "$cleanup"
  chmod +x "$cleanup"
}

@test "over-threshold capacity with reclaim candidates is an actionable BLOCK" {
  write_cleanup "tmp cleanup: cache_dir=x candidates=2 bytes=20001 total_bytes=20001 max_bytes=20000 mode=dry-run"
  run env SHOGUN_THREE_LAYER_CACHE_WARN_BYTES=20000 bash "$fixture_root/scripts/gates/gate_three_layer_health.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"bytes=12288 warn_bytes=20000"* ]]
  [[ "$output" == *"observed_bytes=12288 source=initial_scan"* ]]
  [[ "$output" == *"adopted_bytes=20001 source=cleanup_dry_run"* ]]
  [[ "$output" == *"BLOCK: cache容量が閾値超過(total_bytes=20001 > max_bytes=20000)、回収候補=2"* ]]
  [[ "$output" == *"RECOVERY:"*"--apply"*"--max-bytes 20000"* ]]
  [[ "$output" == *"STATUS: BLOCK"* ]]
}

@test "over-threshold capacity without reclaim candidates is an external-dependency BLOCK" {
  write_cleanup "tmp cleanup: cache_dir=x candidates=0 bytes=0 total_bytes=20001 max_bytes=20000 mode=dry-run"
  run env SHOGUN_THREE_LAYER_CACHE_WARN_BYTES=20000 bash "$fixture_root/scripts/gates/gate_three_layer_health.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"adopted_bytes=20001 source=cleanup_dry_run"* ]]
  [[ "$output" == *"external_dependency=protected_or_nonreclaimable"* ]]
  [[ "$output" == *"回収不能をWARNで継続せず"* ]]
  [[ "$output" == *"STATUS: BLOCK"* ]]
}

@test "both measurements within threshold preserve PASS including equality" {
  write_cleanup "tmp cleanup: cache_dir=x candidates=0 bytes=0 total_bytes=20000 max_bytes=20000 mode=dry-run"
  run env SHOGUN_THREE_LAYER_CACHE_WARN_BYTES=20000 bash "$fixture_root/scripts/gates/gate_three_layer_health.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"adopted_bytes=20000 source=cleanup_dry_run"* ]]
  [[ "$output" == *"STATUS: PASS"* ]]
}

@test "missing cleanup total fails closed" {
  write_cleanup "tmp cleanup: cache_dir=x candidates=0 bytes=0 mode=dry-run"
  run env SHOGUN_THREE_LAYER_CACHE_WARN_BYTES=100 bash "$fixture_root/scripts/gates/gate_three_layer_health.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"total_bytesを解釈できない"* ]]
  [[ "$output" == *"STATUS: BLOCK"* ]]
}

@test "nonnumeric cleanup total fails closed and dry-run executes once" {
  counter="$fixture_root/counter"
  cat > "$cleanup" <<EOF
#!/usr/bin/env bash
printf x >> "$counter"
echo 'tmp cleanup: cache_dir=x candidates=0 bytes=0 total_bytes=bad max_bytes=100 mode=dry-run'
EOF
  chmod +x "$cleanup"
  run env SHOGUN_THREE_LAYER_CACHE_WARN_BYTES=100 bash "$fixture_root/scripts/gates/gate_three_layer_health.sh"
  [ "$status" -eq 2 ]
  [ "$(wc -c < "$counter")" -eq 1 ]
  [[ "$output" == *"STATUS: BLOCK"* ]]
}

# ─── cache追随gapのtelemetry (cmd_karo_impl_cache_gap_telemetry_20260726) ───
# test_necessity: 追随チェックの判定値が既存台帳へ1実行1行だけ残り、測定不能時も
# 欠測として明示記録される不変量を守る(記録が無いことを正常と読み違えないため)。

_gap_ledger_lines() {
  # grep -c は不一致時に0を出力しつつ exit 1 を返す。|| で握ると値が二重に出るため
  # 出力は捨てて自前で数える。
  local n
  n="$(grep -c '"source":"three_layer_health"' "$ledger" 2>/dev/null)" || n=0
  printf '%s' "${n:-0}"
}

setup_gap_ledger() {
  ledger="$fixture_root/logs/defense_overhead.jsonl"
  : > "$ledger"
  export DEFENSE_OVERHEAD_LEDGER="$ledger"
  # gateは repo_root/scripts/lib/ から共有writerをsourceする。fixtureにも
  # 実物を置かないと記録経路そのものが走らず、検査が空振りする。
  mkdir -p "$fixture_root/scripts/lib"
  cp "$BATS_TEST_DIRNAME/../../scripts/lib/defense_overhead_writer.sh" \
    "$fixture_root/scripts/lib/"
  # writerはevent_id重複排除のためsidecar helperも直接ロードする。
  cp "$BATS_TEST_DIRNAME/../../scripts/lib/defense_overhead_event_index.py" \
    "$fixture_root/scripts/lib/"
}

@test "measurable cache gap appends exactly one ledger line carrying gap and both rowids" {
  setup_gap_ledger
  write_cleanup "tmp cleanup: cache_dir=x candidates=0 bytes=0 total_bytes=0 max_bytes=100 mode=dry-run"
  run env SHOGUN_THREE_LAYER_CACHE_WARN_BYTES=200000 SHOGUN_MEMORY_DB="$db" \
    bash "$fixture_root/scripts/gates/gate_three_layer_health.sh"
  [ "$status" -eq 0 ]
  sleep 1
  [ "$(_gap_ledger_lines)" -eq 1 ]
  line="$(grep '"source":"three_layer_health"' "$ledger")"
  [[ "$line" == *'"check_id":"cache_rowid_gap"'* ]]
  [[ "$line" == *'cache_rowid_gap:cache-'* ]]
  [[ "$line" == *':source-'* ]]
  [[ "$line" == *':gap-'* ]]
  [[ "$line" == *':warn-'* ]]
  # 持続時間を後から算出するにはtimestampが要る。
  [[ "$line" == *'"timestamp"'* ]]
}

@test "unreadable rowid watermark records an explicit unmeasured line instead of silence" {
  setup_gap_ledger
  write_cleanup "tmp cleanup: cache_dir=x candidates=0 bytes=0 total_bytes=0 max_bytes=100 mode=dry-run"
  printf 'not a database\n' > "$fixture_root/data/broken.db"
  run env SHOGUN_THREE_LAYER_CACHE_WARN_BYTES=200000 \
    SHOGUN_MEMORY_DB="$fixture_root/data/broken.db" \
    SHOGUN_MEMORY_DB_CACHE_PATH="$fixture_root/data/broken.db" \
    bash "$fixture_root/scripts/gates/gate_three_layer_health.sh"
  # 測定不能でもgate自体は落ちない(診断プローブの失敗を判定へ波及させない)。
  [ "$status" -ne 1 ]
  sleep 1
  [ "$(_gap_ledger_lines)" -eq 1 ]
  [[ "$(grep '"source":"three_layer_health"' "$ledger")" == *':gap-na:'* ]]
}

@test "telemetry append does not alter judgement output or exit status" {
  setup_gap_ledger
  write_cleanup "tmp cleanup: cache_dir=x candidates=0 bytes=0 total_bytes=20001 max_bytes=20000 mode=dry-run"
  run env SHOGUN_THREE_LAYER_CACHE_WARN_BYTES=20000 SHOGUN_MEMORY_DB="$db" \
    bash "$fixture_root/scripts/gates/gate_three_layer_health.sh"
  # 容量超過はtelemetry追加後もBLOCK/exit 2で、判定値と標準出力を汚染しない。
  [ "$status" -eq 2 ]
  [[ "$output" == *"STATUS: BLOCK"* ]]
  # jsonl追記の副作用が標準出力へ混ざらないこと。
  [[ "$output" != *"defense_overhead"* ]]
  [[ "$output" != *'"check_id"'* ]]
}
