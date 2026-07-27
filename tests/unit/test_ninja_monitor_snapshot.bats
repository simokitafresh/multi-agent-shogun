#!/usr/bin/env bats
# test_necessity: task publication must update the recovery snapshot synchronously even while the main monitor cycle is blocked

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "task assignment refresh preserves runtime fields and tracks four transition cases" {
  run bash -c '
set -euo pipefail
ROOT="'"$ROOT"'"
TMP="'"$BATS_TEST_TMPDIR"'/snapshot-parity"
mkdir -p "$TMP/queue/tasks" "$TMP/queue"
export KARO_SNAPSHOT_LOCK_FILE="$TMP/karo_snapshot.lock"
cat > "$TMP/queue/karo_snapshot.txt" <<EOF
# 家老陣形図(karo_snapshot) — ninja_monitor.sh自動生成
# Generated: 2026-07-22T03:20:52
ninja|saizo|cmd_4114_full|idle|dm-signal|CTX:11%|M:GPT|SRC:2026-07-22T03:20:52|TASK:idle|RUNTIME:idle
idle|saizo
EOF

publish() {
  local task_id="$1" status="$2"
  cat > "$TMP/queue/tasks/saizo.yaml" <<EOF
task:
  task_id: $task_id
  status: $status
  project: infra
EOF
  NINJA_MONITOR_LIB_ONLY=1 SHOGUN_TEST_ROOT="$TMP" bash -c '\''
    source "'"$ROOT"'/scripts/ninja_monitor.sh"
    SCRIPT_DIR="$SHOGUN_TEST_ROOT"
    refresh_karo_snapshot_task_assignment saizo
  '\''
}

# task switch / pane reality can start immediately after atomic publication.
publish cmd_4115_full assigned
grep -q "^ninja|saizo|cmd_4115_full|assigned|infra|CTX:11%|M:GPT|.*|TASK:assigned|RUNTIME:busy$" "$TMP/queue/karo_snapshot.txt"
grep -q "^idle|none$" "$TMP/queue/karo_snapshot.txt"

# assigned -> in_progress.
publish cmd_4115_full in_progress
grep -q "^ninja|saizo|cmd_4115_full|in_progress|infra|.*|TASK:in_progress|RUNTIME:busy$" "$TMP/queue/karo_snapshot.txt"

# failed generation -> a newly assigned generation.
publish cmd_failed failed
grep -q "^ninja|saizo|cmd_failed|failed|infra|.*|TASK:failed|RUNTIME:idle$" "$TMP/queue/karo_snapshot.txt"
publish cmd_recovery assigned
grep -q "^ninja|saizo|cmd_recovery|assigned|infra|.*|TASK:assigned|RUNTIME:busy$" "$TMP/queue/karo_snapshot.txt"

# terminal transition restores the idle roster exactly once.
publish cmd_recovery done
grep -q "^ninja|saizo|cmd_recovery|done|infra|.*|TASK:done|RUNTIME:idle$" "$TMP/queue/karo_snapshot.txt"
test "$(grep "^idle|" "$TMP/queue/karo_snapshot.txt")" = "idle|saizo"
printf "parity=5/5 mismatch=0 preserved_ctx_model=2/2\n"
'
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output"
    false
  fi
  [[ "$output" == *"parity=5/5 mismatch=0 preserved_ctx_model=2/2"* ]]
}

# test_necessity: commander line in karo_snapshot.txt must stay exactly one line per
# commander regardless of unread count (0/1+/unreadable-file), because a doubled line
# corrupts every downstream parser (dashboard/gate) that assumes one record per key.
@test "commander UNREAD line stays single-scalar across 0/1/read-error inbox states" {
  run bash -c '
set -euo pipefail
ROOT="'"$ROOT"'"
TMP="'"$BATS_TEST_TMPDIR"'/commander-unread"
mkdir -p "$TMP/queue/tasks" "$TMP/queue/inbox" "$TMP/queue/reports"
export KARO_SNAPSHOT_LOCK_FILE="$TMP/karo_snapshot.lock"

snapshot_karo_line() {
  NINJA_MONITOR_LIB_ONLY=1 SHOGUN_TEST_ROOT="$TMP" bash -c '\''
    source "'"$ROOT"'/scripts/ninja_monitor.sh"
    SCRIPT_DIR="$SHOGUN_TEST_ROOT"
    write_karo_snapshot
  '\'' >/dev/null 2>&1
  grep "^commander|karo|" "$TMP/queue/karo_snapshot.txt"
}

printf "messages:\n- id: g1\n  read: false\n" > "$TMP/queue/inbox/gunshi.yaml"

# case 1: 0 unread
printf "messages:\n" > "$TMP/queue/inbox/karo.yaml"
lines1=$(snapshot_karo_line)
count1=$(printf "%s\n" "$lines1" | grep -c "^commander|karo|")
unread1=$(printf "%s\n" "$lines1" | grep -o "UNREAD:[0-9]*" | head -1)
[ "$count1" -eq 1 ]
[ "$unread1" = "UNREAD:0" ]

# case 2: 1 unread
printf "messages:\n- id: k1\n  read: false\n" > "$TMP/queue/inbox/karo.yaml"
lines2=$(snapshot_karo_line)
count2=$(printf "%s\n" "$lines2" | grep -c "^commander|karo|")
unread2=$(printf "%s\n" "$lines2" | grep -o "UNREAD:[0-9]*" | head -1)
[ "$count2" -eq 1 ]
[ "$unread2" = "UNREAD:1" ]

# case 3: read-error (inbox file missing)
rm -f "$TMP/queue/inbox/karo.yaml"
lines3=$(snapshot_karo_line)
count3=$(printf "%s\n" "$lines3" | grep -c "^commander|karo|")
unread3=$(printf "%s\n" "$lines3" | grep -o "UNREAD:[0-9]*" | head -1)
[ "$count3" -eq 1 ]
[ "$unread3" = "UNREAD:0" ]

printf "commander_lines=1/1/1 false_positive=0 false_negative=0\n"
'
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output"
    false
  fi
  [[ "$output" == *"commander_lines=1/1/1 false_positive=0 false_negative=0"* ]]
}

@test "snapshot assignment refresh is independent of the blocked main loop" {
  run python3 - "$ROOT/scripts/ninja_monitor.sh" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
fn = text[text.index("refresh_karo_snapshot_task_assignment() {"):text.index("# ─── CLI死亡検知")]
assert "flock -x -w 5 200" in fn
assert "mv \"$tmp_file\" \"$snapshot_file\"" in fn
guard = text[text.index("if [ \"${NINJA_MONITOR_LIB_ONLY:-0}\" = \"1\" ]; then"):text.index("# 旧monitor")]
assert "--refresh-snapshot-task" in guard
PY
  [ "$status" -eq 0 ]
}
