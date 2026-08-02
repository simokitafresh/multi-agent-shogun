#!/usr/bin/env bats
# test_necessity: post-bash-commit-reminder.shは、gate_report_format.shが正式に
# 許可しているcommit_hash="no-code-change"(no_code_change_evidence+explicit_no_commit+
# operational_files_onlyの構造契約済み)の報告に対してCOMMIT MISSING警告を誤発火しては
# ならない(cmd_karo_hotfix_no_code_commit_reminder_20260728)。同時に、通常の
# commit_hash欠落/不正な報告に対する警告は維持しなければならない。

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  FIX="$BATS_TEST_TMPDIR/fixture"
  mkdir -p "$FIX/.claude/hooks" "$FIX/scripts/lib" "$FIX/queue/tasks" \
    "$FIX/config" "$FIX/logs" "$FIX/out_reports"
  cp "$ROOT/.claude/hooks/post-bash-commit-reminder.sh" "$FIX/.claude/hooks/"
  cp "$ROOT/scripts/lib/report_commit_identity.py" "$FIX/scripts/lib/"

  cat > "$FIX/config/projects.yaml" <<YAML
projects:
  - id: fixture
    path: $FIX
YAML

  git -C "$FIX" init -q
  git -C "$FIX" config user.email fixture@example.invalid
  git -C "$FIX" config user.name fixture
  echo dummy > "$FIX/logs/existing.log"
  git -C "$FIX" add -A
  tree1=$(git -C "$FIX" write-tree)
  c1=$(git -C "$FIX" commit-tree "$tree1" -m init)
  git -C "$FIX" update-ref refs/heads/main "$c1"
  git -C "$FIX" symbolic-ref HEAD refs/heads/main
  BEFORE_TREE=$(git -C "$FIX" rev-parse HEAD^{tree})
  HEAD_COMMIT=$(git -C "$FIX" rev-parse HEAD)
}

write_task() {
  local ninja="$1" report_rel="$2"
  cat > "$FIX/queue/tasks/${ninja}.yaml" <<YAML
task:
  project: fixture
  target_path: logs/existing.log
  report_path: ${report_rel}
YAML
}

run_hook() {
  local ninja="$1"
  local payload
  payload=$(python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','tool_input':{'command':'bash scripts/inbox_write.sh karo \"x\" report_received '+sys.argv[1]}}))" "$ninja")
  HOOK_PAYLOAD="$payload" run bash "$FIX/.claude/hooks/post-bash-commit-reminder.sh"
}

@test "AC1(再現): legit no-code report triggers a false-positive COMMIT MISSING warning before the fix" {
  # このテストは修正前ロジックのみを検査する固定コピーで再現を保存する。
  # 修正後は同じ入力に対しAC2のテストが「警告なし」を要求する。
  write_task testninjaA out_reports/testninjaA.yaml
  cat > "$FIX/out_reports/testninjaA.yaml" <<YAML
commit_hash: no-code-change
files_modified:
  - path: logs/existing.log
    change: "read-only, no change"
no_code_change_evidence:
  tree_unchanged: true
  before_tree: "$BEFORE_TREE"
  after_tree: "$BEFORE_TREE"
binary_checks:
  commit:
    - check: "commit不要(read-only分析)"
      result: "yes"
YAML
  # 修正前ロジック(40hex限定判定)を直接再現: commit_hashの長さ/16進のみで判定
  run python3 - "$FIX" <<'PY'
import sys, yaml, os
fix = sys.argv[1]
report = yaml.safe_load(open(os.path.join(fix, "out_reports", "testninjaA.yaml")))
commit_hash = str(report.get("commit_hash") or "").strip()
is_warn = len(commit_hash) != 40 or any(c not in "0123456789abcdefABCDEF" for c in commit_hash)
print("WARN" if is_warn else "NO_WARN")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN"* ]]
}

@test "AC2(修正後・正規経路): legit no-code report produces no warning via the real hook" {
  write_task testninjaA out_reports/testninjaA.yaml
  cat > "$FIX/out_reports/testninjaA.yaml" <<YAML
commit_hash: no-code-change
files_modified:
  - path: logs/existing.log
    change: "read-only, no change"
no_code_change_evidence:
  tree_unchanged: true
  before_tree: "$BEFORE_TREE"
  after_tree: "$BEFORE_TREE"
binary_checks:
  commit:
    - check: "commit不要(read-only分析)"
      result: "yes"
YAML
  run_hook testninjaA
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "AC2(regression維持): normal report with missing/empty commit_hash still warns" {
  write_task testninjaB out_reports/testninjaB.yaml
  cat > "$FIX/out_reports/testninjaB.yaml" <<YAML
commit_hash: ""
files_modified:
  - path: logs/existing.log
    change: "modified"
YAML
  run_hook testninjaB
  [ "$status" -eq 0 ]
  [[ "$output" == *"COMMIT MISSING"* ]]
  [[ "$output" == *"report_commit_hash_missing_or_invalid"* ]]
}

@test "AC2(regression維持): normal report with a valid matching 40-hex commit stays silent" {
  write_task testninjaC out_reports/testninjaC.yaml
  cat > "$FIX/out_reports/testninjaC.yaml" <<YAML
commit_hash: "$HEAD_COMMIT"
files_modified:
  - path: logs/existing.log
    change: "committed"
YAML
  run_hook testninjaC
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "AC2(fail-closed維持): no-code sentinel without structural evidence still warns" {
  write_task testninjaD out_reports/testninjaD.yaml
  cat > "$FIX/out_reports/testninjaD.yaml" <<YAML
commit_hash: no-code-change
files_modified:
  - path: logs/existing.log
    change: "claims no-code but has no evidence"
YAML
  run_hook testninjaD
  [ "$status" -eq 0 ]
  [[ "$output" == *"COMMIT MISSING"* ]]
  [[ "$output" == *"report_commit_hash_missing_or_invalid"* ]]
}

@test "AC2(fail-closed維持): no-code sentinel outside queue/logs scope still warns" {
  write_task testninjaE out_reports/testninjaE.yaml
  cat > "$FIX/out_reports/testninjaE.yaml" <<YAML
commit_hash: no-code-change
files_modified:
  - path: scripts/lib/report_commit_identity.py
    change: "claims no-code but path is source code"
no_code_change_evidence:
  tree_unchanged: true
  before_tree: "$BEFORE_TREE"
  after_tree: "$BEFORE_TREE"
binary_checks:
  commit:
    - check: "commit不要"
      result: "yes"
YAML
  run_hook testninjaE
  [ "$status" -eq 0 ]
  [[ "$output" == *"COMMIT MISSING"* ]]
}

# test_necessity: planned scope全件ではなくreport-owned pathだけを照合し、同じ共有fileの
# 後着非重複appendは許可する一方、commit/report片側欠落はBLOCKする。
@test "shared owned hunk ignores later append but blocks planned-report asymmetry" {
  cat > "$FIX/context_shared.md" <<'EOF'
base
EOF
  git -C "$FIX" add context_shared.md
  git -C "$FIX" commit -q -m shared-base
  printf 'owned\n' >> "$FIX/context_shared.md"
  git -C "$FIX" add context_shared.md
  git -C "$FIX" commit -q -m 'cmd_shared owned-change'
  local first_owned_commit
  first_owned_commit=$(git -C "$FIX" rev-parse HEAD)
  printf 'second\n' > "$FIX/context_second.md"
  git -C "$FIX" add context_second.md
  git -C "$FIX" commit -q -m 'cmd_shared final-change'
  local owned_commit
  owned_commit=$(git -C "$FIX" rev-parse HEAD)
  printf 'later append\n' >> "$FIX/context_shared.md"
  git -C "$FIX" add context_shared.md
  git -C "$FIX" commit -q -m later-append

  cat > "$FIX/queue/tasks/sharedninja.yaml" <<YAML
task:
  project: fixture
  task_id: cmd_shared
  planned_paths: [context_shared.md, context_second.md, absent.md]
  report_path: out_reports/sharedninja.yaml
YAML
  cat > "$FIX/out_reports/sharedninja.yaml" <<YAML
commit_hash: $owned_commit
result: {details: "first owned commit $first_owned_commit"}
files_modified: [{path: context_shared.md, change: owned append}, {path: context_second.md, change: owned file}]
YAML
  run_hook sharedninja
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  printf 'files_modified: []\ncommit_hash: %s\ntask_id: cmd_shared\nresult: {details: "first owned commit %s"}\n' "$owned_commit" "$first_owned_commit" > "$FIX/out_reports/sharedninja.yaml"
  run_hook sharedninja
  [ -z "$output" ]

  printf 'files_modified: [{path: context_second.md, change: owned file}]\ncommit_hash: %s\ntask_id: cmd_shared\nresult: {details: "first owned commit %s"}\n' "$owned_commit" "$first_owned_commit" > "$FIX/out_reports/sharedninja.yaml"
  run_hook sharedninja
  [[ "$output" == *"planned_report_scope_asymmetric"* ]]
}
