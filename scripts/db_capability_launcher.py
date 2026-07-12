#!/usr/bin/env python3
"""Fail-closed launcher for registered DB capabilities.

Credentials are read from a protected env file and passed only through the child
environment.  They never appear in argv or shell history.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "config/db_capabilities.json"
NONCE_DIR = ROOT / ".runtime/db-capability-nonces"


def _tracked(path: Path) -> bool:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", str(path.relative_to(ROOT))],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def _matches_head(path: Path) -> bool:
    """Reject both staged and unstaged alteration against the committed blob."""
    rel = str(path.relative_to(ROOT))
    result = subprocess.run(
        ["git", "-C", str(ROOT), "show", f"HEAD:{rel}"], capture_output=True
    )
    return result.returncode == 0 and result.stdout == path.read_bytes()


def _load_env(path: Path, required_keys: set[str]) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError("invalid credential env line")
        key, value = line.split("=", 1)
        if not key.isidentifier():
            raise ValueError("invalid credential env key")
        values[key] = value.strip().strip("'\"")
    if set(values) != required_keys:
        raise ValueError("credential env keys must exactly match registry required_credential_keys")
    return values


def _project_root(project_id: str) -> Path:
    try:
        import yaml
        data = yaml.safe_load((ROOT / "config/projects.yaml").read_text(encoding="utf-8")) or {}
    except Exception as exc:
        raise SystemExit(f"BLOCK: cannot load project SSOT: {exc}")
    for project in data.get("projects", []):
        if project.get("id") == project_id and project.get("path"):
            return Path(project["path"]).resolve()
    raise SystemExit("BLOCK: registry project is unknown")


def _repo_tracked_unchanged(repo: Path, path: Path) -> bool:
    try:
        rel = str(path.relative_to(repo))
    except ValueError:
        return False
    blob = subprocess.run(["git", "-C", str(repo), "show", f"HEAD:{rel}"], capture_output=True)
    return path.is_file() and blob.returncode == 0 and blob.stdout == path.read_bytes()


def _validate_child_args(contract: dict, raw_args: list[str]) -> list[str]:
    args = raw_args[1:] if raw_args[:1] == ["--"] else raw_args
    actions = contract.get("actions")
    if not actions:
        if args:
            raise SystemExit("BLOCK: capability does not accept child arguments")
        return args
    if not args or args[0] not in actions:
        raise SystemExit("BLOCK: action is not permitted")
    allowed_flags = set(contract.get("allowed_child_flags", []))
    index = 1
    while index < len(args):
        flag = args[index]
        if flag not in allowed_flags or index + 1 >= len(args) or args[index + 1].startswith("--"):
            raise SystemExit("BLOCK: child flag is not permitted or lacks a value")
        index += 2
    return args


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--capability", required=True)
    parser.add_argument("--mode", required=True)
    parser.add_argument("--confirm", required=True)
    parser.add_argument("--nonce", required=True)
    parser.add_argument("--credential-file", required=True)
    parser.add_argument("--expected-commit")
    parser.add_argument("--execution-root")
    parser.add_argument("tool_args", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    if not _tracked(REGISTRY) or not _matches_head(REGISTRY):
        raise SystemExit("BLOCK: capability registry is untracked or altered")
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    contract = registry.get("capabilities", {}).get(args.capability)
    if not isinstance(contract, dict):
        raise SystemExit("BLOCK: unknown capability")
    tool = (ROOT / contract["tool"]).resolve()
    if ROOT not in tool.parents or not tool.is_file() or not _tracked(tool) or not _matches_head(tool):
        raise SystemExit("BLOCK: capability tool is absent, outside root, untracked, or altered")
    if args.mode not in contract.get("modes", []):
        raise SystemExit("BLOCK: mode is not permitted")
    if args.confirm != contract.get("confirm"):
        raise SystemExit("BLOCK: confirmation mismatch")
    child_args = _validate_child_args(contract, args.tool_args)
    target_root = ROOT
    dependency = contract.get("dependency_tool")
    if dependency:
        project_root = _project_root(contract.get("project", ""))
        target_root = Path(args.execution_root).resolve() if args.execution_root else project_root
        if args.execution_root:
            common = subprocess.run(
                ["git", "-C", str(project_root), "worktree", "list", "--porcelain"],
                capture_output=True, text=True,
            ).stdout
            declared = {Path(line[9:]).resolve() for line in common.splitlines() if line.startswith("worktree ")}
            if target_root not in declared:
                raise SystemExit("BLOCK: execution root is not a registered project worktree")
        dependency_path = (target_root / dependency).resolve()
        if not _repo_tracked_unchanged(target_root, dependency_path):
            raise SystemExit("BLOCK: dependency tool is absent, untracked, or altered")
    head = subprocess.check_output(["git", "-C", str(target_root), "rev-parse", "HEAD"], text=True).strip()
    if contract.get("requires_expected_commit") and args.expected_commit != head:
        raise SystemExit("BLOCK: expected commit mismatch")
    credential_file = Path(args.credential_file).resolve()
    if not credential_file.is_file() or credential_file.stat().st_mode & 0o077:
        raise SystemExit("BLOCK: credential file must exist with mode 0600")
    NONCE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    nonce_key = hashlib.sha256(args.nonce.encode()).hexdigest()
    nonce_path = NONCE_DIR / nonce_key
    try:
        fd = os.open(nonce_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        os.close(fd)
    except FileExistsError:
        raise SystemExit("BLOCK: nonce already used")
    try:
        credentials = _load_env(credential_file, set(contract.get("required_credential_keys", [])))
    except ValueError as exc:
        raise SystemExit(f"BLOCK: {exc}")
    env = {key: os.environ[key] for key in ("PATH", "LANG", "LC_ALL", "TZ") if key in os.environ}
    env.update(credentials)
    env["DB_CAPABILITY"] = args.capability
    env["DB_CAPABILITY_MODE"] = args.mode
    env["DB_CAPABILITY_EXPECTED_COMMIT"] = args.expected_commit or ""
    env["DB_CAPABILITY_PROJECT_ROOT"] = str(target_root)
    if dependency:
        env["DB_CAPABILITY_DEPENDENCY_TOOL"] = str(dependency_path)
    return subprocess.run([sys.executable, str(tool), *child_args], env=env).returncode


if __name__ == "__main__":
    raise SystemExit(main())
