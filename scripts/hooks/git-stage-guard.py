#!/usr/bin/env python3
"""Block GA-408 mixed task-YAML stages before ``git add`` mutates the index.

The pre-commit hook catches this combination only after it is already staged
and records a hook failure.  This helper simulates each real ``git add`` in a
temporary index, then rejects the command when its resulting index would mix
``queue/tasks/*.yaml`` with implementation/context/test files.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile


SEPARATORS = {";", "&&", "||", "|", "&"}


def command_segments(command: str) -> list[list[str]]:
    """Return executable shell segments without matching quoted prose."""
    try:
        decoded = json.loads(f'"{command}"')
    except json.JSONDecodeError:
        decoded = command
    try:
        lexer = shlex.shlex(decoded, posix=True, punctuation_chars="|&;")
        lexer.whitespace_split = True
        tokens = list(lexer)
    except ValueError:
        return []

    segments: list[list[str]] = []
    current: list[str] = []
    for token in tokens:
        if token in SEPARATORS:
            if current:
                segments.append(current)
                current = []
            continue
        current.append(token)
    if current:
        segments.append(current)
    return segments


def add_arguments(segment: list[str]) -> list[str] | None:
    """Extract arguments for a direct git add command, if this is one."""
    index = 0
    while index < len(segment) and "=" in segment[index] and not segment[index].startswith("-"):
        name = segment[index].split("=", 1)[0]
        if not name.isidentifier():
            break
        index += 1
    if index >= len(segment) or Path(segment[index]).name != "git":
        return None
    for index in range(index + 1, len(segment)):
        if segment[index] == "add":
            return segment[index + 1 :]
        if not segment[index].startswith("-"):
            return None
    return None


def run_git(repo: str, args: list[str], *, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", repo, *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        env=env,
    )


def resolve_repo(script_root: Path) -> str:
    # The override is accepted only under Bats.  It makes dispatcher tests use
    # a disposable repository without introducing a production bypass.
    override = os.environ.get("GA228_STAGE_GUARD_REPO") if os.environ.get("BATS_TEST_FILENAME") else None
    base = override or str(script_root)
    result = run_git(base, ["rev-parse", "--show-toplevel"])
    if result.returncode:
        raise RuntimeError("not inside a git repository")
    return result.stdout.strip()


def is_task_yaml(path: str) -> bool:
    return path.startswith("queue/tasks/") and path.endswith(".yaml")


def is_operational_yaml(path: str) -> bool:
    return (path.startswith("queue/") or path.startswith("logs/")) and path.endswith(".yaml")


def simulated_staged_files(repo: str, add_commands: list[list[str]]) -> list[str]:
    index_path = run_git(repo, ["rev-parse", "--git-path", "index"])
    if index_path.returncode:
        raise RuntimeError(index_path.stderr.strip() or "cannot locate git index")
    source_index = Path(index_path.stdout.strip())
    if not source_index.is_absolute():
        source_index = Path(repo) / source_index

    fd, temporary_index = tempfile.mkstemp(prefix="ga228-index-", dir=str(source_index.parent))
    os.close(fd)
    try:
        if source_index.exists():
            shutil.copy2(source_index, temporary_index)
        env = os.environ.copy()
        env["GIT_INDEX_FILE"] = temporary_index
        for add_args in add_commands:
            added = run_git(repo, ["add", *add_args], env=env)
            if added.returncode:
                # Let Git itself report invalid pathspecs; this guard must not
                # turn them into a false mixed-stage diagnosis.
                return []
        staged = run_git(repo, ["diff", "--cached", "--name-only", "--diff-filter=ACMR"], env=env)
        if staged.returncode:
            raise RuntimeError(staged.stderr.strip() or "cannot inspect temporary index")
        return [line for line in staged.stdout.splitlines() if line]
    finally:
        for suffix in ("", ".lock"):
            try:
                Path(temporary_index + suffix).unlink()
            except FileNotFoundError:
                pass


def main() -> int:
    if len(sys.argv) != 2:
        return 0
    script_root = Path(__file__).resolve().parents[2]
    try:
        repo = resolve_repo(script_root)
    except RuntimeError:
        return 0

    add_commands = [args for segment in command_segments(sys.argv[1]) if (args := add_arguments(segment)) is not None]
    if not add_commands:
        return 0
    try:
        staged = simulated_staged_files(repo, add_commands)
    except RuntimeError as exc:
        print(f"BLOCK(GA-228): cannot safely inspect the prospective stage: {exc}", file=sys.stderr)
        return 1
    violations = [path for path in staged if not is_task_yaml(path) and not is_operational_yaml(path)]
    if any(is_task_yaml(path) for path in staged) and violations:
        print("BLOCK(GA-228): git add would mix queue/tasks/*.yaml with non-operational files.", file=sys.stderr)
        print("Stage task/status YAML separately from scripts, context, docs, and tests.", file=sys.stderr)
        for path in violations:
            print(f"  {path}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
