#!/usr/bin/env python3
"""Single-process adapter for the fixed-SHA deploy preflight functions.

No inspection is reimplemented here.  The adapter sources the immutable
``scripts/deploy_task.sh`` once and invokes its existing read-only functions,
preserving their individual return codes for S1 integration.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from dataclasses import dataclass
from pathlib import Path


FUNCTIONS = (
    "deploy_task_destructive_signal_precheck",
    "should_skip_same_cmd_resolve",
)


@dataclass(frozen=True)
class PreflightResult:
    rc: int
    checks: tuple[tuple[str, int], ...]

    def to_dict(self) -> dict[str, object]:
        return {"rc": self.rc, "checks": [list(item) for item in self.checks]}


_HARNESS = r'''
set +e
export DEPLOY_TASK_LIB_ONLY=1
source "$1"
set +e
source_file=$2
active_file=$3
cmd_id=$4
deploy_task_destructive_signal_precheck "$source_file" "$cmd_id" >/dev/null 2>&1
source_rc=$?
should_skip_same_cmd_resolve "$active_file" "$cmd_id" fixture-worker >/dev/null 2>&1
duplicate_rc=$?
printf '%s\t%s\n' "$source_rc" "$duplicate_rc"
'''


def run_preflight(
    deploy_script: str | Path,
    source_path: str | Path,
    active_task_path: str | Path,
    cmd_id: str,
) -> PreflightResult:
    """Return the existing function rc set; overall rc is 0 only when both pass."""
    env = os.environ.copy()
    env["DEPLOY_TASK_LIB_ONLY"] = "1"
    completed = subprocess.run(
        ["bash", "-c", _HARNESS, "preflight-fast", str(deploy_script), str(source_path),
         str(active_task_path), cmd_id],
        check=False,
        capture_output=True,
        text=True,
        env=env,
    )
    if completed.returncode != 0:
        return PreflightResult(completed.returncode or 2, (("harness", completed.returncode or 2),))
    try:
        source_rc, duplicate_rc = (int(value) for value in completed.stdout.strip().split("\t"))
    except (TypeError, ValueError):
        return PreflightResult(2, (("harness", 2),))
    checks = tuple(zip(FUNCTIONS, (source_rc, duplicate_rc)))
    return PreflightResult(0 if source_rc == 0 and duplicate_rc == 0 else 2, checks)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("deploy_script")
    parser.add_argument("source")
    parser.add_argument("active_task")
    parser.add_argument("cmd_id")
    args = parser.parse_args(argv)
    result = run_preflight(args.deploy_script, args.source, args.active_task, args.cmd_id)
    print(json.dumps(result.to_dict(), ensure_ascii=False, sort_keys=True))
    return result.rc


if __name__ == "__main__":
    raise SystemExit(main())

