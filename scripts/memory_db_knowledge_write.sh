#!/usr/bin/env bash
# semantic-links: [[SQLite記憶DB]], [[三層記憶システム]]
# memory_db_knowledge_write.sh — Direct Layer1 knowledge insert without mailbox/bulletin side effects.
# Usage: bash scripts/memory_db_knowledge_write.sh "knowledge text" "source" [--db PATH] [--cmd-id CMD_ID]
#        echo "knowledge text" | bash scripts/memory_db_knowledge_write.sh - "source"

set -euo pipefail

usage() {
    cat <<'EOF' >&2
Usage: memory_db_knowledge_write.sh "knowledge text" "source" [--db PATH] [--cmd-id CMD_ID]
       memory_db_knowledge_write.sh - "source" [--db PATH] [--cmd-id CMD_ID]

Writes a knowledge event directly to the local memory DB. This is Layer1 only:
it does not write bulletin, inbox, insight, or any other communication channel.
EOF
}

if [[ $# -lt 2 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
knowledge_text="$1"
source_text="$2"
shift 2

db_path="${SHOGUN_MEMORY_DB:-$SCRIPT_DIR/data/multi_agent_shogun_memory.db}"
cmd_id=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            db_path="$2"
            shift 2
            ;;
        --cmd-id)
            [[ $# -ge 2 ]] || { usage; exit 2; }
            cmd_id="$2"
            shift 2
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [[ "$knowledge_text" == "-" ]]; then
    knowledge_text="$(cat)"
fi

if [[ -z "${knowledge_text//[[:space:]]/}" ]]; then
    echo "ERROR: knowledge text is required" >&2
    exit 1
fi
if [[ -z "${source_text//[[:space:]]/}" ]]; then
    echo "ERROR: source is required" >&2
    exit 1
fi
if [[ ! -f "$db_path" ]]; then
    echo "ERROR: memory DB not found: $db_path" >&2
    exit 1
fi

agent_id="${AGENT_ID:-}"
if [[ -z "$agent_id" && -n "${TMUX_PANE:-}" ]]; then
    agent_id="$(tmux display-message -t "$TMUX_PANE" -p '#{@agent_id}' 2>/dev/null || true)"
fi
agent_id="${agent_id:-memory_db_knowledge_write}"

python3 - "$SCRIPT_DIR" "$db_path" "$knowledge_text" "$source_text" "$cmd_id" "$agent_id" <<'PY'
import hashlib
import sys

repo_root, db_path, knowledge_text, source_text, cmd_id, agent_id = sys.argv[1:7]
sys.path.insert(0, f"{repo_root}/scripts")
import memory_db_live_insert as live_insert

knowledge = live_insert.normalize_text(knowledge_text)
source = live_insert.normalize_text(source_text)
explicit_cmd_id = live_insert.normalize_text(cmd_id)
agent = live_insert.normalize_text(agent_id) or "memory_db_knowledge_write"
ts = live_insert.now_timestamp()
summary = live_insert.summarize(knowledge) or "knowledge"
detail = "\n".join(
    line for line in [
        knowledge,
        f"source: {source}",
    ] if line
)
event_cmd_id = explicit_cmd_id or live_insert.infer_cmd_id(summary, detail)
event_hash = hashlib.sha1(f"{ts}\n{agent}\n{source}\n{knowledge}".encode("utf-8")).hexdigest()[:16]
event_id = f"knowledge:{event_hash}"

live_insert.append_event(
    db_path,
    (
        event_id,
        ts,
        "knowledge",
        agent,
        "",
        "direct_insert",
        summary,
        detail,
        "memory_db_knowledge_write",
        event_cmd_id,
        "[]",
        source,
        None,
        "normal",
    ),
    concept_text_extra=f"{source}\n{event_cmd_id}",
    raw_content=knowledge,
)
print(f"OK: {event_id}")
PY
