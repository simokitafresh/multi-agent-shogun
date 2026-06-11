#!/usr/bin/env bash
# pending_approval_set.sh — 保留ファイルレジストリの登録・解除 (flock安全)
# Usage:
#   pending_approval_set.sh add <path> <reason> [agent_id]
#   pending_approval_set.sh remove <path>
#   pending_approval_set.sh list
# semantic-links: [[pending_approval]], [[crackdown_approval_gate]], [[cmd_3285]]
set -euo pipefail

_self="${BASH_SOURCE[0]:-$0}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
SCRIPT_DIR="${_self%/scripts/pending_approval_set.sh}"

PA_FILE="${PENDING_APPROVAL_FILE:-$SCRIPT_DIR/queue/pending_approval.yaml}"
LOCK_FILE="${PA_FILE}.lock"

cmd="${1:-}"
if [[ -z "$cmd" ]]; then
    echo "Usage: $0 add <path> <reason> [agent_id]" >&2
    echo "       $0 remove <path>" >&2
    echo "       $0 list" >&2
    exit 1
fi

(
    flock -x 9

    case "$cmd" in
        add)
            path="${2:-}"
            reason="${3:-}"
            agent_id="${4:-$(tmux display-message -t "${TMUX_PANE:-}" -p '#{@agent_id}' 2>/dev/null || echo unknown)}"
            if [[ -z "$path" ]]; then
                echo "add: path required" >&2
                exit 1
            fi
            if [[ -z "$reason" ]]; then
                echo "add: reason required" >&2
                exit 1
            fi
            # 初期化
            if [[ ! -f "$PA_FILE" ]]; then
                printf 'entries: []\n' > "$PA_FILE"
            fi
            # 追加 (yaml.dumpを使わず手動フォーマット)
            PATH_VAL="$path" REASON_VAL="$reason" AGENT_VAL="$agent_id" PA_FILE="$PA_FILE" \
            python3 - <<'PY'
import os, yaml, datetime, sys
pa_file = os.environ["PA_FILE"]
with open(pa_file, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {"entries": []}
entries = data.get("entries") or []
path = os.environ["PATH_VAL"]
for e in entries:
    if e.get("path") == path:
        print(f"[pending_approval] already registered: {path}")
        sys.exit(0)
entries.append({
    "path": path,
    "reason": os.environ["REASON_VAL"],
    "registered_by": os.environ["AGENT_VAL"],
    "registered_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
})
with open(pa_file, "w", encoding="utf-8") as f:
    if entries:
        f.write("entries:\n")
        for e in entries:
            f.write(f"- path: {e['path']!r}\n")
            f.write(f"  reason: {e['reason']!r}\n")
            f.write(f"  registered_by: {e['registered_by']!r}\n")
            f.write(f"  registered_at: {e['registered_at']!r}\n")
    else:
        f.write("entries: []\n")
print(f"[pending_approval] registered: {path}")
PY
            ;;
        remove)
            path="${2:-}"
            if [[ -z "$path" ]]; then
                echo "remove: path required" >&2
                exit 1
            fi
            if [[ ! -f "$PA_FILE" ]]; then
                echo "[pending_approval] registry not found: $PA_FILE" >&2
                exit 0
            fi
            PATH_VAL="$path" PA_FILE="$PA_FILE" python3 - <<'PY'
import os, yaml, sys
pa_file = os.environ["PA_FILE"]
with open(pa_file, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {"entries": []}
entries = data.get("entries") or []
path = os.environ["PATH_VAL"]
new_entries = [e for e in entries if e.get("path") != path]
if len(new_entries) == len(entries):
    print(f"[pending_approval] not found (nothing removed): {path}")
    sys.exit(0)
with open(pa_file, "w", encoding="utf-8") as f:
    if new_entries:
        f.write("entries:\n")
        for e in new_entries:
            f.write(f"- path: {e['path']!r}\n")
            f.write(f"  reason: {e['reason']!r}\n")
            f.write(f"  registered_by: {e['registered_by']!r}\n")
            f.write(f"  registered_at: {e['registered_at']!r}\n")
    else:
        f.write("entries: []\n")
print(f"[pending_approval] removed: {path}")
PY
            ;;
        list)
            if [[ ! -f "$PA_FILE" ]]; then
                echo "[pending_approval] no registry file"
                exit 0
            fi
            PA_FILE="$PA_FILE" python3 - <<'PY'
import os, yaml
pa_file = os.environ["PA_FILE"]
with open(pa_file, encoding="utf-8") as f:
    data = yaml.safe_load(f) or {"entries": []}
entries = data.get("entries") or []
if not entries:
    print("[pending_approval] no entries")
else:
    for e in entries:
        print(f"- {e.get('path','?')} | reason={e.get('reason','?')} | by={e.get('registered_by','?')} | at={e.get('registered_at','?')}")
PY
            ;;
        *)
            echo "Unknown command: $cmd. Use add|remove|list" >&2
            exit 1
            ;;
    esac
) 9>"$LOCK_FILE"
