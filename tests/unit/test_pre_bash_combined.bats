#!/usr/bin/env bats
# test_necessity: tests配下.batsのbash/sh直実行をrunner file modeへ強制し、PASS/FAIL/SKIP会計の迂回を防ぐ公開hook契約。
# regression_justification: 旧Guard 5はcommand全文の文字列一致で参照文まで誤BLOCKしたため、argv位置とheredoc境界を恒久検証する。

setup_file() {
    export ROOT HOOK
    ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    HOOK="$ROOT/.claude/hooks/pre-bash-combined.sh"
}

run_hook() {
    local command="$1" payload
    payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$command")"
    run env BATS_TEST_FILENAME="$BATS_TEST_FILENAME" bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOK"
}

@test "bashでtests配下.batsを直接実行するとfile mode修正文付きでBLOCK" {
    run_hook "bash tests/unit/test_example.bats"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(bats-file-mode)"* ]]
    [[ "$output" == *"bash scripts/run_tests.sh file tests/unit/test_example.bats"* ]]
}

@test "sh・shell option・絶対pathでもtests配下.bats直実行をBLOCK" {
    for command in \
        "sh tests/unit/test_example.bats" \
        "bash -x ./tests/unit/test_example.bats" \
        "bash -O extglob tests/unit/test_example.bats" \
        "env FOO=1 /bin/bash $ROOT/tests/unit/test_example.bats"; do
        run_hook "$command"
        [ "$status" -eq 2 ]
        [[ "$output" == *"BLOCK(bats-file-mode)"* ]]
    done
}

@test "正規bats実行とrun_tests file modeは許可" {
    run_hook "bats tests/unit/test_example.bats"
    [ "$status" -eq 0 ]
    run_hook "bash scripts/run_tests.sh file tests/unit/test_example.bats"
    [ "$status" -eq 0 ]
}

@test "参照文字列とheredoc本文は誤BLOCKしない" {
    run_hook "printf '%s\\n' 'bash tests/unit/test_example.bats'"
    [ "$status" -eq 0 ]
    run_hook $'cat <<\'EOF\'\nbash tests/unit/test_example.bats\nEOF'
    [ "$status" -eq 0 ]
}

@test "bash -cのcommand文字列は直接script引数ではないため誤BLOCKしない" {
    run_hook "bash -c 'printf %s tests/unit/test_example.bats'"
    [ "$status" -eq 0 ]
}

@test "別worktree相当のcwdでも絶対tests pathをBLOCK" {
    local command payload
    command="bash $ROOT/tests/unit/test_example.bats"
    payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$command")"
    run env BATS_TEST_FILENAME="$BATS_TEST_FILENAME" bash -c 'cd "$1"; printf "%s" "$2" | bash "$3"' _ "$BATS_TEST_TMPDIR" "$payload" "$HOOK"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(bats-file-mode)"* ]]
}

@test "並行呼出しは双方BLOCKしmalformed quoteはfail-closed" {
    ( run_hook "bash tests/unit/first.bats"; [ "$status" -eq 2 ] ) & first=$!
    ( run_hook "sh tests/unit/second.bats"; [ "$status" -eq 2 ] ) & second=$!
    wait "$first"
    wait "$second"

    run_hook "bash 'tests/unit/broken.bats"
    [ "$status" -eq 2 ]
    [[ "$output" == *"安全に解析できない"* ]]
}
