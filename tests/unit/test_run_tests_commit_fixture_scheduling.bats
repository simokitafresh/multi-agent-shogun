#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPROOT="$(mktemp -d)"
  mkdir -p "$TMPROOT/scripts" "$TMPROOT/tests/unit" "$TMPROOT/bin" "$TMPROOT/logs"
  cp "$ROOT/scripts/run_tests.sh" "$ROOT/scripts/test_timing_ledger_write.sh" "$TMPROOT/scripts/"
  for name in \
    test_gate_shogun_startup \
    test_heavy_job_admission \
    test_daemon_maintenance_lock \
    test_heavy_job_classifier_newline \
    test_cmd_complete_insight_consumption \
    test_pending_approval \
    test_pre_bash_guard1_git_commit_tokenizer \
    test_ninja_scope_commit \
    test_deploy_task_template_generation \
    test_unrelated_a \
    test_unrelated_b; do
    printf '@test "sample" { true; }\n' >"$TMPROOT/tests/unit/$name.bats"
  done
  cat >"$TMPROOT/bin/bats" <<'SH'
#!/usr/bin/env bash
file="$(basename "$1")"
jobs=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--jobs" ]; then
    jobs="$2"
    break
  fi
  shift
done
printf '%s\t%s\n' "$file" "$jobs" >>"$BATS_ARGS_LOG"
sleep 0.15
printf '1..1\nok 1 sample\n'
SH
  chmod +x "$TMPROOT/bin/bats"
  git -C "$TMPROOT" init -q
  git -C "$TMPROOT" config user.email test@example.invalid
  git -C "$TMPROOT" config user.name test
  git -C "$TMPROOT" add scripts tests
  git -C "$TMPROOT" commit -qm init
}

teardown() { rm -rf "$TMPROOT"; }

@test "shared hook git daemon and startup fixtures are file-exclusive while unrelated files remain parallel" {
  run env PATH="$TMPROOT/bin:$PATH" REPO_ROOT="$TMPROOT" \
    BATS_ARGS_LOG="$TMPROOT/bats.args" BATS_SCHEDULER_TRACE="$TMPROOT/schedule.tsv" \
    BATS_CACHE=0 BATS_INNER_JOBS=4 BATS_MAX_TEST_JOBS=8 bash -c '
      source "$1/scripts/run_tests.sh"
      run_bats_files_parallel \
        "$1/tests/unit/test_gate_shogun_startup.bats" \
        "$1/tests/unit/test_heavy_job_admission.bats" \
        "$1/tests/unit/test_daemon_maintenance_lock.bats" \
        "$1/tests/unit/test_heavy_job_classifier_newline.bats" \
        "$1/tests/unit/test_cmd_complete_insight_consumption.bats" \
        "$1/tests/unit/test_pending_approval.bats" \
        "$1/tests/unit/test_pre_bash_guard1_git_commit_tokenizer.bats" \
        "$1/tests/unit/test_ninja_scope_commit.bats" \
        "$1/tests/unit/test_deploy_task_template_generation.bats" \
        "$1/tests/unit/test_unrelated_a.bats" \
        "$1/tests/unit/test_unrelated_b.bats"
    ' _ "$TMPROOT"
  [ "$status" -eq 0 ]

  for file in \
    test_gate_shogun_startup.bats \
    test_heavy_job_admission.bats \
    test_daemon_maintenance_lock.bats \
    test_heavy_job_classifier_newline.bats \
    test_cmd_complete_insight_consumption.bats \
    test_pending_approval.bats \
    test_pre_bash_guard1_git_commit_tokenizer.bats \
    test_ninja_scope_commit.bats \
    test_deploy_task_template_generation.bats; do
    awk -F '\t' -v f="$file" '$1 == f && $2 == 1 { found=1 } END { exit !found }' "$TMPROOT/bats.args"
    awk -F '\t' -v f="$file" '$1 == f && $2 == 8 && $3 == 0 { found=1 } END { exit !found }' "$TMPROOT/schedule.tsv"
  done

  awk -F '\t' '$1 ~ /^test_unrelated_[ab]\.bats$/ && $2 == 4 { count++ } END { exit !(count == 2) }' "$TMPROOT/bats.args"
  awk -F '\t' '$1 ~ /^test_unrelated_[ab]\.bats$/ && $2 == 4 { found=1 } END { exit !found }' "$TMPROOT/schedule.tsv"
}
