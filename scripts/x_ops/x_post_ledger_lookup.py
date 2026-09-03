#!/usr/bin/env python3
"""Read one ledger entry and, when requested, its slot instructions."""

import json
import sys
from pathlib import Path

import yaml


def load(path: str):
    with Path(path).open(encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def main() -> int:
    if len(sys.argv) not in (3, 5):
        print(
            "usage: x_post_ledger_lookup.py <ledger> <key> "
            "[<slot_calendar> <slot>]",
            file=sys.stderr,
        )
        return 2
    ledger_path, key = sys.argv[1:3]
    try:
        ledger = load(ledger_path)
        entry = next(
            (
                item
                for item in ledger.get("entries", [])
                if isinstance(item, dict) and item.get("key") == key
            ),
            None,
        )
    except (OSError, yaml.YAMLError) as exc:
        print(f"x_post_ledger_lookup: failed to load ledger: {exc}", file=sys.stderr)
        return 2
    if entry is None:
        print(f"x_post_ledger_lookup: key not found: {key}", file=sys.stderr)
        return 1

    result = entry
    if len(sys.argv) == 5:
        try:
            calendar = load(sys.argv[3])
        except (OSError, yaml.YAMLError) as exc:
            print(f"x_post_ledger_lookup: failed to load slot calendar: {exc}", file=sys.stderr)
            return 2
        slot = next(
            (
                item
                for item in calendar.get("slots", [])
                if isinstance(item, dict) and str(item.get("slot", "")) == sys.argv[4]
            ),
            None,
        )
        if slot is None:
            print(f"x_post_ledger_lookup: slot not found: {sys.argv[4]}", file=sys.stderr)
            return 1
        slot_key = str(slot.get("ledger_key", "")).strip()
        if slot_key and slot_key != key:
            print(
                f"x_post_ledger_lookup: slot {sys.argv[4]} maps to {slot_key}, not {key}",
                file=sys.stderr,
            )
            return 1
        result = {"entry": entry, "slot": slot}
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
