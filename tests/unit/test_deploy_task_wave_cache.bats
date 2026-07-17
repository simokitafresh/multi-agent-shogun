#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TEST_TMPDIR="$(mktemp -d "$BATS_TEST_TMPDIR/wave-cache.XXXXXX")"
  export DEPLOY_TASK_WAVE_CACHE_DIR="$TEST_TMPDIR/cache"
  export DEPLOY_TASK_LIB_ONLY=1
  source "$PROJECT_ROOT/scripts/deploy_task.sh"
  log() { :; }
}

teardown() { rm -rf "$TEST_TMPDIR"; }

@test "4-way same source and target builds immutable snapshot once" {
  printf '234 events\n' > "$TEST_TMPDIR/memory.db"
  printf '#!/usr/bin/env bash\necho x >> "$COUNT_FILE"\nprintf result\n' > "$TEST_TMPDIR/build.sh"
  chmod +x "$TEST_TMPDIR/build.sh"
  export COUNT_FILE="$TEST_TMPDIR/count"
  for _ in 1 2 3 4; do
    deploy_task_wave_cache memory 'same-target' "$TEST_TMPDIR/memory.db" "$TEST_TMPDIR/build.sh" &
  done
  wait
  [ "$(wc -l < "$COUNT_FILE")" -eq 1 ]
}

@test "source fingerprint invalidates stale hit" {
  printf old > "$TEST_TMPDIR/source"
  printf '#!/usr/bin/env bash\necho "$VALUE"\n' > "$TEST_TMPDIR/build.sh"
  chmod +x "$TEST_TMPDIR/build.sh"
  VALUE=old deploy_task_wave_cache semantic target "$TEST_TMPDIR/source" "$TEST_TMPDIR/build.sh" > "$TEST_TMPDIR/first"
  printf new > "$TEST_TMPDIR/source"
  VALUE=new deploy_task_wave_cache semantic target "$TEST_TMPDIR/source" "$TEST_TMPDIR/build.sh" > "$TEST_TMPDIR/second"
  [ "$(cat "$TEST_TMPDIR/first")" = old ]
  [ "$(cat "$TEST_TMPDIR/second")" = new ]
}

@test "target-specific key prevents cross-target leakage" {
  printf stable > "$TEST_TMPDIR/source"
  printf '#!/usr/bin/env bash\necho "$VALUE"\n' > "$TEST_TMPDIR/build.sh"
  chmod +x "$TEST_TMPDIR/build.sh"
  VALUE=sasuke deploy_task_wave_cache memory sasuke "$TEST_TMPDIR/source" "$TEST_TMPDIR/build.sh" > "$TEST_TMPDIR/sasuke"
  VALUE=hanzo deploy_task_wave_cache memory hanzo "$TEST_TMPDIR/source" "$TEST_TMPDIR/build.sh" > "$TEST_TMPDIR/hanzo"
  [ "$(cat "$TEST_TMPDIR/sasuke")" = sasuke ]
  [ "$(cat "$TEST_TMPDIR/hanzo")" = hanzo ]
}
