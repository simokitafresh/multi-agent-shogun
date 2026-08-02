#!/usr/bin/env bats
# test_necessity: pre-commit may suppress affected-test and shell-syntax processes only for an exact PASS receipt identity; every stale/failing/missing identity must execute the guards.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "receipt reuse contract binds task head selection staged tree and shell blobs" {
  hook="$REPO_ROOT/scripts/hooks/git-pre-commit.sh"
  run rg -n 'precommit_receipt_matches|selected_tests_sha256|staged_tree|staged_shell_blobs|test process launches=0|bash processes=0' "$hook"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | rg -c 'precommit_receipt_matches|selected_tests_sha256|staged_tree|staged_shell_blobs|test process launches=0|bash processes=0')" -ge 6 ]
}

@test "receipt validator requires PASS rc0 skip0 and exact source head" {
  hook="$REPO_ROOT/scripts/hooks/git-pre-commit.sh"
  run rg -n 'complete.*True|result.*PASS|rc.*0|skip_count.*0|source_head.*head' "$hook"
  [ "$status" -eq 0 ]
}

@test "ninja commit status probes disable optional locks" {
  skill="$REPO_ROOT/skills/ninja-commit/SKILL.md"
  run rg -n 'git --no-optional-locks status --short' "$skill"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 2 ]
}

@test "seven identity fixtures have false reuse zero" {
  work="$BATS_TEST_TMPDIR/receipt"
  mkdir -p "$work"
  cat >"$work/task.yaml" <<'YAML'
task:
  task_id: task-1
YAML
  function_body="$(awk '/^precommit_receipt_matches\(\)/{p=1} p{print} p && /^}/{exit}' "$REPO_ROOT/scripts/hooks/git-pre-commit.sh")"
  run env FUNCTION_BODY="$function_body" WORK="$work" bash -c '
    eval "$FUNCTION_BODY"
    precommit_staged_tree_hash(){ printf tree-1; }
    precommit_staged_blob_hashes(){ printf "a.sh=blob-1"; }
    git(){ [[ "$1 $2" == "rev-parse HEAD" ]] && printf head-1; }
    selected=$(printf "t.bats\n" | sha256sum | awk "{print \$1}")
    write_receipt(){ cat >"$WORK/r.yaml" <<EOF
complete: $1
result: $2
rc: $3
skip_count: $4
source_head: $5
test_paths: [$6]
precommit_identity:
  task_id: $7
  source_head: $8
  selected_tests_sha256: $9
  staged_tree: ${10}
  staged_shell_blobs: ${11}
EOF
    }
    _PRECOMMIT_TEST_RECEIPT="$WORK/r.yaml"
    pass=0; reject=0
    write_receipt true PASS 0 0 head-1 t.bats task-1 head-1 "$selected" tree-1 a.sh=blob-1
    precommit_receipt_matches "$WORK/task.yaml" && pass=$((pass+1))
    for fixture in head selection blob fail skip missing; do
      case "$fixture" in
        head) write_receipt true PASS 0 0 other t.bats task-1 other "$selected" tree-1 a.sh=blob-1 ;;
        selection) write_receipt true PASS 0 0 head-1 other.bats task-1 head-1 "$selected" tree-1 a.sh=blob-1 ;;
        blob) write_receipt true PASS 0 0 head-1 t.bats task-1 head-1 "$selected" tree-1 a.sh=other ;;
        fail) write_receipt true FAIL 1 0 head-1 t.bats task-1 head-1 "$selected" tree-1 a.sh=blob-1 ;;
        skip) write_receipt true PASS 0 1 head-1 t.bats task-1 head-1 "$selected" tree-1 a.sh=blob-1 ;;
        missing) : >"$WORK/r.yaml" ;;
      esac
      precommit_receipt_matches "$WORK/task.yaml" || reject=$((reject+1))
    done
    printf "reuse=%s reject=%s false_reuse=%s\n" "$pass" "$reject" "$((6-reject))"
    [[ "$pass" -eq 1 && "$reject" -eq 6 ]]
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"reuse=1 reject=6 false_reuse=0"* ]]
}
