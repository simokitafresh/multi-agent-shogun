#!/usr/bin/env bats
# cmd_karo_hotfix_queue_yaml_atomicity_202607110113
# Verifies Bash direct writes to queue/tasks/*.yaml are denied (Guard 3.6),
# forcing the atomic+validated scripts/lib/yaml_field_set.sh path instead.
# Origin: 2026-07-11 01:09 kagemaru.yaml破損 (queue YAML parse error) を受けた恒久防御。

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export HOOK_SCRIPT="$PROJECT_ROOT/.claude/hooks/pre-bash-combined.sh"
    [ -f "$HOOK_SCRIPT" ] || return 1
}

_run_hook() {
    local cmd="$1"
    local payload
    payload="$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd")"
    run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOK_SCRIPT"
}

@test "redirect overwrite of queue/tasks/*.yaml is denied" {
    _run_hook "echo 'status: idle' > queue/tasks/kagemaru.yaml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
    [[ "$output" == *"yaml_field_set.sh"* ]]
}

@test "tee to queue/tasks/*.yaml is denied" {
    _run_hook "echo test | tee queue/tasks/kagemaru.yaml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "sed -i on queue/tasks/*.yaml is denied" {
    _run_hook "sed -i 's/^status: .*/status: idle/' queue/tasks/kagemaru.yaml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "python3 open() write to queue/tasks/*.yaml is denied" {
    # 埋め込みダブルクォートはprintf '%s' でのJSON構築を壊す(引用符閉じ誤検知)ため、
    # python文字列リテラルはシングルクォートのみで構成する(実行はしないのでシェル的な
    # 妥当性は問わない。hookはcommand文字列のパターンマッチのみ行う)。
    _run_hook "python3 -c open('queue/tasks/kagemaru.yaml','w').write('status: idle')"
    [ "$status" -ne 0 ]
    [[ "$output" == *"deny"* ]]
}

@test "yaml_field_set.sh on queue/tasks/*.yaml is allowed" {
    _run_hook "bash scripts/lib/yaml_field_set.sh queue/tasks/kagemaru.yaml task status idle"
    [ "$status" -eq 0 ]
}

@test "grep mentioning queue/tasks/ is allowed" {
    _run_hook "grep -n status queue/tasks/kagemaru.yaml"
    [ "$status" -eq 0 ]
}

@test "cat of queue/tasks/*.yaml (read-only) is allowed" {
    _run_hook "cat queue/tasks/kagemaru.yaml"
    [ "$status" -eq 0 ]
}

@test "unrelated command outside queue/tasks/ is allowed" {
    _run_hook "echo hello > /tmp/scratch_unrelated.txt"
    [ "$status" -eq 0 ]
}
