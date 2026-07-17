#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPROOT="$BATS_TEST_TMPDIR/case"
  mkdir -p "$TMPROOT/bin" "$TMPROOT/out"
  SOURCE="$TMPROOT/source"
  mkdir -p "$SOURCE/skills/campaign-lane" "$SOURCE/tests/unit"
  git init -q "$SOURCE"
  git -C "$SOURCE" config user.email test@example.invalid
  git -C "$SOURCE" config user.name test
  printf base >"$SOURCE/skills/campaign-lane/base"
  git -C "$SOURCE" add skills/campaign-lane/base
  git -C "$SOURCE" commit -qm fixture
  FIXED_SHA="$(git -C "$SOURCE" rev-parse HEAD)"
}

make_deployer() {
  local mode="$1"
  cat >"$TMPROOT/bin/deploy" <<'SH'
#!/usr/bin/env bash
task_path="$1"
readarray -t fields < <(python3 - "$task_path" <<'PY'
import sys,yaml
t=yaml.safe_load(open(sys.argv[1]))['task']; print(t['report_path']); print(t['workdir']); print(t['implementation_path']); print(t['test_path'])
PY
)
report_path="${fields[0]}"; workdir="${fields[1]}"; implementation="${fields[2]}"; test_path="${fields[3]}"
mkdir -p "$(dirname "$implementation")" "$(dirname "$test_path")"
printf impl >"$implementation"; printf test >"$test_path"
git -C "$workdir" config user.email test@example.invalid
git -C "$workdir" config user.name test
git -C "$workdir" add "${implementation#$workdir/}" "${test_path#$workdir/}"
git -C "$workdir" commit -qm shard
head="$(git -C "$workdir" rev-parse HEAD)"
case "${TEST_MODE}" in
  pass) printf 'status: completed\nverdict: PASS\ncommit_hash: %s\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}, {path: tests/unit/test_new.py}]\noperational_simulation: {command: bats test, expected: FAIL0 SKIP0, actual: "TOTAL=3 FAIL=0 SKIP=0", result: PASS}\n' "$head" >"$report_path" ;;
  fail) printf 'status: failed\nverdict: FAIL\n' >"$report_path" ;;
  metrics_missing) printf 'status: completed\nverdict: PASS\ncommit_hash: %s\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}, {path: tests/unit/test_new.py}]\noperational_simulation: {result: PASS}\n' "$head" >"$report_path" ;;
  fail_count) printf 'status: completed\nverdict: PASS\ncommit_hash: %s\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}, {path: tests/unit/test_new.py}]\noperational_simulation: {actual: "TOTAL=3 FAIL=1 SKIP=0", result: PASS}\n' "$head" >"$report_path" ;;
  skip_count) printf 'status: completed\nverdict: PASS\ncommit_hash: %s\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}, {path: tests/unit/test_new.py}]\noperational_simulation: {actual: "TOTAL=3 FAIL=0 SKIP=1", result: PASS}\n' "$head" >"$report_path" ;;
  fake_commit) printf 'status: completed\nverdict: PASS\ncommit_hash: 0123456789012345678901234567890123456789\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}, {path: tests/unit/test_new.py}]\noperational_simulation: {actual: "TOTAL=3 FAIL=0 SKIP=0", result: PASS}\n' >"$report_path" ;;
  missing_owned) printf 'status: completed\nverdict: PASS\ncommit_hash: %s\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}]\noperational_simulation: {actual: "TOTAL=3 FAIL=0 SKIP=0", result: PASS}\n' "$head" >"$report_path" ;;
  dirty) printf dirty >>"$implementation"; printf 'status: completed\nverdict: PASS\ncommit_hash: %s\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}, {path: tests/unit/test_new.py}]\noperational_simulation: {actual: "TOTAL=3 FAIL=0 SKIP=0", result: PASS}\n' "$head" >"$report_path" ;;
  scope_extra) printf extra >"$workdir/extra.txt"; git -C "$workdir" add extra.txt; git -C "$workdir" commit -qm extra; head="$(git -C "$workdir" rev-parse HEAD)"; printf 'status: completed\nverdict: PASS\ncommit_hash: %s\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}, {path: tests/unit/test_new.py}]\noperational_simulation: {actual: "TOTAL=3 FAIL=0 SKIP=0", result: PASS}\n' "$head" >"$report_path" ;;
  crash) exit 9 ;;
  timeout) : ;;
esac
SH
  chmod +x "$TMPROOT/bin/deploy"
  export TEST_MODE="$mode"
}

run_bridge() {
  item_json='{"id":"item","path":"skills/campaign-lane/adapters/new.py","owned_paths":["skills/campaign-lane/adapters/new.py","tests/unit/test_new.py"]}'
  run env SHARD_ITEM_JSON="$item_json" CAMPAIGN_LANE_FIXED_SHA="$FIXED_SHA" CAMPAIGN_LANE_SOURCE_REPO="$SOURCE" CAMPAIGN_LANE_DEPLOY_CMD="$TMPROOT/bin/deploy" \
    CAMPAIGN_LANE_WAIT_SEC=1 CAMPAIGN_LANE_POLL_SEC=0.1 \
    "$ROOT/scripts/campaign_lane_shard_item.sh" item skills/campaign-lane/adapters/new.py worker "$TMPROOT/work" "$TMPROOT/out"
}

reason_is() {
  python3 - "$TMPROOT/out/result.json" "$1" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['reason_code'] == sys.argv[2]
PY
}

@test "normal report PASS maps to shard success" {
  make_deployer pass
  run_bridge
  [ "$status" -eq 0 ]
  reason_is report_terminal_pass
}

@test "generated task preserves list AC and typed ownership scalars" {
  make_deployer pass
  run_bridge
  [ "$status" -eq 0 ]
  python3 - "$TMPROOT/out/task.yaml" "$TMPROOT/work" <<'PY'
import json, os, sys, yaml
task=yaml.safe_load(open(sys.argv[1]))['task']; work=os.path.realpath(sys.argv[2])
assert isinstance(task['acceptance_criteria'], list)
owned=json.loads(task['owned_paths_json']); assert len(owned)==2
assert os.path.commonpath([work, os.path.realpath(task['target_path'])]) == work
assert {task['implementation_path'], task['test_path']} == set(owned)
PY
}

@test "wrong fixed SHA fails closed with result" {
  make_deployer pass
  run env SHARD_ITEM_JSON='{"path":"skills/campaign-lane/adapters/new.py","owned_paths":["skills/campaign-lane/adapters/new.py","tests/unit/test_new.py"]}' CAMPAIGN_LANE_FIXED_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa CAMPAIGN_LANE_SOURCE_REPO="$SOURCE" CAMPAIGN_LANE_DEPLOY_CMD="$TMPROOT/bin/deploy" \
    "$ROOT/scripts/campaign_lane_shard_item.sh" item skills/campaign-lane/adapters/new.py worker "$TMPROOT/work" "$TMPROOT/out"
  [ "$status" -ne 0 ]
  reason_is source_materialize_failed
}

@test "dirty materialized worktree is rejected" {
  mkdir -p "$TMPROOT/work"
  git clone -q --local "$SOURCE" "$TMPROOT/work"
  git -C "$TMPROOT/work" checkout -q --detach "$FIXED_SHA"
  printf dirty >>"$TMPROOT/work/skills/campaign-lane/base"
  make_deployer pass
  run env SHARD_ITEM_JSON='{"path":"skills/campaign-lane/adapters/new.py","owned_paths":["skills/campaign-lane/adapters/new.py","tests/unit/test_new.py"]}' CAMPAIGN_LANE_FIXED_SHA="$FIXED_SHA" CAMPAIGN_LANE_SOURCE_REPO="$SOURCE" CAMPAIGN_LANE_DEPLOY_CMD="$TMPROOT/bin/deploy" \
    "$ROOT/scripts/campaign_lane_shard_item.sh" item skills/campaign-lane/adapters/new.py worker "$TMPROOT/work" "$TMPROOT/out"
  [ "$status" -ne 0 ]
  reason_is source_materialize_failed
}

@test "invalid missing parent path fails before deploy" {
  make_deployer pass
  run env SHARD_ITEM_JSON='{"path":"missing/path/new.py","owned_paths":["missing/path/new.py","tests/unit/test_new.py"]}' CAMPAIGN_LANE_FIXED_SHA="$FIXED_SHA" CAMPAIGN_LANE_SOURCE_REPO="$SOURCE" CAMPAIGN_LANE_DEPLOY_CMD="$TMPROOT/bin/deploy" \
    "$ROOT/scripts/campaign_lane_shard_item.sh" item missing/path/new.py worker "$TMPROOT/work" "$TMPROOT/out"
  [ "$status" -ne 0 ]
  reason_is invalid_item_path
}

@test "owned_paths missing duplicate and traversal are blocked" {
  for item_json in \
    '{"path":"skills/campaign-lane/adapters/new.py"}' \
    '{"path":"skills/campaign-lane/adapters/new.py","owned_paths":["skills/campaign-lane/adapters/new.py","skills/campaign-lane/adapters/new.py"]}' \
    '{"path":"skills/campaign-lane/adapters/new.py","owned_paths":["skills/campaign-lane/adapters/new.py","../escape.py"]}'
  do
    run env SHARD_ITEM_JSON="$item_json" CAMPAIGN_LANE_FIXED_SHA="$FIXED_SHA" CAMPAIGN_LANE_SOURCE_REPO="$SOURCE" \
      "$ROOT/scripts/campaign_lane_shard_item.sh" item skills/campaign-lane/adapters/new.py worker "$TMPROOT/work-$RANDOM" "$TMPROOT/out-$RANDOM"
    [ "$status" -ne 0 ]
  done
}

@test "universal shard exports canonical item metadata" {
  manifest="$TMPROOT/manifest.yaml"
  capture="$TMPROOT/item.json"
  printf 'state_dir: %s\nreservation_root: %s\nmax_workers: 2\ncommand: "printf %%s \\\"$SHARD_ITEM_JSON\\\" > %s-{item_id}"\nitems:\n  - {id: a, path: skills/a, weight: 1, capability: x, owned_paths: [skills/a, tests/a]}\n  - {id: b, path: skills/b, weight: 1, capability: x, owned_paths: [skills/b, tests/b]}\nworkers:\n  - {id: A, idle: true, capabilities: [x]}\n  - {id: B, idle: true, capabilities: [x]}\n' "$TMPROOT/state" "$TMPROOT/leases" "$capture" >"$manifest"
  run python3 "$ROOT/scripts/universal_shard.py" "$manifest" --run
  [ "$status" -eq 0 ]
  python3 - "$capture-a" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); assert d['id']=='a' and d['owned_paths']==['skills/a','tests/a']
PY
}

@test "report timeout fails closed" {
  make_deployer timeout
  run_bridge
  [ "$status" -ne 0 ]
  reason_is report_timeout
}

@test "deploy crash fails closed and cannot become success" {
  make_deployer crash
  run_bridge
  [ "$status" -ne 0 ]
  reason_is deploy_failed
}

@test "terminal report FAIL maps to shard fail" {
  make_deployer fail
  run_bridge
  [ "$status" -ne 0 ]
  reason_is report_terminal_fail
}

@test "missing standard operational metrics fails closed" {
  make_deployer metrics_missing
  run_bridge
  [ "$status" -ne 0 ]
  reason_is report_metrics_missing
}

@test "FAIL1 operational metrics cannot become success" {
  make_deployer fail_count
  run_bridge
  [ "$status" -ne 0 ]
  reason_is report_metrics_missing
}

@test "SKIP1 operational metrics cannot become success" {
  make_deployer skip_count
  run_bridge
  [ "$status" -ne 0 ]
  reason_is report_metrics_missing
}

@test "fake terminal commit is rejected" {
  make_deployer fake_commit
  run_bridge
  [ "$status" -ne 0 ]
  reason_is terminal_commit_mismatch
}

@test "report missing one owned file is rejected" {
  make_deployer missing_owned
  run_bridge
  [ "$status" -ne 0 ]
  reason_is terminal_scope_mismatch
}

@test "terminal dirty worktree is rejected" {
  make_deployer dirty
  run_bridge
  [ "$status" -ne 0 ]
  reason_is terminal_scope_mismatch
}

@test "scope outside owned paths is rejected" {
  make_deployer scope_extra
  run_bridge
  [ "$status" -ne 0 ]
  reason_is terminal_scope_mismatch
}
