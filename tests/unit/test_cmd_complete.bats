#!/usr/bin/env bats

setup() {
    export ROOT="$BATS_TEST_TMPDIR/root"
    mkdir -p "$ROOT/scripts/gates" "$ROOT/scripts/lib" \
        "$ROOT/queue/gates/cmd_fixture" "$ROOT/queue/inbox" "$ROOT/archive/inbox" "$ROOT/logs"
    cp "$BATS_TEST_DIRNAME/../../scripts/cmd_complete.sh" "$ROOT/scripts/cmd_complete.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/defense_overhead_writer.sh" \
        "$ROOT/scripts/lib/defense_overhead_writer.sh"
    cp "$BATS_TEST_DIRNAME/../../scripts/lib/retro_pane_prompt.sh" \
        "$ROOT/scripts/lib/retro_pane_prompt.sh"
    printf '%s\n' \
        '{"review":{"cmd_id":"cmd_fixture","report_fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}' \
        >"$ROOT/queue/gates/cmd_fixture/sg7_bundle.json"

    cat >"$ROOT/scripts/review_bundle.py" <<'PY'
import json
print(json.dumps({"project": "infra"}))
PY
    cat >"$ROOT/scripts/lesson_review.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    cat >"$ROOT/scripts/cmd_complete_gate.sh" <<'SH'
#!/usr/bin/env bash
printf '%s CLEAR\n' "$1" >>"$CMD_COMPLETE_ROOT_DIR/logs/gate_metrics.log"
exit 0
SH
    cat >"$ROOT/scripts/cmd_quality_log.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    cat >"$ROOT/scripts/gates/gate_yaml_status.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    cat >"$ROOT/scripts/archive_completed.sh" <<'SH'
#!/usr/bin/env bash
mkdir -p "$ARCHIVE_COMPLETED_PROJECT_DIR/queue/gates/cmd_fixture"
: >"$ARCHIVE_COMPLETED_PROJECT_DIR/queue/gates/cmd_fixture/archive.done"
SH
    cat >"$ROOT/scripts/dashboard_update.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    cat >"$ROOT/scripts/ntfy_cmd.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    cat >"$ROOT/scripts/inbox_mark_read.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
agent="$1"; shift
printf '%s\n' "$@" >>"$CMD_COMPLETE_ROOT_DIR/logs/marked_ids.log"
python3 - "$CMD_COMPLETE_ROOT_DIR/queue/inbox/$agent.yaml" "$@" <<'PY'
import os, sys, tempfile, yaml
path, *ids = sys.argv[1:]
wanted = set(ids)
data = yaml.safe_load(open(path, encoding="utf-8")) or {}
for message in data.get("messages", []):
    if isinstance(message, dict) and message.get("id") in wanted:
        message["read"] = True
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    yaml.safe_dump(data, fh, sort_keys=False, allow_unicode=True)
os.replace(tmp, path)
PY
if [[ ! -e "$CMD_COMPLETE_ROOT_DIR/logs/arrival.injected" ]]; then
    : >"$CMD_COMPLETE_ROOT_DIR/logs/arrival.injected"
    python3 - "$CMD_COMPLETE_ROOT_DIR/queue/inbox/$agent.yaml" <<'PY'
import os, sys, tempfile, yaml
path = sys.argv[1]
data = yaml.safe_load(open(path, encoding="utf-8")) or {"messages": []}
data.setdefault("messages", []).append({
    "id": "arrival-other", "read": False, "type": "task_assigned",
    "parent_cmd": "cmd_other",
})
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, "w", encoding="utf-8") as fh:
    yaml.safe_dump(data, fh, sort_keys=False, allow_unicode=True)
os.replace(tmp, path)
PY
fi
SH
    cat >"$ROOT/scripts/inbox_archive.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CMD_COMPLETE_ROOT_DIR/logs/archive_calls.log"
SH
    chmod +x "$ROOT/scripts"/*.sh "$ROOT/scripts/gates"/*.sh
    : >"$ROOT/logs/gate_metrics.log"
    export CMD_COMPLETE_ROOT_DIR="$ROOT" CMD_COMPLETE_SCRIPT_DIR="$ROOT/scripts"
    export CMD_COMPLETE_SYNC_TAIL=1 CMD_COMPLETE_DASHBOARD_ENABLED=0
    export DEFENSE_OVERHEAD_ENABLED=0
}

write_fixture_inbox() {
    python3 - "$ROOT/queue/inbox/karo.yaml" <<'PY'
import os, sys, yaml

path = sys.argv[1]
target = "cmd_fixture"
terminal_types = [
    "report_received",
    "report_review_result",
    "accept_report",
    "run_cmd_complete",
    "gate_clear_required",
]
messages = []
for index, message_type in enumerate(terminal_types):
    messages.append({"id": f"target-{index}", "read": False,
                     "type": message_type, "parent_cmd": target})
messages.append({"id": "target-read", "read": True,
                 "type": "gate_clear_required", "parent_cmd": target})
messages.append({"id": "target-processing", "read": False,
                 "type": "task_assigned", "parent_cmd": target})
for index in range(13):
    messages.append({"id": f"other-terminal-{index}", "read": False,
                     "type": terminal_types[index % len(terminal_types)],
                     "parent_cmd": "cmd_other"})
for index in range(14):
    messages.append({"id": f"other-task-{index}", "read": False,
                     "type": "task_assigned", "parent_cmd": "cmd_other"})
with open(path, "w", encoding="utf-8") as fh:
    yaml.safe_dump({"messages": messages}, fh, sort_keys=False)
PY
}

# test_necessity: completion must consume all and only the current cmd's unread
# terminal notifications, preserving unrelated/read/processing/new-arrival rows.
# regression_justification: the prior wrapper consumed only skill_hint rows,
# leaving the five terminal notification types unread in Karo's mailbox.
@test "completion drains only matching unread terminal notifications from 33-message fixture" {
    write_fixture_inbox
    python3 - "$ROOT/queue/inbox/karo.yaml" >"$ROOT/fixture_counts.log" <<'PY'
import sys, yaml
messages = yaml.safe_load(open(sys.argv[1]))["messages"]
assert len(messages) == 34, len(messages)
assert sum(message.get("read") is False for message in messages) == 33
print(f"fixture_unread={sum(message.get('read') is False for message in messages)}")
PY
    grep -q '^fixture_unread=33$' "$ROOT/fixture_counts.log"

    run bash "$ROOT/scripts/cmd_complete.sh" cmd_fixture \
        "$ROOT/queue/gates/cmd_fixture/sg7_bundle.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"inbox_terminal_drain parent_cmd=cmd_fixture selected=5"* ]]
    [ "$(wc -l <"$ROOT/logs/marked_ids.log")" -eq 5 ]
    [ "$(grep -c '^target-' "$ROOT/logs/marked_ids.log")" -eq 5 ]

    run python3 - "$ROOT/queue/inbox/karo.yaml" <<'PY'
import sys, yaml
messages = yaml.safe_load(open(sys.argv[1]))["messages"]
unread = [m for m in messages if m.get("read") is False]
marked = {m["id"] for m in messages if m["id"].startswith("target-") and m.get("read") is True}
assert {m["type"] for m in messages if m["id"].startswith("target-") and m["id"] != "target-read" and m["id"] != "target-processing"} == {
    "report_received", "report_review_result", "accept_report", "run_cmd_complete", "gate_clear_required"
}
assert not [m for m in unread if m["id"].startswith("target-") and m["id"] not in {"target-read", "target-processing"}]
assert any(m["id"] == "target-processing" for m in unread)
assert len(unread) == 29
assert all(m["parent_cmd"] == "cmd_other" for m in unread if m["id"].startswith("other-"))
assert any(m["id"] == "arrival-other" for m in unread)
print(f"remaining_unread={len(unread)} marked_target_count={len(marked)} arrival_preserved=yes")
PY
    [ "$status" -eq 0 ]
    [[ "$output" == *"remaining_unread=29 marked_target_count=6 arrival_preserved=yes"* ]]
}
