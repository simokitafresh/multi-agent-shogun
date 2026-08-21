#!/usr/bin/env bats
# test_necessity: context鮮度判定は対象pathの関連commitだけを根拠にしstaleをfreshへ誤分類しない
# test_context_freshness_check.bats — context_freshness_check.sh unit tests
# cmd_1559: 鮮度判定ロジック/古いファイル検出/出力フォーマットのテスト可能分岐を検証

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/context_freshness_check.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
    command -v python3 >/dev/null 2>&1 || return 1

    # BATS_FILE_TMPDIR can be shared when two full-suite invocations overlap.
    # Give each file invocation its own immutable source fixture so counter,
    # cache, and git state never leak across concurrently running suites.
    CFC_MASTER_FIXTURE="$(mktemp -d "$BATS_FILE_TMPDIR/cfc-master.XXXXXX")"
    export CFC_MASTER_FIXTURE
    mkdir -p "$CFC_MASTER_FIXTURE/scripts/config" \
             "$CFC_MASTER_FIXTURE/config" \
             "$CFC_MASTER_FIXTURE/context" \
             "$CFC_MASTER_FIXTURE/queue/archive/cmds" \
             "$CFC_MASTER_FIXTURE/queue"
    cp "$SRC_SCRIPT" "$CFC_MASTER_FIXTURE/scripts/context_freshness_check.sh"
    cp "$PROJECT_ROOT/scripts/context_history_snapshot_refresh.sh" "$CFC_MASTER_FIXTURE/scripts/context_history_snapshot_refresh.sh"
    cp "$PROJECT_ROOT/scripts/config/context_source_commits.tsv" "$CFC_MASTER_FIXTURE/scripts/config/context_source_commits.tsv"
    chmod +x "$CFC_MASTER_FIXTURE/scripts/context_freshness_check.sh"
    chmod +x "$CFC_MASTER_FIXTURE/scripts/context_history_snapshot_refresh.sh"

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
    export CFC_HISTORY_CACHE_DIR="$TEST_TMPDIR/history-cache"
    export CFC_HISTORY_REFRESH_SYNC=1

}

_wait_history_snapshot() {
    local i
    for i in {1..100}; do
        find "$CFC_HISTORY_CACHE_DIR" -name '*.json' -type f -size +0c 2>/dev/null | grep -q . && return 0
        sleep 0.05
    done
    return 1
}

teardown() {
    unset CFC_OUTPUT_CACHE_TTL
    # Async history refresh may still hold/create its ext4 snapshot while the
    # test body has already returned.  Drain the bounded producer lock before
    # deleting the fixture; otherwise teardown races os.replace and reports a
    # false test failure (Directory not empty).
    if [ -n "${CFC_HISTORY_CACHE_DIR:-}" ] && [ -d "$CFC_HISTORY_CACHE_DIR" ]; then
        for _ in {1..100}; do
            active=0
            for lock in "$CFC_HISTORY_CACHE_DIR"/*.lock; do
                [ -e "$lock" ] || continue
                if command -v fuser >/dev/null 2>&1 && fuser "$lock" >/dev/null 2>&1; then
                    active=1
                    break
                fi
            done
            [ "$active" -eq 0 ] && break
            sleep 0.02
        done
    fi
    [ -n "$TEST_TMPDIR" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

@test "GA-286 history cache reuses success, invalidates on commit, and ignores corruption" {
    export CFC_HISTORY_REFRESH_SYNC=0
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$source_repo" "$TEST_TMPDIR/projects"
    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'project:\n  id: dm-signal\n  path: "%s"\n' "$source_repo" > "$TEST_TMPDIR/projects/dm-signal.yaml"
    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"
    _create_source_commit "docs/rule/db-operations-runbook.md" "test: first source update" "$source_repo"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"source commit check failed"* ]]
    _wait_history_snapshot
    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"source commits"* ]]
    [ "$(find "$CFC_HISTORY_CACHE_DIR" -name '*.json' | wc -l)" -ge 1 ]

    local cache_file
    cache_file="$(find "$CFC_HISTORY_CACHE_DIR" -name '*.json' | head -1)"
    printf '{broken' > "$cache_file"
    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"source commit check failed"* ]]
    rm -f "$cache_file"
    _wait_history_snapshot
    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"source commits"* ]]

    local before_count
    before_count="$(find "$CFC_HISTORY_CACHE_DIR" -name '*.json' | wc -l)"
    _create_source_commit "docs/rule/db-operations-runbook.md" "test: second source update" "$source_repo"
    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"source commit check failed"* ]]
    while [ "$(find "$CFC_HISTORY_CACHE_DIR" -name '*.json' | wc -l)" -le "$before_count" ]; do sleep 0.05; done
    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"source commits 2件"* ]]
    [ "$(find "$CFC_HISTORY_CACHE_DIR" -name '*.json' | wc -l)" -gt "$before_count" ]
}

@test "GA-286 history cache warm lookup bypasses failing git log and stays fail-closed when cold" {
    export CFC_HISTORY_REFRESH_SYNC=0
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$source_repo" "$TEST_TMPDIR/projects"
    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'project:\n  id: dm-signal\n  path: "%s"\n' "$source_repo" > "$TEST_TMPDIR/projects/dm-signal.yaml"
    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"
    _create_source_commit "docs/rule/db-operations-runbook.md" "test: cacheable source update" "$source_repo"
    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    _wait_history_snapshot
    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]

    mkdir -p "$TEST_TMPDIR/fake-bin"
    local real_git
    real_git="$(command -v git)"
    cat > "$TEST_TMPDIR/fake-bin/git" <<EOF
#!/usr/bin/env bash
if [[ " \$* " == *" log "* ]]; then exit 91; fi
exec "$real_git" "\$@"
EOF
    chmod +x "$TEST_TMPDIR/fake-bin/git"

    PATH="$TEST_TMPDIR/fake-bin:$PATH" run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"source commits"* ]]

    local max_ms=0 start_ns elapsed_ms
    for _ in {1..10}; do
        start_ns="$(date +%s%N)"
        PATH="$TEST_TMPDIR/fake-bin:$PATH" bash "$TEST_SCRIPT" --dashboard-warnings >/dev/null
        elapsed_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))
        [ "$elapsed_ms" -gt "$max_ms" ] && max_ms="$elapsed_ms"
    done
    # With ten samples the maximum is a conservative upper bound for p95.
    [ "$max_ms" -le 3445 ]

    rm -f "$CFC_HISTORY_CACHE_DIR"/*.json
    PATH="$TEST_TMPDIR/fake-bin:$PATH" CFC_GIT_TIMEOUT=0.1 CFC_GIT_RETRY_TIMEOUT=0.1 \
        run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"source commit check failed"* ]]
}

@test "GA-291 warm snapshot consumer performs zero git subprocesses and rejects corrupt generation" {
    export CFC_HISTORY_REFRESH_SYNC=1
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$source_repo" "$TEST_TMPDIR/projects"
    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email test@example.invalid
    git -C "$source_repo" config user.name test
    printf 'project:\n  id: dm-signal\n  path: "%s"\n' "$source_repo" > "$TEST_TMPDIR/projects/dm-signal.yaml"
    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"
    _create_source_commit "docs/rule/db-operations-runbook.md" "test: source update" "$source_repo"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    _wait_history_snapshot

    mkdir -p "$TEST_TMPDIR/no-git"
    cat > "$TEST_TMPDIR/no-git/git" <<'GIT'
#!/usr/bin/env bash
echo called >> "${CFC_GIT_CALL_LOG:?}"
exit 91
GIT
    chmod +x "$TEST_TMPDIR/no-git/git"
    export CFC_GIT_CALL_LOG="$TEST_TMPDIR/git-calls"
    run env PATH="$TEST_TMPDIR/no-git:$PATH" bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [ ! -e "$CFC_GIT_CALL_LOG" ]
    [[ "$output" == *"source commits"* ]]

    snapshot="$(find "$CFC_HISTORY_CACHE_DIR" -name '*.json' -type f | head -1)"
    printf '{corrupt' > "$snapshot"
    run env PATH="$TEST_TMPDIR/no-git:$PATH" CFC_HISTORY_REFRESH_SYNC=0 bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" == *"source commit check failed"* ]]
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
    local rel_path="${1:-src/source.txt}" subject="${2:-test: source project changed}" repo="${3:-$TEST_TMPDIR}"
    local abs_path="$repo/$rel_path"
    mkdir -p "$(dirname "$abs_path")"
    printf 'source update\n' >> "$abs_path"
    git -C "$repo" add "$rel_path"
    GIT_AUTHOR_DATE="${TODAY}T00:00:00+09:00" \
    GIT_COMMITTER_DATE="${TODAY}T00:00:00+09:00" \
        git -C "$repo" commit -q -m "$subject"
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

# test_necessity: GA-487のdoc laneがsource commit集合を再調査せず全件受け取れる不変量
@test "GA-487 dashboard warning publishes the complete source commit set" {
    local source_repo="$TEST_TMPDIR"
    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_shogun_to_karo "cmd_500" "dm-signal"

    for n in 1 2 3 4; do
        _create_source_commit "src/ga487-$n.py" "feature: GA-487 source update $n" "$source_repo"
    done

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_500
    [ "$status" -eq 0 ]
    [[ "$output" == *"source commits 4件"* ]]
    [[ "$output" == *"source_commit_set_count=4"* ]]
    [[ "$output" == *"feature: GA-487 source update 1"* ]]
    [[ "$output" == *"feature: GA-487 source update 4"* ]]
}

@test "GA-276 dashboard ignores unpushed local commit while cmd mode detects it" {
    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_archive_cmd "cmd_900" "dm-signal" "completed" "$TODAY"
    _create_shogun_to_karo "cmd_901" "dm-signal"

    # Shared completed boundary.  The next commit represents a ninja's local
    # implementation before cmd_complete_gate/context reflux.
    git -C "$TEST_TMPDIR" update-ref refs/remotes/origin/main HEAD
    _create_source_commit "src/dm_signal.py" "cmd_901: local implementation"

    run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" != *"source commits"* ]]
    [[ "$output" != *"cmd_901: local implementation"* ]]

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_901
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT:"* ]]
    [[ "$output" == *"cmd_901: local implementation"* ]]
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

# GA-466 test_necessity: the runtime freshness detector must consume the same source
# registry as task dependency injection; adding a trigger must not require a
# second hardcoded map or silently produce a false-negative alert (GA-466).
@test "GA-466 registry trigger reaches freshness detector without map patch" {
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$TEST_TMPDIR/projects" "$source_repo/backend/new_surface"
    cat > "$TEST_TMPDIR/projects/dm-signal.yaml" <<PROJ
project:
  id: dm-signal
path: $source_repo
PROJ

    # Simulate a newly discovered dependency added to the existing SSOT.
    sed -i 's#backend/app|backend/tests#backend/app|backend/new_surface|backend/tests#' \
        "$TEST_TMPDIR/scripts/config/context_source_commits.tsv"
    _create_context "context/dm-signal-core.md" "$STALE_DATE"
    _create_shogun_to_karo "cmd_ga466_fixture" "dm-signal"
    _create_archive_cmd "cmd_ga466_fixture" "dm-signal" "completed" "$TODAY"

    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'new dependency surface\n' > "$source_repo/backend/new_surface/runtime.py"
    git -C "$source_repo" add backend/new_surface/runtime.py
    GIT_AUTHOR_DATE="${TODAY}T00:00:00+09:00" \
    GIT_COMMITTER_DATE="${TODAY}T00:00:00+09:00" \
        git -C "$source_repo" commit -q -m "feature: new core dependency surface"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_ga466_fixture
    [ "$status" -eq 0 ]
    [[ "$output" == *"ALERT: context/dm-signal-core.md source commits 1件"* ]]
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

@test "--cmd-warnings resolves project from active task before archive" {
    _create_context "context/dm-signal.md" "$STALE_DATE"
    _create_context "context/infrastructure.md" "$STALE_DATE"
    _create_source_commit "src/dm_signal.py"
    mkdir -p "$TEST_TMPDIR/queue/tasks"
    cat > "$TEST_TMPDIR/queue/tasks/hanzo.yaml" <<'TASK'
task:
  task_id: cmd_922_active_normal
  parent_cmd: cmd_922_active
  project: dm-signal
TASK

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_922_active_normal
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

@test "GA-432 multiple source markers select newest ancestry boundary regardless of line order" {
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$source_repo/backend/app" "$TEST_TMPDIR/projects"
    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'project:\n  id: dm-signal\n  path: "%s"\n' "$source_repo" > "$TEST_TMPDIR/projects/dm-signal.yaml"

    printf 'v1\n' > "$source_repo/backend/app/core.py"
    git -C "$source_repo" add backend/app/core.py
    git -C "$source_repo" commit -q -m "feature: old boundary"
    local old_sha
    old_sha="$(git -C "$source_repo" rev-parse HEAD)"
    printf 'v2\n' >> "$source_repo/backend/app/core.py"
    git -C "$source_repo" add backend/app/core.py
    git -C "$source_repo" commit -q -m "feature: reviewed newer boundary"
    local new_sha
    new_sha="$(git -C "$source_repo" rev-parse HEAD)"

    _create_context "context/dm-signal-core.md" "$TODAY"
    sed -i "1a<!-- source_commit:${old_sha} reason:later write of older boundary evidence:fixture -->\n<!-- source_commit:${new_sha} reason:newer reviewed boundary evidence:fixture -->" "$TEST_TMPDIR/context/dm-signal-core.md"
    _create_shogun_to_karo "cmd_ga432" "dm-signal"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_ga432
    [ "$status" -eq 0 ]
    [[ "$output" != *"context/dm-signal-core.md source commits"* ]]
}

@test "divergent source markers use a frontier and still detect one own commit" {
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$source_repo/backend/app/jobs" "$TEST_TMPDIR/projects"
    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'project:\n  id: dm-signal\n  path: "%s"\n' "$source_repo" > "$TEST_TMPDIR/projects/dm-signal.yaml"
    printf 'base\n' > "$source_repo/backend/app/jobs/base.py"
    git -C "$source_repo" add .
    git -C "$source_repo" commit -q -m "fixture: common source base"
    local base_sha main_sha side_sha
    base_sha="$(git -C "$source_repo" rev-parse HEAD)"

    printf 'main\n' > "$source_repo/backend/app/jobs/main.py"
    git -C "$source_repo" add .
    git -C "$source_repo" commit -q -m "fixture: reviewed main boundary"
    main_sha="$(git -C "$source_repo" rev-parse HEAD)"

    git -C "$source_repo" checkout -q -b fixture-side "$base_sha"
    printf 'side\n' > "$source_repo/backend/app/jobs/side.py"
    git -C "$source_repo" add .
    git -C "$source_repo" commit -q -m "fixture: reviewed side boundary"
    side_sha="$(git -C "$source_repo" rev-parse HEAD)"

    git -C "$source_repo" checkout -q -b fixture-tip "$main_sha"
    git -C "$source_repo" merge --no-ff -q "$side_sha" -m "fixture: merge divergent boundaries"
    printf 'own\n' > "$source_repo/backend/app/core.py"
    git -C "$source_repo" add .
    git -C "$source_repo" commit -q -m "cmd_frontier_own: unreflected source change"

    sed -i '/context\/dm-signal-core\.md/a\      - file: context/dm-signal-ops.md' \
        "$TEST_TMPDIR/config/projects.yaml"
    _create_context "context/dm-signal-core.md" "$TODAY"
    _create_context "context/dm-signal-ops.md" "$TODAY"
    sed -i "1a<!-- source_commit:${main_sha} reason:main boundary evidence:fixture -->\n<!-- source_commit:${side_sha} reason:side boundary evidence:fixture -->" \
        "$TEST_TMPDIR/context/dm-signal-core.md"
    sed -i "1a<!-- source_commit:${main_sha} reason:main boundary evidence:fixture -->\n<!-- source_commit:${side_sha} reason:side boundary evidence:fixture -->" \
        "$TEST_TMPDIR/context/dm-signal-ops.md"
    cp "$PROJECT_ROOT/scripts/config/context_source_commits.tsv" \
        "$TEST_TMPDIR/scripts/config/context_source_commits.tsv"

    CFC_OUTPUT_CACHE_TTL=0 CFC_REQUIRE_SOURCE_COMMIT=1 CFC_HISTORY_REFRESH_SYNC=1 \
        CFC_PROJECT_OVERRIDE=dm-signal run bash "$TEST_SCRIPT" --cmd-commit-list divergent_cmd
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c 'cmd_frontier_own:')" -eq 1 ]
    [[ "$output" != *"MISSING_SOURCE_COMMIT"* ]]
    [[ "$output" != *"INVALID_SOURCE_COMMIT"* ]]
}

@test "invalid source marker emits a blocking machine-readable boundary failure" {
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$source_repo/backend/app" "$TEST_TMPDIR/projects"
    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'project:\n  id: dm-signal\n  path: "%s"\n' "$source_repo" > "$TEST_TMPDIR/projects/dm-signal.yaml"
    printf 'source\n' > "$source_repo/backend/app/core.py"
    git -C "$source_repo" add .
    git -C "$source_repo" commit -q -m "fixture: source"
    _create_context "context/dm-signal-core.md" "$TODAY"
    sed -i '1a<!-- source_commit:0000000000000000000000000000000000000000 reason:invalid evidence:fixture -->' \
        "$TEST_TMPDIR/context/dm-signal-core.md"
    cp "$PROJECT_ROOT/scripts/config/context_source_commits.tsv" \
        "$TEST_TMPDIR/scripts/config/context_source_commits.tsv"

    CFC_OUTPUT_CACHE_TTL=0 CFC_REQUIRE_SOURCE_COMMIT=1 CFC_HISTORY_REFRESH_SYNC=1 \
        CFC_PROJECT_OVERRIDE=dm-signal run bash "$TEST_SCRIPT" --cmd-commit-list invalid_cmd
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c '^INVALID_SOURCE_COMMIT')" -eq 1 ]
    [ "$(printf '%s\n' "$output" | grep -c '^MISSING_SOURCE_COMMIT')" -eq 1 ]
}

@test "GA-288 source commit that updates infra context in same commit is reflected" {
    mkdir -p "$TEST_TMPDIR/skills/codd"
    printf 'v1\n' > "$TEST_TMPDIR/skills/codd/SKILL.md"
    git -C "$TEST_TMPDIR" add skills/codd/SKILL.md
    git -C "$TEST_TMPDIR" commit -q -m "feature: initial codd source"
    local boundary
    boundary="$(git -C "$TEST_TMPDIR" rev-parse --short HEAD)"

    _create_context "context/codd.md" "$TODAY"
    sed -i "1s/ -->/ source_commit:${boundary} -->/" "$TEST_TMPDIR/context/codd.md"
    git -C "$TEST_TMPDIR" add context/codd.md
    git -C "$TEST_TMPDIR" commit -q -m "docs: establish codd boundary"
    boundary="$(git -C "$TEST_TMPDIR" rev-parse --short HEAD)"
    sed -i "1s/source_commit:[0-9a-f]*/source_commit:${boundary}/" "$TEST_TMPDIR/context/codd.md"
    git -C "$TEST_TMPDIR" add context/codd.md
    git -C "$TEST_TMPDIR" commit -q -m "docs: advance exact boundary"
    boundary="$(git -C "$TEST_TMPDIR" rev-parse --short HEAD)"
    sed -i "1s/source_commit:[0-9a-f]*/source_commit:${boundary}/" "$TEST_TMPDIR/context/codd.md"

    printf 'v2\n' >> "$TEST_TMPDIR/skills/codd/SKILL.md"
    printf '\nreflected source change\n' >> "$TEST_TMPDIR/context/codd.md"
    git -C "$TEST_TMPDIR" add skills/codd/SKILL.md context/codd.md
    git -C "$TEST_TMPDIR" commit -q -m "feature: reflected codd source"
    _create_archive_cmd "cmd_ga288_fixture" "infra"

    CFC_OUTPUT_CACHE_TTL=0 run bash "$TEST_SCRIPT" --dashboard-warnings
    [ "$status" -eq 0 ]
    [[ "$output" != *"context/codd.md source commits"* ]]
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

@test "GA-299 schema regeneration preserves exact source_commit boundary" {
    local schema_doc="$TEST_TMPDIR/context/memory-db-schema.md"
    mkdir -p "$(dirname "$schema_doc")"
    cat > "$schema_doc" <<'EOF'
<!-- last_updated: 2026-07-18 -->
<!-- source_commit:abe55194e2c2d9e5f2fa8c16b04a6b806b419ba0 reason:reviewed evidence:test -->
# Memory DB Schema
EOF

    run python3 - "$PROJECT_ROOT/scripts/memory_db_import.py" "$schema_doc" <<'PY'
import importlib.util
import pathlib
import sys

spec = importlib.util.spec_from_file_location("memory_db_import", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
path = pathlib.Path(sys.argv[2])
generated = "<!-- last_updated: 2026-07-19 -->\n\n# Memory DB Schema\n"
path.write_text(module.preserve_schema_source_boundary(path, generated), encoding="utf-8")
print(path.read_text(encoding="utf-8"), end="")
PY

    [ "$status" -eq 0 ]
    [[ "$output" == *"source_commit:abe55194e2c2d9e5f2fa8c16b04a6b806b419ba0"* ]]
    [ "$(grep -c 'source_commit:' "$schema_doc")" -eq 1 ]
}

@test "GA-245 registered and enforced context sets are exact" {
    run python3 - "$SRC_SCRIPT" "$PROJECT_ROOT/scripts/config/context_source_commits.tsv" <<'PY'
import ast, re, sys
text=open(sys.argv[1], encoding='utf-8').read()
registered={parts[0]: parts[1] for parts in (line.rstrip().split('\t') for line in open(sys.argv[2], encoding='utf-8') if line.strip() and not line.startswith('#'))}
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

@test "GA-452 registered source boundary carries owner and update trigger" {
    run python3 - "$PROJECT_ROOT/scripts/config/context_source_commits.tsv" <<'PY'
import sys
rows = [
    line.rstrip().split("\t")
    for line in open(sys.argv[1], encoding="utf-8")
    if line.strip() and not line.lstrip().startswith("#")
]
assert len(rows) == 10
assert all(len(row) == 4 and row[2] and row[3] for row in rows), rows
by_path = {row[0]: row[1:] for row in rows}
assert by_path["context/dm-signal-core.md"][1] == "dm-signal-core"
assert "backend/app" in by_path["context/dm-signal-core.md"][2].split("|")
assert by_path["context/codd.md"][1] == "infra-codd"
assert "skills/codd" in by_path["context/codd.md"][2].split("|")
print("owner_trigger_contract=10/10")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"owner_trigger_contract=10/10"* ]]
}

@test "GA-320 cmd commit-list cache is isolated by project override" {
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$source_repo/backend/app" "$TEST_TMPDIR/projects" "$TEST_TMPDIR/scripts/config"
    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'project:\n  id: dm-signal\n  path: "%s"\n' "$source_repo" > "$TEST_TMPDIR/projects/dm-signal.yaml"
    printf 'dm-v1\n' > "$source_repo/backend/app/core.py"
    git -C "$source_repo" add backend/app/core.py
    git -C "$source_repo" commit -q -m "initial dm source"
    local dm_boundary
    dm_boundary="$(git -C "$source_repo" rev-parse --short HEAD)"
    _create_context "context/dm-signal-core.md" "$TODAY"
    sed -i "1s/ -->/ source_commit:${dm_boundary} -->/" "$TEST_TMPDIR/context/dm-signal-core.md"
    printf 'dm-v2\n' >> "$source_repo/backend/app/core.py"
    git -C "$source_repo" add backend/app/core.py
    git -C "$source_repo" commit -q -m "feature: dm cache identity"

    printf 'infra-v1\n' > "$TEST_TMPDIR/scripts/infra_source.sh"
    git -C "$TEST_TMPDIR" add scripts/infra_source.sh
    git -C "$TEST_TMPDIR" commit -q -m "initial infra source"
    local infra_boundary
    infra_boundary="$(git -C "$TEST_TMPDIR" rev-parse --short HEAD)"
    _create_context "context/infrastructure.md" "$TODAY"
    sed -i "1s/ -->/ source_commit:${infra_boundary} -->/" "$TEST_TMPDIR/context/infrastructure.md"
    printf 'infra-v2\n' >> "$TEST_TMPDIR/scripts/infra_source.sh"
    git -C "$TEST_TMPDIR" add scripts/infra_source.sh
    git -C "$TEST_TMPDIR" commit -q -m "feature: infra cache identity"

    cp "$PROJECT_ROOT/scripts/config/context_source_commits.tsv" \
        "$TEST_TMPDIR/scripts/config/context_source_commits.tsv"

    CFC_OUTPUT_CACHE_TTL=120 CFC_PROJECT_OVERRIDE=dm-signal \
        run bash "$TEST_SCRIPT" --cmd-commit-list same_cmd
    [ "$status" -eq 0 ]
    [[ "$output" == *$'context/dm-signal-core.md\t'* ]]
    [[ "$output" != *"context/infrastructure.md"* ]]

    CFC_OUTPUT_CACHE_TTL=120 CFC_PROJECT_OVERRIDE=infra \
        run bash "$TEST_SCRIPT" --cmd-commit-list same_cmd
    [ "$status" -eq 0 ]
    [[ "$output" == *$'context/infrastructure.md\t'* ]]
    [[ "$output" != *"context/dm-signal-core.md"* ]]
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
    # test_necessity: a detected post-completion source commit must present the canonical context setter action instead of remaining informational only.
    [[ "$output" == *"action: bash scripts/context_source_commit_set.sh context/google-classroom.md"* ]]
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

@test "external split context excludes source commits already reflected in its body" {
    local source_repo="$TEST_TMPDIR/source/dm-signal"
    mkdir -p "$source_repo/backend/app" "$TEST_TMPDIR/projects"
    git -C "$source_repo" init -q
    git -C "$source_repo" config user.email "test@example.invalid"
    git -C "$source_repo" config user.name "Test User"
    printf 'runtime update\n' > "$source_repo/backend/app/runtime.py"
    git -C "$source_repo" add backend/app/runtime.py
    git -C "$source_repo" commit -q -m "cmd_995_reflected: runtime update"

    printf 'project:\n  id: dm-signal\n  path: "%s"\n' "$source_repo" > "$TEST_TMPDIR/projects/dm-signal.yaml"
    _create_context "context/dm-signal-core.md" "$STALE_DATE"
    printf '\n- cmd_995_reflected: runtime behavior already indexed\n' >> "$TEST_TMPDIR/context/dm-signal-core.md"
    _create_shogun_to_karo "cmd_995" "dm-signal"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_995
    [ "$status" -eq 0 ]
    [[ "$output" != *"context/dm-signal-core.md source commits"* ]]
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

# test_necessity: infra-platform must reject a broad root-fallback boundary so
# operational/project commits cannot become infrastructure freshness alerts.
@test "GA-483 infra registry rejects root-fallback and keeps source paths explicit" {
    local registry="$TEST_TMPDIR/scripts/config/context_source_commits.tsv"
    cp "$PROJECT_ROOT/scripts/config/context_source_commits.tsv" "$registry"

    run python3 - "$registry" <<'PY'
import sys
path = sys.argv[1]
rows = open(path, encoding="utf-8").read()
assert "context/infrastructure.md\tinfra\tinfra-platform\troot-fallback" not in rows
assert "context/infrastructure.md\tinfra\tinfra-platform\t.github" in rows
print("infra_platform_explicit=1")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"infra_platform_explicit=1"* ]]

    sed -i 's#context/infrastructure.md\tinfra\tinfra-platform\t.*#context/infrastructure.md\tinfra\tinfra-platform\troot-fallback#' "$registry"
    _create_context "context/infrastructure.md" "$TODAY"
    _create_shogun_to_karo "cmd_ga483" "infra"

    CFC_REQUIRE_SOURCE_COMMIT=1 run bash "$TEST_SCRIPT" --cmd-warnings cmd_ga483
    [ "$status" -ne 0 ]
    [[ "$output" == *"BLOCK: infra context registry requires explicit source pathspecs"* ]]
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
    local second_sha
    second_sha="$(git -C "$TEST_TMPDIR" rev-parse --short HEAD)"
    [[ "$output" == *"latest: ${second_sha} fix: second infra source change"* ]]
}

@test "GA-295 reflected, lesson-only, stale, and missing-source fixtures stay exact" {
    _create_context "context/infrastructure.md" "$TODAY"
    _create_source_commit "scripts/reflected.sh" "cmd_995_reflected: implementation"
    local boundary
    boundary="$(git -C "$TEST_TMPDIR" rev-parse --short HEAD)"
    sed -i "1s/ -->/ source_commit:${boundary} -->/" "$TEST_TMPDIR/context/infrastructure.md"

    _create_source_commit "tasks/lessons.md" "cmd_995_lesson: lesson only"
    _create_source_commit "scripts/already_indexed.sh" "cmd_995_indexed: implementation"
    printf '\n- reflected proof: cmd_995_indexed\n' >> "$TEST_TMPDIR/context/infrastructure.md"
    _create_source_commit "scripts/stale.sh" "cmd_995_stale: implementation"
    _create_shogun_to_karo "cmd_995" "infra"

    run bash "$TEST_SCRIPT" --cmd-warnings cmd_995
    [ "$status" -eq 0 ]
    [[ "$output" == *"source commits 1件"* ]]
    [[ "$output" == *"cmd_995_stale: implementation"* ]]
    [[ "$output" != *"cmd_995_lesson"* ]]
    [[ "$output" != *"cmd_995_indexed"* ]]

    sed -i '1s/ source_commit:[0-9a-f]*//' "$TEST_TMPDIR/context/infrastructure.md"
    CFC_REQUIRE_SOURCE_COMMIT=1 run bash "$TEST_SCRIPT" --cmd-warnings cmd_995
    [ "$status" -eq 0 ]
    [[ "$output" == *"MISSING_SOURCE_COMMIT"* ]]
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

@test "GA-291 producer uses its bounded timeout once without consumer git retry" {
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
    [ "$(cat "$counter_file")" -eq 1 ]
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
    [ "$(cat "$counter_file")" -eq 1 ]
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
    [ "$(cat "$counter_file")" -eq 1 ]
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

    # Build the immutable history generation first.  This test owns output
    # cache publication concurrency; cold producer locking is covered by the
    # GA-286/GA-291 history-cache tests above.
    CFC_OUTPUT_CACHE_TTL=0 bash "$TEST_SCRIPT" --dashboard-warnings >/dev/null

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
