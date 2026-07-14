#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "review bundle carries the cmd summary and FAIL-only karo attention" {
    local skill="$PROJECT_ROOT/skills/review-bundle/SKILL.md"

    grep -q 'cmd_spec_summary:' "$skill"
    grep -q 'acceptance_criteria_count:' "$skill"
    grep -q 'scope:' "$skill"
    grep -q 'project:' "$skill"
    grep -q 'karo_attention: <FAIL時のみ' "$skill"
    grep -q 'APPROVE時はキー自体を省略' "$skill"
}

@test "karo completion consumes SG7 without duplicate full reads" {
    local karo="$PROJECT_ROOT/instructions/karo.md"
    local complete="$PROJECT_ROOT/skills/cmd-complete/SKILL.md"

    grep -q 'SG7バンドルが完了処理SSOT' "$karo"
    grep -q '報告YAML全文.*cmd specを家老が再Readすることは禁止' "$karo"
    grep -q 'SG7バンドルを完了処理の単一情報源にする' "$complete"
    grep -q 'acceptance_criteria_count.*scope.*project' "$complete"
    grep -q '報告YAML全文.*cmd specを再Readしてはならない' "$complete"
}
