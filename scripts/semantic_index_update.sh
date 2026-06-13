#!/usr/bin/env bash
# semantic-links: [[セマンティック辞書構想]]
# semantic_index_update.sh — Update semantic-index resources from known events.
# Usage: bash scripts/semantic_index_update.sh <cmd_complete|lesson|discussion|absorb_pending> '<json-payload>'

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash scripts/semantic_index_update.sh <source_type> <payload_json>

source_type:
  cmd_complete  payload: {"id":"cmd_123","title":"...","purpose":"...","files":["..."]}
  lesson        payload: {"id":"L123","title":"...","enforcement":"..."}
  discussion    payload: {"timestamp":"...","summary":"..."}
  absorb_pending payload: {}  resolve pending semantic insights without queuing a new candidate
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

if [ "$#" -lt 2 ]; then
    usage >&2
    exit 2
fi

source_type="$1"
payload_json="$2"

case "$source_type" in
    cmd_complete|lesson|discussion|absorb_pending) ;;
    *)
        echo "ERROR: unknown source_type: $source_type" >&2
        exit 2
        ;;
esac

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
script_dir="${_self%/scripts/semantic_index_update.sh}"
index_path="${SEMANTIC_INDEX_PATH:-$script_dir/docs/semantic-index/index.md}"
map_generate="${SEMANTIC_MAP_GENERATE:-$script_dir/scripts/semantic_map_generate.sh}"
insight_write="${SEMANTIC_INSIGHT_WRITE:-$script_dir/scripts/insight_write.sh}"
stress_test="${SEMANTIC_STRESS_CMD:-$script_dir/scripts/semantic_stress_test.sh}"
lock_path="${SEMANTIC_INDEX_LOCK:-${index_path}.lock}"

if [ ! -f "$index_path" ]; then
    echo "ERROR: semantic index not found: $index_path" >&2
    exit 1
fi

run_semantic_stress_after_alias_change() {
    [ "${SEMANTIC_STRESS_AFTER_ALIAS_CHANGE:-1}" = "0" ] && return 0
    [ -f "$stress_test" ] || return 0
    if [ -n "${SEMANTIC_INDEX_PATH:-}" ] && [ -z "${SEMANTIC_STRESS_CMD:-}" ]; then
        return 0
    fi

    local limit="${SEMANTIC_STRESS_AFTER_ALIAS_LIMIT:-20}"
    local baseline="${SEMANTIC_STRESS_BASELINE:-$script_dir/logs/semantic_stress_baseline.json}"
    local log_path="${SEMANTIC_STRESS_LOG:-$script_dir/logs/semantic_stress_test.log}"
    local insights="${INSIGHTS_FILE:-$script_dir/queue/insights.yaml}"

    echo "semantic-stress after-alias-change: running"
    if SEMANTIC_DISABLE_MEMORY_DB=1 bash "$stress_test" \
        --source all \
        --limit "$limit" \
        --baseline "$baseline" \
        --log "$log_path" \
        --insights "$insights"; then
        echo "semantic-stress after-alias-change: complete"
    else
        local rc=$?
        echo "WARN: semantic-stress after-alias-change failed(rc=$rc)" >&2
        return 0
    fi
}

run_semantic_quality_after_alias_change() {
    [ "${SEMANTIC_QUALITY_AFTER_ALIAS_CHANGE:-1}" = "0" ] && return 0
    local quality_test="${SEMANTIC_QUALITY_CMD:-$script_dir/scripts/semantic_quality_test.sh}"
    [ -f "$quality_test" ] || return 0
    if [ -n "${SEMANTIC_INDEX_PATH:-}" ] && [ -z "${SEMANTIC_QUALITY_CMD:-}" ]; then
        return 0
    fi

    echo "semantic-quality after-alias-change: running"
    if bash "$quality_test"; then
        echo "semantic-quality after-alias-change: complete"
    else
        local rc=$?
        echo "WARN: semantic-quality after-alias-change failed(rc=$rc)" >&2
        return 0
    fi
}

(
    flock -w 10 200 || { echo "ERROR: lock timeout: $lock_path" >&2; exit 1; }
    changed_flag="$(
    python3 - "$source_type" "$payload_json" "$index_path" "$insight_write" <<'PY'
import hashlib
import json
import math
import os
import re
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

source_type, payload_raw, index_arg, insight_arg = sys.argv[1:5]
index_path = Path(index_arg)
insight_write = Path(insight_arg)
semantic_root = index_path.parent.parent.parent
insights_path = Path(os.environ.get("SEMANTIC_INSIGHTS_PATH", str(semantic_root / "queue" / "insights.yaml")))
deploy_log_path = Path(os.environ.get("SEMANTIC_DEPLOY_LOG", str(semantic_root / "logs" / "deploy_task.log")))
semantic_search_path = Path(os.environ.get("SEMANTIC_SEARCH_CMD", str(semantic_root / "scripts" / "semantic_search.sh")))
pending_alias_threshold = float(os.environ.get("SEMANTIC_PENDING_ALIAS_THRESHOLD", "16.0"))
no_match_scan_lines = int(os.environ.get("SEMANTIC_NO_MATCH_SCAN_LINES", "500"))
no_match_alias_limit = int(os.environ.get("SEMANTIC_NO_MATCH_ALIAS_LIMIT", "5"))
memory_db_path = Path(os.environ.get("SEMANTIC_MEMORY_DB_PATH", str(semantic_root / "data" / "multi_agent_shogun_memory.db")))
tag_propagation_limit = int(os.environ.get("SEMANTIC_TAG_PROPAGATION_LIMIT", "30"))
tag_candidate_limit = int(os.environ.get("SEMANTIC_TAG_PROPAGATION_CANDIDATES", "5"))
tag_min_score = float(os.environ.get("SEMANTIC_TAG_PROPAGATION_MIN_SCORE", "1.0"))
tag_max_concepts = int(os.environ.get("SEMANTIC_TAG_PROPAGATION_MAX_CONCEPTS", "3"))
tag_bh_q = float(os.environ.get("SEMANTIC_TAG_PROPAGATION_BH_Q", "0.75"))
tag_source_per_concept = int(os.environ.get("SEMANTIC_TAG_PROPAGATION_SOURCE_PER_CONCEPT", "1"))
tag_source_limit = int(os.environ.get("SEMANTIC_TAG_PROPAGATION_SOURCE_LIMIT", "5"))
insight_recent_dedup_limit = int(os.environ.get("SEMANTIC_INSIGHT_RECENT_DEDUP_LIMIT", "50"))

try:
    payload = json.loads(payload_raw)
except json.JSONDecodeError as exc:
    print(f"ERROR: invalid payload JSON: {exc}", file=sys.stderr)
    sys.exit(2)

def flatten_text(value):
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, (int, float, bool)):
        return [str(value)]
    if isinstance(value, list):
        out = []
        for item in value:
            out.extend(flatten_text(item))
        return out
    if isinstance(value, dict):
        out = []
        for item in value.values():
            out.extend(flatten_text(item))
        return out
    return [str(value)]

def norm(value):
    return re.sub(r"\s+", " ", str(value).casefold()).strip()

NOISE_RE = re.compile(
    r"(?ix)"
    r"\b\d{4}-\d{2}-\d{2}(?:[t\s]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:z|[+-]\d{2}:?\d{2})?)?\b"
    r"|\bcmd_[a-z0-9_]+\b"
    r"|\bmsg_[a-z0-9_]+\b"
    r"|\bblt_[a-z0-9_]+\b"
    r"|\bLS?\d+\b"
)

def strip_noise(value):
    text = NOISE_RE.sub(" ", str(value))
    text = re.sub(r"`[^`]*`", " ", text)
    text = re.sub(r"https?://\S+", " ", text)
    text = re.sub(r"[/._:,+#|()\[\]{}<>\"'=-]+", " ", text)
    text = re.sub(r"\b\d+\b", " ", text)
    return re.sub(r"\s+", " ", text).strip()

def fts5_query_for_text(text):
    terms = []
    seen = set()
    for token in re.findall(r"[\w\u3040-\u30ff\u3400-\u9fff]+", str(text), flags=re.UNICODE):
        token = token.strip()
        token_n = norm(token)
        if token and token_n and token_n not in seen and len(token_n) >= 3:
            seen.add(token_n)
            terms.append(f'"{token.replace(chr(34), chr(34) + chr(34))}"')
        if len(terms) >= int(os.environ.get("SEMANTIC_TAG_PROPAGATION_QUERY_TERMS", "1")):
            break
    return " OR ".join(terms)

def parse_event_timestamp(value):
    text = str(value or "").strip()
    if not text:
        return None
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)

def semantic_recency_now():
    fixed = os.environ.get("SEMANTIC_RECENCY_NOW", "").strip()
    if fixed:
        parsed = parse_event_timestamp(fixed)
        if parsed is not None:
            return parsed
    return datetime.now(timezone.utc)

def percentile(sorted_values, pct):
    if not sorted_values:
        return 0.0
    if len(sorted_values) == 1:
        return sorted_values[0]
    pos = (len(sorted_values) - 1) * pct
    lower = math.floor(pos)
    upper = math.ceil(pos)
    if lower == upper:
        return sorted_values[int(pos)]
    fraction = pos - lower
    return sorted_values[lower] + (sorted_values[upper] - sorted_values[lower]) * fraction

def recency_frequency_raw(timestamps, now, decay_lambda):
    total = 0.0
    valid = 0
    for value in timestamps:
        parsed = parse_event_timestamp(value)
        if parsed is None:
            continue
        delta_days = max((now - parsed).total_seconds() / 86400.0, 0.0)
        total += math.exp(-decay_lambda * delta_days)
        valid += 1
    if valid == 0:
        return None
    return math.log1p(total)

def iqr_scaled_recency_weights(concept_timestamps):
    decay_lambda = float(os.environ.get("SEMANTIC_RECENCY_LAMBDA", "0.03"))
    now = semantic_recency_now()
    raw_by_concept = {
        concept: recency_frequency_raw(timestamps, now, decay_lambda)
        for concept, timestamps in concept_timestamps.items()
    }
    observed = sorted(value for value in raw_by_concept.values() if value is not None)
    median = percentile(observed, 0.5) if observed else 0.0
    q1 = percentile(observed, 0.25) if observed else median
    q3 = percentile(observed, 0.75) if observed else median
    iqr = q3 - q1
    if iqr <= 0:
        return {
            concept: max(1.0, 1.0 + (median if raw is None else raw))
            for concept, raw in raw_by_concept.items()
        }

    weights = {}
    for concept, raw in raw_by_concept.items():
        initialized = median if raw is None else raw
        weights[concept] = max(0.1, 1.0 + ((initialized - q1) / iqr))
    return weights

def propagate_memory_db_concept_tags(concepts):
    if os.environ.get("SEMANTIC_DISABLE_MEMORY_TAG_PROPAGATION") == "1":
        return
    if tag_propagation_limit <= 0 or tag_candidate_limit <= 0 or tag_max_concepts <= 0:
        return
    if not memory_db_path.is_file():
        return
    # TTL cache: skip if last propagation was within 300s (avoids ~17s SQLite/NTFS per call)
    _ttl = int(os.environ.get("SEMANTIC_TAG_PROPAGATION_TTL", "300"))
    if _ttl > 0:
        _db_key = hashlib.md5(str(memory_db_path.resolve()).encode()).hexdigest()[:8]
        _cache = Path(f"/tmp/shogun_tag_propagation_ttl_{_db_key}")
        try:
            if _cache.exists() and (time.time() - _cache.stat().st_mtime) < _ttl:
                return
        except OSError:
            pass

    known_concepts = {str(concept["id"]) for concept in concepts if str(concept.get("id") or "").strip()}
    if not known_concepts:
        return

    inserted = 0
    scanned = 0
    conn = None
    try:
        conn = sqlite3.connect(memory_db_path)
        conn.execute("PRAGMA busy_timeout=1000")
        conn.row_factory = sqlite3.Row
        total_events = int(conn.execute("SELECT COUNT(*) FROM events").fetchone()[0] or 0)
        if total_events <= 0:
            return

        conn.execute("DROP TABLE IF EXISTS temp.semantic_tag_source_events")
        conn.execute(
            """
            CREATE TEMP TABLE semantic_tag_source_events AS
            SELECT DISTINCT event_id
            FROM event_concepts
            """
        )

        concept_counts = {
            str(row["concept_name"]): int(row["doc_count"])
            for row in conn.execute(
                """
                SELECT concept_name, COUNT(DISTINCT event_id) AS doc_count
                FROM event_concepts
                GROUP BY concept_name
                """
            )
        }
        concept_timestamps = {concept: [] for concept in known_concepts}
        for row in conn.execute(
            """
            SELECT ec.concept_name, e.ts
            FROM event_concepts AS ec
            JOIN events AS e
              ON e.id = ec.event_id
            """
        ):
            concept_timestamps.setdefault(str(row["concept_name"]), []).append(row["ts"])
        recency_weights = iqr_scaled_recency_weights(concept_timestamps)

        selected_concepts = sorted(known_concepts & set(concept_counts))
        if not selected_concepts:
            return
        concept_sql = ",".join("?" for _ in selected_concepts)
        source_rows = list(
            conn.execute(
                f"""
                SELECT
                    ec.concept_name,
                    e.summary,
                    e.detail
                FROM event_concepts AS ec
                JOIN semantic_tag_source_events AS source
                  ON source.event_id = ec.event_id
                JOIN events AS e
                  ON e.id = ec.event_id
                WHERE ec.concept_name IN ({concept_sql})
                  AND COALESCE(e.summary, e.detail, '') != ''
                ORDER BY
                    CASE e.importance WHEN 'high' THEN 0 ELSE 1 END,
                    e.ts DESC,
                    e.id
                LIMIT ?
                """,
                [*selected_concepts, max(tag_source_limit * max(tag_source_per_concept, 1), 1)],
            )
        )
        if not source_rows:
            return

        candidate_scores = {}
        for row in source_rows:
            concept_name = str(row["concept_name"])
            query = fts5_query_for_text(f"{row['summary'] or ''} {row['detail'] or ''}")
            if not query:
                continue
            scanned += 1
            candidate_rows = list(
                conn.execute(
                    """
                    SELECT
                        e.id AS target_event_id,
                        bm25(events_fts) AS bm25_rank
                    FROM events_fts
                    JOIN events AS e ON e.rowid = events_fts.rowid
                    LEFT JOIN event_concepts AS existing
                      ON existing.event_id = e.id
                    WHERE events_fts MATCH ?
                      AND existing.event_id IS NULL
                    ORDER BY bm25_rank, e.ts DESC, e.id
                    LIMIT ?
                    """,
                    (query, tag_candidate_limit),
                )
            )
            if not candidate_rows:
                continue

            candidate_count = len(candidate_rows)
            for position, candidate in enumerate(candidate_rows, 1):
                # One-hop only: tagged source event -> directly matched untagged event -> concept.
                # bm25_rank orders content similarity; R(c) favors recently frequent concepts.
                # bh_decay is a Benjamini-Hochberg-style rank decay to suppress tail matches.
                target_event_id = str(candidate["target_event_id"])
                recency_weight = recency_weights.get(concept_name, 1.0)
                bm25_position_weight = 1.0 / position
                bh_decay = min(1.0, tag_bh_q * candidate_count / position)
                candidate_scores[(target_event_id, concept_name)] = (
                    candidate_scores.get((target_event_id, concept_name), 0.0)
                    + bm25_position_weight * recency_weight * bh_decay
                )

        by_event = {}
        for (event_id, concept_name), score in candidate_scores.items():
            if score >= tag_min_score:
                by_event.setdefault(event_id, []).append((score, concept_name))
        if not by_event:
            return

        event_order = sorted(
            by_event.items(),
            key=lambda item: (-sum(score for score, _concept in item[1]), item[0]),
        )
        for event_id, scored_concepts in event_order[:tag_propagation_limit]:
            selected = [
                concept_name
                for score, concept_name in sorted(scored_concepts, key=lambda item: (-item[0], item[1]))
            ][:tag_max_concepts]
            if not selected:
                continue

            conn.executemany(
                "INSERT OR IGNORE INTO event_concepts (event_id, concept_name) VALUES (?, ?)",
                [(event_id, concept_name) for concept_name in selected],
            )
            merged = sorted(set(selected))
            raw_concepts = conn.execute("SELECT concepts FROM events WHERE id = ?", (event_id,)).fetchone()
            if raw_concepts and raw_concepts["concepts"]:
                try:
                    existing = json.loads(raw_concepts["concepts"])
                    if isinstance(existing, list):
                        merged = sorted(set(str(item) for item in existing if str(item).strip()) | set(selected))
                except json.JSONDecodeError:
                    pass
            conn.execute("UPDATE events SET concepts = ? WHERE id = ?", (json.dumps(merged, ensure_ascii=False), event_id))
            inserted += len(selected)

        if inserted:
            conn.commit()
            print(f"MEMORY_TAG_PROPAGATION: scanned={scanned} inserted={inserted} db={memory_db_path}")
    except sqlite3.Error as exc:
        print(f"WARN: memory tag propagation failed: {exc}", file=sys.stderr)
    finally:
        if conn is not None:
            conn.close()
    # Update TTL cache after successful propagation
    if _ttl > 0:
        try:
            _cache.touch()
        except OSError:
            pass

def is_noise_only_candidate(payload_id, fields):
    signals = []
    for field in fields:
        cleaned = strip_noise(field)
        if cleaned:
            signals.append(cleaned)
    if not signals:
        return True
    combined = norm(" ".join(signals))
    payload_id_clean = norm(strip_noise(payload_id))
    if payload_id_clean and combined == payload_id_clean:
        return True
    # A payload that only contains generic source/event words after ID stripping
    # still has no concept signal worth sending to the insight backlog. Keep this
    # list conservative: it should catch transport/status chatter, not domain terms.
    generic = {
        "cmd",
        "complete",
        "completed",
        "lesson",
        "discussion",
        "payload",
        "event",
        "task",
        "notification",
        "id",
        "tool",
        "use",
        "timestamp",
        "terminal",
        "response",
        "inbound",
        "outbound",
        "ntfy",
        "status",
        "pass",
        "pending",
        "gate",
        "clear",
        "inbox",
        "イベント",
        "タスク",
        "通知",
        "完了",
        "済み",
        "委任",
        "タイムスタンプ",
    }
    def generic_token(token):
        token = norm(token)
        compact = re.sub(r"[\d_]+", "", token)
        if token in generic or compact in generic:
            return True
        transport_fragments = ("complete", "notification", "timestamp", "inbox", "イベント")
        return any(fragment in token for fragment in transport_fragments)

    tokens = [t for t in re.split(r"\s+", combined) if t and not generic_token(t)]
    return not tokens

OPERATIONAL_NOISE_RE = re.compile(
    r"(?ix)"
    r"^【[^】]+】"
    r"|(?:\b|_)(?:alert|warning|info)(?:\b|_)"
    r"|\bci\s*(?:red|green)\b"
    r"|\bci緑\b"
    r"|\bgate\s*(?:clear|pass|warn|block)?\b"
    r"|\brun\s+\d+\b"
    r"|\bpane_cmd\b"
    r"|\binbox\d*\b"
    r"|復帰"
    r"|ダミー"
    r"|起動alert"
    r"|三層ループalert"
    r"|context鮮度alert"
    r"|cli再起動"
    r"|infoバッチ"
    r"|共有して"
    r"|サボり"
)

STRUCTURAL_METADATA_RE = re.compile(
    r"(?ix)"
    r"^(?:title|type|node\s*id)\b"
    r"|^modules$"
)

def is_operational_noise_target(target):
    target_s = str(target).strip()
    target_n = norm(target_s)
    return bool(
        OPERATIONAL_NOISE_RE.search(target_s)
        or OPERATIONAL_NOISE_RE.search(target_n)
        or STRUCTURAL_METADATA_RE.search(target_n)
    )

def parse_related_concepts_cell(value):
    related = []
    for raw_item in str(value or "").split(","):
        item = raw_item.strip().strip("`")
        if not item:
            continue
        relation_type = "related"
        concept_id = item
        match = re.match(r"^([A-Za-z0-9_-]+)\s*\((.*?)\)$", item)
        if match:
            concept_id = match.group(1).strip()
            for attr in match.group(2).split(";"):
                key, sep, attr_value = attr.partition("=")
                if sep and key.strip() == "relation_type" and attr_value.strip():
                    relation_type = attr_value.strip()
        related.append({"id": concept_id, "relation_type": relation_type})
    return related

def parse_concepts(text):
    matches = list(re.finditer(r"(?m)^##\s+(.+)$", text))
    concepts = []
    for i, match in enumerate(matches):
        start = match.start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        block = text[start:end]
        heading = match.group(1).strip()
        concept_id = heading.split(" — ", 1)[0].strip()
        attrs = {}
        for line in block.splitlines():
            m = re.match(r"^\|\s*([^|]+?)\s*\|\s*(.*?)\s*\|$", line.strip())
            if not m:
                continue
            left, right = m.group(1).strip(), m.group(2).strip()
            if left in {"id", "label", "aliases", "related_concepts"}:
                attrs[left] = right
        aliases = [a.strip() for a in attrs.get("aliases", "").split(",") if a.strip()]
        cid = attrs.get("id") or concept_id
        if any(c["id"] == cid for c in concepts):
            continue  # skip duplicate concept IDs
        concepts.append(
            {
                "start": start,
                "end": end,
                "block": block,
                "id": cid,
                "label": attrs.get("label") or heading,
                "aliases": aliases,
                "related_concepts": parse_related_concepts_cell(attrs.get("related_concepts", "")),
            }
        )
    return concepts

def concept_terms(concepts):
    terms = set()
    for concept in concepts:
        for value in [concept["id"], concept["label"], *concept["aliases"]]:
            value_n = norm(value)
            if value_n:
                terms.add(value_n)
    return terms

def all_alias_terms(concepts):
    aliases = set()
    for concept in concepts:
        for value in concept["aliases"]:
            value_n = norm(value)
            if value_n:
                aliases.add(value_n)
    return aliases

def concept_name_map(concepts):
    names = {}
    for concept in concepts:
        for value in [concept["id"], concept["label"], *concept["aliases"]]:
            value_n = norm(value)
            if value_n and value_n not in names:
                names[value_n] = concept
    return names

def similarity_tokens(value):
    cleaned = strip_noise(value)
    tokens = [norm(t) for t in re.split(r"\s+", cleaned) if norm(t)]
    if tokens:
        return set(tokens)
    compact = norm(cleaned)
    if not compact:
        return set()
    if len(compact) <= 2:
        return {compact}
    return {compact[i : i + 2] for i in range(len(compact) - 1)}

def alias_similarity_score(target, alias):
    target_n = norm(target)
    alias_n = norm(alias)
    if not target_n or not alias_n:
        return 0.0
    if target_n == alias_n:
        return 100.0

    score = 0.0
    shorter, longer = sorted((target_n, alias_n), key=len)
    if len(shorter) >= 2 and shorter in longer:
        score += 55.0 * (len(shorter) / max(len(longer), 1))

    target_tokens = similarity_tokens(target)
    alias_tokens = similarity_tokens(alias)
    if target_tokens and alias_tokens:
        overlap = target_tokens & alias_tokens
        if overlap:
            score += 35.0 * (len(overlap) / max(len(target_tokens), len(alias_tokens)))

    target_chars = {c for c in target_n if not c.isspace()}
    alias_chars = {c for c in alias_n if not c.isspace()}
    if target_chars and alias_chars:
        score += 10.0 * (len(target_chars & alias_chars) / max(len(target_chars | alias_chars), 1))

    return score

def similar_concept_suggestions(target, concepts, limit=3):
    suggestions = []
    for concept in concepts:
        best_score = 0.0
        best_alias = ""
        for alias in concept["aliases"]:
            score = alias_similarity_score(target, alias)
            if score > best_score:
                best_score = score
                best_alias = alias
        if best_score <= 0:
            continue
        suggestions.append((best_score, concept["id"], concept["label"], best_alias))
    suggestions.sort(key=lambda item: (item[0], item[1]), reverse=True)
    return suggestions[:limit]

def best_similar_concept(target, concepts):
    suggestions = similar_concept_suggestions(target, concepts, limit=1)
    return suggestions[0] if suggestions else None

def format_similar_concepts(target, concepts):
    suggestions = similar_concept_suggestions(target, concepts)
    if not suggestions:
        return "類似概念TOP3: なし"
    rows = []
    for score, concept_id, label, alias in suggestions:
        rows.append(f"{concept_id}({label}; alias={alias}; score={score:.1f})")
    return "類似概念TOP3: " + " / ".join(rows)

def extract_wiki_targets(fields):
    targets = []
    seen = set()
    for field in fields:
        for raw in re.findall(r"\[\[([^\]]+)\]\]", str(field)):
            target = raw.split("|", 1)[0].split("#", 1)[0].strip()
            if not target:
                continue
            target_n = norm(target)
            if target_n in seen:
                continue
            seen.add(target_n)
            targets.append(target)
    return targets

def extract_cmd_origin_targets(payload):
    if source_type != "cmd_complete":
        return []
    raw = payload.get("origin")
    if raw is None:
        return []
    fields = raw if isinstance(raw, list) else [raw]
    return extract_wiki_targets(fields)

def discussion_candidate_label(payload, fallback):
    if source_type != "discussion":
        return fallback
    for key in ("summary", "detail"):
        value = payload.get(key)
        if not isinstance(value, str):
            continue
        cleaned = strip_noise(value)
        cleaned = re.sub(r"\s+", " ", cleaned).strip(" ・、。:：-")
        if cleaned:
            return cleaned[:80]
    return fallback

def parse_recent_insight_messages(path, limit):
    if limit <= 0 or not path.exists() or not path.stat().st_size:
        return []
    messages = []
    current = {}
    try:
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("- id: "):
                if current.get("insight"):
                    messages.append(current["insight"])
                current = {}
                continue
            if line.startswith("  insight:"):
                raw = line.split(":", 1)[1].strip()
                try:
                    current["insight"] = json.loads(raw)
                except json.JSONDecodeError:
                    current["insight"] = raw.strip("'\"")
        if current.get("insight"):
            messages.append(current["insight"])
    except OSError as exc:
        print(f"WARN: failed to read recent insights for dedup: {exc}", file=sys.stderr)
        return []
    return messages[-limit:]

def recent_insight_exists(message):
    return message in parse_recent_insight_messages(insights_path, insight_recent_dedup_limit)

def is_semantic_wiki_target(target):
    target_n = norm(target)
    if re.fullmatch(r"cmd_[a-z0-9_]+", target_n):
        return False
    if re.fullmatch(r"l\d+[a-z0-9_-]*", target_n):
        return False
    if re.fullmatch(r"ls[-_]?\d+[a-z0-9_-]*", target_n):
        return False
    if is_operational_noise_target(target):
        return False
    return bool(strip_noise(target))

def queue_insight(message, priority="low"):
    if recent_insight_exists(message):
        print(f"SKIP: recent duplicate semantic insight: {message[:120]}")
        return False
    if insight_write.exists():
        result = subprocess.run(
            ["bash", str(insight_write), message, priority, "semantic_index_update"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if result.stdout.strip():
            print(result.stdout.strip())
        if result.returncode != 0:
            if result.stderr.strip():
                print(result.stderr.strip(), file=sys.stderr)
            sys.exit(result.returncode)
    else:
        print(f"WARN: insight_write not found: {insight_write}", file=sys.stderr)
        print(message)
    return True

def queue_unregistered_target(target, concepts, message_prefix):
    if not is_semantic_wiki_target(target):
        return False
    if norm(target) in known_terms:
        return False
    similar = format_similar_concepts(target, concepts)
    if queue_insight(
        f"{message_prefix}: [[{target}]] は既存aliasesに一致なし。{similar}。概念定義とaliases追加を検討せよ",
        "low",
    ):
        return True
    return False

def purpose_alias_candidate(raw):
    cleaned = strip_noise(raw)
    cleaned = re.sub(r"^(修正|実装|改善|追加|強化)\s*[—:-]\s*", "", cleaned).strip()
    cleaned = cleaned.strip(" ・、。:：-")
    if not cleaned:
        return ""
    for part in re.split(r"[。．.!?\n]|[、,]\s*", cleaned):
        part = re.sub(r"\s+", " ", part).strip(" ・、。:：-")
        if len(part) >= 2:
            return part[:60]
    return ""

def recent_no_match_purpose_aliases(path):
    if no_match_alias_limit <= 0:
        return []
    if not path.exists() or not path.stat().st_size:
        return []
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except Exception as exc:
        print(f"WARN: failed to read NO_MATCH deploy log: {exc}", file=sys.stderr)
        return []

    aliases = []
    seen = set()
    for line in lines[-max(no_match_scan_lines, 1) :]:
        if "inject_semantic_concepts: NO_MATCH" not in line or "purpose=" not in line:
            continue
        purpose = line.split("purpose=", 1)[1]
        purpose = re.sub(r"\s+target_path=.*$", "", purpose).strip()
        alias = purpose_alias_candidate(purpose)
        alias_n = norm(alias)
        if not alias or alias_n in seen:
            continue
        seen.add(alias_n)
        aliases.append(alias)
        if len(aliases) >= no_match_alias_limit:
            break
    return aliases

def queue_no_match_purpose_aliases(concepts):
    known = concept_terms(concepts)
    queued = 0
    for alias in recent_no_match_purpose_aliases(deploy_log_path):
        if norm(alias) in known:
            continue
        similar = format_similar_concepts(alias, concepts)
        if queue_insight(
            f"[[{alias}]] NO_MATCH purpose pending alias: cmd_complete時にdeploy_task.logでNO_MATCHだったpurpose。{similar}。既存概念aliasesへの自動昇格候補",
            "low",
        ):
            queued += 1
    if queued:
        print(f"NO_MATCH_PURPOSE_ALIAS: queued {queued} pending alias candidate(s)")

def score_concept(concept, fields):
    normalized_fields = [norm(v) for v in fields if norm(v)]
    haystack = "\n".join(normalized_fields)
    exact_terms = []
    partial_terms = []
    for alias in concept["aliases"]:
        alias_n = norm(alias)
        if not alias_n:
            continue
        if alias_n in normalized_fields:
            exact_terms.append(alias)
        elif alias_n in haystack:
            partial_terms.append(alias)
    if exact_terms or len(set(partial_terms)) >= 2:
        return "HIGH", exact_terms, partial_terms
    if len(set(partial_terms)) == 1:
        return "LOW", exact_terms, partial_terms
    return "NONE", exact_terms, partial_terms

def shell_quote_backtick(value):
    return "`" + str(value).replace("`", "'") + "`"

def resource_row(source_type, payload):
    if source_type == "cmd_complete":
        cmd_id = str(payload.get("id") or payload.get("cmd_id") or "").strip()
        title = str(payload.get("title") or payload.get("purpose") or "").strip()
        files = payload.get("files") or []
        if isinstance(files, str):
            files = [p.strip() for p in re.split(r"[, \n]+", files) if p.strip()]
        file_hint = ", ".join(shell_quote_backtick(p) for p in files[:3])
        ref = shell_quote_backtick(cmd_id) if cmd_id else "`cmd_complete`"
        if title:
            ref += f" {title}"
        if file_hint:
            ref += f" ({file_hint})"
        return f"| cmd | {ref} |"
    if source_type == "lesson":
        lesson_id = str(payload.get("id") or payload.get("lesson_id") or "").strip()
        title = str(payload.get("title") or payload.get("enforcement") or "").strip()
        ref = shell_quote_backtick(lesson_id) if lesson_id else "`lesson`"
        if title:
            ref += f" {title}"
        return f"| lesson | {ref} |"
    timestamp = str(payload.get("timestamp") or payload.get("ts") or "").strip()
    summary = str(payload.get("summary") or payload.get("detail") or "").strip()
    summary = re.sub(r"<[^>]+>", "", summary)  # strip XML/HTML tags
    summary = re.sub(r"\s+", " ", summary).strip()  # collapse whitespace
    summary = summary[:120]  # cap at 120 chars
    target = str(payload.get("target") or payload.get("agent") or "").strip()
    ref = "`queue/lord_conversation.jsonl`"
    if timestamp:
        ref += f" {timestamp}"
    if target:
        ref += f" [{target}宛て]"
    if summary:
        ref += f" {summary}"
    return f"| discussion | {ref} |"

def causal_resource_rows(payload):
    if source_type != "cmd_complete":
        return []
    cmd_id = str(payload.get("id") or payload.get("cmd_id") or "").strip()
    if not cmd_id:
        return []

    rows = []
    seen = set()
    for key in ("origin", "depends_on"):
        raw = payload.get(key)
        if raw is None:
            continue
        if isinstance(raw, list):
            values = raw
        else:
            values = [raw]
        for value in values:
            text = str(value).strip()
            if not text or norm(text) in {"none", "なし", "null", "[]"}:
                continue
            if "[[" not in text and not re.search(r"\bcmd_[a-z0-9_]+\b", text, re.I):
                continue
            row = f"| causal | {shell_quote_backtick(cmd_id)} {key}: {text} |"
            if row not in seen:
                rows.append(row)
                seen.add(row)
    return rows

def append_row_to_block(block, row):
    if row in block:
        return block, False
    lines = block.rstrip("\n").splitlines()
    lines.append(row)
    return "\n".join(lines) + "\n\n", True

def _scope_tokens(text):
    """概念labelやaliases候補からスコープ判定用トークンを抽出"""
    tokens = set()
    tokens.update(w.lower() for w in re.findall(r'[a-zA-Z_][a-zA-Z0-9_]{2,}', str(text)))
    # 日本語2文字以上の単語(カタカナ/漢字)
    tokens.update(re.findall(r'[\u30A0-\u30FF\u4E00-\u9FFF]{2,}', str(text)))
    return tokens

def candidate_aliases(source_type, payload, existing_aliases, concept_label="", concept_id="", all_aliases_norm=None):
    min_alias_length = 3
    max_alias_length = 30
    existing_norm = {norm(alias) for alias in existing_aliases}
    all_aliases_norm = set(all_aliases_norm or ())
    # スコープ判定: 概念label+idからトークンを抽出
    scope_tokens = _scope_tokens(f"{concept_label} {concept_id}")
    scope_tokens.update(_scope_tokens(" ".join(existing_aliases)))  # 既存aliases全件をスコープに含める
    preferred_keys = {
        "cmd_complete": ["title", "purpose", "summary"],
        "lesson": ["title", "enforcement", "summary", "detail"],
        "discussion": ["summary", "detail"],
    }.get(source_type, [])
    aliases = []
    for key in preferred_keys:
        raw = payload.get(key)
        if not isinstance(raw, str):
            continue
        cleaned = strip_noise(raw)
        cleaned = re.sub(r"^(修正|実装|改善|追加|強化)\s*[—:-]\s*", "", cleaned).strip()
        cleaned = cleaned.strip(" ・、。:：-")
        if not cleaned:
            continue
        # Keep aliases compact enough to stay useful in the index table.
        for part in re.split(r"[。．.!?\n]|[、,]\s*", cleaned):
            part = re.sub(r"\s+", " ", part).strip(" ・、。:：-")
            part_norm = norm(part)
            if len(part) < min_alias_length or part_norm in existing_norm:
                continue
            if part_norm in all_aliases_norm:
                continue
            if len(part) > max_alias_length:
                continue
            # スコープチェック: 候補aliasesのトークンと概念スコープに1語も共通がなければ除外
            part_tokens = _scope_tokens(part)
            if scope_tokens and part_tokens and not (scope_tokens & part_tokens):
                continue
            aliases.append(part)
            existing_norm.add(part_norm)
            all_aliases_norm.add(part_norm)
            break
        if aliases:
            break
    return aliases

def append_aliases_to_block(block, aliases):
    if not aliases:
        return block, False
    lines = block.rstrip("\n").splitlines()
    changed = False
    for i, line in enumerate(lines):
        m = re.match(r"^(\|\s*aliases\s*\|\s*)(.*?)(\s*\|)$", line)
        if not m:
            continue
        current = [a.strip() for a in m.group(2).split(",") if a.strip()]
        current_norm = {norm(a) for a in current}
        for alias in aliases:
            if norm(alias) not in current_norm:
                current.append(alias)
                current_norm.add(norm(alias))
                changed = True
        if changed:
            lines[i] = f"{m.group(1)}{', '.join(current)}{m.group(3)}"
        break
    if not changed:
        return block, False
    return "\n".join(lines) + "\n\n", True

def parse_pending_semantic_insights(path):
    if not path.exists() or not path.stat().st_size:
        return []
    try:
        import yaml
        data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception as exc:
        print(f"WARN: failed to read semantic insights: {exc}", file=sys.stderr)
        return []

    pending = []
    for entry in data.get("insights") or []:
        if not isinstance(entry, dict):
            continue
        if str(entry.get("status", "")).strip() != "pending":
            continue
        insight_id = str(entry.get("id", "")).strip()
        insight = str(entry.get("insight", "")).strip()
        if not insight_id or not insight:
            continue

        entry_source = str(entry.get("source", "")).strip()
        is_training_source = (
            "training" in entry_source
            or re.search(r"(?i)(^|[-_])L\d+R\d+($|[-_])", entry_source) is not None
        )
        source_allowed = entry_source in ("semantic_index_update", "semantic_stress_test") or is_training_source

        # Direct alias syntax is already constrained and concept-named; accept it
        # before source filtering so manually curated AC5 insights are not dropped.
        direct_alias_entry = False
        for raw_target, raw_aliases in re.findall(
            r"\[\[([^\]]+)\]\]\s*alias(?:es)?\s*[:：]\s*([^\n]+)",
            insight,
            flags=re.I,
        ):
            target = raw_target.split("|", 1)[0].split("#", 1)[0].strip()
            aliases = []
            for alias in re.split(r"[,、，]", raw_aliases):
                alias = alias.strip(" \t;；。")
                if alias:
                    aliases.append(alias)
            if target and aliases:
                pending.append(
                    {
                        "id": insight_id,
                        "direct_concept": target,
                        "aliases": aliases,
                        "insight": insight,
                    }
                )
                direct_alias_entry = True

        if direct_alias_entry:
            continue
        if not source_allowed:
            continue

        original_query = ""
        m_query = re.search(r"\bquery=(.*?)(?:\s+quality_gate=|\s+fixed_50_role=|$)", insight)
        if m_query:
            original_query = m_query.group(1).strip()

        candidates = []
        for raw in re.findall(r"\[\[([^\]]+)\]\]", insight):
            target = raw.split("|", 1)[0].split("#", 1)[0].strip()
            if target:
                candidates.append(target)
        m = re.search(r"semantic_index_update新概念候補:\s*([^ ]+)\s+は", insight)
        if m:
            label = m.group(1).split(":", 1)[-1].strip()
            if label:
                candidates.append(label)

        seen = set()
        semantic_count = 0
        for candidate in candidates:
            candidate_n = norm(candidate)
            if not candidate_n or candidate_n in seen:
                continue
            seen.add(candidate_n)
            if is_semantic_wiki_target(candidate):
                semantic_count += 1
                pending.append(
                    {
                        "id": insight_id,
                        "alias": candidate,
                        "insight": insight,
                        "query": original_query,
                    }
                )
        if candidates and semantic_count == 0:
            pending.append({"id": insight_id, "alias": "", "insight": insight, "noise": True})
    return pending

def resolve_semantic_insight(insight_id):
    if not insight_write.exists():
        return False
    env = os.environ.copy()
    env["INSIGHTS_FILE"] = str(insights_path)
    result = subprocess.run(
        ["bash", str(insight_write), "--resolve", insight_id],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )
    if result.returncode != 0:
        err = result.stderr.strip() or result.stdout.strip()
        if err:
            print(f"WARN: semantic insight resolve failed: {insight_id}: {err}", file=sys.stderr)
        return False
    return True

def pending_query_now_hits(query):
    if not query or not semantic_search_path.exists():
        return False
    env = os.environ.copy()
    env.setdefault("SEMANTIC_DISABLE_LLM", "1")
    env.setdefault("SEMANTIC_ENABLE_LLM_FALLBACK", "0")
    env.setdefault("SEMANTIC_DISABLE_SEARCH_LOG", "1")
    try:
        result = subprocess.run(
            ["bash", str(semantic_search_path), query],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            timeout=float(os.environ.get("SEMANTIC_PENDING_RECHECK_TIMEOUT", "8")),
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f"WARN: pending semantic recheck failed: {query[:80]}: {exc}", file=sys.stderr)
        return False
    return result.returncode == 0

def absorb_pending_semantic_insights(text, concepts):
    additions = {}
    resolved_ids = set()
    messages = []

    known = concept_terms(concepts)
    names = concept_name_map(concepts)
    concepts_by_id = {concept["id"]: concept for concept in concepts}
    for item in parse_pending_semantic_insights(insights_path):
        if item.get("noise"):
            resolved_ids.add(item["id"])
            messages.append(f"PENDING_ALIAS: resolved noise {item['id']}")
            continue
        recheck_query = item.get("query") or ""
        if recheck_query and pending_query_now_hits(recheck_query):
            resolved_ids.add(item["id"])
            messages.append(f"PENDING_ALIAS_RECHECK: hit now {item['id']}")
            continue
        if item.get("direct_concept"):
            target = item["direct_concept"]
            concept = names.get(norm(target))
            if not concept:
                best_match = best_similar_concept(target, concepts)
                if best_match and best_match[0] >= pending_alias_threshold:
                    _, concept_id, _label, _matched_alias = best_match
                    concept = concepts_by_id.get(concept_id)
                    messages.append(
                        f"PENDING_ALIAS_DIRECT: {target} matched {concept_id} via {_matched_alias}"
                    )
                else:
                    messages.append(f"PENDING_ALIAS_DIRECT: no concept match for {target}")
                    continue
            added = []
            for alias in item.get("aliases") or []:
                alias = str(alias).strip()
                alias_n = norm(alias)
                if not alias_n or alias_n in known:
                    continue
                if is_operational_noise_target(alias) or not strip_noise(alias):
                    continue
                additions.setdefault(concept["id"], [])
                if alias_n not in {norm(v) for v in additions[concept["id"]]}:
                    additions[concept["id"]].append(alias)
                    known.add(alias_n)
                    added.append(alias)
            if added:
                messages.append(
                    f"PENDING_ALIAS_DIRECT: {target} -> {concept['id']} aliases_added={', '.join(added)}"
                )
            else:
                messages.append(f"PENDING_ALIAS_DIRECT: {target} -> {concept['id']} aliases_added=none")
            resolved_ids.add(item["id"])
            continue
        alias = item["alias"]
        alias_n = norm(alias)
        if alias_n in known:
            resolved_ids.add(item["id"])
            messages.append(f"PENDING_ALIAS: already known {alias}")
            continue
        best_match = best_similar_concept(alias, concepts)
        if not best_match:
            continue
        score, concept_id, label, matched_alias = best_match
        messages.append(
            f"PENDING_ALIAS_SCORE: {alias} -> {concept_id}({label}) via {matched_alias} score={score:.1f}"
        )
        if score < pending_alias_threshold:
            continue
        additions.setdefault(concept_id, [])
        if alias_n not in {norm(v) for v in additions[concept_id]}:
            additions[concept_id].append(alias)
            known.add(alias_n)
        resolved_ids.add(item["id"])

    if not additions and not resolved_ids:
        return text, concepts, False, messages

    updated = text
    changed = False
    for concept_id in sorted(additions, key=lambda cid: concepts_by_id[cid]["start"], reverse=True):
        concept = concepts_by_id[concept_id]
        new_block, block_changed = append_aliases_to_block(concept["block"], additions[concept_id])
        if block_changed:
            updated = updated[: concept["start"]] + new_block + updated[concept["end"] :]
            changed = True

    for insight_id in sorted(resolved_ids):
        resolve_semantic_insight(insight_id)

    if changed:
        concepts = parse_concepts(updated)
    return updated, concepts, changed, messages

text = index_path.read_text(encoding="utf-8")
concepts = parse_concepts(text)
if not concepts:
    print("ERROR: no concepts found in semantic index", file=sys.stderr)
    sys.exit(1)

propagate_memory_db_concept_tags(concepts)

if source_type == "cmd_complete":
    queue_no_match_purpose_aliases(concepts)

text, concepts, pending_changed, pending_messages = absorb_pending_semantic_insights(text, concepts)
for msg in pending_messages:
    print(msg)
if pending_changed:
    index_path.write_text(text, encoding="utf-8")
    print("__SEMANTIC_INDEX_CHANGED__")
    print("__SEMANTIC_ALIASES_CHANGED__")
if source_type == "absorb_pending":
    if pending_messages:
        print("ABSORB_PENDING: complete")
    else:
        print("ABSORB_PENDING: no semantic insight changes")
    sys.exit(0)

fields = flatten_text(payload)
known_terms = concept_terms(concepts)
origin_targets_seen = set()
for target in extract_cmd_origin_targets(payload):
    origin_targets_seen.add(norm(target))
    queue_unregistered_target(target, concepts, "semantic_index_update未登録cmd originノード")

for target in extract_wiki_targets(fields):
    if norm(target) in origin_targets_seen:
        continue
    queue_unregistered_target(target, concepts, "semantic_index_update未登録[[リンク]]ターゲット")

rank = {"HIGH": 2, "LOW": 1, "NONE": 0}
scored = []
for concept in concepts:
    confidence, exact, partial = score_concept(concept, fields)
    scored.append((rank[confidence], len(exact), len(set(partial)), concept, confidence, exact, partial))

scored.sort(key=lambda item: (item[0], item[1], item[2]), reverse=True)
_, _, _, best, confidence, exact, partial = scored[0]

payload_id = str(payload.get("id") or payload.get("cmd_id") or payload.get("lesson_id") or payload.get("timestamp") or "").strip()
payload_label = discussion_candidate_label(payload, payload_id or "payload")
matched = ", ".join(exact + sorted(set(partial))) or "none"

if confidence == "HIGH":
    rows = [resource_row(source_type, payload)] + causal_resource_rows(payload)
    new_block = best["block"]
    changed = False
    for row in rows:
        new_block, row_changed = append_row_to_block(new_block, row)
        changed = changed or row_changed
    if changed:
        updated = text[: best["start"]] + new_block + text[best["end"] :]
        index_path.write_text(updated, encoding="utf-8")
        print(f"HIGH: {best['id']} updated from {source_type}:{payload_label} matched={matched}")
        print("__SEMANTIC_INDEX_CHANGED__")
    else:
        print(f"HIGH: {best['id']} already contains {source_type}:{payload_label} matched={matched}")
    sys.exit(0)

if confidence == "LOW":
    aliases_to_add = candidate_aliases(
        source_type,
        payload,
        best["aliases"],
        concept_label=best.get("label", ""),
        concept_id=best.get("id", ""),
        all_aliases_norm=all_alias_terms(concepts),
    )
    alias_block, alias_changed = append_aliases_to_block(best["block"], aliases_to_add)
    rows = [resource_row(source_type, payload)] + causal_resource_rows(payload)
    new_block = alias_block
    row_changed = False
    for row in rows:
        new_block, changed_one = append_row_to_block(new_block, row)
        row_changed = row_changed or changed_one
    if alias_changed or row_changed:
        updated = text[: best["start"]] + new_block + text[best["end"] :]
        index_path.write_text(updated, encoding="utf-8")
        added = ", ".join(aliases_to_add) if alias_changed else "none"
        print(f"LOW: {best['id']} updated from {source_type}:{payload_label} matched={matched} aliases_added={added}")
        print("__SEMANTIC_INDEX_CHANGED__")
        if alias_changed:
            print("__SEMANTIC_ALIASES_CHANGED__")
    else:
        print(f"LOW: {best['id']} already contains {source_type}:{payload_label} matched={matched}")
    sys.exit(0)
else:
    if is_noise_only_candidate(payload_id, fields):
        print(f"NONE: skipped noise-only candidate for {source_type}:{payload_label}")
        sys.exit(0)
    # Dedup: skip if same payload_label already pending in insights
    if insights_path.exists():
        try:
            _raw_insights = insights_path.read_text(encoding="utf-8")
            # テキスト検索で早期チェック: payload_labelが含まれない場合はyaml.safe_load不要(65ms節約)
            if payload_label and payload_label in _raw_insights:
                import yaml as _y
                _ins = _y.safe_load(_raw_insights) or {}
                _pending_labels = [e.get("insight","") for e in _ins.get("insights",[]) if e.get("status")=="pending"]
                if any(payload_label in lbl for lbl in _pending_labels):
                    print(f"NONE: dedup — {source_type}:{payload_label} already pending in insights")
                    sys.exit(0)
        except Exception:
            pass
    message = (
        f"semantic_index_update新概念候補: {source_type}:{payload_label} は "
        f"既存aliasesに一致なし。概念定義とaliases追加を検討せよ"
    )
    priority = "low"

    if queue_insight(message, priority):
        print(f"{confidence}: insight queued for {source_type}:{payload_label}")
    else:
        print(f"{confidence}: insight skipped for {source_type}:{payload_label}")
PY
    )"
    index_changed=false
    aliases_changed=false
    while IFS= read -r line; do
        if [ "$line" = "__SEMANTIC_INDEX_CHANGED__" ]; then
            index_changed=true
        elif [ "$line" = "__SEMANTIC_ALIASES_CHANGED__" ]; then
            aliases_changed=true
        else
            printf '%s\n' "$line"
        fi
    done <<< "$changed_flag"
    if [ "$index_changed" = true ]; then
        if [ -f "$map_generate" ]; then
            # バックグラウンド実行: semantic-mapはeventual consistencyで問題なし。
            # 同期実行(586ms)→非同期化により呼び出し元の待ち時間を削減。
            bash "$map_generate" >/dev/null &
            echo "semantic-map regenerated (background)"
        else
            echo "WARN: semantic map generator not found: $map_generate" >&2
        fi
        if [ "$aliases_changed" = true ]; then
            run_semantic_stress_after_alias_change
            run_semantic_quality_after_alias_change
        fi
    fi
) 200>"$lock_path"
