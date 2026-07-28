#!/usr/bin/env bats
# test_necessity: pre-commit instruction_sync ledger rows must carry the actual
# rebuilt/skipped counts reported by build_instructions.sh (not a fixed value),
# and a re-delivered event_id must not duplicate the ledger row (idempotent write).
# cmd_karo_hotfix_hot_script_instruction_sync_20260728 AC3: future re-measurement
# reads skip/rebuild counts straight from this ledger instead of reconstructing
# them from git log.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  REPO="$(mktemp -d)"
}

teardown() { rm -rf "$REPO"; }

writer_funcs() {
  python3 - "$ROOT/scripts/hooks/git-pre-commit.sh" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
start = text.index("precommit_instruction_sync_write_async() {")
end = text.index("\n}\n\nprecommit_terminal_receipt()", start) + 2
print(text[start:end])
PY
}

@test "instruction_sync ledger row carries the rebuilt and skipped counts" {
  ledger="$REPO/defense_overhead.jsonl"
  FUNCS="$(writer_funcs)"
  run env DEFENSE_OVERHEAD_LEDGER="$ledger" bash -c "
    $FUNCS
    _PRECOMMIT_INSTRUCTION_SYNC_REBUILT=4
    _PRECOMMIT_INSTRUCTION_SYNC_SKIPPED=15
    precommit_instruction_sync_write_async 657 PASS fixture-instruction-sync
    wait
  "
  [ "$status" -eq 0 ]
  run python3 - "$ledger" <<'PY'
import json
import sys
row = json.loads(open(sys.argv[1], encoding="utf-8").read())
assert row["source"] == "git_pre_commit"
assert row["check_id"] == "instruction_sync"
assert row["wall_ms"] == 657
assert row["verdict"] == "PASS"
assert row["rebuilt"] == 4
assert row["skipped"] == 15
PY
  [ "$status" -eq 0 ]
}

@test "instruction_sync ledger write is idempotent on a repeated event_id" {
  ledger="$REPO/defense_overhead.jsonl"
  FUNCS="$(writer_funcs)"
  run env DEFENSE_OVERHEAD_LEDGER="$ledger" bash -c "
    $FUNCS
    _PRECOMMIT_INSTRUCTION_SYNC_REBUILT=4
    _PRECOMMIT_INSTRUCTION_SYNC_SKIPPED=15
    precommit_instruction_sync_write_async 657 PASS fixture-dup
    wait
    _PRECOMMIT_INSTRUCTION_SYNC_REBUILT=20
    _PRECOMMIT_INSTRUCTION_SYNC_SKIPPED=0
    precommit_instruction_sync_write_async 900 PASS fixture-dup
    wait
  "
  [ "$status" -eq 0 ]
  lines="$(wc -l < "$ledger")"
  [ "$lines" -eq 1 ]
}

@test "main() extracts rebuilt/skipped from BUILD_INSTRUCTIONS_SUMMARY output" {
  run python3 - "$ROOT/scripts/hooks/git-pre-commit.sh" <<'PY'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text()
assert 'BUILD_INSTRUCTIONS_SUMMARY\\ rebuilt=([0-9]+)\\ skipped=([0-9]+)' in s
assert '_PRECOMMIT_INSTRUCTION_SYNC_REBUILT="${BASH_REMATCH[1]}"' in s
assert '_PRECOMMIT_INSTRUCTION_SYNC_SKIPPED="${BASH_REMATCH[2]}"' in s
PY
  [ "$status" -eq 0 ]
}
