#!/usr/bin/env bats
# test_necessity: Commit hash verification and scope boundary enforcement prevent fake/dirty/out-of-scope commits; violation is BLOCK.

setup_file() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  [ "$(git -C "$ROOT" ls-files --stage scripts/campaign_lane_shard_item.sh | cut -d' ' -f1)" = 100755 ]
  SHARED_SOURCE="$BATS_FILE_TMPDIR/source-fixture"
  mkdir -p "$SHARED_SOURCE/skills/campaign-lane/scripts" "$SHARED_SOURCE/tests/unit"
  git init -q "$SHARED_SOURCE"
  git -C "$SHARED_SOURCE" config user.email test@example.invalid
  git -C "$SHARED_SOURCE" config user.name test
  printf base >"$SHARED_SOURCE/skills/campaign-lane/base"
  : >"$SHARED_SOURCE/tests/unit/.keep"
  cp "$ROOT/skills/campaign-lane/scripts/"{__init__.py,contracts.py,adapter_sdk.py,outcome_ledger.py} "$SHARED_SOURCE/skills/campaign-lane/scripts/"
  git -C "$SHARED_SOURCE" add skills/campaign-lane/base skills/campaign-lane/scripts tests/unit/.keep
  git -C "$SHARED_SOURCE" commit -qm fixture
  FIXTURE_FINGERPRINT="$(PYTHONPATH="$SHARED_SOURCE/skills/campaign-lane" python3 -c 'from scripts.contracts import contract_fingerprint; print(contract_fingerprint())')"
  export FIXTURE_FINGERPRINT
}

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPROOT="$BATS_TEST_TMPDIR/case"
  mkdir -p "$TMPROOT/bin" "$TMPROOT/out"
  SOURCE="$TMPROOT/source"
  git clone -q --shared "$BATS_FILE_TMPDIR/source-fixture" "$SOURCE"
  git -C "$SOURCE" config user.email test@example.invalid
  git -C "$SOURCE" config user.name test
  FIXED_SHA="$(git -C "$SOURCE" rev-parse HEAD)"
  export CAMPAIGN_LANE_CHECKOUT_ROOT="$TMPROOT/scratch"
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
git -C "$workdir" add "${implementation#$workdir/}" "${test_path#$workdir/}"
git -C "$workdir" commit -qm shard
head="$(git -C "$workdir" rev-parse HEAD)"
case "${TEST_MODE}" in
  pass) printf 'status: completed\nverdict: PASS\ncommit_hash: %s\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}, {path: tests/unit/test_new.py}]\nstage_duration_sec: {test: 2, commit: 1}\noperational_simulation: {command: bats test, expected: FAIL0 SKIP0, actual: "TOTAL=3 FAIL=0 SKIP=0", result: PASS}\n' "$head" >"$report_path" ;;
  fail) printf 'status: failed\nverdict: FAIL\n' >"$report_path" ;;
  metrics_missing) printf 'status: completed\nverdict: PASS\ncommit_hash: %s\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}, {path: tests/unit/test_new.py}]\noperational_simulation: {result: PASS}\n' "$head" >"$report_path" ;;
  metrics_missing_with_bad_commit) printf 'status: completed\nverdict: PASS\ncommit_hash: 0123456789012345678901234567890123456789\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}, {path: tests/unit/test_new.py}]\noperational_simulation: {result: PASS}\n' >"$report_path" ;;
  fail_count) printf 'status: completed\nverdict: PASS\ncommit_hash: %s\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}, {path: tests/unit/test_new.py}]\noperational_simulation: {actual: "TOTAL=3 FAIL=1 SKIP=0", result: PASS}\n' "$head" >"$report_path" ;;
  skip_count) printf 'status: completed\nverdict: PASS\ncommit_hash: %s\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}, {path: tests/unit/test_new.py}]\noperational_simulation: {actual: "TOTAL=3 FAIL=0 SKIP=1", result: PASS}\n' "$head" >"$report_path" ;;
  fake_commit) printf 'status: completed\nverdict: PASS\ncommit_hash: 0123456789012345678901234567890123456789\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}, {path: tests/unit/test_new.py}]\noperational_simulation: {actual: "TOTAL=3 FAIL=0 SKIP=0", result: PASS}\n' >"$report_path" ;;
  missing_owned) printf 'status: completed\nverdict: PASS\ncommit_hash: %s\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}]\noperational_simulation: {actual: "TOTAL=3 FAIL=0 SKIP=0", result: PASS}\n' "$head" >"$report_path" ;;
  dirty) printf dirty >>"$implementation"; printf 'status: completed\nverdict: PASS\ncommit_hash: %s\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}, {path: tests/unit/test_new.py}]\noperational_simulation: {actual: "TOTAL=3 FAIL=0 SKIP=0", result: PASS}\n' "$head" >"$report_path" ;;
  scope_extra) printf extra >"$workdir/extra.txt"; git -C "$workdir" add extra.txt; git -C "$workdir" commit -qm extra; head="$(git -C "$workdir" rev-parse HEAD)"; printf 'status: completed\nverdict: PASS\ncommit_hash: %s\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}, {path: tests/unit/test_new.py}]\noperational_simulation: {actual: "TOTAL=3 FAIL=0 SKIP=0", result: PASS}\n' "$head" >"$report_path" ;;
  canonical_redirect)
    canonical="$(dirname "$report_path")/canonical-report.yaml"
    python3 - "$task_path" "$canonical" <<'PY'
import sys, yaml
path, canonical = sys.argv[1:]
data = yaml.safe_load(open(path, encoding='utf-8'))
data['task']['report_path'] = canonical
with open(path, 'w', encoding='utf-8') as stream:
    yaml.safe_dump(data, stream, allow_unicode=True, sort_keys=False)
PY
    printf 'status: completed\nverdict: PASS\ncommit_hash: %s\nfiles_modified: [{path: skills/campaign-lane/adapters/new.py}, {path: tests/unit/test_new.py}]\noperational_simulation: {actual: "TOTAL=3 FAIL=0 SKIP=0", result: PASS}\n' "$head" >"$canonical"
    ;;
  crash) exit 9 ;;
  timeout) : ;;
esac
SH
  chmod +x "$TMPROOT/bin/deploy"
  export TEST_MODE="$mode"
}

base_item_json() {
  local path="${1:-skills/campaign-lane/adapters/new.py}"
  printf '{"id":"item","path":"%s","owned_paths":["%s","tests/unit/test_new.py"],"read_only_paths":["skills/campaign-lane/scripts/contracts.py"],"test_command":"pytest -q tests/unit/test_new.py","contract_fingerprint":"%s"}' "$path" "$path" "$FIXTURE_FINGERPRINT"
}

run_bridge() {
  item_json="$(base_item_json)"
  run env SHARD_ITEM_JSON="$item_json" CAMPAIGN_LANE_FIXED_SHA="$FIXED_SHA" CAMPAIGN_LANE_SOURCE_REPO="$SOURCE" CAMPAIGN_LANE_DEPLOY_CMD="$TMPROOT/bin/deploy" \
    CAMPAIGN_LANE_WAIT_SEC="${CAMPAIGN_LANE_WAIT_SEC:-5}" CAMPAIGN_LANE_POLL_SEC=0.1 \
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

@test "materialized checkout inherits source local commit identity" {
  make_deployer pass
  git -C "$SOURCE" config user.name "Campaign Source"
  git -C "$SOURCE" config user.email campaign@example.invalid

  run_bridge

  [ "$status" -eq 0 ]
  [ "$(git -C "$TMPROOT/work" config --local user.name)" = "Campaign Source" ]
  [ "$(git -C "$TMPROOT/work" config --local user.email)" = campaign@example.invalid ]
}

@test "deploy rewritten canonical report path completes without stale placeholder wait" {
  make_deployer canonical_redirect
  start=$SECONDS

  run_bridge

  elapsed=$((SECONDS - start))
  [ "$status" -eq 0 ]
  [ "$elapsed" -lt 10 ]
  [ ! -e "$TMPROOT/out/report.yaml" ]
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
read_only=json.loads(task['read_only_paths_json'])
assert read_only == ['skills/campaign-lane/scripts/contracts.py']
assert set(read_only).isdisjoint({'skills/campaign-lane/adapters/new.py', 'tests/unit/test_new.py'})
assert all(os.path.isfile(os.path.join(work, path)) for path in read_only)
assert task['test_command'] == 'pytest -q tests/unit/test_new.py'
assert len(task['contract_fingerprint']) == 64
PY
}

@test "fingerprint mismatch blocks before deploy" {
  make_deployer pass
  fingerprint="$(printf stale | sha256sum | cut -d' ' -f1)"
  item_json="{\"id\":\"item\",\"path\":\"skills/campaign-lane/adapters/new.py\",\"owned_paths\":[\"skills/campaign-lane/adapters/new.py\",\"tests/unit/test_new.py\"],\"read_only_paths\":[\"skills/campaign-lane/scripts/contracts.py\"],\"test_command\":\"pytest -q tests/unit/test_new.py\",\"contract_fingerprint\":\"$fingerprint\"}"
  run env SHARD_ITEM_JSON="$item_json" CAMPAIGN_LANE_FIXED_SHA="$FIXED_SHA" CAMPAIGN_LANE_SOURCE_REPO="$SOURCE" CAMPAIGN_LANE_DEPLOY_CMD="$TMPROOT/bin/deploy" \
    "$ROOT/scripts/campaign_lane_shard_item.sh" item skills/campaign-lane/adapters/new.py worker "$TMPROOT/work" "$TMPROOT/out"
  [ "$status" -ne 0 ]
  reason_is contract_fingerprint_mismatch
}

@test "helper and SDK SHA drift each block before deploy" {
  make_deployer pass
  original_fingerprint="$(PYTHONPATH="$SOURCE/skills/campaign-lane" python3 -c 'from scripts.contracts import contract_fingerprint; print(contract_fingerprint())')"
  for changed in outcome_ledger.py adapter_sdk.py
  do
    git -C "$SOURCE" checkout -q "$FIXED_SHA" -- skills/campaign-lane/scripts/outcome_ledger.py skills/campaign-lane/scripts/adapter_sdk.py
    printf '\n# drift\n' >>"$SOURCE/skills/campaign-lane/scripts/$changed"
    git -C "$SOURCE" add skills/campaign-lane/scripts/outcome_ledger.py skills/campaign-lane/scripts/adapter_sdk.py
    git -C "$SOURCE" commit -qm "drift $changed"
    drift_sha="$(git -C "$SOURCE" rev-parse HEAD)"
    other=adapter_sdk.py; [ "$changed" = adapter_sdk.py ] && other=outcome_ledger.py
    [ "$(git -C "$SOURCE" show "$drift_sha:skills/campaign-lane/scripts/$other" | sha256sum)" = "$(git -C "$SOURCE" show "$FIXED_SHA:skills/campaign-lane/scripts/$other" | sha256sum)" ]
    item_json="$(base_item_json)"
    item_json="$(ITEM_JSON="$item_json" ORIGINAL="$original_fingerprint" python3 -c 'import json,os; d=json.loads(os.environ["ITEM_JSON"]); d["contract_fingerprint"]=os.environ["ORIGINAL"]; print(json.dumps(d,separators=(",",":")))')"
    out="$TMPROOT/drift-${changed%.py}"
    run env SHARD_ITEM_JSON="$item_json" CAMPAIGN_LANE_FIXED_SHA="$drift_sha" CAMPAIGN_LANE_SOURCE_REPO="$SOURCE" CAMPAIGN_LANE_DEPLOY_CMD="$TMPROOT/bin/deploy" \
      "$ROOT/scripts/campaign_lane_shard_item.sh" item skills/campaign-lane/adapters/new.py worker "$TMPROOT/work-${changed%.py}" "$out"
    [ "$status" -ne 0 ]
    python3 - "$out/result.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['reason_code'] == 'contract_fingerprint_mismatch'
PY
  done
}

@test "missing or malformed required item contract is rejected distinctly" {
  for item_json in \
    '{"path":"skills/campaign-lane/adapters/new.py","owned_paths":["skills/campaign-lane/adapters/new.py","tests/unit/test_new.py"],"test_command":"pytest -q x","contract_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' \
    '{"path":"skills/campaign-lane/adapters/new.py","owned_paths":["skills/campaign-lane/adapters/new.py","tests/unit/test_new.py"],"read_only_paths":[],"test_command":"pytest -q x","contract_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' \
    '{"path":"skills/campaign-lane/adapters/new.py","owned_paths":["skills/campaign-lane/adapters/new.py","tests/unit/test_new.py"],"read_only_paths":["skills/campaign-lane/scripts/contracts.py"],"test_command":"","contract_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}' \
    '{"path":"skills/campaign-lane/adapters/new.py","owned_paths":["skills/campaign-lane/adapters/new.py","tests/unit/test_new.py"],"read_only_paths":["skills/campaign-lane/scripts/contracts.py"],"test_command":"pytest -q x","contract_fingerprint":"bad"}'
  do
    out="$TMPROOT/invalid-$RANDOM"
    run env SHARD_ITEM_JSON="$item_json" CAMPAIGN_LANE_FIXED_SHA="$FIXED_SHA" CAMPAIGN_LANE_SOURCE_REPO="$SOURCE" \
      "$ROOT/scripts/campaign_lane_shard_item.sh" item skills/campaign-lane/adapters/new.py worker "$TMPROOT/work-$RANDOM" "$out"
    [ "$status" -ne 0 ]
    reason_is_at="$out/result.json"
    python3 - "$reason_is_at" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['reason_code'] == 'invalid_item_contract'
PY
  done
}

@test "read-only existence is checked at fixed checkout not dirty source" {
  printf newer >"$SOURCE/untracked-newer"
  make_deployer pass
  item_json="$(base_item_json)"
  item_json="$(ITEM_JSON="$item_json" python3 - <<'PY'
import json,os
d=json.loads(os.environ['ITEM_JSON']); d['read_only_paths']=['untracked-newer']; print(json.dumps(d,separators=(',',':')))
PY
)"
  run env SHARD_ITEM_JSON="$item_json" CAMPAIGN_LANE_FIXED_SHA="$FIXED_SHA" CAMPAIGN_LANE_SOURCE_REPO="$SOURCE" CAMPAIGN_LANE_DEPLOY_CMD="$TMPROOT/bin/deploy" \
    "$ROOT/scripts/campaign_lane_shard_item.sh" item skills/campaign-lane/adapters/new.py worker "$TMPROOT/work" "$TMPROOT/out"
  [ "$status" -ne 0 ]
  reason_is read_only_path_missing
}

@test "wrong fixed SHA fails closed with result" {
  make_deployer pass
  run env SHARD_ITEM_JSON="$(base_item_json)" CAMPAIGN_LANE_FIXED_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa CAMPAIGN_LANE_SOURCE_REPO="$SOURCE" CAMPAIGN_LANE_DEPLOY_CMD="$TMPROOT/bin/deploy" \
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
  run env SHARD_ITEM_JSON="$(base_item_json)" CAMPAIGN_LANE_FIXED_SHA="$FIXED_SHA" CAMPAIGN_LANE_SOURCE_REPO="$SOURCE" CAMPAIGN_LANE_DEPLOY_CMD="$TMPROOT/bin/deploy" \
    "$ROOT/scripts/campaign_lane_shard_item.sh" item skills/campaign-lane/adapters/new.py worker "$TMPROOT/work" "$TMPROOT/out"
  [ "$status" -ne 0 ]
  reason_is source_materialize_failed
}

@test "failed shard retry replaces only logical workdir and materializes a fresh checkout" {
  make_deployer pass
  mkdir -p "$TMPROOT/out"
  printf '{"status":"fail","reason_code":"deploy_failed"}\n' > "$TMPROOT/out/result.json"
  stale="$TMPROOT/stale-checkout"
  mkdir -p "$stale"
  printf stale > "$stale/evidence"
  ln -s "$stale" "$TMPROOT/work"

  run_bridge

  [ "$status" -eq 0 ]
  [ -f "$stale/evidence" ]
  [ -L "$TMPROOT/work" ]
  [ "$(readlink -f "$TMPROOT/work")" != "$stale" ]
  reason_is report_terminal_pass
  [ -f "$TMPROOT/out/attempts/attempt-001/result.json" ]
  python3 - "$TMPROOT/out/task.yaml" "$TMPROOT/out/result.json" <<'PY'
import json,sys,yaml
t=yaml.safe_load(open(sys.argv[1]))['task']; r=json.load(open(sys.argv[2]))
assert t['campaign_attempt'] == 2
assert t['task_id'].endswith('_attempt_2')
assert set(r['stage_duration_sec']) == {'materialize','deploy','test','commit','report_wait'}
assert r['stage_duration_sec']['test'] == 2 and r['stage_duration_sec']['commit'] == 1
assert isinstance(r['estimated_exceeded'], bool)
PY
}

@test "retry preserves three terminal reports as separate attempts and redeploys all three" {
  make_deployer pass
  for n in 1 2 3; do
    mkdir -p "$TMPROOT/out"
    printf '{"status":"fail","reason_code":"deploy_failed"}\n' > "$TMPROOT/out/result.json"
    printf 'status: failed\nverdict: FAIL\nattempt: %s\n' "$n" > "$TMPROOT/out/report.yaml"
    run_bridge
    [ "$status" -eq 0 ]
  done
  [ "$(find "$TMPROOT/out/attempts" -name report.yaml | wc -l)" -eq 3 ]
  [ "$(python3 -c 'import yaml; print(yaml.safe_load(open("'"$TMPROOT"'/out/task.yaml"))["task"]["campaign_attempt"])')" -eq 4 ]
}

@test "canonical control root is exported instead of isolated checkout queue" {
  make_deployer pass
  run env SHARD_ITEM_JSON="$(base_item_json)" CAMPAIGN_LANE_FIXED_SHA="$FIXED_SHA" CAMPAIGN_LANE_SOURCE_REPO="$SOURCE" CAMPAIGN_LANE_DEPLOY_CMD="$TMPROOT/bin/deploy" SHOGUN_ROOT="$ROOT" CAMPAIGN_LANE_WAIT_SEC=1 CAMPAIGN_LANE_POLL_SEC=0.1 \
    "$ROOT/scripts/campaign_lane_shard_item.sh" item skills/campaign-lane/adapters/new.py worker "$TMPROOT/work" "$TMPROOT/out"
  # 失敗時にどの段階で落ちたかを残す。判定は変えない(status 0 のみ合格)。
  # CI run 30190382837 でここが status!=0 で落ちたが、bats の run は出力を飲むため
  # reason_code が分からず機序を特定できなかった。次の失敗を診断可能にする。
  if [ "$status" -ne 0 ]; then
    printf 'shard rc=%s\n%s\n' "$status" "$output" >&2
    cat "$TMPROOT/out/result.json" >&2 2>/dev/null || printf 'result.json missing\n' >&2
  fi
  [ "$status" -eq 0 ]
  [ "$(python3 -c 'import yaml; print(yaml.safe_load(open("'"$TMPROOT"'/out/task.yaml"))["task"]["canonical_root"])')" = "$ROOT" ]
}

@test "failed pre-ext4 full clone is atomically quarantined before retry" {
  make_deployer pass
  mkdir -p "$TMPROOT/out" "$TMPROOT/work"
  printf '{"status":"fail","reason_code":"source_materialize_failed"}\n' > "$TMPROOT/out/result.json"
  printf old-evidence > "$TMPROOT/work/evidence"

  run_bridge

  [ "$status" -eq 0 ]
  [ -L "$TMPROOT/work" ]
  quarantine=("$TMPROOT"/work.failed-*)
  [ "${#quarantine[@]}" -eq 1 ]
  [ "$(cat "${quarantine[0]}/evidence")" = old-evidence ]
  reason_is report_terminal_pass
}

@test "retry launched from failed workdir detaches cwd before quarantine" {
  make_deployer pass
  mkdir -p "$TMPROOT/out" "$TMPROOT/work"
  printf '{"status":"fail","reason_code":"source_materialize_failed"}\n' > "$TMPROOT/out/result.json"
  item_json="$(base_item_json)"

  run bash -c "cd '$TMPROOT/work' && exec env SHARD_ITEM_JSON='$item_json' CAMPAIGN_LANE_FIXED_SHA='$FIXED_SHA' CAMPAIGN_LANE_SOURCE_REPO='$SOURCE' CAMPAIGN_LANE_DEPLOY_CMD='$TMPROOT/bin/deploy' CAMPAIGN_LANE_WAIT_SEC=1 CAMPAIGN_LANE_POLL_SEC=0.1 '$ROOT/scripts/campaign_lane_shard_item.sh' item skills/campaign-lane/adapters/new.py worker '$TMPROOT/work' '$TMPROOT/out'"

  [ "$status" -eq 0 ]
  [ -L "$TMPROOT/work" ]
  reason_is report_terminal_pass
}

@test "invalid missing parent path fails before deploy" {
  make_deployer pass
  run env SHARD_ITEM_JSON="$(base_item_json missing/path/new.py)" CAMPAIGN_LANE_FIXED_SHA="$FIXED_SHA" CAMPAIGN_LANE_SOURCE_REPO="$SOURCE" CAMPAIGN_LANE_DEPLOY_CMD="$TMPROOT/bin/deploy" \
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
  export CAMPAIGN_LANE_WAIT_SEC=1
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

@test "missing metrics classification precedes other terminal validation failures" {
  make_deployer metrics_missing_with_bad_commit
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

# --- scratch lifecycle (release_scratch): active-lane guard is binary only
# (completion marker + live process), never mtime/elapsed-time. Three
# fixtures per campaign lane policy: active=marker-absent ("lock" not yet
# released), active=live-process-present despite a terminal marker, and
# completed (both checks clear).

release_scratch_base() {
  local base="$TMPROOT/scratch-base"
  mkdir -p "$base/tmpdir" "$base/cache_dir" "$base/output_dir" "$base/workdir" "$base/workdir.failed-1"
  printf tmp-junk >"$base/tmpdir/junk"
  printf cache-junk >"$base/cache_dir/junk"
  printf old-evidence >"$base/workdir.failed-1/evidence"
  printf '%s' "$base"
}

run_release_scratch() {
  run bash -c "source '$ROOT/scripts/campaign_lane_shard_item.sh' && release_scratch '$1/workdir' '$1/output_dir'"
}

@test "release_scratch: no completion marker leaves scratch untouched (active = lock present)" {
  base="$(release_scratch_base)"

  run_release_scratch "$base"

  [ "$status" -eq 0 ]
  [ -f "$base/tmpdir/junk" ]
  [ -f "$base/cache_dir/junk" ]
  [ -f "$base/workdir.failed-1/evidence" ]
}

@test "release_scratch: non-terminal marker status leaves scratch untouched (active = lock present)" {
  base="$(release_scratch_base)"
  printf '{"status":"in_progress"}' >"$base/output_dir/result.json"

  run_release_scratch "$base"

  [ "$status" -eq 0 ]
  [ -f "$base/tmpdir/junk" ]
  [ -f "$base/workdir.failed-1/evidence" ]
}

@test "release_scratch: terminal marker with a live process holding scratch open is untouched (active = live process)" {
  base="$(release_scratch_base)"
  printf '{"status":"success"}' >"$base/output_dir/result.json"

  ( cd "$base/tmpdir" && exec sleep 5 ) &
  bg_pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -L "/proc/$bg_pid/cwd" ] && break
    sleep 0.1
  done

  run_release_scratch "$base"
  wait "$bg_pid" 2>/dev/null || true

  [ "$status" -eq 0 ]
  [ -f "$base/tmpdir/junk" ]
  [ -f "$base/cache_dir/junk" ]
  [ -f "$base/workdir.failed-1/evidence" ]
}

@test "release_scratch: terminal marker with no live process reclaims tmpdir/cache_dir but preserves failed-attempt quarantine (completed)" {
  base="$(release_scratch_base)"
  printf '{"status":"success"}' >"$base/output_dir/result.json"

  run_release_scratch "$base"

  [ "$status" -eq 0 ]
  [ ! -e "$base/tmpdir/junk" ]
  [ ! -e "$base/cache_dir/junk" ]
  [ -d "$base/tmpdir" ]
  [ -d "$base/cache_dir" ]
  [ -d "$base/workdir" ]
  [ -f "$base/workdir.failed-1/evidence" ]
}

@test "release_scratch: fail status also reclaims tmpdir/cache_dir once terminal and idle" {
  base="$(release_scratch_base)"
  printf '{"status":"fail"}' >"$base/output_dir/result.json"

  run_release_scratch "$base"

  [ "$status" -eq 0 ]
  [ ! -e "$base/tmpdir/junk" ]
  [ -f "$base/workdir.failed-1/evidence" ]
}

@test "release_scratch never removes the shard's own workdir checkout" {
  base="$(release_scratch_base)"
  printf real-checkout >"$base/workdir/marker"
  printf '{"status":"success"}' >"$base/output_dir/result.json"

  run_release_scratch "$base"

  [ "$status" -eq 0 ]
  [ -f "$base/workdir/marker" ]
}

@test "successful shard completion through the real pipeline releases sibling tmpdir/cache_dir scratch" {
  make_deployer pass
  mkdir -p "$TMPROOT/tmpdir" "$TMPROOT/cache_dir"
  printf tmp-junk >"$TMPROOT/tmpdir/junk"
  printf cache-junk >"$TMPROOT/cache_dir/junk"

  run_bridge

  [ "$status" -eq 0 ]
  [ ! -e "$TMPROOT/tmpdir/junk" ]
  [ ! -e "$TMPROOT/cache_dir/junk" ]
}
