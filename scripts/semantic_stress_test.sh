#!/usr/bin/env bash
# semantic_stress_test.sh — Measure semantic_search hit rate and feed NO_MATCH aliases.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash scripts/semantic_stress_test.sh [options]

Options:
  --source <lord|cmds|file|all>  Query source to test (default: all)
  --file <path>                  Query file for --source file or all
  --limit <n>                    Max queries per source (default: 20)
  --baseline <path>              Baseline JSON path (default: logs/semantic_stress_baseline.json)
  --log <path>                   JSONL log path (default: logs/semantic_stress_test.log)
  --insights <path>              insights.yaml path for candidate alias output
  --no-insights                  Do not write candidate aliases to insights.yaml

Sources:
  lord   recent queue/lord_conversation.jsonl content/summary text
  cmds   recent queue/shogun_to_karo.yaml purpose/title-like lines
  file   one query per non-empty line from --file

The script runs semantic_search.sh with LLM and causal expansion disabled so the
metric covers alias-layer hit rate and cannot be distorted by causal timeout.
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_mode="all"
query_file=""
limit=20
baseline_path="${SEMANTIC_STRESS_BASELINE:-$script_dir/logs/semantic_stress_baseline.json}"
log_path="${SEMANTIC_STRESS_LOG:-$script_dir/logs/semantic_stress_test.log}"
insights_path="${INSIGHTS_FILE:-$script_dir/queue/insights.yaml}"
write_insights=true

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --source)
            source_mode="${2:?--source requires a value}"
            shift 2
            ;;
        --file)
            query_file="${2:?--file requires a path}"
            shift 2
            ;;
        --limit)
            limit="${2:?--limit requires a value}"
            shift 2
            ;;
        --baseline)
            baseline_path="${2:?--baseline requires a path}"
            shift 2
            ;;
        --log)
            log_path="${2:?--log requires a path}"
            shift 2
            ;;
        --insights)
            insights_path="${2:?--insights requires a path}"
            shift 2
            ;;
        --no-insights)
            write_insights=false
            shift
            ;;
        *)
            echo "ERROR: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

case "$source_mode" in
    lord|cmds|file|all) ;;
    *)
        echo "ERROR: --source must be lord, cmds, file, or all: $source_mode" >&2
        exit 2
        ;;
esac

if ! [[ "$limit" =~ ^[0-9]+$ ]] || [ "$limit" -lt 1 ]; then
    echo "ERROR: --limit must be a positive integer: $limit" >&2
    exit 2
fi

if { [ "$source_mode" = "file" ] || [ "$source_mode" = "all" ]; } && [ -z "$query_file" ]; then
    query_file="$script_dir/context/semantic-map.md"
fi
if { [ "$source_mode" = "file" ] || [ "$source_mode" = "all" ]; } && [ ! -f "$query_file" ]; then
    echo "ERROR: query file not found: $query_file" >&2
    exit 1
fi

semantic_search="${SEMANTIC_SEARCH_CMD:-$script_dir/scripts/semantic_search.sh}"
insight_write="${SEMANTIC_INSIGHT_WRITE:-$script_dir/scripts/insight_write.sh}"
if [ ! -f "$semantic_search" ]; then
    echo "ERROR: semantic_search not found: $semantic_search" >&2
    exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
queries_jsonl="$tmp_dir/queries.jsonl"
results_jsonl="$tmp_dir/results.jsonl"
summary_json="$tmp_dir/summary.json"

python3 - "$source_mode" "$limit" "$script_dir" "$query_file" "$queries_jsonl" <<'PY'
import json
import re
import sys
from pathlib import Path

source_mode, limit_raw, root_raw, query_file_raw, out_raw = sys.argv[1:6]
limit = int(limit_raw)
root = Path(root_raw)
query_file = Path(query_file_raw) if query_file_raw else None
out_path = Path(out_raw)

def clean(text):
    text = re.sub(r"<[^>]+>", " ", str(text))
    text = re.sub(r"`[^`]*`", " ", text)
    text = re.sub(r"https?://\S+", " ", text)
    text = re.sub(r"\s+", " ", text).strip(" -:：、。")
    return text[:180]

def emit(source, query, rows, seen):
    query = clean(query)
    key = (source, query.casefold())
    if len(query) < 2 or key in seen:
        return
    seen.add(key)
    rows.append({"source": source, "query": query})

def lord_queries(rows, seen):
    path = Path(__import__("os").environ.get("SEMANTIC_STRESS_LORD_LOG", root / "queue" / "lord_conversation.jsonl"))
    if not path.exists():
        return
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()[-300:]
    for line in reversed(lines):
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("direction") != "inbound":
            continue
        for key in ("summary", "content", "message", "text"):
            if key in obj and obj[key]:
                emit("lord", obj[key], rows, seen)
                break
        if sum(1 for row in rows if row["source"] == "lord") >= limit:
            break

def cmd_queries(rows, seen):
    path = Path(__import__("os").environ.get("SEMANTIC_STRESS_CMD_QUEUE", root / "queue" / "shogun_to_karo.yaml"))
    if not path.exists():
        return
    purpose_re = re.compile(r"^\s*(?:purpose|title|summary):\s*(.+?)\s*$")
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    for line in reversed(lines):
        match = purpose_re.match(line)
        if not match:
            continue
        value = match.group(1).strip().strip("'\"")
        emit("cmds", value, rows, seen)
        if sum(1 for row in rows if row["source"] == "cmds") >= limit:
            break

def file_queries(rows, seen):
    if not query_file or not query_file.exists():
        return
    for line in query_file.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("|"):
            continue
        stripped = re.sub(r"^[-*]\s+", "", stripped)
        emit("file", stripped, rows, seen)
        if sum(1 for row in rows if row["source"] == "file") >= limit:
            break

rows = []
seen = set()
if source_mode in {"lord", "all"}:
    lord_queries(rows, seen)
if source_mode in {"cmds", "all"}:
    cmd_queries(rows, seen)
if source_mode in {"file", "all"}:
    file_queries(rows, seen)

with out_path.open("w", encoding="utf-8") as f:
    for row in rows:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")
PY

if [ ! -s "$queries_jsonl" ]; then
    echo "ERROR: no queries collected for source=$source_mode" >&2
    exit 1
fi

while IFS= read -r row; do
    query="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["query"])' <<< "$row")"
    source_name="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["source"])' <<< "$row")"
    output_file="$tmp_dir/search.out"
    status="hit"
    rc=0
    if SEMANTIC_DISABLE_LLM=1 SEMANTIC_DISABLE_CAUSAL=1 bash "$semantic_search" "$query" >"$output_file" 2>&1; then
        status="hit"
    else
        rc=$?
        if [ "$rc" -eq 1 ]; then
            status="no_match"
        else
            status="error"
        fi
    fi
    python3 - "$source_name" "$query" "$status" "$rc" "$output_file" >> "$results_jsonl" <<'PY'
import json
import sys
from pathlib import Path

source, query, status, rc, output_path = sys.argv[1:6]
output = Path(output_path).read_text(encoding="utf-8", errors="replace")
print(json.dumps(
    {
        "source": source,
        "query": query,
        "status": status,
        "exit_code": int(rc),
        "first_line": output.splitlines()[0] if output.splitlines() else "",
    },
    ensure_ascii=False,
))
PY
done < "$queries_jsonl"

python3 - "$results_jsonl" "$baseline_path" "$summary_json" <<'PY'
import json
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

results_path, baseline_raw, summary_raw = sys.argv[1:4]
baseline_path = Path(baseline_raw)
summary_path = Path(summary_raw)

rows = [json.loads(line) for line in Path(results_path).read_text(encoding="utf-8").splitlines() if line.strip()]
by_source = defaultdict(list)
for row in rows:
    by_source[row["source"]].append(row)

def alias_candidate(query):
    text = re.sub(r"`[^`]*`", " ", query)
    text = re.sub(r"https?://\S+", " ", text)
    text = re.sub(r"\b\d{4}-\d{2}-\d{2}\b", " ", text)
    text = re.sub(r"\bcmd_[A-Za-z0-9_]+\b", " ", text)
    text = re.sub(r"[/._:,+#|()\[\]{}<>\"'=-]+", " ", text)
    text = re.sub(r"\s+", " ", text).strip(" ・、。:：-")
    for part in re.split(r"[。．.!?\n]|[、,]\s*", text):
        part = re.sub(r"\s+", " ", part).strip(" ・、。:：-")
        if len(part) >= 2:
            return part[:60]
    return ""

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

CONCEPT_HINT_RE = re.compile(
    r"(?ix)"
    r"意味検索|セマンティック|semantic|aliases?|alias|概念|索引|辞書|obsidian|"
    r"gate|hook|cmd|inbox|bulletin|insight|memory|context|lesson|"
    r"自動化|計測|検証|品質|成長|因果|学習|設計|実装|修正|改善|"
    r"CI|DB|API|frontend|backend|deploy|review|test"
)

STRUCTURAL_METADATA_RE = re.compile(
    r"(?ix)"
    r"^(?:title|type|node\s*id)\b"
    r"|^modules$"
)

MIN_INSIGHT_QUERY_CHARS = int(__import__("os").environ.get("SEMANTIC_STRESS_MIN_INSIGHT_CHARS", "12"))

def semantic_query_length(text):
    return len(re.sub(r"\s+", "", str(text)))

def has_concept_hint(text):
    return bool(CONCEPT_HINT_RE.search(str(text)))

def is_semantic_wiki_target(target):
    target_s = str(target).strip()
    target_n = re.sub(r"\s+", " ", target_s.casefold()).strip()
    if not target_n:
        return False
    if re.fullmatch(r"cmd_[a-z0-9_]+", target_n):
        return False
    if re.fullmatch(r"l\d+[a-z0-9_-]*", target_n):
        return False
    if re.fullmatch(r"ls[-_]?\d+[a-z0-9_-]*", target_n):
        return False
    if OPERATIONAL_NOISE_RE.search(target_s) or OPERATIONAL_NOISE_RE.search(target_n):
        return False
    if STRUCTURAL_METADATA_RE.search(target_n):
        return False
    return bool(target_n)

def should_record_no_match(row, alias):
    query = row.get("query", "")
    if semantic_query_length(query) < MIN_INSIGHT_QUERY_CHARS and not has_concept_hint(query) and not has_concept_hint(alias):
        return False
    return True

sources = {}
total = len(rows)
hits = sum(1 for row in rows if row["status"] == "hit")
no_matches = [row for row in rows if row["status"] == "no_match"]
errors = [row for row in rows if row["status"] == "error"]

for source, source_rows in sorted(by_source.items()):
    source_hits = sum(1 for row in source_rows if row["status"] == "hit")
    sources[source] = {
        "total": len(source_rows),
        "hits": source_hits,
        "no_match": sum(1 for row in source_rows if row["status"] == "no_match"),
        "errors": sum(1 for row in source_rows if row["status"] == "error"),
        "hit_rate": round(source_hits / len(source_rows) * 100, 1) if source_rows else 0.0,
    }

candidates = []
seen = set()
for row in no_matches:
    alias = alias_candidate(row["query"])
    key = alias.casefold()
    if alias and should_record_no_match(row, alias) and is_semantic_wiki_target(alias) and key not in seen:
        seen.add(key)
        candidates.append({"alias": alias, "source": row["source"], "query": row["query"]})

baseline = None
baseline_created = False
if baseline_path.exists() and baseline_path.stat().st_size:
    try:
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        baseline = None
if baseline is None:
    baseline_created = True

summary = {
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "total": total,
    "hits": hits,
    "no_match": len(no_matches),
    "errors": len(errors),
    "hit_rate": round(hits / total * 100, 1) if total else 0.0,
    "sources": sources,
    "candidate_aliases": candidates,
    "status_counts": dict(Counter(row["status"] for row in rows)),
    "baseline_created": baseline_created,
}

if baseline and baseline.get("total"):
    summary["baseline"] = {
        "timestamp": baseline.get("timestamp", ""),
        "hit_rate": baseline.get("hit_rate", 0.0),
        "total": baseline.get("total", 0),
    }
    summary["diff"] = {
        "hit_rate_delta": round(summary["hit_rate"] - float(baseline.get("hit_rate", 0.0)), 1),
        "no_match_delta": summary["no_match"] - int(baseline.get("no_match", 0)),
        "total_delta": summary["total"] - int(baseline.get("total", 0)),
    }
else:
    summary["baseline"] = None
    summary["diff"] = None

summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
if baseline_created:
    baseline_path.parent.mkdir(parents=True, exist_ok=True)
    baseline_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

if [ "$write_insights" = true ]; then
    python3 - "$summary_json" > "$tmp_dir/candidates.tsv" <<'PY'
import json
import sys
summary = json.load(open(sys.argv[1], encoding="utf-8"))
for item in summary.get("candidate_aliases", []):
    print(f'{item["alias"]}\t{item["source"]}\t{item["query"]}')
PY
    while IFS=$'\t' read -r alias source_name original_query; do
        [ -n "$alias" ] || continue
        if [ -x "$insight_write" ] || [ -f "$insight_write" ]; then
            INSIGHTS_FILE="$insights_path" bash "$insight_write" \
                "[[$alias]] semantic_stress_test candidate_aliases: NO_MATCH source=$source_name query=$original_query" \
                low semantic_stress_test >/dev/null
        fi
    done < "$tmp_dir/candidates.tsv"
fi

mkdir -p "$(dirname "$log_path")"
cat "$summary_json" | tr '\n' ' ' >> "$log_path"
printf '\n' >> "$log_path"

python3 - "$summary_json" "$baseline_path" "$log_path" <<'PY'
import json
import sys
summary = json.load(open(sys.argv[1], encoding="utf-8"))
baseline_path = sys.argv[2]
log_path = sys.argv[3]
print(f'SEMANTIC_STRESS total={summary["total"]} hits={summary["hits"]} no_match={summary["no_match"]} errors={summary["errors"]} hit_rate={summary["hit_rate"]}%')
for source, data in summary["sources"].items():
    print(f'  {source}: hit_rate={data["hit_rate"]}% hits={data["hits"]}/{data["total"]} no_match={data["no_match"]} errors={data["errors"]}')
print(f'candidate_aliases={len(summary["candidate_aliases"])}')
for item in summary["candidate_aliases"][:10]:
    print(f'  - {item["alias"]} ({item["source"]})')
if summary["baseline_created"]:
    print(f'baseline: created {baseline_path}')
else:
    diff = summary.get("diff") or {}
    print(f'before_after: hit_rate_delta={diff.get("hit_rate_delta", 0)} no_match_delta={diff.get("no_match_delta", 0)} total_delta={diff.get("total_delta", 0)}')
print(f'log: {log_path}')
PY
