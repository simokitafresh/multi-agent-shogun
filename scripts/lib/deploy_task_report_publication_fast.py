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
from typing import Any, Iterable, Mapping

import yaml


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
    return pattern.sub(lambda m: f"{m.group(1)}{_yaml_scalar(value)}{m.group(3)}", text, count=1)


def _replace_section(text: str, key: str, replacement: str) -> str:
    lines = text.splitlines(keepends=True)
    start = next((i for i, line in enumerate(lines) if line.startswith(f"{key}:")), None)
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
    lines = ["lessons_useful:  # ★教訓注入済み。[]で上書きするな。各教訓にuseful+reasonを記入せよ"]
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
    selected = {_clean(x) for x in (task.get("ac_assigned") or [])} if isinstance(task.get("ac_assigned"), list) else set()
    result: list[tuple[str, list[str]]] = []
    items = list(raw.items()) if isinstance(raw, dict) else list(enumerate(raw, start=1)) if isinstance(raw, list) else []
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
            checks = [item.get("check") if isinstance(item, dict) else item for item in value]
        else:
            description = value
        if not checks:
            checks = _split_checks(description)
        normalized = [_normalize_check(item, description) for item in checks if _clean(item)]
        if not normalized:
            normalized = [f"FILL: {ac_id}の確認項目を記入"]
        if not selected or ac_id in selected:
            result.append((ac_id or f"AC{position}", normalized))
    return result


def _commit_required(task: Mapping[str, Any]) -> bool:
    task_type = _clean(task.get("task_type") or task.get("type") or task.get("scope_mode")).lower()
    paths = " ".join(
        _clean(task.get(key)) for key in ("target_path", "files_to_modify", "files_modified", "owned_paths")
    )
    scope = f"{_clean(task.get('constraints'))} {_clean(task.get('not_in_scope'))}".lower()
    explicit_no_code = bool(re.search(r"コード変更.*禁止|変更.*禁止.*(?:調査|報告)|no[ _-]?code|read[ _-]?only", scope))
    code_path = bool(re.search(r"(?:scripts/|src/|tests/|app/|lib/|\.(?:sh|py|js|ts|go|rs|java|kt)\b)", paths, re.I))
    return not (explicit_no_code or (task_type in {"recon", "recon2", "scout", "readonly", "read_only"} and not code_path))


def _binary_checks_block(task: Mapping[str, Any]) -> str:
    lines = ["binary_checks:"]
    for ac_id, checks in _criteria(task):
        lines.append(f"  {ac_id}:")
        for check in checks:
            lines.append(f"  - check: {_yaml_scalar(check)}")
            lines.append('    result: ""  # yes or no')
    lines.extend(("  commit:", f"  - check: {_yaml_scalar('git commitが完了したか(untracked/modified=0)' if _commit_required(task) else 'commit N/A証跡とコード変更・stage/commitを実行していないことを確認')}", '    result: ""  # yes or no'))
    return "\n".join(lines)


def _variation_required(task: Mapping[str, Any]) -> bool:
    task_type = _clean(task.get("task_type") or task.get("type") or task.get("scope_mode")).lower()
    if task_type in {"scout", "recon", "recon2"}:
        return False
    text = " ".join(_clean(task.get(key)) for key in ("title", "purpose", "command", "description", "target_path", "acceptance_criteria", "constraints", "not_in_scope")).lower()
    enforcement = bool(re.search(r"enforcement|gate|hook|detector|guard|watcher|state[ _-]?machine|ゲート|フック|検知器|ガード|監視", text))
    code = bool(re.search(r"scripts/|\.sh\b|\.py\b|コード変更|コード修正|実装|修正|implement|\bfix\b", text))
    docs_only = bool(re.search(r"docs?[ _-]?only|documentation[ _-]?only|教訓のみ|fixtureのみ|索引のみ|docsのみ", text))
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
    if not re.fullmatch(r"rpt-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", desired_id):
        raise ValueError("report_id must be an RFC 4122 version-4 rpt identity")
    rel_path = report_path or _clean(task.get("report_path"))
    if not rel_path:
        filename = _clean(task.get("report_filename"))
        parent = _clean(task.get("parent_cmd") or task.get("cmd_id"))
        worker = _clean(task.get("assigned_to"))
        filename = filename or (f"{worker}_report_{parent}.yaml" if parent.startswith("cmd_") else f"{worker}_report.yaml")
        rel_path = f"queue/reports/{filename}"
    patch = {
        "report_id": desired_id,
        "report_identity_version": 2,
        "report_path": rel_path,
        "variation_checks_required": _variation_required(task),
    }
    existing_id = REPORT_ID_RE.search(existing)
    existing_status = REPORT_STATUS_RE.search(existing)
    if existing and existing_id and existing_id.group(1) == desired_id and existing_status and existing_status.group(1) == "pending":
        _validate_structural_report(existing)
        return Publication(existing.encode("utf-8"), patch, True)

    report = template
    scalar_values = {
        "worker_id": task.get("assigned_to") or task.get("worker_id") or "",
        "report_id": desired_id,
        "report_identity_version": 2,
        "task_id": task.get("subtask_id") or task.get("task_id") or task.get("_ac_task_id") or "",
        "parent_cmd": task.get("parent_cmd") or task.get("cmd_id") or "",
        "task_type": task.get("task_type") or task.get("type") or task.get("scope_mode") or "",
        "ac_version_read": task.get("ac_version") or "",
    }
    for key, value in scalar_values.items():
        report = _replace_scalar(report, key, value)
    report = _replace_section(report, "lessons_useful", _lessons_block(_lesson_ids(task)))
    report = _replace_section(report, "binary_checks", _binary_checks_block(task))
    _validate_structural_report(report)
    return Publication(report.encode("utf-8"), patch, False)


def _validate_structural_report(text: str) -> None:
    missing = [key for key in REQUIRED_REPORT_KEYS if not re.search(rf"^{re.escape(key)}:", text, re.MULTILINE)]
    if missing:
        raise ValueError(f"report template missing required fields: {', '.join(missing)}")


def atomic_publish(report_bytes: bytes, destination: Path, *, ext4_temp_dir: Path = Path("/tmp")) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    ext4_temp_dir.mkdir(parents=True, exist_ok=True)
    build_path: Path | None = None
    stage_path = destination.with_name(f".{destination.name}.publish.{os.getpid()}.{uuid.uuid4().hex}")
    try:
        with tempfile.NamedTemporaryFile(prefix="deploy-report-", dir=ext4_temp_dir, delete=False) as handle:
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
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--metadata-output", type=Path)
    parser.add_argument("--report-id")
    parser.add_argument("--report-path")
    parser.add_argument("--temp-dir", type=Path, default=Path("/tmp"))
    args = parser.parse_args()
    publication = build_publication(
        args.task.read_bytes(),
        args.template.read_bytes(),
        args.existing.read_bytes() if args.existing and args.existing.exists() else None,
        report_id=args.report_id,
        report_path=args.report_path,
    )
    atomic_publish(publication.report_bytes, args.report, ext4_temp_dir=args.temp_dir)
    payload = json.dumps(publication.task_metadata_patch, ensure_ascii=False, separators=(",", ":")) + "\n"
    if args.metadata_output:
        atomic_publish(payload.encode("utf-8"), args.metadata_output, ext4_temp_dir=args.temp_dir)
    else:
        print(payload, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
