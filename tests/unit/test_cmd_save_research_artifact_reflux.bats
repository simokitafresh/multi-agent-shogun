#!/usr/bin/env bats
# test_cmd_save_research_artifact_reflux.bats — LK-A10 research artifact/context reflux gate

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEST_TMPDIR="$(mktemp -d "${BATS_TMPDIR:-/tmp}/cmd_save_lka10.XXXXXX")"

    cat > "$TEST_TMPDIR/run_check.sh" <<'WRAPPER'
#!/usr/bin/env bash
set -uo pipefail
CMD_BLOCK_NC="$1"
CMD_BLOCK="$CMD_BLOCK_NC"
BLOCK_REASONS=()
BLOCK_COUNT=0
CMD_SAVE_ACCUMULATE_BLOCKS=1

cmd_block_get_field() {
    local field="$1"
    python3 - "$field" <<'PY' <<<"$CMD_BLOCK_NC"
import re, sys
field = sys.argv[1]
text = sys.stdin.read()
pattern = re.compile(r"(?m)^[ \t]*" + re.escape(field) + r":[ \t]*(.*)$")
match = pattern.search(text)
if match:
    print(match.group(1).strip().strip('"').strip("'"), end="")
PY
}

record_block_reason() {
    BLOCK_REASONS+=("$1")
    BLOCK_COUNT=$((BLOCK_COUNT + 1))
    echo "BLOCK: $1" >&2
}
abort_if_block_immediate() { return 0; }
WRAPPER
    sed -n '/^check_research_artifact_reflux_ac()/,/^}/p' \
        "$PROJECT_ROOT/scripts/cmd_save.sh" >> "$TEST_TMPDIR/run_check.sh"
    cat >> "$TEST_TMPDIR/run_check.sh" <<'CALL'

check_research_artifact_reflux_ac
printf 'BLOCK_COUNT=%s\n' "$BLOCK_COUNT"
CALL
    chmod +x "$TEST_TMPDIR/run_check.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

@test "LK-A10: research cmd without artifact prefix, physical verification, and context reflux is BLOCKed" {
    local cmd='  type: research
  project: dm-signal
  title: 研究 — GS結果分析
  purpose: 分析結果をまとめる
  acceptance_criteria:
  - 分析が完了したか'

    run bash "$TEST_TMPDIR/run_check.sh" "$cmd" 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCK_COUNT=1"* ]]
    [[ "$output" == *"LK-A10"* ]]
    [[ "$output" == *"成果物ファイル名プレフィックス"* ]]
    [[ "$output" == *"成果物現物確認"* ]]
    [[ "$output" == *"context還流"* ]]
}

@test "LK-A10: research cmd with cmd artifact prefix, ls/head verification, and context reflux passes" {
    local cmd='  type: research
  project: dm-signal
  title: 研究 — GS結果分析
  purpose: 分析結果をまとめる
  acceptance_criteria:
  - docs/research/cmd_9999_gs_analysis_*.md を生成し、ls -l + head -40で成果物現物確認し、context/dm-signal-research.mdへ結論+参照を還流したか'

    run bash "$TEST_TMPDIR/run_check.sh" "$cmd" 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCK_COUNT=0"* ]]
}

@test "LK-A10: non-research cmd is outside this gate" {
    local cmd='  type: impl
  project: infra
  title: 修正 — inbox helper
  purpose: helperを直す
  acceptance_criteria:
  - tests/unit/test_inbox_write.bats がPASSする'

    run bash "$TEST_TMPDIR/run_check.sh" "$cmd" 2>&1
    [ "$status" -eq 0 ]
    [[ "$output" == *"BLOCK_COUNT=0"* ]]
}
