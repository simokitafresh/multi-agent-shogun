#!/usr/bin/env bats
# test_necessity: queue/tasks共有YAMLはread-only検査を許可し、非atomic直接書込みと判別不能modeを必ずBLOCKする公開hook契約。
# regression_justification: open(...).read()/yaml.safe_load()が直接書込guardに誤分類された偽陽性と、未知modeの偽陰性を境界表で恒久検証する。

setup_file() {
    export ROOT HOOK
    ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    HOOK="$ROOT/.claude/hooks/pre-bash-combined.sh"
}

run_hook() {
    local command="$1" payload
    payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$command")"
    run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOK"
}

@test "legacy broad Python matcher reproduces read-only false positive 1/1" {
    local command legacy_pattern
    command="python3 -c 'import yaml; yaml.safe_load(open(\"queue/tasks/hayate.yaml\"))'"
    legacy_pattern='python3?.*open.*queue/tasks/.*\.yaml'
    [[ "$command" =~ $legacy_pattern ]]
}

@test "queue task YAML read-only Python paths are allowed 4/4" {
    local command
    for command in \
        "python3 -c 'open(\"queue/tasks/hayate.yaml\").read()'" \
        "python3 -c 'import yaml; yaml.safe_load(open(\"queue/tasks/hayate.yaml\"))'" \
        "python3 -c 'from pathlib import Path; Path(\"queue/tasks/hayate.yaml\").read_text()'" \
        "python3 -c 'open(\"queue/tasks/hayate.yaml\", \"r\").read()'"; do
        run_hook "$command"
        [ "$status" -eq 0 ]
    done
}

@test "queue task YAML direct writes are blocked 8/8" {
    local command
    for command in \
        "python3 -c 'open(\"queue/tasks/hayate.yaml\", \"w\")'" \
        "python3 -c 'open(\"queue/tasks/hayate.yaml\", \"a\")'" \
        "python3 -c 'open(\"queue/tasks/hayate.yaml\", \"x\")'" \
        "python3 -c 'open(\"queue/tasks/hayate.yaml\", \"r+\")'" \
        "python3 -c 'from pathlib import Path; Path(\"queue/tasks/hayate.yaml\").write_text(\"x\")'" \
        "printf x > queue/tasks/hayate.yaml" \
        "printf x | tee queue/tasks/hayate.yaml" \
        "sed -i s/x/y/ queue/tasks/hayate.yaml"; do
        run_hook "$command"
        [ "$status" -eq 2 ]
        [[ "$output" == *"queue/tasks/へのBash直接書換え"* ]]
    done
}

@test "unknown Python open mode is fail-closed" {
    run_hook "python3 -c 'open(\"queue/tasks/hayate.yaml\", mode)'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"queue/tasks/へのBash直接書換え"* ]]
}
