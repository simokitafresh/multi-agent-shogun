#!/usr/bin/env bats

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SRC_SCRIPT="$PROJECT_ROOT/scripts/ci_status_check.sh"
    [ -f "$SRC_SCRIPT" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
}

setup() {
    TEST_TMPDIR="$(mktemp -d "$BATS_TMPDIR/ci_status.XXXXXX")"
    mkdir -p "$TEST_TMPDIR/scripts" "$TEST_TMPDIR/bin"
    cp "$SRC_SCRIPT" "$TEST_TMPDIR/scripts/ci_status_check.sh"
    chmod +x "$TEST_TMPDIR/scripts/ci_status_check.sh"
    export TEST_SCRIPT="$TEST_TMPDIR/scripts/ci_status_check.sh"
    export GH_ARGS_LOG="$TEST_TMPDIR/gh_args.log"
}

teardown() {
    [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ] && rm -rf "$TEST_TMPDIR"
}

_write_fake_gh() {
    local list_json="$1"
    local view_json="${2:-{\"jobs\":[]}}"
    cat > "$TEST_TMPDIR/bin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GH_ARGS_LOG"
if [[ "\$1 \$2 \$3" == "run list --repo" ]]; then
    cat <<'JSON'
$list_json
JSON
    exit 0
fi
if [[ "\$1 \$2" == "run view" ]]; then
    cat <<'JSON'
$view_json
JSON
    exit 0
fi
exit 1
EOF
    chmod +x "$TEST_TMPDIR/bin/gh"
}

@test "ci_status_check --status falls back to second completed run when latest is in_progress" {
    _write_fake_gh '[{"status":"in_progress","conclusion":"","databaseId":222},{"status":"completed","conclusion":"success","databaseId":111}]'

    run env PATH="$TEST_TMPDIR/bin:$PATH" bash "$TEST_SCRIPT" --status

    [ "$status" -eq 0 ]
    [ "$output" = "GREEN" ]
    grep -F -- "--limit 2" "$GH_ARGS_LOG"
}

@test "ci_status_check --status keeps first run behavior when latest is completed" {
    _write_fake_gh '[{"status":"completed","conclusion":"success","databaseId":333},{"status":"completed","conclusion":"failure","databaseId":222}]'

    run env PATH="$TEST_TMPDIR/bin:$PATH" bash "$TEST_SCRIPT" --status

    [ "$status" -eq 0 ]
    [ "$output" = "GREEN" ] || {
        printf 'output=%s\n' "$output" >&2
        return 1
    }
    grep -F -- "--limit 2" "$GH_ARGS_LOG"
}
