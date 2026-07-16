#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEST_ROOT="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$TEST_ROOT/scripts/lib" "$TEST_ROOT/queue"
    cp "$ROOT/scripts/ntfy_inbox_archive.sh" "$TEST_ROOT/scripts/"
    cp "$ROOT/scripts/lib/yaml_atomic.py" "$TEST_ROOT/scripts/lib/"
}

@test "explicit empty inbox exits without creating an archive" {
    printf 'inbox: []\n' > "$TEST_ROOT/queue/ntfy_inbox.yaml"
    run bash "$TEST_ROOT/scripts/ntfy_inbox_archive.sh"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_ROOT/queue/ntfy_inbox_archive.yaml" ]
}

@test "nonempty inbox still reaches the archive implementation" {
    cat > "$TEST_ROOT/queue/ntfy_inbox.yaml" <<'YAML'
inbox:
  - id: keep
    timestamp: invalid
    status: pending
YAML
    run bash "$TEST_ROOT/scripts/ntfy_inbox_archive.sh"
    [ "$status" -eq 0 ]
    grep -Fq 'id: keep' "$TEST_ROOT/queue/ntfy_inbox.yaml"
}
