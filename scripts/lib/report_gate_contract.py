"""Shared report contracts used by completion and review gates.

The completion gate remains the behavioral authority.  These pure helpers make
the same acceptance-criteria and lesson-set rules callable by the review
precheck without sourcing the completion gate (which would execute its
side-effecting main flow).
"""

from __future__ import annotations

import hashlib
import json
import pathlib
from typing import Any

import yaml

# cmd_karo_hotfix_contract_schema_20260907: the deploy-time snapshot embedded
# in ``task_contract_snapshot`` predates any explicit version tag.  A missing
# ``contract_version`` key is legacy (version 0) and must keep reading as
# compatible forever; only a value this reader does not recognize is an
# explicit error.  Bump this constant when the snapshot shape gains a field
# that changes how an existing reader must interpret it.
CONTRACT_SCHEMA_VERSION = 1


def _load_yaml(path: str | pathlib.Path) -> dict[str, Any]:
    value = yaml.safe_load(pathlib.Path(path).read_text(encoding="utf-8")) or {}
    return value if isinstance(value, dict) else {}


def _task_node(value: dict[str, Any]) -> dict[str, Any]:
    task = value.get("task", value)
    return task if isinstance(task, dict) else {}


def ac_version_from_criteria(criteria: Any) -> str:
    """Return the canonical 8-character AC fingerprint used by the gate."""
    if isinstance(criteria, list):
        items = criteria
    elif isinstance(criteria, dict):
        items = list(criteria.values())
    else:
        items = []

    values: list[str] = []
    for item in items:
        if not isinstance(item, dict):
            values.append(str(item))
            continue
        description = str(item.get("description", "") or "").strip()
        if description:
            values.append(description)
            continue
        checks = item.get("checks", [])
        if isinstance(checks, list):
            values.append(
                "|".join(
                    str(check.get("check", "") or "").strip()
                    if isinstance(check, dict)
                    else str(check).strip()
                    for check in checks
                )
            )
        else:
            values.append(str(item.get("check", "") or "").strip())
    return hashlib.md5("|".join(sorted(values)).encode()).hexdigest()[:8]


def compute_task_ac_version(task_path: str | pathlib.Path) -> str:
    task = _task_node(_load_yaml(task_path))
    return ac_version_from_criteria(task.get("acceptance_criteria", []))


def task_ac_version_status(task_path: str | pathlib.Path) -> tuple[bool, str]:
    """Match cmd_complete_gate's saved-vs-recomputed task AC check."""
    task = _task_node(_load_yaml(task_path))
    saved = str(task.get("ac_version") or "").strip()
    normalized = saved.lower()
    if normalized in {"", "null", "none", "~"}:
        return True, "task.ac_version missing (compatibility skip)"
    if saved.isdigit():
        return True, f"legacy numeric ac_version={saved} (compatibility skip)"
    computed = compute_task_ac_version(task_path)
    if saved != computed:
        return False, f"ac_version_stale:task={saved}:computed={computed}"
    return True, f"ac_version={saved}"


def _command_from(data: dict[str, Any], cmd_id: str) -> dict[str, Any] | None:
    commands = data.get("commands", data)
    if isinstance(commands, dict):
        item = commands.get(cmd_id)
        return item if isinstance(item, dict) else None
    if isinstance(commands, list):
        return next(
            (
                item
                for item in commands
                if isinstance(item, dict) and str(item.get("id")) == cmd_id
            ),
            None,
        )
    return None


def parent_contract_ac_version(
    report_path: str | pathlib.Path, tasks_dir: str | pathlib.Path
) -> tuple[str, str]:
    """Resolve the report's immutable parent contract for SG-PRE10."""
    report = _load_yaml(report_path)
    parent_cmd = str(report.get("parent_cmd") or "").strip()
    if not parent_cmd:
        return "", "parent_cmd missing"

    snapshot = report.get("task_contract_snapshot")
    if isinstance(snapshot, dict):
        snapshot_parent = str(snapshot.get("parent_cmd") or "").strip()
        snapshot_ac = str(snapshot.get("ac_fingerprint") or "").strip()
        if snapshot_parent != parent_cmd:
            return "", "report.parent_cmd contract mismatch"
        if snapshot_ac:
            return snapshot_ac, "report.parent_cmd contract"

    root = pathlib.Path(tasks_dir).resolve().parent
    candidates = [
        root / "queue" / "shogun_to_karo.yaml",
        root / "queue" / "reopened_cmds" / f"{parent_cmd}.yaml",
    ]
    candidates.extend(
        pathlib.Path(path)
        for path in sorted(
            (root / "queue" / "archive" / "cmds").glob(f"{parent_cmd}_*.yaml"),
            reverse=True,
        )
    )
    for path in candidates:
        if not path.is_file():
            continue
        try:
            command = _command_from(_load_yaml(path), parent_cmd)
        except (OSError, yaml.YAMLError):
            continue
        if isinstance(command, dict) and command.get("acceptance_criteria"):
            return (
                ac_version_from_criteria(command["acceptance_criteria"]),
                "report.parent_cmd saved contract",
            )
    return "", "parent contract unavailable"


def _lesson_ids(raw: Any) -> list[str]:
    values: list[str] = []
    for item in raw if isinstance(raw, list) else []:
        value = item.get("id") if isinstance(item, dict) else item
        value = str(value or "").strip()
        if value and value not in values:
            values.append(value)
    return values


def _lesson_contract(task: dict[str, Any]) -> tuple[str, list[str]]:
    """Return the task-generation lesson mode and its canonical IDs."""
    assigned = task.get("assigned_lesson_ids")
    if isinstance(assigned, list) and assigned:
        return "strict", _lesson_ids(assigned)
    return "subset", _lesson_ids(task.get("related_lessons") or [])


def _report_identity_matches_task(
    report: dict[str, Any], task: dict[str, Any]
) -> bool:
    """Check the report against the live worker lease when it is available.

    Deployed reports carry both fields.  The parent-only fallback keeps old
    hand-written fixtures working, while any explicit task-id disagreement is
    treated as a different lease rather than silently borrowing its lessons.
    """
    report_parent = str(report.get("parent_cmd") or "").strip()
    task_parent = str(task.get("parent_cmd") or "").strip()
    report_task_id = str(report.get("task_id") or "").strip()
    task_task_id = str(task.get("task_id") or "").strip()

    if report_parent and task_parent and report_parent != task_parent:
        return False
    if bool(report_task_id) != bool(task_task_id):
        return False
    if report_task_id and report_task_id != task_task_id:
        return False
    if report_parent and not task_parent:
        return False
    return True


def _snapshot_lesson_contract(
    report: dict[str, Any],
) -> tuple[str, list[str], str] | None:
    """Read the immutable lesson-set snapshot embedded at report creation.

    ``None`` means this is a legacy report with no lesson snapshot.  A
    malformed explicit snapshot is represented by ``snapshot-invalid`` so it
    cannot accidentally become an empty allowlist.
    """
    snapshot = report.get("task_contract_snapshot")
    if not isinstance(snapshot, dict):
        return None

    snapshot_parent = str(snapshot.get("parent_cmd") or "").strip()
    report_parent = str(report.get("parent_cmd") or "").strip()
    snapshot_task_id = str(snapshot.get("task_id") or "").strip()
    report_task_id = str(report.get("task_id") or "").strip()
    if ((snapshot_parent and report_parent and snapshot_parent != report_parent)
            or (snapshot_task_id and report_task_id and snapshot_task_id != report_task_id)
            or bool(snapshot_task_id) != bool(report_task_id)):
        return (
            "snapshot-invalid",
            [],
            "snapshot identity does not match report identity",
        )

    raw = snapshot.get("lesson_set")
    if raw is None:
        # Accept the descriptive alias used by early fixtures during the
        # migration, but do not infer a lesson set from the live task.
        raw = snapshot.get("lesson_set_snapshot")
    if raw is None:
        return None

    if isinstance(raw, dict):
        mode = str(raw.get("mode") or "subset").strip().lower()
        ids = raw.get("ids")
    else:
        mode = "subset"
        ids = raw
    if mode not in {"strict", "subset"} or not isinstance(ids, list):
        return "snapshot-invalid", [], "snapshot lesson_set must contain mode and ids"
    return mode, _lesson_ids(ids), "report.task_contract_snapshot.lesson_set"


def lesson_feedback_set_status(
    task_path: str | pathlib.Path, report_path: str | pathlib.Path
) -> tuple[bool, str]:
    """Apply cmd_complete_gate's strict/subset lesson feedback contract.

    The worker task file is a mutable lease.  A completed report must use its
    immutable deploy-time lesson snapshot after a lease handoff; otherwise a
    later task's lessons become false ``extra`` feedback.  Legacy reports are
    allowed to use the current task only while their explicit identity still
    matches.  A legacy identity mismatch gets an empty allowlist, preserving
    detection of genuine historical extras without self-authorizing them.
    """
    task = _task_node(_load_yaml(task_path))
    report = _load_yaml(report_path)
    snapshot_contract = _snapshot_lesson_contract(report)
    compatibility = ""
    if snapshot_contract is not None:
        mode, allowed, source = snapshot_contract
        if mode == "snapshot-invalid":
            return False, f"MISMATCH mode=snapshot-invalid detail={source}"
    elif _report_identity_matches_task(report, task):
        mode, allowed = _lesson_contract(task)
        source = "current task identity"
    else:
        mode, allowed = "legacy-incompatible", []
        source = "legacy compatibility"
        compatibility = " compatibility=identity-mismatch"
    strict = mode == "strict"
    raw_reported = report.get("lessons_useful")
    if raw_reported is None:
        raw_reported = report.get("lesson_referenced")

    reported: list[str] = []
    duplicates: list[str] = []
    for item in raw_reported if isinstance(raw_reported, list) else []:
        value = item.get("id") if isinstance(item, dict) else item
        value = str(value or "").strip()
        if not value:
            continue
        if value in reported:
            duplicates.append(value)
        else:
            reported.append(value)

    extra = sorted(set(reported) - set(allowed))
    missing = sorted(set(allowed) - set(reported)) if strict else []
    duplicates = sorted(set(duplicates))
    if extra or missing or duplicates:
        return (
            False,
            "MISMATCH "
            f"mode={mode} "
            f"missing={','.join(missing) or 'none'} "
            f"extra={','.join(extra) or 'none'} "
            f"duplicates={','.join(duplicates) or 'none'}"
            f"{compatibility} source={source}",
        )
    return (
        True,
        f"OK mode={mode} allowed={len(allowed)} reported={len(reported)}"
        f"{compatibility} source={source}",
    )


def _task_identity_conflicts_with_report(
    report: dict[str, Any], task: dict[str, Any]
) -> bool:
    """True only when report and task each declare an identity field and disagree.

    Deliberately narrower than :func:`_report_identity_matches_task`: this
    powers the empty-lessons-allowed decision, which must stay permissive for
    legacy/minimal task fixtures that omit ``parent_cmd`` or ``task_id``
    entirely (a long-standing fixture pattern elsewhere in this codebase)
    while still closing the worker-lease-reassignment gap — a live task that
    explicitly names a *different* parent_cmd or task_id than the report is a
    different lease, not a silent match.
    """
    report_parent = str(report.get("parent_cmd") or "").strip()
    task_parent = str(task.get("parent_cmd") or "").strip()
    if report_parent and task_parent and report_parent != task_parent:
        return True
    report_task_id = str(report.get("task_id") or "").strip()
    task_task_id = str(task.get("task_id") or "").strip()
    if report_task_id and task_task_id and report_task_id != task_task_id:
        return True
    return False


def lesson_empty_allowed(task_path: str | pathlib.Path, report: dict[str, Any]) -> bool:
    """Whether terminal readiness may accept an empty ``lessons_useful``.

    Mirrors :func:`lesson_feedback_set_status`'s snapshot precedence: the
    immutable deploy-time lesson snapshot embedded in the report is
    authoritative when present, so a worker lease reassignment (the live
    task file overwritten by a later deployment) cannot silently change
    what an already-published report was allowed to omit. A legacy report
    without a snapshot falls back to the live task unless it explicitly
    conflicts with the report's identity. A malformed snapshot or an
    explicit identity conflict fails closed: empty is not allowed.
    """
    snapshot_contract = _snapshot_lesson_contract(report)
    if snapshot_contract is not None:
        mode, allowed, _source = snapshot_contract
        if mode == "snapshot-invalid":
            return False
        return not allowed
    task = _task_node(_load_yaml(task_path))
    if _task_identity_conflicts_with_report(report, task):
        return False
    _mode, allowed = _lesson_contract(task)
    return not allowed


def contract_snapshot_version(snapshot: dict[str, Any]) -> tuple[int | None, str]:
    """Resolve the deploy-time snapshot's schema version.

    A snapshot with no ``contract_version`` key predates this schema and
    reads as legacy version 0 forever, so a normal old task is never newly
    blocked by this reader.  Only an explicit, unrecognized version value
    (wrong type, negative, or newer than this reader knows) is an error.
    """
    if not isinstance(snapshot, dict) or "contract_version" not in snapshot:
        return 0, "legacy snapshot (no contract_version)"
    raw = snapshot.get("contract_version")
    try:
        version = int(raw)
    except (TypeError, ValueError):
        return None, f"contract_version invalid type: {raw!r}"
    if version < 0 or version > CONTRACT_SCHEMA_VERSION:
        return None, f"contract_version unsupported: {version}"
    return version, f"contract_version={version}"


def _string_list(value: Any) -> list[str]:
    """Normalize a task field that may be a bare string, JSON-string, or list."""
    if isinstance(value, str):
        try:
            decoded = json.loads(value)
        except (TypeError, ValueError):
            decoded = None
        value = decoded if decoded is not None else [value]
    if not isinstance(value, list):
        return []
    return [str(item).strip() for item in value if str(item or "").strip()]


def task_contract_ownership(task: dict[str, Any]) -> dict[str, list[str]]:
    """Canonical owned/forbidden path sets read from the deploy-time task.

    Writer/receipt/precheck/monitor/archive each used to re-derive ownership
    from whichever field happened to be populated for a given task shape
    (``task_worktree_source_paths``, ``planned_paths``, ``target_path``).
    This is the one accessor all of them can share instead.
    """
    source = (
        _string_list(task.get("task_worktree_source_paths"))
        or _string_list(task.get("planned_paths"))
        or _string_list(task.get("target_path"))
    )
    return {
        "source": source,
        "forbidden": _string_list(task.get("not_in_scope")),
    }


def task_contract_evidence(report: dict[str, Any], root: str | pathlib.Path) -> dict[str, Any]:
    """Canonical evidence accessor: commit identity plus no-code tree proof.

    Delegates to ``report_commit_identity``'s existing predicates rather than
    re-deriving commit/no-code validity here, per the reuse-not-reimplement
    contract for this schema.
    """
    import report_commit_identity as _rci

    commit_hash = str(report.get("commit_hash") or "").strip()
    root_path = pathlib.Path(root)
    return {
        "commit_hash": commit_hash,
        "commit_identity_valid": _rci.valid_commit_identity(commit_hash, report, root_path),
        "no_commit_declared": _rci.explicit_no_commit(report),
        "no_code_change_evidence": report.get("no_code_change_evidence"),
    }


def contract_snapshot_status(
    task_path: str | pathlib.Path, report_path: str | pathlib.Path
) -> tuple[bool, str]:
    """Version-aware read of identity/AC/ownership/lesson_set together.

    A report with no ``task_contract_snapshot`` at all is pre-contract
    legacy and reads as compatible.  Inside a present snapshot, a missing
    ``contract_version`` is legacy (version 0) and also compatible; only an
    explicit unrecognized version is a hard error, so this can never newly
    BLOCK a normal old task that simply predates the field.  Ownership and
    lesson-set are read from the live task only after confirming the report's
    lease identity still matches it (see ``_report_identity_matches_task``);
    a lease handoff after redeploy is reported, not silently reinterpreted
    against the new live task.
    """
    task = _task_node(_load_yaml(task_path))
    report = _load_yaml(report_path)
    snapshot = report.get("task_contract_snapshot")
    if not isinstance(snapshot, dict):
        return True, "legacy report (no task_contract_snapshot)"

    version, version_message = contract_snapshot_version(snapshot)
    if version is None:
        return False, f"CONTRACT_INVALID {version_message}"

    if not _report_identity_matches_task(report, task):
        return True, f"identity=lease-handoff snapshot-authoritative {version_message}"

    ownership = task_contract_ownership(task)
    lesson_mode, lesson_ids = _lesson_contract(task)
    return True, (
        f"OK {version_message} owned_source={len(ownership['source'])} "
        f"forbidden={len(ownership['forbidden'])} lesson_mode={lesson_mode} "
        f"lesson_ids={len(lesson_ids)}"
    )


if __name__ == "__main__":
    import argparse
    import sys

    parser = argparse.ArgumentParser(description="shared report gate contracts")
    subparsers = parser.add_subparsers(dest="command", required=True)

    ac_parser = subparsers.add_parser("ac-version")
    ac_parser.add_argument("task_path")

    task_ac_parser = subparsers.add_parser("task-ac-version")
    task_ac_parser.add_argument("task_path")

    lesson_parser = subparsers.add_parser("lesson-feedback-set")
    lesson_parser.add_argument("task_path")
    lesson_parser.add_argument("report_path")

    contract_parser = subparsers.add_parser("contract-status")
    contract_parser.add_argument("task_path")
    contract_parser.add_argument("report_path")

    empty_parser = subparsers.add_parser("lesson-empty-allowed")
    empty_parser.add_argument("task_path")
    empty_parser.add_argument("report_path")

    args = parser.parse_args()
    if args.command == "ac-version":
        print(compute_task_ac_version(args.task_path))
        raise SystemExit(0)
    if args.command == "task-ac-version":
        ok, message = task_ac_version_status(args.task_path)
        print(message)
        raise SystemExit(0 if ok else 1)
    if args.command == "contract-status":
        ok, message = contract_snapshot_status(args.task_path, args.report_path)
        print(message)
        raise SystemExit(0 if ok else 1)
    if args.command == "lesson-empty-allowed":
        # cmd_karo_hotfix_contract_schema_20260907: exposes lesson_empty_allowed
        # (already the snapshot-authoritative rule inside this module) so a
        # bash consumer such as cmd_complete_gate.sh's
        # handle_empty_lessons_useful_check can consult it instead of
        # blocking on an empty lessons_useful whenever the deploy-time
        # snapshot's own lesson_set was legitimately empty.
        allowed = lesson_empty_allowed(args.task_path, _load_yaml(args.report_path))
        print("ALLOWED" if allowed else "NOT_ALLOWED")
        raise SystemExit(0 if allowed else 1)
    ok, message = lesson_feedback_set_status(args.task_path, args.report_path)
    print(message)
    raise SystemExit(0 if ok else 1)
