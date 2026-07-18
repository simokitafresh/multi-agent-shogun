#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export FIXTURE="$BATS_TEST_TMPDIR/fixture"
    mkdir -p "$FIXTURE/bin"
    printf 'expected content\n' > "$FIXTURE/local.md"
    export GH_CMD="$FIXTURE/bin/gh"
    cat > "$GH_CMD" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
mode="${FAKE_GH_MODE:-success}"
if [ "${1:-}" != api ]; then exit 90; fi
shift
if [ "${1:-}" = --method ]; then
    [ "$mode" != network_fail ] || exit 41
    exit 0
fi
if [ "${1:-}" = gists/abc123 ]; then
    if [ "$mode" = filename_mismatch ]; then
        printf '{"files":{"other.md":{"raw_url":"https://raw.test/other"}}}\n'
    else
        printf '{"files":{"index.md":{"raw_url":"https://raw.test/index"}}}\n'
    fi
    exit 0
fi
if [ "${1:-}" = https://raw.test/index ]; then
    if [ "$mode" = silent_noop ]; then
        printf 'old content\n'
    else
        printf 'expected content\n'
    fi
    exit 0
fi
exit 91
SH
    chmod +x "$GH_CMD"
}

@test "successful write verifies remote raw SHA256" {
    run bash "$REPO_ROOT/scripts/gist_verified_write.sh" abc123 index.md "$FIXTURE/local.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"VERIFIED gist=abc123 filename=index.md sha256="* ]]
}

@test "silent successful PATCH with unchanged remote content is blocked" {
    run env FAKE_GH_MODE=silent_noop bash "$REPO_ROOT/scripts/gist_verified_write.sh" abc123 index.md "$FIXTURE/local.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"readback SHA256 mismatch"* ]]
}

@test "network failure is blocked" {
    run env FAKE_GH_MODE=network_fail bash "$REPO_ROOT/scripts/gist_verified_write.sh" abc123 index.md "$FIXTURE/local.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"PATCH request failed"* ]]
}

@test "remote filename mismatch is blocked" {
    run env FAKE_GH_MODE=filename_mismatch bash "$REPO_ROOT/scripts/gist_verified_write.sh" abc123 index.md "$FIXTURE/local.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"remote filename missing"* ]]
}

@test "a repeated write of identical content remains verified" {
    run bash "$REPO_ROOT/scripts/gist_verified_write.sh" abc123 index.md "$FIXTURE/local.md"
    [ "$status" -eq 0 ]
    run bash "$REPO_ROOT/scripts/gist_verified_write.sh" abc123 index.md "$FIXTURE/local.md"
    [ "$status" -eq 0 ]
}

@test "remote filename must not be a path" {
    run bash "$REPO_ROOT/scripts/gist_verified_write.sh" abc123 dir/index.md "$FIXTURE/local.md"
    [ "$status" -ne 0 ]
    [[ "$output" == *"must be a filename"* ]]
}
