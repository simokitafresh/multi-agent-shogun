#!/bin/bash
# inbox_prune.sh — 既読メッセージの自動退避（直近5件は保持）
# Usage: bash scripts/inbox_prune.sh [agent_name]
#   agent_name省略時: queue/inbox/*.yaml の全agentを処理
#
# 仕様:
#   - read: true のメッセージのうち直近5件以外を archive/inbox へ退避
#   - flock排他制御: symlink解決後の実体パスでinbox_write.shと同じlockを使用
#   - ログ: 「ARCHIVED+PRUNED: {agent} {count} messages」(stderr)
#   - 削除0件時は何も出力しない

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INBOX_DIR="$SCRIPT_DIR/queue/inbox"
ARCHIVE_DIR="$SCRIPT_DIR/archive/inbox"
KEEP_READ=5  # 保持する既読メッセージ数

# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/lock_path.sh" 2>/dev/null \
    || lock_path() { printf '%s.lock' "$1"; }

resolve_inbox_file_path() {
    local inbox_file="$1" resolved="" inbox_dir="" inbox_base="" resolved_dir=""
    resolved=$(readlink -f "$inbox_file" 2>/dev/null || true)
    if [ -n "$resolved" ]; then
        printf '%s\n' "$resolved"
        return 0
    fi
    inbox_dir="${inbox_file%/*}"
    inbox_base="${inbox_file##*/}"
    resolved_dir=$(readlink -f "$inbox_dir" 2>/dev/null || true)
    if [ -n "$resolved_dir" ]; then
        printf '%s/%s\n' "$resolved_dir" "$inbox_base"
    else
        printf '%s\n' "$inbox_file"
    fi
}

prune_inbox() {
    local agent="$1"
    local INBOX
    INBOX=$(resolve_inbox_file_path "$INBOX_DIR/${agent}.yaml")
    local LOCKFILE
    LOCKFILE=$(lock_path "$INBOX")

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

        local tmp archived_tmp archive_file archive_new date_stamp
        tmp=$(mktemp --tmpdir="$(dirname "$INBOX")" .inbox_prune_XXXXXX.tmp)
        archived_tmp=$(mktemp /tmp/.inbox_pruned_XXXXXX.tmp)
        printf -v date_stamp '%(%Y%m%d)T' -1
        archive_file="$ARCHIVE_DIR/${agent}_${date_stamp}.yaml"
        mkdir -p "$ARCHIVE_DIR"

        # awk: parse message blocks, keep unread + last KEEP_READ read.  The
        # removed blocks are emitted verbatim for durable archival.
        if ! awk -v keep="$KEEP_READ" -v agent="$agent" -v archived="$archived_tmp" '
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
            for (i=1; i<=n_ur; i++) printf "%s", ur[i]
            start = n_r - keep + 1
            if (start < 1) start = 1
            for (i=start; i<=n_r; i++) printf "%s", r[i]
            for (i=1; i<start; i++) printf "%s", r[i] > archived
            printf "ARCHIVED+PRUNED: %s %d messages\n", agent, pruned > "/dev/stderr"
        }
        ' "$INBOX" > "$tmp"; then
            rm -f "$tmp" "$archived_tmp"
            exit 1
        fi

        # Archive first, then replace the inbox.  A crash between these two
        # operations may duplicate evidence but can never destroy it.
        if [ -s "$archived_tmp" ]; then
            if [ -f "$archive_file" ] && ! grep -q '^messages:[[:space:]]*\[\]' "$archive_file"; then
                cat "$archived_tmp" >> "$archive_file"
            else
                archive_new=$(mktemp --tmpdir="$ARCHIVE_DIR" .inbox_archive_XXXXXX.tmp)
                {
                    printf 'messages:\n'
                    cat "$archived_tmp"
                } > "$archive_new"
                mv "$archive_new" "$archive_file"
            fi
        fi
        mv "$tmp" "$INBOX"
        rm -f "$archived_tmp"

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
