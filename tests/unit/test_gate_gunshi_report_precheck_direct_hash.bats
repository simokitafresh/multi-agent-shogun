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

@test "fixed-hash branch uses one numstat tree walk and derives paths" {
  run awk '/# PRE3\/PRE14: report/{on=1} on{print} /done <<< "\$_REPORT_HASHES"/{exit}' "$TARGET"
  [ "$status" -eq 0 ]
  [[ "$output" == *'cat-file -e'* ]]
  [[ "$output" == *'diff-tree --no-commit-id --numstat'* ]]
  [[ "$output" == *"_hash_files=\$(printf '%s\\n' \"\$_hash_numstat\" | awk -F'\\t' 'NF>=3{print \$3}')"* ]]
  ! printf '%s\n' "$output" | grep -E '^[[:space:]]*[^#].*diff-tree --no-commit-id --name-only'
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

# cmd_karo_hotfix_round2_full_precheck_20260728: D002(project外パスへのrm -rf絶対禁則)
# 違反を家老RCで指摘され是正。SG-PRE21のcausal_backlinks並列化用tmpdir(/tmp配下)の
# 後始末は再帰削除を使わず、既知の個別ファイルのみrm -fしてからrmdir(非再帰)で
# 閉じる。この不変量を静的に固定し、将来の再発を防ぐ。

@test "precheck tmpdir cleanup never uses executable rm -rf (D002)" {
  run cat "$TARGET"
  [ "$status" -eq 0 ]
  # コメント行(# ...)自身がrm -rfという文字列を教訓として引用しているため、
  # コード行(先頭が#でない行)だけを対象にtarget全体で不在を確認する。
  ! printf '%s\n' "$output" | grep -E '^[[:space:]]*[^#[:space:]].*rm[[:space:]]+-rf'
}

@test "SG-PRE21 causal_backlinks tmpdir cleanup uses non-recursive rm -f + rmdir" {
  run grep -F 'rmdir "$_causal_tmpdir" 2>/dev/null || true' "$TARGET"
  [ "$status" -eq 0 ]
  run grep -F 'rm -f "$_causal_tmpdir/${_causal_cleanup_i}.rc" "$_causal_tmpdir/${_causal_cleanup_i}.out"' "$TARGET"
  [ "$status" -eq 0 ]
}

@test "SG-PRE21 causal_backlinks tmpdir leaves no residue after a normal run" {
  # Isolate residue counting from concurrent prechecks that share /tmp (flaky 2026-09-03 GA-561).
  export TMPDIR="$BATS_TEST_TMPDIR"
  before_count=$(find "$TMPDIR" -maxdepth 1 -name 'gunshi_pre21_*' 2>/dev/null | wc -l)
  fixture_report="$BATS_TEST_TMPDIR/fixture_report.yaml"
  cat > "$fixture_report" <<EOF
worker_id: test
task_id: subtask_test
parent_cmd: cmd_test_d002_fixture
timestamp: "2026-03-10T00:00:00"
status: done
verdict: PASS
result:
  summary: "D002 residue fixture"
files_modified:
  - path: "CLAUDE.md"
    change: "fixture only, not a real change"
  - path: "AGENTS.md"
    change: "fixture only, not a real change"
EOF
  run bash "$TARGET" "$fixture_report"
  after_count=$(find "$TMPDIR" -maxdepth 1 -name 'gunshi_pre21_*' 2>/dev/null | wc -l)
  [ "$after_count" -eq "$before_count" ]
}
