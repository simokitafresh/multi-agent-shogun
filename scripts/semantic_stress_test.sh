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
  --quality-fixture <path>       Fixed regression fixture path (default: tests/fixtures/semantic_quality_test_set.json)
  --auto-test-set-add            Promote high-frequency NO_MATCH terms into the fixture after blind non-regression
  --no-insights                  Do not write candidate aliases to insights.yaml

Sources:
  lord   recent queue/lord_conversation.jsonl content/summary text
  cmds   recent queue/shogun_to_karo.yaml purpose/title-like lines
  file   one query per non-empty line from --file

Improvement judgement uses blind random sampling only. The fixed 50-word quality
fixture is regression detection only, never the improvement gate.
EOF
}

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
script_dir="${_self%/scripts/semantic_stress_test.sh}"
source_mode="all"
query_file=""
limit=20
baseline_path="${SEMANTIC_STRESS_BASELINE:-$script_dir/logs/semantic_stress_baseline.json}"
log_path="${SEMANTIC_STRESS_LOG:-$script_dir/logs/semantic_stress_test.log}"
insights_path="${INSIGHTS_FILE:-$script_dir/queue/insights.yaml}"
insights_archive_path="${SEMANTIC_STRESS_INSIGHTS_ARCHIVE:-$script_dir/queue/archive/insights_archive.yaml}"
quality_fixture="${SEMANTIC_QUALITY_FIXTURE:-$script_dir/tests/fixtures/semantic_quality_test_set.json}"
auto_test_set_add="${SEMANTIC_STRESS_AUTO_TEST_SET_ADD:-false}"
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
        --quality-fixture)
            quality_fixture="${2:?--quality-fixture requires a path}"
            shift 2
            ;;
        --auto-test-set-add)
            auto_test_set_add=true
            shift
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
case "$auto_test_set_add" in
    true|false) ;;
    *)
        echo "ERROR: SEMANTIC_STRESS_AUTO_TEST_SET_ADD must be true or false: $auto_test_set_add" >&2
        exit 2
        ;;
esac

if { [ "$source_mode" = "file" ] || [ "$source_mode" = "all" ]; } && [ -z "$query_file" ]; then
    query_file="$script_dir/context/semantic-map.md"
fi
if { [ "$source_mode" = "file" ] || [ "$source_mode" = "all" ]; } && [ ! -f "$query_file" ]; then
    echo "ERROR: query file not found: $query_file" >&2
    exit 1
fi

semantic_search="${SEMANTIC_SEARCH_CMD:-$script_dir/scripts/semantic_search.sh}"
insight_write="${SEMANTIC_INSIGHT_WRITE:-$script_dir/scripts/insight_write.sh}"
quality_test="${SEMANTIC_QUALITY_TEST_CMD:-$script_dir/scripts/semantic_quality_test.sh}"
semantic_index_update="${SEMANTIC_INDEX_UPDATE_CMD:-$script_dir/scripts/semantic_index_update.sh}"
if [ ! -f "$semantic_search" ]; then
    echo "ERROR: semantic_search not found: $semantic_search" >&2
    exit 1
fi
if [ "$auto_test_set_add" = true ] && [ ! -f "$quality_test" ]; then
    echo "ERROR: semantic_quality_test not found: $quality_test" >&2
    exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
queries_jsonl="$tmp_dir/queries.jsonl"
queries_tsv="$tmp_dir/queries.tsv"
results_tsv="$tmp_dir/results.tsv"
results_jsonl="$tmp_dir/results.jsonl"
summary_json="$tmp_dir/summary.json"

python3 - "$source_mode" "$limit" "$script_dir" "$query_file" "$queries_jsonl" <<'PY'
import json
import os
import random
import re
import sys
from pathlib import Path

source_mode, limit_raw, root_raw, query_file_raw, out_raw = sys.argv[1:6]
limit = int(limit_raw)
root = Path(root_raw)
query_file = Path(query_file_raw) if query_file_raw else None
out_path = Path(out_raw)
rng = random.Random(os.environ.get("SEMANTIC_STRESS_RANDOM_SEED") or None)

def clean(text):
    text = re.sub(r"<[^>]+>", " ", str(text))
    text = re.sub(r"`[^`]*`", " ", text)
    text = re.sub(r"https?://\S+", " ", text)
    text = re.sub(r"\s+", " ", text).strip(" -:：、。")
    return text[:180]

KNOWN_JUNK_RE = re.compile(
    r"(?ix)"
    r"<\s*/?\s*(?:task-notification|task-id|tool-use-id|output-file)\b"
    r"|(?:\b|_)(?:toolu_[A-Za-z0-9_-]+|task[-_]?id|tool[-_]?use[-_]?id)(?:\b|_)"
)

def has_japanese(text):
    return re.search(r"[\u3040-\u30FF\u3400-\u9FFF]", str(text)) is not None

def has_english_word_min3(text):
    return re.search(r"[A-Za-z]{3,}", str(text)) is not None

def should_keep_query(query):
    query = str(query).strip()
    if KNOWN_JUNK_RE.search(query):
        return False
    if len(query) < 2:
        return False
    if not has_japanese(query) and not has_english_word_min3(query):
        return False
    return True

def emit(source, query, rows, seen):
    query = clean(query)
    if not should_keep_query(query):
        return
    key = (source, query.casefold())
    if key in seen:
        return
    seen.add(key)
    rows.append({"source": source, "query": query})

def emit_blind_random_sample(source, queries, rows, seen):
    # 改善判定はブラインドテスト(ランダムサンプリング)のみ。固定50語は回帰検知専用。
    cleaned = []
    local_seen = set()
    for query in queries:
        query = clean(query)
        if not should_keep_query(query):
            continue
        key = query.casefold()
        if key in local_seen:
            continue
        local_seen.add(key)
        cleaned.append(query)
    for query in rng.sample(cleaned, min(limit, len(cleaned))):
        emit(source, query, rows, seen)

def lord_queries(rows, seen):
    path = Path(__import__("os").environ.get("SEMANTIC_STRESS_LORD_LOG", root / "queue" / "lord_conversation.jsonl"))
    if not path.exists():
        return
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()[-300:]
    pool = []
    for line in reversed(lines):
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("direction") != "inbound":
            continue
        for key in ("summary", "content", "message", "text"):
            if key in obj and obj[key]:
                pool.append(obj[key])
                break
    emit_blind_random_sample("lord", pool, rows, seen)

def cmd_queries(rows, seen):
    path = Path(__import__("os").environ.get("SEMANTIC_STRESS_CMD_QUEUE", root / "queue" / "shogun_to_karo.yaml"))
    if not path.exists():
        return
    purpose_re = re.compile(r"^\s*(?:purpose|title|summary):\s*(.+?)\s*$")
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    pool = []
    for line in reversed(lines):
        match = purpose_re.match(line)
        if not match:
            continue
        value = match.group(1).strip().strip("'\"")
        pool.append(value)
    emit_blind_random_sample("cmds", pool, rows, seen)

def file_queries(rows, seen):
    if not query_file or not query_file.exists():
        return
    pool = []
    for line in query_file.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("|"):
            continue
        stripped = re.sub(r"^[-*]\s+", "", stripped)
        pool.append(stripped)
    emit_blind_random_sample("file", pool, rows, seen)

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

python3 - "$queries_jsonl" > "$queries_tsv" <<'PY'
import json
import sys
from pathlib import Path

for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    row = json.loads(line)
    print(f'{row["source"]}\t{row["query"]}')
PY

_nproc="${SEMANTIC_STRESS_PARALLEL:-4}"
_job_count=0
_idx=0
while IFS=$'\t' read -r source_name query; do
    [ -n "$query" ] || continue
    (
        _out_file="$tmp_dir/search_${_idx}.out"
        _status="hit"
        _rc=0
        if SEMANTIC_DISABLE_LLM=1 SEMANTIC_DISABLE_CAUSAL=1 bash "$semantic_search" "$query" >"$_out_file" 2>&1; then
            _status="hit"
        else
            _rc=$?
            [ "$_rc" -eq 1 ] && _status="no_match" || _status="error"
        fi
        _first_line="$(awk 'NR == 1 { print; exit }' "$_out_file")"
        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$source_name" \
            "${query//$'\t'/ }" \
            "$_status" \
            "$_rc" \
            "${_first_line//$'\t'/ }" > "$tmp_dir/result_${_idx}.tsv"
    ) &
    _job_count=$((_job_count + 1))
    _idx=$((_idx + 1))
    if [[ "$_job_count" -ge "$_nproc" ]]; then
        wait
        _job_count=0
    fi
done < "$queries_tsv"
wait
for (( _i=0; _i<_idx; _i++ )); do
    cat "$tmp_dir/result_${_i}.tsv" 2>/dev/null || true
done > "$results_tsv"

python3 - "$results_tsv" > "$results_jsonl" <<'PY'
import json
import sys
from pathlib import Path

for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    source, query, status, rc, first_line = line.split("\t", 4)
    print(json.dumps(
        {
            "source": source,
            "query": query,
            "status": status,
            "exit_code": int(rc),
            "first_line": first_line,
        },
        ensure_ascii=False,
    ))
PY

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

KNOWN_JUNK_RE = re.compile(
    r"(?ix)"
    r"<\s*/?\s*(?:task-notification|task-id|tool-use-id|output-file)\b"
    r"|(?:\b|_)(?:toolu_[A-Za-z0-9_-]+|task[-_]?id|tool[-_]?use[-_]?id)(?:\b|_)"
)

def has_japanese(text):
    return re.search(r"[\u3040-\u30FF\u3400-\u9FFF]", str(text)) is not None

def has_english_word_min3(text):
    return re.search(r"[A-Za-z]{3,}", str(text)) is not None

def passes_two_layer_filter(text):
    text = str(text).strip()
    if KNOWN_JUNK_RE.search(text):
        return False
    if len(text) < 2:
        return False
    if not has_japanese(text) and not has_english_word_min3(text):
        return False
    return True

OPERATIONAL_NOISE_RE = re.compile(
    r"(?ix)"
    r"^【[^】]+】"
    r"|(?:\b|_)(?:alert|warning|info)(?:\b|_)"
    r"|\bci\s*(?:red|green)\b"
    r"|\bci緑\b"
    r"|\bgate\s*(?:clear|pass|warn|block)?\b"
    r"|\brun\s+\d+\b"
    r"|\bpane_cmd\b"
    # ASCII boundary: Python \b treats Japanese letters as \w, so "…ようにinbox1"
    # never matched \binbox and leaked as a NO_MATCH insight (2026-09-01 12:46).
    r"|(?<![A-Za-z0-9_])inbox\d*(?![A-Za-z0-9_])"
    r"|復帰"
    r"|ダミー"
    r"|起動alert"
    r"|三層ループalert"
    r"|context鮮度alert"
    r"|cli再起動"
    r"|infoバッチ"
    r"|\bmonitor\s+event\b"
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

try:
    MIN_INSIGHT_QUERY_CHARS = int(__import__("os").environ.get("SEMANTIC_STRESS_MIN_INSIGHT_CHARS", "12"))
except (ValueError, TypeError):
    MIN_INSIGHT_QUERY_CHARS = 12
try:
    HIGH_FREQUENCY_NO_MATCH_MIN_COUNT = int(__import__("os").environ.get("SEMANTIC_STRESS_HIGH_FREQUENCY_MIN_COUNT", "2"))
except (ValueError, TypeError):
    HIGH_FREQUENCY_NO_MATCH_MIN_COUNT = 2

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
    if not passes_two_layer_filter(query) or not passes_two_layer_filter(alias):
        return False
    if semantic_query_length(query) < MIN_INSIGHT_QUERY_CHARS and not has_concept_hint(query) and not has_concept_hint(alias):
        return False
    return True

GENERIC_SHORT_HIT_RE = re.compile(
    r"^(?:記憶|memory|context|仕組み|手順|確認|テスト|test|DB|API)$",
    re.IGNORECASE,
)

def first_line_concept(row):
    match = re.match(r"^##\s+([A-Za-z0-9_-]+)\s+—\s+(.+)$", str(row.get("first_line", "")))
    if not match:
        return "", ""
    return match.group(1), match.group(2).strip()

def dirty_hit_reason(row):
    query = str(row.get("query", "")).strip()
    concept_id, concept_label = first_line_concept(row)
    if row.get("status") != "hit" or not concept_id:
        return ""
    if GENERIC_SHORT_HIT_RE.fullmatch(query):
        return f"generic_short_query:{query}->{concept_id}"
    alias = alias_candidate(query)
    if alias and semantic_query_length(alias) >= MIN_INSIGHT_QUERY_CHARS and concept_label and alias not in concept_label and concept_label not in alias:
        return f"long_query_maybe_misrouted:{alias}->{concept_id}"
    return ""

sources = {}
total = len(rows)
hits = sum(1 for row in rows if row["status"] == "hit")
no_matches = [row for row in rows if row["status"] == "no_match"]
errors = [row for row in rows if row["status"] == "error"]
dirty_hit_candidates = []
for row in rows:
    reason = dirty_hit_reason(row)
    if reason:
        candidate = {
            "query": row["query"],
            "source": row["source"],
            "first_line": row.get("first_line", ""),
            "reason": reason,
        }
        concept_id, concept_label = first_line_concept(row)
        if concept_id:
            candidate["concept_id"] = concept_id
            candidate["concept_label"] = concept_label
        dirty_hit_candidates.append(candidate)

for source, source_rows in sorted(by_source.items()):
    source_hits = sum(1 for row in source_rows if row["status"] == "hit")
    sources[source] = {
        "total": len(source_rows),
        "hits": source_hits,
        "no_match": sum(1 for row in source_rows if row["status"] == "no_match"),
        "errors": sum(1 for row in source_rows if row["status"] == "error"),
        "hit_rate": round(source_hits / len(source_rows) * 100, 1) if source_rows else 0.0,
    }

candidate_counts = Counter()
candidate_rows = {}
for row in no_matches:
    alias = alias_candidate(row["query"])
    key = alias.casefold()
    if alias and should_record_no_match(row, alias) and is_semantic_wiki_target(alias):
        candidate_counts[key] += 1
        candidate_rows.setdefault(key, {"alias": alias, "source": row["source"], "query": row["query"]})

candidates = []
seen = set()
high_frequency_no_match_terms = []
for key, count in candidate_counts.most_common():
    row = candidate_rows[key]
    if key not in seen:
        seen.add(key)
        candidates.append(row)
    if count >= HIGH_FREQUENCY_NO_MATCH_MIN_COUNT:
        high_frequency_no_match_terms.append({**row, "count": count})

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
    "evaluation_mode": "blind_random_sampling",
    "improvement_judgement": "blind_hit_rate_non_regression_only",
    "fixed_50_test_role": "regression_detection_only",
    "total": total,
    "hits": hits,
    "no_match": len(no_matches),
    "errors": len(errors),
    "hit_rate": round(hits / total * 100, 1) if total else 0.0,
    "sources": sources,
    "candidate_aliases": candidates,
    "high_frequency_no_match_terms": high_frequency_no_match_terms,
    "dirty_hit_candidates": dirty_hit_candidates,
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
        # 重複発行ガード: 同一aliasのinsightが既に存在(pending/resolved問わず)するならスキップ。
        # resolved済みクエリの再発行が再蓄積の根因(2026-06-10実証: 18:13 resolve→21:06同一クエリ
        # 再発行→pending 51→0→28再蓄積。生成器が回る限り無限再生成される構造)
        # アーカイブも確認: gate_shogun_startup.shがdone/resolved等をinsights_archive.yamlへ
        # 退避するため、live insights.yamlのみの確認だとアーカイブ後に同一低価値単発文が
        # 「未出現」に見えて再pending化する(cmd_karo_hotfix_cycle_health_insight_churn_202607041407実証)
        if [ -f "$insights_path" ] && grep -qF "[[$alias]]" "$insights_path"; then
            continue
        fi
        if [ -f "$insights_archive_path" ] && grep -qF "[[$alias]]" "$insights_archive_path"; then
            continue
        fi
        if [ -x "$insight_write" ] || [ -f "$insight_write" ]; then
            INSIGHTS_FILE="$insights_path" bash "$insight_write" \
                "[[$alias]] semantic_stress_test candidate_aliases: NO_MATCH source=$source_name query=$original_query" \
                low semantic_stress_test >/dev/null
        fi
    done < "$tmp_dir/candidates.tsv"
fi

python3 - "$summary_json" > "$tmp_dir/high_frequency_no_match_terms.tsv" <<'PY'
import json
import sys
summary = json.load(open(sys.argv[1], encoding="utf-8"))
for item in summary.get("high_frequency_no_match_terms", []):
    print(f'{item["alias"]}\t{item["source"]}\t{item["query"]}\t{item["count"]}')
PY

if [ "$write_insights" = true ] && [ -s "$tmp_dir/high_frequency_no_match_terms.tsv" ]; then
    while IFS=$'\t' read -r alias source_name original_query frequency_count; do
        [ -n "$alias" ] || continue
        # 重複発行ガード(candidate_aliasesと同様): test_set_candidate表記を含む既存があればスキップ
        # (アーカイブも確認。理由は上のcandidate_aliasesガード参照)
        if [ -f "$insights_path" ] && grep -F "[[$alias]]" "$insights_path" | grep -q "test_set_candidate"; then
            continue
        fi
        if [ -f "$insights_archive_path" ] && grep -F "[[$alias]]" "$insights_archive_path" | grep -q "test_set_candidate"; then
            continue
        fi
        if [ -x "$insight_write" ] || [ -f "$insight_write" ]; then
            INSIGHTS_FILE="$insights_path" bash "$insight_write" \
                "[[$alias]] semantic_stress_test test_set_candidate: high_frequency_NO_MATCH count=$frequency_count source=$source_name query=$original_query quality_gate=blind_hit_rate_non_regression fixed_50_role=regression_detection_only" \
                medium semantic_stress_test >/dev/null
        fi
    done < "$tmp_dir/high_frequency_no_match_terms.tsv"
fi

if [ "$write_insights" = true ] && [ "${SEMANTIC_STRESS_ABSORB_PENDING:-1}" != "0" ] && [ -f "$semantic_index_update" ]; then
    if SEMANTIC_STRESS_AFTER_ALIAS_CHANGE=0 SEMANTIC_QUALITY_AFTER_ALIAS_CHANGE=0 \
        SEMANTIC_INSIGHTS_PATH="$insights_path" \
        bash "$semantic_index_update" absorb_pending '{}' >/dev/null 2>&1; then
        :
    else
        echo "WARN: semantic stress pending absorb failed" >&2
    fi
fi

if [ "$auto_test_set_add" = true ] && [ -s "$tmp_dir/high_frequency_no_match_terms.tsv" ]; then
    before_summary="$(bash "$quality_test" --fixture "$quality_fixture" 2>&1)" || {
        before_rc=$?
        printf '%s\n' "$before_summary" >&2
        echo "ERROR: fixed 50-word regression detection failed before test-set auto add" >&2
        exit "$before_rc"
    }

    python3 - "$quality_fixture" "$tmp_dir/high_frequency_no_match_terms.tsv" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

fixture_path = Path(sys.argv[1])
candidate_path = Path(sys.argv[2])
data = json.loads(fixture_path.read_text(encoding="utf-8"))
entries = data.setdefault("entries", [])
existing = {str(entry.get("query", "")).casefold() for entry in entries}
added = 0
for line in candidate_path.read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    alias, source, query, count = line.split("\t", 3)
    if query.casefold() in existing:
        continue
    entries.append(
        {
            "query": query,
            "expected_concept": None,
            "source": "semantic_stress_test:auto_test_set_add",
            "candidate_alias": alias,
            "no_match_frequency": int(count),
            "quality_gate": "blind_hit_rate_non_regression",
            "fixed_50_test_role": "regression_detection_only",
            "added_at": datetime.now(timezone.utc).isoformat(),
        }
    )
    existing.add(query.casefold())
    added += 1
data["auto_growth"] = {
    "last_source": "semantic_stress_test",
    "last_gate": "blind_hit_rate_non_regression",
    "fixed_50_test_role": "regression_detection_only",
    "last_added_count": added,
    "updated_at": datetime.now(timezone.utc).isoformat(),
}
fixture_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(added)
PY

    after_summary="$(bash "$quality_test" --fixture "$quality_fixture" 2>&1)" || {
        after_rc=$?
        printf '%s\n' "$after_summary" >&2
        echo "ERROR: fixed 50-word regression detection failed after test-set auto add" >&2
        exit "$after_rc"
    }
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
print(f'evaluation_mode={summary["evaluation_mode"]} improvement_judgement={summary["improvement_judgement"]} fixed_50_test_role={summary["fixed_50_test_role"]}')
for source, data in summary["sources"].items():
    print(f'  {source}: hit_rate={data["hit_rate"]}% hits={data["hits"]}/{data["total"]} no_match={data["no_match"]} errors={data["errors"]}')
print(f'candidate_aliases={len(summary["candidate_aliases"])}')
print(f'high_frequency_NO_MATCH={len(summary.get("high_frequency_no_match_terms", []))}')
print(f'dirty_hit_candidates={len(summary.get("dirty_hit_candidates", []))}')
for item in summary["candidate_aliases"][:10]:
    print(f'  - {item["alias"]} ({item["source"]})')
for item in summary.get("dirty_hit_candidates", [])[:10]:
    print(f'  - DIRTY_HIT {item["query"]} ({item["source"]}) -> {item.get("concept_id", "")}: {item["reason"]}')
if summary["baseline_created"]:
    print(f'baseline: created {baseline_path}')
else:
    diff = summary.get("diff") or {}
    print(f'before_after: hit_rate_delta={diff.get("hit_rate_delta", 0)} no_match_delta={diff.get("no_match_delta", 0)} total_delta={diff.get("total_delta", 0)}')
print(f'log: {log_path}')
PY
