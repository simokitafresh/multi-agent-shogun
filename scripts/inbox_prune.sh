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

        # Fast exit: count read messages without python3
        local read_count
        read_count=$(grep -c '^  read: true' "$INBOX" 2>/dev/null) || read_count=0
        if (( read_count <= KEEP_READ )); then
            exit 0
        fi

        local tmp
        tmp=$(mktemp --tmpdir="$(dirname "$INBOX")" .inbox_prune_XXXXXX.tmp)

        # awk: parse message blocks, keep unread + last KEEP_READ read (no re-serialization)
        awk -v keep="$KEEP_READ" -v agent="$agent" '
        BEGIN { n_ur=0; n_r=0; in_msg=0; block=""; is_read=0 }
        /^messages:/ { next }
        /^- / {
            if (in_msg) {
                if (is_read) { n_r++; r[n_r]=block } else { n_ur++; ur[n_ur]=block }
            }
            in_msg=1; block=$0"\n"; is_read=0; next
        }
        in_msg {
            if (/^[[:space:]]*read:[[:space:]]*true[[:space:]]*$/) is_read=1
            block=block $0"\n"; next
        }
        END {
            if (in_msg) {
                if (is_read) { n_r++; r[n_r]=block } else { n_ur++; ur[n_ur]=block }
            }
            pruned = n_r - keep
            printf "messages:\n"
            if (n_ur == 0 && n_r == 0) { printf "messages: []\n"; exit }
            for (i=1; i<=n_ur; i++) printf "%s", ur[i]
            start = n_r - keep + 1
            if (start < 1) start = 1
            for (i=start; i<=n_r; i++) printf "%s", r[i]
            printf "PRUNED: %s %d messages removed\n", agent, pruned > "/dev/stderr"
        }
        ' "$INBOX" > "$tmp" && mv "$tmp" "$INBOX"

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
