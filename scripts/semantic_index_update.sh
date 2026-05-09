#!/usr/bin/env bash
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
lock_path="${SEMANTIC_INDEX_LOCK:-${index_path}.lock}"

if [ ! -f "$index_path" ]; then
    echo "ERROR: semantic index not found: $index_path" >&2
    exit 1
fi

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
    # A payload that only contains generic source words after ID stripping still
    # has no concept signal worth sending to the insight backlog.
    generic = {"cmd", "complete", "lesson", "discussion", "payload"}
    tokens = [t for t in re.split(r"\s+", combined) if t and t not in generic]
    return not tokens

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

def append_row_to_block(block, row):
    if row in block:
        return block, False
    lines = block.rstrip("\n").splitlines()
    lines.append(row)
    return "\n".join(lines) + "\n\n", True

def candidate_aliases(source_type, payload, existing_aliases):
    existing_norm = {norm(alias) for alias in existing_aliases}
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
            if len(part) < 2 or norm(part) in existing_norm:
                continue
            aliases.append(part[:60])
            existing_norm.add(norm(part))
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

text = index_path.read_text(encoding="utf-8")
concepts = parse_concepts(text)
if not concepts:
    print("ERROR: no concepts found in semantic index", file=sys.stderr)
    sys.exit(1)

fields = flatten_text(payload)
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
    row = resource_row(source_type, payload)
    new_block, changed = append_row_to_block(best["block"], row)
    if changed:
        updated = text[: best["start"]] + new_block + text[best["end"] :]
        index_path.write_text(updated, encoding="utf-8")
        print(f"HIGH: {best['id']} updated from {source_type}:{payload_label} matched={matched}")
        print("__SEMANTIC_INDEX_CHANGED__")
    else:
        print(f"HIGH: {best['id']} already contains {source_type}:{payload_label} matched={matched}")
    sys.exit(0)

if confidence == "LOW":
    aliases_to_add = candidate_aliases(source_type, payload, best["aliases"])
    row = resource_row(source_type, payload)
    alias_block, alias_changed = append_aliases_to_block(best["block"], aliases_to_add)
    new_block, row_changed = append_row_to_block(alias_block, row)
    if alias_changed or row_changed:
        updated = text[: best["start"]] + new_block + text[best["end"] :]
        index_path.write_text(updated, encoding="utf-8")
        added = ", ".join(aliases_to_add) if alias_changed else "none"
        print(f"LOW: {best['id']} updated from {source_type}:{payload_label} matched={matched} aliases_added={added}")
        print("__SEMANTIC_INDEX_CHANGED__")
    else:
        print(f"LOW: {best['id']} already contains {source_type}:{payload_label} matched={matched}")
    sys.exit(0)
else:
    if is_noise_only_candidate(payload_id, fields):
        print(f"NONE: skipped noise-only candidate for {source_type}:{payload_label}")
        sys.exit(0)
    message = (
        f"semantic_index_update新概念候補: {source_type}:{payload_label} は "
        f"既存aliasesに一致なし。概念定義とaliases追加を検討せよ"
    )
    priority = "low"

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

print(f"{confidence}: insight queued for {source_type}:{payload_label}")
PY
    )"
    index_changed=false
    while IFS= read -r line; do
        if [ "$line" = "__SEMANTIC_INDEX_CHANGED__" ]; then
            index_changed=true
        else
            printf '%s\n' "$line"
        fi
    done <<< "$changed_flag"
    if [ "$index_changed" = true ]; then
        if [ -f "$map_generate" ]; then
            bash "$map_generate" >/dev/null
            echo "semantic-map regenerated"
        else
            echo "WARN: semantic map generator not found: $map_generate" >&2
        fi
    fi
) 200>"$lock_path"
