#!/usr/bin/env bats
# test_necessity: tests配下.batsのbash/sh直実行をrunner file modeへ強制し、PASS/FAIL/SKIP会計の迂回を防ぐ公開hook契約。
# regression_justification: 旧Guard 5はcommand全文の文字列一致で参照文まで誤BLOCKしたため、argv位置とheredoc境界を恒久検証する。

setup_file() {
    export ROOT HOOK
    ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    HOOK="$ROOT/.claude/hooks/pre-bash-combined.sh"
}

setup() {
    export GATE_FIRE_LOG_FILE="$BATS_TEST_TMPDIR/gate_fire_log.yaml"
    export SKILL_EXECUTION_LOG_FILE="$BATS_TEST_TMPDIR/skill_execution_log.yaml"
    export SHOGUN_AGENT_ID="saizo"
}

run_hook() {
    local command="$1" tool="${2:-Bash}" field="${3:-command}" payload
    payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":sys.argv[2],"tool_input":{sys.argv[3]:sys.argv[1]}}))' "$command" "$tool" "$field")"
    run env BATS_TEST_FILENAME="$BATS_TEST_FILENAME" bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOK"
}

@test "shell payload境界は3 toolとcommand/cmdで同じ禁止commit契約を強制する" {
    # test_necessity: Codexの3 shell tool payloadが入口名やcommand field差でPreToolUseを迂回できない不変量。
    for spec in "Bash command" "exec_command cmd" "unified_exec cmd"; do
        set -- $spec
        run_hook "git commit --no-verify -m blocked" "$1" "$2"
        [ "$status" -eq 2 ]
        [[ "$output" == *"BLOCK"* ]]
        run_hook "printf safe" "$1" "$2"
        [ "$status" -eq 0 ]
    done
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

@test "CDP直コマンド3種はnudgeしてexit 0かつfire logへ3件記録" {
    for command in \
        "python3 scripts/cdp_font_probe.py" \
        "chrome --remote-debugging-port=9222" \
        "curl http://127.0.0.1:9222/json/version"; do
        run_hook "$command"
        [ "$status" -eq 0 ]
        [[ "$output" == *"★CDP直コマンド検知: CDP専用スキル /cdp-browse を先に起動せよ"* ]]
    done
    [ "$(grep -c 'gate: \"cdp_direct_skill_nudge\"' "$GATE_FIRE_LOG_FILE")" -eq 3 ]
}

@test "非CDPコマンド5種はnudgeもfire logも発生しない" {
    for command in \
        "ls -la" \
        "python3 normal.py" \
        "python3 server.py --port 8080" \
        "python3 server.py --port 9000" \
        "python3 server.py --port 9222"; do
        run_hook "$command"
        [ "$status" -eq 0 ]
        [[ "$output" != *"CDP直コマンド検知"* ]]
    done
    [ ! -e "$GATE_FIRE_LOG_FILE" ]
}

@test "cdp-browse receipt済みならCDP commandの重複nudgeは0" {
    cat > "$SKILL_EXECUTION_LOG_FILE" <<'YAML'
executions:
- ts: "2026-07-23T14:00:00+0900"
  skill: "cdp-browse"
  executor: "saizo"
  result: "PASS"
  used: "true"
YAML
    run_hook "chrome --remote-debugging-port=9222"
    [ "$status" -eq 0 ]
    [[ "$output" != *"CDP直コマンド検知"* ]]
    [ ! -e "$GATE_FIRE_LOG_FILE" ]
}
