#!/bin/bash
# inbox_prune.sh — 既読メッセージの自動削除（直近5件は保持）
# Usage: bash scripts/inbox_prune.sh [agent_name]
#   agent_name省略時: queue/inbox/*.yaml の全agentを処理
#
# 仕様:
#   - read: true のメッセージを古い順にソートし、直近5件以外を削除
#   - flock排他制御: inbox_write.shと同じロックファイル(${INBOX}.lock)を使用
#   - ログ: 「PRUNED: {agent} {count} messages removed」(stderr)
#   - 削除0件時は何も出力しない

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INBOX_DIR="$SCRIPT_DIR/queue/inbox"
KEEP_READ=5  # 保持する既読メッセージ数

prune_inbox() {
    local agent="$1"
    local INBOX="$INBOX_DIR/${agent}.yaml"
    local LOCKFILE="${INBOX}.lock"

    if [ ! -f "$INBOX" ]; then
        return 0
    fi

    (
        flock -w 5 200 || exit 1

        python3 -c "
import yaml, sys, os, tempfile

inbox_path = '$INBOX'
keep_read = $KEEP_READ

try:
    with open(inbox_path) as f:
        data = yaml.safe_load(f)

    if not data or not data.get('messages'):
        sys.exit(0)

    msgs = data['messages']
    unread = [m for m in msgs if not m.get('read', False)]
    read_msgs = [m for m in msgs if m.get('read', False)]

    if len(read_msgs) <= keep_read:
        sys.exit(0)  # Nothing to prune

    # Keep only the last N read messages (newest)
    pruned_count = len(read_msgs) - keep_read
    kept_read = read_msgs[-keep_read:]

    data['messages'] = unread + kept_read

    # Atomic write
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(inbox_path), suffix='.tmp')
    try:
        with os.fdopen(tmp_fd, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True, indent=2)
        os.replace(tmp_path, inbox_path)
    except:
        os.unlink(tmp_path)
        raise

    print(f'PRUNED: $agent {pruned_count} messages removed', file=sys.stderr)

except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
"
    ) 200>"$LOCKFILE"
}

# メイン処理
if [ -n "$1" ]; then
    # 特定agentのみ
    prune_inbox "$1"
else
    # 全agentのinboxを処理
    for inbox_file in "$INBOX_DIR"/*.yaml; do
        [ -f "$inbox_file" ] || continue
        agent=$(basename "$inbox_file" .yaml)
        prune_inbox "$agent"
    done
fi
