#!/usr/bin/env bash
# bulletin_write.sh — 全エージェント共有掲示板への書込み
# Usage: bash scripts/bulletin_write.sh <content> [requires_confirmation]

set -euo pipefail

SCRIPT_DIR="${BULLETIN_ROOT_OVERRIDE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BULLETIN_FILE="$SCRIPT_DIR/queue/bulletin_board.yaml"
LOCK_FILE="${BULLETIN_FILE}.lock"

if [[ $# -lt 1 ]]; then
    echo "Usage: bash scripts/bulletin_write.sh <content> [requires_confirmation]" >&2
    exit 1
fi

POSTED_BY=""
if [[ -n "${TMUX_PANE:-}" ]]; then
    POSTED_BY="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
fi
if [[ -z "$POSTED_BY" ]]; then
    POSTED_BY="$(tmux display-message -p '#{@agent_id}' 2>/dev/null || true)"
fi
if [[ -z "$POSTED_BY" ]]; then
    echo "ERROR: agent_id unavailable from tmux" >&2
    exit 1
fi

# Usage: bulletin_write.sh <posted_by> <content> [requires_confirmation]
# posted_by is $1 (explicit), content is $2, requires_confirmation is $3
# posted_byはtmuxからも取得するが、引数で明示されたものを優先(互換性)
if [[ $# -ge 2 ]]; then
    # 新形式: bulletin_write.sh <posted_by> <content> [requires_confirmation]
    POSTED_BY_ARG="$1"
    CONTENT="$2"
    REQUIRES_CONFIRMATION="${3:-false}"
    # posted_byが既知エージェント名なら引数を信頼
    case "$POSTED_BY_ARG" in
        shogun|karo|gunshi|hayate|kagemaru|hanzo|saizo|kotaro|tobisaru)
            POSTED_BY="$POSTED_BY_ARG"
            ;;
        *)
            # 第1引数がエージェント名でない→旧形式(content, requires_confirmation)
            CONTENT="$1"
            REQUIRES_CONFIRMATION="${2:-false}"
            ;;
    esac
else
    CONTENT="$1"
    REQUIRES_CONFIRMATION="false"
fi

# GP-207: contentがエージェント名のみの場合はBLOCK(引数順序ミス検出)
case "$CONTENT" in
    shogun|karo|gunshi|hayate|kagemaru|hanzo|saizo|kotaro|tobisaru)
        echo "BLOCK: contentがエージェント名のみ。引数順序ミスの可能性。Usage: bulletin_write.sh <posted_by> <content> [requires_confirmation]" >&2
        exit 1
        ;;
esac
POSTED_AT="$(date '+%Y-%m-%dT%H:%M:%S')"
RAND_SUFFIX="$(printf '%s' "$(date +%s%N)$POSTED_BY$CONTENT" | sha1sum | cut -c1-6)"
ENTRY_ID="blt_$(date '+%Y%m%d_%H%M%S')_${RAND_SUFFIX}"

mkdir -p "$(dirname "$BULLETIN_FILE")"

{
    flock -x 200
    python3 - "$BULLETIN_FILE" "$ENTRY_ID" "$CONTENT" "$POSTED_BY" "$POSTED_AT" "$REQUIRES_CONFIRMATION" <<'PY'
import os
import sys
import yaml

bulletin_file, entry_id, content, posted_by, posted_at, requires_confirmation = sys.argv[1:7]

if os.path.exists(bulletin_file):
    with open(bulletin_file, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
else:
    data = {}

entries = data.get("entries")
if not isinstance(entries, list):
    entries = []

rc_raw = str(requires_confirmation).strip()
if rc_raw.lower() in {"1", "true", "yes", "y"}:
    req = True
elif rc_raw.lower() in {"0", "false", "no", "n", ""}:
    req = False
else:
    agents = [a.strip() for a in rc_raw.split(",") if a.strip()]
    req = agents if agents else False
# GP-210: 同一content+同一posted_byの重複投稿を防止
for existing in entries:
    if (existing.get("content", "").strip() == content.strip()
            and existing.get("posted_by", "") == posted_by):
        print(f"DEDUP: 同一内容の掲示板エントリが既存 ({existing.get('id')})")
        sys.exit(0)

entries.insert(0, {
    "id": entry_id,
    "content": content,
    "posted_by": posted_by,
    "posted_at": posted_at,
    "requires_confirmation": req,
    "confirmed_by": [],
    "status": "open",
})

def sq(value):
    return str(value).replace("'", "''")

tmp_file = f"{bulletin_file}.tmp"
with open(tmp_file, "w", encoding="utf-8") as fh:
    fh.write("entries:\n")
    for entry in entries:
        fh.write(f"- id: '{sq(entry.get('id', ''))}'\n")
        fh.write("  content: |-\n")
        text = str(entry.get("content", ""))
        lines = text.splitlines() or [""]
        for line in lines:
            fh.write(f"    {line}\n")
        fh.write(f"  posted_by: '{sq(entry.get('posted_by', ''))}'\n")
        fh.write(f"  posted_at: '{sq(entry.get('posted_at', ''))}'\n")
        rc = entry.get('requires_confirmation')
        if isinstance(rc, list):
            fh.write("  requires_confirmation:\n")
            for agent_name in rc:
                fh.write(f"    - '{sq(agent_name)}'\n")
        elif rc:
            fh.write("  requires_confirmation: true\n")
        else:
            fh.write("  requires_confirmation: false\n")
        confirmed = entry.get("confirmed_by") or []
        if confirmed:
            fh.write("  confirmed_by:\n")
            for agent in confirmed:
                fh.write(f"    - '{sq(agent)}'\n")
        else:
            fh.write("  confirmed_by: []\n")
        fh.write(f"  status: '{sq(entry.get('status', 'open'))}'\n")
os.replace(tmp_file, bulletin_file)
print(entry_id)
PY
} 200>"$LOCK_FILE"

# --- 投稿者以外の将軍・家老・軍師に自動通知 ---
INBOX_WRITE="$SCRIPT_DIR/scripts/inbox_write.sh"
if [[ -f "$INBOX_WRITE" ]]; then
    # 通知先: 将軍+家老+軍師（投稿者自身は除外）
    NOTIFY_TARGETS=("shogun" "karo" "gunshi")
    # GP-208: 掲示板全文をinboxに含める。80文字要約→全文。
    # 理由: 通知だけでは読みに行く行動は強制できない。
    # inboxを読む行動は既に強制されている(startup gate+stop hook)。
    # その中に全文があれば、別途掲示板を読みに行く必要がない。
    for target in "${NOTIFY_TARGETS[@]}"; do
        if [[ "$target" != "$POSTED_BY" ]]; then
            bash "$INBOX_WRITE" "$target" "掲示板新規投稿($ENTRY_ID): ${CONTENT}" bulletin_notify "$POSTED_BY" 2>/dev/null || true
        fi
    done
fi
