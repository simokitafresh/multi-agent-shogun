#!/usr/bin/env bash
# gate_knowledge_freshness.sh
# AI開発知識辞書(systems/*.md + sources/*.md)の verified_at 鮮度を確認する
#
# Exit code:
#   0 = 全件FRESH
#   1 = 1件以上STALE
#   2 = WARNのみ（verified_at未記載/不正など）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ROOT_DIR="${KNOWLEDGE_FRESHNESS_ROOT:-$SCRIPT_DIR}"
TODAY_OVERRIDE="${KNOWLEDGE_FRESHNESS_TODAY:-}"

python3 - "$ROOT_DIR" "$TODAY_OVERRIDE" <<'PY'
from __future__ import annotations

import re
import sys
from datetime import date
from pathlib import Path

root = Path(sys.argv[1])
today_override = sys.argv[2].strip()

try:
    today = date.fromisoformat(today_override) if today_override else date.today()
except ValueError:
    print(f"WARN: KNOWLEDGE_FRESHNESS_TODAY format invalid: {today_override}")
    print("知識鮮度: WARN — fresh=0 stale=0 warn=1 total=0")
    raise SystemExit(2)

targets = sorted((root / "docs/research/systems-knowledge-base/systems").glob("*.md"))
targets += sorted((root / "docs/research/systems-knowledge-base/sources").glob("*.md"))

if not targets:
    print("WARN: systems-knowledge-base targets not found")
    print("知識鮮度: WARN — fresh=0 stale=0 warn=1 total=0")
    raise SystemExit(2)

table_pattern = re.compile(r"^\|\s*verified_at\s*\|\s*([^|]+?)\s*\|")
list_pattern = re.compile(r"^\s*-\s*verified_at:\s*(.+?)\s*$")
date_pattern = re.compile(r"(\d{4}-\d{2}-\d{2})")

fresh_count = 0
stale_count = 0
warn_count = 0

for path in targets:
    rel_path = path.relative_to(root).as_posix()
    raw_value = None
    for line in path.read_text(encoding="utf-8").splitlines():
        match = table_pattern.match(line) or list_pattern.match(line)
        if match:
            raw_value = match.group(1).strip()
            break

    if raw_value is None:
        print(f"WARN: {rel_path} (verified_at missing)")
        warn_count += 1
        continue

    if raw_value.lower() == "unverified":
        print(f"WARN: {rel_path} (verified_at=unverified)")
        warn_count += 1
        continue

    match = date_pattern.search(raw_value)
    if not match:
        print(f"WARN: {rel_path} (verified_at parse failed: {raw_value})")
        warn_count += 1
        continue

    verified_date = date.fromisoformat(match.group(1))
    age_days = (today - verified_date).days

    if age_days > 30:
        print(f"STALE: {rel_path} ({age_days} days old; verified_at={raw_value})")
        stale_count += 1
    elif age_days < 0:
        print(f"WARN: {rel_path} (verified_at in future: {raw_value})")
        warn_count += 1
    else:
        print(f"FRESH: {rel_path} ({age_days} days old; verified_at={raw_value})")
        fresh_count += 1

total = len(targets)

if stale_count:
    print(
        f"知識鮮度: ALERT — fresh={fresh_count} stale={stale_count} "
        f"warn={warn_count} total={total}"
    )
    raise SystemExit(1)

if warn_count:
    print(
        f"知識鮮度: WARN — fresh={fresh_count} stale={stale_count} "
        f"warn={warn_count} total={total}"
    )
    raise SystemExit(2)

print(
    f"知識鮮度: OK — fresh={fresh_count} stale={stale_count} "
    f"warn={warn_count} total={total}"
)
PY
