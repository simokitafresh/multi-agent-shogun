#!/usr/bin/env bats

setup() {
    export ROOT REPO HOOK
    ROOT="$(mktemp -d "$BATS_TMPDIR/commit-reminder.XXXXXX")"
    REPO="$ROOT/repo"
    HOOK="$ROOT/.claude/hooks/post-bash-commit-reminder.sh"
    mkdir -p "$ROOT/.claude/hooks" "$ROOT/queue/tasks" "$ROOT/queue/reports" "$ROOT/config" "$REPO"
    cp "$BATS_TEST_DIRNAME/../../.claude/hooks/post-bash-commit-reminder.sh" "$HOOK"
    chmod +x "$HOOK"
    git -C "$REPO" init -q
    git -C "$REPO" config user.email test@example.com
    git -C "$REPO" config user.name tester
    printf 'a\n' > "$REPO/a.txt"
    printf 'b\n' > "$REPO/b.txt"
    for i in $(seq 1 13); do printf 'other\n' > "$REPO/other${i}.txt"; done
    git -C "$REPO" add .
    git -C "$REPO" commit -qm init
    export HEAD_SHA
    HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"
    cat > "$ROOT/config/projects.yaml" <<EOF
projects:
  - id: demo
    path: "$REPO"
EOF
    write_task_report "$HEAD_SHA"
}

teardown() {
    rm -rf "$ROOT"
}

write_task_report() {
    local commit_hash="$1"
    cat > "$ROOT/queue/tasks/hanzo.yaml" <<'EOF'
task:
  project: demo
  owned_paths:
    - a.txt
    - b.txt
  report_path: queue/reports/hanzo.yaml
EOF
    cat > "$ROOT/queue/reports/hanzo.yaml" <<EOF
commit_hash: "$commit_hash"
EOF
}

run_hook() {
    local payload
    payload='{"tool_name":"Bash","tool_input":{"command":"bash scripts/inbox_write.sh karo done report_received hanzo"}}'
    run env HOOK_PAYLOAD="$payload" bash "$HOOK"
}

@test "other agents 13 dirty files do not warn when both owned paths are clean" {
    for i in $(seq 1 13); do printf 'dirty\n' >> "$REPO/other${i}.txt"; done
    run_hook
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "dirty owned path is detected with no false negative" {
    printf 'dirty\n' >> "$REPO/a.txt"
    run_hook
    [ "$status" -eq 0 ]
    [[ "$output" == *'owned_paths_uncommitted'* ]]
    [[ "$output" == *'a.txt'* ]]
}

@test "missing report commit hash is detected" {
    write_task_report ""
    run_hook
    [ "$status" -eq 0 ]
    [[ "$output" == *'report_commit_hash_missing_or_invalid'* ]]
}

@test "HEAD and report commit blob mismatch is detected" {
    printf 'new\n' > "$REPO/a.txt"
    git -C "$REPO" add a.txt
    git -C "$REPO" commit -qm newer
    run_hook
    [ "$status" -eq 0 ]
    [[ "$output" == *'head_report_blob_mismatch'* ]]
    [[ "$output" == *'a.txt'* ]]
}

@test "missing task scope falls back to global dirty with explicit reason" {
    cat > "$ROOT/queue/tasks/hanzo.yaml" <<'EOF'
task:
  project: demo
EOF
    printf 'dirty\n' >> "$REPO/other1.txt"
    run_hook
    [ "$status" -eq 0 ]
    [[ "$output" == *'scope_fallback:task_owned_paths_missing_or_invalid'* ]]
    [[ "$output" == *'other1.txt'* ]]
}
