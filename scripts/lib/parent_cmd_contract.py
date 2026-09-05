#!/usr/bin/env python3
"""Fail-closed parent SSOT/purpose/AC coverage validation for numbered cmds."""
from __future__ import annotations

import argparse, glob, hashlib, json, os, re, sys
from pathlib import Path
import yaml


def load(path: Path):
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception:
        return {}


def command_from(data, cmd_id):
    commands = data.get("commands", data)
    if isinstance(commands, dict):
        item = commands.get(cmd_id)
        return item if isinstance(item, dict) else None
    if isinstance(commands, list):
        return next((x for x in commands if isinstance(x, dict) and str(x.get("id")) == cmd_id), None)
    return None


def find_parent(root: Path, cmd_id: str):
    paths = [root / "queue/shogun_to_karo.yaml", root / f"queue/reopened_cmds/{cmd_id}.yaml"]
    paths += [Path(p) for p in sorted(glob.glob(str(root / f"queue/archive/cmds/{cmd_id}_*.yaml")), reverse=True)]
    for path in paths:
        if path.is_file():
            item = command_from(load(path), cmd_id)
            if item is not None:
                return item, path
    return None, None


def ac_ids(value):
    if isinstance(value, dict):
        return [str(key) for key in value]
    result = []
    for i, item in enumerate(value or [], 1):
        if isinstance(item, dict):
            result.append(str(item.get("id") or f"AC{i}"))
        else:
            result.append(f"AC{i}")
    return result


def contract_fingerprint(cmd_id, purpose, acs):
    raw = json.dumps({"cmd": cmd_id, "purpose": purpose, "acs": acs}, ensure_ascii=False, sort_keys=True)
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


def historical_contracts(root: Path, cmd_id: str, expected: set, fingerprint: str):
    """Durable per-(worker, cmd) AC-coverage bindings captured at deployment
    time (deploy_task.sh:inject_parent_contract).  A worker's live
    queue/tasks/{worker}.yaml is overwritten on redeployment to a later,
    unrelated cmd; this archive is keyed by (worker, cmd) so it survives
    that overwrite and keeps the original binding verifiable."""
    result = {}
    directory = root / "queue/archive/parent_contracts"
    if not directory.is_dir():
        return result
    for path in sorted(directory.glob(f"*__{cmd_id}.yaml")):
        record = load(path)
        if str(record.get("parent_cmd") or "").strip() != cmd_id:
            continue
        if str(record.get("parent_contract_fingerprint") or "") != fingerprint:
            continue
        mapping = record.get("parent_ac_coverage")
        if not isinstance(mapping, list) or not mapping:
            continue
        mapping = {str(x) for x in mapping}
        if not mapping <= expected:
            continue
        worker = str(record.get("worker_id") or "").strip()
        if worker:
            result[worker] = mapping
    return result


def report_paths(root: Path, cmd_id: str):
    """Return only reports whose canonical filename belongs to cmd_id."""
    patterns = (
        f"*_report_{cmd_id}.yaml",
        f"*_report_{cmd_id}_*.yaml",
    )
    seen = set()
    for directory in (root / "queue/reports", root / "queue/archive/reports"):
        for pattern in patterns:
            for path in sorted(directory.glob(pattern)):
                if path not in seen:
                    seen.add(path)
                    yield path


def binary_check_satisfied(item, *, allow_waiver: bool):
    """Match GP-190: a PASS report may satisfy a check by explicit waiver."""
    if not isinstance(item, dict):
        return False
    result = item.get("result")
    normalized = "" if result is None else str(result).strip().lower()
    if result is True or normalized == "yes":
        return True
    return (
        allow_waiver
        and normalized in {"no", "false", "fail", "ng"}
        and bool(str(item.get("waive_reason") or "").strip())
    )


def approved_honest_fail_paths(root: Path, cmd_id: str, report_path: Path, report: dict):
    """Return only failed paths authenticated by SG7 and current Karo ACCEPT."""
    if (str(report.get("status") or "").strip(), str(report.get("verdict") or "").strip().upper()) != ("failed", "FAIL"):
        return set()
    bundle_path = root / f"queue/gates/{cmd_id}/sg7_bundle.json"
    if not bundle_path.is_file():
        return set()
    try:
        sys.path.insert(0, str(root))
        from scripts import review_bundle
        bundle = load(bundle_path)
        review = review_bundle.validate(bundle, cmd_id, "APPROVE")
        approved = set(review_bundle._attest_honest_fail(root, cmd_id, review, report_path))
    except Exception:
        return set()
    generation = hashlib.sha256(report_path.read_bytes()).hexdigest()
    try:
        report_ref = str(report_path.resolve().relative_to(root.resolve()))
    except ValueError:
        return set()
    approval_root = root / f"queue/gates/{cmd_id}/review_approvals/reports"
    for approval_path in approval_root.glob("*/karo.yaml"):
        approval = load(approval_path)
        if (
            str(approval.get("result") or "") == "ACCEPT"
            and str(approval.get("approval_mode") or "") == "approved_honest_fail"
            and str(approval.get("generation") or "") == generation
            and str(approval.get("report") or "") == report_ref
        ):
            return approved
    return set()


def validate(root: Path, cmd_id: str):
    if not re.fullmatch(r"cmd_\d+", cmd_id):
        return True, "direct/non-numbered cmd exempt"
    parent, source = find_parent(root, cmd_id)
    if parent is None:
        return False, "parent_ssot_missing"
    purpose = str(parent.get("purpose") or parent.get("title") or "").strip()
    expected = set(ac_ids(parent.get("acceptance_criteria")))
    if not purpose or not expected:
        return False, "parent_contract_incomplete"
    fingerprint = contract_fingerprint(cmd_id, purpose, sorted(expected))
    covered = set()
    task_contracts = {}
    for path in sorted((root / "queue/tasks").glob("*.yaml")):
        task = load(path).get("task") or {}
        if str(task.get("parent_cmd") or "").strip() != cmd_id:
            continue
        mapping = task.get("parent_ac_coverage") or task.get("covers_parent_acs")
        if not isinstance(mapping, list) or not mapping:
            continue
        mapping = {str(x) for x in mapping}
        if not mapping <= expected or str(task.get("parent_contract_fingerprint") or "") != fingerprint:
            continue
        task_contracts[path.stem] = mapping
    # A worker redeployed to a later, unrelated cmd overwrites its live task
    # file above, silently dropping historical coverage.  The durable
    # archive keyed by (worker, cmd) is unaffected by that overwrite.
    for worker, mapping in historical_contracts(root, cmd_id, expected, fingerprint).items():
        task_contracts.setdefault(worker, mapping)
    if not task_contracts:
        return False, "parent_mapping_missing_or_stale"
    for path in report_paths(root, cmd_id):
        report = load(path)
        if str(report.get("parent_cmd") or "").strip() != cmd_id:
            continue
        worker = str(report.get("worker_id") or "")
        mapping = task_contracts.get(worker)
        if not mapping or str(report.get("parent_contract_fingerprint") or "") != fingerprint:
            continue
        declared = report.get("parent_ac_coverage") or report.get("covers_parent_acs")
        if not isinstance(declared, list) or {str(x) for x in declared} != mapping:
            continue
        checks = report.get("binary_checks") or {}
        if isinstance(checks, dict):
            # Child AC names are a separate namespace.  Coverage is granted only
            # when every child check passes (or a PASS report explicitly waives
            # the failed check per GP-190) and the immutable mapping is bound.
            allow_waiver = str(report.get("verdict") or "").strip().upper() == "PASS"
            approved_failures = approved_honest_fail_paths(root, cmd_id, path, report)
            checks_satisfied = bool(checks)
            for group, entries in checks.items():
                if not isinstance(entries, list) or not entries:
                    checks_satisfied = False
                    break
                for index, item in enumerate(entries):
                    check_path = f"binary_checks.{group}[{index}]"
                    if not (binary_check_satisfied(item, allow_waiver=allow_waiver) or check_path in approved_failures):
                        checks_satisfied = False
                        break
                if not checks_satisfied:
                    break
            if checks_satisfied:
                covered.update(mapping)
    missing = sorted(expected - covered)
    if missing:
        return False, "parent_ac_uncovered:" + ",".join(missing)
    return True, f"parent_contract_ok source={source} ac={len(expected)}"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("cmd_id")
    p.add_argument("--root", default=os.environ.get("PROJECT_ROOT", Path(__file__).resolve().parents[2]))
    args = p.parse_args()
    ok, detail = validate(Path(args.root), args.cmd_id)
    print(("OK: " if ok else "BLOCK: ") + detail)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
