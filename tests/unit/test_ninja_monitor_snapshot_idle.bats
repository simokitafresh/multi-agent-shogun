#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "write_karo_snapshot: assigned系タスクはidle行から除外し done/未配備のみ残す" {
    run bash -lc '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
export NINJA_MONITOR_LIB_ONLY=1
source "$PROJECT_ROOT/scripts/ninja_monitor.sh"
unset NINJA_MONITOR_LIB_ONLY

TMP_ROOT="$(mktemp -d)"
trap "rm -rf \"$TMP_ROOT\"" EXIT
SCRIPT_DIR="$TMP_ROOT"
LOG="$TMP_ROOT/test.log"
mkdir -p "$SCRIPT_DIR/queue/tasks" "$SCRIPT_DIR/logs"

NINJA_NAMES=(sasuke kirimaru hayate saizo kagemaru)
declare -A PREV_STATE
PREV_STATE[sasuke]="idle"
PREV_STATE[kirimaru]="idle"
PREV_STATE[hayate]="idle"
PREV_STATE[saizo]="idle"
PREV_STATE[kagemaru]="idle"

get_latest_report_file() { return 1; }
log() { :; }

cat > "$SCRIPT_DIR/queue/tasks/sasuke.yaml" <<'"'"'EOF'"'"'
task:
  task_id: cmd_634
  status: in_progress
  project: infra
EOF

cat > "$SCRIPT_DIR/queue/tasks/kirimaru.yaml" <<'"'"'EOF'"'"'
task:
  task_id: cmd_635
  status: acknowledged
  project: infra
EOF

cat > "$SCRIPT_DIR/queue/tasks/hayate.yaml" <<'"'"'EOF'"'"'
task:
  task_id: cmd_636
  status: assigned
  project: infra
EOF

cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<'"'"'EOF'"'"'
task:
  task_id: cmd_637
  status: done
  project: infra
EOF

write_karo_snapshot

snapshot="$SCRIPT_DIR/queue/karo_snapshot.txt"
grep "^ninja|sasuke|cmd_634|in_progress|infra$" "$snapshot"
grep "^ninja|kirimaru|cmd_635|acknowledged|infra$" "$snapshot"
grep "^ninja|hayate|cmd_636|assigned|infra$" "$snapshot"
grep "^ninja|saizo|cmd_637|done|infra$" "$snapshot"
grep "^ninja|kagemaru|none|idle|none$" "$snapshot"
grep "^idle|saizo,kagemaru$" "$snapshot"
'
    [ "$status" -eq 0 ]
}
