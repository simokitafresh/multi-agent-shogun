#!/usr/bin/env bats
# test_restart_monitor.bats - restart_monitor.sh regression checks

setup_file() {
    export PROJECT_ROOT
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "restart_monitor waits after old process termination before launching new monitor" {
    run bash -lc '
PROJECT_ROOT="'"$PROJECT_ROOT"'"
awk "
    /Old process\\(es\\) terminated successfully/ { terminated=NR }
    /Give the old process a moment to close fd 9/ { comment=NR }
    /^[[:space:]]*sleep 1$/ && comment { sleep_line=NR }
    /Starting new ninja_monitor.sh/ { start=NR }
    END {
        if (terminated && comment > terminated && sleep_line > comment && start > sleep_line) {
            print \"PASS\"
            exit 0
        }
        print \"FAIL\"
        exit 1
    }
" "$PROJECT_ROOT/scripts/restart_monitor.sh"
'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASS"* ]]
}
