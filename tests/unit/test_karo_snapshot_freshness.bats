#!/usr/bin/env bats

@test "done transition publishes snapshot immediately and includes task source timestamp" {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  run python3 - "$ROOT/scripts/ninja_monitor.sh" <<'PY'
import sys
t=open(sys.argv[1], encoding='utf-8').read()
fn=t[t.index('check_and_update_done_task() {'):t.index('# ─── 案E:')]
assert '_reflux_promotion_record_completion "$report_file"' in fn
assert 'write_karo_snapshot' in fn
snap=t[t.index('write_karo_snapshot() {'):t.index('refresh_karo_snapshot_fast_path() {')]
assert '|SRC:${_task_source_ts}' in snap
PY
  [ "$status" -eq 0 ]
}
