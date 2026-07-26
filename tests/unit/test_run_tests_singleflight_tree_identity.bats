#!/usr/bin/env bats
# test_run_tests_singleflight_tree_identity.bats — 対照fixture
# (cmd_karo_impl_singleflight_tree_identity_20260726)
#
# 検出対象(この検知器/修正が何を検証するか、1行):
#   scripts/run_tests.sh の single-flight join(通常経路+stale_owner経路の
#   両方)が、joinerの実際のtree(source_head + テスト選択入力 + 選択対象
#   テストファイル群の未commit状態)がleaderの記録と一致する場合のみjoinし、
#   一致しない場合はjoined受領証を出さずleaderとして走り直すこと、かつ
#   選択対象外の無関係なファイル変更ではjoinを殺さないことを検証する。
#
# 背景: single-flight joinは以前 validate_run_tests_terminal_receipt (受領証
# の"形"だけ)しか検証しておらず、joinerが他人のtreeの受領証を自分の
# 「unit実行でFAIL0」の証明として静かに引き継ぎうる欠陥があった(小太郎の
# 実測: joined受領証2回とも自走しておらず、1回目は自分の新規testが未commitで
# 選択対象外、直後の自走はtestsで8件差)。
#
# test_necessity(1件、1不変量):
#   path=scripts/run_tests.sh
#   defense_target: "single-flight joinはjoinerの選択対象テストファイル群の
#     source_head+未commit状態がleaderの記録と一致する場合のみjoinし、
#     不一致ならjoined受領証を出さずleaderとして再実行する。選択対象外の
#     無関係な変更ではjoinを殺さない"
#   overlap_evidence: "test_run_tests.batsの既存43testは通常のrun_tests.sh
#     動作(selection/scheduling/receipt形式等)を検証し、single-flightの
#     tree identity正誤は検証していない。本ファイルが検証する4不変量
#     (mismatch検出/無関係変更での非mismatch/exact match時のjoin継続/
#     構造化joinedフィールド)はtest_run_tests.batsと重複しない"
#   overlaps_existing: false

setup() {
  unset RUN_TESTS_ACTIVE
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPROOT="$(mktemp -d)"
  mkdir -p "$TMPROOT/scripts" "$TMPROOT/tests/unit" "$TMPROOT/bin" "$TMPROOT/logs" \
    "$TMPROOT/receipts" "$TMPROOT/sf"
  cp "$ROOT/scripts/run_tests.sh" "$ROOT/scripts/test_timing_ledger_write.sh" \
    "$ROOT/scripts/test_suite_timing_ledger_write.sh" "$ROOT/scripts/universal_shard.py" \
    "$ROOT/scripts/universal_shard_adapters.py" "$ROOT/scripts/run_with_receipt.sh" \
    "$ROOT/scripts/heavy_job_admission.sh" "$TMPROOT/scripts/"
  printf '@test "sample" { true; }\n' >"$TMPROOT/tests/unit/sample.bats"
  # run_tests.sh's own plumbing (receipts, single-flight coordination, run
  # markers) lives inside $TMPROOT for this fixture, unlike production where
  # it lives under a gitignored logs/ path or /tmp. Ignore it here too so the
  # tree-identity dirty-hash reflects real source changes, not this
  # harness's own bookkeeping byproducts.
  printf 'receipts/\nsf/\nbin/\nrun-count*\nleader.*\njoiner.*\nunrelated.*\n' >"$TMPROOT/.gitignore"
  git -C "$TMPROOT" init -q
  git -C "$TMPROOT" config user.email test@example.invalid
  git -C "$TMPROOT" config user.name test
  git -C "$TMPROOT" add scripts tests .gitignore
  git -C "$TMPROOT" commit -qm init

  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
exec 9>>"$RUN_COUNT.lock"
flock 9
count=$(cat "$RUN_COUNT" 2>/dev/null || printf 0)
printf '%s\n' "$((count + 1))" >"$RUN_COUNT"
flock -u 9
sleep 1.2
printf '1..1\nok 1 sample\n'
SH
  chmod +x "$TMPROOT/bin/bats"
}

_common_env() {
  printf '%s\n' \
    "REPO_ROOT=$TMPROOT" \
    "RUN_TESTS_RECEIPT_DIR=$TMPROOT/receipts" \
    "RUN_TESTS_SINGLEFLIGHT_DIR=$TMPROOT/sf" \
    "RUN_TESTS_SINGLEFLIGHT_HEARTBEAT_SECONDS=5" \
    "RUN_TESTS_SINGLEFLIGHT_STALE_SECONDS=30"
}

_run_leader_then_joiner() {
  # $1 = shell snippet run between leader-start and joiner-start (the "drift")
  mapfile -t common < <(_common_env)
  env -u RUN_TESTS_ACTIVE -u SHOGUN_HEAVY_JOB_LOCK_HELD -u SHOGUN_HEAVY_JOB_ADMITTED \
    PATH="$TMPROOT/bin:$PATH" "${common[@]}" RUN_COUNT="$TMPROOT/run-count" \
    bash "$TMPROOT/scripts/run_tests.sh" file "$TMPROOT/tests/unit/sample.bats" \
    >"$TMPROOT/leader.out" 2>"$TMPROOT/leader.err" & p1=$!
  sleep 0.3
  eval "$1"
  env -u RUN_TESTS_ACTIVE -u SHOGUN_HEAVY_JOB_LOCK_HELD -u SHOGUN_HEAVY_JOB_ADMITTED \
    PATH="$TMPROOT/bin:$PATH" "${common[@]}" RUN_COUNT="$TMPROOT/run-count" \
    bash "$TMPROOT/scripts/run_tests.sh" file "$TMPROOT/tests/unit/sample.bats" \
    >"$TMPROOT/joiner.out" 2>"$TMPROOT/joiner.err" & p2=$!
  wait "$p1"; wait "$p2"
}

@test "AC3 positive: a new commit landing while the leader runs changes HEAD and prevents the join" {
  _run_leader_then_joiner '
    printf "changed\n" >"$TMPROOT/drift.txt"
    git -C "$TMPROOT" add drift.txt && git -C "$TMPROOT" commit -qm drift
  '
  [[ "$(cat "$TMPROOT/joiner.err")" != *SINGLE_FLIGHT_JOINED* ]]
  [[ "$(cat "$TMPROOT/joiner.err")" == *SINGLE_FLIGHT_TREE_MISMATCH* ]]
  # A same-content pass cache may legitimately skip re-invoking bats for an
  # unchanged test file (a separate, correct optimization); the proof this
  # did NOT join is that the joiner produced its OWN distinct receipt file
  # rather than the leader's, and its own final output carries no joined= tag.
  leader_receipt="$(grep -oE '/[^ ]+run_tests_[0-9TZ_]+\.json' "$TMPROOT/leader.err" | head -1)"
  joiner_receipt="$(grep -oE '/[^ ]+run_tests_[0-9TZ_]+\.json' "$TMPROOT/joiner.out" | tail -1)"
  [ -n "$leader_receipt" ]
  [ -n "$joiner_receipt" ]
  [ "$leader_receipt" != "$joiner_receipt" ]
  [[ "$(cat "$TMPROOT/joiner.out")" != *"joined="* ]]
}

@test "AC3 positive: an uncommitted change to the selected test file itself prevents the join (kotaro's own scenario)" {
  _run_leader_then_joiner '
    printf "@test \"sample\" { true; }\n@test \"extra\" { true; }\n" >"$TMPROOT/tests/unit/sample.bats"
  '
  [[ "$(cat "$TMPROOT/joiner.err")" != *SINGLE_FLIGHT_JOINED* ]]
  [[ "$(cat "$TMPROOT/joiner.err")" == *SINGLE_FLIGHT_TREE_MISMATCH* ]]
  [[ "$(cat "$TMPROOT/joiner.out")" != *"joined="* ]]
}

@test "AC3 negative (gunshi's scoping fix): an uncommitted change to an UNRELATED file does not prevent the join" {
  _run_leader_then_joiner '
    printf "unrelated edit\n" >"$TMPROOT/unrelated.txt"
  '
  [[ "$(cat "$TMPROOT/joiner.err")" == *SINGLE_FLIGHT_JOINED* ]]
  [[ "$(cat "$TMPROOT/joiner.err")" != *SINGLE_FLIGHT_TREE_MISMATCH* ]]
  [ "$(cat "$TMPROOT/run-count")" -eq 1 ]
}

@test "AC3 negative: a joiner whose tree exactly matches the leader still joins without re-running" {
  _run_leader_then_joiner ':'
  [[ "$(cat "$TMPROOT/joiner.err")" == *SINGLE_FLIGHT_JOINED* ]]
  [[ "$(cat "$TMPROOT/joiner.err")" != *SINGLE_FLIGHT_TREE_MISMATCH* ]]
  [ "$(cat "$TMPROOT/run-count")" -eq 1 ]
  [ "$(find "$TMPROOT/receipts" -name '*.json' ! -name '*.join_status.json' -type f | wc -l)" -eq 1 ]
  # AC4: a structured sidecar records join status directly (not a stdout grep).
  join_status="$(find "$TMPROOT/receipts" -name '*.join_status.json' -type f | head -1)"
  [ -n "$join_status" ]
  [[ "$(cat "$join_status")" == *'"joined": true'* ]]
}
