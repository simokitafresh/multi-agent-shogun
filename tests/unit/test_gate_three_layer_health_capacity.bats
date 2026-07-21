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

@test "later cleanup total above threshold makes final status WARN" {
  write_cleanup "tmp cleanup: cache_dir=x candidates=0 bytes=0 total_bytes=20001 max_bytes=20000 mode=dry-run"
  run env SHOGUN_THREE_LAYER_CACHE_WARN_BYTES=20000 bash "$fixture_root/scripts/gates/gate_three_layer_health.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"bytes=12288 warn_bytes=20000"* ]]
  [[ "$output" == *"adopted_bytes=20001 source=cleanup_dry_run"* ]]
  [[ "$output" == *"STATUS: WARN"* ]]
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
  [[ "$output" == *"STATUS: WARN"* ]]
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
  [[ "$output" == *"STATUS: WARN"* ]]
}
