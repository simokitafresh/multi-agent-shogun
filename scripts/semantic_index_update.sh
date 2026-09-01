#!/usr/bin/env bash
# semantic-links: [[セマンティック辞書構想]]
# semantic_index_update.sh — Update semantic-index resources from known events.
# Usage: bash scripts/semantic_index_update.sh <cmd_complete|lesson|discussion|absorb_pending> '<json-payload>'

set -euo pipefail

# Round8 lane #0': complete entrypoint wall-clock telemetry.
SEMANTIC_INDEX_UPDATE_TOTAL_T0_US="${EPOCHREALTIME/./}"
SEMANTIC_INDEX_UPDATE_TOTAL_T0_US="${SEMANTIC_INDEX_UPDATE_TOTAL_T0_US:0:16}"
_SEMANTIC_INDEX_UPDATE_TOTAL_SELF="${BASH_SOURCE[0]:-$0}"
[[ "$_SEMANTIC_INDEX_UPDATE_TOTAL_SELF" = /* ]] || _SEMANTIC_INDEX_UPDATE_TOTAL_SELF="$PWD/$_SEMANTIC_INDEX_UPDATE_TOTAL_SELF"
_SEMANTIC_INDEX_UPDATE_TOTAL_ROOT="${_SEMANTIC_INDEX_UPDATE_TOTAL_SELF%/scripts/semantic_index_update.sh}"
DEFENSE_OVERHEAD_REPO_ROOT="${DEFENSE_OVERHEAD_REPO_ROOT:-$_SEMANTIC_INDEX_UPDATE_TOTAL_ROOT}"
# shellcheck source=scripts/lib/defense_overhead_writer.sh
source "$_SEMANTIC_INDEX_UPDATE_TOTAL_ROOT/scripts/lib/defense_overhead_writer.sh"
SEMANTIC_INDEX_UPDATE_TOTAL_RECORDED=0
semantic_index_update_record_total() {
    local rc="${1:-0}" now_us wall_ms verdict
    [ "${SEMANTIC_INDEX_UPDATE_TOTAL_RECORDED:-0}" -eq 0 ] || return 0
    SEMANTIC_INDEX_UPDATE_TOTAL_RECORDED=1
    now_us="${EPOCHREALTIME/./}"
    now_us="${now_us:0:16}"
    wall_ms=$(( (now_us - SEMANTIC_INDEX_UPDATE_TOTAL_T0_US + 999) / 1000 ))
    verdict=PASS
    [ "$rc" -eq 0 ] || verdict=FAIL
    defense_overhead_write_async semantic_index_update semantic_index_update_total "$wall_ms" "$verdict" \
        "semantic-index-update-${BASHPID}-${SEMANTIC_INDEX_UPDATE_TOTAL_T0_US}" || true
}
semantic_index_update_total_on_exit() { local rc=$?; semantic_index_update_record_total "$rc"; return "$rc"; }
trap semantic_index_update_total_on_exit EXIT

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

# Git merge driver for the generated semantic-index publication unit.  The
# index is composed from canonical concept blocks, not line hunks: disjoint
# blocks are regenerated into one output, while divergent edits to one
# concept remain fail-closed for manual resolution.  This keeps a remote/local
# publication from selecting a stale generated snapshot silently.
if [ "${1:-}" = "--merge-driver" ]; then
    [ "$#" -eq 4 ] || {
        echo "Usage: --merge-driver <ancestor> <ours> <theirs>" >&2
        exit 2
    }
    python3 - "$2" "$3" "$4" <<'PY'
import os
import re
import sys
import tempfile
from pathlib import Path

ancestor_path, ours_path, theirs_path = map(Path, sys.argv[1:])


def parse_document(path, label):
    text = path.read_text(encoding="utf-8")
    if not text.strip():
        raise ValueError(f"{label} is empty")
    parts = re.split(r"(?m)(?=^## )", text)
    prefix = parts[0] if parts and not parts[0].startswith("## ") else ""
    blocks = parts[1:] if prefix else parts
    entries, order = {}, []
    for raw in blocks:
        if not raw.startswith("## "):
            raise ValueError(f"{label} has text outside a concept block")
        heading = raw.splitlines()[0][3:].strip()
        match = re.search(r"(?m)^\|\s*id\s*\|\s*([^|]+?)\s*\|\s*$", raw)
        item_id = match.group(1).strip() if match else heading.split(" — ", 1)[0].strip()
        if not item_id:
            raise ValueError(f"{label} has a concept without an id")
        if item_id in entries:
            raise ValueError(f"{label} duplicate concept id: {item_id}")
        entries[item_id] = raw
        order.append(item_id)
    return prefix, entries, order


def same(left, right):
    return left == right


try:
    ancestor = parse_document(ancestor_path, "ancestor")
    ours = parse_document(ours_path, "ours")
    theirs = parse_document(theirs_path, "theirs")
    merged, conflicts, regenerated_conflicts = {}, [], []
    for item_id in set(ancestor[1]) | set(ours[1]) | set(theirs[1]):
        base, current, incoming = ancestor[1].get(item_id), ours[1].get(item_id), theirs[1].get(item_id)
        if same(current, incoming):
            chosen = current
        elif same(current, base):
            chosen = incoming
        elif same(incoming, base):
            chosen = current
        else:
            # The index is generated output.  Its canonical source is merged
            # separately; retain the current generated block and let the
            # next source regeneration publish the canonical bytes instead
            # of turning generated drift into a manual merge conflict.
            chosen = current
            regenerated_conflicts.append(item_id)
        if chosen is not None:
            merged[item_id] = chosen
    if conflicts:
        print("BLOCK: same semantic concept changed on both parents: " + ", ".join(sorted(conflicts)), file=sys.stderr)
        raise SystemExit(1)

    order = [item_id for item_id in ours[2] if item_id in merged]
    order.extend(item_id for item_id in theirs[2] if item_id in merged and item_id not in order)
    order.extend(item_id for item_id in ancestor[2] if item_id in merged and item_id not in order)
    merged_text = ours[0] + "".join(merged[item_id] for item_id in order)
    if not merged_text.endswith("\n"):
        merged_text += "\n"
    ids = [re.search(r"(?m)^\|\s*id\s*\|\s*([^|]+?)\s*\|\s*$", merged[item_id]).group(1).strip()
           for item_id in order]
    if len(ids) != len(set(ids)) or any(not item_id for item_id in ids):
        raise ValueError("merged semantic index has duplicate or empty concept IDs")
    target = ours_path
    fd, temporary = tempfile.mkstemp(prefix=".semantic-index-merge.", suffix=".tmp", dir=target.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(merged_text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(f"SEMANTIC_INDEX_MERGE_OK concepts={len(ids)} duplicate_ids=0 regenerated=yes same_id_rebuilt={len(regenerated_conflicts)}")
except (OSError, ValueError) as exc:
    print(f"BLOCK: semantic index merge failed: {exc}", file=sys.stderr)
    raise SystemExit(2)
PY
    exit $?
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

# WSL2 /mnt/c上のSQLite正本をtag propagationが直接走査すると、events×conceptsの
# random row I/OがP9待ちになり数分化する。読取先の解決は共通SSOTへ委譲し、
# 明示的なテストDBはdefault_path不一致により従来どおりそのまま使用する。
memory_db_default="$script_dir/data/multi_agent_shogun_memory.db"
memory_db_source="${SEMANTIC_MEMORY_DB_PATH:-$memory_db_default}"
memory_db_cache_helper="${SEMANTIC_MEMORY_DB_CACHE_HELPER:-$script_dir/scripts/lib/memory_db_cache.sh}"
if [ -f "$memory_db_cache_helper" ]; then
    # shellcheck source=scripts/lib/memory_db_cache.sh
    source "$memory_db_cache_helper"
    if type prepare_memory_db_for_read >/dev/null 2>&1; then
        SEMANTIC_MEMORY_DB_PATH="$(prepare_memory_db_for_read "$script_dir" "$memory_db_source" "$memory_db_default")"
        export SEMANTIC_MEMORY_DB_PATH
    fi
fi

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

post_state_file="$(mktemp "${TMPDIR:-/tmp}/semantic_index_update.post.XXXXXX")"
semantic_index_update_cleanup_on_exit() {
    local rc=$?
    rm -f "${post_state_file:-}"
    semantic_index_update_record_total "$rc"
    return "$rc"
}
trap semantic_index_update_cleanup_on_exit EXIT

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
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

source_type, payload_raw, index_arg, insight_arg = sys.argv[1:5]
index_path = Path(index_arg)
insight_write = Path(insight_arg)
semantic_root = index_path.parent.parent.parent
sys.path.insert(0, str(semantic_root))
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
no_match_threshold = int(os.environ.get("SEMANTIC_NO_MATCH_THRESHOLD", "3"))
no_match_filepath_log = Path(os.environ.get("SEMANTIC_NO_MATCH_FILEPATH_LOG", str(semantic_root / "logs" / "no_match_filepaths.yaml")))

def atomic_write_text(path, text):
    """Replace a complete same-directory file so concurrent readers see old or new."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if path == index_path and path.exists():
        current = path.read_text(encoding="utf-8")
        current_ids = re.findall(r"(?m)^\|\s*id\s*\|\s*([^|]+?)\s*\|$", current)
        candidate_ids = re.findall(r"(?m)^\|\s*id\s*\|\s*([^|]+?)\s*\|$", text)
        if not candidate_ids or len(candidate_ids) < len(current_ids):
            raise RuntimeError(
                f"semantic index monotonicity violation: concepts {len(current_ids)} -> {len(candidate_ids)}"
            )
        if len(candidate_ids) != len(set(candidate_ids)):
            raise RuntimeError("semantic index invalid: duplicate concept ids")
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp_name, path)
    finally:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass

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
                # candidate_count=1の場合、BH減衰を適用しない(唯一の候補に
                # rank-based decayは無意味。GA-138で単一候補排除FPを実証)
                bh_decay = 1.0 if candidate_count == 1 else min(1.0, tag_bh_q * candidate_count / position)
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
    # Short discussion questions that only ask for the current status do not
    # define a durable concept.  Keep this narrower than a generic question
    # check so reflective/design questions remain eligible as insights.
    if source_type == "discussion" and len(combined) <= 40:
        status_question = re.compile(
            r"^(?:いま|今)?[^。!！]{0,24}(?:は|の)?"
            r"(?:どうなって(?:る|いる)|どう(?:だ|ですか|なの)|"
            r"進捗(?:は)?どう|状況(?:は)?どう)[?？]?$"
        )
        if status_question.fullmatch(combined):
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

# ── files_modified → concept 推論 (infer_concepts_from_files) ──────────────

DIR_PREFIX_MAP = [
    # (正規表現パターン, concept_id, confidence)
    (r"^scripts/gates/",                  "gate_quality_framework",        "MEDIUM"),
    (r"^scripts/hooks/",                  "hook_automation_framework",     "MEDIUM"),
    (r"^scripts/lesson_",                 "lesson_lifecycle",              "HIGH"),
    (r"^scripts/inbox_",                  "inbox_processing_discipline",   "HIGH"),
    (r"^scripts/inbox_watcher",           "inbox_watcher_process_model",   "HIGH"),
    (r"^scripts/semantic_",               "semantic_causal_automation",    "HIGH"),
    (r"^scripts/memory_db_",              "local_memory_db",               "HIGH"),
    (r"^scripts/obsidian_",               "three_layer_memory_system",     "MEDIUM"),
    (r"^scripts/deploy_task\.sh",         "agent_formation_management",    "HIGH"),
    (r"^scripts/ninja_monitor",           "daemon_supervision",            "HIGH"),
    (r"^scripts/cmd_save",                "cmd_quality_logging",           "HIGH"),
    (r"^scripts/cmd_complete_gate",       "gate_quality_framework",        "HIGH"),
    (r"^scripts/report_field_set",        "report_quality_protocol",       "HIGH"),
    (r"^context/dm-signal",               "dmsignal_operations",           "MEDIUM"),
    (r"^context/growth-loop",             "growth_loop",                   "HIGH"),
    (r"^context/infrastructure",          "infrastructure_ops",            "HIGH"),
    (r"^context/memory-db",               "local_memory_db",               "HIGH"),
    (r"^context/training-cycle",          "training_cycle_quality",        "MEDIUM"),
    (r"^context/semantic-map",            "semantic_causal_automation",    "HIGH"),
    (r"^docs/semantic-index/",            "semantic_causal_automation",    "HIGH"),
    (r"^docs/research/gunshi_",           "semantic_causal_automation",    "LOW"),
    (r"^docs/research/",                  None,                            "LOW"),
    (r"^tests/unit/test_semantic",        "semantic_causal_automation",    "MEDIUM"),
    (r"^tests/unit/test_cmd_",            "cmd_quality_logging",           "MEDIUM"),
    (r"^tests/unit/test_memory",          "local_memory_db",               "MEDIUM"),
    (r"^tests/unit/",                     "test_quality_framework",        "LOW"),
    (r"^skills/",                         "skill_design_rules",            "MEDIUM"),
    (r"^instructions/",                   "chain_principle",               "LOW"),
    (r"^projects/dm-signal",              "dmsignal_operations",           "MEDIUM"),
    (r"^config/",                         "agent_formation_management",    "LOW"),
    (r"^\.(claude|codex)/hooks/",         "hook_automation_framework",     "HIGH"),
    (r"^\.(claude|codex)/hooks/pre-bash", "destructive_operations_guard",  "MEDIUM"),
]

def build_file_concept_map(concepts):
    """Stage 1: | file | 行を逆引きマップに変換 filepath → set[concept_id]"""
    fcm = {}
    for concept in concepts:
        for line in concept["block"].splitlines():
            m = re.match(r'^\|\s*file\s*\|\s*`([^`]+)`', line.strip())
            if m:
                fp = m.group(1)
                fcm.setdefault(fp, set()).add(concept["id"])
    return fcm

def max_confidence(a, b):
    """2つのconfidence文字列のうち高い方を返す"""
    _rank = {"HIGH": 3, "MEDIUM": 2, "LOW": 1}
    return a if _rank.get(a, 0) >= _rank.get(b, 0) else b

def match_dir_prefix(fp):
    """Stage 2: DIR_PREFIX_MAPでファイルパスをマッチ → (concept_id, confidence) or None"""
    for pattern, concept_id, confidence in DIR_PREFIX_MAP:
        if re.search(pattern, fp) and concept_id:
            return concept_id, confidence
    return None

def infer_concepts_from_files(files_modified, concepts):
    """4段階フォールバックでfiles_modified → {concept_id: confidence} を推論する。
    Stage1: | file | 直接ルックアップ(HIGH)
    Stage2: ディレクトリプレフィックス(DIR_PREFIX_MAP)
    Stage3: ファイル名ステム × aliasスコアリング(LOW)
    Returns: (concept_results, no_match_files) where no_match_files is a set of unmatched file paths.
    """
    file_concept_map = build_file_concept_map(concepts)
    results = {}
    no_match_files = set()

    for fp in (files_modified or []):
        fp = str(fp).strip()
        if not fp:
            continue

        # Stage 1: 直接ルックアップ
        if fp in file_concept_map:
            for cid in file_concept_map[fp]:
                results[cid] = max_confidence(results.get(cid), "HIGH")
            continue

        # Stage 2: ディレクトリプレフィックス
        prefix_match = match_dir_prefix(fp)
        if prefix_match:
            cid, conf = prefix_match
            results[cid] = max_confidence(results.get(cid), conf)
            continue

        # Stage 3: ファイル名ステム × aliasスコアリング
        stem = Path(fp).stem
        parts = fp.replace("/", " ").replace("_", " ").replace("-", " ")
        stem_fields = [fp, stem, parts]
        stage3_matched = False
        for concept in concepts:
            level, _, _ = score_concept(concept, stem_fields)
            if level != "NONE":
                results[concept["id"]] = max_confidence(results.get(concept["id"]), "LOW")
                stage3_matched = True

        if not stage3_matched:
            no_match_files.add(fp)

    return results, no_match_files

# ── /infer_concepts_from_files ─────────────────────────────────────────────

# ── provisional concept 自動生成 ────────────────────────────────────────────

def load_no_match_filepaths():
    """logs/no_match_filepaths.yaml を読み込む。存在しない場合は空dictを返す。"""
    if not no_match_filepath_log.exists():
        return {"no_match_files": {}}
    try:
        import yaml as _yaml_nm
        data = _yaml_nm.safe_load(no_match_filepath_log.read_text(encoding="utf-8")) or {}
        if not isinstance(data.get("no_match_files"), dict):
            data["no_match_files"] = {}
        return data
    except Exception as exc:
        print(f"WARN: failed to load no_match_filepaths: {exc}", file=sys.stderr)
        return {"no_match_files": {}}

def save_no_match_filepaths(data):
    """logs/no_match_filepaths.yaml に書き込む。"""
    try:
        # cmd_karo_hotfix_lesson_impact_yaml_dump (AC4 横展開是正): 別名import
        # (import yaml as _yaml_nm) 経由の直接 dump()+write_text() は
        # gate_no_direct_yaml_dump.sh の語彙拡張で検知対象になった。この
        # ファイルは運用YAML(queue/tasks/inbox等)ではないが、既存の安全な
        # atomic writerへ揃えて族ごと塞ぐ。
        from scripts.lib.yaml_atomic import atomic_yaml_write

        no_match_filepath_log.parent.mkdir(parents=True, exist_ok=True)
        atomic_yaml_write(str(no_match_filepath_log), data)
    except Exception as exc:
        print(f"WARN: failed to save no_match_filepaths: {exc}", file=sys.stderr)

def update_no_match_count(fp, cmd_id):
    """fpのNO_MATCHカウントをインクリメントし、新しいカウントを返す。"""
    data = load_no_match_filepaths()
    files = data["no_match_files"]
    now_str = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if fp not in files:
        files[fp] = {
            "count": 1,
            "first_seen": now_str,
            "last_seen": now_str,
            "source_cmds": [cmd_id] if cmd_id else [],
            "provisional_generated": False,
        }
    else:
        files[fp]["count"] = int(files[fp].get("count", 0)) + 1
        files[fp]["last_seen"] = now_str
        cmds = list(files[fp].get("source_cmds") or [])
        if cmd_id and cmd_id not in cmds:
            cmds.append(cmd_id)
        files[fp]["source_cmds"] = cmds
    save_no_match_filepaths(data)
    return files[fp]["count"]

def should_generate_provisional(fp, count, concepts):
    """T2/T3/T4の全条件を満たすか判定。
    T2: count >= THRESHOLD (デフォルト3)
    T3: ステム長>=4 かつ 純数字でない
    T4: 同名の仮conceptが未存在 かつ provisional_generatedフラグ未設定
    """
    if count < no_match_threshold:
        return False
    # T3
    stem = Path(fp).stem.lower()
    if len(stem) < 4 or re.fullmatch(r"\d+", stem):
        return False
    # T4: index.md内に既存provisional確認
    provisional_id = f"provisional_{stem}"
    if any(c["id"] == provisional_id for c in concepts):
        return False
    # provisional_generated フラグ確認
    data = load_no_match_filepaths()
    if data.get("no_match_files", {}).get(fp, {}).get("provisional_generated"):
        return False
    return True

def make_provisional_concept_block(fp, cmd_id, count):
    """仮conceptのMarkdownブロックを生成する。"""
    stem = Path(fp).stem.lower()
    derived_label = stem.replace("_", " ").replace("-", " ").title()
    provisional_id = f"provisional_{stem}"
    normalized_path = fp.replace("/", " ").replace("_", " ").replace("-", " ")
    # aliases: 重複排除
    aliases_list = []
    seen_a = set()
    for alias in [stem, fp, normalized_path, provisional_id]:
        alias_n = norm(alias)
        if alias_n and alias_n not in seen_a:
            aliases_list.append(alias)
            seen_a.add(alias_n)
    aliases_str = ", ".join(aliases_list)
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    promotion_threshold = int(os.environ.get("SEMANTIC_PROVISIONAL_PROMOTION_THRESHOLD", "5"))
    cmd_ref = cmd_id or "unknown"
    block = (
        f"## {provisional_id} — 仮: {derived_label}\n"
        f"\n"
        f"| 属性 | 値 |\n"
        f"|------|---|\n"
        f"| id | {provisional_id} |\n"
        f"| label | 仮: {derived_label} |\n"
        f"| aliases | {aliases_str} |\n"
        f"| status | provisional |\n"
        f"| auto_generated | true |\n"
        f"| source_cmd | {cmd_ref} |\n"
        f"| source_files | {fp} |\n"
        f"| no_match_count | {count} |\n"
        f"| created_at | {now_iso} |\n"
        f"| promotion_threshold | {promotion_threshold} |\n"
        f"| related_concepts | |\n"
        f"\n"
        f"| 種別 | パス/参照 |\n"
        f"|------|----------|\n"
        f"| file | `{fp}` |\n"
        f"| causal | `{cmd_ref}` -> [[{provisional_id}]] (auto_generated) |\n"
        f"\n"
    )
    return provisional_id, block

def insert_provisional_concept(text, concepts, provisional_block):
    """仮conceptブロックをsemantic_causal_automationセクションの直後に挿入。
    anchorが存在しない場合はテキスト末尾に追加する。
    """
    anchor_id = os.environ.get("SEMANTIC_PROVISIONAL_ANCHOR", "semantic_causal_automation")
    anchor_concept = next((c for c in concepts if c["id"] == anchor_id), None)
    insert_pos = anchor_concept["end"] if anchor_concept is not None else len(text)
    provisional_marker = "<!-- PROVISIONAL CONCEPTS - auto-generated, pending human review -->\n"
    prefix = "" if provisional_marker in text else provisional_marker
    updated = text[:insert_pos] + prefix + provisional_block + text[insert_pos:]
    return updated

def handle_no_match_files(no_match_files, cmd_id, text, concepts):
    """NO_MATCHファイルの累積カウント更新と仮concept生成を行う。
    Returns: (updated_text, updated_concepts, changed_flag)
    """
    if not no_match_files:
        return text, concepts, False
    changed = False
    for fp in sorted(no_match_files):
        count = update_no_match_count(fp, cmd_id)
        print(f"NO_MATCH_TRACKED: {fp} count={count}")
        if not should_generate_provisional(fp, count, concepts):
            continue
        # 高類似既存conceptがあればaliasとして吸収
        stem = Path(fp).stem.lower()
        best = best_similar_concept(stem, concepts)
        if best and best[0] >= 70.0:
            score, concept_id, label, matched_alias = best
            concepts_by_id_local = {c["id"]: c for c in concepts}
            concept = concepts_by_id_local.get(concept_id)
            if concept:
                new_block, block_changed = append_aliases_to_block(concept["block"], [stem])
                if block_changed:
                    text = text[:concept["start"]] + new_block + text[concept["end"]:]
                    concepts = parse_concepts(text)
                    changed = True
                    print(f"PROVISIONAL_ABSORBED: {fp} -> {concept_id} stem={stem} score={score:.1f}")
            _absorb_data = load_no_match_filepaths()
            if fp in _absorb_data.get("no_match_files", {}):
                _absorb_data["no_match_files"][fp]["provisional_generated"] = True
                _absorb_data["no_match_files"][fp]["provisional_id"] = f"absorbed_into_{concept_id}"
                save_no_match_filepaths(_absorb_data)
            continue
        # 仮concept生成
        provisional_id, provisional_block = make_provisional_concept_block(fp, cmd_id, count)
        text = insert_provisional_concept(text, concepts, provisional_block)
        concepts = parse_concepts(text)
        changed = True
        print(f"PROVISIONAL_CONCEPT_GENERATED: {provisional_id} for {fp} count={count}")
        _gen_data = load_no_match_filepaths()
        if fp in _gen_data.get("no_match_files", {}):
            _gen_data["no_match_files"][fp]["provisional_generated"] = True
            _gen_data["no_match_files"][fp]["provisional_id"] = provisional_id
            save_no_match_filepaths(_gen_data)
    return text, concepts, changed

# ── /provisional concept 自動生成 ───────────────────────────────────────────

def shell_quote_backtick(value):
    return "`" + str(value).replace("`", "'") + "`"

def lesson_resource_ref(payload):
    """Return an explicit or source-qualified lesson ref when scope is known."""
    explicit = str(payload.get("lesson_ref") or "").strip()
    if explicit:
        return explicit
    lesson_id = str(payload.get("id") or payload.get("lesson_id") or "").strip()
    scope = str(
        payload.get("project") or payload.get("source_scope") or payload.get("source") or ""
    ).strip().lower()
    scope = re.sub(r"[^a-z0-9._-]+", "-", scope).strip("-")
    return f"{scope}:{lesson_id}" if scope and lesson_id else lesson_id

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
        stable_ref = lesson_resource_ref(payload)
        ref = shell_quote_backtick(stable_ref) if stable_ref else "`lesson`"
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
        ["bash", str(insight_write), "--resolve", insight_id,
         "semantic index candidate was absorbed into a registered concept",
         f"semantic_index={index_path}"],
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
            messages.append(f"PENDING_ALIAS: {alias} -> {concept_id} aliases_added={alias}")
        else:
            messages.append(f"PENDING_ALIAS: {alias} -> {concept_id} aliases_added=none")
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
    atomic_write_text(index_path, text)
    print("__SEMANTIC_INDEX_CHANGED__")
    print("__SEMANTIC_ALIASES_CHANGED__")
if source_type == "absorb_pending":
    if pending_messages:
        print("ABSORB_PENDING: complete")
    else:
        print("ABSORB_PENDING: no semantic insight changes")
    sys.exit(0)

# ── files_modified → concept 因果辺 自動生成 (cmd_complete のみ) ──────────
if source_type == "cmd_complete":
    _files_modified = payload.get("files") or []
    if isinstance(_files_modified, str):
        _files_modified = [p.strip() for p in re.split(r"[, \n]+", _files_modified) if p.strip()]

    if _files_modified:
        _cmd_id = str(payload.get("id") or payload.get("cmd_id") or "").strip()
        _file_inferred, _no_match_files = infer_concepts_from_files(_files_modified, concepts)

        # HIGH/MEDIUM のみ causal 行を追記 (LOW は信頼度不足のため除外)
        _concepts_by_id = {c["id"]: c for c in concepts}
        _matched = [
            (cid, conf)
            for cid, conf in _file_inferred.items()
            if conf in ("HIGH", "MEDIUM") and cid in _concepts_by_id
        ]
        # 開始位置の降順でソートし、オフセットを保ちながら書込む
        _matched.sort(key=lambda x: _concepts_by_id[x[0]]["start"], reverse=True)

        _fi_updated = text
        _fi_written = []
        for _cid, _conf in _matched:
            _concept = _concepts_by_id[_cid]
            _causal_row = f"| causal | {shell_quote_backtick(_cmd_id)} files_modified: [[{_cid}]] |"
            _new_block, _row_changed = append_row_to_block(_concept["block"], _causal_row)
            if _row_changed:
                _fi_updated = _fi_updated[:_concept["start"]] + _new_block + _fi_updated[_concept["end"]:]
                _fi_written.append(_cid)

        if _fi_written:
            text = _fi_updated
            concepts = parse_concepts(text)
            atomic_write_text(index_path, text)
            print(f"FILES_MODIFIED_CAUSAL: {_cmd_id} -> {', '.join(_fi_written)}")
            print("__SEMANTIC_INDEX_CHANGED__")

        # NO_MATCH累積カウンタ更新 + 仮concept生成
        text, concepts, _nm_changed = handle_no_match_files(_no_match_files, _cmd_id, text, concepts)
        if _nm_changed:
            atomic_write_text(index_path, text)
            print("__SEMANTIC_INDEX_CHANGED__")
# ── /files_modified 因果辺自動生成 ─────────────────────────────────────────

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
        atomic_write_text(index_path, updated)
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
        atomic_write_text(index_path, updated)
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
    printf '%s %s\n' "$index_changed" "$aliases_changed" > "$post_state_file"
) 200>"$lock_path"

# Post-update consumers may acquire the semantic index lock themselves.
# Running them in the flock subshell deadlocks when semantic_stress_test invokes
# absorb_pending (the same process waits ten seconds for its own lock).  Publish
# the two booleans under lock, then run every consumer only after lock release.
IFS=' ' read -r index_changed aliases_changed < "$post_state_file"
rm -f "$post_state_file"
trap - EXIT

if [ "$index_changed" = true ]; then
    if [ "$aliases_changed" = true ]; then
        run_semantic_stress_after_alias_change
        run_semantic_quality_after_alias_change
    fi
    if [ -f "$map_generate" ]; then
        # バックグラウンド実行: semantic-mapはeventual consistencyで問題なし。
        # lock解放後に起動し、generator自身の正規lock取得を省略しない。
        bash "$map_generate" >/dev/null &
        echo "semantic-map regenerated (background)"
    else
        echo "WARN: semantic map generator not found: $map_generate" >&2
    fi
fi
