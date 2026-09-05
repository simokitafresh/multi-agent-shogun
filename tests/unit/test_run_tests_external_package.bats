#!/usr/bin/env bats
# test_necessity: External package roots are selected from package.json rather
# than a frontend/ directory, and every successful package validation has an
# exact terminal Ninja receipt.

setup() {
  while IFS= read -r run_tests_parent_var; do
    unset "$run_tests_parent_var"
  done < <(compgen -A variable RUN_TESTS_)
  unset BATS_TAP_OUTPUT BATS_CACHE BATS_CACHE_DIR BATS_SOURCE_FINGERPRINT
  unset TEST_TIMING_LEDGER TEST_SUITE_TIMING_LEDGER
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPROOT="$(mktemp -d)"
  mkdir -p "$TMPROOT/control/scripts/lib" "$TMPROOT/control/bin" \
    "$TMPROOT/control/queue/tasks" "$TMPROOT/control/logs"
  cp "$ROOT/scripts/run_tests.sh" "$ROOT/scripts/run_with_receipt.sh" \
    "$ROOT/scripts/test_timing_ledger_write.sh" \
    "$ROOT/scripts/test_suite_timing_ledger_write.sh" \
    "$ROOT/scripts/universal_shard.py" "$ROOT/scripts/universal_shard_adapters.py" \
    "$ROOT/scripts/heavy_job_admission.sh" "$TMPROOT/control/scripts/"
  cp "$ROOT/scripts/lib/yaml_field_set.sh" "$ROOT/scripts/report_field_set.sh" \
    "$TMPROOT/control/scripts/lib/"
  printf '#!/usr/bin/env bash\nprintf "1..1\\nok 1 fixture\\n"\n' \
    >"$TMPROOT/control/bin/bats"
  chmod +x "$TMPROOT/control/bin/bats"
  git -C "$TMPROOT/control" init -q
  git -C "$TMPROOT/control" config user.email test@example.invalid
  git -C "$TMPROOT/control" config user.name test
  git -C "$TMPROOT/control" add scripts
  git -C "$TMPROOT/control" commit -qm init
}

teardown() { rm -rf "$TMPROOT"; }

make_external_repo() {
  local scripts_json="$1"
  EXTERNAL="$TMPROOT/external"
  mkdir -p "$EXTERNAL/lp"
  printf '%s\n' "$scripts_json" >"$EXTERNAL/lp/package.json"
  printf 'export const value = 1;\n' >"$EXTERNAL/lp/app.ts"
  git -C "$EXTERNAL" init -q
  git -C "$EXTERNAL" config user.email test@example.invalid
  git -C "$EXTERNAL" config user.name test
  git -C "$EXTERNAL" add .
  git -C "$EXTERNAL" commit -qm init
}

write_task() {
  cat >"$TMPROOT/control/queue/tasks/external.yaml" <<YAML
task:
  task_id: external-lp
  project: infra
  target_path: lp/app.ts
  commit_contract:
    required: true
    repo_root: $EXTERNAL
    planned_paths: [lp/app.ts]
YAML
}

@test "arbitrary lp package runs typecheck and build with exact Ninja receipt" {
  make_external_repo '{"scripts":{"typecheck":"tsc --noEmit","build":"vite build"}}'
  write_task
  cat >"$TMPROOT/control/bin/npm" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NPM_ARGS_LOG"
case "$*" in
  "run typecheck") printf 'typecheck ok\n' ;;
  "run build") printf 'build ok\n' ;;
  *) printf 'unexpected npm args: %s\n' "$*" >&2; exit 9 ;;
esac
SH
  chmod +x "$TMPROOT/control/bin/npm"

  run env PATH="$TMPROOT/control/bin:$PATH" REPO_ROOT="$TMPROOT/control" \
    NPM_ARGS_LOG="$TMPROOT/npm.args" BATS_CACHE=0 \
    RUN_TESTS_RECEIPT_DIR="$TMPROOT/control/logs/test_receipts" \
    bash "$TMPROOT/control/scripts/run_tests.sh" task \
      "$TMPROOT/control/queue/tasks/external.yaml"

  [ "$status" -eq 0 ]
  [[ "$output" == *"TEST_SELECTION result=external runner=npm-package scope=lp"* ]]
  [[ "$output" != *"WARN: external task scope path excluded"* ]]
  grep -Fqx 'run typecheck' "$TMPROOT/npm.args"
  grep -Fqx 'run build' "$TMPROOT/npm.args"
  grep -Fq 'test_receipt_path:' "$TMPROOT/control/queue/tasks/external.yaml"
  receipt="$(find "$TMPROOT/control/logs/test_receipts" -name '*.json' -type f | head -1)"
  [ -n "$receipt" ]
  run python3 - "$receipt" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["version"] == 3, d
assert d["complete"] is True, d
assert d["result"] == "PASS" and d["rc"] == 0, d
assert d["declared_test_count"] == 1 and d["observed_test_count"] == 1, d
assert d["skip_count"] == 0, d
assert d["test_paths"] == [], d
PY
  [ "$status" -eq 0 ]
}

@test "unsupported lp test engine fails explicitly without package-root exclusion" {
  make_external_repo '{"scripts":{"test":"unknown-runner ./tests"}}'
  write_task
  cat >"$TMPROOT/control/bin/npm" <<'SH'
#!/usr/bin/env bash
printf 'npm must not run for an unsupported engine\n' >&2
exit 9
SH
  chmod +x "$TMPROOT/control/bin/npm"

  run env PATH="$TMPROOT/control/bin:$PATH" REPO_ROOT="$TMPROOT/control" \
    BATS_CACHE=0 RUN_TESTS_RECEIPT_DIR="$TMPROOT/control/logs/test_receipts" \
    bash "$TMPROOT/control/scripts/run_tests.sh" task \
      "$TMPROOT/control/queue/tasks/external.yaml"

  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK: unsupported external npm package test engine"* ]]
  [[ "$output" != *"WARN: external task scope path excluded"* ]]
  [ ! -e "$TMPROOT/control/logs/npm.args" ]
  receipt="$(find "$TMPROOT/control/logs/test_receipts" -name '*.json' -type f | head -1)"
  [ -n "$receipt" ]
  [ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["rc"])' "$receipt")" -eq 2 ]
}

# test_necessity: An external task with no mapped tests must publish an empty
# selected-path set.  The external-project identity is coordination metadata,
# not a test path and must not make the zero-test receipt invalid.
# regression_justification: overlaps_existing=true; W0 reproduced a non-empty
# external-project placeholder with declared/observed counts of zero.
@test "external zero-selection receipt excludes project identity placeholder" {
  external="$TMPROOT/external-docs"
  mkdir -p "$external/scripts" "$external/docs"
  cp "$ROOT/scripts/run_tests.sh" "$ROOT/scripts/run_with_receipt.sh" \
    "$ROOT/scripts/test_select.sh" "$ROOT/scripts/test_timing_ledger_write.sh" \
    "$ROOT/scripts/test_suite_timing_ledger_write.sh" "$ROOT/scripts/universal_shard.py" \
    "$ROOT/scripts/universal_shard_adapters.py" "$ROOT/scripts/heavy_job_admission.sh" \
    "$external/scripts/"
  printf '# docs-only\n' >"$external/docs/change.md"
  git -C "$external" init -q
  git -C "$external" config user.email test@example.invalid
  git -C "$external" config user.name test
  git -C "$external" add scripts docs
  git -C "$external" commit -qm init
  cat >"$TMPROOT/control/queue/tasks/external-docs.yaml" <<YAML
task:
  task_id: external-docs-zero
  project: infra
  task_worktree_path: $external
  task_worktree_repo: $external
  target_path: $external/docs/change.md
YAML

  run env PATH="$TMPROOT/control/bin:$PATH" REPO_ROOT="$TMPROOT/control" \
    BATS_CACHE=0 RUN_TESTS_SINGLEFLIGHT_DIR="$TMPROOT/singleflight" \
    RUN_TESTS_RECEIPT_DIR="$TMPROOT/control/logs/test_receipts" \
    bash "$TMPROOT/control/scripts/run_tests.sh" task \
      "$TMPROOT/control/queue/tasks/external-docs.yaml"

  [ "$status" -eq 0 ]
  [[ "$output" == *"SINGLE_FLIGHT_ADMISSION mode=task selection_count=0 pending=0 admission=acquired"* ]]
  [[ "$output" == *"TEST_SELECTION result=selected reason=no_mapped_tests files=0 admission=skipped"* ]]
  receipt="$(find "$TMPROOT/control/logs/test_receipts" -name '*.json' -type f | head -1)"
  [ -n "$receipt" ]
  run python3 - "$receipt" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["result"] == "PASS" and d["rc"] == 0, d
assert d["declared_test_count"] == 0 and d["observed_test_count"] == 0, d
assert d["skip_count"] == 0 and d["test_paths"] == [], d
assert d["run_manifest"]["scope_identity"]["selected_file_count"] == 0, d
PY
  [ "$status" -eq 0 ]
  echo "ZERO_SELECTION_METRICS before_placeholder=1 after_placeholder=0 rc=0 tests=0/0 skip=0"
}
