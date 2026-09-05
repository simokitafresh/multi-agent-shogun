#!/usr/bin/env bats

setup() { fixture_dir="$(mktemp -d)"; }
teardown() { rm -f context/dm-signal-fixture-vp-*.md; }
make_lines() { awk -v n="$1" 'BEGIN { for (i=1; i<=n; i++) print "line " i }' > "$2"; }

@test "500 line context passes" {
  make_lines 500 "$fixture_dir/new-context.md"
  run bash scripts/gates/gate_vercel_phase.sh "$fixture_dir/new-context.md"
  [ "$status" -eq 0 ]
}

@test "501 line context blocks" {
  make_lines 501 "$fixture_dir/new-context.md"
  run bash scripts/gates/gate_vercel_phase.sh "$fixture_dir/new-context.md"
  [ "$status" -ne 0 ]
}

@test "existing debt increase blocks" {
  make_lines 1490 "$fixture_dir/senkyoku-log.md"
  run bash scripts/gates/gate_vercel_phase.sh "$fixture_dir/senkyoku-log.md"
  [ "$status" -ne 0 ]
}

@test "new 501 line context blocks" {
  make_lines 501 "$fixture_dir/brand-new.md"
  run bash scripts/gates/gate_vercel_phase.sh "$fixture_dir/brand-new.md"
  [ "$status" -ne 0 ]
}

@test "line limit failure reports a distinct machine-readable reason" {
  make_lines 501 "$fixture_dir/line-limit.md"
  run bash scripts/gates/gate_vercel_phase.sh "$fixture_dir/line-limit.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"GATE_REASON=vercel_phase:line_limit_exceeded"* ]]
  [[ "$output" != *"GATE_REASON=vercel_phase:broken_references"* ]]
}

@test "broken reference failure reports a distinct machine-readable reason" {
  printf '# fixture\nSee docs/research/does-not-exist-vercel-phase.md\n' > "$fixture_dir/broken-ref.md"
  run env VERCEL_PHASE_SKIP_CANDIDATE_SUGGESTIONS=1 \
      bash scripts/gates/gate_vercel_phase.sh "$fixture_dir/broken-ref.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"GATE_REASON=vercel_phase:broken_references"* ]]
  [[ "$output" != *"GATE_REASON=vercel_phase:line_limit_exceeded"* ]]
}

@test "completion gate maps machine-readable Vercel reasons without ambiguity" {
  run env CMD_COMPLETE_GATE_VERCEL_REASON_ONLY=1 \
      CMD_COMPLETE_GATE_VERCEL_OUTPUT='[ALERT] line limit exceeded
GATE_REASON=vercel_phase:line_limit_exceeded' \
      bash scripts/cmd_complete_gate.sh cmd_test
  [ "$status" -eq 0 ]
  [ "$output" = "vercel_phase:line_limit_exceeded" ]

  run env CMD_COMPLETE_GATE_VERCEL_REASON_ONLY=1 \
      CMD_COMPLETE_GATE_VERCEL_OUTPUT='[ALERT] broken refs found
GATE_REASON=vercel_phase:broken_references' \
      bash scripts/cmd_complete_gate.sh cmd_test
  [ "$status" -eq 0 ]
  [ "$output" = "vercel_phase:broken_references" ]
}

@test "research context index preserves the exact detail payload before compression" {
  context="context/dm-signal-research.md"
  detail="docs/research/cmd_karo_hotfix_vercel_debt_reason_202608100949_dm_signal_research_full.md"
  [ "$(wc -l < "$context")" -le 500 ]
  expected_lines="$(sed -n 's/.*original_line_count: \([0-9][0-9]*\).*/\1/p' "$detail")"
  expected_sha="$(sed -n 's/.*original_sha256: \([0-9a-f][0-9a-f]*\).*/\1/p' "$detail")"
  actual_lines="$(tail -n +3 "$detail" | wc -l)"
  actual_sha="$(tail -n +3 "$detail" | sha256sum | awk '{print $1}')"
  [ "$actual_lines" -eq "$expected_lines" ]
  [ "$actual_sha" = "$expected_sha" ]
  run bash scripts/gates/gate_vercel_phase.sh "$context"
  [ "$status" -eq 0 ]
}

# GA-579/580: gate_context_freshness.sh's missing_context_links() resolver
# must connect a context file to the real project it belongs to, not to
# whatever project happens to be first in the registry, and must not treat a
# stale/dirty local checkout as proof that a tracked reference is gone. These
# three fixtures build the external project's git history with plumbing
# commands only (hash-object/mktree/commit-tree) since ninjas may not invoke
# `git commit` directly (GA-231).
make_git_fixture_repo() {
  local repo="$1"
  mkdir -p "$repo/docs/research"
  ( cd "$repo" \
    && git init -q \
    && git config user.email test@test.com \
    && git config user.name test )
  local blob_existing blob_new tree_research_old tree_docs_old tree_root_old commit_old
  local tree_research_new tree_docs_new tree_root_new commit_new
  blob_existing="$(cd "$repo" && git hash-object -w --stdin <<< "existing")"
  echo "existing" > "$repo/docs/research/existing.md"
  tree_research_old="$(cd "$repo" && printf '100644 blob %s\texisting.md\n' "$blob_existing" | git mktree)"
  tree_docs_old="$(cd "$repo" && printf '040000 tree %s\tresearch\n' "$tree_research_old" | git mktree)"
  tree_root_old="$(cd "$repo" && printf '040000 tree %s\tdocs\n' "$tree_docs_old" | git mktree)"
  commit_old="$(cd "$repo" && git commit-tree "$tree_root_old" -m init < /dev/null)"

  blob_new="$(cd "$repo" && git hash-object -w --stdin <<< "identity metrics")"
  tree_research_new="$(cd "$repo" && printf '100644 blob %s\texisting.md\n100644 blob %s\tnew-doc.md\n' "$blob_existing" "$blob_new" | git mktree)"
  tree_docs_new="$(cd "$repo" && printf '040000 tree %s\tresearch\n' "$tree_research_new" | git mktree)"
  tree_root_new="$(cd "$repo" && printf '040000 tree %s\tdocs\n' "$tree_docs_new" | git mktree)"
  commit_new="$(cd "$repo" && git commit-tree "$tree_root_new" -p "$commit_old" -m "add new-doc" < /dev/null)"

  ( cd "$repo" \
    && git update-ref refs/heads/main "$commit_old" \
    && git symbolic-ref HEAD refs/heads/main \
    && git update-ref refs/remotes/origin/main "$commit_new" )
}

setup_context_freshness_fixture() {
  fc_root="$BATS_TEST_TMPDIR/fc-root"
  fc_dm_signal="$BATS_TEST_TMPDIR/fc-dm-signal"
  fc_other="$BATS_TEST_TMPDIR/fc-other"
  mkdir -p "$fc_root/context" "$fc_root/config" "$fc_root/scripts"
  make_git_fixture_repo "$fc_dm_signal"
  mkdir -p "$fc_other/docs/research"

  cat > "$fc_root/config/projects.yaml" <<YAML
projects:
  - id: dm-signal
    path: "$fc_dm_signal"
  - id: dm-other
    path: "$fc_other"
YAML
  cat > "$fc_root/scripts/check.sh" <<'SH'
#!/usr/bin/env bash
echo 'ALERT: context/dm-signal-fixture.md source commits 1件 since last_updated=2026-07-19; latest: abc1234 fixture'
SH
  fc_bulletin="$BATS_TEST_TMPDIR/fc-bulletin.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$fc_bulletin"
  chmod +x "$fc_bulletin"
}

@test "GA-579: external project detail reference resolves via git tree despite a stale local checkout" {
  setup_context_freshness_fixture
  printf '<!-- last_updated: 2026-07-19 cmd_fixture -->\nSee `docs/research/new-doc.md`.\n' \
    > "$fc_root/context/dm-signal-fixture.md"

  run env \
    CONTEXT_FRESHNESS_ROOT="$fc_root" \
    CONTEXT_FRESHNESS_PROJECT_CONFIG="$fc_root/config/projects.yaml" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$fc_root/scripts/check.sh" \
    CONTEXT_FRESHNESS_BULLETIN_SCRIPT="$fc_bulletin" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash scripts/gates/gate_context_freshness.sh

  [[ "$output" == *"ALERT: dm-signal-fixture.md"* ]]
  [[ "$output" != *"参照リンク欠落"* ]]
}

@test "GA-579: a genuinely missing reference still blocks" {
  setup_context_freshness_fixture
  printf '<!-- last_updated: 2026-07-19 cmd_fixture -->\nSee `docs/research/truly-missing.md`.\n' \
    > "$fc_root/context/dm-signal-fixture.md"

  run env \
    CONTEXT_FRESHNESS_ROOT="$fc_root" \
    CONTEXT_FRESHNESS_PROJECT_CONFIG="$fc_root/config/projects.yaml" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$fc_root/scripts/check.sh" \
    CONTEXT_FRESHNESS_BULLETIN_SCRIPT="$fc_bulletin" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash scripts/gates/gate_context_freshness.sh

  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCK: dm-signal-fixture.md (source更新あり・参照リンク欠落)"* ]]
  [[ "$output" == *"docs/research/truly-missing.md"* ]]
}

@test "GA-580: a same-named file in an unrelated registered project is not mistaken for the intended one" {
  setup_context_freshness_fixture
  mkdir -p "$fc_other/docs/research"
  echo "unrelated collision" > "$fc_other/docs/research/only-in-other-project.md"
  printf '<!-- last_updated: 2026-07-19 cmd_fixture -->\nSee `docs/research/only-in-other-project.md`.\n' \
    > "$fc_root/context/dm-signal-fixture.md"

  run env \
    CONTEXT_FRESHNESS_ROOT="$fc_root" \
    CONTEXT_FRESHNESS_PROJECT_CONFIG="$fc_root/config/projects.yaml" \
    CONTEXT_FRESHNESS_CHECK_SCRIPT="$fc_root/scripts/check.sh" \
    CONTEXT_FRESHNESS_BULLETIN_SCRIPT="$fc_bulletin" \
    CONTEXT_FRESHNESS_NTFY_SCRIPT=/bin/true \
    CONTEXT_FRESHNESS_ALERT_STATE_DIR="$BATS_TEST_TMPDIR/state" \
    CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1 \
    CONTEXT_FRESHNESS_TODAY=2026-07-20 \
    bash scripts/gates/gate_context_freshness.sh

  [ "$status" -eq 1 ]
  [[ "$output" == *"BLOCK: dm-signal-fixture.md (source更新あり・参照リンク欠落)"* ]]
  [[ "$output" == *"docs/research/only-in-other-project.md"* ]]
}

# Same three scenarios exercised directly against gate_vercel_phase.sh's own
# resolver (ref_exists_in_base/check_ref_record), which has the identical
# canonical-scoping + git-tree-fallback fix applied independently since it is
# a separate script (see external_ref_canonical_project_id and friends in
# that file). VERCEL_PHASE_PROJECT_CONFIG lets these tests register a
# fixture project without touching config/projects.yaml. The context file
# must live under this repo's own context/ dir (removed in teardown) because
# gate_vercel_phase.sh derives the file's canonical project from its path
# relative to SCRIPT_DIR (real repo root, not overridable), unlike
# gate_context_freshness.sh which accepts CONTEXT_FRESHNESS_ROOT.
@test "GA-580: gate_vercel_phase resolves an external detail reference via git tree despite a stale checkout" {
  setup_context_freshness_fixture
  printf '<!-- fixture -->\nSee `docs/research/new-doc.md`.\n' > context/dm-signal-fixture-vp-a.md

  run env VERCEL_PHASE_SKIP_CANDIDATE_SUGGESTIONS=1 \
    VERCEL_PHASE_PROJECT_CONFIG="$fc_root/config/projects.yaml" \
    bash scripts/gates/gate_vercel_phase.sh context/dm-signal-fixture-vp-a.md

  [ "$status" -eq 0 ]
}

@test "GA-580: gate_vercel_phase still blocks a genuinely missing reference" {
  setup_context_freshness_fixture
  printf '<!-- fixture -->\nSee `docs/research/truly-missing.md`.\n' > context/dm-signal-fixture-vp-b.md

  run env VERCEL_PHASE_SKIP_CANDIDATE_SUGGESTIONS=1 \
    VERCEL_PHASE_PROJECT_CONFIG="$fc_root/config/projects.yaml" \
    bash scripts/gates/gate_vercel_phase.sh context/dm-signal-fixture-vp-b.md

  [ "$status" -ne 0 ]
  [[ "$output" == *"docs/research/truly-missing.md"* ]]
}

@test "GA-580: gate_vercel_phase does not adopt a same-named file from an unrelated registered project" {
  setup_context_freshness_fixture
  mkdir -p "$fc_other/docs/research"
  echo "unrelated collision" > "$fc_other/docs/research/only-in-other-project-vp.md"
  printf '<!-- fixture -->\nSee `docs/research/only-in-other-project-vp.md`.\n' > context/dm-signal-fixture-vp-c.md

  run env VERCEL_PHASE_SKIP_CANDIDATE_SUGGESTIONS=1 \
    VERCEL_PHASE_PROJECT_CONFIG="$fc_root/config/projects.yaml" \
    bash scripts/gates/gate_vercel_phase.sh context/dm-signal-fixture-vp-c.md

  [ "$status" -ne 0 ]
  [[ "$output" == *"docs/research/only-in-other-project-vp.md"* ]]
}
