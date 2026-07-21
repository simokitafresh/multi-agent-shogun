#!/usr/bin/env bats

# test_necessity: report commit_hashがある通常経路で全履歴walkを再発させない不変量を守る。

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TARGET="$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh"
}

@test "gate remains syntactically valid" {
  run bash -n "$TARGET"
  [ "$status" -eq 0 ]
}

@test "fixed-hash branch uses direct object and tree operations" {
  run awk '/# PRE3\/PRE14: report/{on=1} on{print} /done <<< "\$_REPORT_HASHES"/{exit}' "$TARGET"
  [ "$status" -eq 0 ]
  [[ "$output" == *'cat-file -e'* ]]
  [[ "$output" == *'diff-tree --no-commit-id --name-only'* ]]
  [[ "$output" == *'diff-tree --no-commit-id --numstat'* ]]
  ! printf '%s\n' "$output" | grep -E '^[[:space:]]*[^#].*git log'
  ! printf '%s\n' "$output" | grep -E '^[[:space:]]*[^#].*rev-list'
}

@test "repo-wide history fallback is skipped when report hash exists" {
  run grep -F 'if [ -n "${FILES_MODIFIED:-}" ] && [ -z "$_REPORT_HASHES" ]; then' "$TARGET"
  [ "$status" -eq 0 ]
}

@test "missing-hash fallback is bounded" {
  run grep -E 'git (log -20|-C "\$REPO_ROOT" log -20)' "$TARGET"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "generated propagation and PRE4 avoid history walks" {
  run grep -E 'rev-list|LATEST_COMMIT=.*git log' "$TARGET"
  [ "$status" -ne 0 ]
}
