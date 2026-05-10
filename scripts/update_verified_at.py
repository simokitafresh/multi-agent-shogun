#!/usr/bin/env python3
"""Update the first verified_at field in a knowledge-base Markdown file."""

from __future__ import annotations

import re
import sys
from datetime import date
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: update_verified_at.py <markdown_path> <YYYY-MM-DD>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    new_date = sys.argv[2]
    try:
        date.fromisoformat(new_date)
    except ValueError:
        print(f"invalid date: {new_date}", file=sys.stderr)
        return 2

    if not path.is_file():
        print(f"file not found: {path}", file=sys.stderr)
        return 2

    text = path.read_text(encoding="utf-8")
    table_pattern = re.compile(r"(^\|\s*verified_at\s*\|\s*)[^|\n]*?(\s*\|.*$)", re.MULTILINE)
    list_pattern = re.compile(r"(^\s*-\s*verified_at:\s*).*$", re.MULTILINE)

    updated, count = table_pattern.subn(rf"\g<1>{new_date}\g<2>", text, count=1)
    if count == 0:
        updated, count = list_pattern.subn(rf"\g<1>{new_date}", text, count=1)

    if count == 0:
        print(f"verified_at field not found: {path}", file=sys.stderr)
        return 1

    path.write_text(updated, encoding="utf-8")
    print(f"updated verified_at: {path} -> {new_date}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
