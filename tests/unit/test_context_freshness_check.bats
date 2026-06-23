#!/usr/bin/env bats
# test_context_freshness_check.bats — context_freshness_check.sh unit tests
# cmd_1559: 鮮度判定ロジック/古いファイル検出/出力フォーマットのテスト可能分岐を検証

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/context_freshness_check.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cfc.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts" \
             "$TEST_TMPDIR/config" \
             "$TEST_TMPDIR/context" \
             "$TEST_TMPDIR/queue/archive/cmds" \
             "$TEST_TMPDIR/queue"

    # Copy the script under test
    cp "$SRC_SCRIPT" "$TEST_TMPDIR/scripts/context_freshness_check.sh"
    chmod +x "$TEST_TMPDIR/scripts/context_freshness_check.sh"

    # Default: one active project with context_file mapping
    cat > "$TEST_TMPDIR/config/projects.yaml" <<'PROJYAML'
projects:
  - id: dm-signal
    status: active
    context_file: context/dm-signal.md
    context_files:
      - file: context/dm-signal-core.md
  - id: infra
    status: active
    context_file: context/infrastructure.md
  - id: archived-proj
    status: archived
    context_file: context/archived-proj.md
PROJYAML

    # Helper: today and stale date strings
    TODAY="$(date +%Y-%m-%d)"
    STALE_DATE="$(date -d '30 days ago' +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d)"

    export TEST_SCRIPT="$TEST_TMPDIR/scripts/context_freshness_check.sh"
    export CFC_ARCHIVE_CACHE="$TEST_TMPDIR/context_freshness_cache.txt"
    export CONTEXT_FRESHNESS_EXCLUDE_LIST="$TEST_TMPDIR/config/context_freshness_excludes.txt"
    export CFC_OUTPUT_CACHE_TTL=0

    cat > "$CONTEXT_FRESHNESS_EXCLUDE_LIST" <<'EOF'
context/README.md
context/cdp-philosophy.md
context/cdp-severity.md
context/checklist-alm-registration.md
context/checklist-shin-v2-registration.md
context/checklist-ward-fof-production.md
EOF

    git -C "$TEST_TMPDIR" init -q
    git -C "$TEST_TMPDIR" config user.email "test@example.invalid"
    git -C "$TEST_TMPDIR" config user.name "Test User"
}

teardown() {
    unset CFC_OUTPUT_CACHE_TTL
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

# ── Helper: create context file with last_updated ──
_create_context() {
    local rel_path="$1" updated_date="${2:-}"
    local abs_path="$TEST_TMPDIR/$rel_path"
    mkdir -p "$(dirname "$abs_path")"
    if [ -n "$updated_date" ]; then
        printf '<!-- last_updated: %s -->\n# Context\nSome content\n' "$updated_date" > "$abs_path"
    else
        printf '# Context\nSome content without last_updated\n' > "$abs_path"
    fi
    git -C "$TEST_TMPDIR" add "$rel_path"
    git -C "$TEST_TMPDIR" commit -q -m "test source update for $rel_path"
}

_create_source_commit() {
    local rel_path="${1:-src/source.txt}" subject="${2:-test: source project changed}"
    local abs_path="$TEST_TMPDIR/$rel_path"
    mkdir -p "$(dirname "$abs_path")"
    printf 'source update\n' >> "$abs_path"
    git -C "$TEST_TMPDIR" add "$rel_path"
    GIT_AUTHOR_DATE="${TODAY}T00:00:00+09:00" \
    GIT_COMMITTER_DATE="${TODAY}T00:00:00+09:00" \
        git -C "$TEST_TMPDIR" commit -q -m "$subject"
}

# ── Helper: create archive cmd entry ──
_create_archive_cmd() {
    local cmd_id="$1" project="$2" status="${3:-completed}" completed_date="${4:-$TODAY}"
    local fname="${cmd_id}_${completed_date}.yaml"
    cat > "$TEST_TMPDIR/queue/archive/cmds/$fname" <<ARCHYAML
id: $cmd_id
project: $project
status: $status
completed_at: $completed_date
ARCHYAML
}

_create_nested_archive_cmd() {
    local cmd_id="$1" project="$2" status="${3:-done}" completed_date="${4:-$TODAY}"
    local compact_date
    compact_date="${completed_date//-/}"
    local fname="${cmd_id}_${status}_${compact_date}.yaml"
    cat > "$TEST_TMPDIR/queue/archive/cmds/$fname" <<ARCHYAML
commands:
  $cmd_id:
    title: test command
    project: $project
    status: $status
    completed_at: "$completed_date"
ARCHYAML
}

_create_cmd_chronicle() {
    local cmd_id="$1" project="$2" mm_dd="${3:-$(date +%m-%d)}"
    local section
    section="$(date +%Y-%m)"
    cat > "$TEST_TMPDIR/context/cmd-chronicle.md" <<CHRONICLE
# CMD年代記
<!-- last_updated: $TODAY -->

## $section

| cmd | title | project | date | key_result |
|-----|-------|---------|------|------------|
| $cmd_id | test command | $project | $mm_dd | — |
CHRONICLE
}

# ── Helper: create shogun_to_karo.yaml with cmd entry ──
_create_shogun_to_karo() {
    local cmd_id="$1" project="$2"
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<STKYAML
commands:
  - id: $cmd_id
    project: $project
    description: test command
STKYAML
}

_create_shogun_to_karo_mapping() {
    local cmd_id="$1" project="$2"
    cat > "$TEST_TMPDIR/queue/shogun_to_karo.yaml" <<STKYAML
commands:
  $cmd_id:
    project: $project
    description: test command
STKYAML
}

# === Test 1: モード未指定 → exit 1 + usage ===
@test "no mode argument → exit 1 with usage" {
    run bash "$TEST_SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# === Test 2: 不明モード → exit 1 + usage ===
@test "unknown mode → exit 1 with usage" {
    run bash "$TEST_SCRIPT" --invalid-mode
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# === Test 3: --cmd-warnings 引数なし → exit 1 ===
@test "--cmd-warnings without cmd_id → exit 1 with usage" {
    run bash "$TEST_SCRIPT" --cmd-warnings
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

# === Test 4: --dashboard-warnings 鮮度OK → 警告なし ===
@test "--dashboard-warnings with fresh context → no warnings" {
    _create_context "context/dm-signal.md" "$TODAY"
    _create_context "context/dm-signal-core.md" "$TODAY"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# === Test 5: --dashboard-warnings 陳腐化ファイル → WARN出力 ===
@test "--dashboard-warnings with stale context → WARN output" {
    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_source_commit "src/dm_signal.py"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT:"* ]]
    [[ "$output" == *"context/dm-signal.md"* ]]
    [[ "$output" == *"source commits"* ]]
}

@test "root fallback ignores context-only commits" {
    _create_context "context/dm-signal.md" "$TODAY"
    _create_context "context/dm-signal-core.md" "$TODAY"
    _create_context "context/dm-signal-research.md" "$STALE_DATE"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "dm-signal split contexts use scoped source pathspecs" {
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$TEST_TMPDIR/projects" "$source_repo/backend/app/jobs"
    cat > "$TEST_TMPDIR/projects/dm-signal.yaml" <<PROJ
project:
  id: dm-signal
path: $source_repo
PROJ

    _create_context "context/dm-signal-frontend.md" "$STALE_DATE"
    _create_context "context/dm-signal-research.md" "$STALE_DATE"
    _create_context "context/dm-signal-ops.md" "$STALE_DATE"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"

    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'backend update\n' > "$source_repo/backend/app/jobs/recalculate_fast.py"
    git -C "$source_repo" add backend/app/jobs/recalculate_fast.py
    GIT_AUTHOR_DATE="${TODAY}T00:00:00+09:00" \
    GIT_COMMITTER_DATE="${TODAY}T00:00:00+09:00" \
        git -C "$source_repo" commit -q -m "test: backend ops update"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"context/dm-signal-ops.md"* ]]
    [[ "$output" != *"context/dm-signal-frontend.md"* ]]
    [[ "$output" != *"context/dm-signal-research.md"* ]]
}

@test "--dashboard-warnings excludes low-frequency context files" {
    _create_context "context/README.md" "$STALE_DATE"
    _create_context "context/cdp-philosophy.md" "$STALE_DATE"
    _create_context "context/cdp-severity.md" "$STALE_DATE"
    _create_context "context/checklist-alm-registration.md" "$STALE_DATE"
    _create_context "context/checklist-shin-v2-registration.md" "$STALE_DATE"
    _create_context "context/checklist-ward-fof-production.md" "$STALE_DATE"
    _create_context "context/infrastructure.md" "$STALE_DATE"
    _create_source_commit "scripts/source_change.sh"
    _create_archive_cmd "cmd_900" "infra" "completed" "$TODAY"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"context/infrastructure.md"* ]]
    [[ "$output" != *"README.md"* ]]
    [[ "$output" != *"cdp-philosophy.md"* ]]
    [[ "$output" != *"cdp-severity.md"* ]]
    [[ "$output" != *"checklist-alm-registration.md"* ]]
    [[ "$output" != *"checklist-shin-v2-registration.md"* ]]
    [[ "$output" != *"checklist-ward-fof-production.md"* ]]
}

@test "--dashboard-warnings excludes context listed by exclude-list path and keeps non-listed alerts" {
    cat >> "$CONTEXT_FRESHNESS_EXCLUDE_LIST" <<'EOF'
context/gunshi-opt12-analysis.md
EOF
    _create_context "context/gunshi-opt12-analysis.md" "$STALE_DATE"
    _create_context "context/infrastructure.md" "$STALE_DATE"
    _create_source_commit "scripts/source_change.sh"
    _create_archive_cmd "cmd_900" "infra" "completed" "$TODAY"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" != *"context/gunshi-opt12-analysis.md"* ]]
    [[ "$output" == *"context/infrastructure.md"* ]]
}

@test "missing exclude list fails safely" {
    CONTEXT_FRESHNESS_EXCLUDE_LIST="$TEST_TMPDIR/config/missing_excludes.txt" \
        run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 1 ]
    [[ "$output" == *"context freshness exclude list not found"* ]]
}

# === Test 6: --dashboard-warnings last_updated未記載 → WARN "未記載" ===
@test "--dashboard-warnings with missing last_updated → WARN 未記載" {
    _create_context "context/dm-signal.md"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN:"* ]]
    [[ "$output" == *"未記載"* ]]
}

# === Test 7: --cmd-warnings 有効cmd_id → 該当PJのWARN ===
@test "--cmd-warnings with valid cmd_id → warnings for that project" {
    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_context "context/infrastructure.md" "$STALE_DATE"
    _create_source_commit "src/dm_signal.py"
    _create_shogun_to_karo "cmd_500" "dm-signal"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_500
    [ "$status" -eq 0 ]
    [[ "$output" == *"context/dm-signal.md"* ]]
    # infra context should NOT appear (different project)
    [[ "$output" != *"infrastructure.md"* ]]
}

@test "--cmd-warnings excludes low-frequency context files" {
    _create_context "context/README.md" "$STALE_DATE"
    _create_context "context/cdp-philosophy.md" "$STALE_DATE"
    _create_context "context/cdp-severity.md" "$STALE_DATE"
    _create_context "context/checklist-alm-registration.md" "$STALE_DATE"
    _create_context "context/checklist-shin-v2-registration.md" "$STALE_DATE"
    _create_context "context/checklist-ward-fof-production.md" "$STALE_DATE"
    _create_context "context/infrastructure.md" "$STALE_DATE"
    _create_source_commit "scripts/source_change.sh"
    _create_shogun_to_karo "cmd_503" "infra"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_503
    [ "$status" -eq 0 ]
    [[ "$output" == *"context/infrastructure.md"* ]]
    [[ "$output" != *"README.md"* ]]
    [[ "$output" != *"cdp-philosophy.md"* ]]
    [[ "$output" != *"cdp-severity.md"* ]]
    [[ "$output" != *"checklist-alm-registration.md"* ]]
    [[ "$output" != *"checklist-shin-v2-registration.md"* ]]
    [[ "$output" != *"checklist-ward-fof-production.md"* ]]
}

@test "--cmd-warnings reads shogun_to_karo mapping command format" {
    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_context "context/infrastructure.md" "$STALE_DATE"
    _create_source_commit "src/dm_signal.py"
    _create_shogun_to_karo_mapping "cmd_502" "dm-signal"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_502
    [ "$status" -eq 0 ]
    [[ "$output" == *"context/dm-signal.md"* ]]
    [[ "$output" != *"infrastructure.md"* ]]
}

@test "--cmd-warnings finds project from archived nested command format" {
    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_context "context/infrastructure.md" "$STALE_DATE"
    _create_source_commit "src/dm_signal.py"
    _create_nested_archive_cmd "cmd_501" "dm-signal" "done" "$TODAY"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_501
    [ "$status" -eq 0 ]
    [[ "$output" == *"context/dm-signal.md"* ]]
    [[ "$output" != *"infrastructure.md"* ]]
}

# === Test 8: auto-commit filter ===
@test "auto-commit source commits are ignored" {
    local rel_path="context/dm-signal.md"
    local abs_path="$TEST_TMPDIR/$rel_path"
    mkdir -p "$(dirname "$abs_path")"
    printf '<!-- last_updated: %s -->\n# Context\nSome content\n' "$STALE_DATE" > "$abs_path"
    git -C "$TEST_TMPDIR" add "$rel_path"
    git -C "$TEST_TMPDIR" commit -q -m "chore: auto-commit before /clear (hayate) — 運用ファイル"
    _create_context "context/dm-signal-core.md" "$TODAY"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# === Test 9: 最近の完了cmdなしPJ → 警告スキップ(dashboard) ===
@test "--dashboard-warnings skips projects without recent completed cmds" {
    _create_context "context/dm-signal.md" "$STALE_DATE"
    # archive空: dm-signalに最近の完了cmdなし

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# === Test 10: 古いarchive cmdは閾値外として無視される ===
@test "--dashboard-warnings ignores archive cmds older than threshold days" {
    local ten_days_ago
    ten_days_ago="$(date -d '10 days ago' +%Y-%m-%d 2>/dev/null || date -v-10d +%Y-%m-%d)"

    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_source_commit "src/dm_signal.py"
    _create_archive_cmd "cmd_850" "dm-signal" "completed" "$ten_days_ago"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    CONTEXT_STALE_DAYS=14 run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"context/dm-signal.md"* ]]
}

@test "--dashboard-warnings reads nested archived command format" {
    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_source_commit "src/dm_signal.py"
    _create_nested_archive_cmd "cmd_910" "dm-signal" "done" "$TODAY"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"context/dm-signal.md"* ]]
}

@test "--dashboard-warnings uses fresh cmd-chronicle as fast index" {
    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_source_commit "src/dm_signal.py"
    _create_cmd_chronicle "cmd_920" "dm-signal"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"context/dm-signal.md"* ]]
}

@test "--cmd-warnings finds project from cmd-chronicle" {
    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_context "context/infrastructure.md" "$STALE_DATE"
    _create_source_commit "src/dm_signal.py"
    _create_cmd_chronicle "cmd_921" "dm-signal"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_921
    [ "$status" -eq 0 ]
    [[ "$output" == *"context/dm-signal.md"* ]]
    [[ "$output" != *"infrastructure.md"* ]]
}

@test "dm-signal context uses external project git log" {
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$source_repo/docs/rule" "$TEST_TMPDIR/projects"
    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'project:\n  id: dm-signal\n  path: "%s"\n' "$source_repo" > "$TEST_TMPDIR/projects/dm-signal.yaml"
    printf 'runbook\n' > "$source_repo/docs/rule/db-operations-runbook.md"
    git -C "$source_repo" add docs/rule/db-operations-runbook.md
    git -C "$source_repo" commit -q -m "feature: source project changed"

    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_context "context/infrastructure.md" "$STALE_DATE"
    _create_shogun_to_karo "cmd_930" "dm-signal"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_930
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: context/dm-signal.md source commits"* ]]
    [[ "$output" != *"infrastructure.md"* ]]
}

@test "dm-signal root and core contexts ignore unrelated external commits" {
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$source_repo/marketing-director/content" "$TEST_TMPDIR/projects"
    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'project:\n  id: dm-signal\n  path: "%s"\n' "$source_repo" > "$TEST_TMPDIR/projects/dm-signal.yaml"
    printf 'article\n' > "$source_repo/marketing-director/content/article.md"
    git -C "$source_repo" add marketing-director/content/article.md
    git -C "$source_repo" commit -q -m "docs: unrelated marketing update"

    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_context "context/dm-signal-core.md" "$STALE_DATE"
    _create_shogun_to_karo "cmd_932" "dm-signal"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_932
    [ "$status" -eq 0 ]
    [[ "$output" != *"context/dm-signal.md"* ]]
    [[ "$output" != *"context/dm-signal-core.md"* ]]
}

@test "infra context uses same-repo path git log" {
    _create_context "context/infrastructure.md" "$STALE_DATE"
    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_source_commit "scripts/source_change.sh"
    _create_shogun_to_karo "cmd_931" "infra"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_931
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: context/infrastructure.md source commits"* ]]
    [[ "$output" != *"dm-signal.md"* ]]
}

@test "infra scoped contexts do not share root fallback counts" {
    _create_context "context/codd.md" "$STALE_DATE"
    _create_context "context/obsidian-link-principles.md" "$STALE_DATE"
    _create_source_commit "scripts/codd/generate.py" "test: codd source changed"
    _create_shogun_to_karo "cmd_933" "infra"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_933
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: context/codd.md source commits 1件"* ]]
    [[ "$output" != *"context/obsidian-link-principles.md source commits 1件"* ]]
}

@test "git timeout is reported instead of treated as zero source commits" {
    _create_context "context/codd.md" "$STALE_DATE"
    _create_source_commit "scripts/codd/generate.py" "test: codd source changed"
    _create_shogun_to_karo "cmd_934" "infra"

    CFC_GIT_TIMEOUT=0 run bash "$TEST_SCRIPT" --cmd-warnings cmd_934
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: context/codd.md source commit check failed"* ]]
}
