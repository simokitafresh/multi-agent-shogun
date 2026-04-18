#!/usr/bin/env bash
# lesson_harvest.sh — アーカイブ済み報告からlesson_candidate未登録候補をスキャン
# Usage: bash scripts/lesson_harvest.sh
# Output: cmd_id | ninja | title | detail(先頭60文字)

set -euo pipefail

SCRIPT_DIR="${LESSON_HARVEST_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
REPO_ROOT="${LESSON_HARVEST_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

ARCHIVE_DIR="${LESSON_HARVEST_ARCHIVE_DIR:-$REPO_ROOT/queue/archive/reports}"
PROJECTS_DIR="${LESSON_HARVEST_PROJECTS_DIR:-$REPO_ROOT/projects}"

if [[ ! -d "$ARCHIVE_DIR" ]]; then
    echo "アーカイブディレクトリが存在しません: $ARCHIVE_DIR" >&2
    exit 1
fi

if ! command -v rg >/dev/null 2>&1; then
    echo "rg が見つかりません: lesson_harvest.sh は ripgrep 必須です" >&2
    exit 1
fi

python3 - "$ARCHIVE_DIR" "$PROJECTS_DIR" <<'PYEOF'
import sys
import re
import subprocess
import os
from pathlib import Path

import yaml

archive_dir = Path(sys.argv[1])
projects_dir = Path(sys.argv[2])

_DICT_RE = re.compile(r"'(?:content|summary|lesson|title)'\s*:\s*['\"](.+)", re.DOTALL)
_REPORT_LINE_RE = re.compile(
    r"^(worker_id|task_id|parent_cmd|lesson_candidate|skill_candidate|decision_candidate):"
    r"|^  (found|title|detail):"
)


def parse_inline_scalar(raw):
    raw = raw.strip()
    if not raw:
        return ""
    if raw[0] == raw[-1] and raw[0] in ('"', "'"):
        value = raw[1:-1]
        if raw[0] == "'":
            value = value.replace("''", "'")
        else:
            value = value.replace(r"\"", '"')
        return value
    if raw == "true":
        return True
    if raw == "false":
        return False
    return raw


def extract_from_stringified_dict(s):
    """Extract value from stringified dict like "{'id': 'LC1', 'content': '...'}"."""
    if not (s.startswith("{") and "'" in s):
        return s
    m = _DICT_RE.search(s)
    if m:
        val = m.group(1).rstrip("'\"} ")
        if val:
            return val
    return s


def extract_lesson_field(value):
    if isinstance(value, dict):
        return str(
            value.get("content", "")
            or value.get("summary", "")
            or value.get("lesson", "")
            or value.get("title", "")
            or value.get("id", "")
            or str(value)
        )
    if isinstance(value, list):
        return str(value[0]) if value else ""
    return extract_from_stringified_dict(str(value).strip())


def load_registered_titles():
    rg_env = os.environ.copy()
    rg_env["LC_ALL"] = "C"
    cmd = [
        "rg",
        "-uuu",
        "-n",
        r"^\s+title:\s*",
        "--glob",
        "**/lessons.yaml",
        "--glob",
        "**/lessons_archive.yaml",
        str(projects_dir),
    ]
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
        env=rg_env,
    )
    if proc.returncode not in (0, 1):
        raise RuntimeError(proc.stderr.strip() or "rg failed")

    titles = set()
    for line in proc.stdout.splitlines():
        try:
            _, _, text = line.split(":", 2)
        except ValueError:
            continue
        raw = text.split(":", 1)[1].strip()
        title = str(parse_inline_scalar(raw) or "").strip()
        if title:
            titles.add(title)
    return titles


def load_report_fallback(report_path):
    try:
        with report_path.open(encoding="utf-8") as f:
            data = yaml.safe_load(f)
    except Exception:
        return None
    if not data or not isinstance(data, dict):
        return None

    lc = data.get("lesson_candidate")
    if not lc or not isinstance(lc, dict):
        return None
    if lc.get("found") is not True:
        return None

    title = extract_lesson_field(lc.get("title", ""))
    if not title:
        return None

    detail = extract_lesson_field(lc.get("detail", ""))
    detail = detail.replace("\n", " ")[:60]

    cmd_id = data.get("parent_cmd", "") or data.get("task_id", "") or ""
    worker = data.get("worker_id", "")
    return (str(cmd_id), str(worker), str(title).strip(), detail)


def fast_scan_candidates(registered_titles):
    rg_env = os.environ.copy()
    rg_env["LC_ALL"] = "C"
    cmd = [
        "rg",
        "-uuu",
        "-n",
        _REPORT_LINE_RE.pattern,
        "--glob",
        "*_report_*.yaml",
        str(archive_dir),
    ]
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
        env=rg_env,
    )
    if proc.returncode not in (0, 1):
        raise RuntimeError(proc.stderr.strip() or "rg failed")

    rows = {}
    fallback_paths = set()

    def needs_fallback(raw):
        if raw in {"|", ">", "|-", ">-", "|+", ">+"}:
            return True
        if raw.startswith("{") or raw.startswith("["):
            return True
        if raw[:1] in {"'", '"'} and ("{" in raw or "[" in raw):
            return True
        return False

    for line in proc.stdout.splitlines():
        try:
            path_str, _, text = line.split(":", 2)
        except ValueError:
            continue
        path = Path(path_str)
        row = rows.setdefault(
            path,
            {
                "worker": "",
                "task": "",
                "parent": "",
                "section": None,
                "lesson_found": False,
                "lesson_title": "",
                "lesson_detail": "",
            },
        )
        if text.startswith("worker_id:"):
            row["worker"] = str(parse_inline_scalar(text.split(":", 1)[1]) or "")
            continue
        if text.startswith("task_id:"):
            row["task"] = str(parse_inline_scalar(text.split(":", 1)[1]) or "")
            continue
        if text.startswith("parent_cmd:"):
            row["parent"] = str(parse_inline_scalar(text.split(":", 1)[1]) or "")
            continue
        if text.endswith(":") and not text.startswith("  "):
            row["section"] = text[:-1]
            continue
        if row["section"] != "lesson_candidate":
            continue

        stripped = text.strip()
        if stripped == "found: true":
            row["lesson_found"] = True
            continue
        if stripped.startswith("title:"):
            raw = stripped.split(":", 1)[1].strip()
            row["lesson_title"] = extract_lesson_field(parse_inline_scalar(raw))
            if needs_fallback(raw):
                fallback_paths.add(path)
            continue
        if stripped.startswith("detail:"):
            raw = stripped.split(":", 1)[1].strip()
            row["lesson_detail"] = extract_lesson_field(parse_inline_scalar(raw))
            if needs_fallback(raw):
                fallback_paths.add(path)

    candidates = []
    for path in sorted(rows):
        row = rows[path]
        if not row["lesson_found"]:
            continue
        if path in fallback_paths or not row["lesson_title"] or not row["lesson_detail"]:
            fallback = load_report_fallback(path)
            if fallback is None:
                continue
            if fallback[2] in registered_titles:
                continue
            candidates.append(fallback)
            continue

        title = row["lesson_title"].strip()
        if title in registered_titles:
            continue

        detail = row["lesson_detail"].replace("\n", " ")[:60]
        cmd_id = row["parent"] or row["task"] or ""
        candidates.append((str(cmd_id), str(row["worker"]), title, detail))
    return candidates


registered_titles = load_registered_titles()
try:
    candidates = fast_scan_candidates(registered_titles)
except RuntimeError as exc:
    print(str(exc), file=sys.stderr)
    sys.exit(1)

if not candidates:
    print("未登録候補なし")
else:
    print(f"未登録候補: {len(candidates)}件")
    print("-" * 100)
    for cmd_id, worker, title, detail in candidates:
        print(f"{cmd_id} | {worker} | {title} | {detail}")
PYEOF
