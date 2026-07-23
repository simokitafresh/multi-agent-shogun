#!/usr/bin/env python3
"""Fast, textual publication of deploy-task report templates.

The deploy path already owns the canonical report template.  This helper keeps
those bytes and mutates only task-specific scalars plus the two generated
sections (``lessons_useful`` and ``binary_checks``).  Operational report YAML
is never serialized with PyYAML; PyYAML is used once, to parse the task input.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import tempfile
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

import yaml

from ac_contract import canonical_assigned_ids


REPORT_ID_RE = re.compile(r"^report_id:\s*['\"]?([^\s'\"#]+)", re.MULTILINE)
REPORT_STATUS_RE = re.compile(r"^status:\s*['\"]?([^\s'\"#]+)", re.MULTILINE)
REQUIRED_REPORT_KEYS = (
    "worker_id",
    "report_id",
    "report_identity_version",
    "task_id",
    "parent_cmd",
    "task_type",
    "result",
    "purpose_validation",
    "files_modified",
    "lesson_candidate",
    "lessons_useful",
    "skill_candidate",
    "decision_candidate",
    "knowledge_candidate",
    "assumption_invalidation",
    "operational_simulation",
    "binary_checks",
    "self_gate_check",
    "verdict",
)


@dataclass(frozen=True)
class Publication:
    report_bytes: bytes
    task_metadata_patch: dict[str, Any]
    reused_existing: bool


@dataclass(frozen=True)
class ExistingReport:
    """One report plus the current task state of its owning worker."""

    path: str
    report_bytes: bytes
    owner_task_parent_cmd: str = ""
    owner_task_status: str = ""


@dataclass(frozen=True)
class PublicationPlan:
    publication: Publication
    destination: str
    archive_paths: tuple[str, ...]
    protected_paths: tuple[str, ...]
    publish_required: bool = True


def _as_text(data: bytes | str | None) -> str:
    if data is None:
        return ""
    if isinstance(data, bytes):
        return data.decode("utf-8")
    return data


def _task_from_bytes(task_bytes: bytes) -> dict[str, Any]:
    """The only YAML parse in the publication path."""
    loaded = yaml.safe_load(task_bytes.decode("utf-8")) or {}
    if not isinstance(loaded, dict):
        raise ValueError("task YAML root must be a mapping")
    task = loaded.get("task", loaded)
    if not isinstance(task, dict):
        raise ValueError("task entry must be a mapping")
    return task


def _clean(value: Any) -> str:
    return "" if value is None else str(value).strip().strip("\"'")


def _yaml_scalar(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    return json.dumps(_clean(value), ensure_ascii=False)


def _report_scalar(text: str, key: str) -> str:
    match = re.search(rf"^{re.escape(key)}:\s*['\"]?([^\n#'\"]*)", text, re.MULTILINE)
    return match.group(1).strip() if match else ""


def _replace_scalar(text: str, key: str, value: Any) -> str:
    pattern = re.compile(rf"^({re.escape(key)}:\s*)([^\n#]*)(.*)$", re.MULTILINE)
    match = pattern.search(text)
    if not match:
        raise ValueError(f"report template missing required scalar: {key}")
    wanted = _clean(value)
    if _report_scalar(text, key) == wanted:
        return text
    return pattern.sub(
        lambda m: f"{m.group(1)}{_yaml_scalar(value)}{m.group(3)}", text, count=1
    )


def _replace_section(text: str, key: str, replacement: str) -> str:
    lines = text.splitlines(keepends=True)
    start = next(
        (i for i, line in enumerate(lines) if line.startswith(f"{key}:")), None
    )
    if start is None:
        raise ValueError(f"report template missing required section: {key}")
    end = start + 1
    while end < len(lines):
        line = lines[end]
        if line and not line[0].isspace() and not line.startswith("#"):
            break
        end += 1
    block = replacement.rstrip("\n") + "\n"
    return "".join(lines[:start]) + block + "".join(lines[end:])


def _top_level_block(text: str, key: str) -> str:
    lines = text.splitlines(keepends=True)
    start = next(
        (i for i, line in enumerate(lines) if line.startswith(f"{key}:")), None
    )
    if start is None:
        raise ValueError(f"report template missing required field: {key}")
    end = start + 1
    while end < len(lines):
        line = lines[end]
        if line and not line[0].isspace() and not line.startswith("#"):
            break
        end += 1
    return "".join(lines[start:end]).rstrip("\n")


def _repair_completeness(
    existing: str, template: str, scalar_repairs: Mapping[str, Any]
) -> str:
    """Append missing canonical top-level fields without serializing YAML."""

    repaired = existing.rstrip("\n") + "\n"
    for key in REQUIRED_REPORT_KEYS:
        if re.search(rf"^{re.escape(key)}:", repaired, re.MULTILINE):
            continue
        if key in scalar_repairs:
            repaired += f"{key}: {_yaml_scalar(scalar_repairs[key])}\n"
        else:
            repaired += _top_level_block(template, key) + "\n"
    yaml.safe_load(repaired)
    return repaired


def _canonical_report_path(task: Mapping[str, Any]) -> str:
    speed = task.get("speed_campaign") or {}
    if isinstance(speed, dict):
        campaign = _clean(speed.get("campaign_id"))
        round_index = speed.get("round_index")
        expected = f"test_speed_report_{campaign}_r{round_index}.yaml"
        explicit_name = _clean(task.get("report_filename"))
        explicit_path = _clean(task.get("report_path"))
        if (
            campaign
            and isinstance(round_index, int)
            and round_index > 0
            and explicit_name == expected
            and explicit_path == f"queue/reports/{expected}"
        ):
            return explicit_path
    parent = _clean(task.get("parent_cmd") or task.get("cmd_id"))
    worker = _task_worker(task)
    explicit_name = Path(_clean(task.get("report_filename"))).name
    expected_suffix = f"_report_{parent}.yaml"
    if parent.startswith("cmd_") and explicit_name.endswith(expected_suffix):
        return f"queue/reports/{explicit_name}"
    if parent.startswith("cmd_"):
        return f"queue/reports/{worker}_report_{parent}.yaml"
    return f"queue/reports/{worker}_report.yaml"


def _task_worker(task: Mapping[str, Any]) -> str:
    worker = _clean(task.get("assigned_to") or task.get("worker_id"))
    if worker:
        return worker
    filename = Path(_clean(task.get("report_filename"))).name
    if "_report" in filename:
        return filename.split("_report", 1)[0]
    return ""


def _lesson_ids(task: Mapping[str, Any]) -> list[str]:
    assigned = task.get("assigned_lesson_ids")
    if isinstance(assigned, list) and assigned:
        return [_clean(item) for item in assigned if _clean(item)]
    related = task.get("related_lessons") or []
    if not isinstance(related, list):
        return []
    result: list[str] = []
    for item in related:
        lesson_id = item.get("id") if isinstance(item, dict) else item
        if _clean(lesson_id):
            result.append(_clean(lesson_id))
    return result


def _lessons_block(ids: Iterable[str]) -> str:
    ids = list(ids)
    if not ids:
        return "lessons_useful: []  # ★教訓注入なし。このフィールドを変更するな。空リストのまま提出せよ"
    lines = [
        "lessons_useful:  # ★教訓注入済み。[]で上書きするな。各教訓にuseful+reasonを記入せよ"
    ]
    for lesson_id in ids:
        lines.extend(
            (
                f"  - id: {lesson_id}",
                "    useful: false",
                "    reason: '未参照'  # 有用/無用の具体理由を記入",
            )
        )
    return "\n".join(lines)


def _split_checks(value: Any) -> list[str]:
    text = _clean(value).replace("FILL_THIS", "FILL-THIS")
    return [part.strip() for part in re.split(r"。+", text) if part.strip()]


def _normalize_check(value: Any, description: Any = "") -> str:
    check = _clean(value).replace("FILL_THIS", "FILL-THIS")
    desc = _clean(description)
    if re.search(r"monthly|月次", desc, re.IGNORECASE) and "進行中月除外" not in check:
        check += " (進行中月除外)"
    if "全テストPASS(bats --jobs 4 tests/unit)" in check:
        return "bash scripts/affected_tests.sh で列挙されたテストを実行し、空リスト時は bats --jobs 4 tests/unit にフォールバックしてPASS確認"
    return check


def _criteria(task: Mapping[str, Any]) -> list[tuple[str, list[str]]]:
    raw = task.get("acceptance_criteria") or []
    # assigned_acs is the parent-contract SSOT. ac_assigned remains a legacy
    # compatibility alias. Reading only the alias re-expanded split reports to
    # every parent AC during fast publication (cmd_4127).
    selected = canonical_assigned_ids(task)
    result: list[tuple[str, list[str]]] = []
    items = (
        list(raw.items())
        if isinstance(raw, dict)
        else list(enumerate(raw, start=1))
        if isinstance(raw, list)
        else []
    )
    for position, pair in enumerate(items, start=1):
        key, value = pair
        ac_id = _clean(key) if isinstance(raw, dict) else f"AC{key}"
        description: Any = ""
        checks: list[Any] = []
        if isinstance(value, dict):
            ac_id = _clean(value.get("id")) or ac_id
            ac_value = _clean(value.get("ac"))
            if re.match(r"^AC[\w-]+\s*:", ac_value):
                parsed_id, description = ac_value.split(":", 1)
                ac_id = _clean(parsed_id)
            description = value.get("description") or description
            raw_checks = value.get("binary_checks") or value.get("checks") or []
            if isinstance(raw_checks, list):
                checks = [
                    (item.get("check") or item.get("description") or item.get("name"))
                    if isinstance(item, dict)
                    else item
                    for item in raw_checks
                ]
        elif isinstance(value, list):
            checks = [
                item.get("check") if isinstance(item, dict) else item for item in value
            ]
        else:
            description = value
        if not checks:
            checks = _split_checks(description)
        normalized = [
            _normalize_check(item, description) for item in checks if _clean(item)
        ]
        if not normalized:
            normalized = [f"FILL: {ac_id}の確認項目を記入"]
        if not selected or ac_id in selected:
            result.append((ac_id or f"AC{position}", normalized))
    return result


def _owned_paths(task: Mapping[str, Any]) -> list[str]:
    result: list[str] = []
    for key in ("owned_paths", "planned_paths", "files_to_modify", "files_modified", "target_path"):
        raw = task.get(key)
        values = raw if isinstance(raw, list) else [raw]
        for value in values:
            if isinstance(value, Mapping):
                value = value.get("path") or value.get("file")
            text = _clean(value)
            if text and text not in result:
                result.append(text)
    return result


def _commit_contract(task: Mapping[str, Any]) -> dict[str, Any]:
    task_type = _clean(
        task.get("task_type") or task.get("type") or task.get("scope_mode")
    ).lower()
    paths = _owned_paths(task)
    explicit = task.get("commit_contract")
    if isinstance(explicit, Mapping) and isinstance(explicit.get("required"), bool):
        return {
            "required": explicit["required"],
            "reason": _clean(explicit.get("reason")) or "task_commit_contract_explicit",
            "task_type": _clean(explicit.get("task_type")) or task_type or "unknown",
            "planned_paths": _owned_paths(explicit) or paths,
        }
    scope = (
        f"{_clean(task.get('constraints'))} {_clean(task.get('not_in_scope'))}".lower()
    )
    explicit_no_code = bool(
        re.search(
            r"コード変更.*禁止|変更.*禁止.*(?:調査|報告)|no[ _-]?code|read[ _-]?only",
            scope,
        )
    )
    code_path = bool(
        re.search(
            r"(?:scripts/|src/|tests/|app/|lib/|\.(?:sh|py|js|ts|go|rs|java|kt)\b)",
            " ".join(paths),
            re.I,
        )
    )
    allowed_no_code = {
        "no_code",
        "no-code",
        "decision",
        "decision_candidate",
        "data_readonly",
        "data-readonly",
        "readonly",
        "read_only",
        "recon",
        "recon2",
        "scout",
    }
    # recon2/scout等は読み取り専用。inspection_path/readonly_refsにscripts/パスがあっても
    # コード変更しないためcode_pathに関係なくrequired=false (2026-07-23 軍師D0)
    required = not (explicit_no_code or (task_type in allowed_no_code))
    if explicit_no_code:
        reason = "explicit_no_code_scope"
    elif task_type in allowed_no_code:
        reason = "allowed_no_code_task_type"
    elif code_path:
        reason = "implementation_path_present"
    else:
        reason = "code_or_unclassified_task"
    return {
        "required": required,
        "reason": reason,
        "task_type": task_type or "unknown",
        "planned_paths": paths,
    }


def _commit_required(task: Mapping[str, Any]) -> bool:
    return bool(_commit_contract(task)["required"])


def _commit_contract_block(task: Mapping[str, Any]) -> str:
    contract = _commit_contract(task)
    lines = [
        "commit_contract:",
        f"  required: {'true' if contract['required'] else 'false'}",
        f"  reason: {_yaml_scalar(contract['reason'])}",
        f"  task_type: {_yaml_scalar(contract['task_type'])}",
        "  planned_paths:",
    ]
    paths = contract["planned_paths"]
    if paths:
        lines.extend(f"  - {_yaml_scalar(path)}" for path in paths)
    else:
        lines[-1] = "  planned_paths: []"
    return "\n".join(lines)


def _binary_checks_block(task: Mapping[str, Any]) -> str:
    lines = ["binary_checks:"]
    for ac_id, checks in _criteria(task):
        lines.append(f"  {ac_id}:")
        for check in checks:
            lines.append(f"  - check: {_yaml_scalar(check)}")
            lines.append('    result: ""  # yes or no')
    lines.extend(
        (
            "  commit:",
            f"  - check: {_yaml_scalar('git commitが完了したか(untracked/modified=0)' if _commit_required(task) else 'commit N/A証跡とコード変更・stage/commitを実行していないことを確認')}",
            '    result: ""  # yes or no',
        )
    )
    return "\n".join(lines)


def _variation_required(task: Mapping[str, Any]) -> bool:
    task_type = _clean(
        task.get("task_type") or task.get("type") or task.get("scope_mode")
    ).lower()
    if task_type in {"scout", "recon", "recon2"}:
        return False
    text = " ".join(
        _clean(task.get(key))
        for key in (
            "title",
            "purpose",
            "command",
            "description",
            "target_path",
            "acceptance_criteria",
            "constraints",
            "not_in_scope",
        )
    ).lower()
    # Negative scope statements describe what the task is not.  Leaving their
    # keywords in the classifier made phrases such as "gate/hook変更でないUI修正"
    # satisfy both the enforcement and code predicates.
    classifier_text = re.sub(
        r"(?:gate|hook|ゲート|フック)(?:\s*[/・]\s*(?:gate|hook|ゲート|フック))?"
        r"\s*(?:の)?変更\s*(?:で|では)?ない",
        "",
        text,
    )
    enforcement = bool(
        re.search(
            r"enforcement|gate|hook|detector|guard|watcher|state[ _-]?machine|ゲート|フック|検知器|ガード|監視",
            classifier_text,
        )
    )
    code = bool(
        re.search(
            r"scripts/|\.sh\b|\.py\b|コード変更|コード修正|実装|修正|implement|\bfix\b",
            classifier_text,
        )
    )
    docs_only = bool(
        re.search(
            r"docs?[ _-]?only|documentation[ _-]?only|教訓のみ|fixtureのみ|索引のみ|docsのみ",
            classifier_text,
        )
    )
    return enforcement and code and not docs_only


def build_publication(
    task_bytes: bytes,
    template_bytes: bytes,
    existing_report_bytes: bytes | None = None,
    *,
    report_id: str | None = None,
    report_path: str | None = None,
) -> Publication:
    task = _task_from_bytes(task_bytes)
    template = _as_text(template_bytes)
    existing = _as_text(existing_report_bytes)
    desired_id = report_id or _clean(task.get("report_id")) or f"rpt-{uuid.uuid4()}"
    if not re.fullmatch(
        r"rpt-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}",
        desired_id,
    ):
        raise ValueError("report_id must be an RFC 4122 version-4 rpt identity")
    canonical_path = _canonical_report_path(task)
    rel_path = report_path or _clean(task.get("report_path")) or canonical_path
    parent = _clean(task.get("parent_cmd") or task.get("cmd_id"))
    if parent.startswith("cmd_") and Path(rel_path).name != Path(canonical_path).name:
        rel_path = canonical_path
    patch = {
        "report_id": desired_id,
        "report_identity_version": 2,
        "report_path": rel_path,
        "report_filename": Path(rel_path).name,
        "variation_checks_required": _variation_required(task),
        "commit_contract": _commit_contract(task),
    }
    scalar_values = {
        "worker_id": task.get("assigned_to")
        or task.get("worker_id")
        or _report_scalar(template, "worker_id"),
        "report_id": desired_id,
        "report_identity_version": 2,
        "task_id": task.get("task_id")
        or task.get("_ac_task_id")
        or task.get("subtask_id")
        or _report_scalar(template, "task_id"),
        "parent_cmd": task.get("parent_cmd")
        or task.get("cmd_id")
        or _report_scalar(template, "parent_cmd"),
        "task_type": task.get("task_type")
        or task.get("type")
        or task.get("scope_mode")
        or _report_scalar(template, "task_type"),
        "ac_version_read": task.get("ac_version")
        or _report_scalar(template, "ac_version_read"),
    }
    existing_id = REPORT_ID_RE.search(existing)
    existing_status = REPORT_STATUS_RE.search(existing)
    if (
        existing
        and existing_id
        and existing_id.group(1) == desired_id
        and existing_status
        and existing_status.group(1) == "pending"
    ):
        repaired = _repair_completeness(existing, template, scalar_values)
        repaired = _replace_section(
            repaired, "commit_contract", _commit_contract_block(task)
        )
        if _report_scalar(repaired, "parent_cmd") != parent:
            existing = ""
        else:
            return Publication(repaired.encode("utf-8"), patch, True)

    report = template
    for key, value in scalar_values.items():
        report = _replace_scalar(report, key, value)
    report = _replace_section(
        report, "lessons_useful", _lessons_block(_lesson_ids(task))
    )
    report = _replace_section(
        report, "commit_contract", _commit_contract_block(task)
    )
    report = _replace_section(report, "binary_checks", _binary_checks_block(task))
    _validate_structural_report(report)
    return Publication(report.encode("utf-8"), patch, False)


def plan_publication(
    task_bytes: bytes,
    template_bytes: bytes,
    existing_reports: Sequence[ExistingReport] = (),
    *,
    report_id: str | None = None,
) -> PublicationPlan:
    """Plan production-safe reuse/archive/protection without filesystem writes.

    Completed reports and active peer reports are immutable.  Pending reports
    are reusable only at the canonical basename with the same parent command
    and report identity.  Every other pending artifact is stale and is offered
    to the caller for archival before atomic publication.
    """

    task = _task_from_bytes(task_bytes)
    destination = _canonical_report_path(task)
    worker = _task_worker(task)
    parent = _clean(task.get("parent_cmd") or task.get("cmd_id"))
    desired_id = report_id or _clean(task.get("report_id"))
    archive: list[str] = []
    protected: list[str] = []
    reusable: bytes | None = None

    for artifact in existing_reports:
        path = artifact.path
        basename = Path(path).name
        owner = basename.split("_report", 1)[0] if "_report" in basename else ""
        try:
            value = yaml.safe_load(artifact.report_bytes) or {}
            if not isinstance(value, dict):
                raise ValueError("report root must be mapping")
        except (yaml.YAMLError, ValueError):
            if owner == worker or path == destination:
                archive.append(path)
            continue

        report_parent = _clean(value.get("parent_cmd"))
        status = _clean(value.get("status"))
        verdict = _clean(value.get("verdict"))
        completed = status == "completed" or bool(
            verdict and verdict not in {"null", '""'}
        )
        peer_active = (
            owner != worker
            and artifact.owner_task_parent_cmd == parent
            and artifact.owner_task_status
            in {"assigned", "acknowledged", "in_progress"}
        )
        if completed or peer_active:
            protected.append(path)
            continue

        # Production scans only this worker's active generation and peer
        # reports for the same parent command.  Unrelated peer reports are not
        # owned by this publication and must remain untouched.
        if owner != worker and report_parent != parent:
            continue

        same_generation = (
            path == destination
            and basename == Path(destination).name
            and report_parent in {"", parent}
            and status == "pending"
            and bool(desired_id)
            and _clean(value.get("report_id")) == desired_id
        )
        if same_generation:
            reusable = artifact.report_bytes
        else:
            archive.append(path)

    destination_protected = destination in protected
    publication = build_publication(
        task_bytes,
        template_bytes,
        reusable,
        report_id=desired_id or report_id,
        report_path=destination,
    )
    return PublicationPlan(
        publication,
        destination,
        tuple(dict.fromkeys(archive)),
        tuple(dict.fromkeys(protected)),
        not destination_protected,
    )


def _patch_task_metadata(task_path: Path, patch: Mapping[str, Any]) -> None:
    """Publish task metadata with a targeted textual rewrite and one rename."""

    raw = task_path.read_text(encoding="utf-8")
    structured_contract = patch.get("commit_contract")
    scalar_patch = {
        key: value for key, value in patch.items() if key != "commit_contract"
    }

    def metadata_scalar(value: Any) -> str:
        if isinstance(value, (bool, int)):
            return _yaml_scalar(value)
        clean = _clean(value)
        return (
            clean if re.fullmatch(r"[A-Za-z0-9_./:-]+", clean) else _yaml_scalar(value)
        )

    lines = raw.splitlines()
    output: list[str] = []
    seen: set[str] = set()
    in_task = False
    insertion = 0
    for line in lines:
        if line == "task:":
            in_task = True
            output.append(line)
            insertion = len(output)
            continue
        if in_task and line and not line[0].isspace() and not line.startswith("#"):
            for key, value in scalar_patch.items():
                if key not in seen:
                    output.append(f"  {key}: {metadata_scalar(value)}")
            in_task = False
        match = re.match(r"^  ([A-Za-z_][A-Za-z0-9_]*):", line) if in_task else None
        if match and match.group(1) in scalar_patch:
            key = match.group(1)
            output.append(f"  {key}: {metadata_scalar(scalar_patch[key])}")
            seen.add(key)
        else:
            output.append(line)
    if in_task:
        for key, value in scalar_patch.items():
            if key not in seen:
                output.append(f"  {key}: {metadata_scalar(value)}")
    if isinstance(structured_contract, Mapping):
        contract_lines = [
            "  commit_contract:",
            f"    required: {'true' if structured_contract.get('required') else 'false'}",
            f"    reason: {_yaml_scalar(structured_contract.get('reason'))}",
            f"    task_type: {_yaml_scalar(structured_contract.get('task_type'))}",
            "    planned_paths:",
        ]
        contract_paths = structured_contract.get("planned_paths") or []
        if contract_paths:
            contract_lines.extend(
                f"    - {_yaml_scalar(path)}" for path in contract_paths
            )
        else:
            contract_lines[-1] = "    planned_paths: []"
        rewritten: list[str] = []
        skip_contract = False
        inserted = False
        for line in output:
            indent = len(line) - len(line.lstrip(" "))
            if skip_contract:
                if line.strip() == "" or indent > 2:
                    continue
                skip_contract = False
            if line.startswith("  commit_contract:"):
                if not inserted:
                    rewritten.extend(contract_lines)
                    inserted = True
                skip_contract = True
                continue
            rewritten.append(line)
        if not inserted:
            task_line = rewritten.index("task:") + 1
            rewritten[task_line:task_line] = contract_lines
        output = rewritten
    rendered = "\n".join(output) + ("\n" if raw.endswith("\n") else "")
    yaml.safe_load(rendered)
    stage = task_path.with_name(f".{task_path.name}.report-meta.{os.getpid()}")
    stage.write_text(rendered, encoding="utf-8")
    os.replace(stage, task_path)


def execute_publication_plan(
    root: Path,
    task_path: Path,
    template_bytes: bytes,
    *,
    report_id: str,
    ext4_temp_dir: Path = Path("/tmp"),
) -> PublicationPlan:
    """Archive -> publish -> task patch -> active pointer, in that order."""

    task = _task_from_bytes(task_path.read_bytes())
    worker = _task_worker(task)
    parent = _clean(task.get("parent_cmd") or task.get("cmd_id"))
    destination_name = Path(_canonical_report_path(task)).name
    reports_dir = root / "queue" / "reports"
    candidates: list[ExistingReport] = []
    for report in reports_dir.glob("*_report*.yaml") if reports_dir.exists() else ():
        owner = report.name.split("_report", 1)[0]
        # This publication owns only the worker's generations and peer reports
        # for the same parent command.  Reading/parsing every historical report
        # made the DrvFs hot path proportional to the entire report corpus even
        # though plan_publication deliberately leaves unrelated peers untouched.
        own_generation = owner == worker
        peer_generation = bool(parent) and report.name.endswith(
            f"_report_{parent}.yaml"
        )
        if not (own_generation or peer_generation or report.name == destination_name):
            continue
        owner_task = root / "queue" / "tasks" / f"{owner}.yaml"
        owner_parent = owner_status = ""
        if owner_task.exists():
            try:
                owner_data = _task_from_bytes(owner_task.read_bytes())
                owner_parent = _clean(owner_data.get("parent_cmd"))
                owner_status = _clean(owner_data.get("status"))
            except (ValueError, yaml.YAMLError, UnicodeDecodeError):
                pass
        candidates.append(
            ExistingReport(
                report.relative_to(root).as_posix(),
                report.read_bytes(),
                owner_parent,
                owner_status,
            )
        )
    plan = plan_publication(
        task_path.read_bytes(), template_bytes, candidates, report_id=report_id
    )

    stale_dir = root / "archive" / "reports" / "stale"
    for relative in plan.archive_paths:
        source = root / relative
        if not source.exists():
            continue
        stale_dir.mkdir(parents=True, exist_ok=True)
        target = stale_dir / source.name
        if target.exists():
            target = stale_dir / f"{source.stem}.{uuid.uuid4().hex}{source.suffix}"
        os.replace(source, target)

    destination = root / plan.destination
    if plan.publish_required:
        atomic_publish(
            plan.publication.report_bytes, destination, ext4_temp_dir=ext4_temp_dir
        )
    elif not destination.exists():
        raise ValueError("protected destination disappeared before publication")

    metadata = dict(plan.publication.task_metadata_patch)
    if not plan.publish_required:
        protected = yaml.safe_load(destination.read_bytes()) or {}
        existing_id = _clean(protected.get("report_id"))
        if existing_id:
            metadata["report_id"] = existing_id
    _patch_task_metadata(task_path, metadata)

    pointer = reports_dir / f".deploy_active_{worker}"
    atomic_publish(
        (plan.destination + "\n").encode("utf-8"), pointer, ext4_temp_dir=ext4_temp_dir
    )
    return plan


def _validate_structural_report(text: str) -> None:
    missing = [
        key
        for key in REQUIRED_REPORT_KEYS
        if not re.search(rf"^{re.escape(key)}:", text, re.MULTILINE)
    ]
    if missing:
        raise ValueError(
            f"report template missing required fields: {', '.join(missing)}"
        )


def atomic_publish(
    report_bytes: bytes, destination: Path, *, ext4_temp_dir: Path = Path("/tmp")
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    ext4_temp_dir.mkdir(parents=True, exist_ok=True)
    build_path: Path | None = None
    stage_path = destination.with_name(
        f".{destination.name}.publish.{os.getpid()}.{uuid.uuid4().hex}"
    )
    try:
        with tempfile.NamedTemporaryFile(
            prefix="deploy-report-", dir=ext4_temp_dir, delete=False
        ) as handle:
            build_path = Path(handle.name)
            handle.write(report_bytes)
            handle.flush()
            os.fsync(handle.fileno())
        if build_path.stat().st_dev == destination.parent.stat().st_dev:
            os.replace(build_path, destination)
            build_path = None
        else:
            with build_path.open("rb") as source, stage_path.open("xb") as target:
                shutil.copyfileobj(source, target)
                target.flush()
                os.fsync(target.fileno())
            os.replace(stage_path, destination)
    finally:
        if build_path is not None:
            build_path.unlink(missing_ok=True)
        stage_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--task", type=Path, required=True)
    parser.add_argument("--template", type=Path, required=True)
    parser.add_argument("--existing", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--metadata-output", type=Path)
    parser.add_argument("--report-id")
    parser.add_argument("--report-path")
    parser.add_argument("--temp-dir", type=Path, default=Path("/tmp"))
    parser.add_argument("--execute-plan", action="store_true")
    parser.add_argument("--root", type=Path)
    args = parser.parse_args()
    if args.execute_plan:
        if args.root is None or args.report_id is None:
            parser.error("--execute-plan requires --root and --report-id")
        plan = execute_publication_plan(
            args.root,
            args.task,
            args.template.read_bytes(),
            report_id=args.report_id,
            ext4_temp_dir=args.temp_dir,
        )
        print(
            json.dumps(
                {
                    **plan.publication.task_metadata_patch,
                    "destination": plan.destination,
                    "archive_paths": plan.archive_paths,
                    "protected_paths": plan.protected_paths,
                    "reused_existing": plan.publication.reused_existing,
                    "publish_required": plan.publish_required,
                },
                ensure_ascii=False,
                separators=(",", ":"),
            )
        )
        return 0
    if args.report is None:
        parser.error("--report is required unless --execute-plan is used")
    publication = build_publication(
        args.task.read_bytes(),
        args.template.read_bytes(),
        args.existing.read_bytes()
        if args.existing and args.existing.exists()
        else None,
        report_id=args.report_id,
        report_path=args.report_path,
    )
    atomic_publish(publication.report_bytes, args.report, ext4_temp_dir=args.temp_dir)
    payload = (
        json.dumps(
            publication.task_metadata_patch, ensure_ascii=False, separators=(",", ":")
        )
        + "\n"
    )
    if args.metadata_output:
        atomic_publish(
            payload.encode("utf-8"), args.metadata_output, ext4_temp_dir=args.temp_dir
        )
    else:
        print(payload, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
