#!/bin/bash
# task_deploy.sh — タスク配備後の偵察2名並行チェック
# Usage: bash scripts/task_deploy.sh <cmd_id> <task_type>
# task_type: recon | implement | review | other
# recon時: 2名以上の偵察タスクがあるか+別々の忍者か検証

set -e

# SCRIPT_DIR: string ops instead of $(cd) subshells (~5ms savings on WSL2)
_td_self="${BASH_SOURCE[0]:-$0}"
[[ "$_td_self" != /* ]] && _td_self="$PWD/$_td_self"
SCRIPT_DIR="${_td_self%/scripts/task_deploy.sh}"
TASKS_DIR="$SCRIPT_DIR/queue/tasks"

CMD_ID="$1"
TASK_TYPE="$2"

write_gate_flag() {
    local cmd_id="$1" gate_name="$2" result="$3" reason="$4"
    local gates_dir="$SCRIPT_DIR/queue/gates"
    # printf -v builtin avoids spawning date; [[ -d ]] skip avoids mkdir when exists
    local _ts
    printf -v _ts '%(%Y-%m-%dT%H:%M:%S)T' -1
    [[ -d "$gates_dir" ]] || mkdir -p "$gates_dir"
    local flag_file="$gates_dir/${cmd_id}_${gate_name}.${result}"
    # printf builtin avoids forking cat for heredoc write
    printf 'timestamp: %s\ncmd_id: %s\ngate_name: %s\nresult: %s\nreason: "%s"\n' \
        "$_ts" "$cmd_id" "$gate_name" "$result" "$reason" > "$flag_file"
}

# Validate arguments
if [ -z "$CMD_ID" ] || [ -z "$TASK_TYPE" ]; then
    echo "Usage: task_deploy.sh <cmd_id> <task_type>" >&2
    echo "  task_type: recon | implement | review | other" >&2
    exit 1
fi

# Non-recon: skip check
if [ "$TASK_TYPE" != "recon" ]; then
    echo "OK: task_type=$TASK_TYPE — 偵察チェックスキップ"
    write_gate_flag "$CMD_ID" "task_deploy" "skip" "task_type=$TASK_TYPE"
    exit 0
fi

# Scan queue/tasks/*.yaml for recon tasks matching parent_cmd
check_output=$(python3 - "$TASKS_DIR" "$CMD_ID" <<'PYEOF'
import yaml, sys, glob, os

tasks_dir = sys.argv[1]
cmd_id = sys.argv[2]
recon_tasks = []

for path in sorted(glob.glob(os.path.join(tasks_dir, "*.yaml"))):
    try:
        with open(path) as f:
            data = yaml.safe_load(f)
    except Exception:
        continue

    if not data or not isinstance(data, dict):
        continue

    task = data.get("task", data)
    if not isinstance(task, dict):
        continue

    parent = task.get("parent_cmd", "")
    if parent != cmd_id:
        continue

    title = str(task.get("title", ""))
    if "\u5075\u5bdf" in title or "recon" in title.lower():
        assigned = task.get("assigned_to", "unknown")
        task_id = task.get("task_id") or task.get("_ac_task_id") or os.path.basename(path)
        recon_tasks.append({"id": task_id, "assigned_to": assigned, "file": os.path.basename(path)})

count = len(recon_tasks)

if count < 2:
    print(f"ERROR: \u5075\u5bdf\u30bf\u30b9\u30af\u306f2\u540d\u4e26\u884c\u304c\u5fc5\u9808(\u73fe\u5728{count}\u4ef6)", file=sys.stderr)
    if recon_tasks:
        for t in recon_tasks:
            print(f'  - {t["id"]} \u2192 {t["assigned_to"]} ({t["file"]})', file=sys.stderr)
    sys.exit(1)

# Check for duplicate assignees
assignees = [t["assigned_to"] for t in recon_tasks]
if len(set(assignees)) < len(assignees):
    from collections import Counter
    dupes = [a for a, c in Counter(assignees).items() if c > 1]
    print(f'ERROR: \u4e26\u884c\u5075\u5bdf\u306f\u5225\u3005\u306e\u5fcd\u8005\u306b\u5272\u308a\u5f53\u3066\u3088(\u91cd\u8907: {", ".join(dupes)})', file=sys.stderr)
    for t in recon_tasks:
        print(f'  - {t["id"]} \u2192 {t["assigned_to"]} ({t["file"]})', file=sys.stderr)
    sys.exit(1)

names = ", ".join(t["assigned_to"] for t in recon_tasks)
print(f"OK: \u5075\u5bdf{count}\u4ef6({names})")
PYEOF
)
echo "$check_output"

ok_line=$(printf '%s\n' "$check_output" | tail -n1)
count=$(printf '%s\n' "$ok_line" | sed -n 's/^OK: 偵察\([0-9]\+\)件(.*/\1/p')
ninjas=$(printf '%s\n' "$ok_line" | sed -n 's/^OK: 偵察[0-9]\+件(\(.*\))$/\1/p')
[ -n "$count" ] || count=0
[ -n "$ninjas" ] || ninjas="unknown"

write_gate_flag "$CMD_ID" "task_deploy" "pass" "偵察${count}件(${ninjas})"
exit 0
