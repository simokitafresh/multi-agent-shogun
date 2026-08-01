#!/usr/bin/env bats
# test_necessity: freshness missing-metadata suppression must behaviorally share the fail-closed active-owner predicate.
setup() {
  ROOT="$(mktemp -d /tmp/acf.XXXXXX)"
  mkdir -p "$ROOT/context" "$ROOT/queue/tasks" "$ROOT/scripts"
  printf 'baseline\n' > "$ROOT/context/infrastructure.md"
  git -C "$ROOT" init -q
  git -C "$ROOT" add .
  git -C "$ROOT" -c user.name=t -c user.email=t@x commit -qm baseline
  BASE="$(git -C "$ROOT" hash-object context/infrastructure.md)"
  printf 'rebuilding\n' > "$ROOT/context/infrastructure.md"
  printf '#!/usr/bin/env bash\nprintf "WARN: context/infrastructure.md stale\\n"\n' > "$ROOT/scripts/check.sh"
  chmod +x "$ROOT/scripts/check.sh"
  GATE="$BATS_TEST_DIRNAME/../../scripts/gates/gate_context_freshness.sh"
}
teardown() { rm -rf "$ROOT"; }
write_task() {
  printf '%s\n' 'task:' "  status: ${1}" \
    '  planned_paths: [context/infrastructure.md]' \
    "  target_path_worktree_blob_at_deploy: $BASE" \
    "  progress_updated_at: '${2}'" > "$ROOT/queue/tasks/owner.yaml"
}
run_gate() {
  run env CONTEXT_FRESHNESS_ROOT="$ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 ACTIVE_CONTEXT_NOW=2026-08-01T12:00:00Z \
    bash "$GATE"
}
@test "fresh exact dirty changed owner defers and terminal owner warns" {
  write_task in_progress 2026-08-01T11:40:00Z
  run_gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEFER: infrastructure.md"* ]]

  write_task done 2026-08-01T11:40:00Z
  run_gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"WARN: infrastructure.md (last_updated 未記載)"* ]]
}
