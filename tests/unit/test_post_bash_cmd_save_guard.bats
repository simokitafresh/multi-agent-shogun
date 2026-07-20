#!/usr/bin/env bats
# test_necessity: PostToolUse Bash classification and optional commit warning stay correct and bounded, including a stalled WSL2 git subprocess.
# regression_justification: filename references and stale BLOCK text previously caused two false-positive injections.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    HOOK="$PROJECT_ROOT/.claude/hooks/post-bash-combined.sh"
}

run_hook() {
    run env HOOK_PAYLOAD="$1" bash "$HOOK"
}

@test "filename reference plus BLOCK output does not inject" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"sed -n 1,20p scripts/cmd_save.sh"},"tool_result":{"exit_code":0,"stdout":"BLOCK: old cmd_save.sh log"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "successful cmd_publish plus stale BLOCK output does not inject" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"bash scripts/cmd_publish.sh cmd_4098"},"tool_result":{"exit_code":0,"stdout":"published\nBLOCK: older failure"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "direct bash cmd_save BLOCK result injects guidance" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"bash scripts/cmd_save.sh cmd_4098"},"tool_result":{"exit_code":1,"stderr":"BLOCK: acceptance criteria missing"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'cmd_save.sh BLOCK'* ]]
    [[ "$output" == *'BLOCK: acceptance criteria missing'* ]]
}

@test "direct env bash cmd_publish BLOCK result injects guidance" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"/usr/bin/env bash scripts/cmd_publish.sh cmd_4098"},"tool_result":{"exit_code":2,"stderr":"BLOCK: publish denied"}}'
    [ "$status" -eq 0 ]
    [[ "$output" == *'cmd_save.sh BLOCK'* ]]
}

@test "nonzero execution without BLOCK record does not inject" {
    run_hook '{"tool_name":"Bash","tool_input":{"command":"bash scripts/cmd_save.sh cmd_4098"},"tool_result":{"exit_code":1,"stderr":"unexpected failure"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "ordinary Bash payload does not run report-only synchronous probes" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/usr/bin/env bash\nprintf "git\\n" >> "$SYNC_PROBE_LOG"\n' > "$BATS_TEST_TMPDIR/bin/git"
    chmod +x "$BATS_TEST_TMPDIR/bin/git"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" SYNC_PROBE_LOG="$BATS_TEST_TMPDIR/probes" \
        HOOK_PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"git status --short"},"tool_result":{"exit_code":0,"stdout":""}}' \
        bash "$HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -e "$BATS_TEST_TMPDIR/probes" ]
}

@test "malformed payload fails open without synchronous probes" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/usr/bin/env bash\nprintf "git\\n" >> "$SYNC_PROBE_LOG"\n' > "$BATS_TEST_TMPDIR/bin/git"
    chmod +x "$BATS_TEST_TMPDIR/bin/git"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" SYNC_PROBE_LOG="$BATS_TEST_TMPDIR/probes" \
        HOOK_PAYLOAD='{malformed' bash "$HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -e "$BATS_TEST_TMPDIR/probes" ]
}

@test "report_received git stall is bounded and fails open with warning" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/usr/bin/env bash\nprintf "git\\n" >> "$SYNC_PROBE_LOG"\nsleep 5\n' > "$BATS_TEST_TMPDIR/bin/git"
    chmod +x "$BATS_TEST_TMPDIR/bin/git"
    start_ms="$(date +%s%3N)"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
        SYNC_PROBE_LOG="$BATS_TEST_TMPDIR/probes" \
        POST_BASH_COMMIT_REMINDER_TIMEOUT_SECONDS=1 \
        HOOK_PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"bash scripts/inbox_write.sh karo done report_received kotaro notify_karo"},"tool_result":{"exit_code":0,"stdout":"ok"}}' \
        bash "$HOOK"
    wall_ms=$(( $(date +%s%3N) - start_ms ))
    [ "$status" -eq 0 ]
    [[ "$output" == *'commit reminder timed out'* ]]
    [ "$wall_ms" -lt 2000 ]
    [ "$(wc -l < "$BATS_TEST_TMPDIR/probes")" -eq 1 ]
}

@test "report_received normal path completes and records synchronous probe count" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/usr/bin/env bash\nprintf "git\\n" >> "$SYNC_PROBE_LOG"\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/git"
    chmod +x "$BATS_TEST_TMPDIR/bin/git"
    start_ms="$(date +%s%3N)"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
        SYNC_PROBE_LOG="$BATS_TEST_TMPDIR/probes" \
        POST_BASH_COMMIT_REMINDER_TIMEOUT_SECONDS=3 \
        HOOK_PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"bash scripts/inbox_write.sh karo done report_received kotaro notify_karo"},"tool_result":{"exit_code":0,"stdout":"ok"}}' \
        bash "$HOOK"
    wall_ms=$(( $(date +%s%3N) - start_ms ))
    [ "$status" -eq 0 ]
    [ "$wall_ms" -lt 3000 ]
    [ "$(wc -l < "$BATS_TEST_TMPDIR/probes")" -gt 0 ]
}

@test "hook does not call gate_report_format synchronously" {
    run grep -n 'gate_report_format' "$HOOK"
    [ "$status" -eq 1 ]
}
