#!/usr/bin/env bats
# test_necessity: Preserve the migration safety boundary: dry-run is side-effect-free, busy cutover is exit-2 fail-closed, and rollback restores only its declared state.

setup() {
  ROOT="$BATS_TEST_DIRNAME/../.."
  TMP_DIR="$(mktemp -d)"
  OLD_ROOT="$TMP_DIR/old"
  NEW_ROOT="$TMP_DIR/new"
  HOME_DIR="$TMP_DIR/home"
  mkdir -p "$OLD_ROOT/queue/tasks" "$NEW_ROOT/queue/tasks" \
    "$HOME_DIR/.claude/projects/-mnt-c-tools-multi-agent-shogun"
  printf '%s\n' 'task:' '  status: idle' > "$OLD_ROOT/queue/tasks/ninja.yaml"
  printf 'old-cron %s\n' "$OLD_ROOT" > "$TMP_DIR/cron"
  mkdir -p "$TMP_DIR/bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -e' \
    'state="${TEST_CRON_STATE:?}"' \
    'if [ "$1" = "-l" ]; then cat "$state"; exit 0; fi' \
    'cp "$1" "$state"' > "$TMP_DIR/bin/crontab"
  chmod +x "$TMP_DIR/bin/crontab"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -e' \
    'case "$1" in' \
    '  list-panes) printf '\''shogun:2.1|karo\nshogun:2.2|gunshi\n'\'' ;;' \
    '  capture-pane) printf '\''›\n'\'' ;;' \
    'esac' > "$TMP_DIR/bin/tmux"
  chmod +x "$TMP_DIR/bin/tmux"
  export OLD_ROOT NEW_ROOT HOME="$HOME_DIR" TEST_CRON_STATE="$TMP_DIR/cron"
  export PATH="$TMP_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$TMP_DIR"
}

@test "cutover dry-run performs no side effects" {
  run env OLD_ROOT="$OLD_ROOT" NEW_ROOT="$NEW_ROOT" HOME="$HOME_DIR" \
    bash "$ROOT/scripts/migrate_to_ext4_cutover.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY_RUN: preflight PASS"* ]]
  [ ! -e "$OLD_ROOT/MIGRATED_TO_EXT4.txt" ]
  [ ! -e "$NEW_ROOT/.migrate_to_ext4_crontab.backup" ]
  grep -Fqx "old-cron $OLD_ROOT" "$TEST_CRON_STATE"
}

@test "cutover blocks a non-idle task with exit 2" {
  sed -i 's/status: idle/status: in_progress/' "$OLD_ROOT/queue/tasks/ninja.yaml"
  run env OLD_ROOT="$OLD_ROOT" NEW_ROOT="$NEW_ROOT" HOME="$HOME_DIR" \
    bash "$ROOT/scripts/migrate_to_ext4_cutover.sh" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"CUTOVER_BLOCKED"* ]]
}

@test "rollback dry-run and live restore are idempotent" {
  printf 'new-cron %s\n' "$NEW_ROOT" > "$NEW_ROOT/.migrate_to_ext4_crontab.backup"
  printf 'marker\n' > "$OLD_ROOT/MIGRATED_TO_EXT4.txt"
  printf 'changed\n' > "$TEST_CRON_STATE"
  run env OLD_ROOT="$OLD_ROOT" NEW_ROOT="$NEW_ROOT" HOME="$HOME_DIR" \
    bash "$ROOT/scripts/migrate_to_ext4_rollback.sh" --dry-run
  [ "$status" -eq 0 ]
  grep -Fqx changed "$TEST_CRON_STATE"
  [ -e "$OLD_ROOT/MIGRATED_TO_EXT4.txt" ]
  run env OLD_ROOT="$OLD_ROOT" NEW_ROOT="$NEW_ROOT" HOME="$HOME_DIR" \
    bash "$ROOT/scripts/migrate_to_ext4_rollback.sh"
  [ "$status" -eq 0 ]
  grep -Fqx "new-cron $NEW_ROOT" "$TEST_CRON_STATE"
  [ ! -e "$OLD_ROOT/MIGRATED_TO_EXT4.txt" ]
  run env OLD_ROOT="$OLD_ROOT" NEW_ROOT="$NEW_ROOT" HOME="$HOME_DIR" \
    bash "$ROOT/scripts/migrate_to_ext4_rollback.sh" --dry-run
  [ "$status" -eq 0 ]
}
