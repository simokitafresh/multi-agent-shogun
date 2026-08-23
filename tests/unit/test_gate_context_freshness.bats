#!/usr/bin/env bats
# test_necessity: context freshness更新cmdがlast_updatedだけの消火を許さず、検証済みsource_commit境界と未解消差分0件を完了条件にする不変量を守る。

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  FIXTURE_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$FIXTURE_ROOT/context" "$FIXTURE_ROOT/scripts" "$BATS_TEST_TMPDIR/state"
  printf '<!-- last_updated: 2026-07-19 cmd_fixture -->\n' > "$FIXTURE_ROOT/context/infrastructure.md"
  cat > "$FIXTURE_ROOT/scripts/check.sh" <<'SH'
#!/usr/bin/env bash
echo 'ALERT: context/infrastructure.md source commits 1件 since last_updated=2026-07-19; latest: abc1234 fixture'
SH
  BULLETIN_SCRIPT="$BATS_TEST_TMPDIR/default-bulletin-write.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BULLETIN_SCRIPT"
  chmod +x "$BULLETIN_SCRIPT"
  export CONTEXT_FRESHNESS_BULLETIN_SCRIPT="$BULLETIN_SCRIPT"
  export CONTEXT_FRESHNESS_BULLETIN_STATE_DIR="$BATS_TEST_TMPDIR/default-bulletin-state"
}

@test "ALERT template requires source commit boundary and zero unresolved commits" {
  run env \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"AC2: scripts/context_source_commit_set.sh"* ]]
  [[ "$output" == *"last_updatedだけの更新は禁止"* ]]
  [[ "$output" == *"未解消source commit=0件かつALERT=0件"* ]]
  [[ "$output" != *"先頭の last_updated を 2026-07-20"* ]]
}

@test "ALERT template preserves registry owner and routes to the doc lane" {
  cat > "$FIXTURE_ROOT/scripts/check.sh" <<'SH'
#!/usr/bin/env bash
echo 'ALERT: context/infrastructure.md source commits 1件 since last_updated=2026-07-19 repo=/fixture root_fallback=yes owner=infra-platform update_trigger=root-fallback latest: abc1234 fixture'
SH

  run env \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"owner: infra-platform"* ]]
  [[ "$output" == *"route: shogun-doc-lane"* ]]
  [[ "$output" == *"update_trigger: \"root-fallback\""* ]]
  [[ "$output" == *"担当=infra-platform"* ]]
  [[ "$output" == *"起票レーン=shogun-doc-lane"* ]]
}

@test "all stale context candidates remain Level5 inputs when more than three alert" {
  for path in infrastructure dm-signal-frontend dm-signal-core dm-signal-ops; do
    printf '<!-- last_updated: 2026-07-19 cmd_fixture -->\n' > "$FIXTURE_ROOT/context/${path}.md"
  done
  cat > "$FIXTURE_ROOT/scripts/check.sh" <<'SH'
#!/usr/bin/env bash
cat <<'EOF'
ALERT: context/infrastructure.md source commits 1件 since last_updated=2026-07-19 repo=/fixture root_fallback=yes owner=infra-platform update_trigger=root-fallback latest: aaa1111 infra
ALERT: context/dm-signal-frontend.md source commits 1件 since last_updated=2026-07-19 repo=/fixture root_fallback=no owner=dm-signal-frontend update_trigger=frontend latest: bbb2222 frontend
ALERT: context/dm-signal-core.md source commits 1件 since last_updated=2026-07-19 repo=/fixture root_fallback=no owner=dm-signal-core update_trigger=backend/app latest: ccc3333 core
ALERT: context/dm-signal-ops.md source commits 1件 since last_updated=2026-07-19 repo=/fixture root_fallback=no owner=dm-signal-ops update_trigger=backend/app/api latest: ddd4444 ops
EOF
SH
  chmod +x "$FIXTURE_ROOT/scripts/check.sh"

  run env \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state-all" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"全件 (4件)"* ]]
  [[ "$output" == *"context/dm-signal-frontend.md の鮮度ALERT"* ]]
  [[ "$output" == *"context/dm-signal-core.md の鮮度ALERT"* ]]
  [[ "$output" == *"context/dm-signal-ops.md の鮮度ALERT"* ]]
  [[ "$output" == *"context/infrastructure.md の鮮度ALERT"* ]]
  [ "$(grep -c '^  purpose: ' <<< "$output")" -eq 4 ]
}

@test "normal checker output produces zero false-positive alerts" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FIXTURE_ROOT/scripts/check.sh"

  run env \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"総合判定: OK"* ]]
  [[ "$output" != *"ALERT:"* ]]
}

# test_necessity: each unresolved raw ALERT must be durably routed once to the
# Shogun doc lane, while retries with identical content remain deduplicated.
@test "raw ALERT doc-lane notification deduplicates successful content and retries changes" {
  bulletin_capture="$BATS_TEST_TMPDIR/bulletin-capture"
  bulletin_script="$BATS_TEST_TMPDIR/bulletin_write.sh"
  cat > "$bulletin_script" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${BULLETIN_NOTIFY:-}|$1|$2|$3|$4" >> "$BULLETIN_CAPTURE"
SH
  # The gate invokes this script through bash; executable permission is not
  # part of the caller contract.
  chmod 644 "$bulletin_script"

  run env \
    BULLETIN_CAPTURE="$bulletin_capture" \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_BULLETIN_SCRIPT="$bulletin_script" \
    CONTEXT_FRESHNESS_BULLETIN_STATE_DIR="$BATS_TEST_TMPDIR/bulletin-state" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state-raw-alert" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$bulletin_capture")" -eq 1 ]
  [[ "$(cat "$bulletin_capture")" == shogun\|gate_context_freshness\|DOC_LANE_ALERT:*\|false\|action_required ]]
  [ "$(find "$BATS_TEST_TMPDIR/bulletin-state" -type f -name '*.sent' | wc -l)" -eq 1 ]

  run env \
    BULLETIN_CAPTURE="$bulletin_capture" \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_BULLETIN_SCRIPT="$bulletin_script" \
    CONTEXT_FRESHNESS_BULLETIN_STATE_DIR="$BATS_TEST_TMPDIR/bulletin-state" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state-raw-alert" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$bulletin_capture")" -eq 1 ]
  [ "$(find "$BATS_TEST_TMPDIR/bulletin-state" -type f -name '*.sent' | wc -l)" -eq 1 ]

  sed -i 's/abc1234/def5678/' "$FIXTURE_ROOT/scripts/check.sh"
  run env \
    BULLETIN_CAPTURE="$bulletin_capture" \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_BULLETIN_SCRIPT="$bulletin_script" \
    CONTEXT_FRESHNESS_BULLETIN_STATE_DIR="$BATS_TEST_TMPDIR/bulletin-state" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state-raw-alert" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$bulletin_capture")" -eq 2 ]
  [ "$(find "$BATS_TEST_TMPDIR/bulletin-state" -type f -name '*.sent' | wc -l)" -eq 2 ]
}

# test_necessity: a target updated after checker output must not create a
# durable stale notification or a success dedupe marker.
@test "raw ALERT rechecks metadata and drops stale notification" {
  bulletin_capture="$BATS_TEST_TMPDIR/stale-bulletin-capture"
  bulletin_script="$BATS_TEST_TMPDIR/stale-bulletin-write.sh"
  cat > "$bulletin_script" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BULLETIN_CAPTURE"
SH
  chmod 644 "$bulletin_script"
  sed -i 's/last_updated: 2026-07-19/last_updated: 2026-07-20/' "$FIXTURE_ROOT/context/infrastructure.md"

  run env \
    BULLETIN_CAPTURE="$bulletin_capture" \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_BULLETIN_SCRIPT="$bulletin_script" \
    CONTEXT_FRESHNESS_BULLETIN_STATE_DIR="$BATS_TEST_TMPDIR/stale-bulletin-state" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/stale-alert-state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"raw ALERT stale after metadata recheck; notification dropped"* ]]
  [ ! -e "$bulletin_capture" ]
  [ "$(find "$BATS_TEST_TMPDIR/stale-bulletin-state" -type f -name '*.sent' 2>/dev/null | wc -l)" -eq 0 ]
}

# test_necessity: a missing or non-readable bulletin path must remain a
# blocking raw ALERT result instead of being passed to bash as a capability.
@test "raw ALERT bulletin requires a readable regular file" {
  bulletin_script="$BATS_TEST_TMPDIR/missing-bulletin-write.sh"
  state_dir="$BATS_TEST_TMPDIR/missing-bulletin-state"

  run env \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_BULLETIN_SCRIPT="$bulletin_script" \
    CONTEXT_FRESHNESS_BULLETIN_STATE_DIR="$state_dir" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state-missing-bulletin" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"raw ALERTのdoc-lane永続通知scriptなし"* ]]
  [[ "$output" == *"総合判定: BLOCK"* ]]
  [ ! -e "$state_dir" ]
}

# test_necessity: dedupe state publication is part of raw ALERT durability;
# a state-directory failure must remain a blocking result.
@test "raw ALERT state directory failure remains blocking" {
  bulletin_script="$BATS_TEST_TMPDIR/state-failure-bulletin-write.sh"
  state_path="$BATS_TEST_TMPDIR/state-path"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bulletin_script"
  chmod 644 "$bulletin_script"
  printf 'not a directory\n' > "$state_path"

  run env \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_BULLETIN_SCRIPT="$bulletin_script" \
    CONTEXT_FRESHNESS_BULLETIN_STATE_DIR="$state_path" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state-state-failure" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"raw ALERTのdoc-lane state領域を作成できない"* ]]
  [[ "$output" == *"総合判定: BLOCK"* ]]
}

# test_necessity: a successful bulletin write without a persisted dedupe marker
# is not a durable raw ALERT result and must remain blocking.
@test "raw ALERT dedupe state save failure remains blocking" {
  bulletin_script="$BATS_TEST_TMPDIR/state-save-bulletin-write.sh"
  mv_wrapper="$BATS_TEST_TMPDIR/mv"
  state_dir="$BATS_TEST_TMPDIR/state-save"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$bulletin_script"
  chmod 644 "$bulletin_script"
  mkdir -p "$state_dir"
  cat > "$mv_wrapper" <<'SH'
#!/usr/bin/env bash
if [[ "${2:-}" == *.sent ]]; then
  exit 1
fi
exec /bin/mv "$@"
SH
  chmod 755 "$mv_wrapper"

  run env \
    PATH="$BATS_TEST_TMPDIR:$PATH" \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_BULLETIN_SCRIPT="$bulletin_script" \
    CONTEXT_FRESHNESS_BULLETIN_STATE_DIR="$state_dir" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state-save-failure" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"raw ALERT通知成功後のdedupe state保存に失敗"* ]]
  [[ "$output" == *"総合判定: BLOCK"* ]]
  [ "$(find "$state_dir" -type f -name '*.sent' | wc -l)" -eq 0 ]
}

# test_necessity: a failed doc-lane write must remain a blocking gate result
# and must not leave a dedupe marker that would suppress a later retry.
@test "raw ALERT bulletin failure blocks without persisting success state" {
  bulletin_script="$BATS_TEST_TMPDIR/failing-bulletin-write.sh"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$bulletin_script"
  chmod +x "$bulletin_script"

  run env \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_BULLETIN_SCRIPT="$bulletin_script" \
    CONTEXT_FRESHNESS_BULLETIN_STATE_DIR="$BATS_TEST_TMPDIR/failed-bulletin-state" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state-failed-alert" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"raw ALERTのdoc-lane永続通知に失敗"* ]]
  [[ "$output" == *"総合判定: BLOCK"* ]]
  [ "$(find "$BATS_TEST_TMPDIR/failed-bulletin-state" -type f -name '*.sent' | wc -l)" -eq 0 ]
}

@test "approved archived infra report routes root-fallback source to its owner" {
  # test_necessity: an approved terminal report must create a context update
  # request for every registered context owner, including infra root-fallback;
  # otherwise GA-475 reappears after the report is archived.
  # regression_justification: GA-475 emitted an infra ALERT even though the
  # source commit's terminal report and APPROVE receipt already existed.
  local repo="$BATS_TEST_TMPDIR/approved-infra"
  mkdir -p "$repo/context" "$repo/scripts" "$repo/queue/archive/reports" "$repo/logs"
  printf '<!-- last_updated: 2026-07-19 cmd_fixture -->\n' > "$repo/context/infrastructure.md"
  git -C "$repo" init -q
  git -C "$repo" config user.email fixture@example.invalid
  git -C "$repo" config user.name fixture
  git -C "$repo" add context/infrastructure.md
  git -C "$repo" commit -qm "cmd_karo_ci_fix_32035893446_normal: approved infra source"
  local source_hash
  source_hash="$(git -C "$repo" rev-parse HEAD)"
  printf '%s\n' \
    'status: completed' \
    'verdict: PASS' \
    'parent_cmd: cmd_karo_ci_fix_32035893446' \
    'commit_hash: 0000000000000000000000000000000000000000' \
    > "$repo/queue/archive/reports/saizo_report_cmd_karo_ci_fix_32035893446_20260818.yaml"
  printf '%s\n' \
    '- cmd_id: cmd_karo_ci_fix_32035893446' \
    '  verdict: APPROVE' \
    > "$repo/logs/gunshi_review_log.yaml"
  cat > "$repo/scripts/check.sh" <<SH
#!/usr/bin/env bash
printf '%s\\n' 'ALERT: context/infrastructure.md source commits 1件 since last_updated=2026-07-19 repo=$repo root_fallback=yes owner=infra-platform update_trigger=root-fallback latest: $source_hash cmd_karo_ci_fix_32035893446_normal: approved infra source'
SH
  chmod +x "$repo/scripts/check.sh"

  run env \
    CONTEXT_FRESHNESS_ROOT="$repo" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$repo/scripts/check.sh" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state-approved-infra" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"CONTEXT_UPDATE_REQUEST project=infra context=context/infrastructure.md"* ]]
  [[ "$output" == *"parent_cmd=cmd_karo_ci_fix_32035893446"* ]]
  [[ "$output" == *"総合判定: OK"* ]]
  [[ "$output" != *"ALERT: context/infrastructure.md"* ]]
}

# test_necessity: a reverted/divergent source commit with identical registered
# trigger content must advance the source boundary through the existing
# machine-readable doc-lane consumer instead of producing a false raw ALERT.
# regression_justification: GA-493 counted a revert as an unreflected core/ops
# change even though the effective backend/services tree was unchanged.
@test "source-equivalent external commit becomes a durable boundary update request" {
  local repo="$BATS_TEST_TMPDIR/source-equivalent"
  local bulletin_capture="$BATS_TEST_TMPDIR/source-equivalent-bulletin"
  local bulletin_script="$BATS_TEST_TMPDIR/source-equivalent-bulletin.sh"
  mkdir -p "$repo/backend/app/services" "$FIXTURE_ROOT/context"
  printf 'baseline\n' > "$repo/backend/app/services/runtime.py"
  git -C "$repo" init -q
  git -C "$repo" config user.email fixture@example.invalid
  git -C "$repo" config user.name fixture
  git -C "$repo" add .
  git -C "$repo" commit -qm 'source baseline'
  local boundary_hash
  boundary_hash="$(git -C "$repo" rev-parse HEAD)"
  printf 'changed\n' > "$repo/backend/app/services/runtime.py"
  git -C "$repo" add .
  git -C "$repo" commit -qm 'source change'
  printf 'baseline\n' > "$repo/backend/app/services/runtime.py"
  git -C "$repo" add .
  git -C "$repo" commit -qm 'Revert "source change"'
  local latest_hash
  latest_hash="$(git -C "$repo" rev-parse HEAD)"

  printf '%s\n' \
    '<!-- last_updated: 2026-08-22 -->' \
    "<!-- source_commit:${boundary_hash} reason:fixture evidence:fixture -->" \
    > "$FIXTURE_ROOT/context/dm-signal-core.md"
  cat > "$FIXTURE_ROOT/scripts/check.sh" <<SH
#!/usr/bin/env bash
printf '%s\\n' 'ALERT: context/dm-signal-core.md source commits 1件 since last_updated=2026-08-22 repo=$repo root_fallback=no owner=dm-signal-core update_trigger=backend/app/services latest: $latest_hash Revert source change'
SH
  chmod +x "$FIXTURE_ROOT/scripts/check.sh"
  cat > "$bulletin_script" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BULLETIN_CAPTURE"
SH
  chmod 644 "$bulletin_script"

  run env \
    BULLETIN_CAPTURE="$bulletin_capture" \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_BULLETIN_SCRIPT="$bulletin_script" \
    CONTEXT_FRESHNESS_BULLETIN_STATE_DIR="$BATS_TEST_TMPDIR/source-equivalent-state" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/source-equivalent-alert-state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-08-23 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"CONTEXT_UPDATE_REQUEST project=dm-signal context=context/dm-signal-core.md source_commit=${latest_hash} parent_cmd=source_${latest_hash} reason=source_equivalent"* ]]
  [[ "$output" == *"source commitは登録boundaryと内容同値"* ]]
  [[ "$output" != *"ALERT: dm-signal-core.md (source commits"* ]]
  [[ "$(cat "$bulletin_capture")" == *"DOC_LANE_REQUEST: CONTEXT_UPDATE_REQUEST project=dm-signal context=context/dm-signal-core.md"* ]]
}

@test "source boundary setter accepts the dashboard freshness tip on divergent HEAD" {
  # test_necessity: the source_commit setter must accept a reviewed origin/main
  # boundary when the shared worktree HEAD is on a divergent local branch.
  mkdir -p "$FIXTURE_ROOT/scripts/lib" "$FIXTURE_ROOT/scripts/config" "$FIXTURE_ROOT/config"
  cp "$ROOT/scripts/context_source_commit_set.sh" "$FIXTURE_ROOT/scripts/context_source_commit_set.sh"
  cp "$ROOT/scripts/lib/project_path.sh" "$FIXTURE_ROOT/scripts/lib/project_path.sh"
  cp "$ROOT/scripts/lib/repo_root.sh" "$FIXTURE_ROOT/scripts/lib/repo_root.sh"
  cp "$ROOT/scripts/config/context_source_commits.tsv" "$FIXTURE_ROOT/scripts/config/context_source_commits.tsv"
  cat > "$FIXTURE_ROOT/config/projects.yaml" <<'YAML'
projects:
  - id: infra
    type: platform
    path: __FIXTURE_ROOT__
    context_file: context/infrastructure.md
    status: active
YAML
  sed -i "s#__FIXTURE_ROOT__#$FIXTURE_ROOT#g" "$FIXTURE_ROOT/config/projects.yaml"
  git -C "$FIXTURE_ROOT" init -q
  git -C "$FIXTURE_ROOT" config user.email fixture@example.invalid
  git -C "$FIXTURE_ROOT" config user.name fixture
  git -C "$FIXTURE_ROOT" add context/infrastructure.md scripts/check.sh scripts/context_source_commit_set.sh scripts/lib/project_path.sh scripts/config/context_source_commits.tsv config/projects.yaml
  git -C "$FIXTURE_ROOT" commit -qm baseline
  base_sha="$(git -C "$FIXTURE_ROOT" rev-parse HEAD)"
  printf 'remote-reviewed\n' > "$FIXTURE_ROOT/source.txt"
  git -C "$FIXTURE_ROOT" add source.txt
  git -C "$FIXTURE_ROOT" commit -qm "reviewed remote source"
  remote_sha="$(git -C "$FIXTURE_ROOT" rev-parse HEAD)"
  git -C "$FIXTURE_ROOT" update-ref refs/remotes/origin/main "$remote_sha"
  git -C "$FIXTURE_ROOT" checkout -q -b local-divergent "$base_sha"
  printf 'local-only\n' > "$FIXTURE_ROOT/local.txt"
  git -C "$FIXTURE_ROOT" add local.txt
  git -C "$FIXTURE_ROOT" commit -qm "local divergent worktree"

  run env CONTEXT_SOURCE_COMMIT_TIP=origin/main \
    bash "$FIXTURE_ROOT/scripts/context_source_commit_set.sh" \
    context/infrastructure.md "$remote_sha" "fixture review" "GA-455 fixture"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SOURCE_COMMIT_SET path=context/infrastructure.md"* ]]
  grep -q "source_commit:${remote_sha}" "$FIXTURE_ROOT/context/infrastructure.md"
}

@test "a later context commit closes source candidates in its ancestry" {
  git -C "$FIXTURE_ROOT" init -q
  git -C "$FIXTURE_ROOT" config user.email fixture@example.com
  git -C "$FIXTURE_ROOT" config user.name fixture
  git -C "$FIXTURE_ROOT" add context/infrastructure.md scripts/check.sh
  git -C "$FIXTURE_ROOT" commit -qm "baseline"
  source_hash="$(git -C "$FIXTURE_ROOT" rev-parse HEAD)"

  printf 'source change\n' > "$FIXTURE_ROOT/scripts/source.sh"
  git -C "$FIXTURE_ROOT" add scripts/source.sh
  git -C "$FIXTURE_ROOT" commit -qm "source change"
  stale_hash="$(git -C "$FIXTURE_ROOT" rev-parse HEAD)"

  printf '%s\n' \
    '<!-- last_updated: 2026-07-19 cmd_fixture -->' \
    "<!-- source_commit:${source_hash} reason:fixture evidence:fixture -->" \
    'reviewed content' > "$FIXTURE_ROOT/context/infrastructure.md"
  git -C "$FIXTURE_ROOT" add context/infrastructure.md
  git -C "$FIXTURE_ROOT" commit -qm "context review"
  cat > "$FIXTURE_ROOT/scripts/check.sh" <<SH
#!/usr/bin/env bash
echo 'ALERT: context/infrastructure.md source commits 1件 since last_updated=2026-07-19 repo=$FIXTURE_ROOT root_fallback=yes latest: ${stale_hash} source change'
SH

  run env \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"context commit"* ]]
  [[ "$output" == *"総合判定: OK"* ]]
  [[ "$output" != *"ALERT: infrastructure.md"* ]]
}

@test "a source commit newer than the context commit remains actionable" {
  git -C "$FIXTURE_ROOT" init -q
  git -C "$FIXTURE_ROOT" config user.email fixture@example.com
  git -C "$FIXTURE_ROOT" config user.name fixture
  git -C "$FIXTURE_ROOT" add context/infrastructure.md scripts/check.sh
  git -C "$FIXTURE_ROOT" commit -qm "baseline"
  source_hash="$(git -C "$FIXTURE_ROOT" rev-parse HEAD)"

  printf '%s\n' \
    '<!-- last_updated: 2026-07-19 cmd_fixture -->' \
    "<!-- source_commit:${source_hash} reason:fixture evidence:fixture -->" \
    'reviewed content' > "$FIXTURE_ROOT/context/infrastructure.md"
  git -C "$FIXTURE_ROOT" add context/infrastructure.md
  git -C "$FIXTURE_ROOT" commit -qm "context review"

  printf 'newer source change\n' > "$FIXTURE_ROOT/scripts/source.sh"
  git -C "$FIXTURE_ROOT" add scripts/source.sh
  git -C "$FIXTURE_ROOT" commit -qm "newer source change"
  stale_hash="$(git -C "$FIXTURE_ROOT" rev-parse HEAD)"
  cat > "$FIXTURE_ROOT/scripts/check.sh" <<SH
#!/usr/bin/env bash
echo 'ALERT: context/infrastructure.md source commits 1件 since last_updated=2026-07-19 repo=$FIXTURE_ROOT root_fallback=yes latest: ${stale_hash} newer source change'
SH

  run env \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"ALERT: infrastructure.md"* ]]
  [[ "$output" == *"総合判定: ALERT"* ]]
}

# test_necessity: every persisted research reflux receipt remains valid after
# later receipts are prepended/appended; only an exact source fingerprint may
# close the alert, and a newer unreviewed commit must still alert.
@test "DM-Signal research reflux receipt closes its exact external source commit" {
  project_root="$BATS_TEST_TMPDIR/dm-signal"
  mkdir -p "$project_root/docs/research"
  git -C "$project_root" init -q
  git -C "$project_root" config user.email fixture@example.com
  git -C "$project_root" config user.name fixture
  printf 'reviewed research\n' > "$project_root/docs/research/result.md"
  git -C "$project_root" add docs/research/result.md
  git -C "$project_root" commit -qm "cmd_fixture: research result"
  source_hash="$(git -C "$project_root" rev-parse HEAD)"
  source_blob="$(git -C "$project_root" rev-parse HEAD:docs/research/result.md)"
  fingerprint="$(printf 'A\tdocs/research/result.md\t%s\n' "$source_blob" | sha256sum | awk '{print $1}')"
  printf '%s\n' \
    '<!-- last_updated: 2026-07-19 cmd_fixture -->' \
    '<!-- dm_signal_research_reflux: fingerprint=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; mode=non-target; evidence_b64=c3RhbGU= -->' \
    "<!-- dm_signal_research_reflux: fingerprint=${fingerprint}; mode=synced; evidence_b64=Zml4dHVyZQ== -->" \
    '<!-- source_commit:abc1234 reason:older evidence:fixture -->' \
    > "$FIXTURE_ROOT/context/dm-signal-research.md"
  cat > "$FIXTURE_ROOT/scripts/check.sh" <<SH
#!/usr/bin/env bash
echo 'ALERT: context/dm-signal-research.md source commits 1件 since last_updated=2026-07-19 repo=$project_root latest: ${source_hash} cmd_fixture research result'
SH

  run env \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"総合判定: OK"* ]]
  [[ "$output" != *"ALERT: dm-signal-research.md"* ]]

  printf 'unreviewed research\n' >> "$project_root/docs/research/result.md"
  git -C "$project_root" add docs/research/result.md
  git -C "$project_root" commit -qm "cmd_fixture_new: unreviewed research"
  newer_hash="$(git -C "$project_root" rev-parse HEAD)"
  sed -i "s/${source_hash}/${newer_hash}/" "$FIXTURE_ROOT/scripts/check.sh"

  run env \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"ALERT: dm-signal-research.md"* ]]
}

# test_necessity: an exact approved source commit must become a context update
# request without weakening the ALERT boundary for the next unreviewed commit.
@test "approved DM-Signal report automatically requests core context update while an unreviewed commit still alerts" {
  project_root="$BATS_TEST_TMPDIR/dm-signal-approved"
  mkdir -p "$project_root/backend/app" "$FIXTURE_ROOT/queue/reports" "$FIXTURE_ROOT/logs"
  git -C "$project_root" init -q
  git -C "$project_root" config user.email fixture@example.com
  git -C "$project_root" config user.name fixture
  printf 'approved runtime change\n' > "$project_root/backend/app/runtime.py"
  git -C "$project_root" add backend/app/runtime.py
  git -C "$project_root" commit -qm 'cmd_fixture: approved runtime change'
  approved_hash="$(git -C "$project_root" rev-parse HEAD)"
  printf '<!-- last_updated: 2026-07-19 cmd_fixture -->\n<!-- source_commit:abc1234 reason:older evidence:fixture -->\n' \
    > "$FIXTURE_ROOT/context/dm-signal-core.md"
  cat > "$FIXTURE_ROOT/queue/reports/ninja_report_cmd_fixture.yaml" <<YAML
status: completed
verdict: PASS
parent_cmd: cmd_fixture
commit_hash: $approved_hash
YAML
  cat > "$FIXTURE_ROOT/logs/gunshi_review_log.yaml" <<'YAML'
- cmd_id: cmd_fixture
  verdict: APPROVE
YAML
  cat > "$FIXTURE_ROOT/scripts/check.sh" <<SH
#!/usr/bin/env bash
echo 'ALERT: context/dm-signal-core.md source commits 1件 since last_updated=2026-07-19 repo=$project_root latest: ${approved_hash} cmd_fixture approved runtime change'
SH

  run env CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CONTEXT_UPDATE_REQUEST project=dm-signal context=context/dm-signal-core.md source_commit=${approved_hash}"* ]]
  [[ "$output" == *"総合判定: OK"* ]]

  printf 'unreviewed runtime change\n' >> "$project_root/backend/app/runtime.py"
  git -C "$project_root" add backend/app/runtime.py
  git -C "$project_root" commit -qm 'cmd_unreviewed: runtime change'
  unreviewed_hash="$(git -C "$project_root" rev-parse HEAD)"
  sed -i "s/${approved_hash}/${unreviewed_hash}/" "$FIXTURE_ROOT/scripts/check.sh"

  run env CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ALERT: dm-signal-core.md"* ]]
}

@test "stale context links resolve across workspace and registered project roots" {
  project_root="$BATS_TEST_TMPDIR/project"
  mkdir -p "$FIXTURE_ROOT/projects" "$FIXTURE_ROOT/docs/research" \
    "$project_root/docs/spec"
  printf 'workspace source\n' > "$FIXTURE_ROOT/docs/research/workspace.md"
  printf 'project source\n' > "$project_root/docs/spec/project.md"
  cat > "$FIXTURE_ROOT/projects/example.yaml" <<YAML
project:
  path: "$project_root"
YAML
  cat > "$FIXTURE_ROOT/context/infrastructure.md" <<'MD'
<!-- last_updated: 2026-07-19 cmd_fixture -->
See `docs/research/workspace.md` and `docs/spec/project.md`.
MD

  run env \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"ALERT: infrastructure.md"* ]]
  [[ "$output" != *"参照リンク欠落"* ]]
}

@test "stale context still blocks when no registered root contains a link" {
  printf '%s\n' \
    '<!-- last_updated: 2026-07-19 cmd_fixture -->' \
    'See `docs/research/truly-missing.md` twice: `docs/research/truly-missing.md`.' \
    > "$FIXTURE_ROOT/context/infrastructure.md"

  run env \
    CONTEXT_FRESHNESS_ROOT="$FIXTURE_ROOT" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$FIXTURE_ROOT/scripts/check.sh" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash "$ROOT/scripts/gates/gate_context_freshness.sh"

  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCK: infrastructure.md (source更新あり・参照リンク欠落)"* ]]
  [ "$(grep -o 'docs/research/truly-missing.md' <<< "$output" | wc -l)" -eq 1 ]
}
