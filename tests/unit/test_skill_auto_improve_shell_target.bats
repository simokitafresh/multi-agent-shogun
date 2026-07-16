#!/usr/bin/env bats

setup() {
    export TEST_ROOT="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$TEST_ROOT/scripts" "$TEST_ROOT/empty-skills"
    cp "$BATS_TEST_DIRNAME/../../scripts/skill_auto_improve.sh" "$TEST_ROOT/scripts/"
    cp -R "$BATS_TEST_DIRNAME/../../scripts/lib" "$TEST_ROOT/scripts/"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "ok\\n"' > "$TEST_ROOT/scripts/target.sh"
    chmod +x "$TEST_ROOT/scripts/target.sh"
    cat > "$TEST_ROOT/executions.yaml" <<EOF
executions:
  - ts: "2026-07-16T22:00:00+0900"
    skill: "missing-shell-skill"
    result: "FAIL"
    used: "true"
    gate: "none"
    stumbling_points: "fixture failure"
    skill_path: "$TEST_ROOT/scripts/target.sh"
EOF
}

@test "apply comments every generated prevention line for shell targets" {
    run env SHOGUN_REPO_ROOT="$TEST_ROOT" \
        SKILL_EXECUTION_LOG_FILE="$TEST_ROOT/executions.yaml" \
        SKILL_AUTO_IMPROVE_SKILLS_DIRS="$TEST_ROOT/empty-skills" \
        SKILL_AUTO_IMPROVE_STATE_JSON="$TEST_ROOT/state.json" \
        bash "$TEST_ROOT/scripts/skill_auto_improve.sh" --apply --top 1

    [ "$status" -eq 0 ]
    grep -Fq '# ### 自動防止ステップ' "$TEST_ROOT/scripts/target.sh"
    grep -Fq '# - <!-- skill-auto-improve:' "$TEST_ROOT/scripts/target.sh"
    bash -n "$TEST_ROOT/scripts/target.sh"
}
