#!/usr/bin/env bats

setup_file() {
    export PRECHECK="$BATS_TEST_DIRNAME/../../scripts/gates/gate_gunshi_report_precheck.sh"
}

@test "SG-PRE13 promotes a greater-than-50-percent hook deletion to blocking error" {
    ERRORS=0
    FILES_MODIFIED="scripts/gates/example.sh"
    _PRE_REPO_NUMSTAT=$'1\t9\tscripts/gates/example.sh'

    eval "$(sed -n '/SG-PRE13: hook\/gate系ファイルの大規模削減検出/,/SG-PRE14: revert検出/p' "$PRECHECK" | sed '$d')"

    [ "$ERRORS" -eq 1 ]
}

@test "SG-PRE13 leaves non-hook files clear" {
    ERRORS=0
    FILES_MODIFIED="docs/example.md"
    _PRE_REPO_NUMSTAT=$'0\t20\tdocs/example.md'

    eval "$(sed -n '/SG-PRE13: hook\/gate系ファイルの大規模削減検出/,/SG-PRE14: revert検出/p' "$PRECHECK" | sed '$d')"

    [ "$ERRORS" -eq 0 ]
}
