#!/usr/bin/env python3
"""Replace one embedded base64 fixture in a consolidated Bats file."""

from __future__ import annotations

import argparse
import base64
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--consolidated", required=True, type=Path)
    parser.add_argument("--function", required=True)
    parser.add_argument("--source", required=True, type=Path)
    return parser.parse_args()


def encode_fixture(path: Path) -> str:
    raw = path.read_bytes()
    return base64.encodebytes(raw).decode("ascii").rstrip("\n")


def replace_fixture(text: str, function_name: str, encoded: str) -> str:
    start_marker = f"{function_name}() {{\n    base64 -d <<'EOF'\n"
    try:
        start = text.index(start_marker) + len(start_marker)
    except ValueError as exc:
        raise SystemExit(f"ERROR: function not found or not a plain base64 fixture: {function_name}") from exc

    end_marker = "\nEOF\n}"
    try:
        end = text.index(end_marker, start)
    except ValueError as exc:
        raise SystemExit(f"ERROR: EOF marker not found for fixture: {function_name}") from exc

    return text[:start] + encoded + text[end:]


def main() -> int:
    args = parse_args()
    text = args.consolidated.read_text()
    encoded = encode_fixture(args.source)
    updated = replace_fixture(text, args.function, encoded)
    args.consolidated.write_text(updated)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
