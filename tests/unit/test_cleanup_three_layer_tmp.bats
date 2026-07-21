#!/usr/bin/env bats
# test_necessity: canonical cacheを残し一時root孤児だけを容量上限まで回収する不変量

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FIXTURE="$(mktemp -d)"
    CACHE="$FIXTURE/cache"
    REPO="$FIXTURE/repo"
    mkdir -p "$CACHE" "$REPO/scripts"
    cp "$ROOT/scripts/cleanup_three_layer_tmp.sh" "$REPO/scripts/"
    SCRIPT="$REPO/scripts/cleanup_three_layer_tmp.sh"
    KEY="${REPO//[^A-Za-z0-9_.-]/_}"
}

teardown() {
    rm -r -- "$FIXTURE"
}

make_old() {
    truncate -s "$2" "$CACHE/$1"
    touch -d '8 hours ago' "$CACHE/$1"
}

@test "contract: dry-run classifies only expired orphan deploy caches" {
    make_old "${KEY}_.deploy-report-fast.111.1_multi_agent_shogun_memory.db" 30
    make_old "${KEY}_.deploy-report-fast.111.1_multi_agent_shogun_memory.db.lock" 1
    make_old "${KEY}_multi_agent_shogun_memory.db" 40
    make_old "${KEY}_multi_agent_shogun_memory.db.preflight" 40
    make_old "${KEY}_.unknown.222_multi_agent_shogun_memory.db" 40
    truncate -s 30 "$CACHE/${KEY}_.deploy-report-fast.222.2_multi_agent_shogun_memory.db"
    mkdir -p "$REPO/.deploy-report-fast.333.3"
    make_old "${KEY}_.deploy-report-fast.333.3_multi_agent_shogun_memory.db" 30

    run "$SCRIPT" --dry-run --ttl-hours 6 --max-bytes 50 --cache-dir "$CACHE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"candidates=2 bytes=31 protected=2"* ]]
    [ "$(find "$CACHE" -type f | wc -l)" -eq 7 ]
}

@test "contract: apply reclaims oldest orphan until capacity and reports FP/FN zero" {
    make_old "${KEY}_.deploy-report-fast.111.1_multi_agent_shogun_memory.db" 30
    sleep 1
    make_old "${KEY}_.deploy-report-fast.222.2_multi_agent_shogun_memory.db" 30
    make_old "${KEY}_multi_agent_shogun_memory.db" 40

    run "$SCRIPT" --apply --ttl-hours 6 --max-bytes 70 --cache-dir "$CACHE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"deleted=1 remaining_bytes=70"* ]]
    [ -f "$CACHE/${KEY}_multi_agent_shogun_memory.db" ]
    remaining_orphans="$(find "$CACHE" -type f -name "${KEY}_.deploy-report-fast.*" | wc -l)"
    [ "$remaining_orphans" -eq 1 ]
    echo "false_positive=0 false_negative=0"
}

@test "contract: apply blocks more than ten files without explicit approval" {
    for n in $(seq 1 11); do
        make_old "${KEY}_.deploy-report-fast.${n}.1_multi_agent_shogun_memory.db" 1
    done
    run "$SCRIPT" --apply --ttl-hours 6 --max-bytes 0 --cache-dir "$CACHE"
    [ "$status" -eq 3 ]
    [[ "$output" == *"BLOCK: apply would delete 11 files"* ]]
    [ "$(find "$CACHE" -type f | wc -l)" -eq 11 ]
}

@test "contract: unsafe path is rejected" {
    run "$SCRIPT" --dry-run --cache-dir /
    [ "$status" -eq 2 ]
    [[ "$output" == *"unsafe cleanup cache_dir"* ]]
}
