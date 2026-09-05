#!/usr/bin/env python3
"""recon-dual independence contract for cmd blocks (cmd_save entrance).

Why this exists (2026-09-06 00:41, cmd_4480): the independence contract of a
2-track recon ("独立2系統 / 相互参照禁止 / 固定base / embargo") lived only in
skills/recon-dual/SKILL.md as a prose keyword check that Karo performed by hand
at deploy time.  The Shogun wrote a 2-track cmd without those words, Karo had to
stop deployment and ask for an edit, and the round trip cost one ninja slot.
The contract now lives in the cmd YAML as a structured `recon_dual:` mapping
and is validated fail-closed at save time, so neither side has to remember it.

Rules (pure, no I/O besides reading the given cmd block file):
  * A cmd is "dual recon" when `parallel_ok` names >= 2 acceptance criteria
    AND the cmd is a recon (title/purpose contains 偵察/recon/調査, or
    task_type recon).  Implementation cmds with parallel_ok are not affected.
  * A dual recon cmd MUST carry `recon_dual:` with exactly these values:
        mode: independent
        cross_reference: forbidden
        base: fixed_origin_main
        shared_context_embargo: karo_release_required
    Legacy prose (any of 独立2系統 / 相互参照禁止 / independent recon in
    title/purpose/command) is accepted as WARN-level compatibility so that
    already-delegated cmds keep working, but the structured mapping is the
    contract.
  * Output: "PASS(recon_dual=...)" on stdout, exit 0; "WARN: ..." exit 0;
    "BLOCK: ..." on stdout, exit 1.  The caller decides how to record it.
"""
from __future__ import annotations

import re
import sys

import yaml

REQUIRED = {
    "mode": "independent",
    "cross_reference": "forbidden",
    "base": "fixed_origin_main",
    "shared_context_embargo": "karo_release_required",
}
LEGACY_KEYWORDS = ("独立2系統", "独立 2 系統", "相互参照禁止", "independent recon")
RECON_MARKERS = ("偵察", "recon", "調査")


def load_cmd(path: str) -> dict:
    with open(path, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh) or {}
    if isinstance(doc, dict) and len(doc) == 1 and isinstance(next(iter(doc.values())), dict):
        return next(iter(doc.values()))
    return doc if isinstance(doc, dict) else {}


def is_dual_recon(cmd: dict) -> bool:
    parallel = cmd.get("parallel_ok")
    if not isinstance(parallel, list) or len([p for p in parallel if str(p).strip()]) < 2:
        return False
    text = " ".join(str(cmd.get(k) or "") for k in ("title", "purpose", "task_type")).lower()
    return any(m in text for m in RECON_MARKERS)


def legacy_prose_present(cmd: dict) -> bool:
    text = " ".join(str(cmd.get(k) or "") for k in ("title", "purpose", "command"))
    return any(k in text for k in LEGACY_KEYWORDS)


def evaluate(cmd: dict) -> tuple[str, str]:
    """Return (level, message). level in {PASS, WARN, BLOCK}."""
    if not is_dual_recon(cmd):
        return "PASS", "not_required"
    rd = cmd.get("recon_dual")
    if isinstance(rd, dict):
        bad = [k for k, v in REQUIRED.items() if str(rd.get(k, "")).strip() != v]
        if not bad:
            return "PASS", "structured"
        return "BLOCK", (
            "recon_dual mapping incomplete: "
            + ", ".join(f"{k} must be '{REQUIRED[k]}' (got '{rd.get(k, '')}')" for k in bad)
        )
    if legacy_prose_present(cmd):
        return "WARN", "legacy prose contract only; add structured recon_dual mapping"
    return "BLOCK", (
        "dual-track recon (parallel_ok>=2) requires recon_dual: {mode: independent, "
        "cross_reference: forbidden, base: fixed_origin_main, shared_context_embargo: karo_release_required}"
    )


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: recon_dual_contract.py <cmd_block.yaml>")
        return 2
    level, msg = evaluate(load_cmd(argv[1]))
    if level == "PASS":
        print(f"PASS(recon_dual={msg})")
        return 0
    if level == "WARN":
        print(f"WARN: recon_dual {msg}")
        return 0
    print(f"BLOCK: {msg}")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
