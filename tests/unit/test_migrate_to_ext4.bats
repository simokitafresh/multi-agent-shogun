#!/usr/bin/env bats
# test_necessity: Preserve the migration safety boundary: dry-run is side-effect-free, busy cutover is exit-2 fail-closed, and rollback restores only its declared state.

setup() {
  ROOT="$BATS_TEST_DIRNAME/../.."
  TMP_DIR="$(mktemp -d)"
  OLD_ROOT="$TMP_DIR/old"
  NEW_ROOT="$TMP_DIR/new"
  HOME_DIR="$TMP_DIR/home"
  mkdir -p "$OLD_ROOT/queue/tasks" "$NEW_ROOT/queue/tasks" \
    "$HOME_DIR/.claude/projects/-mnt-c-tools-multi-agent-shogun" \
    "$OLD_ROOT/scripts"
  cp "$ROOT/scripts/migrate_to_ext4_relocate.sh" "$OLD_ROOT/scripts/"
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
  [[ "$output" == *"DRY_RUN_RELOCATE: would run after final rsync"* ]]
  [ ! -e "$OLD_ROOT/MIGRATED_TO_EXT4.txt" ]
  [ ! -e "$NEW_ROOT/.migrate_to_ext4_crontab.backup" ]
  grep -Fqx "old-cron $OLD_ROOT" "$TEST_CRON_STATE"
}

@test "relocate replaces included references, preserves exclusions, and is idempotent" {
  mkdir -p "$NEW_ROOT/config" "$NEW_ROOT/logs" "$NEW_ROOT/queue/archive" \
    "$NEW_ROOT/docs/research" "$NEW_ROOT/memory"
  printf 'active=%s\n' "$OLD_ROOT" > "$NEW_ROOT/config/runtime.env"
  printf 'history=%s\n' "$OLD_ROOT" > "$NEW_ROOT/logs/history.log"
  printf 'archive=%s\n' "$OLD_ROOT" > "$NEW_ROOT/queue/archive/old.yaml"
  printf 'research=%s\n' "$OLD_ROOT" > "$NEW_ROOT/docs/research/old.md"
  printf 'memory=%s\n' "$OLD_ROOT" > "$NEW_ROOT/memory/old.md"

  run env OLD_ROOT="$OLD_ROOT" NEW_ROOT="$NEW_ROOT" \
    bash "$ROOT/scripts/migrate_to_ext4_relocate.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"changed_files=1 changed_occurrences=1 remaining=0"* ]]
  grep -Fqx "active=$NEW_ROOT" "$NEW_ROOT/config/runtime.env"
  grep -Fqx "history=$OLD_ROOT" "$NEW_ROOT/logs/history.log"
  grep -Fqx "archive=$OLD_ROOT" "$NEW_ROOT/queue/archive/old.yaml"

  run env OLD_ROOT="$OLD_ROOT" NEW_ROOT="$NEW_ROOT" \
    bash "$ROOT/scripts/migrate_to_ext4_relocate.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"changed_files=0 changed_occurrences=0 remaining=0"* ]]
}

@test "live cutover relocates the copied tree before declaring success" {
  mkdir -p "$OLD_ROOT/config"
  printf 'active=%s\n' "$OLD_ROOT" > "$OLD_ROOT/config/runtime.env"

  run env OLD_ROOT="$OLD_ROOT" NEW_ROOT="$NEW_ROOT" HOME="$HOME_DIR" \
    bash "$ROOT/scripts/migrate_to_ext4_cutover.sh"
  [ "$status" -eq 0 ]
  grep -Fqx "active=$NEW_ROOT" "$NEW_ROOT/config/runtime.env"
  ! grep -Fq "$OLD_ROOT" "$NEW_ROOT/config/runtime.env"
  grep -Fqx "old-cron $NEW_ROOT" "$TEST_CRON_STATE"
  [ -e "$OLD_ROOT/MIGRATED_TO_EXT4.txt" ]
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
