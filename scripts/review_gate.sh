#!/bin/bash
# review_gate.sh — コード変更を含むcmdのレビュー完了ゲート
# Usage: bash scripts/review_gate.sh <cmd_id>
# Exit 0: PASS(レビュー済み) or SKIP(コード変更なし)
# Exit 1: BLOCK(レビュー未完了 or レビュータスクなし)

set -e

write_gate_flag() {
    local cmd_id="$1" gate_name="$2" result="$3" reason="$4"
    local gates_dir="$SCRIPT_DIR/queue/gates"
    mkdir -p "$gates_dir"
    local flag_file="$gates_dir/${cmd_id}_${gate_name}.${result}"
    cat > "$flag_file" <<EOF2
timestamp: $(date +%Y-%m-%dT%H:%M:%S)
cmd_id: $cmd_id
gate_name: $gate_name
result: $result
reason: "$reason"
EOF2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMD_ID="$1"

if [ -z "$CMD_ID" ]; then
    echo "Usage: review_gate.sh <cmd_id>" >&2
    exit 1
fi

TASKS_DIR="$SCRIPT_DIR/queue/tasks"

if [ ! -d "$TASKS_DIR" ]; then
    echo "SKIP: タスクディレクトリが存在しない ($TASKS_DIR)"
    exit 0
fi

set +e
PY_OUT="$(python3 - "$CMD_ID" "$TASKS_DIR" <<'PYEOF'
import yaml, glob, sys, os

cmd_id = sys.argv[1]
tasks_dir = sys.argv[2]

# コード変更を示すキーワード
code_keywords = [
    # 既存
    'commit', 'push', 'コード変更', '修正', '実装', 'implement',
    # 英語追加
    'update', 'change', 'refactor', 'fix', 'create', 'add',
    'delete', 'config', 'script', 'hook', 'wrapper', 'modify',
    'patch', 'remove',
    # 日本語追加
    '更新', '変更', 'リファクタ', '作成', '追加', '削除',
    '設定', '構築', '強化',
]
# レビューを示すキーワード
review_keywords = ['review', 'レビュー']

# 全タスクYAMLを走査
all_tasks = []
for yaml_path in glob.glob(os.path.join(tasks_dir, '*.yaml')):
    try:
        with open(yaml_path) as f:
            data = yaml.safe_load(f)
        if not data or 'task' not in data:
            continue
        task = data['task']
        if task.get('parent_cmd') != cmd_id:
            continue
        all_tasks.append(task)
    except Exception:
        continue

if not all_tasks:
    print(f'SKIP: {cmd_id}に該当するタスクなし')
    sys.exit(0)

# コード変更タスクの検出
code_tasks = []
review_tasks = []

for task in all_tasks:
    title = (task.get('title') or '').lower()
    desc = (task.get('description') or '').lower()
    search_text = title + ' ' + desc

    is_code = any(kw.lower() in search_text for kw in code_keywords)
    is_review = any(kw.lower() in search_text for kw in review_keywords)

    if is_review:
        review_tasks.append(task)
    if is_code and not is_review:
        code_tasks.append(task)

if not code_tasks:
    print(f'SKIP: コード変更タスクなし ({len(all_tasks)}件中0件)')
    sys.exit(0)

# コード変更あり → レビュータスクの確認
if not review_tasks:
    code_ids = ', '.join(t.get('task_id', '?') for t in code_tasks)
    print(f'BLOCK: コード変更あるがレビュータスクなし (変更タスク: {code_ids})')
    sys.exit(1)

# レビュータスクの状態チェック
done_reviews = [t for t in review_tasks if t.get('status') == 'done']
not_done = [t for t in review_tasks if t.get('status') != 'done']

if done_reviews and not not_done:
    reviewers = ', '.join(t.get('assigned_to', '?') for t in done_reviews)
    print(f'PASS: レビュー済み ({reviewers})')
    sys.exit(0)
else:
    for t in not_done:
        reviewer = t.get('assigned_to', '?')
        status = t.get('status', '?')
        tid = t.get('task_id', '?')
        print(f'BLOCK: レビュー未完了 ({reviewer}が{status}) [{tid}]')
    sys.exit(1)
PYEOF
)"
PY_RC=$?
set -e

printf '%s\n' "$PY_OUT"

if [ "$PY_RC" -eq 0 ]; then
    if [[ "$PY_OUT" == PASS:* ]]; then
        reviewer="$(printf '%s\n' "$PY_OUT" | sed -n 's/^PASS: レビュー済み (\(.*\))$/\1/p')"
        [ -z "$reviewer" ] && reviewer="unknown"
        write_gate_flag "$CMD_ID" "review_gate" "pass" "レビュー完了(${reviewer})"
    elif [[ "$PY_OUT" == SKIP:* ]]; then
        write_gate_flag "$CMD_ID" "review_gate" "skip" "コード変更なし"
    fi
    # cmd_108: Write .done flag for cmd_complete_gate
    local_gates_dir="$SCRIPT_DIR/queue/gates/${CMD_ID}"
    mkdir -p "$local_gates_dir"
    echo "timestamp: $(date +%Y-%m-%dT%H:%M:%S)" > "$local_gates_dir/review_gate.done"
    echo "result: ${PY_OUT%%:*}" >> "$local_gates_dir/review_gate.done"
fi

exit "$PY_RC"
