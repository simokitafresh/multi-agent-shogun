#!/usr/bin/env bats
# test_context_freshness_check.bats — context_freshness_check.sh unit tests
# cmd_1559: 鮮度判定ロジック/古いファイル検出/出力フォーマットのテスト可能分岐を検証

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/context_freshness_check.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1

    export CFC_MASTER_FIXTURE="$BATS_FILE_TMPDIR/master"
    mkdir -p "$CFC_MASTER_FIXTURE/scripts/config" \
             "$CFC_MASTER_FIXTURE/config" \
             "$CFC_MASTER_FIXTURE/context" \
             "$CFC_MASTER_FIXTURE/queue/archive/cmds" \
             "$CFC_MASTER_FIXTURE/queue"
    cp "$SRC_SCRIPT" "$CFC_MASTER_FIXTURE/scripts/context_freshness_check.sh"
    cp "$PROJECT_ROOT/scripts/config/context_source_commits.tsv" "$CFC_MASTER_FIXTURE/scripts/config/context_source_commits.tsv"
    chmod +x "$CFC_MASTER_FIXTURE/scripts/context_freshness_check.sh"

    cat > "$CFC_MASTER_FIXTURE/config/projects.yaml" <<'PROJYAML'
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

    cat > "$CFC_MASTER_FIXTURE/config/context_freshness_excludes.txt" <<'EOF'
context/README.md
context/cdp-philosophy.md
context/cdp-severity.md
context/checklist-alm-registration.md
context/checklist-shin-v2-registration.md
context/checklist-ward-fof-production.md
EOF

    git -C "$CFC_MASTER_FIXTURE" init -q
    git -C "$CFC_MASTER_FIXTURE" config user.email "test@example.invalid"
    git -C "$CFC_MASTER_FIXTURE" config user.name "Test User"
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/cfc.XXXXXX")"
    cp -a "$CFC_MASTER_FIXTURE/." "$TEST_TMPDIR/"

    # Helper: today and stale date strings
    TODAY="$(date +%Y-%m-%d)"
    STALE_DATE="$(date -d '30 days ago' +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d)"

    export TEST_SCRIPT="$TEST_TMPDIR/scripts/context_freshness_check.sh"
    export CFC_ARCHIVE_CACHE="$TEST_TMPDIR/context_freshness_cache.txt"
    export CONTEXT_FRESHNESS_EXCLUDE_LIST="$TEST_TMPDIR/config/context_freshness_excludes.txt"
    export CFC_OUTPUT_CACHE_TTL=0
    export CFC_REQUIRE_SOURCE_COMMIT=0

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

@test "source_commit marker prevents same-day commits before context refresh from re-alerting" {
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$source_repo/backend/app" "$TEST_TMPDIR/projects"
    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'project:\n  id: dm-signal\n  path: "%s"\n' "$source_repo" > "$TEST_TMPDIR/projects/dm-signal.yaml"

    printf 'v1\n' > "$source_repo/backend/app/core.py"
    git -C "$source_repo" add backend/app/core.py
    git -C "$source_repo" commit -q -m "feature: first same-day source change"
    local first_sha
    first_sha="$(git -C "$source_repo" rev-parse --short HEAD)"

    _create_context "context/dm-signal-core.md" "$TODAY"
    sed -i "1s/ -->/ source_commit:${first_sha} -->/" "$TEST_TMPDIR/context/dm-signal-core.md"
    _create_shogun_to_karo "cmd_938" "dm-signal"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_938
    [ "$status" -eq 0 ]
    [[ "$output" != *"context/dm-signal-core.md source commits"* ]]

    printf 'v2\n' >> "$source_repo/backend/app/core.py"
    git -C "$source_repo" add backend/app/core.py
    git -C "$source_repo" commit -q -m "feature: later same-day source change"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_938
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: context/dm-signal-core.md source commits 1件"* ]]
}

@test "GA-245 registered context without source_commit fails fast before git log" {
    mkdir -p "$TEST_TMPDIR/scripts/config"
    cp "$PROJECT_ROOT/scripts/config/context_source_commits.tsv" "$TEST_TMPDIR/scripts/config/context_source_commits.tsv"
    _create_context "context/dm-signal.md" "$TODAY"
    _create_archive_cmd "cmd_ga245_fixture" "dm-signal"
    mkdir -p "$TEST_TMPDIR/bin"
    cat > "$TEST_TMPDIR/bin/git" <<'EOF'
#!/usr/bin/env bash
echo called >> "$TEST_TMPDIR/git-calls.log"
exec /usr/bin/git "$@"
EOF
    chmod +x "$TEST_TMPDIR/bin/git"
    rm -f "$TEST_TMPDIR/git-calls.log"
    PATH="$TEST_TMPDIR/bin:$PATH" CFC_OUTPUT_CACHE_TTL=0 CFC_REQUIRE_SOURCE_COMMIT=1 run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"MISSING_SOURCE_COMMIT"* ]]
    [ ! -e "$TEST_TMPDIR/git-calls.log" ]
}

@test "GA-245 registered and enforced context sets are exact" {
    run python3 - "$SRC_SCRIPT" "$PROJECT_ROOT/scripts/config/context_source_commits.tsv" <<'PY'
import ast, re, sys
text=open(sys.argv[1], encoding='utf-8').read()
registered=dict(line.rstrip().split('\t') for line in open(sys.argv[2], encoding='utf-8') if line.strip() and not line.startswith('#'))
def mapping(name):
    match=re.search(rf'{name}: dict\[str, list\[str\]\] = (\{{.*?\n\}})', text, re.S)
    return ast.literal_eval(match.group(1))
expected={**{p:'dm-signal' for p in mapping('DM_SIGNAL_CONTEXT_PATHS')},
          **{p:'infra' for p in mapping('INFRA_CONTEXT_PATHS')},
          'context/infrastructure.md':'infra'}
assert registered == expected, (registered, expected)
print(f'registered={len(registered)} enforced={len(expected)}')
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"registered=10 enforced=10"* ]]
}

@test "GA-255 infrastructure context without source_commit blocks before git" {
    mkdir -p "$TEST_TMPDIR/scripts/config"
    cp "$PROJECT_ROOT/scripts/config/context_source_commits.tsv" "$TEST_TMPDIR/scripts/config/context_source_commits.tsv"
    _create_context "context/infrastructure.md" "$TODAY"
    _create_archive_cmd "cmd_ga255_fixture" "infra"
    mkdir -p "$TEST_TMPDIR/bin"
    cat > "$TEST_TMPDIR/bin/git" <<'EOF'
#!/usr/bin/env bash
echo called >> "$TEST_TMPDIR/git-calls.log"
exec /usr/bin/git "$@"
EOF
    chmod +x "$TEST_TMPDIR/bin/git"
    rm -f "$TEST_TMPDIR/git-calls.log"
    PATH="$TEST_TMPDIR/bin:$PATH" CFC_OUTPUT_CACHE_TTL=0 CFC_REQUIRE_SOURCE_COMMIT=1 run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"context/infrastructure.md MISSING_SOURCE_COMMIT"* ]]
    [ ! -e "$TEST_TMPDIR/git-calls.log" ]
}

@test "GA-245 new pathspec map key without registry row blocks before git" {
    sed -i '/DM_SIGNAL_CONTEXT_PATHS: dict/a\    "context/new-map-key.md": ["src"],' "$TEST_SCRIPT"
    CFC_OUTPUT_CACHE_TTL=0 run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -ne 0 ]
    [[ "$output" == *"registry/map mismatch"* ]]
}

@test "duplicate context_file mapping keeps dm-signal.md attached to dm-signal project" {
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$source_repo/docs/rule" "$TEST_TMPDIR/projects"
    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'project:\n  id: dm-signal\n  path: "%s"\n' "$source_repo" > "$TEST_TMPDIR/projects/dm-signal.yaml"
    printf 'runbook\n' > "$source_repo/docs/rule/db-operations-runbook.md"
    git -C "$source_repo" add docs/rule/db-operations-runbook.md
    GIT_AUTHOR_DATE="2020-01-01T00:00:00+09:00" \
    GIT_COMMITTER_DATE="2020-01-01T00:00:00+09:00" \
        git -C "$source_repo" commit -q -m "initial dm-signal source"

    cat >> "$TEST_TMPDIR/config/projects.yaml" <<'PROJ'
  - id: dm-fusion
    status: active
    path: /tmp/nonexistent-dm-fusion
    context_file: context/dm-signal.md
PROJ

    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_context "context/dm-signal-core.md" "$TODAY"
    _create_source_commit "scripts/infra_change.sh" "infra: unrelated root source changed"
    _create_shogun_to_karo "cmd_933" "dm-signal"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_933
    [ "$status" -eq 0 ]
    [[ "$output" != *"context/dm-signal.md"* ]]
}

@test "project path falls back to config/projects.yaml when project yaml is absent" {
    local source_repo="$TEST_TMPDIR/source/google-classroom"
    mkdir -p "$source_repo"
    cat >> "$TEST_TMPDIR/config/projects.yaml" <<PROJ
  - id: google-classroom
    status: active
    path: "$source_repo"
PROJ
    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'classroom update\n' > "$source_repo/app.py"
    git -C "$source_repo" add app.py
    GIT_AUTHOR_DATE="${TODAY}T00:00:00+09:00" \
    GIT_COMMITTER_DATE="${TODAY}T00:00:00+09:00" \
        git -C "$source_repo" commit -q -m "feature: classroom source changed"

    _create_context "context/google-classroom.md" "$STALE_DATE"
    _create_archive_cmd "cmd_940" "google-classroom" "completed" "$TODAY"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: context/google-classroom.md source commits 1件"* ]]
    [[ "$output" == *"latest: "* ]]
    [[ "$output" == *"feature: classroom source changed"* ]]
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

@test "unmapped infra fallback context does not inherit root source alerts" {
    _create_context "context/saxo-trade-engine.md" "$STALE_DATE"
    _create_context "context/infrastructure.md" "$STALE_DATE"
    _create_source_commit "scripts/source_change.sh"
    _create_archive_cmd "cmd_941" "infra" "completed" "$TODAY"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"context/infrastructure.md"* ]]
    [[ "$output" != *"context/saxo-trade-engine.md"* ]]
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

@test "infra root fallback ignores operational sync records" {
    _create_context "context/infrastructure.md" "$STALE_DATE"
    _create_source_commit "logs/cmd_design_quality.yaml" "chore: sync cmd3592 quality log"
    _create_source_commit "queue/tasks/kagemaru.yaml" "chore: sync cmd3591 deployment records"
    _create_source_commit "docs/semantic-index/index.md" "chore: complete cmd3590 records"
    _create_shogun_to_karo "cmd_935" "infra"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_935
    [ "$status" -eq 0 ]
    [[ "$output" != *"context/infrastructure.md source commits"* ]]
}

@test "infra root fallback ignores project research documents" {
    _create_context "context/infrastructure.md" "$STALE_DATE"
    _create_source_commit "docs/research/project-design.md" "docs: project design changed"
    _create_shogun_to_karo "cmd_937" "infra"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_937
    [ "$status" -eq 0 ]
    [[ "$output" != *"context/infrastructure.md source commits"* ]]
}

@test "infra root fallback source_commit marker prevents same-day re-alert" {
    _create_context "context/infrastructure.md" "$TODAY"
    _create_source_commit "scripts/first_change.sh" "fix: first infra source change"
    local first_sha
    first_sha="$(git -C "$TEST_TMPDIR" rev-parse --short HEAD)"
    sed -i "1s/ -->/ source_commit:${first_sha} -->/" "$TEST_TMPDIR/context/infrastructure.md"
    _create_shogun_to_karo "cmd_938" "infra"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_938
    [ "$status" -eq 0 ]
    [[ "$output" != *"context/infrastructure.md source commits"* ]]

    _create_source_commit "scripts/second_change.sh" "fix: second infra source change"
    run bash "$TEST_SCRIPT" --cmd-warnings cmd_938
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: context/infrastructure.md source commits 1件"* ]]
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

@test "obsidian principles ignores generated semantic index growth" {
    _create_context "context/obsidian-link-principles.md" "$STALE_DATE"
    _create_source_commit "docs/semantic-index/index.md" "chore: semantic aliases and records grew"
    _create_shogun_to_karo "cmd_936" "infra"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_936
    [ "$status" -eq 0 ]
    [[ "$output" != *"context/obsidian-link-principles.md source commits"* ]]
}

@test "git timeout is reported instead of treated as zero source commits" {
    _create_context "context/codd.md" "$STALE_DATE"
    _create_source_commit "scripts/codd/generate.py" "test: codd source changed"
    _create_shogun_to_karo "cmd_934" "infra"

    CFC_GIT_TIMEOUT=0 CFC_GIT_RETRY_TIMEOUT=0 run bash "$TEST_SCRIPT" --cmd-warnings cmd_934
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: context/codd.md source commit check failed"* ]]
}

@test "GA-253 transient git timeout retries once and preserves the source freshness result" {
    _create_context "context/codd.md" "$STALE_DATE"
    _create_source_commit "scripts/codd/generate.py" "test: codd source changed"
    _create_shogun_to_karo "cmd_934" "infra"
    local real_git counter_file fake_bin
    real_git="$(command -v git)"
    counter_file="$TEST_TMPDIR/git-log-count"
    fake_bin="$TEST_TMPDIR/fake-bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/git" <<'SH'
#!/usr/bin/env bash
if [[ " $* " == *" log "* ]]; then
    count=0
    [[ -f "$CFC_FAKE_GIT_COUNTER" ]] && count="$(cat "$CFC_FAKE_GIT_COUNTER")"
    count=$((count + 1))
    printf '%s\n' "$count" > "$CFC_FAKE_GIT_COUNTER"
    if (( count == 1 )); then sleep 0.2; fi
fi
exec "$CFC_REAL_GIT" "$@"
SH
    chmod +x "$fake_bin/git"

    PATH="$fake_bin:$PATH" CFC_REAL_GIT="$real_git" CFC_FAKE_GIT_COUNTER="$counter_file" \
      CFC_GIT_TIMEOUT=0.1 CFC_GIT_RETRY_TIMEOUT=0.3 run bash "$TEST_SCRIPT" --cmd-warnings cmd_934

    [ "$status" -eq 0 ]
    [ "$(cat "$counter_file")" -ge 2 ]
    [[ "$output" == *"ALERT: context/codd.md source commits 1件"* ]]
    [[ "$output" != *"source commit check failed"* ]]
}

@test "GA-253 persistent git timeout remains fail-closed after the bounded retry" {
    _create_context "context/codd.md" "$STALE_DATE"
    _create_source_commit "scripts/codd/generate.py" "test: codd source changed"
    _create_shogun_to_karo "cmd_934" "infra"
    local real_git counter_file fake_bin
    real_git="$(command -v git)"
    counter_file="$TEST_TMPDIR/git-log-count"
    fake_bin="$TEST_TMPDIR/fake-bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/git" <<'SH'
#!/usr/bin/env bash
if [[ " $* " == *" log "* ]]; then
    count=0
    [[ -f "$CFC_FAKE_GIT_COUNTER" ]] && count="$(cat "$CFC_FAKE_GIT_COUNTER")"
    printf '%s\n' "$((count + 1))" > "$CFC_FAKE_GIT_COUNTER"
    sleep 0.2
fi
exec "$CFC_REAL_GIT" "$@"
SH
    chmod +x "$fake_bin/git"

    PATH="$fake_bin:$PATH" CFC_REAL_GIT="$real_git" CFC_FAKE_GIT_COUNTER="$counter_file" \
      CFC_GIT_TIMEOUT=0.1 CFC_GIT_RETRY_TIMEOUT=0.1 run bash "$TEST_SCRIPT" --cmd-warnings cmd_934

    [ "$status" -eq 0 ]
    [ "$(cat "$counter_file")" -eq 2 ]
    [[ "$output" == *"WARN: context/codd.md source commit check failed"* ]]
}

@test "GA-253 persistent git returncode remains fail-closed after the bounded retry" {
    _create_context "context/codd.md" "$STALE_DATE"
    _create_source_commit "scripts/codd/generate.py" "test: codd source changed"
    _create_shogun_to_karo "cmd_934" "infra"
    local real_git counter_file fake_bin
    real_git="$(command -v git)"
    counter_file="$TEST_TMPDIR/git-log-count"
    fake_bin="$TEST_TMPDIR/fake-bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/git" <<'SH'
#!/usr/bin/env bash
if [[ " $* " == *" log "* ]]; then
    count=0
    [[ -f "$CFC_FAKE_GIT_COUNTER" ]] && count="$(cat "$CFC_FAKE_GIT_COUNTER")"
    printf '%s\n' "$((count + 1))" > "$CFC_FAKE_GIT_COUNTER"
    exit 17
fi
exec "$CFC_REAL_GIT" "$@"
SH
    chmod +x "$fake_bin/git"

    PATH="$fake_bin:$PATH" CFC_REAL_GIT="$real_git" CFC_FAKE_GIT_COUNTER="$counter_file" \
      CFC_GIT_TIMEOUT=1 CFC_GIT_RETRY_TIMEOUT=3 run bash "$TEST_SCRIPT" --cmd-warnings cmd_934

    [ "$status" -eq 0 ]
    [ "$(cat "$counter_file")" -eq 2 ]
    [[ "$output" == *"WARN: context/codd.md source commit check failed"* ]]
}

# ── GA-237/L1089: 共通防御層(GROUP検出) ──
# 根本原因: 高頻度共有pathspec(docs/research等)を持つ複数context fileが
# 同一source commitで同時ALERTし、家老が同じcommitを重複調査するcmdを
# 別々に起票していた。GROUP行は既存のALERT発火条件(件数閾値1、GA-226で
# 固定)を一切変更せず、可視性のみを追加する非破壊的な防御層。

@test "shared source commit across sibling contexts emits GROUP hint" {
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$TEST_TMPDIR/projects" "$source_repo/docs/research"
    cat > "$TEST_TMPDIR/projects/dm-signal.yaml" <<PROJ
project:
  id: dm-signal
path: $source_repo
PROJ

    local ops_path="$TEST_TMPDIR/context/dm-signal-ops.md"
    printf '<!-- last_updated: %s -->\n# ops\nSee `docs/research/shared_note.md` for details.\n' \
        "$STALE_DATE" > "$ops_path"
    git -C "$TEST_TMPDIR" add "context/dm-signal-ops.md"
    git -C "$TEST_TMPDIR" commit -q -m "test source update for context/dm-signal-ops.md"
    _create_context "context/dm-signal-research.md" "$STALE_DATE"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"

    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'shared research note\n' > "$source_repo/docs/research/shared_note.md"
    git -C "$source_repo" add docs/research/shared_note.md
    GIT_AUTHOR_DATE="${TODAY}T00:00:00+09:00" \
    GIT_COMMITTER_DATE="${TODAY}T00:00:00+09:00" \
        git -C "$source_repo" commit -q -m "docs: shared research note touches both ops and research contexts"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: context/dm-signal-ops.md source commits"* ]]
    [[ "$output" == *"ALERT: context/dm-signal-research.md source commits"* ]]
    [[ "$output" == *"GROUP: context/dm-signal-ops.md,context/dm-signal-research.md share source commit"* ]]
    [[ "$output" == *"L1089"* ]]
}

@test "different source commits across sibling contexts do not emit GROUP hint" {
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$TEST_TMPDIR/projects" "$source_repo/backend/app/jobs" "$source_repo/frontend"
    cat > "$TEST_TMPDIR/projects/dm-signal.yaml" <<PROJ
project:
  id: dm-signal
path: $source_repo
PROJ

    _create_context "context/dm-signal-ops.md" "$STALE_DATE"
    _create_context "context/dm-signal-frontend.md" "$STALE_DATE"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"

    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'ops backend update\n' > "$source_repo/backend/app/jobs/recalculate_fast.py"
    git -C "$source_repo" add backend/app/jobs/recalculate_fast.py
    GIT_AUTHOR_DATE="${TODAY}T00:00:00+09:00" \
    GIT_COMMITTER_DATE="${TODAY}T00:00:00+09:00" \
        git -C "$source_repo" commit -q -m "fix: ops-only backend change"

    printf 'frontend update\n' > "$source_repo/frontend/app.tsx"
    git -C "$source_repo" add frontend/app.tsx
    GIT_AUTHOR_DATE="${TODAY}T00:01:00+09:00" \
    GIT_COMMITTER_DATE="${TODAY}T00:01:00+09:00" \
        git -C "$source_repo" commit -q -m "feature: frontend-only change"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: context/dm-signal-ops.md source commits"* ]]
    [[ "$output" == *"ALERT: context/dm-signal-frontend.md source commits"* ]]
    [[ "$output" != *"GROUP:"* ]]
}

@test "dashboard-warnings tolerates a linked worktree in the source repo" {
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$TEST_TMPDIR/projects" "$source_repo/backend/app/jobs"
    cat > "$TEST_TMPDIR/projects/dm-signal.yaml" <<PROJ
project:
  id: dm-signal
path: $source_repo
PROJ

    _create_context "context/dm-signal-ops.md" "$STALE_DATE"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"

    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'ops backend update\n' > "$source_repo/backend/app/jobs/recalculate_fast.py"
    git -C "$source_repo" add backend/app/jobs/recalculate_fast.py
    GIT_AUTHOR_DATE="${TODAY}T00:00:00+09:00" \
    GIT_COMMITTER_DATE="${TODAY}T00:00:00+09:00" \
        git -C "$source_repo" commit -q -m "fix: ops-only backend change"

    # 忍者worktreeが並行稼働している状況を模す(linked worktree)
    git -C "$source_repo" worktree add -q "$TEST_TMPDIR/source/dm-signal-worktree" -b cmd_worker_branch >/dev/null 2>&1

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: context/dm-signal-ops.md source commits 1件"* ]]
    [[ "$output" != *"GROUP:"* ]]
}

@test "concurrent dashboard-warnings invocations do not corrupt cache output" {
    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_source_commit "src/dm_signal.py"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"

    CFC_OUTPUT_CACHE_TTL=5 bash "$TEST_SCRIPT" --dashboard-warnings > "$TEST_TMPDIR/out1.txt" 2>"$TEST_TMPDIR/err1.txt" &
    local pid1=$!
    CFC_OUTPUT_CACHE_TTL=5 bash "$TEST_SCRIPT" --dashboard-warnings > "$TEST_TMPDIR/out2.txt" 2>"$TEST_TMPDIR/err2.txt" &
    local pid2=$!

    wait "$pid1"
    local status1=$?
    wait "$pid2"
    local status2=$?

    [ "$status1" -eq 0 ]
    [ "$status2" -eq 0 ]
    grep -q "ALERT: context/dm-signal.md source commits" "$TEST_TMPDIR/out1.txt"
    grep -q "ALERT: context/dm-signal.md source commits" "$TEST_TMPDIR/out2.txt"
}

@test "git timeout does not produce a spurious GROUP line" {
    _create_context "context/codd.md" "$STALE_DATE"
    _create_context "context/obsidian-link-principles.md" "$STALE_DATE"
    _create_source_commit "scripts/codd/generate.py" "test: codd source changed"
    _create_shogun_to_karo "cmd_934" "infra"

    CFC_GIT_TIMEOUT=0 CFC_GIT_RETRY_TIMEOUT=0 run bash "$TEST_SCRIPT" --cmd-warnings cmd_934
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: context/codd.md source commit check failed"* ]]
    [[ "$output" != *"GROUP:"* ]]
}

# ── GA-237 karo RC(0件化要求): docs/research配下の"cited:"pathspecは、context本文が
# 既に名指し引用しているファイルへの変更だけを関連commitとして数える。同一fixture
# (ops.mdが引用していないdocs/researchファイルへの単発commit)の再現をmin_source_commits
# を緩めずに0件へ抑え、引用済みファイルへの変更は真陽性のままALERTすることを検証する。

@test "cited pathspec ignores commits to docs/research files the context never cites (false positive → 0)" {
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$TEST_TMPDIR/projects" "$source_repo/docs/research"
    cat > "$TEST_TMPDIR/projects/dm-signal.yaml" <<PROJ
project:
  id: dm-signal
path: $source_repo
PROJ

    local abs_path="$TEST_TMPDIR/context/dm-signal-ops.md"
    mkdir -p "$(dirname "$abs_path")"
    printf '<!-- last_updated: %s -->\n# ops\nSee `docs/research/cmd_100_recalc_status.md` for details.\n' \
        "$STALE_DATE" > "$abs_path"
    git -C "$TEST_TMPDIR" add "context/dm-signal-ops.md"
    git -C "$TEST_TMPDIR" commit -q -m "test source update for context/dm-signal-ops.md"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"

    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'unrelated topic\n' > "$source_repo/docs/research/cmd_200_gs_precompute.md"
    git -C "$source_repo" add docs/research/cmd_200_gs_precompute.md
    GIT_AUTHOR_DATE="${TODAY}T00:00:00+09:00" \
    GIT_COMMITTER_DATE="${TODAY}T00:00:00+09:00" \
        git -C "$source_repo" commit -q -m "docs: unrelated GS precompute progress note, never cited by ops.md"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" != *"context/dm-signal-ops.md source commits"* ]]
}

@test "cited pathspec still alerts when a cited docs/research file changes (true positive preserved)" {
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$TEST_TMPDIR/projects" "$source_repo/docs/research"
    cat > "$TEST_TMPDIR/projects/dm-signal.yaml" <<PROJ
project:
  id: dm-signal
path: $source_repo
PROJ

    local abs_path="$TEST_TMPDIR/context/dm-signal-ops.md"
    mkdir -p "$(dirname "$abs_path")"
    printf '<!-- last_updated: %s -->\n# ops\nSee `docs/research/cmd_100_recalc_status.md` for details.\n' \
        "$STALE_DATE" > "$abs_path"
    git -C "$TEST_TMPDIR" add "context/dm-signal-ops.md"
    git -C "$TEST_TMPDIR" commit -q -m "test source update for context/dm-signal-ops.md"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"

    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'recalc status update\n' > "$source_repo/docs/research/cmd_100_recalc_status.md"
    git -C "$source_repo" add docs/research/cmd_100_recalc_status.md
    GIT_AUTHOR_DATE="${TODAY}T00:00:00+09:00" \
    GIT_COMMITTER_DATE="${TODAY}T00:00:00+09:00" \
        git -C "$source_repo" commit -q -m "docs: recalc status update, cited by ops.md"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: context/dm-signal-ops.md source commits 1件"* ]]
    [[ "$output" == *"docs: recalc status update, cited by ops.md"* ]]
}

@test "cited pathspec still alerts on plain (non-cited) pathspec entries like backend/app/jobs" {
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$TEST_TMPDIR/projects" "$source_repo/backend/app/jobs"
    cat > "$TEST_TMPDIR/projects/dm-signal.yaml" <<PROJ
project:
  id: dm-signal
path: $source_repo
PROJ

    _create_context "context/dm-signal-ops.md" "$STALE_DATE"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"

    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'backend job change\n' > "$source_repo/backend/app/jobs/recalculate_fast.py"
    git -C "$source_repo" add backend/app/jobs/recalculate_fast.py
    GIT_AUTHOR_DATE="${TODAY}T00:00:00+09:00" \
    GIT_COMMITTER_DATE="${TODAY}T00:00:00+09:00" \
        git -C "$source_repo" commit -q -m "fix: backend job change unrelated to docs/research"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: context/dm-signal-ops.md source commits 1件"* ]]
}
