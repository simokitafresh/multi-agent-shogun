#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-}"
ARG="${2:-}"
STALE_DAYS="${CONTEXT_STALE_DAYS:-7}"

usage() {
    cat <<'EOF'
Usage:
  bash scripts/context_freshness_check.sh --dashboard-warnings
  bash scripts/context_freshness_check.sh --cmd-warnings <cmd_id>
EOF
}

case "$MODE" in
    --dashboard-warnings)
        ;;
    --cmd-warnings)
        if [[ -z "$ARG" ]]; then
            usage >&2
            exit 1
        fi
        ;;
    *)
        usage >&2
        exit 1
        ;;
esac

python3 - "$SCRIPT_DIR" "$MODE" "$ARG" "$STALE_DAYS" <<'PY'
from __future__ import annotations

from datetime import date, timedelta
import glob
import os
import re
import sys

import yaml

root = sys.argv[1]
mode = sys.argv[2]
cmd_id = sys.argv[3]
threshold_days = int(sys.argv[4])
cutoff_date = date.today() - timedelta(days=threshold_days)


def load_yaml(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def normalize_rel(path: str) -> str:
    return os.path.relpath(path, root).replace(os.sep, "/")


def extract_date(value: str | None) -> date | None:
    if not value:
        return None
    m = re.search(r"(\d{4}-\d{2}-\d{2})", str(value))
    if not m:
        return None
    try:
        return date.fromisoformat(m.group(1))
    except ValueError:
        return None


def load_projects():
    data = load_yaml(os.path.join(root, "config", "projects.yaml"))
    projects = data.get("projects", []) if isinstance(data, dict) else []

    active_ids: list[str] = []
    explicit_context_map: dict[str, str] = {}

    for project in projects:
        if not isinstance(project, dict):
            continue
        if str(project.get("status", "active")).strip() != "active":
            continue

        project_id = str(project.get("id", "")).strip()
        if not project_id:
            continue

        active_ids.append(project_id)

        context_file = str(project.get("context_file", "")).strip()
        if context_file:
            explicit_context_map[context_file] = project_id

        context_files = project.get("context_files", [])
        if isinstance(context_files, list):
            for item in context_files:
                if not isinstance(item, dict):
                    continue
                rel = str(item.get("file", "")).strip()
                if rel:
                    explicit_context_map[rel] = project_id

    return active_ids, explicit_context_map


ACTIVE_PROJECT_IDS, EXPLICIT_CONTEXT_MAP = load_projects()


def infer_project_id(rel_path: str) -> str | None:
    if rel_path in EXPLICIT_CONTEXT_MAP:
        return EXPLICIT_CONTEXT_MAP[rel_path]

    base = os.path.basename(rel_path)
    if base == "infrastructure.md":
        return "infra"

    for project_id in sorted(ACTIVE_PROJECT_IDS, key=len, reverse=True):
        if base.startswith(f"{project_id}.") or base.startswith(f"{project_id}-"):
            return project_id

    return None


def iter_context_files():
    seen: set[str] = set()
    candidates = set(glob.glob(os.path.join(root, "context", "*.md")))
    for rel in EXPLICIT_CONTEXT_MAP:
        candidates.add(os.path.join(root, rel))

    for abs_path in sorted(candidates):
        rel_path = normalize_rel(abs_path)
        if rel_path in seen:
            continue
        seen.add(rel_path)

        project_id = infer_project_id(rel_path)
        if not project_id:
            continue

        yield project_id, rel_path, abs_path


def last_updated_days(abs_path: str) -> int | None:
    try:
        with open(abs_path, encoding="utf-8") as f:
            text = f.read()
    except Exception:
        return None

    m = re.search(r"<!--\s*last_updated:\s*(\d{4}-\d{2}-\d{2})\b", text)
    if not m:
        return None

    try:
        updated_at = date.fromisoformat(m.group(1))
    except ValueError:
        return None

    return (date.today() - updated_at).days


_recent_cmd_cache: dict[str, bool] = {}
_archive_project_index: dict[str, list[str]] | None = None

def _build_archive_index() -> dict[str, list[str]]:
    """Build project→files index from archive dir (one-time scan per run)."""
    global _archive_project_index
    if _archive_project_index is not None:
        return _archive_project_index
    archive_dir = os.path.join(root, "queue", "archive", "cmds")
    _archive_project_index = {}
    if not os.path.isdir(archive_dir):
        return _archive_project_index
    # GP-074: scan only recent files (last 14 days by filename date)
    cutoff_14d = date.today() - timedelta(days=14)
    for fname in os.listdir(archive_dir):
        if not fname.endswith(".yaml"):
            continue
        fpath = os.path.join(archive_dir, fname)
        # Quick date check from filename first
        fdate = extract_date(fname)
        if fdate and fdate < cutoff_14d:
            continue
        # If no date in filename, include it (conservative)
        try:
            with open(fpath, encoding="utf-8") as f:
                text = f.read(4096)  # First 4KB is enough for metadata
        except Exception:
            continue
        for pid in ACTIVE_PROJECT_IDS:
            if f"project: {pid}" in text or f"project: '{pid}'" in text:
                _archive_project_index.setdefault(pid, []).append(fpath)
    return _archive_project_index

def project_has_recent_completed_cmd(project_id: str) -> bool:
    if project_id in _recent_cmd_cache:
        return _recent_cmd_cache[project_id]
    # GP-074: pre-indexed scan, no yaml.safe_load
    index = _build_archive_index()
    candidate_paths = index.get(project_id, [])

    for path in candidate_paths:
        # Quick text scan: check project, status, and date without full YAML parse
        try:
            with open(path, encoding="utf-8") as f:
                text = f.read()
        except Exception:
            continue
        if f"project: {project_id}" not in text and f"project: '{project_id}'" not in text:
            continue
        if "status: completed" not in text and "status: done" not in text:
            continue
        # Extract date from text (any date in the file near completed_at/archived_at)
        for date_field in ("completed_at:", "archived_at:", "updated_at:", "delegated_at:", "created_at:"):
            idx = text.find(date_field)
            if idx < 0:
                continue
            snippet = text[idx:idx+60]
            d = extract_date(snippet)
            if d and d >= cutoff_date:
                _recent_cmd_cache[project_id] = True
                return True
        # Fallback: date from filename
        d = extract_date(os.path.basename(path))
        if d and d >= cutoff_date:
            _recent_cmd_cache[project_id] = True
            return True

    _recent_cmd_cache[project_id] = False
    return False


def find_cmd_project(target_cmd_id: str) -> str | None:
    candidates = [os.path.join(root, "queue", "shogun_to_karo.yaml")]
    candidates.extend(
        sorted(
            glob.glob(os.path.join(root, "queue", "archive", "cmds", f"{target_cmd_id}_*.yaml")),
            reverse=True,
        )
    )

    for path in candidates:
        data = load_yaml(path)
        commands = data.get("commands", []) if isinstance(data, dict) else []
        if not isinstance(commands, list):
            continue
        for command in commands:
            if not isinstance(command, dict):
                continue
            if str(command.get("id", "")).strip() == target_cmd_id:
                project_id = str(command.get("project", "")).strip()
                return project_id or None
    return None


def build_warning(rel_path: str, days_old: int | None) -> str:
    if days_old is None:
        return f"WARN: {rel_path} last_updated 未記載。更新要否を確認せよ"
    return f"WARN: {rel_path} last_updated {days_old}日前。更新要否を確認せよ"


warnings: list[str] = []

if mode == "--dashboard-warnings":
    recent_project_cache: dict[str, bool] = {}
    for project_id, rel_path, abs_path in iter_context_files():
        if project_id not in recent_project_cache:
            recent_project_cache[project_id] = project_has_recent_completed_cmd(project_id)
        if not recent_project_cache[project_id]:
            continue

        days_old = last_updated_days(abs_path)
        if days_old is None or days_old >= threshold_days:
            warnings.append(build_warning(rel_path, days_old))
elif mode == "--cmd-warnings":
    project_id = find_cmd_project(cmd_id)
    if project_id:
        for current_project, rel_path, abs_path in iter_context_files():
            if current_project != project_id:
                continue
            days_old = last_updated_days(abs_path)
            if days_old is None or days_old >= threshold_days:
                warnings.append(build_warning(rel_path, days_old))

for line in sorted(dict.fromkeys(warnings)):
    print(line)
PY
