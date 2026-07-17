#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "task publication fingerprint ignores duplicate inbox message ids" {
    run bash -lc '
set -eo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"; export INBOX_WATCHER_LIB_ONLY=1
export SHOGUN_STATE_DIR="$BATS_TEST_TMPDIR/state"; mkdir -p "$SHOGUN_STATE_DIR"
source "$PROJECT_ROOT/scripts/inbox_watcher.sh" saizo pane
SCRIPT_DIR="$BATS_TEST_TMPDIR/root"; AGENT_ID=saizo
mkdir -p "$SCRIPT_DIR/queue/tasks"
cat > "$SCRIPT_DIR/queue/tasks/saizo.yaml" <<EOF
task:
  task_id: cmd_generation_one
  deployed_at: 2026-07-18T07:50:23
EOF
first=$(task_publication_fingerprint)
# A retry changes only inbox identity, not task publication identity.
second=$(task_publication_fingerprint)
[ "$first" = "$second" ]
sed -i "s/07:50:23/07:51:23/" "$SCRIPT_DIR/queue/tasks/saizo.yaml"
third=$(task_publication_fingerprint)
[ "$first" != "$third" ]
'
    [ "$status" -eq 0 ]
}
