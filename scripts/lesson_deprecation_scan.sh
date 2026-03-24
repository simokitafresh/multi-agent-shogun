#!/bin/bash
# lesson_deprecation_scan.sh - deprecation候補を自動検出+自動退役する
# cmd_531: ファイル消滅教訓・有効率10%未満×注入10回以上の教訓を自動deprecated化
# Usage: bash scripts/lesson_deprecation_scan.sh [--project dm-signal|infra|all]
# Default: --project all

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/projects.yaml"
TRACKING_TSV="$SCRIPT_DIR/logs/lesson_tracking.tsv"
IMPACT_TSV="$SCRIPT_DIR/logs/lesson_impact.tsv"

# --- Argument Parsing ---
PROJECT_FILTER="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --project requires a value (dm-signal|infra|all)" >&2
        exit 1
      fi
      PROJECT_FILTER="$2"
      shift 2
      ;;
    *)
      echo "Usage: bash scripts/lesson_deprecation_scan.sh [--project dm-signal|infra|all]" >&2
      exit 1
      ;;
  esac
done

export SCRIPT_DIR CONFIG_FILE TRACKING_TSV IMPACT_TSV PROJECT_FILTER

python3 << 'PYEOF'
import os
import sys
import re
import yaml
import subprocess
from pathlib import Path

SCRIPT_DIR = Path(os.environ["SCRIPT_DIR"])
CONFIG_FILE = Path(os.environ["CONFIG_FILE"])
TRACKING_TSV = Path(os.environ["TRACKING_TSV"])
IMPACT_TSV = Path(os.environ["IMPACT_TSV"])
PROJECT_FILTER = os.environ["PROJECT_FILTER"]

# --- Load projects ---
with open(CONFIG_FILE, encoding="utf-8") as f:
    config = yaml.safe_load(f)
all_projects = config.get("projects", [])

if PROJECT_FILTER == "all":
    projects = all_projects
else:
    projects = [p for p in all_projects if p["id"] == PROJECT_FILTER]
    if not projects:
        print(f"ERROR: project '{PROJECT_FILTER}' not found", file=sys.stderr)
        sys.exit(1)

project_root_map = {}
for project in all_projects:
    project_id = str(project.get("id", "")).strip()
    if not project_id:
        continue
    project_root_map[project_id] = Path(str(project.get("path", SCRIPT_DIR))).expanduser()


# GP-075: cmd_project_map with persistent cache + incremental scan
_ID_PAT = re.compile(r'id:\s+(cmd_\d+)')
_PROJ_PAT = re.compile(r'project:\s+[\x27"]?([a-zA-Z0-9_-]+)')
_CACHE_PATH = SCRIPT_DIR / "queue" / "cmd_project_map_cache.tsv"


def _load_cache():
    """Load cached cmd→project map and set of processed archive filenames."""
    cached = {}
    cached_files = set()
    if not _CACHE_PATH.is_file():
        return cached, cached_files
    with open(_CACHE_PATH, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) == 3 and parts[0] == "F":
                cached_files.add(parts[1])
            elif len(parts) == 2:
                cached[parts[0]] = parts[1]
    return cached, cached_files


def _save_cache(metadata, all_archive_files):
    """Persist cmd→project map + archive file list."""
    with open(_CACHE_PATH, "w", encoding="utf-8") as f:
        f.write("# cmd_project_map_cache (auto-generated)\n")
        for cid in sorted(metadata):
            f.write(f"{cid}\t{metadata[cid]}\n")
        for fname in sorted(all_archive_files):
            f.write(f"F\t{fname}\t1\n")


def _text_scan_cmd_metadata(path):
    """Extract (cmd_id, project_id) pairs via text scan (no yaml.safe_load)."""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read(8192)
    except Exception:
        return {}
    result = {}
    ids = list(_ID_PAT.finditer(text))
    if len(ids) == 1:
        projs = _PROJ_PAT.findall(text)
        if projs:
            result[ids[0].group(1)] = projs[0]
    else:
        for m in ids:
            pm = _PROJ_PAT.search(text, m.end())
            if pm and (pm.start() - m.end()) < 500:
                result[m.group(1)] = pm.group(1)
    return result


def load_cmd_metadata(root_dir):
    metadata = {}

    # Always re-scan shogun_to_karo.yaml (active commands, changes frequently)
    stk = root_dir / "queue" / "shogun_to_karo.yaml"
    if stk.is_file():
        try:
            data = yaml.safe_load(stk.read_text(encoding="utf-8")) or {}
        except Exception:
            data = {}
        if isinstance(data, dict):
            for key, cmd in data.items():
                if isinstance(cmd, dict):
                    cid = str(cmd.get("id", "")).strip()
                    pid = str(cmd.get("project", "")).strip()
                    if cid and pid:
                        metadata[cid] = pid

    # Archive: load cache + scan only new files
    archive_dir = root_dir / "queue" / "archive" / "cmds"
    if not archive_dir.is_dir():
        return metadata

    cached, cached_files = _load_cache()
    all_archive_files = {f for f in os.listdir(archive_dir) if f.endswith(".yaml")}
    new_files = all_archive_files - cached_files

    if not new_files:
        metadata.update(cached)
        return metadata

    # Scan only new files with text scan (no yaml.safe_load)
    new_entries = {}
    for fname in new_files:
        path = archive_dir / fname
        new_entries.update(_text_scan_cmd_metadata(path))

    # Merge: cache + new
    merged_archive = {**cached, **new_entries}
    metadata.update(merged_archive)

    # Persist updated cache
    _save_cache(merged_archive, all_archive_files)
    return metadata


cmd_project_map = load_cmd_metadata(SCRIPT_DIR)

# --- Load lesson_tracking.tsv for last_referenced_cmd ---
# Columns: timestamp  cmd_id  ninja  gate_result  injected_ids  referenced_ids
lesson_last_cmd = {}  # (project_id, lesson_id) -> last cmd_num (int)
max_cmd_num = 0

if TRACKING_TSV.exists():
    with open(TRACKING_TSV, encoding="utf-8") as f:
        for i, line in enumerate(f):
            line = line.strip()
            if i == 0 or not line:
                continue
            parts = line.split("\t")
            if len(parts) < 6:
                continue
            cmd_id = parts[1]
            referenced_str = parts[5] if len(parts) > 5 else ""
            m = re.match(r'cmd_(\d+)$', cmd_id)
            if not m:
                continue
            cmd_num = int(m.group(1))
            if cmd_num >= 900:  # skip test cmds (cmd_999 etc.)
                continue
            project_id = cmd_project_map.get(cmd_id)
            if not project_id:
                continue
            max_cmd_num = max(max_cmd_num, cmd_num)
            if referenced_str and referenced_str != "none":
                for lid in referenced_str.split(","):
                    lid = lid.strip()
                    if re.match(r'^L\d+$', lid):
                        key = (project_id, lid)
                        prev = lesson_last_cmd.get(key, 0)
                        if cmd_num > prev:
                            lesson_last_cmd[key] = cmd_num


# --- Load lesson_impact.tsv for injection/helpful counts ---
# Columns: timestamp  cmd_id  ninja  lesson_id  action  result  referenced  project  task_type  bloom_level
tsv_injection_count = {}  # (project_id, lesson_id) -> count
tsv_helpful_count = {}    # (project_id, lesson_id) -> count

if IMPACT_TSV.exists():
    with open(IMPACT_TSV, encoding="utf-8") as f:
        for i, line in enumerate(f):
            line = line.strip()
            if i == 0 or not line:
                continue
            parts = line.split("\t")
            if len(parts) < 8:
                continue
            lesson_id_tsv = parts[3]
            action = parts[4]
            result = parts[5].strip().upper()
            referenced = parts[6]
            project_id = parts[7].strip()
            key = (project_id, lesson_id_tsv)
            if result == "PENDING":
                continue
            if action == "injected" and re.match(r'^L\d+$', lesson_id_tsv) and project_id:
                tsv_injection_count[key] = tsv_injection_count.get(key, 0) + 1
                if referenced == "yes":
                    tsv_helpful_count[key] = tsv_helpful_count.get(key, 0) + 1


def last_ref_text(project_id, lesson_id):
    """Format last-referenced info as 'Ncmd前(cmd_NNN)' or '参照なし'."""
    last = lesson_last_cmd.get((project_id, lesson_id))
    if last is None:
        return "参照なし"
    diff = max_cmd_num - last
    if diff == 0:
        return f"最新cmd(cmd_{last})で参照済み"
    return f"{diff}cmd前(cmd_{last})"


def is_deprecated(lesson):
    """Check if lesson is already deprecated (skip these)."""
    return bool(lesson.get("deprecated", False)) or lesson.get("status") == "deprecated"


def find_file_refs(text):
    """Find explicit repo file path references (e.g. scripts/xxx.sh, queue/xxx.yaml).
    Use ASCII-only char class to avoid matching Japanese text after file extensions."""
    pattern = (
        r'\b((?:scripts|queue|config|projects|logs|context|tasks|docs)'
        r'/[a-zA-Z0-9_/.-]+\.[a-zA-Z0-9]+)'
    )
    return re.findall(pattern, text)


def find_script_names(text):
    """Find bare .sh script name mentions."""
    return re.findall(r'\b([\w_-]+\.sh)\b', text)


def ref_exists(project_root, relative_path):
    candidate_paths = [project_root / relative_path, SCRIPT_DIR / relative_path]
    return any(path.exists() for path in candidate_paths)


def script_exists(project_root, script_name):
    candidate_paths = [project_root / "scripts" / script_name, SCRIPT_DIR / "scripts" / script_name]
    return any(path.exists() for path in candidate_paths)


def sanitize_reason(reason):
    """Collapse control chars so deprecation reason stays single-line and log-safe."""
    if not isinstance(reason, str):
        raise ValueError("reason must be a string")

    sanitized = reason.replace("\r", " ").replace("\n", " ").replace("\t", " ")
    sanitized = re.sub(r"[\x00-\x1f\x7f]", "", sanitized)
    sanitized = " ".join(sanitized.split())
    if not sanitized:
        raise ValueError("reason is empty after sanitization")
    if len(sanitized) > 240:
        sanitized = sanitized[:237] + "..."
    return sanitized


# --- Main scan ---
global_max_id = 0  # track max lesson ID across all projects for checkpoint
confirmed = []  # (project_id, lesson_id, reason)
review = []     # (project_id, lesson_id, title_snip, related, last_ref)
eff_confirmed = []  # (project_id, lesson_id, title_snip, inj_count, hlp_count)
eff_review = []     # (project_id, lesson_id, title_snip, inj_count, hlp_count, rate)

for project in projects:
    project_id = project["id"]
    project_status = project.get("status", "active")
    project_root = project_root_map.get(project_id, SCRIPT_DIR)
    lessons_file = SCRIPT_DIR / "projects" / project_id / "lessons.yaml"

    if not lessons_file.exists():
        continue

    with open(lessons_file, encoding="utf-8") as f:
        data = yaml.safe_load(f)
    if not isinstance(data, dict):
        continue
    lessons = data.get("lessons", [])
    if not isinstance(lessons, list):
        continue

    for lesson in lessons:
        if not isinstance(lesson, dict):
            continue
        if is_deprecated(lesson):
            continue  # already deprecated: skip

        lesson_id = lesson.get("id", "?")
        m_id = re.match(r'^L(\d+)$', lesson_id)
        if m_id:
            global_max_id = max(global_max_id, int(m_id.group(1)))
        title = lesson.get("title", "")
        summary = lesson.get("summary", "")
        full_text = f"{title} {summary}"

        # (a-1) Confirmed: lesson belongs to an archived project
        if project_status == "archived":
            confirmed.append((project_id, lesson_id, f"{project_id}プロジェクト(archived)"))
            continue

        # (a-2) Confirmed: explicit file path in text -> file no longer exists
        added_confirmed = False
        for ref in find_file_refs(full_text):
            if not ref_exists(project_root, ref):
                confirmed.append((project_id, lesson_id, f"{ref}参照（ファイル消滅）"))
                added_confirmed = True
                break

        if added_confirmed:
            continue

        # (b) Review recommended: .sh script name mentioned + that script exists in scripts/
        for sname in find_script_names(full_text):
            if script_exists(project_root, sname):
                title_snip = (title or summary)[:60]
                lref = last_ref_text(project_id, lesson_id)
                review.append((
                    project_id, lesson_id,
                    f'"{title_snip}"',
                    f"scripts/{sname} 現存(仕組み化済みの可能性)",
                    lref,
                ))
                break

        # (c) Effectiveness rate check
        # Safety pattern: project-aware MAX(YAML, TSV) to avoid stale-cache false positives.
        yaml_inj = lesson.get("injection_count", 0) or 0
        yaml_hlp = lesson.get("helpful_count", 0) or 0
        count_key = (project_id, lesson_id)
        inj_count = max(yaml_inj, tsv_injection_count.get(count_key, 0))
        hlp_count = max(yaml_hlp, tsv_helpful_count.get(count_key, 0))

        # (c-1) Confirmed: injection >= 5 and effectiveness == 0%
        if inj_count >= 5 and hlp_count == 0:
            title_snip = (title or summary)[:60]
            eff_confirmed.append((project_id, lesson_id, title_snip, inj_count, hlp_count))
        # (c-2) Review: injection >= 10 and effectiveness < 10%
        elif inj_count >= 10:
            rate = hlp_count / inj_count * 100
            if rate < 10:
                title_snip = (title or summary)[:60]
                eff_review.append((project_id, lesson_id, title_snip, inj_count, hlp_count, rate))

# --- Output ---
print("=== 確定candidate（自動） ===")
if confirmed:
    for proj, lid, reason in confirmed:
        print(f"  [{proj}] {lid}: {reason}")
else:
    print("  (なし)")

print()
print("=== 審査推奨（材料提示のみ） ===")
if review:
    for proj, lid, title_snip, related, lref in review:
        print(f"  [{proj}] {lid}: {title_snip}")
        print(f"        → 関連: {related}")
        print(f"        → 最終参照: {lref}")
        print(f"        ★ 構造防止済みの可能性あり。家老判断を推奨")
else:
    print("  (なし)")

print()
print("=== 有効率0% 確定candidate (注入N≥5) ===")
if eff_confirmed:
    for proj, lid, title_snip, inj, hlp in eff_confirmed:
        print(f"  [{proj}] {lid}: {title_snip} (injected={inj}, helpful=0)")
else:
    print("  (なし)")

print()
print("=== 有効率<10% 自動退役対象 (注入N≥10) ===")
if eff_review:
    for proj, lid, title_snip, inj, hlp, rate in eff_review:
        print(f"  [{proj}] {lid}: {title_snip} (injected={inj}, helpful={hlp}, rate={rate:.0f}%)")
else:
    print("  (なし)")

# cmd_531: 自動退役実行
deprecate_script = str(SCRIPT_DIR / "scripts" / "lesson_deprecate.sh")
auto_deprecated_count = 0

print()
print("=== 自動退役実行 ===")

# AC5: ファイル消滅教訓の自動退役
for proj, lid, reason in confirmed:
    if "ファイル消滅" in reason:
        safe_reason = sanitize_reason(f"AUTO-DEPRECATE(file_missing): {reason}")
        result = subprocess.run(
            ["bash", deprecate_script, proj, lid, safe_reason],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            print(f"  [AUTO] DEPRECATED: [{proj}] {lid} ({reason})")
            auto_deprecated_count += 1
        else:
            print(f"  [AUTO] WARN: {lid} deprecation failed: {result.stderr.strip()}", file=sys.stderr)

# AC4: 有効率10%未満 × 注入10回以上の自動退役
for proj, lid, title_snip, inj, hlp in eff_confirmed:
    if inj >= 10:
        safe_reason = sanitize_reason(
            f"AUTO-DEPRECATE(low_effectiveness): rate=0% injected={inj} helpful=0"
        )
        result = subprocess.run(
            ["bash", deprecate_script, proj, lid, safe_reason],
            capture_output=True, text=True
        )
        if result.returncode == 0:
            print(f"  [AUTO] DEPRECATED: [{proj}] {lid} (rate=0%, injected={inj})")
            auto_deprecated_count += 1
        else:
            print(f"  [AUTO] WARN: {lid} deprecation failed: {result.stderr.strip()}", file=sys.stderr)

for proj, lid, title_snip, inj, hlp, rate in eff_review:
    safe_reason = sanitize_reason(
        f"AUTO-DEPRECATE(low_effectiveness): rate={rate:.0f}% injected={inj} helpful={hlp}"
    )
    result = subprocess.run(
        ["bash", deprecate_script, proj, lid, safe_reason],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        print(f"  [AUTO] DEPRECATED: [{proj}] {lid} (rate={rate:.0f}%, injected={inj})")
        auto_deprecated_count += 1
    else:
        print(f"  [AUTO] WARN: {lid} deprecation failed: {result.stderr.strip()}", file=sys.stderr)

print(f"  合計: {auto_deprecated_count}件 自動退役")

# --- Checkpoint update ---
if global_max_id > 0:
    checkpoint_path = SCRIPT_DIR / "queue" / "lesson_deprecation_checkpoint.txt"
    with open(checkpoint_path, "w") as f:
        f.write(f"L{global_max_id}\n")
    print(f"\nCheckpoint updated: L{global_max_id}")
PYEOF
