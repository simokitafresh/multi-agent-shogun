#!/usr/bin/env bats
# test_necessity: ledger operations preserve root ownership, allowlist, and CAS invariants.

setup() {
  STATE_TMP_ROOT="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
  TEST_ROOT_PARENT="$(mktemp -d "$STATE_TMP_ROOT/ledger-test-parent.XXXXXX")"
  TEST_ROOT="$(mktemp -d "$TEST_ROOT_PARENT/repo.XXXXXX")"
  STATE_DIR="$(mktemp -d "$STATE_TMP_ROOT/ledger-test.XXXXXX")"
  mkdir -p "$TEST_ROOT/queue" "$TEST_ROOT/logs"
  cp "$BATS_TEST_DIRNAME/../../scripts/ledger_writer.sh" "$TEST_ROOT/ledger_writer.sh"
  chmod +x "$TEST_ROOT/ledger_writer.sh"
  printf '#!/usr/bin/env bash\nexec bash "%s/ledger_writer.sh" "$@"\n' "$TEST_ROOT" > "$TEST_ROOT/writer"
  chmod +x "$TEST_ROOT/writer"
  export PATH="$TEST_ROOT:$PATH"
  export SHOGUN_STATE_DIR="$STATE_DIR" LEDGER_WRITER_NOTIFY=0
}
teardown() { rm -r -- "$TEST_ROOT_PARENT" "$STATE_DIR"; }
make_entry() { printf '%s\n' "- id: $1" "  status: pending" "  insight: $2" > "$TEST_ROOT/entry.yaml"; }
writer() { bash "$TEST_ROOT/ledger_writer.sh" "$@"; }

@test "append emits an operation outside the repository and leaves root unchanged" {
  printf 'insights:\n' > "$TEST_ROOT/insights.yaml"; make_entry INS-001 first
  before="$(sha256sum "$TEST_ROOT/insights.yaml" | awk '{print $1}')"
  run env LEDGER_SOURCE_FILE="$TEST_ROOT/insights.yaml" writer append insights "$TEST_ROOT/entry.yaml"
  [ "$status" -eq 0 ]; [ -f "$output" ]; [[ "$output" == *"/ledger_inbox/insights/"* ]]
  after="$(sha256sum "$TEST_ROOT/insights.yaml" | awk '{print $1}')"; [ "$before" = "$after" ]
}
@test "append/apply materializes an insights entry" {
  printf 'insights:\n' > "$TEST_ROOT/insights.yaml"; make_entry INS-002 second
  op="$(env LEDGER_SOURCE_FILE="$TEST_ROOT/insights.yaml" writer append insights "$TEST_ROOT/entry.yaml")"
  run env LEDGER_SOURCE_FILE="$TEST_ROOT/insights.yaml" writer apply "$op"
  [ "$status" -eq 0 ]; grep -q 'INS-002' "$TEST_ROOT/insights.yaml"
}
@test "append supports bulletin ledger" {
  printf 'entries:\n' > "$TEST_ROOT/bulletin.yaml"; make_entry blt-001 bulletin
  op="$(env LEDGER_SOURCE_FILE="$TEST_ROOT/bulletin.yaml" writer append bulletin "$TEST_ROOT/entry.yaml")"
  run env LEDGER_SOURCE_FILE="$TEST_ROOT/bulletin.yaml" writer apply "$op"
  [ "$status" -eq 0 ]; grep -q 'blt-001' "$TEST_ROOT/bulletin.yaml"
}
@test "semantic_index append/apply replaces index atomically" {
  printf '%s\n' '## semantic_dictionary_design' '| id | semantic_dictionary_design |' > "$TEST_ROOT/index.md"
  printf '%s\n' '## semantic_dictionary_design' '| id | semantic_dictionary_design |' 'alias: appended' > "$TEST_ROOT/index.next.md"
  op="$(env LEDGER_SOURCE_FILE="$TEST_ROOT/index.md" LEDGER_OPERATION_ID=semantic-index-test writer append semantic_index "$TEST_ROOT/index.next.md")"
  run env LEDGER_SOURCE_FILE="$TEST_ROOT/index.md" writer apply "$op"
  [ "$status" -eq 0 ]; grep -q 'alias: appended' "$TEST_ROOT/index.md"
}
@test "bulletin update preserves confirmed_by as a YAML list" {
  printf '%s\n' 'entries:' '- id: blt-list' '  status: open' '  confirmed_by: []' > "$TEST_ROOT/bulletin.yaml"
  op="$(env LEDGER_SOURCE_FILE="$TEST_ROOT/bulletin.yaml" writer update bulletin blt-list 'confirmed_by=["karo"]' status=closed --expect status=open)"
  run env LEDGER_SOURCE_FILE="$TEST_ROOT/bulletin.yaml" writer apply "$op"
  [ "$status" -eq 0 ]
  run python3 - "$TEST_ROOT/bulletin.yaml" <<'PY'
import sys, yaml
entry = yaml.safe_load(open(sys.argv[1], encoding='utf-8'))['entries'][0]
assert entry['confirmed_by'] == ['karo'], entry
assert entry['status'] == 'closed', entry
PY
  [ "$status" -eq 0 ]
}
@test "append supports workarounds flat ledger" {
  : > "$TEST_ROOT/workarounds.yaml"; make_entry cmd-001 workaround
  op="$(env LEDGER_SOURCE_FILE="$TEST_ROOT/workarounds.yaml" writer append workarounds "$TEST_ROOT/entry.yaml")"
  run env LEDGER_SOURCE_FILE="$TEST_ROOT/workarounds.yaml" writer apply "$op"
  [ "$status" -eq 0 ]; grep -q 'cmd-001' "$TEST_ROOT/workarounds.yaml"
}
@test "append supports markdown lessons ledger" {
  printf '# Lessons\n' > "$TEST_ROOT/lessons.md"
  printf '### L001: lesson\n- **status**: confirmed\n- detail\n' > "$TEST_ROOT/entry.md"
  op="$(env LEDGER_SOURCE_FILE="$TEST_ROOT/lessons.md" writer append lessons "$TEST_ROOT/entry.md")"
  run env LEDGER_SOURCE_FILE="$TEST_ROOT/lessons.md" writer apply "$op"
  [ "$status" -eq 0 ]; grep -q '### L001: lesson' "$TEST_ROOT/lessons.md"
}
@test "append records the exact entry hash" {
  printf 'insights:\n' > "$TEST_ROOT/insights.yaml"; make_entry INS-003 hash
  op="$(env LEDGER_SOURCE_FILE="$TEST_ROOT/insights.yaml" writer append insights "$TEST_ROOT/entry.yaml")"
  expected="$(sha256sum "$TEST_ROOT/entry.yaml" | awk '{print $1}')"
  run python3 - "$op" "$expected" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))["entry_hash"] == sys.argv[2]
PY
  [ "$status" -eq 0 ]
}
@test "update rejects fields outside the ledger allowlist with rc 12" {
  printf '%s\n' '- id: INS-004' '  status: pending' > "$TEST_ROOT/insights.yaml"
  run env LEDGER_SOURCE_FILE="$TEST_ROOT/insights.yaml" writer update insights INS-004 id=bad --expect status=pending
  [ "$status" -eq 12 ]
}
@test "update operation records expected value and current entry hash" {
  printf '%s\n' '- id: INS-005' '  status: pending' > "$TEST_ROOT/insights.yaml"
  run env LEDGER_SOURCE_FILE="$TEST_ROOT/insights.yaml" writer update insights INS-005 status=resolved --expect status=pending
  [ "$status" -eq 0 ]; grep -q '"status": "pending"' "$output"
  grep -q '"entry_hash":' "$output"
}
@test "CAS mismatch moves operation to rejected without changing root" {
  printf '%s\n' '- id: INS-006' '  status: pending' > "$TEST_ROOT/insights.yaml"
  op="$(env LEDGER_SOURCE_FILE="$TEST_ROOT/insights.yaml" writer update insights INS-006 status=resolved --expect status=pending)"
  sed -i 's/status: pending/status: resolved/' "$TEST_ROOT/insights.yaml"
  run env LEDGER_SOURCE_FILE="$TEST_ROOT/insights.yaml" writer apply "$op"
  [ "$status" -eq 11 ]; [[ "$output" == REJECTED* ]]; [ "$(find "$STATE_DIR/ledger_inbox/insights/rejected" -type f | wc -l)" -eq 1 ]
  grep -q 'status: resolved' "$TEST_ROOT/insights.yaml"
}
@test "CAS success applies newest value and preserves id" {
  printf '%s\n' '- id: INS-007' '  status: pending' '  created_at: 2026-01-01' > "$TEST_ROOT/insights.yaml"
  op="$(env LEDGER_SOURCE_FILE="$TEST_ROOT/insights.yaml" writer update insights INS-007 status=resolved --expect status=pending)"
  env LEDGER_SOURCE_FILE="$TEST_ROOT/insights.yaml" writer apply "$op"
  grep -q 'id: INS-007' "$TEST_ROOT/insights.yaml"; grep -q 'created_at: 2026-01-01' "$TEST_ROOT/insights.yaml"; grep -q 'status: "resolved"' "$TEST_ROOT/insights.yaml"
}
@test "resolve emits status and evidence fields as one operation" {
  printf '%s\n' '- id: INS-008' '  status: pending' > "$TEST_ROOT/insights.yaml"
  run env LEDGER_SOURCE_FILE="$TEST_ROOT/insights.yaml" writer resolve insights INS-008 --expect status=pending --resolved-reason done --action-artifact commit
  [ "$status" -eq 0 ]; grep -q '"resolved_reason": "done"' "$output"; grep -q '"status": "resolved"' "$output"
}
@test "concurrent append operation names have unique sequence values" {
  printf 'insights:\n' > "$TEST_ROOT/insights.yaml"
  for n in 1 2 3 4 5 6; do printf '%s\n' "- id: INS-1$n" '  status: pending' > "$TEST_ROOT/e$n.yaml"; env LEDGER_SOURCE_FILE="$TEST_ROOT/insights.yaml" writer append insights "$TEST_ROOT/e$n.yaml" > "$TEST_ROOT/o$n" & done
  wait
  [ "$(find "$STATE_DIR/ledger_inbox/insights" -maxdepth 1 -name '*.yaml' | wc -l)" -eq 6 ]
  [ "$(find "$STATE_DIR/ledger_inbox/insights" -maxdepth 1 -name '*.yaml' -printf '%f\n' | sort -u | wc -l)" -eq 6 ]
}
