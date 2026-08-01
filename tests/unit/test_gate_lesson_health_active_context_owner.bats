#!/usr/bin/env bats
# test_necessity: active context DEFER requires one fresh exact owner plus dirty changed blob and exact lease boundaries.
setup(){ ROOT="$(mktemp -d /tmp/aco.XXXXXX)"; mkdir -p "$ROOT/queue/tasks" "$ROOT/context"; git -C "$ROOT" init -q; printf 'base\n' > "$ROOT/context/infrastructure.md"; git -C "$ROOT" add .; git -C "$ROOT" -c user.name=t -c user.email=t@x commit -qm b; BASE=$(git -C "$ROOT" hash-object context/infrastructure.md); printf 'changed\n' > "$ROOT/context/infrastructure.md"; }
teardown(){ rm -rf "$ROOT"; }
task(){ printf '%s\n' 'task:' '  status: in_progress' '  planned_paths: [context/infrastructure.md]' "  target_path_worktree_blob_at_deploy: $BASE" "  progress_updated_at: '$1'" > "$ROOT/queue/tasks/a.yaml"; }
@test "fresh exact changed dirty owner passes and lease boundaries fail closed" {
  for pair in '2026-08-01T11:40:00Z:0' '2026-08-01T11:39:59Z:1' '2026-08-01T12:00:05Z:0' '2026-08-01T12:00:06Z:1'; do
    task "${pair%:*}"; run env ACTIVE_CONTEXT_NOW=2026-08-01T12:00:00Z bash -c 'source "$1"; active_context_defer_allowed "$2" context/infrastructure.md' _ "$BATS_TEST_DIRNAME/../../scripts/lib/yaml_field_set.sh" "$ROOT"
    if [ "${pair##*:}" -eq 0 ]; then [ "$status" -eq 0 ]; else [ "$status" -ne 0 ]; fi
  done
}
