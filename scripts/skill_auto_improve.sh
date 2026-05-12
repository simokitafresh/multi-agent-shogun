#!/usr/bin/env bash
# skill_auto_improve.sh — convert skill FAIL patterns into SKILL.md prevention steps.
#
# Usage:
#   bash scripts/skill_auto_improve.sh [--top 3] [--apply] [--skill <name>]

set -euo pipefail

REPO_ROOT="${SHOGUN_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOG_FILE="${SKILL_EXECUTION_LOG_FILE:-$REPO_ROOT/logs/skill_execution_log.yaml}"
SKILLS_DIRS="${SKILL_AUTO_IMPROVE_SKILLS_DIRS:-$REPO_ROOT/skills:$HOME/.codex/skills:$HOME/.claude/skills}"
top_n=3
apply=false
skill_filter=""

usage() {
    sed -n '1,7p' "$0" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --log) LOG_FILE="${2:-}"; shift 2 ;;
        --skills-dirs) SKILLS_DIRS="${2:-}"; shift 2 ;;
        --top) top_n="${2:-}"; shift 2 ;;
        --skill) skill_filter="${2:-}"; shift 2 ;;
        --apply) apply=true; shift ;;
        --dry-run) apply=false; shift ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Unknown arg: $1" >&2
            usage
            exit 2
            ;;
    esac
done

python3 - "$LOG_FILE" "$SKILLS_DIRS" "$top_n" "$apply" "$skill_filter" "$REPO_ROOT" <<'PY'
import hashlib
import json
import os
import re
import sys
import tempfile
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

import yaml

log_file, skills_dirs, top_n_raw, apply_raw, skill_filter, repo_root = sys.argv[1:7]

# --- Gate FIX hint lookup (skill_auto_improve) ---
# Import lookup_fix_hints from gate_report_format_main to generate
# specific prevention steps instead of generic keyword-matching templates.
_gate_dir = os.path.join(repo_root, "scripts", "gates")
if _gate_dir not in sys.path and os.path.isdir(_gate_dir):
    sys.path.insert(0, _gate_dir)
_grfm = None
try:
    import gate_report_format_main as _grfm  # type: ignore
    if not hasattr(_grfm, "lookup_fix_hints"):
        _grfm = None
except Exception:
    pass

try:
    top_n = int(top_n_raw)
except ValueError:
    print("--top must be an integer", file=sys.stderr)
    raise SystemExit(2)
if top_n < 1:
    print("--top must be >= 1", file=sys.stderr)
    raise SystemExit(2)
apply_changes = apply_raw.lower() == "true"


def _cache_path(log_path):
    digest = hashlib.sha1(str(log_path).encode()).hexdigest()[:16]
    return Path(tempfile.gettempdir()) / f"skill_auto_improve_cache_{digest}.json"


def load_entries(path):
    try:
        stat = Path(path).stat()
        cache_key = (stat.st_mtime_ns, stat.st_size)
    except FileNotFoundError:
        return []
    cache_file = _cache_path(path)
    if cache_file.is_file():
        try:
            cached = json.loads(cache_file.read_text(encoding="utf-8"))
            if tuple(cached.get("key", [])) == cache_key:
                return cached["entries"]
        except (json.JSONDecodeError, KeyError):
            pass
    try:
        with open(path, encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
    except FileNotFoundError:
        return []
    entries = [entry for entry in (data.get("executions") or []) if isinstance(entry, dict)]
    try:
        cache_file.write_text(
            json.dumps({"key": list(cache_key), "entries": entries}, ensure_ascii=False),
            encoding="utf-8",
        )
    except OSError:
        pass
    return entries


def iter_skill_files():
    seen = set()
    for raw_dir in skills_dirs.split(":"):
        if not raw_dir:
            continue
        root = Path(os.path.expanduser(raw_dir))
        if not root.is_dir():
            continue
        for child in sorted(root.iterdir(), key=lambda p: p.name):
            skill_file = child / "SKILL.md"
            try:
                resolved = skill_file.resolve()
            except OSError:
                resolved = skill_file
            if not skill_file.is_file() or resolved in seen:
                continue
            seen.add(resolved)
            yield child.name, skill_file


_skill_index = None
GATE_SKILL_MAP = {
    "gate_report_format": "report-write",
}


def _get_skill_index():
    global _skill_index
    if _skill_index is None:
        _skill_index = {}
        for name, path in iter_skill_files():
            _skill_index.setdefault(name, path)
    return _skill_index


def skill_file_for(skill_name, logged_path):
    indexed = _get_skill_index().get(skill_name)
    if indexed:
        return indexed
    if logged_path:
        path = Path(os.path.expanduser(str(logged_path)))
        if path.is_file():
            return path
    return None


def normalize_reason(value):
    return " ".join(str(value or "").split())


def shorten(value, limit=180):
    if len(value) <= limit:
        return value
    return value[: limit - 3] + "..."


def marker_for(skill_name, reason):
    digest = hashlib.sha1(f"{skill_name}\0{reason}".encode("utf-8")).hexdigest()[:12]
    return f"<!-- skill-auto-improve:{digest} -->"


def concrete_prevention_steps(reason):
    # Phase 1: gate-specific FIX hints from gate_report_format_main.lookup_fix_hints()
    # This replaces generic keyword templates with concrete, actionable steps.
    if _grfm is not None:
        try:
            gate_hints = _grfm.lookup_fix_hints(reason)
        except Exception:
            gate_hints = []
        if gate_hints:
            first = gate_hints[0]
            field_m = re.match(r"FIX \(([^)]+)\):", first)
            check_text = (
                f"`{field_m.group(1)}` フィールドを gate FIXヒントに従って確認"
                if field_m
                else "gate_report_format FIXヒントを確認する"
            )
            fix_parts = list(dict.fromkeys(shorten(h, 150) for h in gate_hints[:3]))
            return check_text, " / ".join(fix_parts[:2])

    # Phase 2: keyword-based fallback (for non-gate-report-format gates or unmatched reasons)
    lower = reason.lower()
    checks = []
    fixes = []

    if "fill_this" in lower:
        checks.append("提出前に対象YAML/本文へ `rg -n 'FILL_THIS'` を実行する")
        fixes.append("残存箇所を実値または具体的な no_* reason に置換する")
    if "verdict" in lower:
        checks.append("verdict が空/None/不正値でないこと、かつ binary_checks 記入後に決めていることを確認する")
        fixes.append("`/verdict-check` または `report_field_set.sh ... verdict PASS|FAIL` で再導出する")
    if "binary_checks" in lower or "bc:" in lower or "bc_" in lower:
        checks.append("全 binary_checks の result が yes/no のみで、空欄・waive・PASS・FAIL を含まないことを確認する")
        fixes.append("各ACの result を yes/no に直し、1つでも no なら verdict を FAIL にする")
    if "lesson_candidate" in lower:
        checks.append("lesson_candidate が dict で、found=false なら no_lesson_reason が具体文になっていることを確認する")
        fixes.append("found/no_lesson_reason または title/detail を report_field_set.sh 経由で記入する")
    if "lessons_useful" in lower or "draft_lessons" in lower:
        checks.append("関連教訓ごとに lessons_useful の id/useful/reason が埋まっていることを確認する")
        fixes.append("UNKNOWN/null/FILL_THISを使わず、各教訓の有用性と理由を記入する")
    if "assumption_invalidation" in lower:
        checks.append("assumption_invalidation に detail と affected_cmds があることを確認する")
        fixes.append("`report_field_set.sh <report> assumption_invalidation found false` で dict 形式を保証する")
    if "files_modified" in lower:
        checks.append("files_modified が空/欠落/FILL_THISでないことを確認する")
        fixes.append("`report_field_set.sh <report> files_modified <path>` で変更ファイルを記入する")
    if "ac_version" in lower:
        checks.append("ac_version_read がHEADの短縮ハッシュと一致するか `git rev-parse --short HEAD` で確認する")
        fixes.append("`report_field_set.sh <report> ac_version_read $(git rev-parse --short HEAD)` で記入する")
    if "purpose_validation" in lower:
        checks.append("purpose_validation.fit が true/false で、purpose_gap が記入済みか確認する")
        fixes.append("`report_field_set.sh <report> purpose_validation fit true` で記入する")
    if "worker_id" in lower or "parent_cmd" in lower:
        checks.append("worker_id と parent_cmd がテンプレート生成値と一致するか確認する")
        fixes.append("`report_field_set.sh <report> worker_id <name>` / `report_field_set.sh <report> parent_cmd <cmd_id>` で記入する")
    if "missing" in lower or "欠落" in reason:
        checks.append("FAIL理由に出たフィールド名を報告YAML上で `rg -n '<field>' <report>` で検索する")
        fixes.append("欠落フィールドを `report_field_set.sh` 経由で追加する")
    if not checks:
        checks.append("`bash scripts/gates/gate_report_format.sh <report>` を事前実行しFAIL箇所を確認する")
    if not fixes:
        fixes.append("gate出力のFIXヒントに従い `report_field_set.sh` で修正後、gateを再実行する")

    # Keep generated lines readable and deterministic.
    checks = list(dict.fromkeys(checks))[:2]
    fixes = list(dict.fromkeys(fixes))[:2]
    return " / ".join(checks), " / ".join(fixes)


def prevention_line(skill_name, reason, gate, count, last_fail):
    marker = marker_for(skill_name, reason)
    compact_reason = shorten(reason)
    gate_text = gate or "unknown_gate"
    check_text, fix_text = concrete_prevention_steps(reason)
    return (
        f"- {marker} 自動防止: gate={gate_text} のTop FAIL理由「{compact_reason}」"
        f"(count={count}, last={last_fail or 'unknown'})を避ける。確認: {check_text}。"
        f"修正: {fix_text}。"
    )


def existing_auto_section_insert_index(lines):
    for idx, line in enumerate(lines):
        if line.strip() != "### 自動防止ステップ":
            continue
        insert = idx + 1
        while insert < len(lines) and not lines[insert].startswith("#"):
            insert += 1
        return insert
    return None


def procedure_insertion_index(lines):
    heading_re = re.compile(r"^##\s+.*(手順|実行フロー|Workflow|Procedure|Steps|使い方|commit手順)")
    fallback_re = re.compile(r"^##\s+注意ポイント\s*$")
    for idx, line in enumerate(lines):
        if heading_re.search(line):
            insert = idx + 1
            while insert < len(lines) and lines[insert].strip() == "":
                insert += 1
            return insert
    for idx, line in enumerate(lines):
        if fallback_re.search(line):
            return idx
    return len(lines)


def apply_prevention_steps(skill_path, rows):
    text = skill_path.read_text(encoding="utf-8", errors="ignore")
    additions = []
    for row in rows:
        marker = marker_for(row["skill"], row["reason"])
        if marker in text:
            continue
        additions.append(prevention_line(row["skill"], row["reason"], row["gate"], row["count"], row["last_fail"]))
    if not additions:
        return False

    lines = text.splitlines()
    auto_idx = existing_auto_section_insert_index(lines)
    if auto_idx is None:
        block = ["### 自動防止ステップ", *additions, ""]
        idx = procedure_insertion_index(lines)
    else:
        block = additions
        idx = auto_idx
    new_lines = lines[:idx] + block + lines[idx:]
    new_text = "\n".join(new_lines).rstrip() + "\n"

    fd, tmp = tempfile.mkstemp(dir=str(skill_path.parent), prefix=".SKILL.", suffix=".tmp")
    os.close(fd)
    Path(tmp).write_text(new_text, encoding="utf-8")
    os.replace(tmp, skill_path)
    return True


stats = defaultdict(lambda: {"counter": Counter(), "last": {}, "gate": {}, "path": ""})
for entry in load_entries(log_file):
    if str(entry.get("result", "")).strip().upper() != "FAIL":
        continue
    if str(entry.get("used", True)).strip().lower() == "false":
        continue
    gate_name = str(entry.get("gate") or "").strip()
    skill = GATE_SKILL_MAP.get(gate_name) or str(entry.get("skill") or "").strip()
    if not skill:
        continue
    if skill_filter and skill != skill_filter:
        continue
    reason = normalize_reason(entry.get("stumbling_points"))
    if not reason:
        continue
    stats[skill]["counter"][reason] += 1
    ts = str(entry.get("ts") or "").strip()
    if ts >= stats[skill]["last"].get(reason, ""):
        stats[skill]["last"][reason] = ts
        stats[skill]["gate"][reason] = gate_name
    logged_path = str(entry.get("skill_path") or "").strip()
    if GATE_SKILL_MAP.get(gate_name):
        mapped_path = skill_file_for(skill, "")
        if mapped_path:
            stats[skill]["path"] = str(mapped_path)
    elif logged_path:
        stats[skill]["path"] = logged_path

print("skill | rank | fail_count | last_fail | gate | top_fail_reason")
apply_plan = defaultdict(list)
for skill in sorted(stats):
    top_rows = sorted(stats[skill]["counter"].items(), key=lambda kv: (-kv[1], kv[0]))[:top_n]
    for rank, (reason, count) in enumerate(top_rows, start=1):
        row = {
            "skill": skill,
            "rank": rank,
            "count": count,
            "last_fail": stats[skill]["last"].get(reason, ""),
            "gate": stats[skill]["gate"].get(reason, ""),
            "reason": reason,
        }
        print(
            f"{skill} | {rank} | {count} | {row['last_fail']} | {row['gate']} | {shorten(reason, 220)}"
        )
        apply_plan[skill].append(row)

if not apply_changes:
    raise SystemExit(0)

updated = 0
for skill, rows in apply_plan.items():
    path = skill_file_for(skill, stats[skill]["path"])
    if not path:
        print(f"SKIP: {skill} SKILL.md not found")
        continue
    if apply_prevention_steps(path, rows):
        updated += 1
        print(f"UPDATED: {path}")
    else:
        print(f"UNCHANGED: {path}")

print(f"updated_skills={updated} generated_at={datetime.now().strftime('%Y-%m-%dT%H:%M:%S')}")
PY
