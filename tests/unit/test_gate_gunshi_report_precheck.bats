#!/usr/bin/env bats
# test_necessity: 軍師precheckは報告のbinary contract欠落と不正な完了判定をレビュー前にBLOCKする。
# test_necessity: SG-PRE3Xは共有cross-repo契約で所有repoを解決し、有効な外部repo成果の偽BLOCKを防ぎつつ不正repo/commit/path/primary矛盾をfail-closedに保つ。
# test_necessity: precheckがCLEARと予測した報告はcmd_complete_gateのparent_cmd_contract/ac_version_stale/lesson_feedback_set_mismatchのいずれでもBLOCKされない（判定関数が同一）。
# test_necessity: SG-PRE20はshared lesson-feedback-setのOK接頭辞付き成功結果をPASSとして扱い、MISMATCHのERROR/WARN契約を維持する。

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ENGINE="$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck_engine.py"
  TMP_DIR="$(mktemp -d)"
  mkdir -p "$TMP_DIR/tasks"
  cat > "$TMP_DIR/tasks/kagemaru.yaml" <<'YAML'
task:
  binary_checks:
    AC1:
      - check: concrete check
        result: yes
YAML
}

# test_necessity: report review must compare ac_version_read with the immutable
# report.parent_cmd contract, not the worker's mutable next-assignment lease.
@test "ac_version check accepts completed reports after worker redeployment" {
  cat > "$TMP_DIR/tasks/saizo.yaml" <<'YAML'
task:
  parent_cmd: cmd_4277
  task_id: cmd_4277_full
  ac_version: cf5a1428
  binary_checks: {AC1: [{result: yes}]}
YAML
  for old_cmd in cmd_4274 cmd_karo_dashboard_freshness_speed; do
    case "$old_cmd" in
      cmd_4274) old_ac=b4003b4b; old_task=cmd_4274_full ;;
      cmd_karo_dashboard_freshness_speed) old_ac=816b63f9; old_task=cmd_karo_dashboard_freshness_speed_normal ;;
    esac
    cat > "$TMP_DIR/report.yaml" <<YAML
worker_id: saizo
parent_cmd: $old_cmd
task_id: $old_task
ac_version_read: $old_ac
task_contract_snapshot:
  parent_cmd: $old_cmd
  task_id: $old_task
  issued_cmd_id: $old_cmd
  ac_fingerprint: $old_ac
  purpose: completed old command
  project: infra
  acceptance_criteria: [{id: AC1}]
binary_checks: {AC1: [{result: yes}]}
YAML
    run python3 "$ENGINE" --report "$TMP_DIR/report.yaml" --tasks-dir "$TMP_DIR/tasks"
    [ "$status" -eq 0 ]
    [[ "$output" == *"AC_VERSION_MSG='  PASS: ac_version一致 ($old_ac) source=report.parent_cmd contract'"* ]]
  done
}

teardown() {
  find "$TMP_DIR" -depth -delete
}

run_engine() {
  local assumption_check="$1"
  local completion_evidence="${2:-}"
  cat > "$TMP_DIR/report.yaml" <<YAML
worker_id: kagemaru
parent_cmd: cmd_fixture
assumption_check: "$assumption_check"
result:
  details: "$completion_evidence"
task_clarity:
  score: 100
  unclear_points: なし
  discretion_fills: なし
binary_checks:
  AC1:
    - check: concrete check
      result: yes
YAML
  run python3 "$ENGINE" --report "$TMP_DIR/report.yaml" --tasks-dir "$TMP_DIR/tasks"
}

make_git_repo() {
  local repo="$1" path="$2"
  mkdir -p "$repo/$(dirname "$path")"
  git -C "$repo" init -q
  git -C "$repo" config user.email fixture@example.invalid
  git -C "$repo" config user.name fixture
  printf 'fixture\n' > "$repo/$path"
  git -C "$repo" add "$path"
  git -C "$repo" commit -qm fixture
  git -C "$repo" rev-parse HEAD
}

run_cross_repo_precheck() {
  run env GUNSHI_PRECHECK_ONLY=SG-PRE3X \
    GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" \
    bash "$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh" "$TMP_DIR/report.yaml"
}

run_contract_precheck() {
  run env GUNSHI_PRECHECK_ONLY=SG-PRE10 \
    GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" \
    bash "$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh" "$TMP_DIR/report.yaml"
}

run_sg_pre20() {
  run env GUNSHI_PRECHECK_ONLY=SG-PRE20 \
    GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" \
    bash "$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh" "$TMP_DIR/report.yaml"
}

@test "SG-PRE20 accepts shared OK prefix with contract counts" {
  cat > "$TMP_DIR/tasks/kagemaru.yaml" <<'YAML'
task:
  parent_cmd: cmd_fixture
  related_lessons:
    - id: L100
YAML
  cat > "$TMP_DIR/report.yaml" <<'YAML'
worker_id: kagemaru
parent_cmd: cmd_fixture
lessons_useful:
  - id: L100
    useful: true
YAML

  run_sg_pre20
  [[ "$output" == *"■ SG-PRE20: related_lessons+lessons_useful整合"* ]]
  [[ "$output" == *"PASS: related_lessons="*" lessons_useful=1 set=OK mode=subset allowed=1 reported=1"* ]]
  [[ "$output" != *"ERROR: lessons_useful集合がtask契約と不一致 → GATE BLOCK確実: OK mode=subset"* ]]
}

make_source_context_fixture() {
  local source="$1" mode="${2:-clear}" generation="${3:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
  mkdir -p "$source/scripts/gates" "$source/context" "$source/docs/research" "$source/config" "$source/external/docs/research"
  cp "$REPO_ROOT/scripts/gates/gate_vercel_phase.sh" "$source/scripts/gates/"
  printf 'projects:\n  - id: external\n    path: %s\n' "$source/external" > "$source/config/projects.yaml"
  local i
  for i in $(seq 1 11); do
    printf 'fixture %s\n' "$i" > "$source/external/docs/research/ref-$i.md"
  done
  if [ "$mode" = broken ]; then
    printf '%s\n' 'See docs/research/does-not-exist.md' > "$source/context/owned.md"
  else
    : > "$source/context/owned.md"
    for i in $(seq 1 11); do
      printf 'See docs/research/ref-%s.md\n' "$i" >> "$source/context/owned.md"
    done
  fi
  git -C "$source" init -q
  git -C "$source" config user.email fixture@example.invalid
  git -C "$source" config user.name fixture
  git -C "$source" add .
  git -C "$source" commit -qm "source context fixture"
  printf '%s\n' "$generation"
}

write_source_task_and_report() {
  local source="$1" generation="$2" marker="$3"
  local source_sha
  source_sha="$(git -C "$source" rev-parse HEAD)"
  cat > "$marker" <<JSON
{"version":1,"state":"active","generation":"$generation","task_id":"cmd_fixture_full","worktree":"$source"}
JSON
  cat > "$TMP_DIR/tasks/kagemaru.yaml" <<YAML
task:
  task_id: cmd_fixture_full
  parent_cmd: cmd_fixture
  project: infra
  task_worktree_required: "true"
  task_worktree_path: $source
  task_worktree_workdir: $source
  task_worktree_generation: $generation
  task_worktree_marker: $marker
  task_worktree_status: active
YAML
  cat > "$TMP_DIR/report.yaml" <<YAML
worker_id: kagemaru
parent_cmd: cmd_fixture
commit_hash: $source_sha
files_modified:
  - {path: context/owned.md, change: source-generation fixture}
YAML
}

# test_necessity: SG-PRE23 must measure context links from the reviewed source
# generation. A clear shared checkout cannot hide a broken source worktree.
@test "SG-PRE23 resolves source generation and rejects mixed shared/source results" {
  local source="$TMP_DIR/source-clear" shared="$TMP_DIR/shared-broken"
  local generation="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  mkdir -p "$shared/scripts/gates" "$shared/context" "$shared/docs/research" "$shared/config" "$shared/external/docs/research"
  cp "$REPO_ROOT/scripts/gates/gate_vercel_phase.sh" "$shared/scripts/gates/"
  printf 'projects:\n  - id: external\n    path: %s\n' "$shared/external" > "$shared/config/projects.yaml"
  printf 'See docs/research/shared-clear.md\n' > "$shared/context/owned.md"
  printf 'ok\n' > "$shared/external/docs/research/shared-clear.md"
  run env VERCEL_PHASE_SKIP_CANDIDATE_SUGGESTIONS=1 bash "$shared/scripts/gates/gate_vercel_phase.sh" "$shared/context/owned.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"refs checked, all exist"* ]]

  make_source_context_fixture "$source" clear "$generation" >/dev/null
  marker="$TMP_DIR/source.marker"
  write_source_task_and_report "$source" "$generation" "$marker"
  run env GUNSHI_PRECHECK_ONLY=SG-PRE23 \
    GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" \
    VERCEL_PHASE_SKIP_CANDIDATE_SUGGESTIONS=1 \
    bash "$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh" "$TMP_DIR/report.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"source_context_status=SOURCE"* ]]
  [[ "$output" == *"11 refs checked, all exist"* ]]
  [[ "$output" == *"source generation context references are clear"* ]]

  make_source_context_fixture "$source" broken "$generation" >/dev/null
  write_source_task_and_report "$source" "$generation" "$marker"
  run env VERCEL_PHASE_SKIP_CANDIDATE_SUGGESTIONS=1 bash "$source/scripts/gates/gate_vercel_phase.sh" "$source/context/owned.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"1 broken refs found"* ]]

  run env GUNSHI_PRECHECK_ONLY=SG-PRE23 \
    GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" \
    VERCEL_PHASE_SKIP_CANDIDATE_SUGGESTIONS=1 \
    bash "$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh" "$TMP_DIR/report.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"source generation has broken refs"* ]]
}

# test_necessity: a task-worktree generation mismatch is an unresolved source
# identity and must fail closed before any context reference result is used.
@test "SG-PRE23 blocks unresolved task-worktree generation" {
  local source="$TMP_DIR/source-mismatch" marker="$TMP_DIR/source-mismatch.marker"
  local generation="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  make_source_context_fixture "$source" clear "$generation" >/dev/null
  write_source_task_and_report "$source" "$generation" "$marker"
  sed -i 's/task_worktree_generation: .*/task_worktree_generation: cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc/' "$TMP_DIR/tasks/kagemaru.yaml"
  run env GUNSHI_PRECHECK_ONLY=SG-PRE23 \
    GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" \
    bash "$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh" "$TMP_DIR/report.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"task_worktree_marker_generation_mismatch"* ]]
}

@test "shared contract blocks stale task ac_version before CLEAR prediction" {
  cat > "$TMP_DIR/tasks/kagemaru.yaml" <<'YAML'
task:
  parent_cmd: cmd_fixture
  ac_version: deadbeef
  acceptance_criteria:
    - id: AC1
      description: stable fixture contract
YAML
  cat > "$TMP_DIR/report.yaml" <<'YAML'
worker_id: kagemaru
parent_cmd: cmd_fixture
lessons_useful: []
YAML

  run_contract_precheck
  [ "$status" -ne 0 ]
  [[ "$output" == *"ac_version_stale:task=deadbeef"* ]]
  [[ "$output" == *"GATE_PREDICTION=BLOCK"* ]]
}

@test "shared contract blocks lesson feedback extras before CLEAR prediction" {
  cat > "$TMP_DIR/tasks/kagemaru.yaml" <<'YAML'
task:
  parent_cmd: cmd_fixture
  related_lessons:
    - id: L100
YAML
  cat > "$TMP_DIR/report.yaml" <<'YAML'
worker_id: kagemaru
parent_cmd: cmd_fixture
lessons_useful:
  - id: L404
    useful: false
YAML

  run_contract_precheck
  [ "$status" -ne 0 ]
  [[ "$output" == *"lesson_feedback_set_mismatch:MISMATCH mode=subset"* ]]
  [[ "$output" == *"extra=L404"* ]]
  [[ "$output" == *"GATE_PREDICTION=BLOCK"* ]]
}

@test "shared contract blocks invalid numeric parent_cmd_contract before CLEAR prediction" {
  cat > "$TMP_DIR/tasks/kagemaru.yaml" <<'YAML'
task:
  parent_cmd: cmd_999999
YAML
  cat > "$TMP_DIR/report.yaml" <<'YAML'
worker_id: kagemaru
parent_cmd: cmd_999999
lessons_useful: []
YAML

  run_contract_precheck
  [ "$status" -ne 0 ]
  [[ "$output" == *"parent_cmd_contract: BLOCK:"* ]]
  [[ "$output" == *"parent_ssot_missing"* ]]
  [[ "$output" == *"GATE_PREDICTION=BLOCK"* ]]
}

# test_necessity: no-hashの同一repo/parent_cmd git走査はHEAD世代とparent_cmdを
# cache keyへ含め、報告本文の変化では再走査せず、commit世代またはcmd変更では再計測する不変量。
@test "no-hash batch git lookup reuses same committed-history generation" {
  gate="$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh"
  cache="$TMP_DIR/batch-git-cache"
  trace="$TMP_DIR/batch-git-trace"
  cat > "$TMP_DIR/tasks/kagemaru.yaml" <<'YAML'
task:
  project: infra
  parent_cmd: cmd_fixture
  planned_paths: [scripts/gates/gate_gunshi_report_precheck.sh]
YAML
  cat > "$TMP_DIR/report.yaml" <<'YAML'
worker_id: kagemaru
parent_cmd: cmd_fixture
command: tests/unit/not_target.bats
files_modified:
  - {path: scripts/gates/gate_gunshi_report_precheck.sh, change: fixture}
binary_checks:
  AC1:
    - {check: fixture, result: yes}
YAML

  run env GUNSHI_BATCH_GIT_CACHE_DIR="$cache" \
    GUNSHI_BATCH_GIT_CACHE_TRACE_FILE="$trace" \
    GUNSHI_PRECHECK_CACHE_DIR="$TMP_DIR/full-cache-1" \
    GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" \
    GUNSHI_PRECHECK_ONLY=SG-PRE25 \
    bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -ne 0 ]
  grep -q '^miss:parent_numstat$' "$trace"
  grep -q '^miss:recent_data$' "$trace"

  run env GUNSHI_BATCH_GIT_CACHE_DIR="$cache" \
    GUNSHI_BATCH_GIT_CACHE_TRACE_FILE="$trace" \
    GUNSHI_PRECHECK_CACHE_DIR="$TMP_DIR/full-cache-2" \
    GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" \
    GUNSHI_PRECHECK_ONLY=SG-PRE25 \
    bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -ne 0 ]
  grep -q '^hit:parent_numstat$' "$trace"
  grep -q '^hit:recent_data$' "$trace"

  sed -i 's/parent_cmd: cmd_fixture/parent_cmd: cmd_fixture_changed/g' "$TMP_DIR/report.yaml"
  run env GUNSHI_BATCH_GIT_CACHE_DIR="$cache" \
    GUNSHI_BATCH_GIT_CACHE_TRACE_FILE="$trace" \
    GUNSHI_PRECHECK_CACHE_DIR="$TMP_DIR/full-cache-3" \
    GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" \
    GUNSHI_PRECHECK_ONLY=SG-PRE25 \
    bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -ne 0 ]
  [ "$(grep -c '^miss:parent_numstat$' "$trace")" -ge 2 ]
  [ "$(find "$cache" -type f | wc -l)" -ge 2 ]
}

@test "SG-PRE3 no-code exemption requires matching structured task and report contracts" {
  cat > "$TMP_DIR/tasks/kagemaru.yaml" <<'YAML'
task:
  task_type: recon
  commit_contract:
    required: false
    task_type: recon
YAML
  cat > "$TMP_DIR/report.yaml" <<'YAML'
worker_id: kagemaru
parent_cmd: cmd_fixture
task_type: recon
files_modified: [{path: docs/nonexistent-recon-output.md}]
commit_contract:
  required: false
  task_type: recon
YAML
  run python3 "$ENGINE" --report "$TMP_DIR/report.yaml" --tasks-dir "$TMP_DIR/tasks"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NO_CODE_COMMIT_EXEMPT=1"* ]]

  sed -i 's/task_type: recon/task_type: impl/' "$TMP_DIR/report.yaml"
  run python3 "$ENGINE" --report "$TMP_DIR/report.yaml" --tasks-dir "$TMP_DIR/tasks"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NO_CODE_COMMIT_EXEMPT=0"* ]]
}

@test "SG-PRE3X resolves valid external and primary reports and blocks invalid ownership contracts" {
  external="$TMP_DIR/external"
  hash="$(make_git_repo "$external" backend/app.py)"

  cat > "$TMP_DIR/report.yaml" <<YAML
worker_id: kagemaru
parent_cmd: cmd_fixture
commit_hash: $hash
files_modified: [{path: backend/app.py}]
cross_repo_commits:
  - repo: $external
    commit_hash: $hash
    paths: [backend/app.py]
YAML
  run_cross_repo_precheck
  [ "$status" -eq 0 ]
  [[ "$output" == *"backend/app.py → $external@$hash"* ]]

  primary_hash="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  cat > "$TMP_DIR/report.yaml" <<YAML
worker_id: kagemaru
parent_cmd: cmd_fixture
commit_hash: $primary_hash
YAML
  run_cross_repo_precheck
  [ "$status" -eq 0 ]
  [[ "$output" == *"primary repo commit resolved: $primary_hash"* ]]

  for mutation in unknown_repo missing_commit path_mismatch primary_conflict; do
    bad_repo="$external"
    bad_hash="$hash"
    bad_path="backend/app.py"
    primary="$hash"
    case "$mutation" in
      unknown_repo) bad_repo="$TMP_DIR/not-a-repo" ;;
      missing_commit) bad_hash="0000000000000000000000000000000000000000"; primary="$bad_hash" ;;
      path_mismatch) bad_path="backend/missing.py" ;;
      primary_conflict) primary="1111111111111111111111111111111111111111" ;;
    esac
    cat > "$TMP_DIR/report.yaml" <<YAML
worker_id: kagemaru
parent_cmd: cmd_fixture
commit_hash: $primary
files_modified: [{path: $bad_path}]
cross_repo_commits:
  - repo: $bad_repo
    commit_hash: $bad_hash
    paths: [$bad_path]
YAML
    run_cross_repo_precheck
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK:"* ]]
  done
}

@test "LG043 ignores completed negative expression for unverified assumptions" {
  run_engine "未確認前提なし"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
}

@test "LG043 ignores completed negative expression for unresolved items" {
  run_engine "未解決事項なし"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
}

@test "LG043 ignores a resolved historical state only with completion evidence" {
  run_engine "対象は未解決だったが既存原則に包含" "target status=resolved"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
  [[ "$output" == *"GATE_PREDICTION=CLEAR"* ]]
}

@test "LG043 blocks a historical unresolved phrase without completion evidence" {
  run_engine "対象は未解決だったがresolve可能"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
  [[ "$output" == *"GATE_PREDICTION=BLOCK"* ]]
}

@test "LG043 ignores completed zero-count confirmation" {
  run_engine "未確認0を確認"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
}

@test "LG043 ignores bare zero-count completion at end of L-axis report" {
  run_engine "route母集団21と表21を機械比較して未確認0"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
  [[ "$output" == *"GATE_PREDICTION=CLEAR"* ]]
  [[ "$output" == *"GATE_PREDICTION_WITH_SHELL_FINDINGS=BLOCK"* ]]
}

@test "LG043 ignores bare zero-count completion before whitespace and punctuation" {
  for expression in "未確認0 " "未確認0。" "未確認0、次項も完了"; do
    run_engine "$expression"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
  done
}

@test "LG043 blocks bare zero-count followed by remaining work" {
  run_engine "未確認0だが残作業あり"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
  [[ "$output" == *"GATE_PREDICTION=BLOCK"* ]]
}

@test "LG043 ignores no-route completion expression" {
  run_engine "未確認routeなし"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
}

@test "LG043 ignores quoted conditional AC requirement" {
  run_engine "AC要件は未確認が1件でもあればBLOCK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
}

@test "LG043 keeps blocking actual unverified work" {
  run_engine "本番動作は未確認"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
  [[ "$output" == *"BC_YES_CLARITY_TERMS="*"未確認"* ]]
}

@test "LG043 keeps blocking actual incomplete work" {
  run_engine "実装は未完了"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
  [[ "$output" == *"BC_YES_CLARITY_TERMS="*"未完了"* ]]
}

@test "LG043 keeps blocking deferred work" {
  run_engine "確認を保留"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
  [[ "$output" == *"BC_YES_CLARITY_TERMS="*"保留"* ]]
}

@test "LG043 keeps blocking delegation to karo" {
  run_engine "残作業は家老が実施"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
  [[ "$output" == *"BC_YES_CLARITY_TERMS="*"家老が実施"* ]]
}

# test_necessity: 時間窓分類はAC未達ではない一方、真の未完了はBLOCKする不変量。
@test "LG043 ignores temporal-window classifications only" {
  for expression in "2026未完了当年102 PF年は確定年から分離" "未完了年度は別集計" "進行中月は対象外" "判明したのは実行後であり、事前検証不可能だった"; do
    run_engine "$expression"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
  done
}

# test_necessity: 分布母集団からの未完了task除外は業務未完了ではない一方、
# 同じ文脈の実作業未完了はBLOCKする不変量。
@test "LG043 distinguishes population exclusion from incomplete work" {
  run_engine "未完了の現taskは分布から除外した"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=0"* ]]
  [[ "$output" == *"GATE_PREDICTION=CLEAR"* ]]

  run_engine "実装未完了の現taskは分布から除外した"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
  [[ "$output" == *"GATE_PREDICTION=BLOCK"* ]]
}

@test "LG043 keeps blocking concrete incomplete, deferred, and delegated work" {
  for expression in "作業未完了" "検証未完了" "後で実施" "家老へ委譲し、家老が実施"; do
    run_engine "$expression"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BC_YES_CLARITY_CONTRADICTION=1"* ]]
    [[ "$output" == *"GATE_PREDICTION=BLOCK"* ]]
  done
}

@test "SG-PRE35 blocks unclassified new test and accepts necessity plus control groups" {
  gate="$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh"
  task="$TMP_DIR/tasks/kagemaru.yaml"
  printf 'worker_id: kagemaru\nparent_cmd: cmd_fixture\n' > "$TMP_DIR/report.yaml"

  printf 'task:\n  project: infra\n  planned_paths: [tests/unit/test_never_existing_contract.bats]\n' > "$task"
  run env GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"omits transient deletion evidence: tests/unit/test_never_existing_contract.bats"* ]]

  cat > "$task" <<'YAML'
task:
  project: infra
  planned_paths: [tests/unit/test_never_existing_contract.bats, scripts/deploy_task.sh]
  test_necessity:
    defense_target: deployment rejects tests without unique production defense
    overlap_evidence: existing tests and added commit paths have no equivalent assertion
    overlaps_existing: false
    fixture_self_reference: false
    deprecated_mechanism: false
YAML
  run env GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"persistent=tests/unit/test_never_existing_contract.bats"* ]]

  printf 'task:\n  project: infra\n  planned_paths: [tests/unit/test_gate_gunshi_report_precheck.bats]\n' > "$task"
  run env GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -eq 0 ]
  printf 'task:\n  project: infra\n  planned_paths: [scripts/deploy_task.sh]\n' > "$task"
  run env GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -eq 0 ]

  for path in logs/test_timing_ledger.tsv docs/test-plan.md contest/data.tsv; do
    printf 'task:\n  project: infra\n  planned_paths: [%s]\n' "$path" > "$task"
    run env GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
    [ "$status" -eq 0 ]
  done

  for path in tests/unit/test_new.bats tests/test_new.sh test_new.py; do
    printf 'task:\n  project: infra\n  planned_paths: [%s]\n' "$path" > "$task"
    run env GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"omits transient deletion evidence: $path"* ]]
  done
}

@test "SG-PRE35 uses report actual scope and requires path declarations or transient deletion evidence" {
  gate="$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh"
  task="$TMP_DIR/tasks/kagemaru.yaml"
  cat > "$task" <<'YAML'
task:
  project: infra
  planned_paths: [scripts/only_planned.sh]
  test_necessity:
    - path: tests/unit/test_actual_persistent.bats
      defense_target: actual persistent boundary remains enforced
      overlap_evidence: no equivalent assertion in the current suite
      overlaps_existing: false
      fixture_self_reference: false
      deprecated_mechanism: false
YAML
  cat > "$TMP_DIR/report.yaml" <<'YAML'
worker_id: kagemaru
parent_cmd: cmd_fixture
files_modified:
  - {path: tests/unit/test_actual_persistent.bats, change: contract}
  - {path: tests/unit/test_actual_transient.bats, change: proof}
transient_tests_deleted: [tests/unit/test_actual_transient.bats]
YAML
  run env GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"persistent=tests/unit/test_actual_persistent.bats"* ]]
  [[ "$output" == *"transient=tests/unit/test_actual_transient.bats"* ]]
  sed -i '/transient_tests_deleted:/d' "$TMP_DIR/report.yaml"
  run env GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"omits transient deletion evidence"* ]]
}

@test "SG-PRE35 resolves existing and new tests against the task project working tree" {
  gate="$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh"
  task="$TMP_DIR/tasks/kagemaru.yaml"
  project_id="sgpre35_fixture_${BATS_TEST_NUMBER}_$$"
  projects_dir="$TMP_DIR/projects"
  project_file="$projects_dir/${project_id}.yaml"
  project_repo="$TMP_DIR/external-project"
  mkdir -p "$project_repo/tests/unit" "$projects_dir"
  git -C "$project_repo" init -q
  git -C "$project_repo" config user.email fixture@example.invalid
  git -C "$project_repo" config user.name fixture
  printf '# existing a\n' > "$project_repo/tests/unit/test_existing.py"
  printf '# existing b\n' > "$project_repo/tests/unit/test_existing_b.py"
  printf '# existing c\n' > "$project_repo/tests/unit/test_existing_c.py"
  git -C "$project_repo" add .
  git -C "$project_repo" commit -qm baseline
  printf 'path: %s\n' "$project_repo" > "$project_file"
  printf 'worker_id: kagemaru\nparent_cmd: cmd_fixture\n' > "$TMP_DIR/report.yaml"

  printf 'task:\n  project: %s\n  planned_paths: [tests/unit/test_existing.py, tests/unit/test_existing_b.py, tests/unit/test_existing_c.py]\n' "$project_id" > "$task"
  old_basis_misses=0
  for path in tests/unit/test_existing.py tests/unit/test_existing_b.py tests/unit/test_existing_c.py; do
    git -C "$REPO_ROOT" cat-file -e "HEAD:$path" 2>/dev/null || old_basis_misses=$((old_basis_misses + 1))
  done
  [ "$old_basis_misses" -eq 3 ]
  run env DEPLOY_TASK_PROJECTS_DIR="$projects_dir" GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -eq 0 ]

  cat > "$task" <<YAML
task:
  project: $project_id
  planned_paths: [tests/unit/test_new.py]
  test_necessity:
    - path: tests/unit/test_new.py
      defense_target: external project new-test lifecycle remains explicit
      overlap_evidence: fixture has no equivalent assertion
      overlaps_existing: false
      fixture_self_reference: false
      deprecated_mechanism: false
YAML
  run env DEPLOY_TASK_PROJECTS_DIR="$projects_dir" GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"persistent=tests/unit/test_new.py"* ]]

  printf 'task:\n  project: unknown_project_fixture\n  planned_paths: [tests/unit/test_existing.py]\n' > "$task"
  run env DEPLOY_TASK_PROJECTS_DIR="$projects_dir" GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot resolve test lifecycle repo"* ]]

  printf 'task:\n  project: %s\n  planned_paths: [../tests/unit/test_outside.py]\n' "$project_id" > "$task"
  run env DEPLOY_TASK_PROJECTS_DIR="$projects_dir" GUNSHI_PRECHECK_ONLY=SG-PRE35 GUNSHI_PRECHECK_TASKS_DIR="$TMP_DIR/tasks" bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside project repo"* ]]
}

# test_necessity: LG048(SG-PRE31)はresult=PASSのみを受理していたため、意味検算の結果を
# 「FAILである」と自己申告する経路自体が存在せず、忍者は根拠があっても受理不能で往復が発生していた
# (cmd_karo_impl_lg048_fail_receivable_20260727)。この不変量は、result=PASS/FAILのリテラルのみを
# 受理し、FAILは根拠(recount/actual非空)がある場合に限りERRORS非加算・GATE_PREDICTION=WARNで通し、
# 空欄/散文/根拠なしFAILは引き続きBLOCKすることを保証する。
@test "SG-PRE31 accepts literal PASS/FAIL with evidence, routes FAIL to WARN, still blocks empty or unevidenced claims" {
  gate="$REPO_ROOT/scripts/gates/gate_gunshi_report_precheck.sh"

  cat > "$TMP_DIR/report.yaml" <<'YAML'
result:
  summary: "3件×82件=246件を確認"
semantic_validation:
  classification_axis: "PF種別×trigger種別"
  recount: "3種別×82件=246件を再計算式で確認"
  actual: "内訳: PF-A 100件, PF-B 146件"
  result: PASS
YAML
  run env GUNSHI_PRECHECK_ONLY=SG-PRE31 bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS(LG048)"* ]]
  [[ "$output" == *"GATE_PREDICTION=CLEAR"* ]]

  cat > "$TMP_DIR/report.yaml" <<'YAML'
result:
  summary: "3件×82件=246件を確認"
semantic_validation:
  classification_axis: "PF種別×trigger種別"
  recount: "3種別×82件=246件だが実際は240件で6件の分類漏れを検出"
  actual: "内訳: PF-A 94件, PF-B 146件(6件不足)"
  result: FAIL
YAML
  run env GUNSHI_PRECHECK_ONLY=SG-PRE31 bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FAIL_DECLARED(LG048)"* ]]
  [[ "$output" == *"GATE_PREDICTION=WARN"* ]]

  cat > "$TMP_DIR/report.yaml" <<'YAML'
result:
  summary: "3件×82件=246件を確認"
semantic_validation:
  classification_axis: "PF種別×trigger種別"
  recount:
  actual:
  result: FAIL
YAML
  run env GUNSHI_PRECHECK_ONLY=SG-PRE31 bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCK(LG048): semantic_validation.recountがない"* ]]

  cat > "$TMP_DIR/report.yaml" <<'YAML'
result:
  summary: "3件×82件=246件を確認"
semantic_validation:
  classification_axis: "PF種別×trigger種別"
  recount: "3種別×82件=246件を再計算式で確認"
  actual: "内訳: PF-A 100件, PF-B 146件"
  result: "特に問題なさそうです"
YAML
  run env GUNSHI_PRECHECK_ONLY=SG-PRE31 bash "$gate" "$TMP_DIR/report.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BLOCK(LG048): semantic_validation.resultがPASS/FAILのいずれでもない"* ]]
}
