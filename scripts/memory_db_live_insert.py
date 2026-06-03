#!/usr/bin/env python3
# semantic-links: [[SQLite記憶DB]], [[eventsテーブル]], [[掲示板通信基盤]], [[セマンティック辞書構想]]
"""Append live inbox/bulletin/insight events to the local memory DB."""

import os
import sys
import json
import glob
import re
import tempfile
import shutil


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DB_PATH = os.path.join(REPO_ROOT, "data", "multi_agent_shogun_memory.db")
DEFAULT_CACHE_DIR = os.path.join(tempfile.gettempdir(), "shogun_memory_db_cache")
DEFAULT_SEMANTIC_MAP_PATH = os.path.join(REPO_ROOT, "context", "semantic-map.md")
DEFAULT_SEMANTIC_INDEX_PATH = os.path.join(REPO_ROOT, "docs", "semantic-index", "index.md")
SUMMARY_LIMIT = 240
SQLITE_BUSY_TIMEOUT_MS = 5000
DEFAULT_CONFIDENCE = "medium"
DEFAULT_FRESHNESS = "current"
DEFAULT_SOURCE_TYPE = "fact"
_SEMANTIC_CONCEPT_CACHE = None
_CMD_CONTEXT_CACHE: dict[str, str] = {}
OBSIDIAN_LINK_RE = re.compile(r"\[\[([^\[\]]+)\]\]")
OBSIDIAN_LINK_NOISE_TARGETS = {
    "リンク",
    "概念名",
    "ファイル名",
    "発端",
    "原因",
    "結果",
    "対象事象",
    "レビュー結果",
}
REPORT_METADATA_DOT_KEYS = {
    "ac_version_read",
    "files_modified",
    "hook_failures",
    "parent_cmd",
    "status",
    "status_detail",
    "task_id",
    "timestamp",
    "verdict",
    "worker_id",
}
REPORT_METADATA_PREFIXES = (
    "binary_checks.",
    "hook_failures.",
    "lessons_useful.",
    "self_gate_check.",
    "skill_candidate.",
    "task_clarity.",
    "test_triage.",
)
REPORT_MEANINGFUL_DOT_KEYS = {
    "assumption_check",
    "simplicity_check",
}
REPORT_MEANINGFUL_PREFIXES = (
    "assumption_invalidation.",
    "decision_candidate.",
    "knowledge_candidate.",
    "lesson_candidate.",
    "purpose_validation.",
    "result.",
)


def memory_db_cache_path(db_path: str) -> str:
    override = os.environ.get("SHOGUN_MEMORY_DB_CACHE_PATH", "").strip()
    if override:
        return override
    cache_dir = os.environ.get("SHOGUN_MEMORY_DB_CACHE_DIR", DEFAULT_CACHE_DIR)
    repo_key = re.sub(r"[^A-Za-z0-9_.-]", "_", REPO_ROOT)
    return os.path.join(cache_dir, f"{repo_key}_{os.path.basename(db_path)}")


def sync_memory_db_ext4_cache(db_path: str) -> None:
    if os.environ.get("SHOGUN_DISABLE_MEMORY_DB_CACHE", "0") == "1":
        return
    if not os.path.exists(db_path):
        return

    import fcntl

    cache_path = memory_db_cache_path(db_path)
    cache_dir = os.path.dirname(cache_path)
    os.makedirs(cache_dir, exist_ok=True)
    lock_path = f"{cache_path}.lock"
    tmp_path = ""
    with open(lock_path, "w", encoding="utf-8") as lock_handle:
        fcntl.flock(lock_handle, fcntl.LOCK_EX)
        fd, tmp_path = tempfile.mkstemp(
            prefix=f".{os.path.basename(cache_path)}.",
            suffix=".tmp",
            dir=cache_dir,
        )
        os.close(fd)
        try:
            shutil.copyfile(db_path, tmp_path)
            for suffix in ("-wal", "-shm"):
                source_sidecar = f"{db_path}{suffix}"
                tmp_sidecar = f"{tmp_path}{suffix}"
                cache_sidecar = f"{cache_path}{suffix}"
                if os.path.exists(source_sidecar):
                    shutil.copyfile(source_sidecar, tmp_sidecar)
                elif os.path.exists(cache_sidecar):
                    os.unlink(cache_sidecar)
            os.replace(tmp_path, cache_path)
            for suffix in ("-wal", "-shm"):
                tmp_sidecar = f"{tmp_path}{suffix}"
                if os.path.exists(tmp_sidecar):
                    os.replace(tmp_sidecar, f"{cache_path}{suffix}")
            tmp_path = ""
        finally:
            if tmp_path and os.path.exists(tmp_path):
                os.unlink(tmp_path)
            for suffix in ("-wal", "-shm"):
                tmp_sidecar = f"{tmp_path}{suffix}" if tmp_path else ""
                if tmp_sidecar and os.path.exists(tmp_sidecar):
                    os.unlink(tmp_sidecar)


def normalize_text(value: object) -> str:
    if value is None:
        return ""
    return str(value).replace("\r\n", "\n").replace("\r", "\n").strip()


def summarize(text: str) -> str:
    first_line = next((line.strip() for line in text.splitlines() if line.strip()), "")
    if not first_line:
        return ""
    return first_line[:SUMMARY_LIMIT]


def infer_cmd_id(summary: str, detail: str) -> str:
    text = f"{summary}\n{detail}"
    start = text.find("cmd_")
    while start != -1:
        end = start + 4
        while end < len(text) and (text[end].isalnum() or text[end] == "_"):
            end += 1
        if end > start + 4:
            return text[start:end]
        start = text.find("cmd_", start + 4)
    return ""


def _yaml_scalar_value(raw_value: str) -> str:
    value = normalize_text(raw_value)
    if len(value) >= 2:
        if value[0] == value[-1] == '"':
            return value[1:-1].replace('\\"', '"')
        if value[0] == value[-1] == "'":
            return value[1:-1].replace("''", "'")
    return value


def _line_indent(line: str) -> int:
    return len(line) - len(line.lstrip(" "))


def _extract_scalar_in_block(lines: list[str], start_index: int, base_indent: int, key: str) -> str:
    prefix = f"{key}:"
    for line in lines[start_index + 1:]:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = _line_indent(line)
        stripped = line.strip()
        if base_indent >= 0 and indent <= base_indent:
            break
        if stripped.startswith(prefix):
            return _yaml_scalar_value(stripped[len(prefix):])
    return ""


def _extract_cmd_context_from_text(text: str, cmd_id: str) -> str:
    lines = text.splitlines()
    candidates: list[tuple[int, int]] = []
    for index, line in enumerate(lines):
        stripped = line.strip()
        indent = _line_indent(line)
        if stripped == f"{cmd_id}:":
            candidates.append((index, indent))
            continue
        if stripped.startswith("- id:") and _yaml_scalar_value(stripped[len("- id:"):]) == cmd_id:
            candidates.append((index, indent))
            continue
        if stripped.startswith("id:") and _yaml_scalar_value(stripped[len("id:"):]) == cmd_id:
            candidates.append((index, -1))

    for index, indent in candidates:
        title = _extract_scalar_in_block(lines, index, indent, "title")
        purpose = _extract_scalar_in_block(lines, index, indent, "purpose")
        if title or purpose:
            return "\n".join(
                line for line in [
                    f"cmd_id: {cmd_id}",
                    f"cmd_title: {title}" if title else "",
                    f"cmd_purpose: {purpose}" if purpose else "",
                ]
                if line
            )
    return ""


def _extract_task_context_from_text(text: str, cmd_id: str) -> str:
    lines = text.splitlines()
    candidates: list[tuple[int, int]] = []
    for index, line in enumerate(lines):
        stripped = line.strip()
        indent = _line_indent(line)
        for key in ("task_id", "parent_cmd"):
            prefix = f"{key}:"
            if stripped.startswith(prefix) and _yaml_scalar_value(stripped[len(prefix):]) == cmd_id:
                candidates.append((index, max(indent - 2, -1)))

    for index, indent in candidates:
        title = _extract_scalar_in_block(lines, index, indent, "title")
        purpose = _extract_scalar_in_block(lines, index, indent, "purpose")
        command = _extract_scalar_in_block(lines, index, indent, "command")
        result_summary = _extract_scalar_in_block(lines, index, indent, "result_summary")
        if title or purpose or command or result_summary:
            return "\n".join(
                line for line in [
                    f"cmd_id: {cmd_id}",
                    f"cmd_title: {title}" if title else "",
                    f"cmd_purpose: {purpose}" if purpose else "",
                    f"cmd_command: {command}" if command else "",
                    f"cmd_result_summary: {result_summary}" if result_summary else "",
                ]
                if line
            )
    return ""


def command_context_text(cmd_id: str) -> str:
    cmd_id = normalize_text(cmd_id)
    if not cmd_id:
        return ""
    if cmd_id in _CMD_CONTEXT_CACHE:
        return _CMD_CONTEXT_CACHE[cmd_id]

    source_paths = [
        os.path.join(REPO_ROOT, "queue", "shogun_to_karo.yaml"),
        os.path.join(REPO_ROOT, "queue", "archive", "shogun_to_karo_done.yaml"),
    ]
    source_paths.extend(glob.glob(os.path.join(REPO_ROOT, "queue", "archive", "cmds", f"{cmd_id}*.yaml")))

    for path in source_paths:
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            context = _extract_cmd_context_from_text(handle.read(), cmd_id)
        if context:
            _CMD_CONTEXT_CACHE[cmd_id] = context
            return context

    for path in glob.glob(os.path.join(REPO_ROOT, "queue", "tasks", "*.yaml")):
        with open(path, encoding="utf-8", errors="replace") as handle:
            context = _extract_task_context_from_text(handle.read(), cmd_id)
        if context:
            _CMD_CONTEXT_CACHE[cmd_id] = context
            return context

    _CMD_CONTEXT_CACHE[cmd_id] = ""
    return ""


def _split_markdown_row(line: str) -> list[str]:
    stripped = line.strip()
    if not stripped.startswith("|") or not stripped.endswith("|"):
        return []
    return [cell.strip() for cell in stripped.strip("|").split("|")]


def _semantic_index_label_to_id(index_path: str) -> dict[str, str]:
    if not os.path.exists(index_path):
        return {}
    mapping: dict[str, str] = {}
    concept_id = ""
    with open(index_path, encoding="utf-8", errors="replace") as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\n")
            if line.startswith("## ") and " — " in line:
                heading = line[3:].strip()
                concept_id, label = heading.split(" — ", 1)
                mapping[normalize_text(label)] = normalize_text(concept_id)
                continue
            cells = _split_markdown_row(line)
            if len(cells) >= 2 and cells[0] == "id":
                concept_id = normalize_text(cells[1])
                if concept_id:
                    mapping[concept_id] = concept_id
            elif len(cells) >= 2 and cells[0] == "label":
                label = normalize_text(cells[1])
                if label and concept_id:
                    mapping[label] = concept_id
    return mapping


def load_semantic_map_concept_cache(
    semantic_map_path: str = DEFAULT_SEMANTIC_MAP_PATH,
    semantic_index_path: str = DEFAULT_SEMANTIC_INDEX_PATH,
) -> list[dict[str, object]]:
    """Load concept aliases from index.md (SSOT) for live inserts.

    Bug 4 fix: Previously read semantic-map.md (generated), causing alias divergence
    with batch import (which reads index.md). Now both use the same source.
    semantic-map.md is kept as fallback only if index.md is unavailable.
    """
    import re as _re

    # Primary: index.md (SSOT, same as batch import memory_db_import.py)
    if os.path.exists(semantic_index_path):
        concepts: list[dict[str, object]] = []
        current_id = ""
        current_label = ""
        current_aliases: list[str] = []
        for raw_line in open(semantic_index_path, encoding="utf-8", errors="replace"):
            heading = _re.match(r"^##\s+([A-Za-z0-9_-]+)\s+—\s+(.+?)\s*$", raw_line)
            if heading:
                if current_id:
                    terms = [current_id, current_label, *current_aliases]
                    concepts.append({
                        "id": current_id,
                        "terms": [t for t in terms if len(t) >= 3],
                    })
                current_id = heading.group(1).strip()
                current_label = heading.group(2).strip()
                current_aliases = []
                continue
            alias_match = _re.match(r"^\|\s*aliases\s*\|\s*(.*?)\s*\|$", raw_line)
            if alias_match and current_id:
                current_aliases = [
                    normalize_text(a) for a in alias_match.group(1).split(",")
                    if normalize_text(a) and len(normalize_text(a)) >= 3
                ]
        if current_id:
            terms = [current_id, current_label, *current_aliases]
            concepts.append({
                "id": current_id,
                "terms": [t for t in terms if len(t) >= 3],
            })
        return concepts

    # Fallback: semantic-map.md (generated) — only if index.md unavailable
    label_to_id = _semantic_index_label_to_id(semantic_index_path)
    if not os.path.exists(semantic_map_path):
        return []

    concepts = []
    with open(semantic_map_path, encoding="utf-8", errors="replace") as handle:
        for raw_line in handle:
            cells = _split_markdown_row(raw_line)
            if len(cells) < 2:
                continue
            label = normalize_text(cells[0])
            if not label or label in {"概念", "------"} or set(label) <= {"-"}:
                continue
            concept_id = label_to_id.get(label, label)
            aliases = [normalize_text(part) for part in cells[1].split(",") if normalize_text(part)]
            terms_list = [concept_id, label, *aliases]
            concepts.append({
                "id": concept_id,
                "terms": [term for term in terms_list if len(term) >= 3],
            })
    return concepts


def semantic_concept_cache() -> list[dict[str, object]]:
    global _SEMANTIC_CONCEPT_CACHE
    if _SEMANTIC_CONCEPT_CACHE is None:
        _SEMANTIC_CONCEPT_CACHE = load_semantic_map_concept_cache()
    return _SEMANTIC_CONCEPT_CACHE


def _concept_term_matches(term: object, haystack: str) -> bool:
    needle = normalize_text(term).casefold()
    if not needle:
        return False
    if len(needle) <= 3:
        return re.fullmatch(rf"\b{re.escape(needle)}\b", haystack) is not None
    return needle in haystack


def concepts_for_text(text: str, concepts: list[dict[str, object]] | None = None) -> str:
    haystack = normalize_text(text).casefold()
    matched: list[str] = []
    for concept in semantic_concept_cache() if concepts is None else concepts:
        terms = concept.get("terms", [])
        if any(_concept_term_matches(term, haystack) for term in terms):
            matched.append(str(concept["id"]))
    return json.dumps(sorted(set(matched)), ensure_ascii=False)


def event_concept_rows(event_id: object, concepts_json: str) -> list[tuple[str, str]]:
    try:
        concepts = json.loads(concepts_json)
    except json.JSONDecodeError:
        return []
    if not isinstance(concepts, list):
        return []
    return [(str(event_id), str(concept)) for concept in concepts if str(concept).strip()]


def event_link_rows(event_id: object, text: str) -> list[tuple[str, str, str]]:
    rows: list[tuple[str, str, str]] = []
    seen: set[tuple[str, str, str]] = set()
    for match in OBSIDIAN_LINK_RE.finditer(normalize_text(text)):
        concept = match.group(1).strip()
        if not concept or concept in OBSIDIAN_LINK_NOISE_TARGETS:
            continue
        key = (str(event_id), concept, "obsidian")
        if key in seen:
            continue
        seen.add(key)
        rows.append(key)
    return rows


def require_live_tables(conn) -> bool:
    for table_name in ("events", "events_fts"):
        if conn.execute(
            "SELECT 1 FROM sqlite_master WHERE name = ? AND type IN ('table', 'virtual table') LIMIT 1",
            (table_name,),
        ).fetchone() is None:
            return False
    return True


def ensure_event_attribute_columns(conn) -> None:
    cols = [row[1] for row in conn.execute("PRAGMA table_info(events)")]
    if "confidence" not in cols:
        conn.execute(f"ALTER TABLE events ADD COLUMN confidence TEXT DEFAULT '{DEFAULT_CONFIDENCE}'")
    if "freshness" not in cols:
        conn.execute(f"ALTER TABLE events ADD COLUMN freshness TEXT DEFAULT '{DEFAULT_FRESHNESS}'")
    if "source_type" not in cols:
        conn.execute(f"ALTER TABLE events ADD COLUMN source_type TEXT DEFAULT '{DEFAULT_SOURCE_TYPE}'")
    if "state" not in cols:
        conn.execute("ALTER TABLE events ADD COLUMN state TEXT DEFAULT 'raw'")
    if "raw_content" not in cols:
        conn.execute("ALTER TABLE events ADD COLUMN raw_content TEXT")


def append_event(
    db_path: str,
    row: tuple[object, ...],
    concept_text_extra: str | None = "",
    raw_content: object | None = None,
) -> None:
    if not os.path.exists(db_path):
        return
    import sqlite3

    mutable_row = list(row)
    link_text_extra = "" if concept_text_extra is None else concept_text_extra
    link_text = f"{mutable_row[6]}\n{mutable_row[7]}\n{link_text_extra}"
    if concept_text_extra is not None:
        concept_text = f"{mutable_row[6]}\n{mutable_row[7]}\n{concept_text_extra}"
        mutable_row[10] = concepts_for_text(concept_text)
    row = tuple(mutable_row)
    raw_content_value = normalize_text(raw_content if raw_content is not None else row[7])

    with sqlite3.connect(db_path) as conn:
        conn.execute(f"PRAGMA busy_timeout={SQLITE_BUSY_TIMEOUT_MS}")
        if not require_live_tables(conn):
            return
        ensure_event_attribute_columns(conn)
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS event_concepts (
                event_id TEXT NOT NULL,
                concept_name TEXT NOT NULL,
                PRIMARY KEY (event_id, concept_name),
                FOREIGN KEY (event_id) REFERENCES events(id)
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS event_links (
                source_event_id TEXT NOT NULL,
                target_concept TEXT NOT NULL,
                link_type TEXT NOT NULL DEFAULT 'obsidian',
                PRIMARY KEY (source_event_id, target_concept, link_type),
                FOREIGN KEY (source_event_id) REFERENCES events(id)
            )
            """
        )
        cursor = conn.execute(
            """
            INSERT OR IGNORE INTO events (
                id, ts, event_type, agent, target, direction, summary, detail,
                session_id, cmd_id, concepts, source_file, parent_event_id, importance,
                confidence, freshness, source_type, state, raw_content
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'medium', 'current', 'fact', 'raw', ?)
            """,
            row + (raw_content_value,),
        )
        if cursor.rowcount == 1:
            rowid = conn.execute("SELECT rowid FROM events WHERE id = ?", (row[0],)).fetchone()[0]
            conn.execute(
                "INSERT INTO events_fts(rowid, summary, detail) VALUES (?, ?, ?)",
                (rowid, row[6], row[7]),
            )
            conn.executemany(
                "INSERT OR IGNORE INTO event_concepts (event_id, concept_name) VALUES (?, ?)",
                event_concept_rows(row[0], str(row[10])),
            )
            conn.executemany(
                "INSERT OR IGNORE INTO event_links (source_event_id, target_concept, link_type) VALUES (?, ?, ?)",
                event_link_rows(row[0], link_text),
            )
            conn.execute("CREATE INDEX IF NOT EXISTS idx_event_links_source_event_id ON event_links(source_event_id)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_event_links_target_concept ON event_links(target_concept)")


def append_bulletin(args) -> None:
    content = normalize_text(args.content)
    action_type = normalize_text(args.action_type) or "info"
    status = normalize_text(args.status) or "open"
    requires_confirmation = normalize_text(args.requires_confirmation)
    actioned_by = normalize_text(args.actioned_by)
    summary = summarize(content) or "bulletin"
    detail = "\n".join(
        line
        for line in [
            content,
            f"action_type: {action_type}" if action_type else "",
            f"status: {status}" if status else "",
            f"actioned_by: {actioned_by}" if actioned_by else "",
            f"requires_confirmation: {requires_confirmation}",
        ]
        if line
    )
    importance = "high" if action_type == "action_required" and status != "closed" else "normal"
    append_event(
        args.db_path,
        (
            f"bulletin:{normalize_text(args.entry_id)}",
            normalize_text(args.ts),
            "bulletin",
            normalize_text(args.agent),
            actioned_by,
            action_type,
            summary,
            detail,
            "",
            infer_cmd_id(summary, detail),
            "[]",
            normalize_text(args.source_file),
            None,
            importance,
        ),
        raw_content=content,
    )


def append_insight(args) -> None:
    insight = normalize_text(args.insight)
    status = normalize_text(args.status) or "pending"
    priority = normalize_text(args.priority) or "medium"
    source = normalize_text(args.source) or "manual"
    resolved_at = normalize_text(args.resolved_at)
    summary = summarize(insight) or "insight"
    detail = "\n".join(
        line
        for line in [
            insight,
            f"status: {status}" if status else "",
            f"priority: {priority}" if priority else "",
            f"source: {source}" if source else "",
            f"resolved_at: {resolved_at}" if resolved_at else "",
        ]
        if line
    )
    importance = "high" if priority == "high" or status == "pending" else "normal"
    append_event(
        args.db_path,
        (
            f"insight:{normalize_text(args.entry_id)}",
            normalize_text(args.ts),
            "insight",
            source,
            "",
            status,
            summary,
            detail,
            "",
            infer_cmd_id(summary, detail),
            "[]",
            normalize_text(args.source_file),
            None,
            importance,
        ),
        raw_content=insight,
    )


def append_inbox(args) -> None:
    content = normalize_text(args.content)
    message_type = normalize_text(args.message_type) or "wake_up"
    action = normalize_text(args.action)
    from_agent = normalize_text(args.from_agent) or "unknown"
    target_agent = normalize_text(args.target_agent)
    summary = summarize(content) or "inbox"
    detail = "\n".join(
        line
        for line in [
            content,
            f"type: {message_type}" if message_type else "",
            f"action: {action}" if action else "",
            f"from: {from_agent}" if from_agent else "",
            f"target: {target_agent}" if target_agent else "",
        ]
        if line
    )
    importance = "high" if message_type in {"cmd_new", "task_assigned", "report_received", "task_done"} else "normal"
    cmd_id = infer_cmd_id(summary, detail)
    append_event(
        args.db_path,
        (
            f"inbox:{normalize_text(args.message_id)}",
            normalize_text(args.ts),
            "inbox",
            from_agent,
            target_agent,
            message_type,
            summary,
            detail,
            "",
            cmd_id,
            "[]",
            normalize_text(args.source_file),
            None,
            importance,
        ),
        concept_text_extra=command_context_text(cmd_id),
        raw_content=content,
    )


def append_cmd_save(args) -> None:
    cmd_id = normalize_text(args.cmd_id)
    summary = normalize_text(args.summary) or f"{cmd_id} saved"
    detail = normalize_text(args.detail) or summary
    append_event(
        args.db_path,
        (
            f"cmd_save:{cmd_id}:{normalize_text(args.ts)}",
            normalize_text(args.ts),
            "cmd_save",
            "shogun",
            "",
            "save",
            summary,
            detail,
            "",
            cmd_id,
            "[]",
            normalize_text(args.source_file),
            None,
            "high",
        ),
        concept_text_extra=command_context_text(cmd_id),
        raw_content=detail,
    )


def append_cmd_quality(args) -> None:
    cmd_id = normalize_text(args.cmd_id)
    gate_result = normalize_text(args.gate_result)
    source = normalize_text(args.source) or "cmd_quality_log"
    ts = normalize_text(args.ts)
    notes = normalize_text(args.notes)
    diagnosis = normalize_text(args.diagnosis)
    project = normalize_text(args.project)
    summary = f"{cmd_id} quality: {gate_result}" if cmd_id else f"quality: {gate_result}"
    detail = "\n".join(
        line
        for line in [
            f"gate_result: {gate_result}" if gate_result else "",
            f"karo_rework: {normalize_text(args.karo_rework)}",
            f"gunshi_verdict: {normalize_text(args.gunshi_verdict)}",
            f"ninja_blockers: {normalize_text(args.ninja_blockers)}",
            f"ac_count: {normalize_text(args.ac_count)}",
            f"supplementary_cmds: {normalize_text(args.supplementary_cmds)}",
            f"project: {project}" if project else "",
            f"source: {source}" if source else "",
            f"diagnosis: {diagnosis}" if diagnosis else "",
            f"notes: {notes}" if notes else "",
        ]
        if line
    )
    importance = "high" if gate_result in ("FAIL", "BLOCK") else "normal"
    append_event(
        args.db_path,
        (
            f"cmd_quality:{cmd_id}:{gate_result}:{source}:{ts}",
            ts,
            "cmd_quality",
            "shogun",
            cmd_id,
            gate_result,
            summary[:SUMMARY_LIMIT],
            detail,
            "",
            cmd_id,
            "[]",
            normalize_text(args.source_file),
            None,
            importance,
        ),
        raw_content=detail,
    )


def append_cmd_delegate(args) -> None:
    cmd_id = normalize_text(args.cmd_id)
    message = normalize_text(args.message)
    delegated_at = normalize_text(args.delegated_at)
    summary = normalize_text(args.summary) or summarize(message) or f"{cmd_id} delegated"
    detail = "\n".join(
        line
        for line in [
            message,
            f"delegated_at: {delegated_at}" if delegated_at else "",
        ]
        if line
    )
    append_event(
        args.db_path,
        (
            f"cmd_delegate:{cmd_id}:{delegated_at or normalize_text(args.ts)}",
            normalize_text(args.ts),
            "cmd_delegate",
            "shogun",
            "karo",
            "delegate",
            summary,
            detail,
            "",
            cmd_id,
            "[]",
            normalize_text(args.source_file),
            None,
            "high",
        ),
        concept_text_extra=command_context_text(cmd_id),
        raw_content=message,
    )


def append_lesson(args) -> None:
    lesson_id = normalize_text(args.lesson_id)
    title = normalize_text(args.title)
    detail = normalize_text(args.detail)
    source_cmd = normalize_text(args.source_cmd)
    agent = normalize_text(args.agent) or "karo"
    project = normalize_text(args.project)
    ts = normalize_text(args.ts)
    summary = summarize(title) or lesson_id
    detail_full = "\n".join(
        line
        for line in [
            detail,
            f"project: {project}" if project else "",
            f"source_cmd: {source_cmd}" if source_cmd else "",
        ]
        if line
    )
    append_event(
        args.db_path,
        (
            f"lesson:{lesson_id}",
            ts,
            "lesson",
            agent,
            project,
            "",
            summary,
            detail_full,
            "",
            source_cmd or infer_cmd_id(summary, detail_full),
            "[]",
            normalize_text(args.source_file),
            None,
            "normal",
        ),
        raw_content=detail,
    )


def append_gate(args) -> None:
    gate_name = normalize_text(args.gate_name)
    result = normalize_text(args.result)
    cmd_id = normalize_text(args.cmd_id)
    detail = normalize_text(args.detail)
    ts = normalize_text(args.ts)
    summary = f"{gate_name}: {result}"
    if detail:
        summary = f"{gate_name}: {result} — {detail[:80]}"
    summary = summary[:SUMMARY_LIMIT]
    importance = "high" if result in ("FAIL", "BLOCK") else "normal"
    event_id = f"gate:{gate_name}:{cmd_id}:{ts}" if cmd_id else f"gate:{gate_name}:{ts}"
    detail_full = "\n".join(
        line
        for line in [
            detail,
            f"cmd_id: {cmd_id}" if cmd_id else "",
        ]
        if line
    )
    append_event(
        args.db_path,
        (
            event_id,
            ts,
            "gate",
            gate_name,
            cmd_id,
            result,
            summary,
            detail_full,
            "",
            cmd_id,
            "[]",
            normalize_text(args.source_file),
            None,
            importance,
        ),
        raw_content=detail,
    )


def _report_dot_key(dot_key: str) -> str:
    dot_key = normalize_text(dot_key)
    if dot_key.startswith("report_field_set."):
        return dot_key[len("report_field_set."):]
    return dot_key


def _report_field_has_concepts(dot_key: str) -> bool:
    normalized = _report_dot_key(dot_key)
    if normalized in REPORT_METADATA_DOT_KEYS:
        return False
    if any(normalized.startswith(prefix) for prefix in REPORT_METADATA_PREFIXES):
        return False
    if normalized in REPORT_MEANINGFUL_DOT_KEYS:
        return True
    return any(normalized.startswith(prefix) for prefix in REPORT_MEANINGFUL_PREFIXES)


def _report_value_to_text(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, dict):
        return "\n".join(_report_value_to_text(v) for v in value.values())
    if isinstance(value, list):
        return "\n".join(_report_value_to_text(v) for v in value)
    return normalize_text(value)


def _resolve_report_path(report_path: str) -> str:
    if not report_path:
        return ""
    if os.path.isabs(report_path):
        return report_path
    repo_relative = os.path.join(REPO_ROOT, report_path)
    if os.path.exists(repo_relative):
        return repo_relative
    return report_path


def _extract_report_field_value(report_path: str, dot_key: str) -> str:
    path = _resolve_report_path(report_path)
    if not path or not os.path.exists(path):
        return ""
    try:
        import yaml
    except ImportError:
        return ""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            data = yaml.safe_load(handle) or {}
    except Exception:
        return ""
    current: object = data
    for part in _report_dot_key(dot_key).split("."):
        if isinstance(current, dict):
            current = current.get(part)
        else:
            return ""
    return _report_value_to_text(current)


def append_report(args) -> None:
    report_path = normalize_text(args.report_path)
    agent = normalize_text(args.agent) or "unknown"
    parent_cmd = normalize_text(args.parent_cmd)
    verdict = normalize_text(args.verdict)
    dot_key = normalize_text(args.dot_key)
    report_base = os.path.basename(report_path) if report_path else ""
    summary = f"{agent} report:{report_base} field:{dot_key}"
    if verdict:
        summary = f"{summary} verdict:{verdict}"
    summary = summary[:SUMMARY_LIMIT]
    detail = "\n".join(
        line
        for line in [
            f"report_path: {report_path}",
            f"dot_key: {dot_key}",
            f"verdict: {verdict}" if verdict else "",
            f"parent_cmd: {parent_cmd}" if parent_cmd else "",
        ]
        if line
    )
    importance = "high" if verdict in ("PASS", "FAIL", "PASS_NO_IMPROVEMENT") else "normal"
    ts = normalize_text(args.ts)
    concept_text_extra = None
    raw_field_value = ""
    if _report_field_has_concepts(dot_key):
        raw_field_value = _extract_report_field_value(report_path, dot_key)
        concept_text_extra = "\n".join(
            line for line in [
                raw_field_value,
                command_context_text(parent_cmd),
            ] if line
        )

    append_event(
        args.db_path,
        (
            f"report:{report_base}:{dot_key}:{ts}",
            ts,
            "report",
            agent,
            report_path,
            dot_key,
            summary,
            detail,
            "",
            parent_cmd,
            "[]",
            normalize_text(args.source_file),
            None,
            importance,
        ),
        concept_text_extra=concept_text_extra,
        raw_content=raw_field_value or detail,
    )


def append_workaround(args) -> None:
    cmd_id = normalize_text(args.cmd_id)
    ninja = normalize_text(args.ninja)
    category = normalize_text(args.category)
    issue = normalize_text(args.issue)
    root_cause = normalize_text(args.root_cause)
    ts = normalize_text(args.ts)
    summary = summarize(issue) or f"{cmd_id} workaround"
    detail = "\n".join(
        line
        for line in [
            issue,
            f"root_cause: {root_cause}" if root_cause else "",
            f"category: {category}" if category else "",
            f"ninja: {ninja}" if ninja else "",
        ]
        if line
    )
    append_event(
        args.db_path,
        (
            f"workaround:{cmd_id}:{ninja}:{ts}",
            ts,
            "workaround",
            "karo",
            ninja,
            category,
            summary,
            detail,
            "",
            cmd_id or infer_cmd_id(summary, detail),
            "[]",
            normalize_text(args.source_file),
            None,
            "high",
        ),
        raw_content=issue,
    )


def parse_args():
    specs = {
        "inbox": (
            {
                "action": "",
            },
            ["message_id", "ts", "target_agent", "from_agent", "content", "message_type", "source_file"],
        ),
        "cmd_save": (
            {
                "summary": "",
                "detail": "",
            },
            ["cmd_id", "ts", "source_file"],
        ),
        "cmd_quality": (
            {
                "gunshi_verdict": "",
                "ninja_blockers": "0",
                "ac_count": "0",
                "supplementary_cmds": "0",
                "project": "",
                "source": "cmd_quality_log",
                "diagnosis": "",
                "notes": "",
            },
            ["cmd_id", "ts", "gate_result", "karo_rework", "source_file"],
        ),
        "cmd_delegate": (
            {
                "delegated_at": "",
                "summary": "",
            },
            ["cmd_id", "ts", "message", "source_file"],
        ),
        "bulletin": (
            {
                "requires_confirmation": "",
                "action_type": "info",
                "actioned_by": "",
                "status": "open",
            },
            ["entry_id", "ts", "agent", "content", "source_file"],
        ),
        "insight": (
            {
                "priority": "medium",
                "source": "manual",
                "status": "pending",
                "resolved_at": "",
            },
            ["entry_id", "ts", "insight", "source_file"],
        ),
        "report": (
            {
                "agent": "unknown",
                "parent_cmd": "",
                "verdict": "",
            },
            ["report_path", "ts", "dot_key", "source_file"],
        ),
        "workaround": (
            {
                "root_cause": "",
            },
            ["cmd_id", "ts", "ninja", "category", "issue", "source_file"],
        ),
        "lesson": (
            {
                "detail": "",
                "source_cmd": "",
                "agent": "karo",
                "project": "",
            },
            ["lesson_id", "title", "ts", "source_file"],
        ),
        "gate": (
            {
                "cmd_id": "",
                "detail": "",
            },
            ["gate_name", "result", "ts", "source_file"],
        ),
    }

    argv = sys.argv[1:]
    values = {"db_path": os.environ.get("SHOGUN_MEMORY_DB", DEFAULT_DB_PATH)}
    while argv and argv[0].startswith("--"):
        key = argv.pop(0)
        if key in ("-h", "--help"):
            print(__doc__ or "")
            raise SystemExit(0)
        if key != "--db-path" or not argv:
            print(f"FATAL: invalid global argument: {key}", file=sys.stderr)
            raise SystemExit(2)
        values["db_path"] = argv.pop(0)

    if not argv:
        print("FATAL: event_type is required", file=sys.stderr)
        raise SystemExit(2)
    event_type = argv.pop(0)
    if event_type not in specs:
        print(f"FATAL: unknown event_type: {event_type}", file=sys.stderr)
        raise SystemExit(2)

    defaults, required = specs[event_type]
    values.update(defaults)
    values["event_type"] = event_type

    while argv:
        option = argv.pop(0)
        if not option.startswith("--") or not argv:
            print(f"FATAL: invalid argument for {event_type}: {option}", file=sys.stderr)
            raise SystemExit(2)
        values[option[2:].replace("-", "_")] = argv.pop(0)

    missing = [name for name in required if name not in values or values[name] == ""]
    if missing:
        print(f"FATAL: missing required argument(s): {', '.join(missing)}", file=sys.stderr)
        raise SystemExit(2)

    return type("Args", (), values)()


def main() -> int:
    args = parse_args()
    if args.event_type == "inbox":
        append_inbox(args)
    elif args.event_type == "cmd_save":
        append_cmd_save(args)
    elif args.event_type == "cmd_quality":
        append_cmd_quality(args)
    elif args.event_type == "cmd_delegate":
        append_cmd_delegate(args)
    elif args.event_type == "bulletin":
        append_bulletin(args)
    elif args.event_type == "insight":
        append_insight(args)
    elif args.event_type == "report":
        append_report(args)
    elif args.event_type == "workaround":
        append_workaround(args)
    elif args.event_type == "lesson":
        append_lesson(args)
    elif args.event_type == "gate":
        append_gate(args)
    try:
        sync_memory_db_ext4_cache(args.db_path)
    except Exception as exc:
        print(f"WARN: memory DB ext4 cache sync failed: {exc}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
