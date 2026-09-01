#!/usr/bin/env bats
# test_necessity: ninja scope commitは他者stageを混入せず、指定scopeだけを原子的にcommitする。

NINJA_SCOPE_BASE_REPO="$BATS_FILE_TMPDIR/ninja_scope_commit.base"

setup_file() {
    mkdir -p "$NINJA_SCOPE_BASE_REPO"
    git -C "$NINJA_SCOPE_BASE_REPO" init -q
    git -C "$NINJA_SCOPE_BASE_REPO" config user.email test@example.com
    git -C "$NINJA_SCOPE_BASE_REPO" config user.name test
    printf 'base\n' > "$NINJA_SCOPE_BASE_REPO/own.txt"
    printf 'base\n' > "$NINJA_SCOPE_BASE_REPO/other.txt"
    git -C "$NINJA_SCOPE_BASE_REPO" add own.txt other.txt
    git -C "$NINJA_SCOPE_BASE_REPO" commit -qm initial
}

setup() {
    REPO="$(mktemp -d "$BATS_TMPDIR/ninja_scope_commit.XXXXXX")"
    git clone -q --local "$NINJA_SCOPE_BASE_REPO" "$REPO"
    git -C "$REPO" config user.email test@example.com
    git -C "$REPO" config user.name test
    HELPER="$BATS_TEST_DIRNAME/../../scripts/ninja_scope_commit.sh"
    # ninja_scope_commit.sh unconditionally sources scripts/lib/scope_path.sh
    # (SSOT for scope path normalization); every sandbox repo needs a copy.
    mkdir -p "$REPO/scripts/lib"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/scope_path.sh" "$REPO/scripts/lib/scope_path.sh"
}

# test_necessity: a stale queue/insights.yaml candidate is an omission, not a
# deletion; the shared ID-union helper must retain HEAD IDs and new candidate
# IDs without duplicating either side.
@test "insights ID union preserves HEAD IDs while rebasing a stale candidate" {
    head="$REPO/head-insights.yaml"
    candidate="$REPO/candidate-insights.yaml"
    merged="$REPO/merged-insights.yaml"
    printf '%s\n' 'insights:' '- id: existing' '  value: head' '- id: remote-only' '  value: remote' >"$head"
    printf '%s\n' 'insights:' '- id: candidate-only' '  value: candidate' '- id: existing' '  value: candidate' >"$candidate"

    run bash "$BATS_TEST_DIRNAME/../../scripts/restore_insights_from_corrupt.sh" \
        --id-union "$head" "$candidate" "$merged"
    [ "$status" -eq 0 ]
    run python3 - "$merged" <<'PY'
import sys
import yaml
rows = (yaml.safe_load(open(sys.argv[1], encoding='utf-8')) or {}).get('insights') or []
ids = [row['id'] for row in rows]
assert ids == ['candidate-only', 'existing', 'remote-only'], ids
assert len(ids) == len(set(ids))
print('gold_missing=0 duplicates=0 new_ids=1')
PY
    [ "$status" -eq 0 ]
    [ "$output" = 'gold_missing=0 duplicates=0 new_ids=1' ]
}

@test "explicit ignored new scope is committed without force-staging ignored files outside scope" {
    printf '*\n' > "$REPO/.gitignore"
    git -C "$REPO" add -f .gitignore
    git -C "$REPO" commit -qm ignore-all
    printf owned > "$REPO/owned.txt"
    printf foreign > "$REPO/foreign.txt"

    run bash -c 'cd "$1" && exec bash "$2" -m "ignored owned" -- owned.txt' _ "$REPO" "$HELPER"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" show --format= --name-only HEAD)" = "owned.txt" ]
    [ "$(git -C "$REPO" show HEAD:owned.txt)" = owned ]
    ! git -C "$REPO" ls-tree -r --name-only HEAD | grep -qx foreign.txt
    git -C "$REPO" check-ignore -q foreign.txt
}

teardown() {
    rm -rf "$REPO"
}

teardown_file() {
    rm -rf "$NINJA_SCOPE_BASE_REPO"
}

@test "ninja task commit subject automatically identifies task_id" {
    mkdir -p "$REPO/queue/tasks"
    printf 'task:\n  task_id: task-subject-contract\n  parent_cmd: cmd_parent-contract\n' > "$REPO/queue/tasks/hayate.yaml"
    printf 'task subject change\n' >> "$REPO/own.txt"

    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml bash "$2" -m "implement subject contract" -- own.txt' _ "$REPO" "$HELPER"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" log -1 --format=%s)" = 'task-subject-contract: implement subject contract' ]
}

@test "ninja task commit subject does not duplicate an existing task identifier" {
    mkdir -p "$REPO/queue/tasks"
    printf 'task:\n  task_id: task-subject-contract\n  parent_cmd: cmd_parent-contract\n' > "$REPO/queue/tasks/hayate.yaml"
    printf 'already tagged\n' >> "$REPO/own.txt"

    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml bash "$2" -m "task-subject-contract: already tagged" -- own.txt' _ "$REPO" "$HELPER"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" log -1 --format=%s)" = 'task-subject-contract: already tagged' ]
}

@test "ninja task commit subject falls back to parent_cmd when task_id is absent" {
    mkdir -p "$REPO/queue/tasks"
    printf 'task:\n  parent_cmd: cmd_parent-contract\n' > "$REPO/queue/tasks/hayate.yaml"
    printf 'parent command subject change\n' >> "$REPO/own.txt"

    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml bash "$2" -m "implement parent contract" -- own.txt' _ "$REPO" "$HELPER"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" log -1 --format=%s)" = 'cmd_parent-contract: implement parent contract' ]
}

@test "task外commit without a task file preserves the caller subject" {
    printf 'manual subject change\n' >> "$REPO/own.txt"

    run bash -c 'cd "$1" && env -u NINJA_SCOPE_TASK_FILE bash "$2" -m "manual subject" -- own.txt' _ "$REPO" "$HELPER"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" log -1 --format=%s)" = 'manual subject' ]
}

@test "transient PASS receipt deletes only untracked test and commits production scope" {
    mkdir -p "$REPO/tests" "$REPO/queue/tasks"
    printf 'change\n' >> "$REPO/own.txt"
    printf 'proof\n' > "$REPO/tests/test_transient.bats"
    cat > "$REPO/queue/tasks/hayate.yaml" <<'YAML'
task:
  planned_paths: [own.txt, tests/test_transient.bats]
YAML
    cat > "$REPO/receipt.yaml" <<'YAML'
complete: true
result: PASS
rc: 0
skip_count: 0
observed_test_count: 1
test_paths: [tests/test_transient.bats]
YAML
    printf 'source_head: %s\n' "$(git -C "$REPO" rev-parse HEAD)" >> "$REPO/receipt.yaml"
    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml NINJA_TEST_RECEIPT=receipt.yaml bash "$2" -m transient -- own.txt tests/test_transient.bats' _ "$REPO" "$HELPER"
    [ "$status" -eq 0 ]
    [ ! -e "$REPO/tests/test_transient.bats" ]
    [ "$(git -C "$REPO" show --format= --name-only HEAD)" = own.txt ]
}

# test_necessity: scope commit must reject an external receipt whose source_head and run_manifest.commit_sha disagree, before deleting or committing any path.
@test "receipt source_head and run_manifest commit identity mismatch blocks scope commit" {
    mkdir -p "$REPO/queue/tasks"
    printf 'change\n' >>"$REPO/own.txt"
    printf 'task:\n  planned_paths: [own.txt]\n' >"$REPO/queue/tasks/hayate.yaml"
    head="$(git -C "$REPO" rev-parse HEAD)"
    cat >"$REPO/receipt.yaml" <<YAML
complete: true
result: PASS
rc: 0
skip_count: 0
observed_test_count: 1
test_paths: [tests/example.bats]
source_head: $head
run_manifest:
  commit_sha: "0000000000000000000000000000000000000000"
YAML
    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml NINJA_TEST_RECEIPT=receipt.yaml bash "$2" -m mismatch -- own.txt' _ "$REPO" "$HELPER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"source_head/run_manifest.commit_sha mismatch"* ]]
    [ -n "$(git -C "$REPO" status --short -- own.txt)" ]
}

@test "transient FAIL receipt blocks before deletion" {
    mkdir -p "$REPO/tests" "$REPO/queue/tasks"
    printf 'change\n' >> "$REPO/own.txt"; printf proof > "$REPO/tests/test_transient.bats"
    printf 'task:\n  planned_paths: [own.txt, tests/test_transient.bats]\n' > "$REPO/queue/tasks/hayate.yaml"
    printf 'complete: true\nresult: FAIL\nrc: 1\nskip_count: 0\nobserved_test_count: 1\ntest_paths: [tests/test_transient.bats]\n' > "$REPO/receipt.yaml"
    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml NINJA_TEST_RECEIPT=receipt.yaml bash "$2" -m transient -- own.txt tests/test_transient.bats' _ "$REPO" "$HELPER"
    [ "$status" -eq 2 ]
    [ -f "$REPO/tests/test_transient.bats" ]
}

@test "canonical SKIP and insufficient coverage receipts block before deletion" {
    mkdir -p "$REPO/tests" "$REPO/queue/tasks"
    printf 'change\n' >> "$REPO/own.txt"; printf proof > "$REPO/tests/test_transient.bats"
    printf 'task:\n  planned_paths: [own.txt, tests/test_transient.bats]\n' > "$REPO/queue/tasks/hayate.yaml"
    head="$(git -C "$REPO" rev-parse HEAD)"
    printf 'complete: true\nresult: PASS\nrc: 0\nskip_count: 1\nobserved_test_count: 1\ntest_paths: [tests/test_transient.bats]\nsource_head: %s\n' "$head" > "$REPO/receipt.yaml"
    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml NINJA_TEST_RECEIPT=receipt.yaml bash "$2" -m skip -- own.txt tests/test_transient.bats' _ "$REPO" "$HELPER"
    [ "$status" -eq 2 ]; [ -f "$REPO/tests/test_transient.bats" ]

    printf 'complete: true\nresult: PASS\nrc: 0\nskip_count: 0\nobserved_test_count: 1\ntest_paths: [tests/another.bats]\nsource_head: %s\n' "$head" > "$REPO/receipt.yaml"
    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml NINJA_TEST_RECEIPT=receipt.yaml bash "$2" -m coverage -- own.txt tests/test_transient.bats' _ "$REPO" "$HELPER"
    [ "$status" -eq 2 ]; [ -f "$REPO/tests/test_transient.bats" ]
}

@test "envなしでもreceipt HEAD後の並行test変更をBLOCKしproduction-only変更は許可する" {
    mkdir -p "$REPO/tests" "$REPO/queue/tasks"
    printf 'change\n' >> "$REPO/own.txt"; printf proof > "$REPO/tests/test_transient.bats"
    printf 'task:\n  planned_paths: [own.txt, tests/test_transient.bats]\n' > "$REPO/queue/tasks/hayate.yaml"
    source_head="$(git -C "$REPO" rev-parse HEAD)"
    printf 'complete: true\nresult: PASS\nrc: 0\nskip_count: 0\nobserved_test_count: 1\ntest_paths: [tests/test_transient.bats]\nsource_head: %s\n' "$source_head" > "$REPO/receipt.yaml"
    printf 'parallel production\n' >> "$REPO/other.txt"; git -C "$REPO" add other.txt; git -C "$REPO" commit -qm parallel-production
    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml NINJA_TEST_RECEIPT=receipt.yaml bash "$2" -m production-drift -- own.txt tests/test_transient.bats' _ "$REPO" "$HELPER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"stale test receipt source_head"* ]]

    printf 'next\n' >> "$REPO/own.txt"; printf proof > "$REPO/tests/test_transient.bats"
    source_head="$(git -C "$REPO" rev-parse HEAD)"
    printf 'complete: true\nresult: PASS\nrc: 0\nskip_count: 0\nobserved_test_count: 1\ntest_paths: [tests/test_transient.bats]\nsource_head: %s\n' "$source_head" > "$REPO/receipt.yaml"
    printf tracked > "$REPO/tests/test_parallel.bats"; git -C "$REPO" add tests/test_parallel.bats; git -C "$REPO" commit -qm parallel-test
    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml NINJA_TEST_RECEIPT=receipt.yaml bash "$2" -m test-drift -- own.txt tests/test_transient.bats' _ "$REPO" "$HELPER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"stale test receipt source_head"* ]]
    [ -f "$REPO/tests/test_transient.bats" ]
}

# test_necessity: broad cache fingerprints must not make an unrelated agent's source commit invalidate a focused PASS receipt.
@test "unrelated committed source selected to a disjoint test reuses focused receipt" {
    mkdir -p "$REPO/tests" "$REPO/queue/tasks"
    printf 'proof\n' >"$REPO/tests/test_owned.bats"
    printf 'other\n' >"$REPO/tests/test_other.bats"
    cat >"$REPO/scripts/test_select.sh" <<'SH'
#!/usr/bin/env bash
printf '%s/tests/test_other.bats\n' "$(git rev-parse --show-toplevel)"
SH
    chmod +x "$REPO/scripts/test_select.sh"
    git -C "$REPO" add scripts/test_select.sh tests/test_owned.bats tests/test_other.bats
    git -C "$REPO" commit -qm selector-base
    source_head="$(git -C "$REPO" rev-parse HEAD)"
    source_fp="$(git -C "$REPO" ls-files --format='%(objectname)' -- scripts lib tests/helpers ':!scripts/run_tests.sh' | sha256sum | awk '{print $1}')"
    printf 'parallel\n' >"$REPO/scripts/unrelated.sh"
    git -C "$REPO" add scripts/unrelated.sh
    git -C "$REPO" commit -qm unrelated-source
    printf 'change\n' >>"$REPO/own.txt"
    printf 'task:\n  planned_paths: [own.txt]\n' >"$REPO/queue/tasks/hayate.yaml"
    printf 'complete: true\nresult: PASS\nrc: 0\nskip_count: 0\nobserved_test_count: 1\ntest_paths: [tests/test_owned.bats]\nsource_head: %s\nsource_fingerprint: %s\n' "$source_head" "$source_fp" >"$REPO/receipt.yaml"

    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml NINJA_TEST_RECEIPT=receipt.yaml bash "$2" -m disjoint -- own.txt' _ "$REPO" "$HELPER"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" show --format= --name-only HEAD)" = own.txt ]
}

# test_necessity: receipt reuse must remain fail-closed when dependency selection maps a concurrent source change to the verified test.
@test "committed dependency selected to verified test invalidates focused receipt" {
    mkdir -p "$REPO/tests" "$REPO/queue/tasks"
    printf 'proof\n' >"$REPO/tests/test_owned.bats"
    cat >"$REPO/scripts/test_select.sh" <<'SH'
#!/usr/bin/env bash
printf '%s/tests/test_owned.bats\n' "$(git rev-parse --show-toplevel)"
SH
    chmod +x "$REPO/scripts/test_select.sh"
    git -C "$REPO" add scripts/test_select.sh tests/test_owned.bats
    git -C "$REPO" commit -qm selector-base
    source_head="$(git -C "$REPO" rev-parse HEAD)"
    source_fp="$(git -C "$REPO" ls-files --format='%(objectname)' -- scripts lib tests/helpers ':!scripts/run_tests.sh' | sha256sum | awk '{print $1}')"
    printf 'dependency\n' >"$REPO/scripts/dependency.sh"
    git -C "$REPO" add scripts/dependency.sh
    git -C "$REPO" commit -qm dependency-source
    printf 'change\n' >>"$REPO/own.txt"
    printf 'task:\n  planned_paths: [own.txt]\n' >"$REPO/queue/tasks/hayate.yaml"
    printf 'complete: true\nresult: PASS\nrc: 0\nskip_count: 0\nobserved_test_count: 1\ntest_paths: [tests/test_owned.bats]\nsource_head: %s\nsource_fingerprint: %s\n' "$source_head" "$source_fp" >"$REPO/receipt.yaml"

    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml NINJA_TEST_RECEIPT=receipt.yaml bash "$2" -m dependency -- own.txt' _ "$REPO" "$HELPER"

    [ "$status" -eq 2 ]
    [[ "$output" == *"verified test dependency changed: tests/test_owned.bats"* ]]
    [ -n "$(git -C "$REPO" status --short -- own.txt)" ]
}

@test "transient削除はHEAD証跡欠落をfail closedする" {
    mkdir -p "$REPO/tests" "$REPO/queue/tasks"
    printf 'change\n' >> "$REPO/own.txt"; printf proof > "$REPO/tests/test_transient.bats"
    printf 'task:\n  planned_paths: [own.txt, tests/test_transient.bats]\n' > "$REPO/queue/tasks/hayate.yaml"
    printf 'status: complete\npass: true\nfail: 0\nskip: 0\ntest_paths: [tests/test_transient.bats]\n' > "$REPO/receipt.yaml"
    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml NINJA_TEST_RECEIPT=receipt.yaml bash "$2" -m missing-head -- own.txt tests/test_transient.bats' _ "$REPO" "$HELPER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"HEAD evidence missing"* ]]
    [ -f "$REPO/tests/test_transient.bats" ]
}

@test "実CLI scopeの未計画新testを分類しpath宣言1件は別testを永続化しない" {
    mkdir -p "$REPO/tests" "$REPO/queue/tasks"
    printf 'change\n' >> "$REPO/own.txt"
    printf persistent > "$REPO/tests/test_persistent.bats"
    printf transient > "$REPO/tests/test_unplanned.bats"
    cat > "$REPO/queue/tasks/hayate.yaml" <<'YAML'
task:
  planned_paths: [own.txt]
  test_necessity:
    - path: tests/test_persistent.bats
      defense_target: persistent scope ownership remains atomic
      overlap_evidence: no equivalent contract exists
      overlaps_existing: false
      fixture_self_reference: false
      deprecated_mechanism: false
YAML
    head="$(git -C "$REPO" rev-parse HEAD)"
    printf 'status: complete\npass: true\nfail: 0\nskip: 0\ntest_paths: [tests/test_unplanned.bats]\nsource_head: %s\n' "$head" > "$REPO/receipt.yaml"
    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml NINJA_TEST_RECEIPT=receipt.yaml bash "$2" -m actual-scope -- own.txt tests/test_persistent.bats tests/test_unplanned.bats' _ "$REPO" "$HELPER"
    [ "$status" -eq 0 ]
    [ -f "$REPO/tests/test_persistent.bats" ]
    [ ! -e "$REPO/tests/test_unplanned.bats" ]
    git -C "$REPO" cat-file -e HEAD:tests/test_persistent.bats
}

# test_necessity: a persistent test committed earlier by the same task must remain valid evidence for a later production-only follow-up commit.
@test "same-task retained test allows production-only follow-up commit" {
    mkdir -p "$REPO/tests" "$REPO/queue/tasks"
    printf retained >"$REPO/tests/test_retained.bats"
    git -C "$REPO" add tests/test_retained.bats
    git -C "$REPO" commit -qm 'task-retained: add contract test'
    printf 'follow-up\n' >>"$REPO/own.txt"
    cat >"$REPO/queue/tasks/hayate.yaml" <<'YAML'
task:
  task_id: task-retained
  planned_paths: [own.txt]
  test_necessity:
    - path: tests/test_retained.bats
      defense_target: same task follow-up retains the established contract
      overlap_evidence: no equivalent retained contract exists
      overlaps_existing: false
      fixture_self_reference: false
      deprecated_mechanism: false
YAML
    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml bash "$2" -m "task-retained: production follow-up" -- own.txt' _ "$REPO" "$HELPER"
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" show --format= --name-only HEAD)" = own.txt ]
}

# test_necessity: a declaration with no actual new test and no same-task retained history must fail closed instead of silently blessing a missing contract.
@test "test necessity absent from current scope and same-task history blocks" {
    mkdir -p "$REPO/queue/tasks"
    printf 'follow-up\n' >>"$REPO/own.txt"
    cat >"$REPO/queue/tasks/hayate.yaml" <<'YAML'
task:
  task_id: task-missing
  planned_paths: [own.txt]
  test_necessity:
    - path: tests/test_missing.bats
      defense_target: missing contracts cannot be inferred from declarations
      overlap_evidence: no equivalent contract exists
      overlaps_existing: false
      fixture_self_reference: false
      deprecated_mechanism: false
YAML
    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml bash "$2" -m "task-missing: production follow-up" -- own.txt' _ "$REPO" "$HELPER"
    [ "$status" -ne 0 ]
    [[ "$output" == *"neither an actual new test nor retained in same-task history"* ]]
    [ -n "$(git -C "$REPO" status --short -- own.txt)" ]
}

@test "existing test net deletion requires justification and concurrent HEAD drift blocks" {
    mkdir -p "$REPO/tests" "$REPO/queue/tasks"
    printf 'one\ntwo\n' > "$REPO/tests/test_contract.bats"; git -C "$REPO" add tests/test_contract.bats; git -C "$REPO" commit -qm test-base
    printf 'one\n' > "$REPO/tests/test_contract.bats"
    printf 'task:\n  planned_paths: [tests/test_contract.bats]\n' > "$REPO/queue/tasks/hayate.yaml"
    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml bash "$2" -m shrink -- tests/test_contract.bats' _ "$REPO" "$HELPER"
    [ "$status" -eq 2 ]; [[ "$output" == *deletion_justification* ]]
    printf 'task:\n  deletion_justification: obsolete duplicate assertion\n  planned_paths: [tests/test_contract.bats]\n' > "$REPO/queue/tasks/hayate.yaml"
    expected_head="$(git -C "$REPO" rev-parse HEAD)"
    printf parallel > "$REPO/tests/test_parallel.bats"; git -C "$REPO" add tests/test_parallel.bats; git -C "$REPO" commit -qm parallel-test-change
    run bash -c 'cd "$1" && NINJA_SCOPE_EXPECTED_HEAD="$3" NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml bash "$2" -m shrink -- tests/test_contract.bats' _ "$REPO" "$HELPER" "$expected_head"
    [ "$status" -eq 2 ]; [[ "$output" == *"stale test receipt source_head"* ]]
}

@test "tracked test deletion with justification commits through the scoped helper" {
    mkdir -p "$REPO/tests" "$REPO/queue/tasks"
    printf 'obsolete contract\n' > "$REPO/tests/test_obsolete.bats"
    git -C "$REPO" add tests/test_obsolete.bats
    git -C "$REPO" commit -qm tracked-test-base
    rm "$REPO/tests/test_obsolete.bats"
    cat > "$REPO/queue/tasks/hayate.yaml" <<'YAML'
task:
  deletion_justification: contract is intentionally retired by the approved default-delete batch
  planned_paths: [tests/test_obsolete.bats]
YAML

    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml bash "$2" -m "delete tracked test" -- tests/test_obsolete.bats' _ "$REPO" "$HELPER"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-status -r HEAD)" = $'D\ttests/test_obsolete.bats' ]
    ! git -C "$REPO" cat-file -e HEAD:tests/test_obsolete.bats
    [ -z "$(git -C "$REPO" status --porcelain -- tests/test_obsolete.bats)" ]
}

@test "tracked test deletion blocks while canonical inventory column 2 still references it" {
    mkdir -p "$REPO/tests" "$REPO/queue/tasks" "$REPO/docs/research"
    printf 'obsolete contract\n' > "$REPO/tests/test_obsolete.bats"
    printf 'case_id,test_path\ntests/test_obsolete.bats#1,tests/test_obsolete.bats\n' > "$REPO/docs/research/inventory.csv"
    git -C "$REPO" add tests/test_obsolete.bats docs/research/inventory.csv
    git -C "$REPO" commit -qm tracked-test-inventory-base
    rm "$REPO/tests/test_obsolete.bats"
    printf 'task:\n  deletion_justification: approved retirement\n  planned_paths: [tests/test_obsolete.bats]\n' > "$REPO/queue/tasks/hayate.yaml"

    run bash -c 'cd "$1" && NINJA_SCOPE_TEST_INVENTORY=docs/research/inventory.csv NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml bash "$2" -m delete -- tests/test_obsolete.bats' _ "$REPO" "$HELPER"

    [ "$status" -eq 2 ]
    [[ "$output" == *"canonical inventory column 2"* ]]
    git -C "$REPO" cat-file -e HEAD:tests/test_obsolete.bats
}

@test "tracked test deletion proceeds after canonical inventory synchronization" {
    mkdir -p "$REPO/tests" "$REPO/queue/tasks" "$REPO/docs/research"
    reflux_identity="$(mktemp -d "$BATS_TMPDIR/ninja_scope_reflux_identity.XXXXXX")"
    git -C "$reflux_identity" init -q
    printf 'obsolete contract\n' > "$REPO/tests/test_obsolete.bats"
    printf 'case_id,test_path\ntests/test_obsolete.bats#1,tests/test_obsolete.bats\n' > "$REPO/docs/research/inventory.csv"
    git -C "$REPO" add tests/test_obsolete.bats docs/research/inventory.csv
    git -C "$REPO" commit -qm tracked-test-inventory-base
    rm "$REPO/tests/test_obsolete.bats"
    printf 'case_id,test_path\n' > "$REPO/docs/research/inventory.csv"
    printf 'task:\n  deletion_justification: approved retirement\n  planned_paths: [tests/test_obsolete.bats, docs/research/inventory.csv]\n' > "$REPO/queue/tasks/hayate.yaml"

    run bash -c 'cd "$1" && DM_SIGNAL_REPO="$3" NINJA_SCOPE_TEST_INVENTORY=docs/research/inventory.csv NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml bash "$2" -m delete -- tests/test_obsolete.bats docs/research/inventory.csv' _ "$REPO" "$HELPER" "$BATS_TMPDIR/does-not-exist"

    [ "$status" -eq 2 ]
    [[ "$output" == *"DM_SIGNAL_REPO"* ]]

    run bash -c 'cd "$1" && DM_SIGNAL_REPO="$3" NINJA_SCOPE_TEST_INVENTORY=docs/research/inventory.csv NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml bash "$2" -m delete -- tests/test_obsolete.bats docs/research/inventory.csv' _ "$REPO" "$HELPER" "$reflux_identity"

    if [ "$status" -ne 0 ]; then
        printf '%s\n' "$output" >&3
    fi
    [ "$status" -eq 0 ]
    ! git -C "$REPO" cat-file -e HEAD:tests/test_obsolete.bats
    [ "$(git -C "$REPO" show HEAD:docs/research/inventory.csv)" = 'case_id,test_path' ]
}

@test "true missing test path remains blocked independently of canonical inventory" {
    mkdir -p "$REPO/queue/tasks" "$REPO/docs/research"
    printf 'case_id,test_path\n' > "$REPO/docs/research/inventory.csv"
    printf 'task:\n  deletion_justification: approved retirement\n  planned_paths: [tests/test_never_existed.bats]\n' > "$REPO/queue/tasks/hayate.yaml"

    run bash -c 'cd "$1" && NINJA_SCOPE_TEST_INVENTORY=docs/research/inventory.csv NINJA_SCOPE_TASK_FILE=queue/tasks/hayate.yaml bash "$2" -m delete -- tests/test_never_existed.bats' _ "$REPO" "$HELPER"

    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK:"* ]]
    ! git -C "$REPO" cat-file -e HEAD:tests/test_never_existed.bats
}

make_ga282_fixture() {
    mkdir -p "$REPO/queue/tasks" "$REPO/projects/infra"
    printf 'task: base\n' > "$REPO/queue/tasks/hayate.yaml"
    printf 'lesson: base\n' > "$REPO/projects/infra/lessons_gunshi.yaml"
    printf 'lesson2: base\n' > "$REPO/projects/infra/lessons_karo.yaml"
    git -C "$REPO" add queue/tasks/hayate.yaml projects/infra/lessons_gunshi.yaml projects/infra/lessons_karo.yaml
    git -C "$REPO" commit -qm ga282-base
}

install_ga282_boundary_hook() {
    mkdir -p "$REPO/.git/hooks"
    cat > "$REPO/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
mapfile -t staged < <(git diff --cached --name-only)
printf '%s\n' "${staged[@]}" > .git/ga282-hook-seen
has_task=false
has_impl=false
for path in "${staged[@]}"; do
    [[ "$path" == queue/tasks/*.yaml ]] && has_task=true
    [[ "$path" == projects/* || "$path" == scripts/* || "$path" == tests/* || "$path" == context/* ]] && has_impl=true
done
if [[ "$has_task" == true && "$has_impl" == true ]]; then
    echo 'BLOCKED: queue/tasks/*.yaml cannot be committed with implementation files (GA-408)' >&2
    exit 1
fi
HOOK
    chmod +x "$REPO/.git/hooks/pre-commit"
}

@test "修正前: 通常commitは事前stage済み他者fileも含め2件commitする" {
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    printf 'own change\n' >> "$REPO/own.txt"
    git -C "$REPO" add own.txt

    git -C "$REPO" commit -qm unsafe

    run git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l)" -eq 2 ]
}

@test "ambient merge state is blocked before scoped commit and HEAD remains unchanged" {
    git -C "$REPO" checkout -qb side
    printf 'side\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    git -C "$REPO" commit -qm side
    git -C "$REPO" checkout -q master
    printf 'main\n' >> "$REPO/own.txt"
    git -C "$REPO" add own.txt
    git -C "$REPO" commit -qm main
    git -C "$REPO" merge --no-commit --no-ff side
    head_before="$(git -C "$REPO" rev-parse HEAD)"
    printf 'scoped\n' >> "$REPO/own.txt"

    run bash -c 'cd "$1" && bash "$2" -m must-block-merge -- own.txt' _ "$REPO" "$HELPER"

    [ "$status" -eq 2 ]
    [[ "$output" == *"repository operation state is active: MERGE_HEAD"* ]]
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
    [ "$(git -C "$REPO" rev-parse -q --verify MERGE_HEAD)" != "" ]
}

@test "cherry-pick and rebase ambient states are fail-closed without false success" {
    head_before="$(git -C "$REPO" rev-parse HEAD)"
    printf 'scoped\n' >> "$REPO/own.txt"
    for state in CHERRY_PICK_HEAD rebase-merge rebase-apply; do
        state_path="$(git -C "$REPO" rev-parse --git-path "$state")"
        [[ "$state_path" = /* ]] || state_path="$REPO/$state_path"
        if [[ "$state" == rebase-* ]]; then
            mkdir -p "$state_path"
        else
            printf '%s\n' "$head_before" > "$state_path"
        fi
        run bash -c 'cd "$1" && bash "$2" -m must-block-operation -- own.txt' _ "$REPO" "$HELPER"
        [ "$status" -eq 2 ]
        [[ "$output" == *"repository operation state is active: $state"* ]]
        [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
        if [[ "$state" == rebase-* ]]; then
            rmdir "$state_path"
        else
            rm -f "$state_path"
        fi
    done
}

@test "normal scoped commit has exactly the captured HEAD as its sole parent" {
    parent="$(git -C "$REPO" rev-parse HEAD)"
    printf 'single-parent\n' >> "$REPO/own.txt"

    run bash -c 'cd "$1" && bash "$2" -m single-parent -- own.txt 2>single-parent.err' _ "$REPO" "$HELPER"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" show -s --format=%P "$output")" = "$parent" ]
    [ "$(git -C "$REPO" show -s --format=%P "$output" | wc -w)" -eq 1 ]
}

@test "scoped commit publishes through commit-tree and update-ref without git commit porcelain" {
    printf 'bounded publication\n' >> "$REPO/own.txt"
    trace="$REPO/trace.json"

    run bash -c 'cd "$1" && GIT_TRACE2_EVENT="$3" bash "$2" -m bounded-publish -- own.txt' _ "$REPO" "$HELPER" "$trace"

    [ "$status" -eq 0 ]
    [[ "$output" == *"event=terminal_receipt"* ]]
    [ "$(printf '%s\n' "$output" | tail -1)" = "$(git -C "$REPO" rev-parse HEAD)" ]
    [ "$(grep -c '"name":"commit"' "$trace" || true)" -eq 0 ]
    [ "$(grep -c '"name":"commit-tree"' "$trace" || true)" -eq 1 ]
    [ "$(grep -c '"name":"update-ref"' "$trace" || true)" -eq 1 ]
}

@test "commit済みoutput消失後のno-change再照会はdurable receiptからhashと同一telemetryを返す" {
    printf 'recoverable publication\n' >> "$REPO/own.txt"
    run_id="receipt-reconnect-$BATS_TEST_NUMBER"

    run bash -c 'cd "$1" && NINJA_SCOPE_COMMIT_RUN_ID="$3" bash "$2" -m reconnect -- own.txt' _ "$REPO" "$HELPER" "$run_id"
    [ "$status" -eq 0 ]
    owner_hash="$(printf '%s\n' "$output" | tail -1)"
    owner_event="$(printf '%s\n' "$output" | grep '^event=completed ')"
    [[ "$owner_hash" =~ ^[0-9a-f]{40}$ ]]
    [[ "$owner_event" == *"commit_hash=$owner_hash"* ]]

    run bash -c 'cd "$1" && NINJA_SCOPE_COMMIT_RUN_ID="$3" bash "$2" -m reconnect -- own.txt' _ "$REPO" "$HELPER" "$run_id"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | tail -1)" = "$owner_hash" ]
    [ "$(printf '%s\n' "$output" | grep '^event=completed ')" = "$owner_event" ]
    [[ "$output" == *"event=terminal_receipt role=follower"* ]]
    [ -z "$(git -C "$REPO" status --porcelain -- own.txt)" ]
}

@test "stdout欠落後はrun id terminal ledgerからcomplete commitを回復しduplicateを作らない" {
    printf 'ledger recovery\n' >> "$REPO/own.txt"
    run_id="terminal-ledger-$BATS_TEST_NUMBER"

    run bash -c 'cd "$1" && NINJA_SCOPE_COMMIT_RUN_ID="$3" bash "$2" -m ledger-recovery -- own.txt >/dev/null' _ "$REPO" "$HELPER" "$run_id"
    [ "$status" -eq 0 ]
    head_after_first="$(git -C "$REPO" rev-parse HEAD)"
    ledger="$(printf '%s\n' "$output" | sed -n 's/.* ledger=\([^ ]*\).*/\1/p' | tail -1)"
    [ -s "$ledger" ]
    grep -qx "run_id=$run_id" "$ledger"
    grep -qx "commit_hash=$head_after_first" "$ledger"
    grep -qx 'rc=0' "$ledger"
    grep -qx 'phase=complete' "$ledger"
    grep -qx 'status_clean=true' "$ledger"
    grep -qx "head_generation=$head_after_first" "$ledger"
    grep -qx 'complete=true' "$ledger"

    run bash -c 'cd "$1" && NINJA_SCOPE_COMMIT_RUN_ID="$3" bash "$2" -m ledger-recovery -- own.txt' _ "$REPO" "$HELPER" "$run_id"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | tail -1)" = "$head_after_first" ]
    [ "$(git -C "$REPO" rev-list --count HEAD)" -eq 2 ]
}

@test "normal commit appends maintenance.auto=false and preserves caller config" {
    printf 'maintenance lane\n' >> "$REPO/own.txt"
    mkdir -p "$REPO/.git/hooks"
    cat > "$REPO/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
test "$(git config --bool maintenance.auto)" = false
test "$(git config scoped.fixture)" = preserved
HOOK
    chmod +x "$REPO/.git/hooks/pre-commit"
    trace="$REPO/trace.json"

    run bash -c 'cd "$1" && GIT_TRACE2_EVENT="$3" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=scoped.fixture GIT_CONFIG_VALUE_0=preserved bash "$2" -m maintenance-isolated -- own.txt' _ "$REPO" "$HELPER" "$trace"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" show --format= --name-only HEAD)" = own.txt ]
    [ "$(grep -c 'maintenance run --auto' "$trace" || true)" -eq 0 ]
    [ "$(grep -c '\"event\":\"cmd_name\".*\"name\":\"commit-tree\"' "$trace" || true)" -eq 1 ]
}

@test "invalid caller config count fails closed before commit" {
    head_before="$(git -C "$REPO" rev-parse HEAD)"
    printf 'must not commit\n' >> "$REPO/own.txt"

    run bash -c 'cd "$1" && GIT_CONFIG_COUNT=invalid bash "$2" -m invalid-config -- own.txt' _ "$REPO" "$HELPER"

    [ "$status" -eq 2 ]
    [[ "$output" == *"GIT_CONFIG_COUNT must be a non-negative integer"* ]]
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
}

@test "helperは対象1件だけcommitし他者stage1件を保持する" {
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    other_index_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    printf 'own change\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m safe -- own.txt"
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD)" = own.txt ]
    [ "$(git -C "$REPO" diff --cached --name-only)" = other.txt ]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$other_index_before" ]
}

@test "terminal eventは7 phaseを一意に記録し合計誤差200ms以下・計測overhead 50ms以下" {
    printf 'timed change\n' >> "$REPO/own.txt"

    run bash -c 'cd "$1" && bash "$2" -m timed -- own.txt 2>&1' _ "$REPO" "$HELPER"

    [ "$status" -eq 0 ]
    event="$(printf '%s\n' "$output" | grep '^event=completed ')"
    [ -n "$event" ]
    EVENT="$event" python3 - <<'PY'
import os, re

fields = dict(re.findall(r"([a-z0-9_]+)=([^ ]+)", os.environ["EVENT"]))
phases = (
    "read_tree", "add", "scope_sync", "guard", "git_commit",
    "advance_shared_index", "post_check",
)
for phase in phases:
    assert f"phase_{phase}_ms" in fields, phase
    assert fields[f"phase_{phase}_rc"] == "0", phase
assert sum(int(fields[f"phase_{phase}_ms"]) for phase in phases) == int(fields["phase_total_ms"])
assert abs(int(fields["phase_unattributed_ms"])) <= 200
assert int(fields["telemetry_overhead_ms"]) <= 50
measured = [key for key in fields if key.startswith("phase_") and key.endswith("_ms")
            and key not in {"phase_total_ms", "phase_unattributed_ms"}]
assert len(measured) == 7, measured
PY
}

@test "patch terminal eventも7 phaseを一意に記録し誤帰属しない" {
    make_shared_fixture; make_own_patch
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m patch-phases --patch '$REPO/own.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 0 ]
    terminal="$(printf '%s\n' "$output" | grep 'event=completed' | tail -1)"
    python3 - "$terminal" <<'PY'
import sys
fields = dict(item.split("=", 1) for item in sys.argv[1].split() if "=" in item)
phases = ["read_tree", "add", "scope_sync", "guard", "git_commit", "advance_shared_index", "post_check"]
assert all(fields.get(f"phase_{p}_rc") == "0" for p in phases), fields
assert len([k for k in fields if k.startswith("phase_") and k.endswith("_rc")]) == 7, fields
assert sum(int(fields[f"phase_{p}_ms"]) for p in phases) == int(fields["phase_total_ms"])
assert abs(int(fields["phase_unattributed_ms"])) <= 200, fields
assert int(fields["telemetry_overhead_ms"]) <= 50, fields
PY
}

@test "実行中helper本体の書換え後も起動時snapshotでcommitとshared indexを完遂する" {
    printf 'before\n' > "$REPO/self-mutation.txt"
    git -C "$REPO" add self-mutation.txt
    git -C "$REPO" commit -qm base-self-mutation
    printf 'after\n' > "$REPO/self-mutation.txt"
    mkdir -p "$REPO/helper/scripts/lib"
    helper_copy="$REPO/helper/scripts/ninja_scope_commit.sh"
    cp "$HELPER" "$helper_copy"
    cp "$(dirname "$HELPER")/lib/lock_path.sh" "$REPO/helper/scripts/lib/"
    cp "$(dirname "$HELPER")/lib/scope_path.sh" "$REPO/helper/scripts/lib/"
    cp "$(dirname "$HELPER")/lib/report_commit_nonoverlap_filter.sh" "$REPO/helper/scripts/lib/"

    snapshot_ready="$REPO/snapshot.ready"
    (
        for _ in $(seq 1 100); do
            [ -f "$snapshot_ready" ] && break
            sleep 0.05
        done
        [ -f "$snapshot_ready" ]
        printf '\nexit 2 # injected after immutable snapshot\n' >> "$helper_copy"
    ) &
    mutator_pid=$!
    run bash -c "cd '$REPO' && NINJA_SCOPE_COMMIT_TEST_SNAPSHOT_READY_FILE='$snapshot_ready' NINJA_SCOPE_COMMIT_TEST_AFTER_SNAPSHOT_DELAY=0.5 bash '$helper_copy' -m self-snapshot -- self-mutation.txt"
    run_status="$status"
    wait "$mutator_pid" || true

    [ "$run_status" -eq 0 ]
    [ "$(git -C "$REPO" show HEAD:self-mutation.txt)" = "after" ]
    [ -z "$(git -C "$REPO" status --porcelain -- self-mutation.txt)" ]
    [[ "$output" == *"event=completed"* ]]
}

@test "normal modeは専用indexから対象だけcommitしforeign stageをblob不変で保持する" {
    printf 'foreign staged\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    foreign_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    printf 'own unstaged\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m isolated-index -- own.txt"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD)" = own.txt ]
    [ "$(git -C "$REPO" diff --cached --name-only)" = other.txt ]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$foreign_before" ]
    [ "$(git -C "$REPO" status --porcelain -- own.txt)" = "" ]
}

# test_necessity: multi-path normal commits must advance the exact owned paths in one shared-index transaction while preserving every foreign staged entry and leaving no index lock; violation restores O(paths) DrvFS latency or clobbers another worker.
@test "multi-path shared index advance is one exact batch and preserves foreign stage" {
    mkdir -p "$REPO/bulk" "$REPO/trace-bin"
    owned=()
    for i in $(seq -w 1 24); do
        path="bulk/owned-${i}.txt"
        owned+=("$path")
        printf 'base-%s\n' "$i" > "$REPO/$path"
    done
    git -C "$REPO" add -- bulk
    git -C "$REPO" commit -qm bulk-base

    for path in "${owned[@]}"; do
        printf 'changed\n' >> "$REPO/$path"
    done
    printf 'foreign staged\n' >> "$REPO/other.txt"
    git -C "$REPO" add -- other.txt
    foreign_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    mkdir -p "$REPO/.git/hooks"
    cat > "$REPO/.git/hooks/post-commit" <<'POST_COMMIT'
#!/usr/bin/env bash
printf 'same-path foreign stage\n' >> bulk/owned-01.txt
unset GIT_INDEX_FILE
git add -- bulk/owned-01.txt
POST_COMMIT
    chmod +x "$REPO/.git/hooks/post-commit"

    cat > "$REPO/trace-bin/git" <<'GIT_WRAPPER'
#!/usr/bin/env bash
if [[ "${GIT_INDEX_FILE:-}" == "${TRACE_SHARED_INDEX:-}" && " $* " == *" update-index "* ]]; then
    printf '%s\n' "$*" >> "$TRACE_LOG"
fi
exec "$REAL_GIT" "$@"
GIT_WRAPPER
    chmod +x "$REPO/trace-bin/git"

    run bash -c 'cd "$1" && shift; TRACE_SHARED_INDEX="$PWD/.git/index" TRACE_LOG="$PWD/shared-index.trace" REAL_GIT="$(command -v git)" PATH="$PWD/trace-bin:$PATH" bash "$1" -m bulk-index -- "${@:2}"' _ "$REPO" "$HELPER" "${owned[@]}"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD | sort)" = "$(printf '%s\n' "${owned[@]}" | sort)" ]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$foreign_before" ]
    [ "$(git -C "$REPO" diff --cached --name-only | sort)" = $'bulk/owned-01.txt\nother.txt' ]
    [ "$(git -C "$REPO" show :bulk/owned-01.txt | tail -1)" = "same-path foreign stage" ]
    [[ "$output" == *"preserving newer staged entry: bulk/owned-01.txt"* ]]
    [ "$(grep -c -- '--index-info' "$REPO/shared-index.trace")" -eq 1 ]
    ! grep -q -- '--cacheinfo' "$REPO/shared-index.trace"
    [ ! -e "$REPO/.git/index.lock" ]
}

# test_necessity: an exact-path scoped commit must never refresh the whole shared worktree through status/non-cached diff while preserving foreign staged, tracked-worktree, and untracked bytes outside its owned path.
@test "exact owned path post-check uses no shared worktree scan and preserves every foreign dirty class" {
    mkdir -p "$REPO/trace-bin"
    git -C "$REPO" config core.filemode false
    chmod +x "$REPO/own.txt"
    printf 'foreign worktree\n' >> "$REPO/other.txt"
    printf 'foreign staged\n' > "$REPO/staged.txt"
    printf 'foreign untracked\n' > "$REPO/untracked.txt"
    git -C "$REPO" add -- staged.txt
    foreign_stage_before="$(git -C "$REPO" ls-files -s -- staged.txt)"
    foreign_worktree_before="$(git -C "$REPO" hash-object -- other.txt)"
    foreign_untracked_before="$(git -C "$REPO" hash-object -- untracked.txt)"
    printf 'owned change\n' >> "$REPO/own.txt"

    cat > "$REPO/trace-bin/git" <<'GIT_WRAPPER'
#!/usr/bin/env bash
if [[ "${1:-}" == status ]]; then
    printf 'status %s\n' "$*" >> "$TRACE_STATUS_LOG"
    exit 97
fi
if [[ "${1:-}" == diff && " $* " != *" --cached "* ]]; then
    printf 'worktree-diff %s\n' "$*" >> "$TRACE_STATUS_LOG"
    exit 98
fi
exec "$REAL_GIT" "$@"
GIT_WRAPPER
    chmod +x "$REPO/trace-bin/git"

    run bash -c 'cd "$1" && TRACE_STATUS_LOG="$PWD/status.trace" REAL_GIT="$(command -v git)" PATH="$PWD/trace-bin:$PATH" bash "$2" -m no-status -- own.txt' _ "$REPO" "$HELPER"

    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN(GA-260)"* ]]
    [ ! -e "$REPO/status.trace" ]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD)" = own.txt ]
    [ "$(git -C "$REPO" ls-files -s -- staged.txt)" = "$foreign_stage_before" ]
    [ "$(git -C "$REPO" hash-object -- other.txt)" = "$foreign_worktree_before" ]
    [ "$(git -C "$REPO" hash-object -- untracked.txt)" = "$foreign_untracked_before" ]
    [ "$(git -C "$REPO" diff --cached --name-only)" = staged.txt ]
    [ -n "$(git -C "$REPO" diff --name-only -- other.txt)" ]
    [ -n "$(git -C "$REPO" ls-files --others --exclude-standard -- untracked.txt)" ]
    [ ! -e "$REPO/.git/index.lock" ]
}

@test "2並列の事前stage済みcommitはsubject/pathを分離しforeign stageを保持する" {
    printf 'alpha change\n' >> "$REPO/own.txt"
    printf 'beta change\n' >> "$REPO/other.txt"
    printf 'foreign base\n' > "$REPO/foreign.txt"
    git -C "$REPO" add foreign.txt
    git -C "$REPO" commit -qm foreign-base
    printf 'foreign pending\n' >> "$REPO/foreign.txt"
    git -C "$REPO" add own.txt other.txt foreign.txt
    foreign_index_before="$(git -C "$REPO" ls-files -s -- foreign.txt)"
    mkdir -p "$REPO/.git/hooks"
    cat > "$REPO/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
sleep 0.2
HOOK
    chmod +x "$REPO/.git/hooks/pre-commit"

    (
        cd "$REPO"
        bash "$HELPER" -m subject-alpha -- own.txt
        printf 'alpha-parent-alive\n' > "$REPO/alpha.alive"
    ) >"$REPO/alpha.out" 2>&1 &
    alpha_pid=$!
    (
        cd "$REPO"
        bash "$HELPER" -m subject-beta -- other.txt
        printf 'beta-parent-alive\n' > "$REPO/beta.alive"
    ) >"$REPO/beta.out" 2>&1 &
    beta_pid=$!

    wait "$alpha_pid"
    alpha_rc=$?
    wait "$beta_pid"
    beta_rc=$?

    [ "$alpha_rc" -eq 0 ]
    [ "$beta_rc" -eq 0 ]
    [ -f "$REPO/alpha.alive" ]
    [ -f "$REPO/beta.alive" ]
    [ "$(git -C "$REPO" log -2 --format=%s | sort)" = $'subject-alpha\nsubject-beta' ]
    [ "$(git -C "$REPO" log --format=%H --grep='^subject-alpha$' -1 | xargs -r git -C "$REPO" diff-tree --no-commit-id --name-only -r)" = own.txt ]
    [ "$(git -C "$REPO" log --format=%H --grep='^subject-beta$' -1 | xargs -r git -C "$REPO" diff-tree --no-commit-id --name-only -r)" = other.txt ]
    [ "$(git -C "$REPO" ls-files -s -- foreign.txt)" = "$foreign_index_before" ]
    [ "$(git -C "$REPO" diff --cached --name-only)" = foreign.txt ]
}

@test "normal modeは対象pathの完全stage済みblobを安全にcommitする" {
    printf 'fully staged own change\n' >> "$REPO/own.txt"
    git -C "$REPO" add own.txt

    run bash -c "cd '$REPO' && bash '$HELPER' -m staged-safe -- own.txt"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD)" = own.txt ]
    [ "$(git -C "$REPO" status --porcelain -- own.txt)" = "" ]
}

@test "GA-282 mixed stageはtask YAMLを分離しimplementationだけcommit、foreign task stageを保持する" {
    make_ga282_fixture
    install_ga282_boundary_hook
    printf 'task: assigned\n' > "$REPO/queue/tasks/hayate.yaml"
    printf 'lesson: fixed\n' > "$REPO/projects/infra/lessons_gunshi.yaml"
    git -C "$REPO" add queue/tasks/hayate.yaml projects/infra/lessons_gunshi.yaml
    task_index_before="$(git -C "$REPO" ls-files -s -- queue/tasks/hayate.yaml)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m ga282-mixed -- queue/tasks/hayate.yaml projects/infra/lessons_gunshi.yaml"

    [ "$status" -eq 0 ]
    [[ "$output" == *"INFO(GA-282): separated live task YAML"* ]]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD)" = projects/infra/lessons_gunshi.yaml ]
    [ "$(git -C "$REPO" show HEAD:projects/infra/lessons_gunshi.yaml)" = 'lesson: fixed' ]
    [ "$(git -C "$REPO" diff --cached --name-only)" = queue/tasks/hayate.yaml ]
    [ "$(git -C "$REPO" ls-files -s -- queue/tasks/hayate.yaml)" = "$task_index_before" ]
    [ "$(cat "$REPO/.git/ga282-hook-seen")" = projects/infra/lessons_gunshi.yaml ]
}

@test "GA-282 task-only commitは分離せずpre-commit境界を通過する" {
    make_ga282_fixture
    install_ga282_boundary_hook
    printf 'task: completed\n' > "$REPO/queue/tasks/hayate.yaml"
    git -C "$REPO" add queue/tasks/hayate.yaml

    run bash -c "cd '$REPO' && bash '$HELPER' -m ga282-task-only -- queue/tasks/hayate.yaml"

    [ "$status" -eq 0 ]
    [[ "$output" != *"INFO(GA-282)"* ]]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD)" = queue/tasks/hayate.yaml ]
    [ "$(cat "$REPO/.git/ga282-hook-seen")" = queue/tasks/hayate.yaml ]
}

@test "GA-282 implementation-only commitは実装欠落なしで従来通りcommitする" {
    make_ga282_fixture
    install_ga282_boundary_hook
    printf 'lesson: implementation-only\n' > "$REPO/projects/infra/lessons_gunshi.yaml"

    run bash -c "cd '$REPO' && bash '$HELPER' -m ga282-implementation-only -- projects/infra/lessons_gunshi.yaml"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD)" = projects/infra/lessons_gunshi.yaml ]
    [ "$(git -C "$REPO" show HEAD:projects/infra/lessons_gunshi.yaml)" = 'lesson: implementation-only' ]
}

@test "GA-282 parallel mixed workersは実装2commitを分離しtask stageをblob不変で保持する" {
    make_ga282_fixture
    install_ga282_boundary_hook
    printf 'task: running\n' > "$REPO/queue/tasks/hayate.yaml"
    printf 'lesson: worker-a\n' > "$REPO/projects/infra/lessons_gunshi.yaml"
    printf 'lesson2: worker-b\n' > "$REPO/projects/infra/lessons_karo.yaml"
    git -C "$REPO" add queue/tasks/hayate.yaml projects/infra/lessons_gunshi.yaml projects/infra/lessons_karo.yaml
    task_index_before="$(git -C "$REPO" ls-files -s -- queue/tasks/hayate.yaml)"

    (cd "$REPO" && bash "$HELPER" -m ga282-worker-a -- queue/tasks/hayate.yaml projects/infra/lessons_gunshi.yaml) >"$REPO/a.out" 2>&1 &
    a_pid=$!
    (cd "$REPO" && bash "$HELPER" -m ga282-worker-b -- queue/tasks/hayate.yaml projects/infra/lessons_karo.yaml) >"$REPO/b.out" 2>&1 &
    b_pid=$!
    wait "$a_pid"; a_rc=$?
    wait "$b_pid"; b_rc=$?

    [ "$a_rc" -eq 0 ]
    [ "$b_rc" -eq 0 ]
    [ "$(git -C "$REPO" log -2 --format=%s | sort)" = $'ga282-worker-a\nga282-worker-b' ]
    [ "$(git -C "$REPO" log --format=%H --grep='^ga282-worker-a$' -1 | xargs -r git -C "$REPO" diff-tree --no-commit-id --name-only -r)" = projects/infra/lessons_gunshi.yaml ]
    [ "$(git -C "$REPO" log --format=%H --grep='^ga282-worker-b$' -1 | xargs -r git -C "$REPO" diff-tree --no-commit-id --name-only -r)" = projects/infra/lessons_karo.yaml ]
    [ "$(git -C "$REPO" diff --cached --name-only)" = queue/tasks/hayate.yaml ]
    [ "$(git -C "$REPO" ls-files -s -- queue/tasks/hayate.yaml)" = "$task_index_before" ]
}

@test "normal modeはpartial stageとworktree不一致をfail-closedしindexを保持する" {
    printf 'staged owner unknown\n' >> "$REPO/own.txt"
    git -C "$REPO" add own.txt
    staged_before="$(git -C "$REPO" ls-files -s -- own.txt)"
    printf 'additional unstaged\n' >> "$REPO/own.txt"
    head_before="$(git -C "$REPO" rev-parse HEAD)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m must-block -- own.txt"

    [ "$status" -eq 2 ]
    [[ "$output" == *"partial/foreign staged content"* ]]
    [ "$(git -C "$REPO" ls-files -s -- own.txt)" = "$staged_before" ]
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
}

@test "commit後のdirty差分は別eventとしてWARNし公開済みcommitを失敗へ戻さない" {
    mkdir -p "$REPO/.git/hooks"
    cat > "$REPO/.git/hooks/post-commit" <<'HOOK'
#!/bin/sh
printf 'dirty after commit\n' > own.txt
HOOK
    chmod +x "$REPO/.git/hooks/post-commit"
    printf 'committed change\n' > "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m overlap -- own.txt"

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN(GA-260)"* ]]
    [[ "$output" == *"own.txt"* ]]
}

make_shared_fixture() {
    : > "$REPO/shared.txt"
    for i in $(seq 1 36); do printf 'base-%02d\n' "$i" >> "$REPO/shared.txt"; done
    git -C "$REPO" add shared.txt
    git -C "$REPO" commit -qm shared-base
}

make_own_patch() {
    cp "$REPO/shared.txt" "$REPO/shared.working"
    for i in 2 9 16 23 30; do sed -i "${i}s/$/-own/" "$REPO/shared.txt"; done
    git -C "$REPO" diff -- shared.txt > "$REPO/own.patch"
    mv "$REPO/shared.working" "$REPO/shared.txt"
}

# test_necessity: moving live HEAD after patch private-index construction must
# not classify an unrelated committed path as patch-owned scope pollution.
@test "patch modeはprivate index構築後の無関係HEAD前進をscope汚染と誤判定しない" {
    make_shared_fixture; make_own_patch
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    ready="$BATS_TEST_TMPDIR/patch-index-ready"

    (
        for _ in $(seq 1 200); do
            [[ -e "$ready" ]] && break
            sleep 0.01
        done
        [[ -e "$ready" ]] || exit 91
        printf 'parallel\n' > "$REPO/unrelated.txt"
        git -C "$REPO" add unrelated.txt
        git -C "$REPO" commit -qm unrelated-parallel
    ) &
    advancer=$!

    run bash -c "cd '$REPO' && NINJA_SCOPE_PATCH_INDEX_READY_FILE='$ready' NINJA_SCOPE_PATCH_AFTER_INDEX_DELAY=0.5 bash '$HELPER' -m moving-head --patch '$REPO/own.patch' --base-blob '$base_blob' -- shared.txt"
    wait "$advancer"

    [ "$status" -eq 0 ]
    [[ "$output" != *"patch polluted temporary index scope"* ]]
    [ "$(git -C "$REPO" show HEAD:shared.txt | grep -c -- '-own')" -eq 5 ]
    git -C "$REPO" cat-file -e HEAD:unrelated.txt
}

@test "patch modeは同内容hunkが別位置へ適用されたらcommit前にBLOCKする" {
    printf 'start\nrepeat\nend\nstart\nrepeat\nend\n' > "$REPO/ambiguous.txt"
    git -C "$REPO" add ambiguous.txt && git -C "$REPO" commit -qm ambiguous-base
    printf '%s\n' \
        'diff --git a/ambiguous.txt b/ambiguous.txt' \
        '--- a/ambiguous.txt' '+++ b/ambiguous.txt' \
        '@@ -4,3 +4,3 @@' ' start' '-repeat' '+changed' ' end' > "$REPO/ambiguous.patch"
    # Remove the intended bottom block only in the working fixture used to
    # demonstrate that git apply can relocate identical context to the top.
    sed -i '4,6d' "$REPO/ambiguous.txt"
    git -C "$REPO" add ambiguous.txt && git -C "$REPO" commit -qm split-delete
    base_blob="$(git -C "$REPO" rev-parse HEAD:ambiguous.txt)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m must-block --patch '$REPO/ambiguous.patch' --base-blob '$base_blob' -- ambiguous.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"does not exactly match requested patch position/content"* ]]
    [ "$(git -C "$REPO" log --format=%s -1)" = split-delete ]
}

@test "patch modeはlinked worktreeでも意図位置をcommitしforeign hunkを保全する" {
    make_shared_fixture; make_own_patch
    # Parallel/aborted suites may reuse BATS_TMPDIR + test number.  Reserve a
    # process-unique pathname, then let `git worktree add` create it.
    linked="$(mktemp -d "${TMPDIR:-/tmp}/ninja-linked-${BATS_TEST_NUMBER}.XXXXXX")"
    rmdir "$linked"
    git -C "$REPO" worktree add -q -b linked-branch "$linked"
    for i in 1 4 7; do sed -i "${i}s/$/-foreign/" "$linked/shared.txt"; done
    before="$(cat "$linked/shared.txt")"
    base_blob="$(git -C "$linked" rev-parse HEAD:shared.txt)"

    run bash -c "cd '$linked' && bash '$HELPER' -m linked-own --patch '$REPO/own.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 0 ]
    [ "$(git -C "$linked" show HEAD:shared.txt | grep -c -- '-own')" -eq 5 ]
    [ "$(cat "$linked/shared.txt")" = "$before" ]
    [ "$(grep -c -- '-foreign' "$linked/shared.txt")" -eq 3 ]
    git -C "$REPO" worktree remove -f "$linked"
}

make_task_worktree_shared_source_fixture() {
    mkdir -p "$REPO/scripts" "$REPO/queue/tasks"
    for path in scripts/cache-one.sh scripts/cache-two.sh scripts/cache-three.sh; do
        printf 'base source\n' > "$REPO/$path"
    done
    git -C "$REPO" add scripts/cache-one.sh scripts/cache-two.sh scripts/cache-three.sh
    git -C "$REPO" commit -qm shared-source-base
    linked="$(mktemp -d "${TMPDIR:-/tmp}/ninja-shared-source-${BATS_TEST_NUMBER}.XXXXXX")"
    rmdir "$linked"
    git -C "$REPO" worktree add -q -b "shared-source-${BATS_TEST_NUMBER}" "$linked"
    cat > "$REPO/queue/tasks/hayate.yaml" <<YAML
task:
  task_id: shared-source-contract
  parent_cmd: cmd_shared-source-contract
  task_worktree_path: $linked
  task_worktree_source_paths: [scripts/cache-one.sh, scripts/cache-two.sh, scripts/cache-three.sh]
YAML
    printf 'owned task change\n' >> "$linked/own.txt"
}

@test "共有rootの3 dirty sourceがtask worktreeと同一contentならcommitを許可する" {
    make_task_worktree_shared_source_fixture
    paths=(scripts/cache-one.sh scripts/cache-two.sh scripts/cache-three.sh)
    for path in "${paths[@]}"; do
        printf 'same source edit\n' > "$REPO/$path"
        printf 'same source edit\n' > "$linked/$path"
    done

    root_matches=0
    head_differences=0
    for path in "${paths[@]}"; do
        cmp -s "$REPO/$path" "$linked/$path"
        root_matches=$((root_matches + 1))
        if ! git -C "$REPO" diff --quiet HEAD -- "$path"; then
            head_differences=$((head_differences + 1))
        fi
    done
    [ "$root_matches" -eq 3 ]
    [ "$head_differences" -eq 3 ]

    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE="$3" bash "$2" -m shared-content -- own.txt' _ "$linked" "$HELPER" "$REPO/queue/tasks/hayate.yaml"
    [ "$status" -eq 0 ]
    [ "$(git -C "$linked" show --format= --name-only HEAD)" = own.txt ]
    [ -n "$(git -C "$REPO" status --porcelain -- scripts/cache-one.sh scripts/cache-two.sh scripts/cache-three.sh)" ]
    git -C "$REPO" worktree remove -f "$linked"
}

@test "共有rootとtask worktreeのdirty source content相違はBLOCKする" {
    make_task_worktree_shared_source_fixture
    printf 'root source edit\n' > "$REPO/scripts/cache-one.sh"
    printf 'task source edit\n' > "$linked/scripts/cache-one.sh"

    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE="$3" bash "$2" -m different-content -- own.txt' _ "$linked" "$HELPER" "$REPO/queue/tasks/hayate.yaml"
    [ "$status" -eq 2 ]
    [[ "$output" == *"content differs from task worktree: scripts/cache-one.sh"* ]]
    [ -n "$(git -C "$linked" status --porcelain -- own.txt)" ]
    git -C "$REPO" worktree remove -f "$linked"
}

@test "共有root dirty sourceのtask worktree片側欠落はBLOCKする" {
    make_task_worktree_shared_source_fixture
    printf 'root source edit\n' > "$REPO/scripts/cache-two.sh"
    rm "$linked/scripts/cache-two.sh"

    run bash -c 'cd "$1" && NINJA_SCOPE_TASK_FILE="$3" bash "$2" -m missing-content -- own.txt' _ "$linked" "$HELPER" "$REPO/queue/tasks/hayate.yaml"
    [ "$status" -eq 2 ]
    [[ "$output" == *"regular-file parity unavailable: scripts/cache-two.sh"* ]]
    [ -n "$(git -C "$linked" status --porcelain -- own.txt)" ]
    git -C "$REPO" worktree remove -f "$linked"
}

@test "patch modeはpostverify異常時にcommitせずforeign stageを保全する" {
    make_shared_fixture; make_own_patch
    printf 'foreign staged\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    foreign_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    printf 'not a patch\n' > "$REPO/own.patch"

    run bash -c "cd '$REPO' && bash '$HELPER' -m invalid --patch '$REPO/own.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 2 ]
    [ "$(git -C "$REPO" log --format=%s -1)" = shared-base ]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$foreign_before" ]
}

@test "patch modeは同一fileの自分5 hunkだけcommitし他者13 hunkと共有indexを完全保全する" {
    make_shared_fixture
    make_own_patch
    for i in 1 4 7 10 13 18 21 24 27 31 33 35 36; do sed -i "${i}s/$/-other/" "$REPO/shared.txt"; done
    printf 'other staged\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    other_index_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    worktree_before="$(cat "$REPO/shared.txt")"
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m own-five --patch '$REPO/own.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" show --format= --numstat HEAD -- shared.txt | awk '{print $1+$2}')" -eq 10 ]
    [ "$(git -C "$REPO" show HEAD:shared.txt | grep -c -- '-own')" -eq 5 ]
    [ "$(cat "$REPO/shared.txt")" = "$worktree_before" ]
    [ "$(grep -c -- '-other' "$REPO/shared.txt")" -eq 13 ]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$other_index_before" ]
    [ "$(git -C "$REPO" diff --cached --name-only)" = other.txt ]
}

@test "preexisting same-file foreign 506行とtask-owned 10変更はpatch modeでforeign吸収0件" {
    : > "$REPO/shared.txt"
    for i in $(seq 1 600); do printf 'base-%03d\n' "$i" >> "$REPO/shared.txt"; done
    git -C "$REPO" add shared.txt
    git -C "$REPO" commit -qm same-file-base
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"

    cp "$REPO/shared.txt" "$REPO/shared.base"
    for i in 10 60 110 160 210 260 310 360 410 460; do
        sed -i "${i}s/$/-task/" "$REPO/shared.txt"
    done
    git -C "$REPO" diff -- shared.txt > "$REPO/task.patch"
    mv "$REPO/shared.base" "$REPO/shared.txt"

    for i in $(seq 1 506); do printf 'foreign-%03d\n' "$i" >> "$REPO/shared.txt"; done
    for i in 10 60 110 160 210 260 310 360 410 460; do
        sed -i "${i}s/$/-task/" "$REPO/shared.txt"
    done
    worktree_before="$(git -C "$REPO" hash-object shared.txt)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m same-file-owned --patch '$REPO/task.patch' --base-blob '$base_blob' -- shared.txt"

    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" show HEAD:shared.txt | grep -c -- '-task')" -eq 10 ]
    [ "$(git -C "$REPO" show HEAD:shared.txt | grep -c '^foreign-')" -eq 0 ]
    [ "$(git -C "$REPO" hash-object shared.txt)" = "$worktree_before" ]
    [ "$(grep -c '^foreign-' "$REPO/shared.txt")" -eq 506 ]
    [ "$(git -C "$REPO" show --format= --numstat HEAD -- shared.txt | awk '{print $1+$2}')" -eq 20 ]
}

@test "patch mode commit後の直接git add競合はforeign stageを上書きしない" {
    make_shared_fixture; make_own_patch
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    mkdir -p "$REPO/.git/hooks"
    cat > "$REPO/.git/hooks/post-commit" <<'HOOK'
#!/usr/bin/env bash
printf 'foreign-after-commit\n' >> shared.txt
unset GIT_INDEX_FILE
git add shared.txt
HOOK
    chmod +x "$REPO/.git/hooks/post-commit"

    run bash -c "cd '$REPO' && bash '$HELPER' -m patch-cas --patch '$REPO/own.patch' --base-blob '$base_blob' -- shared.txt"

    [ "$status" -eq 0 ]
    [[ "$output" == *"preserving newer staged entry"* ]]
    [ "$(git -C "$REPO" show :shared.txt | tail -1)" = foreign-after-commit ]
    [ "$(git -C "$REPO" show HEAD:shared.txt | grep -c -- '-own')" -eq 5 ]
    [ "$(git -C "$REPO" diff-tree --no-commit-id --name-only -r HEAD)" = shared.txt ]
}

@test "旧HEAD blobがshared indexに残るMM状態でも後続patchはcommitしforeign内容を保全する(B27)" {
    make_shared_fixture; make_own_patch
    old_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    base_blob="$old_blob"
    run bash -c "cd '$REPO' && bash '$HELPER' -m first --patch '$REPO/own.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 0 ]

    # 隔離fixtureで事故状態を構成: HEADは新blob、indexだけ旧HEAD、worktreeはforeign hunk。
    git -C "$REPO" update-index --cacheinfo "100644,$old_blob,shared.txt"
    printf 'foreign-worktree\n' >> "$REPO/shared.txt"
    stale_entry="$(git -C "$REPO" ls-files -s -- shared.txt)"
    head_before="$(git -C "$REPO" rev-parse HEAD)"
    # 2本目のpatchは現HEAD基準(line36、1本目のown.patchが触れていない行)で有効に構成する。
    printf '%s\n' 'diff --git a/shared.txt b/shared.txt' '--- a/shared.txt' '+++ b/shared.txt' \
        '@@ -36 +36 @@' '-base-36' '+base-36-second-own' > "$REPO/next.patch"
    new_base="$(git -C "$REPO" rev-parse HEAD:shared.txt)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m second --patch '$REPO/next.patch' --base-blob '$new_base' -- shared.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"leaving it untouched"* ]]
    # shared indexの旧stale entryはcommit後も一切上書きされず保全される(B27 AC2)。
    [ "$(git -C "$REPO" ls-files -s -- shared.txt)" = "$stale_entry" ]
    [ "$(tail -1 "$REPO/shared.txt")" = foreign-worktree ]
    [ "$(git -C "$REPO" rev-parse HEAD)" != "$head_before" ]
    [ "$(git -C "$REPO" show HEAD:shared.txt | tail -1)" = base-36-second-own ]
}

@test "shared indexに事前staged済みforeign内容がある状態でもpatch modeはcommitしforeign stageを保全する(B27)" {
    make_shared_fixture
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    make_own_patch

    # 他者(例: 自動生成索引の再生成)が同一pathへ別内容を自分のpatch呼び出し前に
    # 既にstage済み。normal modeは「partial/foreign staged content...use --patch」で
    # BLOCKし、この--patch modeが実際の脱出経路になる(2026-07-25実例:
    # logs/push_dirty_tree_bypass.jsonl context/lord-conversation-index.md)。
    printf 'foreign pre-staged content\n' > "$REPO/shared.txt"
    git -C "$REPO" add shared.txt
    foreign_entry="$(git -C "$REPO" ls-files -s -- shared.txt)"
    worktree_before="$(cat "$REPO/shared.txt")"

    run bash -c "cd '$REPO' && bash '$HELPER' -m b27-patch --patch '$REPO/own.patch' --base-blob '$base_blob' -- shared.txt"

    [ "$status" -eq 0 ]
    [[ "$output" == *"leaving it untouched"* ]]
    [ "$(git -C "$REPO" show HEAD:shared.txt | grep -c -- '-own')" -eq 5 ]
    [ "$(git -C "$REPO" ls-files -s -- shared.txt)" = "$foreign_entry" ]
    [ "$(cat "$REPO/shared.txt")" = "$worktree_before" ]
}

@test "patch modeはbase blob不一致をcommit前にBLOCKする" {
    make_shared_fixture; make_own_patch
    run bash -c "cd '$REPO' && bash '$HELPER' -m stale --patch '$REPO/own.patch' --base-blob 0000000000000000000000000000000000000000 -- shared.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"base blob mismatch"* ]]
}

@test "patch modeはscope外path混入をcommit前にBLOCKする" {
    make_shared_fixture; make_own_patch
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" diff -- shared.txt other.txt > "$REPO/mixed.patch"
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    run bash -c "cd '$REPO' && bash '$HELPER' -m mixed --patch '$REPO/mixed.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"out-of-scope path"* ]]
}

@test "patch modeは空patchと適用不能patchをcommit前にBLOCKする" {
    make_shared_fixture
    : > "$REPO/empty.patch"
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    run bash -c "cd '$REPO' && bash '$HELPER' -m empty-patch --patch '$REPO/empty.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"missing or empty"* ]]

    printf '%s\n' 'diff --git a/shared.txt b/shared.txt' '--- a/shared.txt' '+++ b/shared.txt' '@@ -1 +1 @@' '-not-the-base' '+changed' > "$REPO/bad.patch"
    run bash -c "cd '$REPO' && bash '$HELPER' -m bad-patch --patch '$REPO/bad.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"does not apply cleanly"* ]]
}

@test "patch modeは削除・新規file・改行境界のpatchを扱う" {
    make_shared_fixture
    printf 'tail-no-newline' >> "$REPO/shared.txt"
    git -C "$REPO" add shared.txt && git -C "$REPO" commit -qm newline-base
    printf '\nchanged-tail\n' >> "$REPO/shared.txt"
    git -C "$REPO" diff -- shared.txt > "$REPO/newline.patch"
    git -C "$REPO" checkout -q -- shared.txt
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    run bash -c "cd '$REPO' && bash '$HELPER' -m newline --patch '$REPO/newline.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 0 ]

    printf 'new file\n' > "$REPO/new.txt"
    git -C "$REPO" diff --no-index /dev/null new.txt > "$REPO/new.patch" || true
    run bash -c "cd '$REPO' && bash '$HELPER' -m new --patch '$REPO/new.patch' --base-blob 0000000000000000000000000000000000000000 -- new.txt"
    [ "$status" -eq 0 ]

    # patch modeはworking treeを意図的に不変に保つ。次の独立edge fixture前に
    # sandbox内だけHEADへ同期する（本番helperは他者差分へ触れない）。
    git -C "$REPO" checkout -q -- shared.txt
    base_blob="$(git -C "$REPO" rev-parse HEAD:shared.txt)"
    git -C "$REPO" rm -q shared.txt
    git -C "$REPO" diff --cached -- shared.txt > "$REPO/delete.patch"
    git -C "$REPO" reset -q HEAD -- shared.txt
    git -C "$REPO" checkout -q -- shared.txt
    run bash -c "cd '$REPO' && bash '$HELPER' -m delete --patch '$REPO/delete.patch' --base-blob '$base_blob' -- shared.txt"
    [ "$status" -eq 0 ]
    ! git -C "$REPO" cat-file -e HEAD:shared.txt
}

@test "空scopeはBLOCKする" {
    run bash -c "cd '$REPO' && bash '$HELPER' -m empty --"
    [ "$status" -eq 2 ]
    [[ "$output" == *"commit scope is empty"* ]]
}

@test "stale shared index.lock is removed inside commit transaction" {
    printf 'own change\n' >> "$REPO/own.txt"
    : > "$REPO/.git/index.lock"
    run bash -c "cd '$REPO' && bash '$HELPER' -m stale-lock -- own.txt"
    [ "$status" -eq 0 ]
    [ ! -e "$REPO/.git/index.lock" ]
    [ -z "$(git -C "$REPO" status --porcelain -- own.txt)" ]
}

@test "foreign active index lock after HEAD publication is retried and foreign stage is preserved" {
    printf 'own change\n' >> "$REPO/own.txt"
    printf 'foreign change\n' >> "$REPO/other.txt"
    mkdir -p "$REPO/.git/hooks"
cat > "$REPO/.git/hooks/post-commit" <<'HOOK'
#!/usr/bin/env bash
(
    cp .git/index .git/foreign-index
    GIT_INDEX_FILE=.git/foreign-index git add other.txt
    mv .git/foreign-index .git/index.lock
    exec 9>>.git/index.lock
    sleep 0.15
    mv .git/index.lock .git/index
) </dev/null >.git/foreign-writer.log 2>&1 &
for _ in $(seq 1 100); do
    [[ -e .git/index.lock ]] && exit 0
    sleep 0.01
done
exit 1
HOOK
    chmod +x "$REPO/.git/hooks/post-commit"

    run bash -c 'cd "$1" && NINJA_SCOPE_COMMIT_INDEX_RETRY_ATTEMPTS=100 NINJA_SCOPE_COMMIT_INDEX_RETRY_DELAY=0.01 bash "$2" -m foreign-lock -- own.txt' _ "$REPO" "$HELPER"

    [ "$status" -eq 0 ]
    hash="$(printf '%s\n' "$output" | tail -1)"
    [[ "$hash" =~ ^[0-9a-f]{40}$ ]]
    [ "$(git -C "$REPO" diff --cached --name-only)" = other.txt ]
    [ -z "$(git -C "$REPO" status --porcelain -- own.txt)" ]
    [[ "$output" == *"event=terminal_receipt"* ]]
}

@test "foreign active index lock retry exhaustion emits durable commit receipt" {
    printf 'own change\n' >> "$REPO/own.txt"
    mkdir -p "$REPO/.git/hooks"
    cat > "$REPO/.git/hooks/post-commit" <<'HOOK'
#!/usr/bin/env bash
(
    exec 9>.git/index.lock
    sleep 1
    rm -f .git/index.lock
) </dev/null >.git/foreign-writer.log 2>&1 &
for _ in $(seq 1 100); do
    [[ -e .git/index.lock ]] && exit 0
    sleep 0.01
done
exit 1
HOOK
    chmod +x "$REPO/.git/hooks/post-commit"
    run_id="foreign-timeout-$BATS_TEST_NUMBER"

    run bash -c 'cd "$1" && NINJA_SCOPE_COMMIT_RUN_ID="$3" NINJA_SCOPE_COMMIT_INDEX_RETRY_ATTEMPTS=2 NINJA_SCOPE_COMMIT_INDEX_RETRY_DELAY=0.01 bash "$2" -m foreign-timeout -- own.txt' _ "$REPO" "$HELPER" "$run_id"

    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK: shared index did not converge after 2 attempts"* ]]
    event="$(printf '%s\n' "$output" | grep '^event=failed ')"
    hash="$(printf '%s\n' "$event" | sed -n 's/.* commit_hash=\([0-9a-f]\{40\}\).*/\1/p')"
    [[ "$hash" =~ ^[0-9a-f]{40}$ ]]
    receipt="$(printf '%s\n' "$output" | sed -n 's/.* receipt=\([^ ]*\).*/\1/p' | tail -1)"
    [ -s "$receipt" ]
    grep -qx "commit_hash=$hash" "$receipt"
    grep -qx 'rc=1' "$receipt"
    ledger="$(printf '%s\n' "$output" | sed -n 's/.* ledger=\([^ ]*\).*/\1/p' | tail -1)"
    [ -s "$ledger" ]
    grep -qx "commit_hash=$hash" "$ledger"
    grep -qx 'rc=1' "$ledger"
    grep -qx 'phase=advance_shared_index' "$ledger"
    grep -qx 'complete=false' "$ledger"
}

@test "存在しないpathはBLOCKする" {
    run bash -c "cd '$REPO' && bash '$HELPER' -m missing -- absent.txt"
    [ "$status" -eq 2 ]
    [[ "$output" == *"scope path does not exist"* ]]
}

@test "GA-222 final edge RC: root scope '.' はBLOCKされindex/working treeが不変のまま" {
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    other_index_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    other_worktree_before="$(cat "$REPO/other.txt")"
    printf 'own change\n' >> "$REPO/own.txt"
    own_worktree_before="$(cat "$REPO/own.txt")"
    head_before="$(git -C "$REPO" rev-parse HEAD)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m root-scope -- ."

    [ "$status" -eq 2 ]
    [[ "$output" == *"repository root"* ]]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$other_index_before" ]
    [ "$(cat "$REPO/other.txt")" = "$other_worktree_before" ]
    [ "$(cat "$REPO/own.txt")" = "$own_worktree_before" ]
    [ "$(git -C "$REPO" status --porcelain -- own.txt)" = " M own.txt" ]
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
}

@test "GA-222 4回目RC: root scope別名'subdir/..'はBLOCKされindex/working treeが不変のまま" {
    mkdir -p "$REPO/subdir"
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    other_index_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    printf 'own change\n' >> "$REPO/own.txt"
    own_worktree_before="$(cat "$REPO/own.txt")"
    head_before="$(git -C "$REPO" rev-parse HEAD)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m subdir-dotdot -- subdir/.."

    [ "$status" -eq 2 ]
    [[ "$output" == *"'..'"* ]]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$other_index_before" ]
    [ "$(cat "$REPO/own.txt")" = "$own_worktree_before" ]
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
}

@test "GA-222 4回目RC: 単独'..'はBLOCKされindex/working treeが不変のまま" {
    printf 'other change\n' >> "$REPO/other.txt"
    git -C "$REPO" add other.txt
    other_index_before="$(git -C "$REPO" ls-files -s -- other.txt)"
    printf 'own change\n' >> "$REPO/own.txt"
    own_worktree_before="$(cat "$REPO/own.txt")"
    head_before="$(git -C "$REPO" rev-parse HEAD)"

    run bash -c "cd '$REPO' && bash '$HELPER' -m bare-dotdot -- .."

    [ "$status" -eq 2 ]
    [[ "$output" == *"'..'"* ]]
    [ "$(git -C "$REPO" ls-files -s -- other.txt)" = "$other_index_before" ]
    [ "$(cat "$REPO/own.txt")" = "$own_worktree_before" ]
    [ "$(git -C "$REPO" rev-parse HEAD)" = "$head_before" ]
}

@test "pre-commit hookを実行する" {
    mkdir -p "$REPO/.git/hooks"
    printf '#!/usr/bin/env bash\nprintf hook-ran > .git/hook-marker\n' > "$REPO/.git/hooks/pre-commit"
    chmod +x "$REPO/.git/hooks/pre-commit"
    printf 'own change\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m hooked -- own.txt"
    [ "$status" -eq 0 ]
    [ "$(cat "$REPO/.git/hook-marker")" = hook-ran ]
}

@test "lefthook configured command bypasses unbounded wrapper status scan" {
    mkdir -p "$REPO/.git/hooks" "$REPO/scripts"
    printf '#!/bin/sh\nexit 99\n' > "$REPO/.git/hooks/pre-commit"
    chmod +x "$REPO/.git/hooks/pre-commit"
    printf 'pre-commit:\n  commands:\n    repo-checks:\n      run: bash scripts/run_precommit_checks.sh\n' > "$REPO/lefthook.yml"
    printf '#!/bin/sh\nprintf direct > .git/direct-hook-marker\n' > "$REPO/scripts/run_precommit_checks.sh"
    chmod +x "$REPO/scripts/run_precommit_checks.sh"
    printf 'own change\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m direct-hook -- own.txt"
    [ "$status" -eq 0 ]
    [ "$(cat "$REPO/.git/direct-hook-marker")" = direct ]
}

@test "GA-222: 正本が無いrepoではsync_git_hooks呼び出しが無害にno-opする" {
    printf 'own change\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m no-sync-source -- own.txt"
    [ "$status" -eq 0 ]
}

@test "GA-222: commit前にstale/未配備の.git/hooks/pre-commitを正本と同期する" {
    SYNC_SCRIPT="$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh"
    mkdir -p "$REPO/scripts" "$REPO/scripts/hooks" "$REPO/.git/hooks"
    cp "$SYNC_SCRIPT" "$REPO/scripts/sync_git_hooks.sh"
    chmod +x "$REPO/scripts/sync_git_hooks.sh"

    printf '#!/usr/bin/env bash\nprintf hook-ran-fixed > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    chmod +x "$REPO/scripts/hooks/git-pre-commit.sh"
    printf '#!/usr/bin/env bash\nprintf hook-ran-stale > .git/hook-marker\n' \
        > "$REPO/.git/hooks/pre-commit"
    chmod +x "$REPO/.git/hooks/pre-commit"
    (
        cd "$REPO"
        git add scripts/sync_git_hooks.sh scripts/hooks/git-pre-commit.sh
        git commit -qm "add tracked hook source + sync helper"
    )

    printf 'own change\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m sync-then-commit -- own.txt"
    [ "$status" -eq 0 ]
    cmp -s "$REPO/scripts/hooks/git-pre-commit.sh" "$REPO/.git/hooks/pre-commit"
    [ "$(cat "$REPO/.git/hook-marker")" = hook-ran-fixed ]
}

@test "GA-222 REQUEST_CHANGES: another agent's uncommitted hook-source edit does not leak in via an unrelated ninja commit" {
    mkdir -p "$REPO/scripts/hooks"
    cp "$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh" "$REPO/scripts/sync_git_hooks.sh"
    chmod +x "$REPO/scripts/sync_git_hooks.sh"
    printf '#!/usr/bin/env bash\nprintf hook-ran-committed > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    chmod +x "$REPO/scripts/hooks/git-pre-commit.sh"
    (
        cd "$REPO"
        git add scripts/sync_git_hooks.sh scripts/hooks/git-pre-commit.sh
        git commit -qm "add tracked hook source + sync helper"
    )

    # Another agent is mid-edit: unstaged, uncommitted change to the hook
    # source, unrelated to this ninja's own.txt-only commit scope.
    printf '#!/usr/bin/env bash\nprintf OTHER_AGENT_WIP > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    printf 'own change\n' >> "$REPO/own.txt"

    run bash -c "cd '$REPO' && bash '$HELPER' -m unrelated-commit -- own.txt"
    [ "$status" -eq 0 ]
    run cat "$REPO/.git/hooks/pre-commit"
    [[ "$output" == *"hook-ran-committed"* ]]
    [[ "$output" != *"OTHER_AGENT_WIP"* ]]
}

@test "GA-222 REQUEST_CHANGES: committing the hook source itself installs the newly staged content" {
    mkdir -p "$REPO/scripts/hooks"
    cp "$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh" "$REPO/scripts/sync_git_hooks.sh"
    chmod +x "$REPO/scripts/sync_git_hooks.sh"
    printf '#!/usr/bin/env bash\nprintf OLD_VERSION > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    chmod +x "$REPO/scripts/hooks/git-pre-commit.sh"
    (
        cd "$REPO"
        git add scripts/sync_git_hooks.sh scripts/hooks/git-pre-commit.sh
        git commit -qm "add tracked hook source + sync helper"
    )

    # This ninja's own commit scope IS the hook source itself.
    printf '#!/usr/bin/env bash\nprintf NEW_VERSION > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"

    run bash -c "cd '$REPO' && bash '$HELPER' -m update-hook-source -- scripts/hooks/git-pre-commit.sh"
    [ "$status" -eq 0 ]
    run cat "$REPO/.git/hooks/pre-commit"
    [[ "$output" == *"NEW_VERSION"* ]]
}

@test "GA-222 followup: committing a directory scope that contains the hook source installs the newly staged content" {
    mkdir -p "$REPO/scripts/hooks"
    cp "$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh" "$REPO/scripts/sync_git_hooks.sh"
    chmod +x "$REPO/scripts/sync_git_hooks.sh"
    printf '#!/usr/bin/env bash\nprintf OLD_VERSION > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    chmod +x "$REPO/scripts/hooks/git-pre-commit.sh"
    (
        cd "$REPO"
        git add scripts/sync_git_hooks.sh scripts/hooks/git-pre-commit.sh
        git commit -qm "add tracked hook source + sync helper"
    )

    # This ninja commits the whole scripts/hooks directory (not the exact
    # file path). git add stages git-pre-commit.sh recursively, and the
    # committed tree includes the new content — the live hook must match
    # that same new content immediately after commit, not the stale HEAD
    # value from before this commit (which would otherwise cause an
    # immediate re-drift right after the commit completes).
    printf '#!/usr/bin/env bash\nprintf NEW_VERSION_VIA_DIR_SCOPE > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"

    run bash -c "cd '$REPO' && bash '$HELPER' -m update-hook-source-dir-scope -- scripts/hooks"
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO" show HEAD:scripts/hooks/git-pre-commit.sh)" = "$(cat "$REPO/scripts/hooks/git-pre-commit.sh")" ]
    run cat "$REPO/.git/hooks/pre-commit"
    [[ "$output" == *"NEW_VERSION_VIA_DIR_SCOPE"* ]]
}

@test "GA-222 final edge RC: 'scripts/hooks/.' (trailing /.) scope path installs the newly staged content" {
    mkdir -p "$REPO/scripts/hooks"
    cp "$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh" "$REPO/scripts/sync_git_hooks.sh"
    chmod +x "$REPO/scripts/sync_git_hooks.sh"
    printf '#!/usr/bin/env bash\nprintf OLD_VERSION > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    chmod +x "$REPO/scripts/hooks/git-pre-commit.sh"
    (
        cd "$REPO"
        git add scripts/sync_git_hooks.sh scripts/hooks/git-pre-commit.sh
        git commit -qm "add tracked hook source + sync helper"
    )

    # "scripts/hooks/." is pathspec-equivalent to "scripts/hooks" for git add,
    # but is a distinct string — is_in_scope must normalize before comparing.
    printf '#!/usr/bin/env bash\nprintf NEW_VERSION_VIA_TRAILING_DOT > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"

    run bash -c "cd '$REPO' && bash '$HELPER' -m update-hook-source-trailing-dot -- scripts/hooks/."
    [ "$status" -eq 0 ]
    run cat "$REPO/.git/hooks/pre-commit"
    [[ "$output" == *"NEW_VERSION_VIA_TRAILING_DOT"* ]]
}

@test "GA-222 4回目RC: 'scripts//hooks' (double slash) scope path installs the newly staged content" {
    mkdir -p "$REPO/scripts/hooks"
    cp "$BATS_TEST_DIRNAME/../../scripts/sync_git_hooks.sh" "$REPO/scripts/sync_git_hooks.sh"
    chmod +x "$REPO/scripts/sync_git_hooks.sh"
    printf '#!/usr/bin/env bash\nprintf OLD_VERSION > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"
    chmod +x "$REPO/scripts/hooks/git-pre-commit.sh"
    (
        cd "$REPO"
        git add scripts/sync_git_hooks.sh scripts/hooks/git-pre-commit.sh
        git commit -qm "add tracked hook source + sync helper"
    )

    # "scripts//hooks" is pathspec-equivalent to "scripts/hooks" for git add.
    printf '#!/usr/bin/env bash\nprintf NEW_VERSION_VIA_DOUBLE_SLASH > .git/hook-marker\n' \
        > "$REPO/scripts/hooks/git-pre-commit.sh"

    run bash -c "cd '$REPO' && bash '$HELPER' -m update-hook-source-double-slash -- scripts//hooks"
    [ "$status" -eq 0 ]
    run cat "$REPO/.git/hooks/pre-commit"
    [[ "$output" == *"NEW_VERSION_VIA_DOUBLE_SLASH"* ]]
}
# test_necessity: a slow pre-commit must not serialize an independent scoped
# commit, and the slow caller must publish on the latest single-parent HEAD.
@test "slow pre-commit releases repository scope lock and rebases onto concurrent HEAD" {
    repo="$BATS_TEST_TMPDIR/concurrent-precommit"
    git init -q "$repo"
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name test
    printf 'base-a\n' > "$repo/a.txt"
    printf 'base-b\n' > "$repo/b.txt"
    git -C "$repo" add a.txt b.txt
    git -C "$repo" commit -qm base
    base_head="$(git -C "$repo" rev-parse HEAD)"

    mkdir -p "$repo/.git/hooks"
    cat > "$repo/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
if git diff --cached --name-only | grep -qx a.txt; then
    sleep 5
fi
HOOK
    chmod +x "$repo/.git/hooks/pre-commit"
    printf 'change-a\n' > "$repo/a.txt"

    (
        cd "$repo"
        exec env NINJA_SCOPE_COMMIT_RUN_ID=slow-a \
            bash "$HELPER" -m slow-a -- a.txt
    ) >"$BATS_TEST_TMPDIR/a.out" 2>"$BATS_TEST_TMPDIR/a.err" &
    slow_pid=$!
    # The full CI lane can spend several seconds scheduling the helper before
    # it reaches pre-commit.  Keep this observation deadline distinct from the
    # hook's intentional five-second sleep; otherwise scheduler delay alone
    # makes the evidence check race the hook duration.
    for _ in $(seq 1 300); do
        grep -q 'phase=pre_commit' "$BATS_TEST_TMPDIR/a.err" 2>/dev/null && break
        ps -p "$slow_pid" >/dev/null 2>&1 || break
        sleep 0.05
    done
    grep -q 'phase=pre_commit' "$BATS_TEST_TMPDIR/a.err" || {
        printf 'reason_code=pre_commit_phase_not_observed helper_rc=' >&3
        if ps -p "$slow_pid" >/dev/null 2>&1; then
            printf 'running\n' >&3
        else
            wait "$slow_pid"
            printf '%s\n' "$?" >&3
        fi
        cat "$BATS_TEST_TMPDIR/a.err" >&3
        false
    }
    sleep 0.2

    printf 'change-b\n' > "$repo/b.txt"
    # commit_queue.sh's Phase2 reservation ledger (248ea8d5b) intentionally
    # serializes every ninja_scope_commit.sh invocation against one repo-wide
    # lane (see tests/unit/test_commit_queue.bats "FIFO wait_turn ... preserve
    # reservation order"), so this disjoint-scope helper now legitimately
    # queues behind slow-a's in-flight hook instead of racing it. What this
    # test still proves is the original GA correctness invariant: once b.txt's
    # helper gets its turn, it rebases onto whatever HEAD slow-a already
    # published rather than a stale one.
    run bash -c "cd '$repo' && NINJA_SCOPE_COMMIT_RUN_ID=fast-b bash '$HELPER' -m fast-b -- b.txt"
    [ "$status" -eq 0 ]

    wait "$slow_pid" || {
        cat "$BATS_TEST_TMPDIR/a.err" >&3
        false
    }
    [ "$(git -C "$repo" rev-list --count "$base_head..HEAD")" -eq 2 ]
    [ "$(git -C "$repo" show -s --format=%P HEAD | wc -w)" -eq 1 ]
    [ "$(git -C "$repo" show -s --format=%P HEAD)" = "$(git -C "$repo" rev-parse HEAD^)" ]
    [ "$(git -C "$repo" show HEAD:a.txt)" = change-a ]
    [ "$(git -C "$repo" show HEAD:b.txt)" = change-b ]
    [ -z "$(git -C "$repo" status --porcelain)" ]
}

# test_necessity: two helpers that snapshot the same owned change may publish
# exactly one material commit; the follower must return success without an
# empty commit while preserving unrelated dirty worktree bytes.
@test "same owned change raced by two helpers produces one material commit and zero empty commits" {
    repo="$BATS_TEST_TMPDIR/same-change-race"
    git init -q "$repo"
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name test
    printf 'base-owned\n' > "$repo/owned.txt"
    printf 'base-foreign\n' > "$repo/foreign.txt"
    git -C "$repo" add owned.txt foreign.txt
    git -C "$repo" commit -qm base
    base_head="$(git -C "$repo" rev-parse HEAD)"

    mkdir -p "$repo/.git/hooks"
    cat > "$repo/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
printf 'run\n' >> .git/pre-commit-runs
sleep 1
HOOK
    cat > "$repo/.git/hooks/post-commit" <<'HOOK'
#!/usr/bin/env bash
sentinel=.git/scoped-publish-active
if ! mkdir "$sentinel" 2>/dev/null; then
    printf 'overlap\n' >> .git/scoped-publish-overlap
    exit 1
fi
sleep 0.2
rmdir "$sentinel"
HOOK
    chmod +x "$repo/.git/hooks/pre-commit" "$repo/.git/hooks/post-commit"
    printf 'changed-owned\n' > "$repo/owned.txt"
    printf 'changed-foreign\n' > "$repo/foreign.txt"

    (
        cd "$repo"
        NINJA_SCOPE_COMMIT_RUN_ID=same-change-a bash "$HELPER" -m same-change-a -- owned.txt
    ) >"$BATS_TEST_TMPDIR/same-a.out" 2>"$BATS_TEST_TMPDIR/same-a.err" &
    pid_a=$!
    (
        cd "$repo"
        NINJA_SCOPE_COMMIT_RUN_ID=same-change-b bash "$HELPER" -m same-change-b -- owned.txt
    ) >"$BATS_TEST_TMPDIR/same-b.out" 2>"$BATS_TEST_TMPDIR/same-b.err" &
    pid_b=$!
    status_a=0
    status_b=0
    wait "$pid_a" || status_a=$?
    wait "$pid_b" || status_b=$?
    if [ "$status_a" -ne 0 ] || [ "$status_b" -ne 0 ]; then
        printf 'reason_code=same_owned_helper_failed rc_a=%s rc_b=%s\n' \
            "$status_a" "$status_b" >&3
        sed 's/^/helper_a: /' "$BATS_TEST_TMPDIR/same-a.err" >&3
        sed 's/^/helper_b: /' "$BATS_TEST_TMPDIR/same-b.err" >&3
    fi

    [ "$status_a" -eq 0 ]
    [ "$status_b" -eq 0 ]
    [ "$(wc -l < "$repo/.git/pre-commit-runs")" -eq 1 ]
    [ "$(git -C "$repo" rev-list --count "$base_head..HEAD")" -eq 1 ]
    [ -n "$(git -C "$repo" diff-tree --no-commit-id --name-only -r HEAD)" ]
    [ "$(git -C "$repo" log --format= --name-only "$base_head..HEAD" | sed '/^$/d' | sort -u)" = owned.txt ]
    [ "$(git -C "$repo" show HEAD:owned.txt)" = changed-owned ]
    [ "$(cat "$repo/foreign.txt")" = changed-foreign ]
    [ -n "$(git -C "$repo" status --porcelain -- foreign.txt)" ]
    [ ! -e "$repo/.git/scoped-publish-overlap" ]
}

# test_necessity: a foreign blob present in the final private candidate tree
# must be rejected before commit-tree/update-ref; this is the 980b4110 safety
# invariant and cannot be proved by the existing post-publication assertion.
# test_necessity: -h/--help must print usage on stdout with rc=0; misuse (unknown
# option / no message) must keep BLOCK on stderr with rc=2. Help is not a BLOCK.
# regression_justification: 2026-09-01 Karo ran `--help` three times and got
# "BLOCK: unknown argument" rc=2 each time (lord audit 13:22; karo review 14:12
# REJECT because usage went to stderr).
@test "help flags print usage on stdout and exit 0" {
    run bash -c 'bash "$1" --help 2>/dev/null' _ "$HELPER"
    [ "$status" -eq 0 ]
    [[ "$output" == Usage:* ]]
    run bash -c 'bash "$1" -h 2>&1 >/dev/null' _ "$HELPER"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "unknown option is a BLOCK on stderr with rc=2 and nothing on stdout" {
    run bash -c 'bash "$1" --bogus 2>/dev/null' _ "$HELPER"
    [ "$status" -eq 2 ]
    [ -z "$output" ]
    run bash -c 'bash "$1" --bogus 2>&1 >/dev/null' _ "$HELPER"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK: unknown argument: --bogus"* ]]
}

@test "no arguments is a BLOCK with rc=2" {
    run bash -c 'cd "$2" && bash "$1"' _ "$HELPER" "$REPO"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK:"* ]]
}

@test "final private tree scope detector blocks foreign blob before HEAD publication" {
    repo="$BATS_TEST_TMPDIR/prepublish-scope-detector"
    git init -q "$repo"
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name test
    printf 'base-owned\n' > "$repo/owned.txt"
    printf 'base-foreign\n' > "$repo/foreign.txt"
    git -C "$repo" add owned.txt foreign.txt
    git -C "$repo" commit -qm base
    before="$(git -C "$repo" rev-parse HEAD)"
    printf 'changed-owned\n' > "$repo/owned.txt"
    printf 'changed-foreign\n' > "$repo/foreign.txt"

    run bash -c 'cd "$1" && NINJA_SCOPE_COMMIT_TEST_INJECT_FOREIGN_PATH=foreign.txt bash "$2" -m detector -- owned.txt' _ "$repo" "$HELPER"

    [ "$status" -eq 2 ]
    [[ "$output" == *"out-of-scope path entered private commit tree before publish: foreign.txt"* ]]
    [ "$(git -C "$repo" rev-parse HEAD)" = "$before" ]
    [ "$(git -C "$repo" rev-list --count --all)" -eq 1 ]
    [ -n "$(git -C "$repo" status --porcelain -- owned.txt foreign.txt)" ]
}
