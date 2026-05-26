#!/usr/bin/env bash
# semantic-links: [[セマンティック辞書構想]]
# semantic_index_update.sh — Update semantic-index resources from known events.
# Usage: bash scripts/semantic_index_update.sh <cmd_complete|lesson|discussion> '<json-payload>'

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash scripts/semantic_index_update.sh <source_type> <payload_json>

source_type:
  cmd_complete  payload: {"id":"cmd_123","title":"...","purpose":"...","files":["..."]}
  lesson        payload: {"id":"L123","title":"...","enforcement":"..."}
  discussion    payload: {"timestamp":"...","summary":"..."}
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
    cmd_complete|lesson|discussion) ;;
    *)
        echo "ERROR: unknown source_type: $source_type" >&2
        exit 2
        ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
import json
import os
import re
import subprocess
import sys
from pathlib import Path

source_type, payload_raw, index_arg, insight_arg = sys.argv[1:5]
index_path = Path(index_arg)
insight_write = Path(insight_arg)
semantic_root = index_path.parent.parent.parent
insights_path = Path(os.environ.get("SEMANTIC_INSIGHTS_PATH", str(semantic_root / "queue" / "insights.yaml")))
deploy_log_path = Path(os.environ.get("SEMANTIC_DEPLOY_LOG", str(semantic_root / "logs" / "deploy_task.log")))
pending_alias_threshold = float(os.environ.get("SEMANTIC_PENDING_ALIAS_THRESHOLD", "16.0"))
no_match_scan_lines = int(os.environ.get("SEMANTIC_NO_MATCH_SCAN_LINES", "500"))
no_match_alias_limit = int(os.environ.get("SEMANTIC_NO_MATCH_ALIAS_LIMIT", "5"))

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
            if left in {"id", "label", "aliases"}:
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

def queue_unregistered_target(target, concepts, message_prefix):
    if not is_semantic_wiki_target(target):
        return False
    if norm(target) in known_terms:
        return False
    similar = format_similar_concepts(target, concepts)
    queue_insight(
        f"{message_prefix}: [[{target}]] は既存aliasesに一致なし。{similar}。概念定義とaliases追加を検討せよ",
        "low",
    )
    return True

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
        queue_insight(
            f"[[{alias}]] NO_MATCH purpose pending alias: cmd_complete時にdeploy_task.logでNO_MATCHだったpurpose。{similar}。既存概念aliasesへの自動昇格候補",
            "low",
        )
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
    ref = "`queue/lord_conversation.jsonl`"
    if timestamp:
        ref += f" {timestamp}"
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
                pending.append({"id": insight_id, "alias": candidate, "insight": insight})
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

if source_type == "cmd_complete":
    queue_no_match_purpose_aliases(concepts)

text, concepts, pending_changed, pending_messages = absorb_pending_semantic_insights(text, concepts)
for msg in pending_messages:
    print(msg)
if pending_changed:
    index_path.write_text(text, encoding="utf-8")
    print("__SEMANTIC_INDEX_CHANGED__")
    print("__SEMANTIC_ALIASES_CHANGED__")

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
payload_label = payload_id or "payload"
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

queue_insight(message, priority)

print(f"{confidence}: insight queued for {source_type}:{payload_label}")
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
