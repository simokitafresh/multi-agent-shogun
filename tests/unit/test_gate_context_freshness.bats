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
