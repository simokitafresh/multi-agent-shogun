#!/usr/bin/env python3
"""Detect high false-positive cmd_save WARN gates and propose relaxations."""

from __future__ import annotations

import argparse
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import yaml


def _parse_timestamp(value: Any) -> datetime | None:
    if not value:
        return None
    text = str(value).strip().replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _load_entries(path: Path) -> list[dict[str, Any]]:
    with path.open(encoding="utf-8", errors="replace") as f:
        data = yaml.safe_load(f) or {}
    if isinstance(data, dict):
        entries = data.get("entries", [])
    elif isinstance(data, list):
        entries = data
    else:
        entries = []
    return [entry for entry in entries if isinstance(entry, dict)]


def _warn_key(note: str) -> tuple[str, str]:
    parts = [part.strip() for part in note.split("|") if part.strip()]
    warn_type = parts[0] if parts else "unknown"
    check_name = ""
    for part in parts[1:]:
        if part.startswith("check="):
            check_name = part.split("=", 1)[1].strip()
            break
    return warn_type, check_name


def _proposal_for(note: str, fp: int, total: int, pattern_summary: str) -> str:
    warn_type, check_name = _warn_key(note)
    check_text = f" / {check_name}" if check_name else ""
    return (
        f"  提案: {warn_type}{check_text} の条件緩和cmdを起票。"
        f"根拠: 直近FP {fp}/{total}、関連BLOCK={pattern_summary}"
    )


def build_report(
    entries: list[dict[str, Any]],
    *,
    days: int,
    min_count: int,
    threshold: int,
    limit: int,
) -> list[str]:
    if limit > 0:
        entries = entries[-limit:]

    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    entries = [
        entry
        for entry in entries
        if (_parse_timestamp(entry.get("timestamp")) or datetime.min.replace(tzinfo=timezone.utc)) >= cutoff
    ]

    warn_by_cmd: dict[str, set[str]] = defaultdict(set)
    cleared_cmds: set[str] = set()
    cmd_save_runs: dict[str, int] = defaultdict(int)
    block_patterns: dict[str, int] = defaultdict(int)
    block_notes_by_cmd: dict[str, list[str]] = defaultdict(list)

    for entry in entries:
        cmd_id = str(entry.get("cmd_id") or "").strip()
        source = str(entry.get("source") or "").strip()
        gate_result = str(entry.get("gate_result") or "").strip()
        note = str(entry.get("notes") or "unknown").strip() or "unknown"
        if not cmd_id:
            continue
        if source == "cmd_save_warn" and gate_result == "WARN":
            warn_by_cmd[cmd_id].add(note)
        if source == "cmd_complete_gate" and gate_result == "CLEAR":
            cleared_cmds.add(cmd_id)
        if source in {"cmd_save_warn", "cmd_save_block", "cmd_save"}:
            cmd_save_runs[cmd_id] += 1
        if gate_result == "BLOCK":
            block_notes_by_cmd[cmd_id].append(note)
            if "|check=" in note:
                note = note.split("|check=", 1)[0].strip()
            if "WARN累計昇格" in note:
                note = "WARN累計昇格"
            block_patterns[note] += 1

    if not warn_by_cmd:
        return ["  WARN記録なし"]

    warn_type_total: dict[str, int] = defaultdict(int)
    warn_type_fp: dict[str, int] = defaultdict(int)
    for cmd_id, notes_set in warn_by_cmd.items():
        for note in notes_set:
            warn_type_total[note] += 1
            warn_type, check_name = _warn_key(note)
            escalated_to_block = any(
                "WARN累計昇格" in block_note
                and (note in block_note or warn_type in block_note or (check_name and check_name in block_note))
                for block_note in block_notes_by_cmd.get(cmd_id, [])
            )
            if escalated_to_block or (cmd_id in cleared_cmds and cmd_save_runs.get(cmd_id, 0) <= 1):
                warn_type_fp[note] += 1

    pattern_summary = "直近BLOCKなし"
    if block_patterns:
        pattern_summary = ", ".join(
            f"{name}:{count}件"
            for name, count in sorted(block_patterns.items(), key=lambda item: (-item[1], item[0]))[:3]
        )

    lines: list[str] = []
    high_fp: list[tuple[str, int, int, int]] = []
    for note, total in sorted(warn_type_total.items(), key=lambda item: (-item[1], item[0])):
        fp = warn_type_fp.get(note, 0)
        rate = fp * 100 // total if total else 0
        if total >= min_count and rate >= threshold:
            high_fp.append((note, total, fp, rate))
            lines.append(f'  ALERT: "{note}" FP率={rate}% ({fp}/{total}) → gate精度劣化。修正候補あり')
            lines.append(_proposal_for(note, fp, total, pattern_summary))
        elif total >= min_count:
            lines.append(f'  OK: "{note}" FP率={rate}% ({fp}/{total})')

    if not lines:
        lines.append("  高FP率のWARN typeなし")

    for note, total, fp, rate in high_fp:
        alert = f'ALERT: "{note}" FP率={rate}% ({fp}/{total}) → gate精度劣化。修正候補あり'
        proposal = _proposal_for(note, fp, total, pattern_summary).strip()
        lines.append(f"__FP_RELAXATION_REQUEST__\t{alert}\t{pattern_summary}\t{proposal}")

    return lines


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("cmd_design_quality")
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--limit", type=int, default=5000)
    parser.add_argument("--min-count", type=int, default=3)
    parser.add_argument("--threshold", type=int, default=60)
    args = parser.parse_args()

    path = Path(args.cmd_design_quality)
    if not path.is_file():
        print("  cmd_design_quality.yaml不在")
        return 0

    for line in build_report(
        _load_entries(path),
        days=args.days,
        limit=args.limit,
        min_count=args.min_count,
        threshold=args.threshold,
    ):
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
