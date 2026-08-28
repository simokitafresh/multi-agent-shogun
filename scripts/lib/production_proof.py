#!/usr/bin/env python3
"""Extract monitor-owned production observations from deployment ACs.

The deployment task is the worker contract.  A live observation window is a
monitor contract, so it must not remain in the worker's acceptance criteria.
The proof file is deliberately JSON: JSON is a YAML 1.2 subset and avoids
round-tripping operational YAML through a lossy serializer.
"""

from __future__ import annotations

import fcntl
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any

import yaml


_OBSERVATION_RE = re.compile(
    r"(live\s*後|本番\s*(?:観測|監視|計測)|本番(?:で|の|を)?\s*(?:\d+\s*(?:h|時間|分|min)))"
    r"|(?:\d+\s*(?:h|時間|分|min|秒|s)|1h|3600\s*(?:s|秒)?)\s*(?:の)?"
    r"(?:観測|窓|計測|待|proof|証明|監視)"
    r"|観測窓|観測し|観測する|live\s*\d+\s*(?:h|時間|s|秒|分)"
    r"|(?:gate_metrics|ninja_monitor\.log|monitor).{0,30}"
    r"(?:で|から).{0,20}(?:証明|proof)",
    re.IGNORECASE,
)
_WINDOW_RE = re.compile(
    r"(?P<value>\d+(?:\.\d+)?)\s*(?P<unit>h|hour|時間|分|min|秒|s)",
    re.IGNORECASE,
)
_KEY_VALUE_RE = re.compile(
    r"(?P<label>判定式|predicate|assertion|条件|ログ名|log_name|log)\s*[:=：]\s*"
    r"(?P<value>[^,;。\n]+)",
    re.IGNORECASE,
)
_CMD_ID_RE = re.compile(r"^[A-Za-z0-9_.-]+$")


def _text(item: Any) -> str:
    if isinstance(item, str):
        return item
    if not isinstance(item, dict):
        return ""
    values: list[str] = []
    for key in ("id", "title", "description", "check", "predicate", "log_name"):
        value = item.get(key)
        if value not in (None, ""):
            values.append(str(value))
    checks = item.get("checks")
    if isinstance(checks, list):
        values.extend(_text(value) for value in checks)
    return " ".join(value for value in values if value)


def _window_seconds(text: str, item: dict[str, Any] | None = None) -> int:
    item = item or {}
    for key in ("observation_window_seconds", "window_seconds", "window_sec"):
        value = item.get(key)
        if isinstance(value, (int, float)) and not isinstance(value, bool) and value > 0:
            return int(value)
        if isinstance(value, str) and value.strip().isdigit() and int(value.strip()) > 0:
            return int(value.strip())
    match = _WINDOW_RE.search(text)
    if not match:
        return 0
    value = float(match.group("value"))
    unit = match.group("unit").lower()
    multiplier = {"h": 3600, "hour": 3600, "時間": 3600, "分": 60, "min": 60, "秒": 1, "s": 1}[unit]
    return int(value * multiplier)


def _field(item: dict[str, Any], names: tuple[str, ...], text: str) -> str:
    for name in names:
        value = item.get(name)
        if value not in (None, ""):
            return str(value).strip()
    for match in _KEY_VALUE_RE.finditer(text):
        label = match.group("label").strip().lower()
        if any(name.lower() == label for name in names):
            return match.group("value").strip()
    return ""


def _proof_check(item: Any, fallback_id: str) -> dict[str, Any]:
    mapping = item if isinstance(item, dict) else {}
    text = _text(item)
    window = _window_seconds(text, mapping)
    predicate = _field(mapping, ("predicate", "assertion", "判定式", "condition"), text)
    log_name = _field(mapping, ("log_name", "log", "ログ名"), text)
    if not predicate:
        predicate = text
    if not log_name:
        log_name = "ninja_monitor.log"
    result: dict[str, Any] = {
        "id": str(mapping.get("id") or fallback_id),
        "description": text,
        "observation_window_seconds": window,
        "predicate": predicate,
        "log_name": log_name,
    }
    return result


def _criteria_items(criteria: Any) -> list[tuple[str, Any]]:
    if isinstance(criteria, list):
        return [(str(item.get("id") or f"AC{index}"), item) if isinstance(item, dict)
                else (f"AC{index}", item) for index, item in enumerate(criteria, 1)]
    if isinstance(criteria, dict):
        return [(str(key), value) for key, value in criteria.items()]
    return []


def split_acceptance_criteria(entry: dict[str, Any], cmd_id: str) -> tuple[Any, dict[str, Any] | None]:
    """Return worker ACs and a monitor-owned proof contract."""
    explicit = entry.get("production_proof")
    criteria = entry.get("acceptance_criteria")
    implementation: Any = [] if isinstance(criteria, list) else {}
    checks: list[dict[str, Any]] = []

    for ac_id, item in _criteria_items(criteria):
        if _OBSERVATION_RE.search(_text(item)):
            checks.append(_proof_check(item, ac_id))
        else:
            if isinstance(criteria, dict):
                implementation[ac_id] = item
            else:
                implementation.append(item)

    if explicit is not None:
        if isinstance(explicit, dict):
            root = dict(explicit)
            explicit_checks = root.get("checks")
            if isinstance(explicit_checks, list):
                checks.extend(_proof_check(item, f"PROOF{index}") for index, item in enumerate(explicit_checks, 1))
            elif not checks:
                checks.append(_proof_check(root, "PROOF1"))
        elif isinstance(explicit, list):
            checks.extend(_proof_check(item, f"PROOF{index}") for index, item in enumerate(explicit, 1))
        else:
            checks.append(_proof_check({"description": str(explicit)}, "PROOF1"))

    if not checks:
        return criteria, None

    windows = [check["observation_window_seconds"] for check in checks if check["observation_window_seconds"] > 0]
    first = checks[0]
    proof: dict[str, Any] = {
        "schema_version": 1,
        "cmd_id": cmd_id,
        "observation_window_seconds": max(windows) if windows else 0,
        "predicate": first["predicate"],
        "log_name": first["log_name"],
        "checks": checks,
    }
    if isinstance(explicit, dict):
        if "observation_window_seconds" in explicit:
            proof["observation_window_seconds"] = _window_seconds(
                "", {"observation_window_seconds": explicit["observation_window_seconds"]}
            )
        elif "window_seconds" in explicit:
            proof["observation_window_seconds"] = _window_seconds(
                "", {"window_seconds": explicit["window_seconds"]}
            )
        for key in ("predicate", "log_name"):
            if key in explicit:
                proof[key] = explicit[key]
    return implementation, proof


def publish_proof(proof: dict[str, Any], proof_dir: str | os.PathLike[str]) -> Path:
    """Publish one proof under a per-command lock and atomic rename."""
    cmd_id = str(proof.get("cmd_id") or "")
    if not _CMD_ID_RE.fullmatch(cmd_id):
        raise ValueError(f"invalid command id for production proof: {cmd_id!r}")
    directory = Path(proof_dir)
    directory.mkdir(parents=True, exist_ok=True)
    destination = directory / f"{cmd_id}.yaml"
    lock_path = directory / f".{cmd_id}.lock"
    payload = (json.dumps(proof, ensure_ascii=False, indent=2, sort_keys=False) + "\n").encode("utf-8")
    with lock_path.open("a+") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        fd, temporary = tempfile.mkstemp(prefix=f".{cmd_id}.", suffix=".tmp", dir=directory)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(payload)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, destination)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
    return destination


def _atomic_task_ac_replace(task_path: str | os.PathLike[str], worker_acs: Any) -> None:
    """Replace only the task acceptance_criteria node, preserving other fields."""
    path = Path(task_path)
    lines = path.read_text(encoding="utf-8").splitlines()
    encoded = json.dumps(worker_acs, ensure_ascii=False, separators=(",", ":"))
    replacement = f"  acceptance_criteria: {encoded}"
    output: list[str] = []
    replaced = False
    skip = False
    for line in lines:
        stripped = line.lstrip(" ")
        indent = len(line) - len(stripped)
        if skip:
            if not stripped or indent > 2 or (indent == 2 and stripped.startswith("- ")):
                continue
            skip = False
        if indent == 2 and stripped.startswith("acceptance_criteria:"):
            output.append(replacement)
            replaced = True
            skip = True
            continue
        output.append(line)
    if not replaced:
        insert_at = next((index + 1 for index, line in enumerate(output) if line == "task:"), None)
        if insert_at is None:
            raise ValueError("task block missing")
        output.insert(insert_at, replacement)
    rendered = ("\n".join(output) + "\n").encode("utf-8")
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(rendered)
            handle.flush()
            os.fsync(handle.fileno())
        yaml.safe_load(rendered)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def rewrite_task_from_source(task_path: str, source_path: str, cmd_id: str, proof_dir: str) -> str:
    """Publish proof and leave only implementation ACs in a task YAML."""
    with open(source_path, encoding="utf-8") as handle:
        source = yaml.safe_load(handle) or {}
    commands = source.get("commands", source)
    entry = commands.get(cmd_id) if isinstance(commands, dict) else None
    if not isinstance(entry, dict):
        raise ValueError(f"command {cmd_id!r} not found or not a mapping")
    worker_acs, proof = split_acceptance_criteria(entry, cmd_id)
    if proof is None:
        return ""
    publish_proof(proof, proof_dir)
    _atomic_task_ac_replace(task_path, worker_acs if worker_acs is not None else [])
    return str(Path(proof_dir) / f"{cmd_id}.yaml")


def main() -> int:
    if len(sys.argv) != 5:
        print("usage: production_proof.py TASK SOURCE CMD_ID PROOF_DIR", file=sys.stderr)
        return 2
    try:
        result = rewrite_task_from_source(*sys.argv[1:])
    except (OSError, ValueError, yaml.YAMLError) as exc:
        print(f"production proof extraction failed: {exc}", file=sys.stderr)
        return 2
    if result:
        print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
