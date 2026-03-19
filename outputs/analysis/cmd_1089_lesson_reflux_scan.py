#!/usr/bin/env python3
"""cmd_1089: 全教訓の穴検出3問バッチスキャン

各教訓について以下3箇所をキーワードgrepし、還流状況を判定:
1. projects/{project}.yaml production_invariants → PI
2. docs/rule/*.md → ランブック
3. instructions/*.md → ワークフロー

出力: outputs/analysis/cmd_1089_lesson_reflux_scan.csv
"""

import csv
import os
import re
import yaml
from pathlib import Path

BASE = Path("/mnt/c/tools/multi-agent-shogun")
DM_SIGNAL_PATH = Path("/mnt/c/Python_app/DM-signal")

# Search targets
PI_FILES = {
    "dm-signal": [BASE / "projects" / "dm-signal.yaml"],
    "infra": [BASE / "projects" / "infra.yaml"],
}
RUNBOOK_DIR = DM_SIGNAL_PATH / "docs" / "rule"
INSTRUCTIONS_DIR = BASE / "instructions"


def load_lessons(project: str) -> list:
    path = BASE / "projects" / project / "lessons.yaml"
    with open(path, "r") as f:
        data = yaml.safe_load(f)
    return data.get("lessons", [])


def is_deprecated(lesson: dict) -> bool:
    cat = str(lesson.get("category", "")).lower()
    status = str(lesson.get("status", "")).lower()
    return "deprecated" in cat or "deprecated" in status or "廃止" in cat


def extract_keywords(lesson: dict) -> list:
    """Extract searchable keywords from lesson summary/title."""
    text = f"{lesson.get('title', '')} {lesson.get('summary', '')}"
    # Extract meaningful tokens: identifiers, file names, technical terms
    keywords = set()

    # File paths / identifiers (e.g., recalculate_fast.py, pipeline_config)
    identifiers = re.findall(r'[a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z]+)?', text)
    for ident in identifiers:
        if len(ident) >= 5 and ident.lower() not in {
            'false', 'their', 'should', 'would', 'could', 'about',
            'before', 'after', 'which', 'where', 'there', 'these',
            'those', 'other', 'every', 'under', 'above', 'below',
            'between', 'through', 'being', 'having', 'doing',
            'because', 'since', 'while', 'until', 'during',
            'lesson', 'summary', 'title', 'source', 'category',
            'count', 'using', 'value', 'first', 'check',
        }:
            keywords.add(ident.lower())

    # Japanese technical terms (3+ chars)
    jp_terms = re.findall(r'[ぁ-んァ-ヶ亜-熙]+', text)
    for term in jp_terms:
        if len(term) >= 3:
            keywords.add(term)

    return list(keywords)


def search_in_files(keywords: list, files: list) -> bool:
    """Check if any keyword appears in any of the given files."""
    for fpath in files:
        if not fpath.exists():
            continue
        try:
            content = fpath.read_text(encoding="utf-8").lower()
            for kw in keywords:
                if kw in content:
                    return True
        except Exception:
            continue
    return False


def search_in_dir(keywords: list, dirpath: Path, glob_pattern: str = "*.md") -> bool:
    """Check if any keyword appears in files matching glob in directory."""
    if not dirpath.exists():
        return False
    files = list(dirpath.glob(glob_pattern))
    return search_in_files(keywords, files)


def is_pi_candidate(lesson: dict) -> str:
    """Determine if lesson is a PI candidate.
    PI候補: 本番コード挙動に関わり、忍者が知らなければ再発するもの
    """
    text = f"{lesson.get('title', '')} {lesson.get('summary', '')}".lower()
    # Signals for production-relevant lessons
    prod_signals = [
        'recalculate', 'pipeline', 'config', 'database', 'db', 'api',
        'deploy', 'production', 'migrate', 'schema', 'upsert',
        'フォールバック', 'fallback', 'cash', 'signal', 'portfolio',
        'monthly_return', 'rebalance', 'holding_signal', 'fof',
        '本番', 'render', 'postgresql', 'supabase', 'env',
        'pipeline_config', 'recalculate_fast', 'block_type',
        'jsonb', 'constraint', 'unique', 'index',
    ]
    score = sum(1 for s in prod_signals if s in text)
    # Need at least 2 production signals to be a candidate
    return "yes" if score >= 2 else "no"


def main():
    results = []

    for project in ["dm-signal", "infra"]:
        lessons = load_lessons(project)
        pi_files = PI_FILES.get(project, [])
        # For dm-signal, runbook is in DM-signal repo; for infra, no runbook dir
        if project == "dm-signal":
            runbook_dir = RUNBOOK_DIR
        else:
            runbook_dir = BASE / "docs" / "rule"  # doesn't exist for infra, will return False

        for lesson in lessons:
            if is_deprecated(lesson):
                continue

            lid = lesson.get("id", "?")
            summary = lesson.get("summary", "")
            # Truncate summary for CSV readability
            summary_short = summary[:120].replace("\n", " ").replace(",", ";")

            keywords = extract_keywords(lesson)
            if not keywords:
                results.append({
                    "lesson_id": lid,
                    "project": project,
                    "summary": summary_short,
                    "pi_found": "N/A",
                    "runbook_found": "N/A",
                    "instructions_found": "N/A",
                    "pi_candidate": "no",
                    "note": "no_keywords_extracted",
                })
                continue

            pi_found = search_in_files(keywords, pi_files)
            runbook_found = search_in_dir(keywords, runbook_dir)
            instructions_found = search_in_dir(keywords, INSTRUCTIONS_DIR)

            results.append({
                "lesson_id": lid,
                "project": project,
                "summary": summary_short,
                "pi_found": "FOUND" if pi_found else "MISSING",
                "runbook_found": "FOUND" if runbook_found else "MISSING",
                "instructions_found": "FOUND" if instructions_found else "MISSING",
                "pi_candidate": is_pi_candidate(lesson),
                "note": "",
            })

    # Write CSV
    outpath = BASE / "outputs" / "analysis" / "cmd_1089_lesson_reflux_scan.csv"
    with open(outpath, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "lesson_id", "project", "summary", "pi_found",
            "runbook_found", "instructions_found", "pi_candidate", "note"
        ])
        writer.writeheader()
        writer.writerows(results)

    # Summary stats
    total = len(results)
    pi_missing = sum(1 for r in results if r["pi_found"] == "MISSING")
    rb_missing = sum(1 for r in results if r["runbook_found"] == "MISSING")
    inst_missing = sum(1 for r in results if r["instructions_found"] == "MISSING")
    pi_candidates = sum(1 for r in results if r["pi_candidate"] == "yes")

    # All-three-MISSING (highest priority)
    all_missing = [r for r in results if r["pi_found"] == "MISSING"
                   and r["runbook_found"] == "MISSING"
                   and r["instructions_found"] == "MISSING"]

    # PI candidates that are MISSING from PI
    pi_cand_missing = [r for r in results if r["pi_candidate"] == "yes"
                       and r["pi_found"] == "MISSING"]

    print(f"=== cmd_1089 Lesson Reflux Scan Results ===")
    print(f"Total lessons scanned: {total}")
    print(f"PI MISSING:           {pi_missing}")
    print(f"Runbook MISSING:      {rb_missing}")
    print(f"Instructions MISSING: {inst_missing}")
    print(f"PI candidates:        {pi_candidates}")
    print(f"All-3 MISSING:        {len(all_missing)}")
    print(f"PI candidate+MISSING: {len(pi_cand_missing)}")
    print(f"\nOutput: {outpath}")

    # Print top priority: PI candidates missing from PI
    if pi_cand_missing:
        print(f"\n--- PI Candidate + PI MISSING (top priority) ---")
        for r in pi_cand_missing[:30]:
            print(f"  {r['lesson_id']} [{r['project']}] {r['summary'][:80]}")

    print(f"\n--- All-3 MISSING sample (first 20) ---")
    for r in all_missing[:20]:
        print(f"  {r['lesson_id']} [{r['project']}] {r['summary'][:80]}")


if __name__ == "__main__":
    main()
