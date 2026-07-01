#!/usr/bin/env bash
# semantic-links: [[学習ループ]]
set -euo pipefail

_self="${BASH_SOURCE[0]}"
[[ "$_self" != /* ]] && _self="$PWD/$_self"
_scripts_dir="${_self%/*}"
SCRIPT_DIR="${_scripts_dir%/*}"
unset _self _scripts_dir
DATA_FILE="$SCRIPT_DIR/logs/lesson_impact.tsv"
CANDIDATE_MIN_SAMPLES="${LESSON_IMPACT_CANDIDATE_MIN_SAMPLES:-3}"

if [ "$#" -eq 0 ]; then
    awk -F '\t' -v candidate_min_samples="$CANDIDATE_MIN_SAMPLES" '
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function upper(s) { return toupper(s) }
function lower(s) { return tolower(s) }
function pct(num, den) { return den <= 0 ? 0 : int((num * 100.0 / den) + 0.5) }
function safe_date(ts, s) { s = trim(ts); return length(s) >= 10 ? substr(s, 1, 10) : "unknown" }
function bool_value(v, s) { s = lower(trim(v)); return s == "yes" || s == "true" || s == "1" || s == "y" }
function rate_line(id) {
    return sprintf("  %-5s injected:%-4d ref_rate:%3d%%  CLEAR:%3d%%  BLOCK:%3d%%",
        id, injected[id], pct(referenced_count[id], injected[id]),
        pct(inj_clear[id], injected[id]), pct(inj_block[id], injected[id]))
}
function ab_line(id, inj_n, with_n, inj_clear_pct, with_clear_pct, delta, sig, sign) {
    inj_n = injected[id]
    with_n = withheld[id]
    inj_clear_pct = pct(inj_clear[id], inj_n)
    with_clear_pct = pct(with_clear[id], with_n)
    delta = inj_clear_pct - with_clear_pct
    sig = (inj_n < 10 || with_n < 10 || (delta < 0 ? -delta : delta) < 20) ? "n/s" : "*"
    sign = delta >= 0 ? "+" : ""
    return sprintf("  %-5s injected:%-3d CLEAR:%3d%%  |  withheld:%-3d CLEAR:%3d%%  |  delta:%s%d%%  sig:%s",
        id, inj_n, inj_clear_pct, with_n, with_clear_pct, sign, delta, sig)
}
function better_top(id, best) {
    return best == "" || injected[id] > injected[best] || (injected[id] == injected[best] && id < best)
}
function better_low_ref(id, best, p, bp) {
    if (best == "") return 1
    p = pct(referenced_count[id], injected[id])
    bp = pct(referenced_count[best], injected[best])
    return p < bp || (p == bp && (injected[id] > injected[best] || (injected[id] == injected[best] && id < best)))
}
function better_high_block(id, best, p, bp) {
    if (best == "") return 1
    p = pct(inj_block[id], injected[id])
    bp = pct(inj_block[best], injected[best])
    return p > bp || (p == bp && (injected[id] > injected[best] || (injected[id] == injected[best] && id < best)))
}
function better_ab(id, best, d, bd) {
    if (best == "") return 1
    d = pct(inj_clear[id], injected[id]) - pct(with_clear[id], withheld[id])
    bd = pct(inj_clear[best], injected[best]) - pct(with_clear[best], withheld[best])
    return d > bd || (d == bd && id < best)
}
function print_top10(kind,    printed, pass, i, id, best) {
    delete used
    printed = 0
    for (pass = 1; pass <= 10; pass++) {
        best = ""
        for (i = 1; i <= key_count; i++) {
            id = keys[i]
            if (used[id] || injected[id] <= 0) continue
            if ((kind == "low" || kind == "high") && injected[id] < candidate_min_samples) continue
            if (kind == "low" && pct(referenced_count[id], injected[id]) > 0) continue
            if (kind == "high" && pct(inj_block[id], injected[id]) <= 0) continue
            if (kind == "top" && better_top(id, best)) best = id
            else if (kind == "low" && better_low_ref(id, best)) best = id
            else if (kind == "high" && better_high_block(id, best)) best = id
            else if (kind == "never" && referenced_count[id] == 0 && better_top(id, best)) best = id
        }
        if (best == "") break
        used[best] = 1
        if (kind == "never") printf("  %-5s injected:%-4d ref_rate:  0%%\n", best, injected[best])
        else print rate_line(best)
        printed++
    }
    return printed
}
NR == 1 {
    for (i = 1; i <= NF; i++) col[$i] = i
    next
}
{
    lesson_id = trim($col["lesson_id"])
    action = lower(trim($col["action"]))
    result = upper(trim($col["result"]))
    if (lesson_id == "" || (action != "injected" && action != "withheld") || result == "PENDING") next

    if (!(lesson_id in seen)) {
        seen[lesson_id] = 1
        keys[++key_count] = lesson_id
    }
    d = safe_date($col["timestamp"])
    if (row_count == 0 || d < min_date) min_date = d
    if (row_count == 0 || d > max_date) max_date = d
    row_count++

    if (action == "injected") {
        injected[lesson_id]++
        total_injected++
        if (result == "CLEAR") inj_clear[lesson_id]++
        else if (result == "BLOCK") inj_block[lesson_id]++
        if (bool_value($col["referenced"])) {
            referenced_count[lesson_id]++
            if (result == "CLEAR") ref_clear[lesson_id]++
            else if (result == "BLOCK") ref_block[lesson_id]++
        }
    } else {
        withheld[lesson_id]++
        if (result == "CLEAR") with_clear[lesson_id]++
        else if (result == "BLOCK") with_block[lesson_id]++
    }
}
END {
    print "=== Lesson Impact Analysis ==="
    if (row_count > 0) print "Period: " min_date " ~ " max_date
    else print "Period: n/a"
    print "Total injections: " total_injected
    print "Unique lessons: " key_count
    print ""

    print "Top 10 Most Injected:"
    if (print_top10("top") == 0) print "  none"
    print ""

    print "Low Reference Rate (noise candidates):"
    print "  min_samples: " candidate_min_samples
    if (print_top10("low") == 0) print "  none"
    print ""

    print "High BLOCK Rate (harm candidates):"
    print "  min_samples: " candidate_min_samples
    if (print_top10("high") == 0) print "  none"
    print ""

    print "Never Referenced:"
    if (print_top10("never") == 0) print "  none"
    print ""

    print "=== A/B Comparison (lessons with N>=5 in both groups) ==="
    delete used
    ab_count = 0
    while (1) {
        best = ""
        for (i = 1; i <= key_count; i++) {
            id = keys[i]
            if (used[id] || injected[id] < 5 || withheld[id] < 5) continue
            if (better_ab(id, best)) best = id
        }
        if (best == "") break
        used[best] = 1
        print ab_line(best)
        ab_count++
    }
    if (ab_count > 0) {
        print "sig: n/s=not significant, *=p<0.05 (heuristic)"
    } else {
        print "  insufficient data for A/B comparison"
    }
}
' "$DATA_FILE"
    exit 0
fi

python3 - "$DATA_FILE" "$@" <<'PY'
import csv
import os
import re
import sys
from collections import Counter, defaultdict

yaml = None


def require_yaml():
    global yaml
    if yaml is not None:
        return yaml
    try:
        import yaml as yaml_module
    except Exception:
        return None
    yaml = yaml_module
    return yaml


def usage() -> None:
    print("Usage: bash scripts/lesson_impact_analysis.sh [--detail LESSON_ID] [--sync-counters] [--dry-run]")


def parse_args(argv):
    result = {"mode": "summary", "detail_id": None, "dry_run": False}
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--detail" and i + 1 < len(argv):
            result["mode"] = "detail"
            result["detail_id"] = argv[i + 1]
            i += 2
        elif arg == "--sync-counters":
            result["mode"] = "sync"
            i += 1
        elif arg == "--dry-run":
            result["dry_run"] = True
            i += 1
        else:
            usage()
            sys.exit(1)
    return result


def to_bool(value: str) -> bool:
    return str(value).strip().lower() in {"yes", "true", "1", "y"}


def to_result(value: str) -> str:
    return str(value).strip().upper()


def pct(num: int, den: int) -> int:
    if den <= 0:
        return 0
    return int(round((num * 100.0) / den))


def safe_date(ts: str) -> str:
    ts = (ts or "").strip()
    if len(ts) >= 10:
        return ts[:10]
    return "unknown"


def load_rows(path: str):
    rows = []
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return rows

    with open(path, "r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for raw in reader:
            lesson_id = (raw.get("lesson_id") or "").strip()
            action = (raw.get("action") or "").strip().lower()
            result = to_result(raw.get("result", ""))
            if not lesson_id or action not in {"injected", "withheld"}:
                continue
            if result == "PENDING":
                continue

            rows.append(
                {
                    "timestamp": raw.get("timestamp", ""),
                    "lesson_id": lesson_id,
                    "action": action,
                    "result": result,
                    "referenced": to_bool(raw.get("referenced", "")),
                    "task_type": (raw.get("task_type") or "").strip(),
                    "model": (raw.get("model") or "").strip(),
                }
            )
    return rows


def load_lesson_summaries(root: str):
    summaries = {}
    yaml_module = require_yaml()
    if yaml_module is None:
        return summaries

    import glob

    if yaml is None:
        return summaries

    for lesson_file in glob.glob(os.path.join(root, "projects", "*", "lessons.yaml")):
        try:
            with open(lesson_file, "r", encoding="utf-8") as f:
                data = yaml_module.safe_load(f) or {}
        except Exception:
            continue
        for lesson in data.get("lessons", []):
            lesson_id = str(lesson.get("id", "")).strip()
            if lesson_id and lesson_id not in summaries:
                summaries[lesson_id] = str(lesson.get("summary", "")).strip()
    return summaries


def unquote_scalar(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] == "'":
        return value[1:-1].replace("''", "'")
    if len(value) >= 2 and value[0] == value[-1] == '"':
        return value[1:-1]
    return value


def extract_flow_summary(line: str) -> str:
    match = re.search(r"[,{]\s*summary:", line)
    if not match:
        return ""
    value = line[match.end():].strip()
    in_quote = ""
    out = []
    i = 0
    while i < len(value):
        ch = value[i]
        if in_quote:
            out.append(ch)
            if ch == in_quote:
                if in_quote == "'" and i + 1 < len(value) and value[i + 1] == "'":
                    out.append(value[i + 1])
                    i += 1
                else:
                    in_quote = ""
        elif ch in ("'", '"'):
            in_quote = ch
            out.append(ch)
        elif ch in (",", "}"):
            break
        else:
            out.append(ch)
        i += 1
    return unquote_scalar("".join(out))


def load_lesson_summary_fast(root: str, lesson_id: str) -> str:
    import glob

    inline_pattern = re.compile(r"^-\s*\{id:\s*" + re.escape(lesson_id) + r"\s*[,}]")
    block_pattern = re.compile(r"^-\s*id:\s*" + re.escape(lesson_id) + r"\s*$")
    for lesson_file in glob.glob(os.path.join(root, "projects", "*", "lessons.yaml")):
        try:
            with open(lesson_file, "r", encoding="utf-8") as f:
                in_target = False
                for raw in f:
                    line = raw.rstrip("\n")
                    stripped = line.strip()
                    if inline_pattern.match(stripped):
                        return extract_flow_summary(stripped)
                    if block_pattern.match(stripped):
                        in_target = True
                        continue
                    if in_target:
                        if stripped.startswith("- id:") or stripped.startswith("- {id:"):
                            break
                        if stripped.startswith("summary:"):
                            return unquote_scalar(stripped.split(":", 1)[1])
        except OSError:
            continue
    return ""


def iter_lesson_ids_fast(lesson_file: str):
    inline_pattern = re.compile(r"^-\s*\{id:\s*([^,\s}]+)")
    block_pattern = re.compile(r"^-\s*id:\s*(\S+)\s*$")
    with open(lesson_file, "r", encoding="utf-8") as f:
        for raw in f:
            stripped = raw.strip()
            match = inline_pattern.match(stripped) or block_pattern.match(stripped)
            if match:
                yield unquote_scalar(match.group(1))


def build_stats(rows):
    stats = defaultdict(
        lambda: {
            "injected": 0,
            "withheld": 0,
            "inj_clear": 0,
            "inj_block": 0,
            "with_clear": 0,
            "with_block": 0,
            "referenced_count": 0,
            "ref_clear": 0,
            "ref_block": 0,
            "task_types": Counter(),
            "models": Counter(),
        }
    )

    for r in rows:
        sid = r["lesson_id"]
        st = stats[sid]
        action = r["action"]
        result = r["result"]

        if action == "injected":
            st["injected"] += 1
            if result == "CLEAR":
                st["inj_clear"] += 1
            elif result == "BLOCK":
                st["inj_block"] += 1

            if r["referenced"]:
                st["referenced_count"] += 1
                if result == "CLEAR":
                    st["ref_clear"] += 1
                elif result == "BLOCK":
                    st["ref_block"] += 1

            if r["task_type"]:
                st["task_types"][r["task_type"]] += 1
            if r["model"]:
                st["models"][r["model"]] += 1
        else:
            st["withheld"] += 1
            if result == "CLEAR":
                st["with_clear"] += 1
            elif result == "BLOCK":
                st["with_block"] += 1

    return stats


def rate_line(lesson_id: str, st: dict) -> str:
    inj = st["injected"]
    ref_rate = pct(st["referenced_count"], inj)
    clear_rate = pct(st["inj_clear"], inj)
    block_rate = pct(st["inj_block"], inj)
    return (
        f"  {lesson_id:<5} injected:{inj:<4} ref_rate:{ref_rate:>3}%  "
        f"CLEAR:{clear_rate:>3}%  BLOCK:{block_rate:>3}%"
    )


def ab_line(lesson_id: str, st: dict) -> str:
    inj_n = st["injected"]
    with_n = st["withheld"]
    inj_clear = pct(st["inj_clear"], inj_n)
    with_clear = pct(st["with_clear"], with_n)
    delta = inj_clear - with_clear
    if min(inj_n, with_n) >= 10 and abs(delta) >= 20:
        sig = "*"
    else:
        sig = "n/s"
    sign = "+" if delta >= 0 else ""
    return (
        f"  {lesson_id:<5} injected:{inj_n:<3} CLEAR:{inj_clear:>3}%  |  "
        f"withheld:{with_n:<3} CLEAR:{with_clear:>3}%  |  delta:{sign}{delta}%  sig:{sig}"
    )


def joined_counter(counter: Counter) -> str:
    if not counter:
        return "n/a"
    return " ".join(f"{k}={v}" for k, v in counter.most_common())


def print_summary(rows, stats):
    candidate_min_samples = int(os.environ.get("LESSON_IMPACT_CANDIDATE_MIN_SAMPLES", "3") or "3")
    print("=== Lesson Impact Analysis ===")
    if rows:
        dates = sorted(safe_date(r["timestamp"]) for r in rows)
        print(f"Period: {dates[0]} ~ {dates[-1]}")
    else:
        print("Period: n/a")
    total_injected = sum(1 for r in rows if r["action"] == "injected")
    print(f"Total injections: {total_injected}")
    print(f"Unique lessons: {len(stats)}")
    print()

    print("Top 10 Most Injected:")
    top_injected = sorted(stats.items(), key=lambda kv: (-kv[1]["injected"], kv[0]))[:10]
    if top_injected and top_injected[0][1]["injected"] > 0:
        for lesson_id, st in top_injected:
            if st["injected"] <= 0:
                continue
            print(rate_line(lesson_id, st))
    else:
        print("  none")
    print()

    print("Low Reference Rate (noise candidates):")
    print(f"  min_samples: {candidate_min_samples}")
    low_ref = [
        kv for kv in stats.items()
        if (
            kv[1]["injected"] >= candidate_min_samples
            and pct(kv[1]["referenced_count"], kv[1]["injected"]) == 0
        )
    ]
    low_ref.sort(key=lambda kv: (pct(kv[1]["referenced_count"], kv[1]["injected"]), -kv[1]["injected"], kv[0]))
    if low_ref:
        for lesson_id, st in low_ref[:10]:
            print(rate_line(lesson_id, st))
    else:
        print("  none")
    print()

    print("High BLOCK Rate (harm candidates):")
    print(f"  min_samples: {candidate_min_samples}")
    high_block = [
        kv for kv in stats.items()
        if (
            kv[1]["injected"] >= candidate_min_samples
            and pct(kv[1]["inj_block"], kv[1]["injected"]) > 0
        )
    ]
    high_block.sort(key=lambda kv: (-pct(kv[1]["inj_block"], kv[1]["injected"]), -kv[1]["injected"], kv[0]))
    if high_block:
        for lesson_id, st in high_block[:10]:
            print(rate_line(lesson_id, st))
    else:
        print("  none")
    print()

    print("Never Referenced:")
    never_ref = [kv for kv in stats.items() if kv[1]["injected"] > 0 and kv[1]["referenced_count"] == 0]
    never_ref.sort(key=lambda kv: (-kv[1]["injected"], kv[0]))
    if never_ref:
        for lesson_id, st in never_ref[:10]:
            print(f"  {lesson_id:<5} injected:{st['injected']:<4} ref_rate:  0%")
    else:
        print("  none")
    print()

    print("=== A/B Comparison (lessons with N>=5 in both groups) ===")
    ab_candidates = [kv for kv in stats.items() if kv[1]["injected"] >= 5 and kv[1]["withheld"] >= 5]
    ab_candidates.sort(
        key=lambda kv: (
            -(pct(kv[1]["inj_clear"], kv[1]["injected"]) - pct(kv[1]["with_clear"], kv[1]["withheld"])),
            kv[0],
        )
    )
    if ab_candidates:
        for lesson_id, st in ab_candidates:
            print(ab_line(lesson_id, st))
        print("sig: n/s=not significant, *=p<0.05 (heuristic)")
    else:
        print("  insufficient data for A/B comparison")


def print_detail(lesson_id: str, stats: dict, summary: str):
    st = stats.get(
        lesson_id,
        {
            "injected": 0,
            "withheld": 0,
            "inj_clear": 0,
            "inj_block": 0,
            "with_clear": 0,
            "with_block": 0,
            "referenced_count": 0,
            "ref_clear": 0,
            "ref_block": 0,
            "task_types": Counter(),
            "models": Counter(),
        },
    )

    print(f"=== {lesson_id} Detail ===")
    print(f"Summary: {summary or 'summary not found'}")
    inj = st["injected"]
    print(f"Injected: {inj} times")
    print(f"Referenced: {st['referenced_count']} times ({pct(st['referenced_count'], inj)}%)")
    print(
        f"Results when injected: CLEAR {st['inj_clear']} ({pct(st['inj_clear'], inj)}%) / "
        f"BLOCK {st['inj_block']} ({pct(st['inj_block'], inj)}%)"
    )
    ref_n = st["referenced_count"]
    print(
        f"Results when referenced: CLEAR {st['ref_clear']} ({pct(st['ref_clear'], ref_n)}%) / "
        f"BLOCK {st['ref_block']} ({pct(st['ref_block'], ref_n)}%)"
    )
    print(f"Models: {joined_counter(st['models'])}")
    print(f"Task types: {joined_counter(st['task_types'])}")

    if st["injected"] >= 5 and st["withheld"] >= 5:
        print("A/B: " + ab_line(lesson_id, st).strip())
    else:
        print("A/B: insufficient data for A/B comparison")


def sync_counters(rows, root, dry_run=False):
    yaml_module = require_yaml()
    if yaml_module is None:
        print("ERROR: PyYAML required for --sync-counters", file=sys.stderr)
        sys.exit(1)

    import fcntl
    import glob

    counts = {}
    for r in rows:
        if r["action"] != "injected":
            continue
        if not r["referenced"]:
            continue
        lid = r["lesson_id"]
        if lid not in counts:
            counts[lid] = {"helpful": 0, "harmful": 0, "last_ts": ""}
        if r["result"] == "CLEAR":
            counts[lid]["helpful"] = counts[lid]["helpful"] + 1
        elif r["result"] == "BLOCK":
            counts[lid]["harmful"] = counts[lid]["harmful"] + 1
        ts = safe_date(r["timestamp"])
        if ts > counts[lid]["last_ts"]:
            counts[lid]["last_ts"] = ts

    if not counts:
        print("No referenced lessons found in TSV")
        return

    project_updates = []
    if dry_run:
        import glob

        for lesson_file in sorted(glob.glob(os.path.join(root, "projects", "*", "lessons.yaml"))):
            project = os.path.basename(os.path.dirname(lesson_file))
            updated = 0
            try:
                lesson_ids = iter_lesson_ids_fast(lesson_file)
                for lid in lesson_ids:
                    if lid in counts:
                        c = counts[lid]
                        updated = updated + 1
                        print(
                            f"SYNC: {project} {lid} helpful={c['helpful']} "
                            f"harmful={c['harmful']} last_referenced={c['last_ts']}"
                        )
            except OSError:
                continue
            if updated > 0:
                project_updates.append(f"{project} {updated} lessons")

        summary_line = ", ".join(project_updates) if project_updates else "0 lessons"
        print(f"\n[DRY RUN] Would update: {summary_line}")
        return

    for lesson_file in sorted(glob.glob(os.path.join(root, "projects", "*", "lessons.yaml"))):
        project = os.path.basename(os.path.dirname(lesson_file))

        if dry_run:
            with open(lesson_file, "r", encoding="utf-8") as f:
                data = yaml_module.safe_load(f) or {}
        else:
            f = open(lesson_file, "r+", encoding="utf-8")
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            data = yaml_module.safe_load(f) or {}

        updated = 0
        for lesson in data.get("lessons", []):
            lid = str(lesson.get("id", "")).strip()
            if lid in counts:
                c = counts[lid]
                lesson["helpful_count"] = c["helpful"]
                lesson["harmful_count"] = c["harmful"]
                if c["last_ts"]:
                    lesson["last_referenced"] = c["last_ts"]
                updated = updated + 1
                print(
                    f"SYNC: {project} {lid} helpful={c['helpful']} "
                    f"harmful={c['harmful']} last_referenced={c['last_ts']}"
                )

        if updated > 0:
            project_updates.append(f"{project} {updated} lessons")
            if not dry_run:
                f.seek(0)
                f.truncate()
                yaml_module.dump(
                    data, f,
                    allow_unicode=True,
                    default_flow_style=False,
                    sort_keys=False,
                )

        if not dry_run:
            f.close()

    summary_line = ", ".join(project_updates) if project_updates else "0 lessons"
    if dry_run:
        print(f"\n[DRY RUN] Would update: {summary_line}")
    else:
        print(f"Updated: {summary_line}")


def main():
    data_file = sys.argv[1]
    opts = parse_args(sys.argv[2:])
    rows = load_rows(data_file)

    if opts["mode"] == "sync":
        root = os.path.dirname(os.path.dirname(data_file))
        sync_counters(rows, root, opts["dry_run"])
    elif opts["mode"] == "detail":
        stats = build_stats(rows)
        root = os.path.dirname(os.path.dirname(data_file))
        summary = load_lesson_summary_fast(root, opts["detail_id"])
        if not summary:
            summary = load_lesson_summaries(root).get(opts["detail_id"], "")
        print_detail(opts["detail_id"], stats, summary)
    else:
        stats = build_stats(rows)
        print_summary(rows, stats)


if __name__ == "__main__":
    main()
PY
