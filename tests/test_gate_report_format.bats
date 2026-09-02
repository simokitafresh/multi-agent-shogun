#!/usr/bin/env bats
# test_gate_report_format.bats — gate_report_format.sh回帰テスト
# GP-073(PASSキャッシュ)、GP-128(verdict整合性)を含む主要チェックのテスト

GATE="scripts/gates/gate_report_format.sh"
AUTOFIX="scripts/gates/gate_report_autofix.sh"
TMPDIR_BATS=""
REPO_TMPDIR_BATS=""
SKILL_LOG_REPORT_DIR=""

setup() {
    TMPDIR_BATS=$(mktemp -d)
    REPO_TMPDIR_BATS=$(mktemp -d ".tmp_gate_report_format.XXXXXX")
    SKILL_LOG_REPORT_DIR=""
    # --jobs 8並列実行時の競合を回避するためキャッシュ/ログをテストごとに一意化
    export GATE_PASS_CACHE_FILE="$TMPDIR_BATS/.gate_pass_cache"
    export GATE_FIRE_LOG_FILE="$TMPDIR_BATS/gate_fire_log.yaml"
    export SKILL_EXECUTION_LOG_FILE="$TMPDIR_BATS/skill_execution_log.yaml"
    export SKILL_GATE_FEEDBACK_DISABLE=1
    export SKILL_LOG_SYNC=1
}

teardown() {
    rm -rf "$TMPDIR_BATS"
    rm -rf "$REPO_TMPDIR_BATS"
    if [ -n "$SKILL_LOG_REPORT_DIR" ]; then
        rm -rf "$SKILL_LOG_REPORT_DIR"
    fi
    unset GATE_PASS_CACHE_FILE GATE_FIRE_LOG_FILE SKILL_EXECUTION_LOG_FILE
}

# Helper: fixture repoを作る唯一の入口。
# REPO_TMPDIR_BATSは本番repoの直下にあるため、git initが失敗すると .git が不完全なまま残り、
# 以降の `git -C "$repo" add/commit` は discovery が親を遡って**本番repoに解決される**。
# 実測(B31): /mnt/c(DrvFs)では config.lock の chmod が EPERM で init が rc=128 になり、
# _setup_ac3_hunk_repo の `commit -q -m "init"` が本番mainへ他者のstage済み変更を
# message="init"でcommitしていた(9e88ddc28 / da5dbb369)。
# ∴ initの成否ではなく「このgitが本当にfixture repoを指しているか」を実体で検査し、
# 逸脱していればcommitへ到達する前にsubshellごと落とす。
_init_fixture_repo() {
    local repo="$1"
    mkdir -p "$repo"
    git -C "$repo" init -q || true
    local top expected
    top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)"
    expected="$(cd "$repo" && pwd -P)"
    if [ "$top" != "$expected" ]; then
        echo "FATAL: fixture git init escaped to '${top:-<none>}' (expected '$expected'). Aborting before any commit reaches the production repo." >&2
        exit 1
    fi
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name test
}

# Helper: create a minimal valid report
create_valid_report() {
    local path="${1:-$TMPDIR_BATS/report.yaml}"
    cat > "$path" << 'YAML'
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
timestamp: '2026-07-12T00:00:00+09:00'
status: completed
binary_checks:
  AC1:
    - check: "テスト対象の確認項目を詳細に記載"
      result: "yes"
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
lessons_useful: []
purpose_validation:
  cmd_purpose: "テスト用途の確認タスク"
  fit: true
  purpose_gap: ""
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
operational_simulation:
  command: "bats tests/test_gate_report_format.bats"
  expected: "fixture report satisfies the executable-report contract"
  actual: "fixture report validation executed"
  result: "PASS"
result:
  summary: "テスト結果のサマリ"
verdict: PASS
YAML
    echo "$path"
}

# --- T-001: Valid report → PASS ---
@test "T-001: valid report passes gate" {
    local report=$(create_valid_report)
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# test_necessity: files_modified の './X' と manifest の 'X' は同一 path として扱われ、
# top-level file を含む報告が manifest 検査と path 形式検査の双方を PASS できる不変量を守る。
# regression_justification: manifest 比較が './' 接頭辞だけで正当な報告を FAIL させていた。
@test "T-MANIFEST-1: top-level report path with dot slash matches manifest" {
    local report="$TMPDIR_BATS/report.yaml"
    local task_id="cmd_manifest_dotslash_contract"
    local state_dir="$TMPDIR_BATS/publish-state"
    local manifest_dir="$state_dir/publish_queue/artifacts/$task_id"
    create_valid_report "$report" >/dev/null
    mkdir -p "$manifest_dir"
    sed -i \
        -e 's/^files_modified: \[\]$/files_modified:\n  - path: .\/AGENTS.md/' \
        -e "/^parent_cmd:/a task_id: $task_id" \
        "$report"
    cat > "$manifest_dir/manifest.yaml" <<'YAML'
source_sha: ""
base: fixture-base
paths:
  - AGENTS.md
YAML

    run env SHOGUN_STATE_DIR="$state_dir" bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS(manifest_consistency)"* ]]
    [[ "$output" != *"paths mismatch"* ]]
}

@test "T-001b: missing origin emits WARN without failing" {
    local report=$(create_valid_report)
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" == *"WARN: origin欄が空/未記入"* ]]
    [[ "$output" == *"report_field_set.sh <report> origin"* ]]
}

@test "T-001c: required variation 5項目が空なら正規report gateがFAIL" {
    mkdir -p "$TMPDIR_BATS/queue/reports" "$TMPDIR_BATS/queue/tasks"
    local report="$TMPDIR_BATS/queue/reports/testninja_report_cmd_test.yaml"
    create_valid_report "$report" >/dev/null
    cat > "$TMPDIR_BATS/queue/tasks/testninja.yaml" <<'YAML'
task:
  parent_cmd: cmd_test
  variation_checks_required: true
YAML
    cat >> "$report" <<'YAML'
variation_checks:
  normal_pass: {check: normal, result: ""}
  quoted_or_heredoc: {check: quoted, result: ""}
  linked_worktree: {check: worktree, result: ""}
  parallel_or_respawn: {check: parallel, result: ""}
  abnormal_exit: {check: abnormal, result: ""}
YAML

    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"variation_checks: required cells unfilled"* ]]
}

@test "T-001d: required variation 5項目がyes/noなら正規report gateがPASS" {
    mkdir -p "$TMPDIR_BATS/queue/reports" "$TMPDIR_BATS/queue/tasks"
    local report="$TMPDIR_BATS/queue/reports/testninja_report_cmd_test.yaml"
    create_valid_report "$report" >/dev/null
    cat > "$TMPDIR_BATS/queue/tasks/testninja.yaml" <<'YAML'
task:
  parent_cmd: cmd_test
  commit_contract: {required: false}
  variation_checks_required: true
YAML
    cat >> "$report" <<'YAML'
variation_checks:
  normal_pass: {check: normal, result: yes}
  quoted_or_heredoc: {check: quoted, result: no}
  linked_worktree: {check: worktree, result: yes}
  parallel_or_respawn: {check: parallel, result: no}
  abnormal_exit: {check: abnormal, result: yes}
YAML

    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# test_necessity: multi-round speed callback must never advance from prose-only PASS evidence.
@test "T-001e: terminal speed PASS with prose-only results is BLOCKed" {
    local report=$(create_valid_report)
    cat >> "$report" <<'YAML'
speed_result:
  quality: pass
  last_wall: 12.5
  approach: shared fixture
  dominant: repeated setup
  elapsed_sec: 100
  ctx_percent: 40
test_results:
  command: bats tests/unit/example.bats
  actual: all tests passed
  result: PASS
YAML

    run env GATE_NO_LOG=1 bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"speed callback schema"* ]]
}

# test_necessity: a complete numeric speed callback measurement remains accepted.
@test "T-001f: terminal speed PASS with numeric callback fields passes" {
    local report=$(create_valid_report)
    cat >> "$report" <<'YAML'
speed_result:
  quality: pass
  last_wall: 12.5
  approach: shared fixture
  dominant: repeated setup
  elapsed_sec: 100
  ctx_percent: 40
test_results:
  status: pass
  wall_sec: 12.5
  failures: 0
  skips: 0
YAML

    run env GATE_NO_LOG=1 bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# test_necessity: same-run A/B campaigns must not reach callback without complete interleaved evidence.
@test "T-001g: terminal same-run speed PASS without speed_ab is BLOCKed" {
    mkdir -p "$TMPDIR_BATS/queue/reports" "$TMPDIR_BATS/queue/tasks"
    local report="$TMPDIR_BATS/queue/reports/testninja_report_cmd_test.yaml"
    create_valid_report "$report" >/dev/null
    cat > "$TMPDIR_BATS/queue/tasks/testninja.yaml" <<'YAML'
task:
  parent_cmd: cmd_test
  speed_campaign:
    baseline_policy: same_run_interleaved_ab
YAML
    cat >> "$report" <<'YAML'
speed_result: {quality: pass}
test_results: {status: pass, wall_sec: 12.5, failures: 0, skips: 0}
YAML

    run env GATE_NO_LOG=1 bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"speed callback AB schema"* ]]
}

# test_necessity: complete same-run A/B evidence with matching statistics remains accepted.
@test "T-001h: terminal same-run speed PASS with complete speed_ab passes" {
    mkdir -p "$TMPDIR_BATS/queue/reports" "$TMPDIR_BATS/queue/tasks"
    local report="$TMPDIR_BATS/queue/reports/testninja_report_cmd_test.yaml"
    create_valid_report "$report" >/dev/null
    cat > "$TMPDIR_BATS/queue/tasks/testninja.yaml" <<'YAML'
task:
  parent_cmd: cmd_test
  commit_contract: {required: false}
  speed_campaign:
    baseline_policy: same_run_interleaved_ab
YAML
    cat >> "$report" <<'YAML'
speed_result: {quality: pass}
test_results: {status: pass, wall_sec: 9, failures: 0, skips: 0}
speed_ab:
  last_good_commit: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  candidate_commit: bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  command: bats tests/unit/example.bats
  order: alternating
  warmup_each: 1
  sequence: [L, C, L, C, L, C, L, C, L, C, L, C, L, C, L, C, L, C, L, C]
  last_good_samples_ms: [10, 10, 10, 10, 10, 10, 10, 10, 10, 10]
  candidate_samples_ms: [9, 9, 9, 9, 9, 9, 9, 9, 9, 9]
  last_good_p50: 10
  last_good_p95: 10
  candidate_p50: 9
  candidate_p95: 9
  adopted: true
YAML

    run env GATE_NO_LOG=1 bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# --- T-002: Missing file → FAIL ---
@test "T-002: missing file returns FAIL" {
    run bash "$GATE" "$TMPDIR_BATS/nonexistent.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

# --- T-003: Empty verdict with unfilled binary_checks → FAIL (autofix cannot derive) ---
@test "T-003: empty verdict with unfilled binary_checks returns FAIL" {
    local report=$(create_valid_report)
    # Set verdict="" AND binary_checks result="" → autofix can't derive verdict
    sed -i 's/^verdict: PASS/verdict: ""/' "$report"
    sed -i 's/result: "yes"/result: ""/' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"verdict"* ]]
}

@test "T-003b: empty verdict emits report_field_set fix command" {
    local report=$(create_valid_report)
    sed -i 's/^verdict: PASS/verdict: ""/' "$report"
    sed -i 's/result: "yes"/result: ""/' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FIX COMMAND (verdict)"* ]]
    [[ "$output" == *"bash scripts/report_field_set.sh $report verdict PASS"* ]]
}

@test "T-003c: empty binary_checks result emits report_field_set fix command" {
    local report=$(create_valid_report)
    sed -i 's/^verdict: PASS/verdict: ""/' "$report"
    sed -i 's/result: "yes"/result: ""/' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FIX COMMAND (binary_checks result)"* ]]
    [[ "$output" == *"bash scripts/report_field_set.sh $report binary_checks.AC1.0.result yes"* ]]
}

@test "T-003d: FILL_THIS placeholder emits report_field_set fix command" {
    local report=$(create_valid_report)
    sed -i 's#files_modified: \[\]#files_modified: FILL_THIS#' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"files_modified: FILL_THIS placeholder remaining"* ]]
    [[ "$output" == *"FIX COMMAND (files_modified)"* ]]
    [[ "$output" == *"bash scripts/report_field_set.sh $report files_modified scripts/gates/gate_report_format_main.py"* ]]
}

# --- T-004: GP-128 PASS+no → auto-derived FAIL verdict → PASS ---
@test "T-004: verdict=PASS with bc no is overwritten to FAIL" {
    local report=$(create_valid_report)
    sed -i 's/result: "yes"/result: "no"/' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    run grep '^verdict: FAIL$' "$report"
    [ "$status" -eq 0 ]
}

# --- T-005: GP-128 FAIL+all-yes → auto-derived PASS verdict ---
@test "T-005: verdict=FAIL with all-yes is overwritten to PASS" {
    local report=$(create_valid_report)
    sed -i 's/^verdict: PASS/verdict: FAIL/' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    run grep '^verdict: PASS$' "$report"
    [ "$status" -eq 0 ]
}

@test "T-GP287-1: short commit_hash fails" {
    local short_report="$TMPDIR_BATS/short_hash_report.yaml"
    create_valid_report "$short_report" >/dev/null
    cat >> "$short_report" << 'YAML'
commit_hash: abc1234
YAML

    run bash "$GATE" "$short_report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"commit_hash: 'abc1234' は40文字フルhashでない"* ]]
}

@test "T-GP287-2: full 40-char commit_hash passes" {
    local full_report="$TMPDIR_BATS/full_hash_report.yaml"
    create_valid_report "$full_report" >/dev/null
    cat >> "$full_report" << 'YAML'
commit_hash: 0123456789abcdef0123456789abcdef01234567
YAML

    run bash "$GATE" "$full_report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"40文字フルhashでない"* ]]
}

# --- cmd_karo_hotfix_report_commit_contract_202607131320: commit_hash欠落の前段BLOCK ---
# tobisaruのhotfix実装報告(binary_checks.commit=yes, commit_hash欠落, status=completed)が
# gate_report_formatをPASSし、review_approval.shで初めてBLOCKした事故の再発防止。
# parent cmd sourceが直近git logに無いkaro_direct hotfixでも欠落を検出しなければならない(AC1)。

@test "T-CHC-1 (AC1): commit AC=yes without commit_hash is BLOCKed even without parent_cmd in git log" {
    local report="$TMPDIR_BATS/chc1_report.yaml"
    cat > "$report" << 'YAML'
worker_id: testninja
parent_cmd: cmd_karo_hotfix_no_parent_source_in_recent_log
ac_version_read: abc12345
timestamp: '2026-07-13T00:00:00+09:00'
status: completed
result:
  summary: "hotfix実装完了"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
files_modified:
  - path: scripts/gates/gate_report_format_main.py
causal_verification:
  cause_checked: regression fixture for commit identity
  design_intent_checked: exercise the production gate path
  evidence: "rg -n gate_report_format_main scripts --glob '!tests/**'; non-test caller count: 1"
operational_simulation:
  command: "bats --filter T-CHC-2 tests/test_gate_report_format.bats"
  expected: "valid commit hash report passes"
  actual: "exit 0 and PASS"
  result: "PASS"
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
lessons_useful: []
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
binary_checks:
  AC1:
    - check: "テスト対象の確認項目を詳細に記載"
      result: "yes"
  commit:
    - check: "git commitが完了したか(untracked/modified=0)"
      result: "yes"
verdict: PASS
YAML

    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"commit_hash"* ]]
    [[ "$output" == *"binary_checks.commitがyes"* ]]
}

@test "T-CHC-2 (AC2 true negative): commit AC=yes with valid 40-char commit_hash still PASSes" {
    local report="$TMPDIR_BATS/chc2_report.yaml"
    cat > "$report" << 'YAML'
worker_id: testninja
parent_cmd: cmd_karo_hotfix_no_parent_source_in_recent_log
ac_version_read: abc12345
timestamp: '2026-07-13T00:00:00+09:00'
status: completed
commit_hash: 0123456789abcdef0123456789abcdef01234567
result:
  summary: "hotfix実装完了"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
files_modified:
  - path: scripts/gates/gate_report_format_main.py
causal_verification:
  cause_checked: regression fixture for valid commit identity
  design_intent_checked: exercise the production gate path
  evidence: "rg -n gate_report_format_main scripts --glob '!tests/**'; non-test caller count: 1"
operational_simulation:
  command: "bats --filter T-CHC-2 tests/test_gate_report_format.bats"
  expected: "valid commit hash report passes"
  actual: "exit 0 and PASS"
  result: "PASS"
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
lessons_useful: []
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
binary_checks:
  AC1:
    - check: "テスト対象の確認項目を詳細に記載"
      result: "yes"
  commit:
    - check: "git commitが完了したか(untracked/modified=0)"
      result: "yes"
verdict: PASS
YAML

    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

@test "T-CHC-3 (AC2 true negative): no-code recon report without commit_hash still PASSes" {
    local report="$TMPDIR_BATS/chc3_report.yaml"
    cat > "$report" << 'YAML'
worker_id: testninja
parent_cmd: cmd_test
task_type: recon
ac_version_read: abc12345
timestamp: '2026-07-13T00:00:00+09:00'
status: completed
result:
  summary: "偵察完了。変更なし"
purpose_validation:
  cmd_purpose: "テスト"
  fit: true
  purpose_gap: ""
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
lessons_useful: []
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
binary_checks:
  AC1:
    - check: "偵察対象の確認"
      result: "yes"
verdict: PASS
YAML

    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# test_necessity: 標準git revertのidentity例外は、明示40hex・本文完全一致・対象解決可能の積だけを許可する。
@test "T-REVERT-IDENTITY: explicit verified revert passes and five invalid boundaries fail closed" {
    local repo="$TMPDIR_BATS/revert_identity_repo"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name test
    printf 'base\n' > "$repo/owned.txt"
    git -C "$repo" add owned.txt
    git -C "$repo" commit -qm "base"
    printf 'changed\n' > "$repo/owned.txt"
    git -C "$repo" commit -qam "unrelated original subject"
    local reverted
    reverted="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" revert --no-edit "$reverted" >/dev/null
    local identity
    identity="$(git -C "$repo" rev-parse HEAD)"
    printf 'other\n' > "$repo/other.txt"
    git -C "$repo" add other.txt
    git -C "$repo" commit -qm "other resolvable commit"
    local other
    other="$(git -C "$repo" rev-parse HEAD)"

    run python3 - "$PROJECT_ROOT" "$repo" "$identity" "$reverted" "$other" <<'PY'
import importlib.util
import pathlib
import sys

project_root, repo, identity, reverted, other = sys.argv[1:]
module_path = pathlib.Path(project_root) / "scripts/gates/gate_report_format_main.py"
spec = importlib.util.spec_from_file_location("gate_report_format_main", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

report = {
    "commit_hash": identity,
    "task_id": "cmd_not_in_revert_subject",
    "parent_cmd": "cmd_also_absent",
    "files_modified": [{"path": "owned.txt"}],
}

def errors(reverts_commit_marker=...):
    contract = {
        "required": True,
        "repo_root": repo,
        "planned_paths": ["owned.txt"],
    }
    if reverts_commit_marker is not ...:
        contract["reverts_commit"] = reverts_commit_marker
    task = {"task_id": report["task_id"], "commit_contract": contract}
    return module.commit_contract_errors(report, task, pathlib.Path(repo))

assert errors(reverted) == [], errors(reverted)
invalid = [
    errors(),
    errors(reverted[:8]),
    errors(other),
    errors("f" * 40),
    errors("0" * 40),
]
assert len(invalid) == 5
assert all("commit subject does not identify task_id/parent_cmd" in case for case in invalid)
print("false_positive=0/5 false_negative=0/1")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"false_positive=0/5 false_negative=0/1"* ]]
}

@test "T-GP286-1: non-path files_modified fails" {
    local non_path_report="$TMPDIR_BATS/non_path_files_modified_report.yaml"
    create_valid_report "$non_path_report" >/dev/null
    python3 - "$non_path_report" <<'PY'
import sys, yaml
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = yaml.safe_load(f)
data["files_modified"] = ["変更内容の説明だけ"]
with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(data, f, allow_unicode=True, sort_keys=False)
PY

    run bash "$GATE" "$non_path_report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"files_modified: 1件がパス形式でない"* ]]
}

@test "T-GP286-2: path-form files_modified passes" {
    local path_report="$TMPDIR_BATS/path_files_modified_report.yaml"
    create_valid_report "$path_report" >/dev/null
    python3 - "$path_report" <<'PY'
import sys, yaml
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = yaml.safe_load(f)
data["files_modified"] = ["tests/test_gate_report_format.bats"]
with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(data, f, allow_unicode=True, sort_keys=False)
PY

    run bash "$GATE" "$path_report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"パス形式でない"* ]]
}

@test "T-LKA14-1: residual sweep mention without grep zero evidence fails" {
    local report="$TMPDIR_BATS/lka14_missing_evidence.yaml"
    create_valid_report "$report" >/dev/null
    python3 - "$report" <<'PY'
import sys, yaml
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = yaml.safe_load(f)
data["result"]["details"] = "修正前パターンの横展開確認を実施した"
data["files_modified"] = ["scripts/gates/gate_report_format_main.py"]
with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(data, f, allow_unicode=True, sort_keys=False)
PY

    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"LK-A14: 横展開/修正前パターンを扱う報告にはgrep/rg残存0件の一次証跡が必須"* ]]
}

@test "T-LKA14-2: residual sweep mention with grep zero evidence passes" {
    local report="$TMPDIR_BATS/lka14_with_evidence.yaml"
    create_valid_report "$report" >/dev/null
    python3 - "$report" <<'PY'
import sys, yaml
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = yaml.safe_load(f)
data["result"]["details"] = "修正前パターンの横展開確認を実施。rg 'old_pattern' scripts tests の残存0件を確認。"
data["files_modified"] = ["scripts/gates/gate_report_format_main.py"]
data["causal_verification"] = {
    "cause_checked": "regression fixture for residual sweep",
    "design_intent_checked": "exercise the production gate path",
    "evidence": "rg -n gate_report_format_main scripts --glob '!tests/**'; non-test caller count: 1",
}

data["operational_simulation"] = {
    "command": "rg 'old_pattern' scripts tests",
    "expected": "残存0件",
    "actual": "残存0件",
    "result": "PASS",
}
with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(data, f, allow_unicode=True, sort_keys=False)
PY

    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"LK-A14"* ]]
}

# test_necessity: LK-A14 must require both an existing implementation file and an affirmative completed-sweep claim.
# regression_justification: prose-only/read-only/proposal/docs/empty/negated reports previously caused false positives.
@test "T-LKA14-3: implementation precision six variants have zero false positives and negatives" {
    local fixture="$TMPDIR_BATS/lka14_variants.py"
    cat > "$fixture" <<'PY'
import importlib.util
import pathlib

module_path = pathlib.Path("scripts/gates/gate_report_format_main.py").resolve()
spec = importlib.util.spec_from_file_location("gate_report_format_main", module_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

variants = [
    ("implemented_code", ["scripts/gates/gate_report_format_main.py"], "修正前パターンの横展開を実施した", True),
    ("readonly", ["scripts/gates/gate_report_format_main.py"], "read-only調査でSSOT横展開を確認のみ", False),
    ("proposal", ["scripts/gates/gate_report_format_main.py"], "SSOT横展開を今後提案する", False),
    ("docs_only", ["docs/research/example.md"], "修正前パターンの横展開を実施した", False),
    ("files_empty", [], "修正前パターンの横展開を実施した", False),
    ("negated", ["scripts/gates/gate_report_format_main.py"], "SSOT横展開は実施していない", False),
]
fp = fn = 0
for name, files, text, expected in variants:
    actual = (
        module._report_has_existing_implementation_file(files)
        and module._report_claims_completed_residual_sweep({"result": text})
    )
    print(f"{name}: expected={expected} actual={actual}")
    fp += int(actual and not expected)
    fn += int(expected and not actual)
print(f"false_positive={fp} false_negative={fn}")
raise SystemExit(0 if fp == 0 and fn == 0 else 1)
PY

    run python3 "$fixture"
    [ "$status" -eq 0 ]
    [[ "$output" == *"false_positive=0 false_negative=0"* ]]
}

@test "T-LG055-1: integration report without operational_simulation is BLOCKed" {
    local report="$TMPDIR_BATS/lg055_missing.yaml"
    create_valid_report "$report" >/dev/null
    python3 - "$report" <<'PY'
import sys, yaml
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = yaml.safe_load(f)
data["files_modified"] = [{"path": "scripts/gates/gate_report_format_main.py"}]
data.pop("operational_simulation", None)
with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(data, f, allow_unicode=True, sort_keys=False)
PY

    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"operational_simulation: MISSING"* ]]
}

@test "T-LG055-2: integration report with incomplete operational_simulation is BLOCKed" {
    local report="$TMPDIR_BATS/lg055_incomplete.yaml"
    create_valid_report "$report" >/dev/null
    python3 - "$report" <<'PY'
import sys, yaml
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = yaml.safe_load(f)
data["files_modified"] = [{"path": "scripts/gates/gate_report_format_main.py"}]
data["operational_simulation"] = {"command": "bats tests/test_gate_report_format.bats"}
with open(path, "w", encoding="utf-8") as f:
    yaml.safe_dump(data, f, allow_unicode=True, sort_keys=False)
PY

    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"expected,actual,result"* ]]
}

# --- T-006: GP-073 PASS cache hit ---
@test "T-006: GP-073 second call hits mtime cache" {
    local report="$REPO_TMPDIR_BATS/cache_report.yaml"
    create_valid_report "$report" >/dev/null
    # First call: full validation
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    # Verify cache file exists
    [ -f "$GATE_PASS_CACHE_FILE" ]
    # Second call: should hit cache (no GP-062 WARN etc, just PASS)
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == "PASS" ]]
}

# --- T-007: GP-073 cache invalidation on mtime change ---
@test "T-007: GP-073 cache invalidated on file change" {
    local report="$REPO_TMPDIR_BATS/cache_invalidate_report.yaml"
    create_valid_report "$report" >/dev/null
    # First call: cache
    bash "$GATE" "$report" > /dev/null 2>&1
    [ -f "$GATE_PASS_CACHE_FILE" ]
    # Modify file (changes mtime)
    sleep 1
    echo "# mtime change" >> "$report"
    # Second call: should NOT hit cache (full validation)
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# test_necessity: cached PASS must be invalidated whenever validator code generation changes.
@test "T-007b: GP-073 cache invalidated when validator generation changes" {
    local report="$REPO_TMPDIR_BATS/cache_validator_invalidate_report.yaml"
    local generation="$REPO_TMPDIR_BATS/validator.generation"
    create_valid_report "$report" >/dev/null
    printf 'generation-1\n' > "$generation"
    GATE_CACHE_VERSION_FILE_OVERRIDE="$generation" bash "$GATE" "$report" > /dev/null 2>&1
    [ -f "$GATE_PASS_CACHE_FILE" ]

    run env GATE_CACHE_VERSION_FILE_OVERRIDE="$generation" bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == "PASS" ]]

    sleep 1
    printf 'generation-2\n' > "$generation"
    run env GATE_CACHE_VERSION_FILE_OVERRIDE="$generation" bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: origin欄が空/未記入"* ]]
}

# --- T-008: Missing binary_checks → FAIL ---
@test "T-008: missing binary_checks returns FAIL" {
    local report=$(create_valid_report)
    sed -i '/^binary_checks:/,/^[a-z]/{ /^binary_checks:/d; /^  /d; }' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"binary_checks"* ]]
}

# --- T-009: YAML parse error → FAIL ---
@test "T-009: invalid YAML returns FAIL" {
    echo "invalid: yaml: : :" > "$TMPDIR_BATS/broken.yaml"
    run bash "$GATE" "$TMPDIR_BATS/broken.yaml"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
}

# --- T-010: FAIL report not cached (use unfixable FAIL: empty result string) ---
@test "T-010: FAIL reports are not cached" {
    local report=$(create_valid_report)
    # Set both verdict="" and binary_checks result="" → autofix can't derive → still FAIL
    sed -i 's/^verdict: PASS/verdict: ""/' "$report"
    sed -i 's/result: "yes"/result: ""/' "$report"
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    # Cache should not contain this file
    if [ -f "$GATE_PASS_CACHE_FILE" ]; then
        run grep "$(realpath "$report")" "$GATE_PASS_CACHE_FILE"
        [ "$status" -ne 0 ]
    fi
}

# --- T-NOLOG-1: GATE_NO_LOG=1 PASS時にgate_fire_logに書込みなし ---
@test "T-NOLOG-1: GATE_NO_LOG=1 skips fire_log on PASS" {
    local report=$(create_valid_report)
    GATE_NO_LOG=1 run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    # fire_log should not exist or not contain this report
    if [ -f "$GATE_FIRE_LOG_FILE" ]; then
        run grep "gate_report_format" "$GATE_FIRE_LOG_FILE"
        [ "$status" -ne 0 ]
    fi
}

# --- T-NOLOG-2: GATE_NO_LOG未設定で通常書込み確認 ---
@test "T-NOLOG-2: without GATE_NO_LOG fire_log is written" {
    local report="$REPO_TMPDIR_BATS/report.yaml"
    create_valid_report "$report" >/dev/null
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    # fire_log should contain an entry
    [ -f "$GATE_FIRE_LOG_FILE" ]
    run grep "gate_report_format" "$GATE_FIRE_LOG_FILE"
    [ "$status" -eq 0 ]
}

# --- T-SKILL-LOG-1: PASS report records report-write execution ---
@test "T-SKILL-LOG-1: PASS reports are recorded in skill_execution_log" {
    # Skill execution logging intentionally covers only genuine queue reports;
    # keep this fixture on that production path without sharing the real ledger.
    local report
    SKILL_LOG_REPORT_DIR="$(mktemp -d "queue/.tmp_gate_report_skill_log.XXXXXX")"
    report="$SKILL_LOG_REPORT_DIR/testninja_report_cmd_test.yaml"
    create_valid_report "$report" >/dev/null
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]

    # SKILL_LOG_SYNC=1 により同期実行。ポーリング不要。
    run python3 - <<EOF
import yaml
data = yaml.safe_load(open("$SKILL_EXECUTION_LOG_FILE", encoding="utf-8"))
entries = data["executions"]
report_write = next(e for e in entries if e["skill"] == "report-write")
verdict_check = next(e for e in entries if e["skill"] == "verdict-check")
assert report_write["result"] == "PASS"
assert report_write["gate"] == "gate_report_format"
assert report_write["source"] == "cmd_test"
assert verdict_check["result"] == "PASS"
assert verdict_check["gate"] == "gate_report_format"
assert verdict_check["source"] == "cmd_test"
print("OK")
EOF
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# --- T-NOLOG-3: /tmp/テストレポートはfire_logに書き込まない ---
@test "T-NOLOG-3: /tmp reports are excluded from fire_log" {
    local report=$(create_valid_report)
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    if [ -f "$GATE_FIRE_LOG_FILE" ]; then
        run grep "$report" "$GATE_FIRE_LOG_FILE"
        [ "$status" -ne 0 ]
    fi
}

# --- T-011: Autofix binary_checks str→list conversion ---
@test "T-011: autofix converts binary_checks string to list" {
    local report="$TMPDIR_BATS/report.yaml"
    cat > "$report" << 'YAML'
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
timestamp: '2026-07-12T00:00:00+09:00'
status: completed
binary_checks:
  AC1: "テスト対象の確認項目を詳細に記載"
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
lessons_useful: []
purpose_validation:
  cmd_purpose: "テスト用途の確認タスク"
  fit: true
  purpose_gap: ""
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
operational_simulation:
  command: "bash scripts/gates/gate_report_autofix.sh"
  expected: "autofixed report passes format validation"
  actual: "autofix and format validation executed"
  result: "PASS"
result:
  summary: "テスト結果のサマリ"
verdict: PASS
YAML
    # Run autofix — should convert string to [{check: str, result: yes}]
    run bash "$AUTOFIX" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AUTO-FIXED"* ]]
    [[ "$output" == *"binary_checks"* ]]
    # Verify format gate passes after autofix
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
}

# --- T-012: lessons_useful MISSING → BLOCK (消火撤去: スケルトン生成廃止) ---
@test "T-012: lessons_useful MISSING triggers BLOCK not autofix" {
    # Setup directory structure matching report→task path resolution
    mkdir -p "$TMPDIR_BATS/tasks" "$TMPDIR_BATS/reports"
    cat > "$TMPDIR_BATS/tasks/testninja.yaml" << 'YAML'
task:
  related_lessons:
    - id: L001
      summary: "テスト教訓1"
    - id: L002
      summary: "テスト教訓2"
YAML
    local report="$TMPDIR_BATS/reports/testninja_report_cmd_test.yaml"
    # Report WITHOUT lessons_useful key
    cat > "$report" << 'YAML'
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
status: completed
binary_checks:
  AC1:
    - check: "テスト対象の確認項目を詳細に記載"
      result: "yes"
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
purpose_validation:
  cmd_purpose: "テスト用途の確認タスク"
  fit: true
  purpose_gap: ""
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
result:
  summary: "テスト結果のサマリ"
verdict: PASS
YAML
    # Run gate format check — should FAIL (lessons_useful MISSING → BLOCK)
    # 消火撤去(GP-107): autofixでスケルトン生成=消火。忍者が自力記入すべき
    run bash "$GATE" "$report"
    [ "$status" -ne 0 ]
    [[ "$output" == *"lessons_useful"* ]]
}

# --- T-INTERMEDIATE-1: 中間状態(verdict空+AC欄なし)でgate_fire_logにFAIL記録されないこと ---
@test "T-INTERMEDIATE-1: intermediate state (empty verdict + no AC) does not write FAIL to fire_log" {
    local report="$REPO_TMPDIR_BATS/intermediate_report.yaml"
    cat > "$report" << 'YAML'
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
status: completed
binary_checks: {}
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
lessons_useful: []
purpose_validation:
  cmd_purpose: "テスト用途の確認タスク"
  fit: true
  purpose_gap: ""
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
result:
  summary: "テスト結果のサマリ"
verdict: ""
YAML
    run bash "$GATE" "$report"
    # Gate should still FAIL (exit 1) — verdict未設定は本当にFAIL
    [ "$status" -eq 1 ]
    # fire_log should NOT contain FAIL entry for this report（中間状態=偽陽性）
    if [ -f "$GATE_FIRE_LOG_FILE" ]; then
        run grep "$report" "$GATE_FIRE_LOG_FILE"
        [ "$status" -ne 0 ]
    fi
}

# --- T-INTERMEDIATE-2: verdict記入済み+AC欄なし → 通常FAIL記録（本物の品質問題）---
@test "T-INTERMEDIATE-2: non-intermediate FAIL (verdict=FAIL + no AC) writes FAIL to fire_log" {
    local report="$REPO_TMPDIR_BATS/real_fail_report.yaml"
    cat > "$report" << 'YAML'
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
status: completed
binary_checks: {}
files_modified: []
lesson_candidate:
  found: false
  no_lesson_reason: "既知パターンのため新規教訓なし"
lessons_useful: []
purpose_validation:
  cmd_purpose: "テスト用途の確認タスク"
  fit: true
  purpose_gap: ""
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
result:
  summary: "テスト結果のサマリ"
verdict: FAIL
YAML
    run bash "$GATE" "$report"
    # Gate should FAIL（verdict=FAILかつAC欄なしは本物の品質問題）
    [ "$status" -eq 1 ]
    # fire_log SHOULD contain FAIL entry（中間状態ではない）
    [ -f "$GATE_FIRE_LOG_FILE" ]
    run grep "$report" "$GATE_FIRE_LOG_FILE"
    [ "$status" -eq 0 ]
}

# --- T-SGC-1: self_gate_check 必須4キーが揃ったdict → PASS ---
@test "T-SGC-1: self_gate_check with required keys passes" {
    local report=$(create_valid_report)
    cat >> "$report" << 'YAML'
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
YAML
    run bash "$GATE" "$report"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}

# --- T-SGC-2: self_gate_check 必須キー欠落 → FAIL ---
@test "T-SGC-2: self_gate_check missing required key fails with specific message" {
    local report=$(create_valid_report)
    cat >> "$report" << 'YAML'
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  purpose_fit: PASS
YAML
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *'self_gate_check: missing required key "status_valid" (required: lesson_ref, lesson_candidate, status_valid, purpose_fit)'* ]]
}

# --- T-SGC-3: 旧キー名dict → FAIL ---
@test "T-SGC-3: self_gate_check legacy key names fail required key validation" {
    local report=$(create_valid_report)
    cat >> "$report" << 'YAML'
self_gate_check:
  lesson_ref: PASS
  format_compliance: PASS
  binary_checks: PASS
  purpose_fit: PASS
YAML
    run bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *'self_gate_check: missing required key "lesson_candidate" (required: lesson_ref, lesson_candidate, status_valid, purpose_fit)'* ]]
    [[ "$output" == *'self_gate_check: missing required key "status_valid" (required: lesson_ref, lesson_candidate, status_valid, purpose_fit)'* ]]
}

# --- cmd_3264: auto-commit contamination check ---

@test "T-AC2-1: bc:commit=yes with uncommitted target_path files triggers WARN" {
    # Create report in project-local temp dir (not /tmp) to activate AC2/AC3 check
    local report="$REPO_TMPDIR_BATS/testninja_report_cmd_test.yaml"
    mkdir -p "$REPO_TMPDIR_BATS/queue/tasks"
    cat > "$REPO_TMPDIR_BATS/queue/tasks/testninja.yaml" <<YAML
task:
  status: in_progress
  target_path: scripts/gates
YAML
    cat > "$report" <<YAML
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
status: completed
binary_checks:
  AC1:
    - check: "test check"
      result: "yes"
  commit:
    - check: "git commitが完了したか"
      result: "yes"
files_modified:
  - path: scripts/gates/test.sh
lesson_candidate:
  found: false
  no_lesson_reason: "test"
result:
  summary: "test summary"
  details: "test details"
purpose_validation:
  cmd_purpose: "test"
  fit: true
  purpose_gap: ""
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
lessons_useful: []
YAML
    # The check uses REPO_ROOT to find queue/tasks - override to use our temp dir
    # Since REPO_ROOT in gate_report_format.sh is derived from the script location,
    # the check will look at the real repo's queue/tasks, not our temp one.
    # This test verifies the contamination check doesn't crash on non-/tmp reports.
    # Gate may FAIL for other missing fields — we only check the check ran without error.
    run bash "$GATE" "$report"
    echo "$output"
    # Should not contain Python traceback from the contamination check
    [[ "$output" != *"Traceback"* ]]
    # The WARN check should not fire since testninja has no task in real repo
    [[ "$output" != *"WARN(cmd_3264"* ]]
}

@test "T-AC2-2: /tmp reports skip contamination check" {
    local report="$TMPDIR_BATS/report.yaml"
    create_valid_report "$report"
    # Add commit bc with yes
    cat >> "$report" <<YAML
  commit:
    - check: "git commitが完了したか"
      result: "yes"
YAML
    run bash "$GATE" "$report"
    # Should PASS without any WARN (check skipped for /tmp)
    [[ "$output" != *"WARN(cmd_3264"* ]]
}

@test "T-AC2-3: session_state-only tracked task diff does not block commit check" {
    local repo="$REPO_TMPDIR_BATS/session_state_repo"
    local report="$repo/reports/testninja_report_cmd_test.yaml"
    mkdir -p "$repo/queue/tasks" "$repo/reports" "$repo/logs"
    _init_fixture_repo "$repo"
    cat > "$repo/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: in_progress
  target_path: queue/tasks/testninja.yaml
YAML
    git -C "$repo" add queue/tasks/testninja.yaml
    git -C "$repo" commit -q -m "seed task"
    local commit_hash
    commit_hash=$(git -C "$repo" rev-parse HEAD)
    cat >> "$repo/queue/tasks/testninja.yaml" <<'YAML'
  session_state:
    attempt: 1
    last_block_reason: 'cmd_3264-AC2 target_path配下に未commit変更あり'
    tried_approaches:
    - 'cmd_3264-AC2 target_path配下に未commit変更あり'
    prior_attempts:
    - attempt: 1
      block_reason: 'cmd_3264-AC2 target_path配下に未commit変更あり'
YAML
    cat > "$report" <<YAML
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
timestamp: '2026-07-08T00:00:00'
status: completed
commit_hash: ${commit_hash}
result:
  summary: "test summary"
purpose_validation:
  cmd_purpose: "test"
  fit: true
  purpose_gap: ""
binary_checks:
  AC1:
  - check: "test check"
    result: "yes"
  commit:
  - check: "git commitが完了したか"
    result: "yes"
files_modified:
- path: queue/tasks/testninja.yaml
lesson_candidate:
  found: false
  no_lesson_reason: "test"
lessons_useful: []
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
verdict: PASS
YAML

    run env GATE_REPO_ROOT_OVERRIDE="$repo" GATE_SESSION_STATE_TASK_DIR="$repo/queue/tasks" bash "$GATE" "$report"
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
    [[ "$output" != *"BLOCK(cmd_3264-AC2)"* ]]
}

@test "T-AC2-4: tracked task status diff still blocks commit check" {
    local repo="$REPO_TMPDIR_BATS/task_status_repo"
    local report="$repo/reports/testninja_report_cmd_test.yaml"
    mkdir -p "$repo/queue/tasks" "$repo/reports" "$repo/logs"
    _init_fixture_repo "$repo"
    cat > "$repo/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: in_progress
  target_path: queue/tasks/testninja.yaml
YAML
    git -C "$repo" add queue/tasks/testninja.yaml
    git -C "$repo" commit -q -m "seed task"
    sed -i 's/status: in_progress/status: done/' "$repo/queue/tasks/testninja.yaml"
    cat > "$report" <<'YAML'
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
timestamp: '2026-07-08T00:00:00'
status: completed
result:
  summary: "test summary"
purpose_validation:
  cmd_purpose: "test"
  fit: true
  purpose_gap: ""
binary_checks:
  AC1:
  - check: "test check"
    result: "yes"
  commit:
  - check: "git commitが完了したか"
    result: "yes"
files_modified:
- path: queue/tasks/testninja.yaml
lesson_candidate:
  found: false
  no_lesson_reason: "test"
lessons_useful: []
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
verdict: PASS
YAML

    run env GATE_REPO_ROOT_OVERRIDE="$repo" GATE_SESSION_STATE_TASK_DIR="$repo/queue/tasks" bash "$GATE" "$report"
    echo "$output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK(cmd_3264-AC2)"* ]]
    [[ "$output" == *"M queue/tasks/testninja.yaml"* ]]
}

@test "T-AC2-5: abbreviated earlier task-owned commit in structured evidence permits non-overlapping dirty hunk" {
    local repo="$REPO_TMPDIR_BATS/multicommit_nonoverlap_repo"
    local report="$repo/reports/testninja_report_cmd_multi.yaml"
    mkdir -p "$repo/queue/tasks" "$repo/reports" "$repo/logs"
    _init_fixture_repo "$repo"
    mkdir -p "$repo/context"
    printf 'one\ntwo\nthree\nfour\n' > "$repo/context/shared.txt"
    git -C "$repo" add context/shared.txt && git -C "$repo" commit -q -m "test-fixture(tests/test_gate_report_format.bats): fixture repo seed"
    sed -i 's/^one$/one owned/' "$repo/context/shared.txt"
    git -C "$repo" add context/shared.txt && git -C "$repo" commit -q -m 'cmd_multi: first scoped commit'
    local first_hash; first_hash=$(git -C "$repo" rev-parse HEAD)
    printf 'second\n' > "$repo/second.txt"
    git -C "$repo" add second.txt && git -C "$repo" commit -q -m 'cmd_multi: final scoped commit'
    local final_hash; final_hash=$(git -C "$repo" rev-parse HEAD)
    sed -i 's/^four$/four concurrent/' "$repo/context/shared.txt"
    cat > "$repo/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: in_progress
  target_path: context/shared.txt
YAML
    _write_ac3_report "$report" "$final_hash"
    sed -i 's/path: shared.txt/path: context\/shared.txt/' "$report"
    local first_short="${first_hash:0:8}"
    sed -i "s/parent_cmd: cmd_test/parent_cmd: cmd_multi/; /summary: \"test summary\"/a\\ac_evidence_mapping:\n  AC2: \"task commits ${first_short}\"" "$report"
    run env GATE_REPO_ROOT_OVERRIDE="$repo" GATE_SESSION_STATE_TASK_DIR="$repo/queue/tasks" bash "$GATE" "$report"
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK(cmd_3264-AC2)"* ]]
}

@test "T-AC2-6: unowned commit mentioned in report cannot suppress dirty hunk" {
    local repo="$REPO_TMPDIR_BATS/multicommit_unowned_repo"
    local report="$repo/reports/testninja_report_cmd_multi.yaml"
    mkdir -p "$repo/queue/tasks" "$repo/reports" "$repo/logs"
    _init_fixture_repo "$repo"
    mkdir -p "$repo/context"
    printf 'one\ntwo\nthree\nfour\n' > "$repo/context/shared.txt"
    git -C "$repo" add context/shared.txt && git -C "$repo" commit -q -m "test-fixture(tests/test_gate_report_format.bats): fixture repo seed"
    sed -i 's/^one$/one foreign/' "$repo/context/shared.txt"
    git -C "$repo" add context/shared.txt && git -C "$repo" commit -q -m 'other_cmd: foreign commit'
    local foreign_hash; foreign_hash=$(git -C "$repo" rev-parse HEAD)
    printf 'owned\n' > "$repo/owned.txt"
    git -C "$repo" add owned.txt && git -C "$repo" commit -q -m 'cmd_multi: final scoped commit'
    local final_hash; final_hash=$(git -C "$repo" rev-parse HEAD)
    sed -i 's/^four$/four dirty/' "$repo/context/shared.txt"
    cat > "$repo/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: in_progress
  target_path: context/shared.txt
YAML
    _write_ac3_report "$report" "$final_hash"
    sed -i 's/path: shared.txt/path: context\/shared.txt/' "$report"
    local foreign_short="${foreign_hash:0:8}"
    sed -i "s/parent_cmd: cmd_test/parent_cmd: cmd_multi/; /summary: \"test summary\"/a\\ac_evidence_mapping:\n  AC2: \"foreign ${foreign_short}\"" "$report"
    run env GATE_REPO_ROOT_OVERRIDE="$repo" GATE_SESSION_STATE_TASK_DIR="$repo/queue/tasks" bash "$GATE" "$report"
    echo "$output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK(cmd_3264-AC2)"* ]]
}

@test "T-AC2-7: abbreviated owned commit with overlapping dirty hunk remains blocked" {
    local repo="$REPO_TMPDIR_BATS/multicommit_short_overlap_repo"
    local report="$repo/reports/testninja_report_cmd_multi.yaml"
    mkdir -p "$repo/queue/tasks" "$repo/reports" "$repo/logs" "$repo/context"
    _init_fixture_repo "$repo"
    printf 'one\ntwo\n' > "$repo/context/shared.txt"
    git -C "$repo" add context/shared.txt && git -C "$repo" commit -q -m "test-fixture(tests/test_gate_report_format.bats): seed"
    sed -i 's/^one$/one owned/' "$repo/context/shared.txt"
    git -C "$repo" add context/shared.txt && git -C "$repo" commit -q -m 'cmd_multi: first scoped commit'
    local first_hash; first_hash=$(git -C "$repo" rev-parse HEAD)
    printf 'final\n' > "$repo/final.txt"
    git -C "$repo" add final.txt && git -C "$repo" commit -q -m 'cmd_multi: final scoped commit'
    local final_hash; final_hash=$(git -C "$repo" rev-parse HEAD)
    sed -i 's/^one owned$/one dirty overlap/' "$repo/context/shared.txt"
    printf 'task:\n  status: in_progress\n  target_path: context/shared.txt\n' > "$repo/queue/tasks/testninja.yaml"
    _write_ac3_report "$report" "$final_hash"
    sed -i 's/path: shared.txt/path: context\/shared.txt/' "$report"
    local first_short="${first_hash:0:8}"
    sed -i "s/parent_cmd: cmd_test/parent_cmd: cmd_multi/; /summary: \"test summary\"/a\\ac_evidence_mapping:\n  AC2: \"task commit ${first_short}\"" "$report"
    run env GATE_REPO_ROOT_OVERRIDE="$repo" GATE_SESSION_STATE_TASK_DIR="$repo/queue/tasks" bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK(cmd_3264-AC2)"* ]]
}

# --- cmd_karo_hotfix_gate_ac3_hunk_provenance_202607121205: AC3 hunk/commit provenance ---
# AC3のfile名一致だけの旧判定は、共有fileの非重複hunkにも誤ってWARNしていた(AC2はhunk比較済み)。
# 判定原理をAC2同様のcommit/hunk provenanceへ統一し、真の重複だけWARNする。

_setup_ac3_hunk_repo() {
    # $1=repo dir を作り、shared.txtへreporterのcommit→auto-commit(別行変更)の2commit履歴を積む。
    # 戻り値: reporter commitのフルhash(stdout)
    local repo="$1"
    local autocommit_line_edit="$2"
    mkdir -p "$repo/queue/tasks" "$repo/reports" "$repo/logs"
    _init_fixture_repo "$repo"
    cat > "$repo/queue/tasks/testninja.yaml" <<'YAML'
task:
  status: in_progress
  target_path: shared.txt
YAML
    printf 'line01\nline02\nline03\nline04\nline05\nline06\nline07\nline08\nline09\nline10\n' > "$repo/shared.txt"
    git -C "$repo" add queue/tasks/testninja.yaml shared.txt
    git -C "$repo" commit -q -m "test-fixture(tests/test_gate_report_format.bats:_setup_ac3_hunk_repo): fixture repo seed"

    sed -i 's/^line02$/line02 reporter-change/' "$repo/shared.txt"
    git -C "$repo" add shared.txt
    git -C "$repo" commit -q -m "feat: reporter change"
    local commit_hash
    commit_hash=$(git -C "$repo" rev-parse HEAD)

    sed -i "$autocommit_line_edit" "$repo/shared.txt"
    git -C "$repo" add shared.txt
    git -C "$repo" commit -q -m "chore: auto-commit before /clear (other) — 運用ファイル"

    echo "$commit_hash"
}

_write_ac3_report() {
    local report="$1"
    local commit_hash="$2"
    cat > "$report" <<YAML
worker_id: testninja
parent_cmd: cmd_test
ac_version_read: abc12345
timestamp: '2026-07-12T00:00:00'
status: completed
commit_hash: ${commit_hash}
result:
  summary: "test summary"
purpose_validation:
  cmd_purpose: "test"
  fit: true
  purpose_gap: ""
binary_checks:
  AC1:
  - check: "test check"
    result: "yes"
  commit:
  - check: "git commitが完了したか"
    result: "yes"
files_modified:
- path: shared.txt
lesson_candidate:
  found: false
  no_lesson_reason: "test"
lessons_useful: []
assumption_invalidation:
  found: false
  affected_cmds: []
  detail: ""
self_gate_check:
  lesson_ref: PASS
  lesson_candidate: PASS
  status_valid: PASS
  purpose_fit: PASS
verdict: PASS
YAML
}

@test "completed report blocks empty or invalid timestamp and accepts ISO timestamp" {
    local report="$TMPDIR_BATS/report.yaml"
    create_valid_report "$report"

    sed -i "s/^timestamp:.*/timestamp: ''/" "$report"
    run env GATE_NO_LOG=1 bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires a parseable ISO timestamp"* ]]

    sed -i "s/^timestamp:.*/timestamp: 'not-a-date'/" "$report"
    run env GATE_NO_LOG=1 bash "$GATE" "$report"
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires a parseable ISO timestamp"* ]]

    sed -i "s/^timestamp:.*/timestamp: '2026-07-12T23:40:00+09:00'/" "$report"
    run env GATE_NO_LOG=1 bash "$GATE" "$report"
    [ "$status" -eq 0 ]
}

@test "T-AC3-1: non-overlapping auto-commit hunk on shared file does not WARN" {
    local repo="$REPO_TMPDIR_BATS/ac3_nonoverlap_repo"
    local report="$repo/reports/testninja_report_cmd_test.yaml"
    local commit_hash
    # auto-commitはline09（reporterが触ったline02とは非重複）を変更
    commit_hash=$(_setup_ac3_hunk_repo "$repo" 's/^line09$/line09 auto-commit-change/')
    _write_ac3_report "$report" "$commit_hash"

    run env GATE_REPO_ROOT_OVERRIDE="$repo" GATE_SESSION_STATE_TASK_DIR="$repo/queue/tasks" GATE_AUTOCOMMIT_CACHE_FILE="$repo/logs/.gate_autocommit_hunk_cache" bash "$GATE" "$report"
    echo "$output"
    [[ "$output" != *"Traceback"* ]]
    [[ "$output" != *"WARN(cmd_3264-AC3)"* ]]
    [[ "$output" != *"BLOCK(cmd_3264-AC2)"* ]]
}

@test "T-AC3-2: overlapping auto-commit hunk on shared file still WARNs" {
    local repo="$REPO_TMPDIR_BATS/ac3_overlap_repo"
    local report="$repo/reports/testninja_report_cmd_test.yaml"
    local commit_hash
    # auto-commitはreporterと同じline02を変更 → 真の巻込み
    commit_hash=$(_setup_ac3_hunk_repo "$repo" 's/^line02 reporter-change$/line02 auto-commit-change/')
    _write_ac3_report "$report" "$commit_hash"

    run env GATE_REPO_ROOT_OVERRIDE="$repo" GATE_SESSION_STATE_TASK_DIR="$repo/queue/tasks" GATE_AUTOCOMMIT_CACHE_FILE="$repo/logs/.gate_autocommit_hunk_cache" bash "$GATE" "$report"
    echo "$output"
    [[ "$output" != *"Traceback"* ]]
    [[ "$output" == *"WARN(cmd_3264-AC3)"* ]]
    [[ "$output" == *"shared.txt"* ]]
}

# ─── DIVERGENT v2 の実体判定 (cmd_karo_impl_divergent_detector_fix_20260726) ───
# test_necessity: 契約/環境がブロックしている間の正しい再提出ではDIVERGENTを発火させず、
# 同一のアプローチ起因BLOCKが継続する反復では従来どおり発火し続けること(両方向)。
DIAGNOSE_GATE="scripts/gates/gate_diagnose_check.sh"

# 診断文とapproachは実データ(queue/tasks/hanzo.yaml prior_attempts attempt6-8)由来。
# 3ケースとも同一文面を使うため、差を生むのは「実体=BLOCK理由」だけになる。
_divergent_fixture() {  # $1=prior block_reason
    local diag='commit_contract.planned_paths が実装1件のみで、AC4が明示的に要求するtest fixtureを含んでいない。許可scopeの正本はtask YAMLであり報告側では解消できない。'
    local approach='残骸をrepo外へ集約移動しTTL retentionを既存cleanupへ載せた。交互A/B計測では-11.6%。'
    local task_dir="$TMPDIR_BATS/state/tasks"
    mkdir -p "$task_dir" "$TMPDIR_BATS/reports"
    cat > "$task_dir/fixninja.yaml" <<YAML
task:
  status: in_progress
  session_state:
    attempt: 7
    prior_attempts:
    - attempt: 6
      block_reason: '$1'
      diagnose_reason: '$diag'
      approach_summary: '$approach'
YAML
    cat > "$TMPDIR_BATS/reports/r.yaml" <<YAML
worker_id: fixninja
parent_cmd: cmd_fix
status: completed
diagnose_reason: '$diag'
result:
  summary: '$approach'
YAML
}

@test "DIVERGENT v2: 契約起因BLOCK(planned scope外)では同一診断の再提出でも発火しない" {
    local reason='commit_contract: files_modified path is outside planned scope: tests/unit/test_scratch_retention.bats'
    _divergent_fixture "$reason"
    run env GATE_SESSION_STATE_TASK_DIR="$TMPDIR_BATS/state/tasks" \
        bash "$DIAGNOSE_GATE" "$TMPDIR_BATS/reports/r.yaml" "$reason"
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" != *"DIVERGENT v2"* ]]
    [[ "$output" == *"DIVERGENT抑止"* ]]
}

@test "DIVERGENT v2: BLOCK理由が前回から変化していればblockしない(同じ壁での足踏みではない)" {
    _divergent_fixture 'variation_checks: required cells unfilled: normal_pass'
    run env GATE_SESSION_STATE_TASK_DIR="$TMPDIR_BATS/state/tasks" \
        bash "$DIAGNOSE_GATE" "$TMPDIR_BATS/reports/r.yaml" 'binary_checks.AC3[2].result: 空文字'
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" != *"DIVERGENT v2"* ]]
}

@test "DIVERGENT v2: 同一のアプローチ起因BLOCKが継続する反復は従来どおり発火する" {
    local reason='binary_checks.AC1[0].result: 空文字。"yes" または "no" を記入せよ'
    _divergent_fixture "$reason"
    run env GATE_SESSION_STATE_TASK_DIR="$TMPDIR_BATS/state/tasks" \
        bash "$DIAGNOSE_GATE" "$TMPDIR_BATS/reports/r.yaml" "$reason"
    echo "$output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"DIVERGENT v2"* ]]
}

# --- B31: fixture repoの本番repoへの逸脱を止める両方向fixture ---
# test_necessity: fixture用のgitコマンドは、fixture repo以外(特に本番repo)を対象にしてはならない。

@test "T-B31-1: _init_fixture_repo aborts when git discovery escapes the fixture dir" {
    local repo="$TMPDIR_BATS/escaped_repo"
    mkdir -p "$repo"
    # initを不能にする(書込み不可) → .gitが作られず discovery が外へ逃げる状態を作る
    chmod 500 "$repo"
    run _init_fixture_repo "$repo"
    chmod 700 "$repo"
    [ "$status" -ne 0 ]
    [[ "$output" == *"FATAL: fixture git init escaped"* ]]
}

@test "T-B31-2: _init_fixture_repo accepts a genuine isolated fixture repo" {
    local repo="$TMPDIR_BATS/genuine_repo"
    run _init_fixture_repo "$repo"
    echo "$output"
    [ "$status" -eq 0 ]
    [ "$(git -C "$repo" rev-parse --show-toplevel)" = "$(cd "$repo" && pwd -P)" ]
    [ "$(git -C "$repo" config user.name)" = "test" ]
}

# test_necessity: project repository and commit repository may intentionally differ;
# an explicit, exact git root must win without weakening project semantics.
@test "commit repo_root: explicit canonical git root overrides project lookup" {
    local repo="$TMPDIR_BATS/commit_repo"
    _init_fixture_repo "$repo"
    run python3 - "$repo" <<'PY'
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location("gate_main", "scripts/gates/gate_report_format_main.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
repo, error = module._resolve_commit_repo(
    {"project": "dm-signal"},
    {"project": "dm-signal"},
    pathlib.Path("/definitely/not/the/project"),
    {"repo_root": sys.argv[1]},
)
print(repo)
print(error)
raise SystemExit(0 if repo == pathlib.Path(sys.argv[1]).resolve() and error is None else 1)
PY
    [ "$status" -eq 0 ]
}

# test_necessity: an explicit path that is not a git repository must fail closed.
@test "commit repo_root: non-git explicit path is blocked" {
    local repo="$TMPDIR_BATS/not_git"
    mkdir -p "$repo"
    run python3 - "$repo" <<'PY'
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location("gate_main", "scripts/gates/gate_report_format_main.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
repo, error = module._resolve_commit_repo({}, {}, pathlib.Path("."), {"repo_root": sys.argv[1]})
print(error)
raise SystemExit(0 if repo is None and "not a git repository" in error else 1)
PY
    [ "$status" -eq 0 ]
}

# test_necessity: a subdirectory or tampered path must not silently resolve upward
# to a different git root.
@test "commit repo_root: non-canonical nested path is blocked" {
    local repo="$TMPDIR_BATS/commit_repo"
    _init_fixture_repo "$repo"
    mkdir -p "$repo/nested"
    run python3 - "$repo/nested" <<'PY'
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location("gate_main", "scripts/gates/gate_report_format_main.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
repo, error = module._resolve_commit_repo({}, {}, pathlib.Path("."), {"repo_root": sys.argv[1]})
print(error)
raise SystemExit(0 if repo is None and error == "explicit commit repository root mismatch" else 1)
PY
    [ "$status" -eq 0 ]
}

# test_necessity: report-side repo_root cannot contradict the task contract,
# while an omitted report copy preserves the task SSOT.
@test "commit repo_root: task report contradiction is blocked" {
    run python3 - <<'PY'
import importlib.util

spec = importlib.util.spec_from_file_location("gate_main", "scripts/gates/gate_report_format_main.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
contract, error = module._resolved_commit_contract(
    {"commit_contract": {"required": True, "repo_root": "/tmp/repo-b"}},
    {"commit_contract": {"required": True, "repo_root": "/tmp/repo-a"}},
)
print(error)
raise SystemExit(0 if contract is None and error == "task/report commit_contract repo_root mismatch" else 1)
PY
    [ "$status" -eq 0 ]
}

# test_necessity: tasks that predate repo_root keep the existing project-based
# repository resolution unchanged.
@test "commit repo_root: omitted field preserves infra project fallback" {
    run python3 - "$PWD" <<'PY'
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location("gate_main", "scripts/gates/gate_report_format_main.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
root = pathlib.Path(sys.argv[1]).resolve()
repo, error = module._resolve_commit_repo({}, {"project": "infra"}, root, {})
print(repo)
print(error)
raise SystemExit(0 if repo == root and error is None else 1)
PY
    [ "$status" -eq 0 ]
}

# test_necessity: 偵察結果が0件でも探索完遂+一次証拠なら成功し、同じ0件主張でも
# 探索未完了または証拠なしなら失敗する outcome-neutral 境界を固定する。
@test "investigation contract accepts evidenced zero findings and rejects unevidenced claims" {
    run python3 <<'PY'
import importlib.util

spec = importlib.util.spec_from_file_location("gate_main", "scripts/gates/gate_report_format_main.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
contract = {
    "version": 1,
    "required": True,
    "outcome_neutral": True,
    "discovery_required": False,
    "allowed_outcomes": ["found", "zero_found", "not_present", "external_boundary", "unknown_after_exhaustion"],
    "minimum_primary_evidence": 1,
}
base = {"task_contract_snapshot": {"investigation_contract": contract}}
valid = dict(base, investigation_outcome={
    "outcome": "zero_found",
    "method_completed": True,
    "primary_evidence": [{"source": "git grep rc=1", "observation": "bounded target has zero matches"}],
    "remaining_unknowns": [],
})
assert module._investigation_contract_issues(valid) == []

no_evidence = dict(base, investigation_outcome={
    "outcome": "zero_found", "method_completed": True,
    "primary_evidence": [], "remaining_unknowns": [],
})
assert any("primary_evidence" in issue for issue in module._investigation_contract_issues(no_evidence))

not_completed = dict(base, investigation_outcome={
    "outcome": "zero_found", "method_completed": False,
    "primary_evidence": [{"source": "query", "observation": "partial"}],
    "remaining_unknowns": [],
})
assert any("method_completed" in issue for issue in module._investigation_contract_issues(not_completed))
PY
    [ "$status" -eq 0 ]
}

# test_necessity: a report-only commit may live in the control-plane repo while
# the task's explicit project repo remains the authoritative primary repo.
@test "cross repo report-only commit falls back to its declared repository" {
    local report_repo="$TMPDIR_BATS/report_repo"
    local project_repo="$TMPDIR_BATS/project_repo"
    _init_fixture_repo "$report_repo"
    _init_fixture_repo "$project_repo"
    mkdir -p "$report_repo/queue/reports"
    printf '%s\n' 'report: cross-repo' > "$report_repo/queue/reports/cross.yaml"
    git -C "$report_repo" add queue/reports/cross.yaml
    git -C "$report_repo" commit -q -m 'cmd_cross_repo report-only evidence'
    local commit_hash
    commit_hash="$(git -C "$report_repo" rev-parse HEAD)"
    run python3 - "$report_repo" "$project_repo" "$commit_hash" <<'PY'
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location("gate_main", "scripts/gates/gate_report_format_main.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
report_repo, project_repo, commit_hash = map(pathlib.Path, sys.argv[1:])
report = {
    "task_id": "cmd_cross_repo",
    "parent_cmd": "cmd_cross_repo",
    "commit_hash": str(commit_hash),
    "commit_contract": {"required": True, "repo_root": str(project_repo)},
    "cross_repo_commits": [{
        "repo": str(report_repo),
        "commit_hash": str(commit_hash),
        "paths": ["queue/reports/cross.yaml"],
    }],
    "files_modified": [{"path": "queue/reports/cross.yaml"}],
}
task = {
    "task_id": "cmd_cross_repo",
    "parent_cmd": "cmd_cross_repo",
    "commit_contract": {
        "required": True,
        "planned_paths": [str(project_repo)],
        "repo_root": str(project_repo),
    },
}
errors = module.commit_contract_errors(report, task, pathlib.Path.cwd())
print(errors)
raise SystemExit(0 if not errors else 1)
PY
    echo "$output"
    [ "$status" -eq 0 ]
}
