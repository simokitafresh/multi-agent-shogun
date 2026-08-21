#!/usr/bin/env bash
# semantic-links: [[ゲート品質統合フレームワーク]] [[context鮮度偽陽性_経過日数判定]]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-}"
ARG="${2:-}"
STALE_DAYS="${CONTEXT_STALE_DAYS:-7}"
EXCLUDE_LIST_FILE="${CONTEXT_FRESHNESS_EXCLUDE_LIST:-$SCRIPT_DIR/config/context_freshness_excludes.txt}"

if [[ ! -f "$EXCLUDE_LIST_FILE" ]]; then
    echo "ERROR: context freshness exclude list not found: $EXCLUDE_LIST_FILE" >&2
    echo "  action: config/context_freshness_excludes.txt を復旧し、安定contextの除外対象を明示せよ。" >&2
    exit 1
fi

EXCLUDE_ENTRIES=()
while IFS= read -r _exclude_line || [[ -n "$_exclude_line" ]]; do
    _exclude_line="${_exclude_line%%#*}"
    _exclude_line="${_exclude_line#"${_exclude_line%%[![:space:]]*}"}"
    _exclude_line="${_exclude_line%"${_exclude_line##*[![:space:]]}"}"
    [[ -n "$_exclude_line" ]] || continue
    EXCLUDE_ENTRIES+=("$_exclude_line")
done < "$EXCLUDE_LIST_FILE"
EXCLUDE_ENTRIES_CSV="$(IFS=,; printf '%s' "${EXCLUDE_ENTRIES[*]}")"

usage() {
    cat <<'EOF'
Usage:
  bash scripts/context_freshness_check.sh --dashboard-warnings
  bash scripts/context_freshness_check.sh --cmd-warnings <cmd_id>
  bash scripts/context_freshness_check.sh --cmd-commit-list <cmd_id>
EOF
}

case "$MODE" in
    --dashboard-warnings)
        ;;
    --cmd-warnings|--cmd-commit-list)
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
# --cmd-commit-list callers may reuse one cmd id while walking more than one
# project.  CFC_PROJECT_OVERRIDE changes the result set, so omitting it from the
# cache identity can replay project A's commit list for project B and let an
# unreflected source/context pair escape the completion-time BLOCK (GA-320).
_PROJECT_OVERRIDE="${CFC_PROJECT_OVERRIDE:-}"
_MODE_KEY="$(printf '%s|%s|%s|%s|%s|%s|%s' "$MODE" "$ARG" "$STALE_DAYS" "$_ARCHIVE_CACHE" "$EXCLUDE_ENTRIES_CSV" "$_PROJECT_OVERRIDE" "$(date +%Y-%m-%d)" | cksum | awk '{print $1}')"
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
python3 - "$SCRIPT_DIR" "$MODE" "$ARG" "$STALE_DAYS" "$_ARCHIVE_CACHE" "$EXCLUDE_ENTRIES_CSV" > "$_TMP_CACHE" <<'PY'
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, timedelta
import glob
import fcntl
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import time

root = sys.argv[1]
mode = sys.argv[2]
cmd_id = sys.argv[3]
threshold_days = int(sys.argv[4])
archive_cache_path = sys.argv[5] if len(sys.argv) > 5 else ""
exclude_entries = {
    item.strip()
    for item in (sys.argv[6] if len(sys.argv) > 6 else "").split(",")
    if item.strip()
}
cutoff_date = date.today() - timedelta(days=threshold_days)
FINAL_STATUSES = {"completed", "done", "complete", "success"}
# GA-487: retain the complete source commit candidate set for doc-lane
# consumers; the human-facing warning still shows a short preview.
MAX_SOURCE_COMMIT_DETAILS = int(
    os.environ.get("CFC_MAX_SOURCE_COMMIT_DETAILS", "1000")
)


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
    explicit_context_map: dict[str, list[str]] = {}
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
            explicit_context_map.setdefault(context_file, []).append(project_id)

        context_files = project.get("context_files", [])
        if isinstance(context_files, list):
            for rel in context_files:
                if rel:
                    explicit_context_map.setdefault(str(rel), []).append(project_id)

    return active_ids, explicit_context_map


ACTIVE_PROJECT_IDS, EXPLICIT_CONTEXT_MAP = load_projects()
SORTED_PROJECT_IDS = sorted(ACTIVE_PROJECT_IDS, key=len, reverse=True)
LAST_UPDATED_RE = re.compile(r"<!--\s*last_updated:\s*(\d{4}-\d{2}-\d{2})\b")
SOURCE_COMMIT_RE = re.compile(r"\bsource_commit:([0-9a-f]{7,40})\b")
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
        mapped_ids = EXPLICIT_CONTEXT_MAP[rel_path]
        base = os.path.basename(rel_path)
        for project_id in sorted(mapped_ids, key=len, reverse=True):
            if base.startswith(f"{project_id}.") or base.startswith(f"{project_id}-"):
                return project_id
        return mapped_ids[0] if mapped_ids else None

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


def last_updated_date(abs_path: str) -> date | None:
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
                    return date.fromisoformat(m.group(1))
                except ValueError:
                    return None
    except Exception:
        return None

    return None


def source_commit_markers(abs_path: str) -> list[str]:
    """Return every source-repository boundary recorded beside last_updated."""
    markers: list[str] = []
    try:
        with open(abs_path, encoding="utf-8") as f:
            for _ in range(5):
                line = f.readline()
                if not line:
                    break
                match = SOURCE_COMMIT_RE.search(line)
                if match:
                    markers.append(match.group(1))
    except Exception:
        return []
    return markers


def source_commit_frontier(
    project_id: str, rel_path: str, abs_path: str
) -> tuple[tuple[str, ...], str | None]:
    """Resolve markers and retain every non-ancestor frontier.

    Independently reviewed markers may be divergent. A single newest marker is
    valid only for a linear history; the frontier keeps both branch tips so
    callers can exclude commits reachable from either reviewed boundary.
    """
    markers = source_commit_markers(abs_path)
    if not markers:
        return (), "missing"
    repo_path, _pathspecs, _root_fallback = source_repo_for_context(project_id, rel_path)
    cache_key = (repo_path, tuple(markers))
    cached = _SOURCE_FRONTIER_CACHE.get(cache_key)
    if cached is not None:
        return cached

    resolved: list[str] = []
    for marker in markers:
        marker_key = (repo_path, marker)
        commit = _SOURCE_MARKER_CACHE.get(marker_key)
        if commit is None and marker_key not in _SOURCE_MARKER_CACHE:
            result = subprocess.run(
                ["git", "-C", repo_path, "rev-parse", "--verify", f"{marker}^{{commit}}"],
                capture_output=True,
                text=True,
            )
            commit = result.stdout.strip() if result.returncode == 0 else ""
            _SOURCE_MARKER_CACHE[marker_key] = commit
        if not commit:
            outcome = ((), "invalid")
            _SOURCE_FRONTIER_CACHE[cache_key] = outcome
            return outcome
        if commit not in resolved:
            resolved.append(commit)

    # `--independent` returns exactly the commits which are not ancestors of
    # any other supplied commit. It is equivalent to the old pairwise
    # `merge-base --is-ancestor` loop, while resolving the whole frontier in a
    # single git process (23 markers otherwise caused 253 subprocesses).
    result = _run_git_with_bounded_retry(
        ["git", "-C", repo_path, "merge-base", "--independent", *resolved],
        f"source_commit_frontier: {repo_path}",
    )
    if result is None:
        outcome = ((), "invalid")
        _SOURCE_FRONTIER_CACHE[cache_key] = outcome
        return outcome

    frontier = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if not frontier:
        outcome = ((), "invalid")
        _SOURCE_FRONTIER_CACHE[cache_key] = outcome
        return outcome
    outcome = (tuple(frontier), None)
    _SOURCE_FRONTIER_CACHE[cache_key] = outcome
    return outcome


def load_project_paths() -> dict[str, str]:
    paths: dict[str, str] = {}
    config_yaml = os.path.join(root, "config", "projects.yaml")
    try:
        current_id = ""
        current_status = "active"
        current_path = ""

        def flush_current() -> None:
            if current_id and current_path and current_status == "active":
                paths[current_id] = current_path

        with open(config_yaml, encoding="utf-8") as f:
            for raw_line in f:
                line = raw_line.split("#", 1)[0].rstrip()
                stripped = line.strip()
                if not stripped:
                    continue
                if line.startswith("  - "):
                    flush_current()
                    current_id = ""
                    current_status = "active"
                    current_path = ""
                    remainder = stripped[2:].strip()
                    if ":" in remainder:
                        key, value = remainder.split(":", 1)
                        if key.strip() == "id":
                            current_id = normalize_scalar(value)
                    continue
                if not line.startswith("    ") or line.startswith("      "):
                    continue
                if ":" not in stripped:
                    continue
                key, value = stripped.split(":", 1)
                key = key.strip()
                if key == "id":
                    current_id = normalize_scalar(value)
                elif key == "status":
                    current_status = normalize_scalar(value) or "active"
                elif key == "path":
                    current_path = normalize_scalar(value)
        flush_current()
    except Exception:
        paths = {}

    for project_id in ACTIVE_PROJECT_IDS:
        project_yaml = os.path.join(root, "projects", f"{project_id}.yaml")
        try:
            with open(project_yaml, encoding="utf-8") as f:
                for raw_line in f:
                    stripped = raw_line.strip()
                    if stripped.startswith("path:"):
                        candidate = normalize_scalar(stripped.split(":", 1)[1])
                        if candidate:
                            paths[project_id] = candidate
                        break
        except Exception:
            continue
    return paths


PROJECT_PATHS = load_project_paths()
AUTO_COMMIT_SUBJECT_RE = re.compile(
    r"^chore: (auto-commit|batch context|auto-generated index|lord-conversation-index|"
    r"運用コンテキスト更新|commit pending changes|session cleanup|"
    r"gunshi idle分析|家老自律hotfix|スキル統合|三層記憶貫通|運用データ蓄積|"
    r"sync .*records|sync .*quality log|complete .*records|"
    r"LS\d+→LS-|運用ファイル)\b"
)
ROOT_FALLBACK_IGNORED_PREFIXES = (
    "archive/",
    "context/",
    # Project research documents are indexed by their project-specific
    # context pathspecs (for example dm-signal-research.md).  Treating them
    # as infrastructure sources makes unrelated project design work stale
    # the infra root context as well.
    "docs/research/",
    "docs/semantic-index/",
    "logs/",
    "projects/",
    "queue/",
)
ROOT_FALLBACK_IGNORED_PATHS = {
    "tasks/lessons.md",
}
DM_SIGNAL_CONTEXT_PATHS: dict[str, list[str]] = {
    "context/dm-signal.md": [
        "context/dm-signal-terminology.md",
        "docs/knowledge-base/terminology/disambiguation.md",
        "docs/rule/db-operations-runbook.md",
    ],
    "context/dm-signal-core.md": [
        "backend/app",
        "backend/tests",
        "docs/rule",
        "context/dm-signal-terminology.md",
        "docs/knowledge-base/terminology/disambiguation.md",
    ],
    "context/dm-signal-frontend.md": [
        "frontend",
        "docs/research/frontend-components.md",
        "docs/research/frontend-api-spec.md",
        "docs/research/frontend-deploy.md",
        "docs/research/fe-speed-improvement-design.md",
    ],
    "context/dm-signal-research.md": [
        "docs/research",
        "analysis",
        "outputs",
        "tasks/lessons.md",
        "marketing-director",
    ],
    "context/dm-signal-ops.md": [
        "backend/app/api",
        "backend/app/jobs",
        "backend/app/services",
        "backend/tests",
        "docs/rule",
        "cited:docs/research",
        "render.yaml",
        "tasks/lessons.md",
    ],
}
# GA-237/karo RC(2026-07-13): "cited:<dir>"はdocs/researchのような広域共有ディレクトリを
# 二次的スコープとして持つcontext file専用のマーカー。dm-signal-research.mdのようにdocs/research
# 自体を主目的として網羅追跡するcontext fileには付けない(新規未引用ファイルを検知できなくなり
# 逆行するため)。付与したcontext fileでは、そのディレクトリ配下のcommitは自分の本文が既に
# `docs/research/xxx.md`の形で名指し引用しているファイルを変更した場合のみ関連commitとして
# 数える。min_source_commitsの既定閾値1(GA-226/L1056で意図的に固定)は一切変更しない —
# 発火条件ではなく「どのcommitを対象母集団に含めるか」というpathspecの意味的境界を絞る。
CITED_PATHSPEC_PREFIX = "cited:"
INFRA_CONTEXT_PATHS: dict[str, list[str]] = {
    "context/codd.md": [
        "scripts/codd",
        "scripts/codd_",
        "skills/codd",
        "skills/codd-refactor",
    ],
    "context/memory-db-queries.md": [
        "scripts/memory_db_",
        "scripts/lord_conversation_",
        "data",
    ],
    "context/memory-db-schema.md": [
        "scripts/memory_db_",
        "scripts/lord_conversation_",
        "data",
    ],
    "context/obsidian-link-principles.md": [
        "scripts/obsidian_",
        "scripts/causal_",
        "scripts/semantic_",
    ],
}
# GA-466: retain only the legacy key set for detecting stale duplicate declarations.
# Runtime pathspecs below come from the registry; a new registry trigger must
# not require this compatibility map to be edited as well.
# The compatibility key check remains intentionally path-only.
LEGACY_CONTEXT_PATHS = set(DM_SIGNAL_CONTEXT_PATHS) | set(INFRA_CONTEXT_PATHS)
SOURCE_CONTEXT_REGISTRY = os.path.join(root, "scripts", "config", "context_source_commits.tsv")


def load_registry_pathspecs() -> tuple[dict[str, list[str]], dict[str, list[str]]]:
    """Use the task dependency registry as the freshness pathspec SSOT.

    The old checker kept a second literal path map above this registry.  A new
    trigger could therefore be accepted by task injection but omitted from
    freshness scanning (or fail at the later map-mismatch guard).  Loading the
    same rows here makes the detector and the completion dependency injector
    observe one frontier.
    """
    try:
        with open(SOURCE_CONTEXT_REGISTRY, encoding="utf-8") as f:
            rows = [line.rstrip("\n").split("\t") for line in f
                    if line.strip() and not line.lstrip().startswith("#")]
    except FileNotFoundError:
        raise SystemExit("BLOCK: source context registry missing")

    dm_signal: dict[str, list[str]] = {}
    infra: dict[str, list[str]] = {}
    recognized_paths: set[str] = set()
    for row in rows:
        if len(row) != 4 or not all(field.strip() for field in row):
            raise SystemExit(
                "BLOCK: malformed source context registry row "
                "(expected path/project/owner/update_trigger)"
            )
        path, project, _owner, trigger_text = [field.strip() for field in row]
        pathspecs = [item.strip() for item in trigger_text.split("|") if item.strip()]
        if project == "dm-signal":
            recognized_paths.add(path)
            dm_signal[path] = pathspecs
        elif project == "infra":
            recognized_paths.add(path)
            if pathspecs == ["root-fallback"]:
                raise SystemExit(
                    "BLOCK: infra context registry requires explicit source pathspecs "
                    f"({path})"
                )
            infra[path] = pathspecs
    if recognized_paths != {row[0] for row in rows}:
        raise SystemExit("BLOCK: duplicate or unknown source context registry path")
    return dm_signal, infra


# Keep the registry as the single dependency frontier for both task injection
# and runtime freshness scanning.  The literal maps above remain only as a
# compatibility reference for older source snapshots; they are not consulted.
DM_SIGNAL_CONTEXT_PATHS, INFRA_CONTEXT_PATHS = load_registry_pathspecs()


def expected_source_contexts() -> dict[str, str]:
    return ({path: "dm-signal" for path in DM_SIGNAL_CONTEXT_PATHS}
            | {path: "infra" for path in INFRA_CONTEXT_PATHS}
            | {"context/infrastructure.md": "infra"})


SOURCE_CONTEXT_METADATA: dict[str, tuple[str, str, str]] = {}


def load_registered_source_contexts() -> frozenset[str]:
    """Load the source boundary plus its owner and update trigger.

    A path-only registry detects drift after the fact but cannot tell the
    completion flow who owns the context or which source paths require a
    review.  Keep those two routing facts beside the exact boundary and fail
    closed when either is absent.
    """
    global SOURCE_CONTEXT_METADATA
    try:
        with open(SOURCE_CONTEXT_REGISTRY, encoding="utf-8") as f:
            rows = [line.rstrip("\n").split("\t") for line in f
                    if line.strip() and not line.lstrip().startswith("#")]
    except FileNotFoundError:
        raise SystemExit("BLOCK: source context registry missing")
    if any(
        len(row) != 4
        or not row[0]
        or not row[1]
        or not row[2]
        or not row[3]
        for row in rows
    ):
        raise SystemExit(
            "BLOCK: malformed source context registry row "
            "(expected path/project/owner/update_trigger)"
        )
    actual = {row[0]: row[1] for row in rows}
    if len(actual) != len(rows):
        raise SystemExit("BLOCK: duplicate source context registry path")
    unknown = set(actual.values()) - {"infra", "dm-signal"}
    if unknown:
        raise SystemExit(f"BLOCK: unknown source context project: {sorted(unknown)}")
    SOURCE_CONTEXT_METADATA = {
        row[0]: (row[1], row[2], row[3]) for row in rows
    }
    stale_legacy_paths = LEGACY_CONTEXT_PATHS - set(actual)
    if stale_legacy_paths:
        raise SystemExit(
            "BLOCK: source context registry/map mismatch "
            f"missing={sorted(stale_legacy_paths)} extra=[]"
        )
    expected = expected_source_contexts()
    if actual != expected:
        missing = sorted(set(expected.items()) - set(actual.items()))
        extra = sorted(set(actual.items()) - set(expected.items()))
        raise SystemExit(f"BLOCK: source context registry/map mismatch missing={missing} extra={extra}")
    return frozenset(actual)


REGISTERED_SOURCE_CONTEXTS = load_registered_source_contexts()
REQUIRE_SOURCE_COMMIT = os.environ.get("CFC_REQUIRE_SOURCE_COMMIT", "1") != "0"


def is_registered_source_context(rel_path: str) -> bool:
    return rel_path in REGISTERED_SOURCE_CONTEXTS


def source_context_contract(rel_path: str) -> tuple[str, str]:
    """Return (owner, update_trigger) for a registered context path."""
    _project, owner, trigger = SOURCE_CONTEXT_METADATA.get(rel_path, ("", "", ""))
    return owner, trigger


def build_missing_source_commit_warning(rel_path: str) -> str:
    return (
        f"ALERT: {rel_path} MISSING_SOURCE_COMMIT — registered pathspec contextは"
        "exact revision境界が必須。日付--since fallbackは禁止"
    )


def build_invalid_source_commit_warning(rel_path: str) -> str:
    return (
        f"ALERT: {rel_path} INVALID_SOURCE_COMMIT — registered pathspec contextの"
        "source_commit markerが解決不能。正確なrevision境界へ修復せよ"
    )
# WSL2/9pマウント上でgit logが数秒〜十数秒かかるため並列実行と組み合わせてこの値で
# 打ち切る。GA-245実測: 集約後の呼び出しは6秒以下では不安定(5回中2回timeout)、
# 8秒で安定、安全マージンを見て10秒を既定とする(旧既定3秒は実測を大幅に下回り
# ほぼ全件timeoutしていた)。テスト用小さいrepoでは瞬時完了するため精度に影響しない。
# 環境変数 CFC_GIT_TIMEOUT で上書き可能（テスト/開発用）。
_GIT_TIMEOUT: float = float(os.environ.get("CFC_GIT_TIMEOUT", "10"))
_GIT_RETRY_TIMEOUT: float = float(os.environ.get("CFC_GIT_RETRY_TIMEOUT", "60"))
_GIT_ATTEMPTS: int = 2
_GIT_SUBPROCESS_COUNT: int = 0


def _run_git_with_bounded_retry(cmd: list[str], label: str) -> subprocess.CompletedProcess[str] | None:
    """Run git with bounded 10s/60s budgets; persistent failure stays fail-closed."""
    global _GIT_SUBPROCESS_COUNT
    for attempt in range(1, _GIT_ATTEMPTS + 1):
        timeout_seconds = _GIT_TIMEOUT if attempt == 1 else _GIT_RETRY_TIMEOUT
        try:
            _GIT_SUBPROCESS_COUNT += 1
            result = subprocess.run(
                cmd,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=timeout_seconds,
            )
        except Exception as exc:
            if attempt < _GIT_ATTEMPTS:
                print(
                    f"WARN: {label} git transient failure attempt={attempt}/{_GIT_ATTEMPTS} "
                    f"timeout={timeout_seconds}s: {exc}; retrying with timeout={_GIT_RETRY_TIMEOUT}s",
                    file=sys.stderr,
                )
                continue
            print(f"WARN: {label} git failed after {_GIT_ATTEMPTS} attempts: {exc}", file=sys.stderr)
            return None
        if result.returncode == 0:
            return result
        if attempt < _GIT_ATTEMPTS:
            print(
                f"WARN: {label} git transient returncode={result.returncode} "
                f"attempt={attempt}/{_GIT_ATTEMPTS}; retrying",
                file=sys.stderr,
            )
            continue
        print(
            f"WARN: {label} git returncode={result.returncode} after {_GIT_ATTEMPTS} attempts",
            file=sys.stderr,
        )
    return None


_SOURCE_TIP_CACHE: dict[str, str] = {}
_SOURCE_MARKER_CACHE: dict[tuple[str, str], str | None] = {}
_SOURCE_FRONTIER_CACHE: dict[
    tuple[str, tuple[str, ...]], tuple[tuple[str, ...], str | None]
] = {}


def source_tip_ref(repo_path: str) -> str:
    """Return the revision boundary appropriate for the current check mode.

    The always-on dashboard/gate must only inspect the shared completed
    boundary.  Looking at local HEAD there observes a ninja's commit before
    cmd_complete_gate has had the chance to require context reflux and emits a
    false-positive GA alert (GA-276).  Per-command modes deliberately keep
    HEAD so the completion gate still sees and blocks an unreflected own
    commit.
    """
    cached = _SOURCE_TIP_CACHE.get(repo_path)
    if cached:
        return cached

    candidates: list[str] = []
    override = os.environ.get("CFC_DASHBOARD_SOURCE_TIP", "").strip()
    if mode == "--dashboard-warnings":
        candidates = [override] if override else ["origin/main", "origin/master"]

    def ref_exists_without_git(candidate: str) -> bool:
        dotgit = os.path.join(repo_path, ".git")
        try:
            gitdir = dotgit
            if os.path.isfile(dotgit):
                marker = open(dotgit, encoding="utf-8").read().strip()
                if not marker.startswith("gitdir:"):
                    return False
                gitdir = os.path.realpath(os.path.join(repo_path, marker[7:].strip()))
            common = gitdir
            marker_path = os.path.join(gitdir, "commondir")
            if os.path.isfile(marker_path):
                common = os.path.realpath(os.path.join(gitdir, open(marker_path, encoding="utf-8").read().strip()))
            refs = [f"refs/remotes/{candidate}", f"refs/heads/{candidate}"]
            if any(os.path.isfile(os.path.join(common, ref)) for ref in refs):
                return True
            packed = os.path.join(common, "packed-refs")
            if os.path.isfile(packed):
                text = open(packed, encoding="ascii", errors="ignore").read()
                return any(f" {ref}\n" in text for ref in refs)
        except OSError:
            return False
        return False

    for candidate in [item for item in candidates if ref_exists_without_git(item)]:
        # The loose/packed ref existence check above is the freshness
        # boundary.  Re-verifying it with `git rev-parse` puts the consumer hot
        # path back on synchronous 9p history I/O and can turn a valid snapshot
        # hit into GA-291 timeout/returncode=1.  The producer validates the
        # revision while building the next snapshot; consumers stay syscall
        # only and fail closed when no ref can be resolved.
        _SOURCE_TIP_CACHE[repo_path] = candidate
        return candidate

    _SOURCE_TIP_CACHE[repo_path] = "HEAD"
    return "HEAD"


def source_repo_for_context(project_id: str, rel_path: str) -> tuple[str, list[str], bool]:
    project_path = PROJECT_PATHS.get(project_id, "")
    base = os.path.basename(rel_path)
    if project_id == "infra" and rel_path in INFRA_CONTEXT_PATHS:
        return root, INFRA_CONTEXT_PATHS[rel_path], False
    if project_id == "infra" and base != "infrastructure.md":
        return "", [], False
    if project_path and os.path.abspath(project_path) != os.path.abspath(root):
        if base.startswith(f"{project_id}.") or base.startswith(f"{project_id}-"):
            if project_id == "dm-signal" and rel_path in DM_SIGNAL_CONTEXT_PATHS:
                return project_path, DM_SIGNAL_CONTEXT_PATHS[rel_path], False
            return project_path, [], False

    return root, [], True


def is_root_fallback_source_path(path: str) -> bool:
    normalized = path.strip().lstrip("./")
    if not normalized:
        return False
    if normalized in ROOT_FALLBACK_IGNORED_PATHS:
        return False
    if any(normalized.startswith(prefix) for prefix in ROOT_FALLBACK_IGNORED_PREFIXES):
        return False
    return True


LESSON_ONLY_SOURCE_PATHS = {"tasks/lessons.md"}
CMD_ID_RE = re.compile(r"\bcmd_[A-Za-z0-9_]+\b")
REFLUX_FINGERPRINT_RE = re.compile(
    r"dm_signal_research_reflux:\s+fingerprint=([0-9a-f]{64});"
)
_REFLUX_FINGERPRINTS_CACHE: set[str] | None = None
_REFLUX_COMMIT_FINGERPRINT_CACHE: dict[tuple[str, str], str | None] = {}


def load_research_reflux_fingerprints() -> set[str]:
    """Load exact DM-Signal research reflection receipts from the context."""
    global _REFLUX_FINGERPRINTS_CACHE
    if _REFLUX_FINGERPRINTS_CACHE is not None:
        return _REFLUX_FINGERPRINTS_CACHE
    path = os.path.join(root, "context/dm-signal-research.md")
    try:
        text = open(path, encoding="utf-8", errors="ignore").read()
    except OSError:
        _REFLUX_FINGERPRINTS_CACHE = set()
        return _REFLUX_FINGERPRINTS_CACHE
    _REFLUX_FINGERPRINTS_CACHE = set(REFLUX_FINGERPRINT_RE.findall(text))
    return _REFLUX_FINGERPRINTS_CACHE


def source_commit_reflux_fingerprint(repo_path: str, commit_hash: str) -> str | None:
    """Recompute the reflux guard's canonical fingerprint for one commit."""
    cache_key = (repo_path, commit_hash)
    if cache_key in _REFLUX_COMMIT_FINGERPRINT_CACHE:
        return _REFLUX_COMMIT_FINGERPRINT_CACHE[cache_key]
    try:
        result = subprocess.run(
            [
                "git", "-C", repo_path, "diff-tree", "--root", "--no-commit-id",
                "--name-status", "-r", "-z", commit_hash, "--", "docs/research",
            ],
            capture_output=True,
            check=False,
        )
    except OSError:
        result = None
    if result is None or result.returncode != 0:
        _REFLUX_COMMIT_FINGERPRINT_CACHE[cache_key] = None
        return None

    raw = result.stdout.decode("utf-8", "surrogateescape").split("\0")
    entries: list[str] = []
    index = 0
    while index < len(raw) and raw[index]:
        status = raw[index]
        path = raw[index + 1]
        index += 2
        if status.startswith(("R", "C")):
            if index >= len(raw):
                _REFLUX_COMMIT_FINGERPRINT_CACHE[cache_key] = None
                return None
            path = raw[index]
            index += 1
        blob_result = subprocess.run(
            ["git", "-C", repo_path, "rev-parse", f"{commit_hash}:{path}"],
            capture_output=True,
            text=True,
            check=False,
        )
        blob = blob_result.stdout.strip() if blob_result.returncode == 0 else "DELETED"
        entries.append(f"{status}\t{path}\t{blob}")
    if not entries:
        _REFLUX_COMMIT_FINGERPRINT_CACHE[cache_key] = None
        return None
    canonical = "\n".join(sorted(entries, key=lambda row: row.split("\t", 1)[1])) + "\n"
    fingerprint = hashlib.sha256(canonical.encode("utf-8", "surrogateescape")).hexdigest()
    _REFLUX_COMMIT_FINGERPRINT_CACHE[cache_key] = fingerprint
    return fingerprint


def is_research_reflux_reflected(
    rel_path: str, repo_path: str | None, commit_hash: str
) -> bool:
    """Consume an exact reflux receipt for the research context only."""
    if rel_path != "context/dm-signal-research.md" or not repo_path:
        return False
    fingerprint = source_commit_reflux_fingerprint(repo_path, commit_hash)
    return bool(fingerprint and fingerprint in load_research_reflux_fingerprints())


def commit_is_reflected_or_lesson_only(
    rel_path: str,
    commit_hash: str,
    subject: str,
    changed_paths: list[str],
    repo_path: str | None = None,
) -> bool:
    """Exclude only commits carrying machine-checkable reflection evidence.

    A context-writing commit is reflected by definition.  A lesson-only commit
    is consumed by lesson_write's indexed context route and must not make the
    implementation freshness lane noisy.  Every other commit stays stale unless
    the context body names its hash or cmd id; dates and subjects alone are not
    accepted as proof.
    """
    normalized = {path.strip().lstrip("./") for path in changed_paths if path.strip()}
    if rel_path in normalized:
        return True
    if is_research_reflux_reflected(rel_path, repo_path, commit_hash):
        return True
    relevant = {path for path in normalized if is_root_fallback_source_path(path)}
    if relevant and relevant <= LESSON_ONLY_SOURCE_PATHS:
        return True
    try:
        text = open(os.path.join(root, rel_path), encoding="utf-8", errors="ignore").read()
    except OSError:
        return False
    tokens = {commit_hash, *CMD_ID_RE.findall(subject)}
    return any(token and token in text for token in tokens)


def _root_fallback_commit_count_since(
    updated_at: date, source_commits: tuple[str, ...] | None = None
) -> tuple[int, list[str]]:
    tip_ref = source_tip_ref(root)
    revision: str | tuple[str, ...] = tip_ref
    if source_commits:
        revision = (tip_ref, *(f"^{commit}" for commit in source_commits))
    commits = _run_grouped_git_log(
        root, revision, None if source_commits else updated_at, []
    )
    if commits is None:
        return -1, []

    count = 0
    details: list[str] = []
    for current_hash, subject, changed_paths in commits:
        source_paths = [
            path.strip()
            for path in changed_paths
            if is_root_fallback_source_path(path)
        ]
        if source_paths and not commit_is_reflected_or_lesson_only(
            "context/infrastructure.md", current_hash, subject, changed_paths, root
        ):
            count += 1
            if len(details) < MAX_SOURCE_COMMIT_DETAILS:
                details.append(f"{current_hash} {subject}".strip())
    return count, details


def load_cited_paths(abs_path: str, dirs: list[str]) -> set[str]:
    """context fileの本文が`<dir>/xxx.md`の形で直接名指し引用しているファイルの集合を返す。
    "cited:"pathspec entryの関連性フィルタで使う。dirsが空なら空集合。"""
    cited: set[str] = set()
    if not dirs:
        return cited
    try:
        with open(abs_path, encoding="utf-8", errors="ignore") as f:
            text = f.read()
    except Exception:
        return cited
    for d in dirs:
        d_norm = d.rstrip("/")
        pattern = re.compile(re.escape(d_norm) + r"/[A-Za-z0-9_./-]+\.[A-Za-z0-9]+")
        for match in pattern.finditer(text):
            cited.add(match.group(0))
    return cited


def _commit_touches_relevant_path(
    changed_paths: list[str],
    plain_prefixes: list[str],
    cited_dirs: list[str],
    cited_files: set[str],
) -> bool:
    """変更ファイルのいずれかが、非cited pathspecに一致するか、cited pathspec配下かつ
    context fileが既に名指し引用しているファイルであれば関連commitとみなす。"""
    for raw in changed_paths:
        path = raw.strip()
        if not path:
            continue
        if any(
            path == prefix or path.startswith(prefix.rstrip("/") + "/")
            for prefix in plain_prefixes
        ):
            return True
        for cited_dir in cited_dirs:
            cited_dir_norm = cited_dir.rstrip("/")
            if (
                path == cited_dir_norm or path.startswith(cited_dir_norm + "/")
            ) and path in cited_files:
                return True
    return False


def source_commit_summary_since(
    project_id: str,
    rel_path: str,
    abs_path: str,
    updated_at: date,
    source_commits: tuple[str, ...] | None = None,
    max_details: int = MAX_SOURCE_COMMIT_DETAILS,
) -> tuple[int, list[str]]:
    repo_path, pathspecs, root_fallback = source_repo_for_context(project_id, rel_path)
    if not repo_path or not os.path.isdir(repo_path):
        return 0, []
    if root_fallback:
        return _root_fallback_commit_count_since(updated_at, source_commits)

    cited_dirs = [
        p[len(CITED_PATHSPEC_PREFIX):] for p in pathspecs if p.startswith(CITED_PATHSPEC_PREFIX)
    ]
    plain_pathspecs = [p for p in pathspecs if not p.startswith(CITED_PATHSPEC_PREFIX)]
    git_pathspecs = [*plain_pathspecs, *cited_dirs]
    cited_files = load_cited_paths(abs_path, cited_dirs) if cited_dirs else set()

    tip_ref = source_tip_ref(repo_path)
    revision_args = [tip_ref]
    if source_commits:
        revision_args.extend(f"^{commit}" for commit in source_commits)
    cmd = [
        "git",
        "-C",
        repo_path,
        "log",
        "--pretty=format:__CFC_C__%x00%h%x00%s",
        "--name-only",
    ]
    cmd.extend(revision_args)
    if not source_commits:
        cmd.append(f"--since={(updated_at + timedelta(days=1)).isoformat()} 00:00:00")
    if git_pathspecs:
        cmd.extend(["--", *git_pathspecs])

    result = _run_git_with_bounded_retry(cmd, f"source_commit_count_since: {repo_path}")
    if result is None:
        return -1, []

    count = 0
    details: list[str] = []
    current_hash = ""
    current_subject = ""
    changed_paths: list[str] = []

    def flush_commit() -> None:
        nonlocal count, current_hash, current_subject, changed_paths
        subject = current_subject.strip()
        if not subject or AUTO_COMMIT_SUBJECT_RE.match(subject):
            return
        if cited_dirs and not _commit_touches_relevant_path(
            changed_paths, plain_pathspecs, cited_dirs, cited_files
        ):
            return
        # Keep the external split-context path on the same reflection
        # contract as the infra root-fallback path.  Without this check,
        # a source commit whose cmd id/hash is already present in the context
        # body is counted as stale again, even though its reflection evidence
        # is already recorded (GA-449).
        if commit_is_reflected_or_lesson_only(
            rel_path, current_hash, subject, changed_paths, repo_path
        ):
            return
        count += 1
        if len(details) < max_details:
            details.append(f"{current_hash} {subject}".strip())

    for line in result.stdout.splitlines():
        if line.startswith("__CFC_C__\x00"):
            flush_commit()
            _marker, current_hash, current_subject = line.split("\x00", 2)
            changed_paths = []
            continue
        if line.strip():
            changed_paths.append(line.strip())
    flush_commit()
    return count, details


def _run_grouped_git_log(
    repo_path: str,
    revision: str | tuple[str, ...] | None,
    since_date: date | None,
    pathspecs: list[str],
) -> list[tuple[str, str, list[str]]] | None:
    """1回のgit logで(short_hash, subject, changed_paths)のコミット列を返す。
    timeout/エラー時はNone(呼び出し元でfail-closed判定させる)。"""
    cmd = [
        "git",
        "-C",
        repo_path,
        "log",
        "--pretty=format:__CFC_G__%x00%h%x00%s",
        "--name-only",
    ]
    revision_parts = (
        list(revision)
        if isinstance(revision, (tuple, list))
        else ([revision] if revision else [])
    )
    cmd.extend(revision_parts)
    if since_date is not None:
        cmd.append(f"--since={(since_date + timedelta(days=1)).isoformat()} 00:00:00")
    if pathspecs:
        cmd.extend(["--", *pathspecs])

    # Divergent source markers need multiple revision exclusions. The shared
    # snapshot refresh helper accepts one revision argument, so execute this
    # exact multi-boundary query directly and keep the cache path unchanged
    # for the common single-boundary case.
    if len(revision_parts) > 1:
        result = _run_git_with_bounded_retry(cmd, f"source_commit_count_since: {repo_path}")
        if result is None:
            return None
        commits: list[tuple[str, str, list[str]]] = []
        current_hash = ""
        current_subject = ""
        changed_paths: list[str] = []

        def flush_commit() -> None:
            if current_subject.strip():
                commits.append((current_hash, current_subject.strip(), list(changed_paths)))

        for line in result.stdout.splitlines():
            if line.startswith("__CFC_G__\x00"):
                flush_commit()
                _marker, current_hash, current_subject = line.split("\x00", 2)
                changed_paths = []
            elif line.strip():
                changed_paths.append(line.strip())
        flush_commit()
        return commits

    # GA-286: dashboard rendering invokes this checker repeatedly, while a 9p
    # git log may consume the full 10s + 60s retry budget.  Persist only
    # successful history snapshots on ext4 (/tmp by default).  The key binds
    # the repository, resolved revision boundary, date range and pathspecs, so
    # a new commit cannot reuse stale history.  Corrupt/missing snapshots are
    # cache misses; git failures remain fail-closed and are never cached.
    cache_dir = os.environ.get("CFC_HISTORY_CACHE_DIR", "/tmp/cfc-history-v1")

    def resolve_tip_without_git(repo: str, rev: str | None) -> str:
        """Resolve the positive end of a revision from Git's files.

        This is deliberately a read-only fallback for 9p stalls.  It supports
        normal repositories, linked worktrees, loose refs and packed refs.
        Failure returns an empty string, preserving fail-closed behaviour.
        """
        tip = (rev or "HEAD").rsplit("..", 1)[-1]
        dotgit = os.path.join(repo, ".git")
        try:
            if os.path.isfile(dotgit):
                marker = open(dotgit, encoding="utf-8").read().strip()
                if not marker.startswith("gitdir:"):
                    return ""
                gitdir = os.path.realpath(os.path.join(repo, marker[7:].strip()))
            else:
                gitdir = os.path.realpath(dotgit)
            common = gitdir
            common_marker = os.path.join(gitdir, "commondir")
            if os.path.isfile(common_marker):
                common = os.path.realpath(
                    os.path.join(gitdir, open(common_marker, encoding="utf-8").read().strip())
                )
            ref = tip
            if tip == "HEAD":
                head = open(os.path.join(gitdir, "HEAD"), encoding="utf-8").read().strip()
                if re.fullmatch(r"[0-9a-f]{40}", head):
                    return head
                if not head.startswith("ref: "):
                    return ""
                ref = head[5:]
            elif not tip.startswith("refs/"):
                candidates = [f"refs/heads/{tip}", f"refs/remotes/{tip}", f"refs/tags/{tip}"]
                ref = next((item for item in candidates if os.path.isfile(os.path.join(common, item))), "")
            loose = os.path.join(common, ref)
            if ref and os.path.isfile(loose):
                oid = open(loose, encoding="ascii").read().strip()
                return oid if re.fullmatch(r"[0-9a-f]{40}", oid) else ""
            packed = os.path.join(common, "packed-refs")
            if os.path.isfile(packed):
                packed_candidates = [ref] if ref else candidates
                with open(packed, encoding="ascii", errors="ignore") as stream:
                    for line in stream:
                        fields = line.rstrip().split(" ", 1)
                        if (len(fields) == 2 and fields[1] in packed_candidates
                                and re.fullmatch(r"[0-9a-f]{40}", fields[0])):
                            return fields[0]
        except OSError:
            return ""
        return ""

    started = time.monotonic()
    subprocess_before = _GIT_SUBPROCESS_COUNT

    def record_diagnostic(cache_result: str) -> None:
        diagnostic_path = os.environ.get("CFC_GIT_DIAGNOSTICS_FILE", "")
        if not diagnostic_path:
            return
        record = {
            "repo": os.path.realpath(repo_path),
            "revision": revision,
            "pathspecs": sorted(pathspecs),
            "source_tip": boundary,
            "workers": max(1, int(os.environ.get("CFC_GIT_MAX_WORKERS", "4"))),
            "git_subprocesses": _GIT_SUBPROCESS_COUNT - subprocess_before,
            "wall_ms": round((time.monotonic() - started) * 1000, 3),
            "cache": cache_result,
        }
        try:
            with open(diagnostic_path, "a", encoding="utf-8") as stream:
                stream.write(json.dumps(record, sort_keys=True) + "\n")
        except OSError:
            pass
    # The loose/packed ref is the complete consumer source-tip contract.
    # Never fall back to synchronous git here: missing/unsupported boundaries
    # are unknown freshness and must request no snapshot / return fail-closed.
    boundary = resolve_tip_without_git(repo_path, revision)
    contract = json.dumps(
        {
            "repo": os.path.realpath(repo_path),
            "revision": revision,
            "since": since_date.isoformat() if since_date else None,
            "pathspecs": sorted(pathspecs),
        },
        sort_keys=True,
        separators=(",", ":"),
    )
    contract_hash = hashlib.sha256(contract.encode()).hexdigest()
    fingerprint = json.dumps({"contract": contract_hash, "source_tip": boundary}, sort_keys=True)
    cache_path = os.path.join(cache_dir, hashlib.sha256(fingerprint.encode()).hexdigest() + ".json")
    refresh_script = os.path.join(root, "scripts", "context_history_snapshot_refresh.sh")

    def parse_snapshot(path: str) -> list[tuple[str, str, list[str]]] | None:
        try:
            with open(path, encoding="utf-8") as stream:
                snapshot = json.load(stream)
            commits_value = snapshot.get("commits")
            if (snapshot.get("schema") != "cfc-history-v2"
                    or snapshot.get("contract_hash") != contract_hash
                    or snapshot.get("source_tip") != boundary
                    or not isinstance(commits_value, list)):
                return None
            canonical = json.dumps(commits_value, sort_keys=True, separators=(",", ":"))
            if snapshot.get("output_sha256") != hashlib.sha256(canonical.encode()).hexdigest():
                return None
            parsed = [
                (str(item[0]), str(item[1]), [str(path) for path in item[2]])
                for item in commits_value
                if isinstance(item, list) and len(item) == 3 and isinstance(item[2], list)
            ]
            return parsed if len(parsed) == len(commits_value) else None
        except (OSError, ValueError, TypeError, KeyError):
            return None

    def request_refresh() -> None:
        if not boundary or not os.path.isfile(refresh_script):
            return
        env = os.environ.copy()
        env.update({
            "CFC_REFRESH_REPO": os.path.realpath(repo_path),
            "CFC_REFRESH_REVISION": revision or "",
            "CFC_REFRESH_SINCE": since_date.isoformat() if since_date else "",
            "CFC_REFRESH_PATHS": json.dumps(pathspecs),
            "CFC_REFRESH_CONTRACT_HASH": contract_hash,
            "CFC_REFRESH_SOURCE_TIP": boundary,
            "CFC_REFRESH_OUTPUT": cache_path,
            "CFC_REFRESH_CACHE_DIR": cache_dir,
        })
        try:
            if os.environ.get("CFC_HISTORY_REFRESH_SYNC") == "1":
                subprocess.run(["bash", refresh_script], env=env, check=False,
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=_GIT_RETRY_TIMEOUT + 5)
            else:
                subprocess.Popen(
                    ["bash", refresh_script], env=env,
                    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    start_new_session=True, close_fds=True,
                )
        except OSError:
            pass
    if boundary:
        try:
            cached_commits = parse_snapshot(cache_path)
            if cached_commits is not None:
                record_diagnostic("hit")
                return cached_commits
        except (OSError, ValueError, TypeError, KeyError):
            pass
        # Legacy snapshots lack the v2 content hash and generation tuple.
        # Treat every one as a miss; adopting one can silently mix a stale or
        # partially-written generation into a current source-tip decision.
    request_refresh()
    if os.environ.get("CFC_HISTORY_REFRESH_SYNC") == "1":
        refreshed = parse_snapshot(cache_path)
        if refreshed is not None:
            record_diagnostic("rebuilt")
            return refreshed
    record_diagnostic("refresh_requested")
    return None


def _compute_direct_group(
    key: tuple[str, tuple[str, ...] | None, date | None],
    members: list[tuple[str, str, list[str], list[str], set[str]]],
) -> dict[tuple[str, str], tuple[int, list[str]]]:
    """(repo_path, source_commit/updated_at)を共有するcontext file群を
    git log 1回に集約し(GA-245: 9pマウント環境ではgit呼び出し回数がレイテンシに
    直結するため個別呼び出しをまとめる)、結果を各context fileのpathspec条件で
    Python側にて個別に絞り込む。member = (project_id, rel_path, plain_pathspecs,
    cited_dirs, cited_files)。plain/cited双方が空のmember(pathspec指定のない
    project直下context)は元のsource_commit_summary_sinceと同じくフィルタ無しで
    全コミットを対象にする。"""
    repo_path, source_commits, since_date = key
    tip_ref = source_tip_ref(repo_path)
    revision: str | tuple[str, ...] = (
        (tip_ref, *(f"^{commit}" for commit in source_commits))
        if source_commits
        else tip_ref
    )
    has_unfiltered_member = any(
        not plain_pathspecs and not cited_dirs
        for _pid, _rp, plain_pathspecs, cited_dirs, _cf in members
    )
    if has_unfiltered_member:
        union_pathspecs: list[str] = []
    else:
        union_pathspecs = sorted(
            {p for _pid, _rp, plain, cited, _cf in members for p in (*plain, *cited)}
            | {rel_path for project_id, rel_path, *_ in members if project_id == "infra"}
        )

    commits = _run_grouped_git_log(repo_path, revision, since_date, union_pathspecs)
    if commits is None:
        return {(project_id, rel_path): (-1, []) for project_id, rel_path, *_ in members}

    results: dict[tuple[str, str], tuple[int, list[str]]] = {}
    for project_id, rel_path, plain_pathspecs, cited_dirs, cited_files in members:
        no_filter = not plain_pathspecs and not cited_dirs
        count = 0
        details: list[str] = []
        for commit_hash, subject, changed_paths in commits:
            # An infra source commit that also updates its context index is
            # already reflected.  Including each infra context path in the
            # grouped log above lets this remain one git call while avoiding
            # the perpetual post-commit alert that GA-288 exposed.
            if project_id == "infra" and rel_path in changed_paths:
                continue
            if not no_filter and not _commit_touches_relevant_path(
                changed_paths, plain_pathspecs, cited_dirs, cited_files
            ):
                continue
            if commit_is_reflected_or_lesson_only(
                rel_path, commit_hash, subject, changed_paths, repo_path
            ):
                continue
            count += 1
            if len(details) < MAX_SOURCE_COMMIT_DETAILS:
                details.append(f"{commit_hash} {subject}".strip())
        results[(project_id, rel_path)] = (count, details)
    return results


def batch_source_commit_summaries(
    infos: list[tuple[str, str, str, date, tuple[str, ...] | None]],
) -> dict[tuple[str, str], tuple[int, list[str]]]:
    """(project_id, rel_path) → commit_count を並列計算（ThreadPoolExecutor）。
    GA-245: 同一リポジトリ×同一revision範囲(source_commit有無/updated_at)を
    共有するcontext fileはgit log 1回に集約する。集約しない場合、9pマウント上
    ではcontext file数だけ個別git呼び出しが発生し、各呼び出しが数秒〜十数秒
    かかるため1秒既定timeoutでほぼ全滅する(cmd_karo_hotfix_ga245実測)。"""
    if not infos:
        return {}
    summaries: dict[tuple[str, str], tuple[int, list[str]]] = {}

    root_fallback_groups: dict[tuple[date, tuple[str, ...] | None], list[tuple[str, str]]] = {}
    direct_groups: dict[
        tuple[str, tuple[str, ...] | None, date | None],
        list[tuple[str, str, list[str], list[str], set[str]]],
    ] = {}

    for project_id, rel_path, abs_path, updated_at, source_commits in infos:
        repo_path, pathspecs, root_fallback = source_repo_for_context(project_id, rel_path)
        if root_fallback:
            root_fallback_groups.setdefault((updated_at, source_commits), []).append(
                (project_id, rel_path)
            )
            continue
        if not repo_path or not os.path.isdir(repo_path):
            summaries[(project_id, rel_path)] = (0, [])
            continue
        cited_dirs = [
            p[len(CITED_PATHSPEC_PREFIX):] for p in pathspecs if p.startswith(CITED_PATHSPEC_PREFIX)
        ]
        plain_pathspecs = [p for p in pathspecs if not p.startswith(CITED_PATHSPEC_PREFIX)]
        cited_files = load_cited_paths(abs_path, cited_dirs) if cited_dirs else set()
        key = (repo_path, source_commits, None if source_commits else updated_at)
        direct_groups.setdefault(key, []).append(
            (project_id, rel_path, plain_pathspecs, cited_dirs, cited_files)
        )

    # GA-283: /mnt/c (9p) saturates when all context git logs start at once;
    # 16-way fan-out made three otherwise valid source checks hit the timeout.
    # Keep concurrency bounded and configurable for small/ext4 test fixtures.
    max_workers = max(1, int(os.environ.get("CFC_GIT_MAX_WORKERS", "4")))
    with ThreadPoolExecutor(max_workers=min(max_workers, 16)) as executor:
        root_futures = {
            executor.submit(_root_fallback_commit_count_since, updated_at, source_commits): keys
            for (updated_at, source_commits), keys in root_fallback_groups.items()
        }
        direct_futures = {
            executor.submit(_compute_direct_group, key, members): key
            for key, members in direct_groups.items()
        }

        for future in as_completed([*root_futures, *direct_futures]):
            if future in root_futures:
                count, details = future.result()
                for key in root_futures[future]:
                    summaries[key] = (count, details)
            else:
                summaries.update(future.result())
    return summaries


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

                    # Active ninja tasks are the freshest project SSOT while a
                    # command is still running.  Before archival/chronicle
                    # publication, resolve task_id/parent_cmd/issued_cmd_id
                    # from the current task file so --cmd-warnings cannot
                    # silently return no project and skip freshness evidence.
                    if indent == 2 and any(
                        stripped.startswith(f"{key}:")
                        for key in ("task_id", "parent_cmd", "issued_cmd_id")
                    ):
                        top_level_match = top_level_match or normalize_scalar(stripped.split(":", 1)[1]) == target_cmd_id
                        continue

                    if top_level_match and indent == 2 and stripped.startswith("project:"):
                        return normalize_scalar(stripped.split(":", 1)[1]) or None

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

    # The active task file is authoritative before the command is archived or
    # added to cmd-chronicle.  Keep this fallback after immutable history so a
    # stale task slot cannot override a published command record.
    for path in sorted(glob.glob(os.path.join(root, "queue", "tasks", "*.yaml"))):
        project_id = find_project_in_command_file(path)
        if project_id:
            return project_id
    return None


def build_warning(rel_path: str, days_old: int | None) -> str:
    if days_old is None:
        return f"WARN: {rel_path} last_updated 未記載。更新要否を確認せよ"
    return f"WARN: {rel_path} last_updated {days_old}日前。更新要否を確認せよ"


def build_source_warning(
    project_id: str,
    rel_path: str,
    commit_count: int,
    updated_at: date,
    details: list[str] | None = None,
) -> str:
    repo_path, _pathspecs, root_fallback = source_repo_for_context(project_id, rel_path)
    owner, trigger = source_context_contract(rel_path)
    message = (
        f"ALERT: {rel_path} source commits {commit_count}件 "
        f"since last_updated={updated_at.isoformat()} "
        f"repo={repo_path} root_fallback={'yes' if root_fallback else 'no'} "
        f"timeout={_GIT_TIMEOUT:g}s/{_GIT_RETRY_TIMEOUT:g}s "
        f"owner={owner} update_trigger={trigger}。更新要否を確認せよ"
    )
    if details:
        preview = details[:3]
        message += f" latest: {' | '.join(preview)}"
        # The preview keeps dashboard lines readable; the complete set is the
        # durable Level5 input consumed by doc-lane tooling and reports.
        message += (
            f" source_commit_set_count={len(details)}"
            f" source_commit_set: {' | '.join(details)}"
        )
        latest_hash, _, _latest_subject = details[0].partition(" ")
        reason = "context_freshness reviewed source boundary"
        evidence = f"context_freshness_check context={rel_path} commit={latest_hash}"
        command = " ".join(
            shlex.quote(part)
            for part in (
                "bash",
                "scripts/context_source_commit_set.sh",
                rel_path,
                latest_hash,
                reason,
                evidence,
            )
        )
        message += f" action: {command}"
    return message


def build_source_check_warning(project_id: str, rel_path: str, updated_at: date) -> str:
    repo_path, _pathspecs, root_fallback = source_repo_for_context(project_id, rel_path)
    return (
        f"WARN: {rel_path} source commit check failed "
        f"since last_updated={updated_at.isoformat()} repo={repo_path} "
        f"root_fallback={'yes' if root_fallback else 'no'} "
        f"timeout={_GIT_TIMEOUT:g}s/{_GIT_RETRY_TIMEOUT:g}s。timeout/returncodeを確認せよ"
    )


def is_excluded_context_file(rel_path: str) -> bool:
    normalized = rel_path.strip().lstrip("./")
    return normalized in exclude_entries or os.path.basename(normalized) in exclude_entries


def build_group_warnings(alerted: list[tuple[str, list[str]]]) -> list[str]:
    """GA-237/L1089: 複数context fileが同一source commitで同時ALERTした場合、
    家老が1cmdで一括反映できるよう共有commitを明示する。ALERT自体の発火条件
    (件数閾値1、GA-226で固定)は一切変更しない — 可視性を追加するだけの
    非破壊的な共通防御層。"""
    hash_to_paths: dict[str, list[str]] = {}
    hash_to_subject: dict[str, str] = {}
    for rel_path, details in alerted:
        for detail in details:
            short_hash, _, subject = detail.partition(" ")
            short_hash = short_hash.strip()
            if not short_hash:
                continue
            paths = hash_to_paths.setdefault(short_hash, [])
            if rel_path not in paths:
                paths.append(rel_path)
            hash_to_subject.setdefault(short_hash, subject.strip())

    lines: list[str] = []
    for short_hash, paths in hash_to_paths.items():
        if len(paths) < 2:
            continue
        subject = hash_to_subject.get(short_hash, "")
        joined = ",".join(sorted(paths))
        message = f"GROUP: {joined} share source commit {short_hash}"
        if subject:
            message += f" {subject}"
        message += " — 家老は1cmdで一括反映を検討せよ(重複調査防止, L1089)"
        lines.append(message)
    return lines


warnings: list[str] = []

if mode == "--dashboard-warnings":
    recent_project_cache: dict[str, bool] = {}
    files_for_git: list[tuple[str, str, str, date]] = []
    for project_id, rel_path, abs_path in iter_context_files():
        if is_excluded_context_file(rel_path):
            continue
        if project_id not in recent_project_cache:
            recent_project_cache[project_id] = project_has_recent_completed_cmd(project_id)
        if not recent_project_cache[project_id]:
            continue

        updated_at = last_updated_date(abs_path)
        if updated_at is None:
            warnings.append(build_warning(rel_path, None))
            continue
        source_commits, marker_error = source_commit_frontier(project_id, rel_path, abs_path)
        if REQUIRE_SOURCE_COMMIT and is_registered_source_context(rel_path) and marker_error:
            warnings.append(
                build_invalid_source_commit_warning(rel_path)
                if marker_error == "invalid"
                else build_missing_source_commit_warning(rel_path)
            )
            continue
        files_for_git.append((project_id, rel_path, abs_path, updated_at, source_commits or None))
    commit_summaries = batch_source_commit_summaries(files_for_git)
    min_source_commits = int(os.environ.get("CONTEXT_FRESHNESS_MIN_SOURCE_COMMITS", "1"))
    alerted_for_group: list[tuple[str, list[str]]] = []
    for project_id, rel_path, abs_path, updated_at, _source_commit in files_for_git:
        cc, details = commit_summaries.get((project_id, rel_path), (0, []))
        if cc < 0:
            warnings.append(build_source_check_warning(project_id, rel_path, updated_at))
        elif cc >= min_source_commits:
            warnings.append(build_source_warning(project_id, rel_path, cc, updated_at, details))
            alerted_for_group.append((rel_path, details))
    warnings.extend(build_group_warnings(alerted_for_group))
elif mode == "--cmd-warnings":
    project_id = find_cmd_project(cmd_id)
    if project_id:
        files_for_git = []
        for current_project, rel_path, abs_path in iter_context_files():
            if current_project != project_id:
                continue
            if is_excluded_context_file(rel_path):
                continue
            updated_at = last_updated_date(abs_path)
            if updated_at is None:
                warnings.append(build_warning(rel_path, None))
                continue
            source_commits, marker_error = source_commit_frontier(
                current_project, rel_path, abs_path
            )
            if REQUIRE_SOURCE_COMMIT and is_registered_source_context(rel_path) and marker_error:
                warnings.append(
                    build_invalid_source_commit_warning(rel_path)
                    if marker_error == "invalid"
                    else build_missing_source_commit_warning(rel_path)
                )
                continue
            files_for_git.append(
                (current_project, rel_path, abs_path, updated_at, source_commits or None)
            )
        commit_summaries = batch_source_commit_summaries(files_for_git)
        alerted_for_group = []
        for current_project, rel_path, abs_path, updated_at, _source_commit in files_for_git:
            cc, details = commit_summaries.get((current_project, rel_path), (0, []))
            if cc < 0:
                warnings.append(build_source_check_warning(current_project, rel_path, updated_at))
            elif cc > 0:
                warnings.append(build_source_warning(current_project, rel_path, cc, updated_at, details))
                alerted_for_group.append((rel_path, details))
        warnings.extend(build_group_warnings(alerted_for_group))
elif mode == "--cmd-commit-list":
    # GA-238 AC3: cmd_complete_gate.shが「このcmd自身のcommitが、未反映のsplit
    # context候補に含まれるか」を判定するための機械可読出力。--cmd-warningsと違い
    # detailsを3件に丸めず全件出す(相関対象を見逃さないため)。
    # project解決はfind_cmd_project(chronicle/archive依存、未archiveのcmdでは
    # 失敗しうる)ではなく、呼び出し元(cmd_complete_gate.sh)がMATCHING_TASK_FILESの
    # project:から直接渡すCFC_PROJECT_OVERRIDEを優先する。
    project_override = os.environ.get("CFC_PROJECT_OVERRIDE", "").strip()
    project_id = project_override or find_cmd_project(cmd_id)
    if project_id:
        for current_project, rel_path, abs_path in iter_context_files():
            if current_project != project_id:
                continue
            if is_excluded_context_file(rel_path):
                continue
            updated_at = last_updated_date(abs_path)
            if updated_at is None:
                continue
            source_commits, marker_error = source_commit_frontier(
                current_project, rel_path, abs_path
            )
            if REQUIRE_SOURCE_COMMIT and is_registered_source_context(rel_path) and marker_error:
                if marker_error == "invalid":
                    print(f"INVALID_SOURCE_COMMIT\t{rel_path}")
                # cmd_complete_gate already fail-closes on this machine-readable
                # marker; retain the common prefix for invalid boundaries too.
                print(f"MISSING_SOURCE_COMMIT\t{rel_path}")
                continue
            cc, details = source_commit_summary_since(
                current_project,
                rel_path,
                abs_path,
                updated_at,
                source_commits or None,
                max_details=1000,
            )
            if cc < 0:
                print(f"CHECK_FAILED\t{rel_path}")
                continue
            for detail in details:
                commit_hash, _, subject = detail.partition(" ")
                print(f"{rel_path}\t{commit_hash}\t{subject}")

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
