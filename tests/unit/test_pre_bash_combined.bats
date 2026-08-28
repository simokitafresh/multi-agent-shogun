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

run_dispatch() {
    local command="$1" payload
    payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$command")"
    run env BATS_TEST_FILENAME="$BATS_TEST_FILENAME" bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$ROOT/.claude/hooks/pretool-dispatch.sh"
}

@test "Claude pretool dispatchのlive chainは直接batsをBLOCKしrunner file modeを許可" {
    run_dispatch "env FOO=bar bash -c 'timeout 30 bats tests/unit/test_pre_bash_combined.bats'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK: batsの直接実行は禁止"* ]]
    [[ "$output" == *"bash scripts/run_tests.sh file"* ]]

    run_dispatch "env FOO=bar bash scripts/run_tests.sh file tests/unit/test_pre_bash_combined.bats"
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK: batsの直接実行は禁止"* ]]
}

@test "Codex/Claudeのcombined callerは各1件でclassifier接続が重複しない" {
    local codex_callers claude_callers classifier_callers
    codex_callers="$(rg -n 'pre-bash-combined\.sh' .codex/hooks.json | awk 'END {print NR+0}')"
    claude_callers="$(rg -n 'pre-bash-combined\.sh' .claude/hooks/pretool-dispatch.sh | awk 'END {print NR+0}')"
    classifier_callers="$(rg -nF 'scripts/hooks/pre-bash-test-fullrun-guard.sh' .claude/hooks/pre-bash-combined.sh | awk 'END {print NR+0}')"
    [ "$codex_callers" -eq 1 ]
    [ "$claude_callers" -eq 1 ]
    [ "$classifier_callers" -eq 1 ]
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

@test "直接batsはclassifierでBLOCKしrun_tests file modeは許可" {
    run_hook "bats tests/unit/test_example.bats"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK: batsの直接実行は禁止"* ]]
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

# cmd_karo_impl_commander_scope_commit_20260725
# test_necessity: GA-231 previously checked only get_ninja_names, leaving shogun/karo/gunshi
# free to run raw `git commit` and sweep in another agent's staged changes (実害: 0f1c3ea65
# swallowed 才蔵's staged 922-line deletion). Commander roles must now be denied the same way,
# directed at ninja_scope_commit.sh's explicit-pathspec entry point.
@test "commander(karo) direct git commit is BLOCKED and routed to ninja_scope_commit.sh (GA-231c)" {
    TMUX_AGENT_ID=karo run_hook "git commit -m test"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(GA-231c)"* ]]
    [[ "$output" == *"ninja_scope_commit.sh"* ]]
}

@test "commander(shogun/gunshi) direct git commit is BLOCKED same as karo (GA-231c)" {
    for _cmdr in shogun gunshi; do
        TMUX_AGENT_ID="$_cmdr" run_hook "git commit -m test"
        [ "$status" -eq 2 ]
        [[ "$output" == *"BLOCK(GA-231c)"* ]]
    done
}

# test_necessity: regression guard — the pre-existing ninja block (GA-231) must keep firing
# with its own message, not the new commander branch, so callers still get ninja-specific
# guidance (/ninja-commit).
@test "ninja direct git commit is still BLOCKED with the original GA-231 message (regression)" {
    TMUX_AGENT_ID=saizo run_hook "git commit -m test"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCK(GA-231)"* ]]
    [[ "$output" != *"GA-231c"* ]]
    [[ "$output" == *"/ninja-commit"* ]]
}

# test_necessity: an unrecognized agent id (neither ninja nor commander) must not be denied by
# GA-231/GA-231c — false positives here would fail-closed every unlabeled or CI invocation.
@test "unrecognized agent id direct git commit is not blocked by GA-231/GA-231c" {
    TMUX_AGENT_ID=nobody run_hook "git commit -m test"
    [[ "$output" != *"BLOCK(GA-231"* ]]
}

# test_necessity: Guard2 previously classified raw argument text, so a read-only
# search for a forbidden Python/YAML example was denied despite executing only rg.
@test "Guard2 allows read-only search arguments containing Python YAML write examples" {
    run_hook "rg 'python3 yaml.dump open(\"queue/x.yaml\",\"w\")' AGENTS.md"
    [ "$status" -eq 0 ]
    [[ "$output" != *"yaml.dump on operational YAML"* ]]
}

# test_necessity: narrowing Guard2 to executable argv must not permit actual
# operational-YAML writes through Python, including an absolute interpreter path.
@test "Guard2 blocks actual Python operational YAML dump variations" {
    for command in \
        "python3 -c 'import yaml; yaml.dump({},open(\"queue/tasks/x.yaml\",\"w\"))'" \
        "/usr/bin/python3 -c 'import yaml; yaml.safe_dump({},open(\"queue/inbox/x.yaml\",\"a\"))'"; do
        run_hook "$command"
        [ "$status" -eq 2 ]
        [[ "$output" == *"yaml.dump on operational YAML"* ]]
    done
}

# test_necessity: helper evidence/reason text may describe direct commits; only
# an executed git commit argv is subject to GA-231/GA-231c.
@test "GA-231 allows helper argument text describing direct git commit" {
    TMUX_AGENT_ID=hanzo run_hook "bash scripts/report_field_set.sh report.yaml reason 'direct git commit is forbidden'"
    [ "$status" -eq 0 ]
    [[ "$output" != *"BLOCK(GA-231"* ]]
}

# test_necessity: shared-main integration must not inherit a private index and
# advance ref/index while leaving changed worktree paths at an older blob.
@test "direct shared git merge is blocked and convergence helper is allowed" {
    run_hook "git merge --ff-only origin/main"
    [ "$status" -eq 2 ]
    [[ "$output" == *"D012"* ]]
    [[ "$output" == *"safe_shared_main_ff.sh"* ]]

    run_hook "bash scripts/safe_shared_main_ff.sh origin/main"
    [ "$status" -eq 0 ]
    [[ "$output" != *"D012"* ]]
}

# T163 (2026-08-28): cherry-pick in the shared worktree left conflict markers in a
# live hook for 12 minutes and self-deadlocked karo.  History-rewriting ops must
# run in an isolated worktree; --continue/--abort stay allowed so an in-flight op
# can always be finished.
@test "D012: git cherry-pick/rebase/revert in shared worktree are blocked, --continue allowed" {
    run_hook "git cherry-pick 43fc68078"
    [ "$status" -eq 2 ]
    [[ "$output" == *"D012"* ]]
    [[ "$output" == *"cherry-pick"* ]]

    run_hook "git rebase origin/main"
    [ "$status" -eq 2 ]
    [[ "$output" == *"D012"* ]]

    run_hook "git cherry-pick --continue"
    [ "$status" -eq 0 ]
    [[ "$output" != *"D012"* ]]
}

# test_necessity: 家老 pane からの run_tests/bats 再試験は BLOCK され(殿裁定 2026-08-29 00:50)、忍者の同一 command と KARO_TEST_REASON 付きは通る。
@test "karo-retest guard: 家老の run_tests.sh は BLOCK される" {
    payload="$(python3 -c 'import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"BATS_CACHE=0 bash scripts/run_tests.sh file tests/unit/test_x.bats"}}))')"
    run env BATS_TEST_FILENAME="$BATS_TEST_FILENAME" TMUX_AGENT_ID=karo bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOK"
    [ "$status" -ne 0 ]
    [[ "$output" == *"karo-retest"* ]]
}

@test "karo-retest guard: KARO_TEST_REASON=e2e 付きは通る" {
    payload="$(python3 -c 'import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"KARO_TEST_REASON=e2e bash scripts/run_tests.sh file tests/unit/test_x.bats"}}))')"
    run env BATS_TEST_FILENAME="$BATS_TEST_FILENAME" TMUX_AGENT_ID=karo bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOK"
    [[ "$output" != *"karo-retest"* ]]
}

@test "karo-retest guard: 忍者の run_tests.sh は通る" {
    payload="$(python3 -c 'import json; print(json.dumps({"tool_name":"Bash","tool_input":{"command":"bash scripts/run_tests.sh file tests/unit/test_x.bats"}}))')"
    run env BATS_TEST_FILENAME="$BATS_TEST_FILENAME" TMUX_AGENT_ID=hanzo bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOK"
    [[ "$output" != *"karo-retest"* ]]
}
