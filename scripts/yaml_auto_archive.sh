#!/usr/bin/env bash
# yaml_auto_archive.sh — bounded hot YAML lists with text-preserving archives.
#
# Config: config/yaml_auto_archive.tsv
# columns: path<TAB>keep<TAB>top_key<TAB>entry_regex<TAB>archive_path
#
# The implementation is intentionally line/block based. Do not replace this
# with yaml.dump/safe_dump; several operational YAML files contain long free
# text and mixed historical formatting.

set -euo pipefail

# WSL2最適化: $(cd)/$(dirname) subshell(~8ms) → string ops。
_yaa_self="${BASH_SOURCE[0]}"
[[ "$_yaa_self" != /* ]] && _yaa_self="$PWD/$_yaa_self"
ROOT_DIR="${SHOGUN_ROOT:-${_yaa_self%/scripts/yaml_auto_archive.sh}}"
unset _yaa_self
CONFIG_FILE="${YAML_AUTO_ARCHIVE_CONFIG:-$ROOT_DIR/config/yaml_auto_archive.tsv}"
LOCK_FILE="/tmp/shogun_yaml_auto_archive.lock"

[ -f "$CONFIG_FILE" ] || exit 0

# WSL2最適化: flock subshell(~5-15ms) → exec fd。subshell fork排除。
exec 200>"$LOCK_FILE"
flock -w 10 200
python3 - "$ROOT_DIR" "$CONFIG_FILE" <<'PY'
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
config = Path(sys.argv[2])


def resolve(path: str) -> Path:
    p = Path(path)
    return p if p.is_absolute() else root / p


def parse_entries(text: str, entry_pattern: str) -> tuple[list[str], list[list[str]]]:
    lines = text.splitlines(keepends=True)
    entry_re = re.compile(entry_pattern)
    header: list[str] = []
    entries: list[list[str]] = []
    current: list[str] | None = None

    for line in lines:
        if entry_re.match(line):
            if current is not None:
                entries.append(current)
            current = [line]
            continue
        if current is None:
            header.append(line)
            continue
        current.append(line)

    if current is not None:
        entries.append(current)
    return header, entries


def body_for(top_key: str, entries: list[list[str]], include_header: bool) -> str:
    out: list[str] = []
    if include_header and top_key != "-":
        out.append(f"{top_key}:\n")
    for block in entries:
        out.extend(block)
        if block and not block[-1].endswith("\n"):
            out.append("\n")
    return "".join(out)


def archive_one(path: Path, keep: int, top_key: str, entry_pattern: str, archive_path: Path) -> None:
    if not path.exists():
        print(f"SKIP missing {path.relative_to(root) if path.is_relative_to(root) else path}")
        return

    text = path.read_text(encoding="utf-8", errors="ignore")
    _header, entries = parse_entries(text, entry_pattern)
    total = len(entries)
    if total <= keep:
        print(f"OK {path.relative_to(root) if path.is_relative_to(root) else path}: entries={total} keep={keep}")
        return

    archive_entries = entries[:-keep]
    recent_entries = entries[-keep:]

    archive_path.parent.mkdir(parents=True, exist_ok=True)
    archive_exists = archive_path.exists() and archive_path.stat().st_size > 0
    with archive_path.open("a", encoding="utf-8") as fh:
        fh.write(body_for(top_key, archive_entries, include_header=not archive_exists))

    tmp_path = path.with_suffix(path.suffix + f".tmp.{os.getpid()}")
    tmp_path.write_text(body_for(top_key, recent_entries, include_header=True), encoding="utf-8")
    os.replace(tmp_path, path)
    print(
        f"ARCHIVED {path.relative_to(root) if path.is_relative_to(root) else path}: "
        f"{len(archive_entries)} archived, {len(recent_entries)} kept -> "
        f"{archive_path.relative_to(root) if archive_path.is_relative_to(root) else archive_path}"
    )


for raw in config.read_text(encoding="utf-8").splitlines():
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    parts = raw.split("\t")
    if len(parts) != 5:
        raise SystemExit(f"invalid config line (expected 5 tab columns): {raw}")
    rel_path, keep_s, top_key, entry_pattern, rel_archive = parts
    if not keep_s.isdigit() or int(keep_s) < 1:
        raise SystemExit(f"invalid keep value for {rel_path}: {keep_s}")
    archive_one(resolve(rel_path), int(keep_s), top_key, entry_pattern, resolve(rel_archive))
PY
exec 200>&-
