#!/usr/bin/env bats

setup() {
    export REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export GH_CMD="$BATS_TEST_TMPDIR/fake_gh_gist_index_update.sh"
    cat > "$GH_CMD" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "gist" || "${2:-}" != "list" ]]; then
    printf 'unexpected arguments: %s\n' "$*" >&2
    exit 2
fi

for i in $(seq 1 100); do
    printf 'gist-%03d\tResearch Report %03d\tfile.md\tpublic\t2026-07-16T12:00:00Z\n' "$i" "$i"
done
FAKE_GH
    chmod 0644 "$GH_CMD"
}

@test "title normalization preserves ASCII lowercase behavior" {
    run bash -c 'source "$1"; title_key "Research REPORT 123"' _ \
        "$REPO_ROOT/scripts/gist_index_update.sh"

    [ "$status" -eq 0 ]
    [ "$output" = "research report 123" ]
}

@test "dry-run renders all 100 fixture gists without editing" {
    run bash "$REPO_ROOT/scripts/gist_index_update.sh" --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"100件中100件を掲載"* ]]
    [[ "$output" == *"[Research Report 100]"* ]]
}
