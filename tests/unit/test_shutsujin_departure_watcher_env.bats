#!/usr/bin/env bats
# test_shutsujin_departure_watcher_env.bats - shogun watcher escalation env guard

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "T-SD-WE-001: shutsujin shogun watcher launch does not disable escalation" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
awk "
    /inbox_watcher.sh\" shogun \"shogun:main\"/ {
        if (block ~ /ASW_DISABLE_ESCALATION=1/) {
            print \"shogun watcher launch disables escalation\"
            exit 1
        }
        found=1
    }
    {
        block = block \"\n\" \$0
        if (length(block) > 1200) {
            block = substr(block, length(block) - 1200)
        }
    }
    END {
        if (!found) {
            print \"shogun watcher launch not found\"
            exit 1
        }
    }
" "$PROJECT_ROOT/shutsujin_departure.sh"
echo "SHOGUN_WATCHER_ESCALATION_ENABLED=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"SHOGUN_WATCHER_ESCALATION_ENABLED=yes"* ]]
}

@test "T-SD-WE-002: shogun startup gate alerts when watcher disables escalation" {
    run bash -c '
set -euo pipefail
PROJECT_ROOT="'"$PROJECT_ROOT"'"
grep -q "■ 将軍watcher環境変数" "$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh"
grep -q "ASW_DISABLE_ESCALATION=1" "$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh"
grep -q "将軍watcher環境変数: ASW_DISABLE_ESCALATION=1" "$PROJECT_ROOT/scripts/gates/gate_shogun_startup.sh"
echo "STARTUP_GATE_ENV_ALERT_PRESENT=yes"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"STARTUP_GATE_ENV_ALERT_PRESENT=yes"* ]]
}
