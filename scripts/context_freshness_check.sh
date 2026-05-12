#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-}"
ARG="${2:-}"
STALE_DAYS="${CONTEXT_STALE_DAYS:-7}"
EXCLUDE_FILES=(
    "README.md"
    "cdp-philosophy.md"
    "cdp-severity.md"
    "checklist-alm-registration.md"
    "checklist-shin-v2-registration.md"
    "checklist-ward-fof-production.md"
)
EXCLUDE_FILES_CSV="$(IFS=,; printf '%s' "${EXCLUDE_FILES[*]}")"

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

# GP-082: Accept pre-computed archive cache via env var CFC_ARCHIVE_CACHE
# When called from dashboard_auto_section.sh, the cache is already generated
# by the shared gawk pass (zero extra I/O). Standalone calls fall back to Python scan.
_ARCHIVE_CACHE="${CFC_ARCHIVE_CACHE:-/tmp/dashboard_arch_cfc_cache.txt}"

_CACHE_TTL="${CFC_OUTPUT_CACHE_TTL:-2}"
_ROOT_KEY="$(printf '%s' "$SCRIPT_DIR" | cksum | awk '{print $1}')"
_MODE_KEY="$(printf '%s|%s|%s|%s|%s|%s' "$MODE" "$ARG" "$STALE_DAYS" "$_ARCHIVE_CACHE" "$EXCLUDE_FILES_CSV" "$(date +%Y-%m-%d)" | cksum | awk '{print $1}')"
_CACHE_FILE="/tmp/context_freshness_check_${_ROOT_KEY}_${_MODE_KEY}.cache"

if [[ "$_CACHE_TTL" =~ ^[0-9]+$ ]] && [[ "$_CACHE_TTL" -gt 0 ]] && [[ -f "$_CACHE_FILE" ]]; then
    _NOW="$(date +%s)"
    _MTIME="$(stat -c %Y "$_CACHE_FILE" 2>/dev/null || echo 0)"
    if [[ $((_NOW - _MTIME)) -lt "$_CACHE_TTL" ]]; then
        cat "$_CACHE_FILE"
        exit 0
    fi
fi

_TMP_CACHE="${_CACHE_FILE}.$$"
python3 - "$SCRIPT_DIR" "$MODE" "$ARG" "$STALE_DAYS" "$_ARCHIVE_CACHE" "$EXCLUDE_FILES_CSV" > "$_TMP_CACHE" <<'PY'
from __future__ import annotations

from datetime import date, timedelta
import glob
import os
import re
import sys

root = sys.argv[1]
mode = sys.argv[2]
cmd_id = sys.argv[3]
threshold_days = int(sys.argv[4])
archive_cache_path = sys.argv[5] if len(sys.argv) > 5 else ""
exclude_files = {
    item.strip()
    for item in (sys.argv[6] if len(sys.argv) > 6 else "").split(",")
    if item.strip()
}
cutoff_date = date.today() - timedelta(days=threshold_days)
FINAL_STATUSES = {"completed", "done", "complete", "success"}


def normalize_rel(path: str) -> str:
    return os.path.relpath(path, root).replace(os.sep, "/")


def extract_date(value: str | None) -> date | None:
    if not value:
        return None
    text = str(value)

    iso_match = re.search(r"(\d{4}-\d{2}-\d{2})", text)
    if iso_match:
        try:
            return date.fromisoformat(iso_match.group(1))
        except ValueError:
            return None

    compact_match = re.search(r"(?<!\d)(\d{8})(?!\d)", text)
    if not compact_match:
        return None

    compact = compact_match.group(1)
    try:
        return date(
            int(compact[0:4]),
            int(compact[4:6]),
            int(compact[6:8]),
        )
    except ValueError:
        return None


def normalize_scalar(value: str) -> str:
    text = str(value).strip()
    if len(text) >= 2 and (
        (text.startswith('"') and text.endswith('"'))
        or (text.startswith("'") and text.endswith("'"))
    ):
        text = text[1:-1]
    return text.strip()


def load_projects():
    active_ids: list[str] = []
    explicit_context_map: dict[str, str] = {}
    current: dict[str, object] | None = None
    projects: list[dict[str, object]] = []
    in_context_files = False

    def flush_current() -> None:
        if current:
            projects.append(current)

    path = os.path.join(root, "config", "projects.yaml")
    try:
        with open(path, encoding="utf-8") as f:
            for raw_line in f:
                line = raw_line.split("#", 1)[0].rstrip()
                stripped = line.strip()
                if not stripped:
                    continue

                if line.startswith("  - "):
                    flush_current()
                    current = {}
                    in_context_files = False
                    remainder = stripped[2:].strip()
                    if ":" in remainder:
                        key, value = remainder.split(":", 1)
                        current[key.strip()] = normalize_scalar(value)
                    continue

                if current is None:
                    continue

                if line.startswith("    ") and not line.startswith("      "):
                    if ":" not in stripped:
                        continue
                    key, value = stripped.split(":", 1)
                    key = key.strip()
                    value = value.strip()
                    in_context_files = key == "context_files"
                    if value:
                        current[key] = normalize_scalar(value)
                    continue

                if in_context_files and line.startswith("      - "):
                    item = stripped[2:].strip()
                    if item.startswith("file:"):
                        rel = normalize_scalar(item.split(":", 1)[1])
                        if rel:
                            current.setdefault("context_files", []).append(rel)
    except Exception:
        projects = []
    else:
        flush_current()

    for project in projects:
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
            for rel in context_files:
                if rel:
                    explicit_context_map[str(rel)] = project_id

    return active_ids, explicit_context_map


ACTIVE_PROJECT_IDS, EXPLICIT_CONTEXT_MAP = load_projects()
SORTED_PROJECT_IDS = sorted(ACTIVE_PROJECT_IDS, key=len, reverse=True)
LAST_UPDATED_RE = re.compile(r"<!--\s*last_updated:\s*(\d{4}-\d{2}-\d{2})\b")
CHRONICLE_MONTH_RE = re.compile(r"^##\s+(\d{4})-(\d{2})\s*$")
CHRONICLE_ROW_RE = re.compile(
    r"^\|\s*(cmd_[^| ]+)\s*\|[^|]*\|\s*([^|]+?)\s*\|\s*(\d{2}-\d{2})\s*\|"
)
PROJECT_LINE_PATTERNS = [
    (
        project_id,
        re.compile(rf"^\s*project:\s*['\"]?{re.escape(project_id)}['\"]?\s*$"),
    )
    for project_id in SORTED_PROJECT_IDS
]
STATUS_LINE_RE = re.compile(r"^\s*status:\s*['\"]?([A-Za-z_]+)['\"]?\s*$")
DATE_FIELD_PATTERNS = [
    re.compile(rf"^\s*{field}:\s*(.+?)\s*$")
    for field in ("completed_at", "archived_at", "updated_at")
]
ARCHIVE_SCAN_MAX_LINES = 80


def infer_project_id(rel_path: str) -> str | None:
    if rel_path in EXPLICIT_CONTEXT_MAP:
        return EXPLICIT_CONTEXT_MAP[rel_path]

    base = os.path.basename(rel_path)
    if base == "infrastructure.md":
        return "infra"

    for project_id in SORTED_PROJECT_IDS:
        if base.startswith(f"{project_id}.") or base.startswith(f"{project_id}-"):
            return project_id

    # Fallback: context/ files with no explicit project match belong to 'infra'.
    # Covers gunshi-*.md, karo-operations.md, growth-loop.md etc. that are
    # infra-scoped but not listed in config/projects.yaml context_files.
    if rel_path.startswith("context/") and "infra" in ACTIVE_PROJECT_IDS:
        return "infra"

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
            for _ in range(5):
                line = f.readline()
                if not line:
                    break
                m = LAST_UPDATED_RE.search(line)
                if not m:
                    continue
                try:
                    updated_at = date.fromisoformat(m.group(1))
                except ValueError:
                    return None
                return (date.today() - updated_at).days
    except Exception:
        return None

    return None

def scan_archive_metadata(abs_path: str) -> tuple[str, str, str]:
    project_id = ""
    status = ""
    stamp = ""

    try:
        with open(abs_path, encoding="utf-8") as f:
            for idx, line in enumerate(f):
                if idx >= ARCHIVE_SCAN_MAX_LINES:
                    break

                if not project_id:
                    stripped = line.rstrip("\n")
                    for candidate_id, pattern in PROJECT_LINE_PATTERNS:
                        if pattern.match(stripped):
                            project_id = candidate_id
                            break

                if not status:
                    status_match = STATUS_LINE_RE.match(line)
                    if status_match:
                        status_value = status_match.group(1).strip().lower()
                        if status_value in ("completed", "done", "complete", "success"):
                            status = status_value

                if not stamp:
                    for pattern in DATE_FIELD_PATTERNS:
                        date_match = pattern.match(line)
                        if not date_match:
                            continue
                        parsed = extract_date(date_match.group(1))
                        if parsed:
                            stamp = str(parsed)
                            break

                if project_id and status and stamp:
                    break
    except Exception:
        return "", "", ""

    return project_id, status, stamp


_recent_cmd_cache: dict[str, bool] = {}
_archive_entries: list[tuple[str, str, str, str]] | None = None
_chronicle_rows: list[tuple[str, str, date]] | None = None
_chronicle_recent_projects: set[str] | None = None
_chronicle_is_fresh: bool | None = None


def load_cmd_chronicle_rows() -> list[tuple[str, str, date]]:
    global _chronicle_rows, _chronicle_is_fresh
    if _chronicle_rows is not None:
        return _chronicle_rows

    _chronicle_rows = []
    _chronicle_is_fresh = False
    chronicle_path = os.path.join(root, "context", "cmd-chronicle.md")
    if not os.path.isfile(chronicle_path):
        return _chronicle_rows

    current_year: int | None = None
    current_month: int | None = None

    try:
        with open(chronicle_path, encoding="utf-8") as f:
            for raw_line in f:
                line = raw_line.rstrip("\n")

                month_match = CHRONICLE_MONTH_RE.match(line)
                if month_match:
                    current_year = int(month_match.group(1))
                    current_month = int(month_match.group(2))
                    continue

                row_match = CHRONICLE_ROW_RE.match(line)
                if not row_match or current_year is None or current_month is None:
                    continue

                project_id = row_match.group(2).strip()
                if not project_id or project_id == "—":
                    continue

                month_text, day_text = row_match.group(3).split("-", 1)
                try:
                    row_date = date(current_year, int(month_text), int(day_text))
                except ValueError:
                    continue

                _chronicle_rows.append((row_match.group(1).strip(), project_id, row_date))
    except Exception:
        _chronicle_rows = []
        _chronicle_is_fresh = False
        return _chronicle_rows

    _chronicle_is_fresh = any(row_date >= cutoff_date for _, _, row_date in _chronicle_rows)
    return _chronicle_rows


def recent_projects_from_chronicle() -> set[str]:
    global _chronicle_recent_projects
    if _chronicle_recent_projects is not None:
        return _chronicle_recent_projects

    _chronicle_recent_projects = {
        project_id
        for _, project_id, row_date in load_cmd_chronicle_rows()
        if row_date >= cutoff_date
    }
    return _chronicle_recent_projects

def _load_archive_entries() -> list[tuple[str, str, str, str]]:
    """Load archive entries from gawk cache (GP-082) or fallback to file scan."""
    global _archive_entries
    if _archive_entries is not None:
        return _archive_entries
    _archive_entries = []

    # GP-082: Use pre-computed gawk cache if available
    if archive_cache_path and os.path.isfile(archive_cache_path):
        with open(archive_cache_path, encoding="utf-8") as f:
            for line in f:
                parts = line.strip().split("|", 3)
                if len(parts) < 4:
                    continue
                fname, proj, status, dt = parts
                _archive_entries.append((fname, proj, status, dt))
        return _archive_entries

    # Fallback: direct scan (for --cmd-warnings or standalone use)
    # Only recent archive files can affect cutoff_date, so skip older files
    # before opening them to keep standalone scans bounded by STALE_DAYS.
    archive_dir = os.path.join(root, "queue", "archive", "cmds")
    if not os.path.isdir(archive_dir):
        return _archive_entries
    candidates: list[tuple[date, str]] = []
    for fname in os.listdir(archive_dir):
        if not fname.endswith(".yaml"):
            continue
        fdate = extract_date(fname)
        if fdate and fdate < cutoff_date:
            continue
        candidates.append((fdate or date.min, fname))

    for _, fname in sorted(candidates, reverse=True):
        fpath = os.path.join(archive_dir, fname)
        proj, status, dt = scan_archive_metadata(fpath)
        if not proj:
            continue
        _archive_entries.append((fname, proj, status, dt))
    return _archive_entries

def project_has_recent_completed_cmd(project_id: str) -> bool:
    if project_id in _recent_cmd_cache:
        return _recent_cmd_cache[project_id]

    chronicle_projects = recent_projects_from_chronicle()
    if _chronicle_is_fresh:
        result = project_id in chronicle_projects
        _recent_cmd_cache[project_id] = result
        return result

    entries = _load_archive_entries()
    for fname, proj, status, dt in entries:
        if proj != project_id:
            continue
        if status not in ("completed", "done", "complete", "success"):
            continue
        d = extract_date(dt) if dt else extract_date(fname)
        if d and d >= cutoff_date:
            _recent_cmd_cache[project_id] = True
            return True
    _recent_cmd_cache[project_id] = False
    return False


def find_cmd_project(target_cmd_id: str) -> str | None:
    def find_project_in_command_file(path: str) -> str | None:
        current_cmd: str | None = None
        in_commands = False
        top_level_match = False

        try:
            with open(path, encoding="utf-8") as f:
                for raw_line in f:
                    line = raw_line.rstrip("\n")
                    stripped = line.strip()
                    if not stripped or stripped.startswith("#"):
                        continue

                    indent = len(line) - len(line.lstrip(" "))

                    if indent == 0 and stripped == "commands:":
                        in_commands = True
                        current_cmd = None
                        top_level_match = False
                        continue

                    if indent == 0 and in_commands and stripped != "commands:":
                        in_commands = False
                        current_cmd = None

                    if indent == 0 and stripped.startswith("id:"):
                        top_level_match = normalize_scalar(stripped.split(":", 1)[1]) == target_cmd_id
                        continue

                    if top_level_match and indent == 0 and stripped.startswith("project:"):
                        return normalize_scalar(stripped.split(":", 1)[1]) or None

                    if not in_commands:
                        continue

                    if stripped.startswith("- id:"):
                        current_cmd = normalize_scalar(stripped.split(":", 1)[1])
                        continue

                    if indent == 2 and stripped.endswith(":") and not stripped.startswith("- "):
                        current_cmd = normalize_scalar(stripped[:-1])
                        continue

                    if current_cmd == target_cmd_id and stripped.startswith("project:"):
                        return normalize_scalar(stripped.split(":", 1)[1]) or None
        except Exception:
            return None

        return None

    candidates = [os.path.join(root, "queue", "shogun_to_karo.yaml")]

    for current_cmd_id, project_id, _ in load_cmd_chronicle_rows():
        if current_cmd_id == target_cmd_id:
            return project_id

    candidates.extend(
        sorted(
            glob.glob(os.path.join(root, "queue", "archive", "cmds", f"{target_cmd_id}_*.yaml")),
            reverse=True,
        )
    )

    for path in candidates:
        project_id = find_project_in_command_file(path)
        if project_id:
            return project_id
        if path.endswith(".yaml") and os.path.basename(path).startswith(f"{target_cmd_id}_"):
            project_id, _, _ = scan_archive_metadata(path)
            if project_id:
                return project_id
    return None


def build_warning(rel_path: str, days_old: int | None) -> str:
    if days_old is None:
        return f"WARN: {rel_path} last_updated 未記載。更新要否を確認せよ"
    return f"WARN: {rel_path} last_updated {days_old}日前。更新要否を確認せよ"


def is_excluded_context_file(rel_path: str) -> bool:
    return os.path.basename(rel_path) in exclude_files


warnings: list[str] = []

if mode == "--dashboard-warnings":
    recent_project_cache: dict[str, bool] = {}
    for project_id, rel_path, abs_path in iter_context_files():
        if is_excluded_context_file(rel_path):
            continue
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
            if is_excluded_context_file(rel_path):
                continue
            days_old = last_updated_days(abs_path)
            if days_old is None or days_old >= threshold_days:
                warnings.append(build_warning(rel_path, days_old))

for line in sorted(dict.fromkeys(warnings)):
    print(line)
PY
_PY_STATUS=$?
if [[ "$_PY_STATUS" -eq 0 ]]; then
    mv "$_TMP_CACHE" "$_CACHE_FILE"
    cat "$_CACHE_FILE"
else
    rm -f "$_TMP_CACHE"
fi
exit "$_PY_STATUS"
