#!/usr/bin/env bash
# lord_conversation.sh — lord_conversation.jsonl 原子追記ライブラリ
#
# 提供関数:
#   append_lord_conversation <message> <direction> [agent] [source] [target]
#     - message: 記録本文（必須）
#     - direction: inbound/outbound/prompt/response 等（必須）
#     - agent: 発話主体（任意）
#     - source: 由来チャネル（省略時 "ntfy"）
#
# 必須環境変数:
#   LORD_CONVERSATION — queue/lord_conversation.jsonl
#   LORD_CONVERSATION_LOCK — ロックファイル

append_lord_conversation() {
  local message="${1:?append_lord_conversation: message is required}"
  local direction="${2:?append_lord_conversation: direction is required}"
  local agent="${3:-}"
  local source="${4:-ntfy}"
  local target="${5:-}"
  local lock_wait="${LORD_CONVERSATION_LOCK_WAIT_SEC:-5}"
  local db_path="${LORD_CONVERSATION_DB:-}"
  local semantic_index_path="${SEMANTIC_INDEX_PATH:-}"
  local insight_write_path="${LORD_CONVERSATION_INSIGHT_WRITE:-}"

  case "$direction" in
    ""|*[!a-z_]*)
      echo "ERROR: append_lord_conversation: direction must be lowercase snake_case, got '$direction'" >&2
      return 1
      ;;
  esac

  if [ -z "${LORD_CONVERSATION:-}" ]; then
    echo "ERROR: append_lord_conversation: LORD_CONVERSATION is not set" >&2
    return 1
  fi
  if [ -z "${LORD_CONVERSATION_LOCK:-}" ]; then
    echo "ERROR: append_lord_conversation: LORD_CONVERSATION_LOCK is not set" >&2
    return 1
  fi

  local timestamp legacy_yaml
  timestamp="$(date "+%Y-%m-%dT%H:%M:%S%:z")"
  legacy_yaml="${LORD_CONVERSATION%.jsonl}.yaml"
  if [ -z "$db_path" ]; then
    db_path="$(cd "$(dirname "$LORD_CONVERSATION")/.." 2>/dev/null && pwd)/data/multi_agent_shogun_memory.db"
  fi
  if [ -z "$semantic_index_path" ]; then
    semantic_index_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/docs/semantic-index/index.md"
  fi
  if [ -z "$insight_write_path" ]; then
    insight_write_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/scripts/insight_write.sh"
  fi

  mkdir -p "$(dirname "$LORD_CONVERSATION")"
  [ -f "$LORD_CONVERSATION" ] || : > "$LORD_CONVERSATION"

  if ! (
    flock -w "$lock_wait" 200 || exit 1
    CONV_PATH="$LORD_CONVERSATION" \
    CONV_LEGACY_PATH="$legacy_yaml" \
    CONV_TIMESTAMP="$timestamp" \
    CONV_DIRECTION="$direction" \
    CONV_AGENT="$agent" \
    CONV_SOURCE="$source" \
    CONV_TARGET="$target" \
    CONV_MESSAGE="$message" \
    CONV_DB_PATH="$db_path" \
    CONV_SEMANTIC_INDEX_PATH="$semantic_index_path" \
    CONV_INSIGHT_WRITE_PATH="$insight_write_path" \
    python3 - <<'PY'
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

MAX_ENTRIES = 500
SUMMARY_LIMIT = 140

path = Path(os.environ["CONV_PATH"])
legacy_path = Path(os.environ.get("CONV_LEGACY_PATH", ""))
timestamp = os.environ["CONV_TIMESTAMP"]
direction = os.environ["CONV_DIRECTION"]
agent = os.environ["CONV_AGENT"]
source = os.environ.get("CONV_SOURCE", "ntfy") or "ntfy"
target = os.environ.get("CONV_TARGET", "")
message = os.environ["CONV_MESSAGE"]
db_path = Path(os.environ.get("CONV_DB_PATH", ""))
semantic_index_path = Path(os.environ.get("CONV_SEMANTIC_INDEX_PATH", ""))
insight_write_path = Path(os.environ.get("CONV_INSIGHT_WRITE_PATH", ""))
CMD_RE = re.compile(r"\bcmd_[A-Za-z0-9_]+\b")
SQLITE_BUSY_TIMEOUT_MS = 5000
LESSON_TRIGGER_RE = re.compile(
    r"(指摘|裁定|原則|教訓|学習|改善|許可|承認|禁止|必ず|べき|してよい|してはならない)"
)


def normalize_text(value: object) -> str:
    return str(value).replace("\r\n", "\n").replace("\r", "\n").strip()


def summarize(text: str) -> str:
    one_line = " ".join(text.split())
    if len(one_line) <= SUMMARY_LIMIT:
        return one_line
    return one_line[: SUMMARY_LIMIT - 1] + "…"


def load_jsonl(file_path: Path) -> list[dict]:
    entries: list[dict] = []
    if not file_path.exists():
        return entries
    with file_path.open("r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            try:
                parsed = json.loads(line)
            except json.JSONDecodeError:
                parsed = {
                    "ts": "",
                    "source": "parser",
                    "direction": "invalid",
                    "summary": "JSONL parse error",
                    "detail": line,
                }
            if isinstance(parsed, dict):
                entries.append(parsed)
    return entries


def load_legacy_yaml(file_path: Path) -> list[dict]:
    if not file_path.exists():
        return []
    try:
        import yaml

        with file_path.open("r", encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        return []
    if not isinstance(data, dict):
        return []
    raw_entries = data.get("entries")
    if not isinstance(raw_entries, list):
        return []
    converted: list[dict] = []
    for item in raw_entries:
        if not isinstance(item, dict):
            continue
        legacy_message = normalize_text(item.get("message", ""))
        if not legacy_message:
            continue
        legacy_source = str(item.get("channel", "legacy"))
        legacy_agent = str(item.get("agent", "")).strip()
        entry = {
            "ts": str(item.get("timestamp", "")),
            "source": legacy_source,
            "direction": str(item.get("direction", "legacy")),
            "summary": summarize(legacy_message),
            "detail": legacy_message,
        }
        if legacy_agent:
            entry["agent"] = legacy_agent
        converted.append(entry)
    return converted


def infer_cmd_id(summary: str, detail: str) -> str:
    match = CMD_RE.search(f"{summary}\n{detail}")
    return match.group(0) if match else ""


def infer_target(entry_agent: str, entry_direction: str, entry_target: str) -> str:
    if entry_target:
        return entry_target
    if entry_direction == "inbound":
        return "shogun"
    if entry_direction in {"response", "outbound"}:
        return "lord"
    return ""


def iter_semantic_concepts(index_path: Path) -> list[dict]:
    if not index_path.exists():
        return []

    concepts: list[dict] = []
    current: dict | None = None
    for raw_line in index_path.read_text(encoding="utf-8", errors="replace").splitlines():
        heading = re.match(r"^##\s+([A-Za-z0-9_-]+)\s+—\s+(.+?)\s*$", raw_line)
        if heading:
            if current:
                concepts.append(current)
            current = {
                "id": heading.group(1).strip(),
                "label": heading.group(2).strip(),
                "aliases": [],
            }
            continue
        if current is None:
            continue
        alias_match = re.match(r"^\|\s*aliases\s*\|\s*(.*?)\s*\|$", raw_line)
        if alias_match:
            current["aliases"] = [
                alias.strip()
                for alias in alias_match.group(1).split(",")
                if alias.strip()
            ]
    if current:
        concepts.append(current)
    return concepts


def concept_terms(concept: dict) -> list[str]:
    terms = [concept["id"], concept["label"], *concept.get("aliases", [])]
    return [term for term in terms if len(term) >= 3]


def concept_matches_for_text(text: str, concepts: list[dict]) -> list[tuple[str, float]]:
    haystack = text.casefold()
    matched: list[tuple[str, float]] = []
    for concept in concepts:
        terms = concept_terms(concept)
        matched_terms = sum(1 for term in terms if term.casefold() in haystack)
        if matched_terms:
            matched.append((concept["id"], float(matched_terms)))
    return sorted(matched, key=lambda item: item[0])


def ensure_event_concepts_schema(conn) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS event_concepts (
            event_id TEXT NOT NULL,
            concept_name TEXT NOT NULL,
            relevance_score REAL NOT NULL DEFAULT 1.0,
            PRIMARY KEY (event_id, concept_name),
            FOREIGN KEY (event_id) REFERENCES events(id)
        )
        """
    )
    columns = {
        row[1]
        for row in conn.execute("PRAGMA table_info(event_concepts)")
    }
    if "relevance_score" not in columns:
        conn.execute(
            "ALTER TABLE event_concepts ADD COLUMN relevance_score REAL NOT NULL DEFAULT 1.0"
        )


def append_memory_db_entry(entry: dict, event_index: int) -> None:
    if not db_path or not db_path.exists():
        return

    import hashlib
    import sqlite3

    event_hash = hashlib.sha1(
        json.dumps(
            {
                "ts": entry.get("ts", ""),
                "source": entry.get("source", ""),
                "direction": entry.get("direction", ""),
                "agent": entry.get("agent", ""),
                "target": entry.get("target", ""),
                "detail": entry.get("detail", ""),
                "event_index": event_index,
            },
            ensure_ascii=False,
            sort_keys=True,
        ).encode("utf-8")
    ).hexdigest()[:16]
    session_id = Path(path).stem
    event_id = f"conversation:{session_id}:live:{event_hash}"
    entry_agent = normalize_text(entry.get("agent", ""))
    entry_direction = normalize_text(entry.get("direction", ""))
    entry_summary = normalize_text(entry.get("summary", ""))
    entry_detail = normalize_text(entry.get("detail", ""))
    entry_target = normalize_text(entry.get("target", ""))
    source_file = str(path)
    concept_matches = concept_matches_for_text(
        f"{entry_summary}\n{entry_detail}",
        iter_semantic_concepts(semantic_index_path),
    )
    concept_names_json = json.dumps(
        [concept_name for concept_name, _score in concept_matches],
        ensure_ascii=False,
    )

    with sqlite3.connect(db_path) as conn:
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
        tables = {
            row[0]
            for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type IN ('table', 'view', 'virtual table')"
            )
        }
        if not {"conversations", "events", "events_fts"}.issubset(tables):
            return
        ensure_event_concepts_schema(conn)
        cols = {row[1] for row in conn.execute("PRAGMA table_info(events)")}
        if "raw_content" not in cols:
            conn.execute("ALTER TABLE events ADD COLUMN raw_content TEXT")
        cursor = conn.execute(
            """
            INSERT OR IGNORE INTO events (
                id, ts, event_type, agent, target, direction, summary, detail,
                session_id, cmd_id, concepts, source_file, parent_event_id, importance,
                raw_content
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                event_id,
                normalize_text(entry.get("ts", "")),
                "conversation",
                entry_agent,
                infer_target(entry_agent, entry_direction, entry_target),
                entry_direction,
                entry_summary,
                entry_detail,
                session_id,
                infer_cmd_id(entry_summary, entry_detail),
                concept_names_json,
                source_file,
                None,
                "normal",
                entry_detail,
            ),
        )
        if cursor.rowcount == 1:
            rowid = conn.execute(
                "SELECT rowid FROM events WHERE id = ?",
                (event_id,),
            ).fetchone()[0]
            conn.execute(
                "INSERT INTO events_fts(rowid, summary, detail) VALUES (?, ?, ?)",
                (rowid, entry_summary, entry_detail),
            )
            conn.executemany(
                """
                INSERT OR REPLACE INTO event_concepts (event_id, concept_name, relevance_score)
                VALUES (?, ?, ?)
                """,
                [
                    (event_id, concept_name, relevance_score)
                    for concept_name, relevance_score in concept_matches
                ],
            )
            obsidian_links = set(
                m.group(1).strip()
                for m in re.finditer(r"\[\[([^\[\]]+)\]\]", f"{entry_summary}\n{entry_detail}")
                if m.group(1).strip()
            )
            if obsidian_links and "event_links" in tables:
                conn.executemany(
                    "INSERT OR IGNORE INTO event_links (source_event_id, target_concept, link_type) VALUES (?, ?, ?)",
                    [(event_id, target, "obsidian") for target in obsidian_links],
                )


def should_queue_lesson_candidate(entry: dict) -> bool:
    if normalize_text(entry.get("direction", "")) != "inbound":
        return False
    detail = normalize_text(entry.get("detail", ""))
    if not detail:
        return False
    # Agent tool task-notificationは殿の発言ではない(cmd_3267と同根: gate_shogun_startup.shの
    # 殿生発言Q生成でも同判定を採用済み)。誤帰属によるlord_conversation教訓候補FPを防ぐ。
    if detail.lstrip().startswith("<task-notification>"):
        return False
    return LESSON_TRIGGER_RE.search(detail) is not None


def queue_lesson_candidate(entry: dict) -> None:
    if not should_queue_lesson_candidate(entry):
        return
    if not insight_write_path.exists():
        return

    detail = normalize_text(entry.get("detail", ""))
    target = normalize_text(entry.get("target", ""))
    source_name = "lord_conversation:lesson_candidate"
    message = (
        f"lord_conversation教訓候補: target={target or 'unknown'} "
        f"trigger=inbound_lord detail={detail}"
    )
    result = subprocess.run(
        ["bash", str(insight_write_path), message, "medium", source_name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=False,
    )
    if result.returncode != 0:
        err = (result.stderr or "").strip()
        print(
            f"WARN: append_lord_conversation: lesson candidate insight skipped: {err}",
            file=os.sys.stderr,
        )


entries = load_jsonl(path)
if not entries and str(path).endswith(".jsonl"):
    entries = load_legacy_yaml(legacy_path)

normalized_message = normalize_text(message)
if not normalized_message:
    raise SystemExit(0)

entry = {
    "ts": timestamp,
    "source": source,
    "direction": direction,
    "summary": summarize(normalized_message),
    "detail": normalized_message,
}
if agent:
    entry["agent"] = agent
if target:
    entry["target"] = target

entries.append(entry)
if len(entries) > MAX_ENTRIES:
    entries = entries[-MAX_ENTRIES:]

tmp_fd, tmp_path = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
try:
    with os.fdopen(tmp_fd, "w", encoding="utf-8", errors="replace") as f:
        for row in entries:
            f.write(json.dumps(row, ensure_ascii=False))
            f.write("\n")
    os.replace(tmp_path, path)
except Exception:
    os.unlink(tmp_path)
    raise

try:
    append_memory_db_entry(entry, len(entries))
except Exception as exc:
    print(f"WARN: append_lord_conversation: DB INSERT skipped: {exc}", file=os.sys.stderr)

try:
    queue_lesson_candidate(entry)
except Exception as exc:
    print(f"WARN: append_lord_conversation: lesson candidate insight skipped: {exc}", file=os.sys.stderr)
PY
  ) 200>"$LORD_CONVERSATION_LOCK"; then
    return 1
  fi
}
