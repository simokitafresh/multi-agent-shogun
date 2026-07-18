#!/usr/bin/env bats
# test_necessity: New begin_target ID without boundary synchronization is blocked; violation is BLOCK.

setup() {
    GATE="scripts/gates/gate_yaml_field_set_block_sync.sh"
    SOURCE="scripts/lib/yaml_field_set.sh"
    FIXTURE="$BATS_TEST_TMPDIR/yaml_field_set.sh"
    cp "$SOURCE" "$FIXTURE"
}

@test "canonical implementations and one-line flush pass" {
    run bash "$GATE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS(LG047)"* ]]
}

@test "new begin_target ID without boundary synchronization is blocked" {
    python3 - "$FIXTURE" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
needle = 'if (t ~ /^[[:space:]]*-[[:space:]]*cmd_id:[[:space:]]*/) {'
s = s.replace(needle, 'if (t ~ /^[[:space:]]*-[[:space:]]*(cmd_id|review_id):[[:space:]]*/) {', 1)
open(p, "w", encoding="utf-8").write(s)
PY
    run env YFS_SYNC_TARGET="$FIXTURE" bash "$GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK(LG047)"* ]]
}

@test "boundary ID removed from one implementation is blocked" {
    python3 - "$FIXTURE" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
needle = '(id|cmd_id):[[:space:]]*/'
s = s.replace(needle, '(id|other_id):[[:space:]]*/', 1)
open(p, "w", encoding="utf-8").write(s)
PY
    run env YFS_SYNC_TARGET="$FIXTURE" bash "$GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BLOCK(LG047)"* ]]
}

@test "missing flush implementation is blocked" {
    python3 - "$FIXTURE" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read().replace('function flush_block(', 'function flush_removed(', 1)
open(p, "w", encoding="utf-8").write(s)
PY
    run env YFS_SYNC_TARGET="$FIXTURE" bash "$GATE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"implementation count drift"* ]]
}
