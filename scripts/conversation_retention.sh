#!/usr/bin/env bash
# conversation_retention.sh — lord_conversation.jsonl の24h保持 + 索引更新
set -eu

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
JSONL_PATH="${1:-$PROJECT_DIR/queue/lord_conversation.jsonl}"
INDEX_PATH="${2:-$PROJECT_DIR/context/lord-conversation-index.md}"
ARCHIVE_DIR="${3:-$PROJECT_DIR/logs/lord_conversation_archive}"
LOCK_PATH="${JSONL_PATH}.lock"

mkdir -p "$(dirname "$JSONL_PATH")" "$(dirname "$INDEX_PATH")" "$ARCHIVE_DIR"
[ -f "$JSONL_PATH" ] || : > "$JSONL_PATH"

(
  flock -w 10 200 || {
    echo "[conversation_retention] ERROR: flock timeout on $LOCK_PATH" >&2
    exit 1
  }

  CONV_JSONL="$JSONL_PATH" CONV_INDEX="$INDEX_PATH" CONV_ARCHIVE_DIR="$ARCHIVE_DIR" \
    python3 - <<'PY'
import json
import os
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

MAX_ENTRIES = 200
WINDOW_HOURS = 24

jsonl_path = Path(os.environ["CONV_JSONL"])
index_path = Path(os.environ["CONV_INDEX"])
archive_dir = Path(os.environ["CONV_ARCHIVE_DIR"])
now_utc = datetime.now(timezone.utc)
cutoff_utc = now_utc - timedelta(hours=WINDOW_HOURS)


def parse_ts(ts: Any) -> datetime | None:
    if not isinstance(ts, str):
        return None
    text = ts.strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = f"{text[:-1]}+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def normalize_entry(entry: Any) -> dict[str, Any]:
    if not isinstance(entry, dict):
        return {}
    out = dict(entry)
    out.setdefault("ts", "")
    out.setdefault("source", "")
    out.setdefault("direction", "")
    out.setdefault("summary", "")
    out.setdefault("detail", "")
    return out


def clip(text: Any, limit: int) -> str:
    if text is None:
        return ""
    normalized = str(text).replace("\n", " ").strip()
    if len(normalized) <= limit:
        return normalized
    return normalized[: limit - 1] + "…"


def display_ts(entry: dict[str, Any]) -> str:
    dt = parse_ts(entry.get("ts"))
    if dt is None:
        return "時刻不明"
    return dt.astimezone().isoformat(timespec="seconds")


def entry_sort_key(entry: dict[str, Any]) -> datetime:
    dt = parse_ts(entry.get("ts"))
    if dt is None:
        return datetime.min.replace(tzinfo=timezone.utc)
    return dt


def render_recent(entries: list[dict[str, Any]]) -> str:
    if not entries:
        return "- 該当なし"
    lines: list[str] = []
    for entry in sorted(entries, key=entry_sort_key, reverse=True)[:10]:
        summary = clip(entry.get("summary") or entry.get("detail"), 120) or "(要約なし)"
        source = clip(entry.get("source"), 24) or "unknown"
        direction = clip(entry.get("direction"), 24) or "unknown"
        lines.append(f"- {display_ts(entry)} | {source} | {direction} | {summary}")
    return "\n".join(lines)


def render_unresolved(entries: list[dict[str, Any]]) -> str:
    patterns = ("?", "確認", "未解決", "要確認", "TODO", "保留")
    found: list[str] = []
    for entry in sorted(entries, key=entry_sort_key, reverse=True):
        text = f"{entry.get('summary', '')}\n{entry.get('detail', '')}"
        if any(token in text for token in patterns):
            line = clip(entry.get("summary") or entry.get("detail"), 140)
            if line and line not in found:
                found.append(line)
        if len(found) >= 8:
            break
    if not found:
        return "- 該当なし"
    return "\n".join(f"- {line}" for line in found)


def render_lord_decisions(entries: list[dict[str, Any]]) -> str:
    keywords = ("指示", "裁定", "決裁", "決定", "方針", "承認", "却下")
    lines: list[str] = []
    for entry in sorted(entries, key=entry_sort_key, reverse=True):
        source = str(entry.get("source", "")).lower()
        text = f"{entry.get('summary', '')}\n{entry.get('detail', '')}"
        if "lord" in source or any(token in text for token in keywords):
            line = clip(entry.get("summary") or entry.get("detail"), 150)
            if not line:
                continue
            lines.append(f"- {display_ts(entry)} | {line}")
        if len(lines) >= 8:
            break
    if not lines:
        return "- 該当なし"
    return "\n".join(lines)


def render_cmd_refs(entries: list[dict[str, Any]]) -> str:
    refs: set[str] = set()
    for entry in entries:
        text = f"{entry.get('summary', '')}\n{entry.get('detail', '')}"
        refs.update(re.findall(r"\b(?:cmd_\d+|PD-\d+)\b", text))
    if not refs:
        return "- 該当なし"
    ordered = sorted(refs, key=lambda x: (0, int(x.split("_")[1])) if x.startswith("cmd_") else (1, int(x.split("-")[1])))
    return "\n".join(f"- {ref}" for ref in ordered[:30])


def load_entries(path: Path) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    if not path.exists():
        return entries
    with path.open("r", encoding="utf-8") as f:
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
            entries.append(normalize_entry(parsed))
    return entries


entries = load_entries(jsonl_path)
recent_entries: list[dict[str, Any]] = []
expired_entries: list[dict[str, Any]] = []

for entry in entries:
    ts = parse_ts(entry.get("ts"))
    if ts is None:
        # 時刻不明は削除せず保持する（誤削除防止）
        recent_entries.append(entry)
        continue
    if ts < cutoff_utc:
        expired_entries.append(entry)
    else:
        recent_entries.append(entry)

overflow_entries: list[dict[str, Any]] = []
if len(recent_entries) > MAX_ENTRIES:
    overflow_entries = recent_entries[:-MAX_ENTRIES]
    recent_entries = recent_entries[-MAX_ENTRIES:]

archived_entries = expired_entries + overflow_entries

archive_file = archive_dir / f"{now_utc.astimezone().date().isoformat()}.jsonl"
if archived_entries:
    archive_dir.mkdir(parents=True, exist_ok=True)
    with archive_file.open("a", encoding="utf-8", errors="replace") as f:
        for entry in archived_entries:
            f.write(json.dumps(entry, ensure_ascii=False))
            f.write("\n")

with jsonl_path.open("w", encoding="utf-8", errors="replace") as f:
    for entry in recent_entries:
        f.write(json.dumps(entry, ensure_ascii=False))
        f.write("\n")

index_body = f"""# Lord Conversation Index
<!-- last_updated: {now_utc.astimezone().date().isoformat()} auto-generated -->
<!-- generated_by: scripts/conversation_retention.sh -->
<!-- generated_at: {now_utc.astimezone().isoformat(timespec="seconds")} -->

## 最新やり取り（直近24h）
{render_recent(recent_entries)}

## 未解決確認事項
{render_unresolved(recent_entries)}

## 殿の直近裁定・方針（直近24h）
{render_lord_decisions(recent_entries)}

## 参照cmd
{render_cmd_refs(recent_entries)}

## 参照先
- `queue/lord_conversation.jsonl`（一次データ）
- `logs/lord_conversation_archive/*.jsonl`（24h超過・200件超過の退避先）
"""

index_path.write_text(index_body, encoding="utf-8", errors="replace")

print(
    f"[conversation_retention] total={len(entries)} kept={len(recent_entries)} "
    f"archived={len(archived_entries)} archive_file={archive_file}"
)
PY
) 200>"$LOCK_PATH"
