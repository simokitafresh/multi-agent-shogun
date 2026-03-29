#!/usr/bin/env bats
# Unit tests for match_ninja() in deploy_task.sh
# Specifically tests str() safety for ninja: true (boolean) case

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    command -v python3 >/dev/null 2>&1 || return 1
}

# Helper: run match_ninja with given ninja_field value and target_name
run_match_ninja() {
    local ninja_value="$1"
    local target_name="$2"
    python3 - "$ninja_value" "$target_name" <<'PY'
import sys

NINJA_JP_MAP = {
    'hayate': '疾風',
    'kagemaru': '影丸',
    'hanzo': '半蔵',
    'saizo': '才蔵',
    'tobisaru': '飛猿',
    'kotaro': '小太郎',
}

def match_ninja(entry, target_name):
    """エントリが対象忍者に属するか判定"""
    ninja_field = str(entry.get('ninja', '') or '')
    if ninja_field and ninja_field.lower() == target_name.lower():
        return True
    jp_name = NINJA_JP_MAP.get(target_name.lower(), '')
    if not jp_name:
        return False
    for field in ('root_cause', 'detail', 'issue', 'workaround_detail'):
        val = str(entry.get(field, '') or '')
        if jp_name in val:
            return True
    return False

import yaml
ninja_val_raw = sys.argv[1]
target = sys.argv[2]

# Parse the value through YAML to get correct Python type
ninja_val = yaml.safe_load(ninja_val_raw)

entry = {'ninja': ninja_val}
result = match_ninja(entry, target)
print("MATCH" if result else "NO_MATCH")
PY
}

@test "match_ninja: string ninja field matches target" {
    run run_match_ninja "hayate" "hayate"
    [ "$status" -eq 0 ]
    [ "$output" = "MATCH" ]
}

@test "match_ninja: string ninja field case insensitive" {
    run run_match_ninja "Hayate" "hayate"
    [ "$status" -eq 0 ]
    [ "$output" = "MATCH" ]
}

@test "match_ninja: boolean true does not crash (str safety)" {
    run run_match_ninja "true" "hayate"
    [ "$status" -eq 0 ]
    [ "$output" = "NO_MATCH" ]
}

@test "match_ninja: boolean false does not crash" {
    run run_match_ninja "false" "hayate"
    [ "$status" -eq 0 ]
    [ "$output" = "NO_MATCH" ]
}

@test "match_ninja: null/empty does not crash" {
    run run_match_ninja "null" "hayate"
    [ "$status" -eq 0 ]
    [ "$output" = "NO_MATCH" ]
}

@test "match_ninja: empty string does not match" {
    run run_match_ninja "''" "hayate"
    [ "$status" -eq 0 ]
    [ "$output" = "NO_MATCH" ]
}

@test "match_ninja: numeric value does not crash" {
    run run_match_ninja "123" "hayate"
    [ "$status" -eq 0 ]
    [ "$output" = "NO_MATCH" ]
}

@test "match_ninja: wrong ninja name does not match" {
    run run_match_ninja "kagemaru" "hayate"
    [ "$status" -eq 0 ]
    [ "$output" = "NO_MATCH" ]
}
