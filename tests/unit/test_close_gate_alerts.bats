#!/usr/bin/env bats

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TMP_DIR="$(mktemp -d)"
    ALERTS="$TMP_DIR/gate_alerts.yaml"
}

teardown() {
    rm -f "$ALERTS" "$ALERTS.lock"
    rmdir "$TMP_DIR"
}

write_fixture() {
    cat > "$ALERTS" <<'YAML'
alerts:
  - alert_id: GA-001
    gate: lesson_health
    alert_detail: "ALERT: unassigned lessons"
    investigation_cmd: null
    improvement_done: false
  - alert_id: GA-002
    gate: hook_failure
    alert_detail: "ALERT: scripts/hooks/pre-bash-guard.sh failed"
    investigation_cmd: null
    improvement_done: false
YAML
}

@test "gate implementation change closes the matching unresolved alert" {
    write_fixture

    run python3 "$ROOT/scripts/lib/close_gate_alerts.py" \
        --alerts "$ALERTS" --cmd-id cmd_4000 -- scripts/gates/gate_lesson_health.sh

    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    run python3 - "$ALERTS" <<'PY'
import sys, yaml
alerts = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))["alerts"]
assert alerts[0]["investigation_cmd"] == "cmd_4000"
assert alerts[0]["improvement_done"] is True
assert alerts[1]["investigation_cmd"] is None
assert alerts[1]["improvement_done"] is False
PY
    [ "$status" -eq 0 ]
}

@test "alert detail check file closes only its matching alert" {
    write_fixture

    run python3 "$ROOT/scripts/lib/close_gate_alerts.py" \
        --alerts "$ALERTS" --cmd-id cmd_4000 -- scripts/hooks/pre-bash-guard.sh

    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
    run grep -F "investigation_cmd: cmd_4000" "$ALERTS"
    [ "$status" -eq 0 ]
}

@test "unrelated files do not close alerts or rewrite the file" {
    write_fixture
    before="$(sha256sum "$ALERTS" | awk '{print $1}')"

    run python3 "$ROOT/scripts/lib/close_gate_alerts.py" \
        --alerts "$ALERTS" --cmd-id cmd_4000 -- docs/readme.md

    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
    after="$(sha256sum "$ALERTS" | awk '{print $1}')"
    [ "$before" = "$after" ]
}
