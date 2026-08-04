#!/usr/bin/env python3
"""Fail-closed reducer for fixed-HEAD sharded test checkpoint receipts."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable

try:
    import yaml
except ImportError:  # pragma: no cover
    yaml = None


HEAD_RE = re.compile(r"^[0-9a-f]{40}$")


class CheckpointBlock(ValueError):
    """A current-head receipt cannot safely contribute reusable results."""


def _read_structured(path: str | Path) -> dict[str, Any]:
    source = Path(path)
    try:
        text = source.read_text(encoding="utf-8")
        value = yaml.safe_load(text) if source.suffix.lower() in {".yaml", ".yml"} else json.loads(text)
    except (OSError, ValueError, TypeError) as exc:
        raise CheckpointBlock(f"invalid structured input {source}: {exc}") from exc
    if not isinstance(value, dict):
        raise CheckpointBlock(f"structured input must be a mapping: {source}")
    return value


def _first(mapping: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in mapping:
            return mapping[key]
    return None


def _as_paths(value: Any, *, label: str) -> list[str]:
    if not isinstance(value, list) or not all(isinstance(item, str) and item for item in value):
        raise CheckpointBlock(f"{label} must be a non-empty string list")
    paths = list(value)
    if len(paths) != len(set(paths)):
        raise CheckpointBlock(f"{label} contains duplicate paths")
    return paths


def _manifest_identity(manifest: dict[str, Any]) -> tuple[str, list[str]]:
    source_head = _first(manifest, "source_head", "fixed_head", "head")
    paths = _as_paths(_first(manifest, "test_paths", "expected_paths", "files"), label="manifest test_paths")
    if not isinstance(source_head, str) or not HEAD_RE.fullmatch(source_head):
        raise CheckpointBlock("manifest source_head must be a 40-character lowercase commit hash")
    return source_head, paths


def _artifact_matches(receipt: dict[str, Any]) -> None:
    artifact = receipt.get("artifact")
    expected = receipt.get("output_sha256")
    if not isinstance(artifact, str) or not artifact or not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise CheckpointBlock("receipt artifact or output_sha256 is missing or malformed")
    try:
        actual = hashlib.sha256(Path(artifact).read_bytes()).hexdigest()
    except OSError as exc:
        raise CheckpointBlock(f"receipt artifact is unreadable: {artifact}") from exc
    if actual != expected:
        raise CheckpointBlock(f"receipt artifact hash mismatch: {artifact}")


def _validate_current_receipt(receipt: dict[str, Any], expected_head: str, manifest_paths: set[str]) -> set[str]:
    if receipt.get("source_head") != expected_head:
        raise CheckpointBlock("receipt source_head does not match manifest")
    if receipt.get("complete") is not True:
        raise CheckpointBlock("receipt is not complete")
    if receipt.get("skip_count") != 0:
        raise CheckpointBlock("receipt has skipped tests")
    if receipt.get("result") not in {"PASS", "FAIL"}:
        raise CheckpointBlock("receipt result is not terminal PASS/FAIL")
    _artifact_matches(receipt)
    paths = set(_as_paths(receipt.get("test_paths"), label="receipt test_paths"))
    if not paths <= manifest_paths:
        raise CheckpointBlock("receipt contains paths outside the expected manifest")
    run_manifest = receipt.get("run_manifest")
    if not isinstance(run_manifest, dict) or (run_manifest.get("cache") or {}).get("enabled") is not False:
        raise CheckpointBlock("receipt does not prove BATS_CACHE=0")
    scope = run_manifest.get("scope_identity")
    if not isinstance(scope, dict) or scope.get("complete") is not True:
        raise CheckpointBlock("receipt scope_identity is missing or incomplete")
    if scope.get("selected_file_count") != len(paths):
        raise CheckpointBlock("receipt selected_file_count disagrees with test_paths")
    failed_value = scope.get("failed_files")
    if not isinstance(failed_value, list) or scope.get("failed_file_count") != len(failed_value):
        raise CheckpointBlock("receipt failed_files count is invalid")
    failed = set(_as_paths(failed_value, label="receipt failed_files"))
    if not failed <= paths:
        raise CheckpointBlock("receipt failed_files are outside test_paths")
    if receipt["result"] == "PASS" and failed:
        raise CheckpointBlock("PASS receipt declares failed files")
    if receipt["result"] == "FAIL" and not failed:
        raise CheckpointBlock("FAIL receipt does not identify failed files")
    return paths - failed


def reduce_checkpoint(manifest: dict[str, Any], receipts: Iterable[dict[str, Any]]) -> dict[str, Any]:
    """Return reusable PASS files and the fail/missing retry set."""
    receipts = list(receipts)
    expected_head, expected = _manifest_identity(manifest)
    expected_set = set(expected)
    current = [r for r in receipts if r.get("source_head") == expected_head]
    reused: set[str] = set()
    covered: set[str] = set()
    block_reason = ""
    try:
        for receipt in current:
            receipt_paths = set(_as_paths(receipt.get("test_paths"), label="receipt test_paths"))
            if covered & receipt_paths:
                raise CheckpointBlock(f"duplicate receipt coverage: {sorted(covered & receipt_paths)}")
            reused.update(_validate_current_receipt(receipt, expected_head, expected_set))
            covered.update(receipt_paths)
    except CheckpointBlock as exc:
        block_reason = str(exc)
        reused.clear()
        covered.clear()
    failed = sorted(covered - reused)
    missing = sorted(expected_set - covered)
    retry = sorted(expected_set) if block_reason else sorted(set(failed) | set(missing))
    return {
        "status": "BLOCK" if block_reason else "PASS",
        "source_head": expected_head,
        "expected_files": expected,
        "reused_files": sorted(reused),
        "failed_files": failed,
        "missing_files": missing,
        "retry_files": retry,
        "duplicate": [],
        "stale_receipt_count": sum(1 for r in receipts if r.get("source_head") != expected_head),
        "receipt_count": len(receipts),
        "reason": block_reason,
    }


compute_resume = reduce_checkpoint
resume_plan = reduce_checkpoint


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", help="fixed-HEAD manifest (JSON/YAML)")
    parser.add_argument("receipts", nargs="+", help="terminal run_tests receipt(s) (JSON)")
    args = parser.parse_args(argv)
    try:
        result = reduce_checkpoint(_read_structured(args.manifest), [_read_structured(p) for p in args.receipts])
    except CheckpointBlock as exc:
        result = {"status": "BLOCK", "reason": str(exc)}
    print(json.dumps(result, sort_keys=True))
    return 2 if result.get("status") == "BLOCK" else 0


if __name__ == "__main__":
    raise SystemExit(main())
