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
CACHE_TTL="${KNOWLEDGE_FRESHNESS_CACHE_TTL:-2}"

if [[ "${KNOWLEDGE_FRESHNESS_DISABLE_CACHE:-0}" != "1" && "$CACHE_TTL" =~ ^[0-9]+$ && "$CACHE_TTL" -gt 0 ]]; then
    _root_key="${ROOT_DIR//[^A-Za-z0-9._-]/_}"
    _today_key="${TODAY_OVERRIDE:-today}"
    _cache_file="/tmp/gate_knowledge_freshness_${_root_key}_${_today_key}.cache"
    _cache_rc_file="${_cache_file}.rc"
    _now="$(date +%s)"
    if [[ -f "$_cache_file" && -f "$_cache_rc_file" ]]; then
        _cache_mtime="$(stat -c '%Y' "$_cache_file" 2>/dev/null || printf 0)"
        if (( _now - _cache_mtime < CACHE_TTL )); then
            cat "$_cache_file"
            exit "$(cat "$_cache_rc_file")"
        fi
    fi
fi

_tmp_output=""
if [[ -n "${_cache_file:-}" ]]; then
    _tmp_output="${_cache_file}.$$"
fi

run_scan() {
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
        print(f"  action: {rel_path} に verified_at フィールドを追記せよ (例: | verified_at | {today} |)")
        warn_count += 1
        continue

    if raw_value.lower() == "unverified":
        print(f"WARN: {rel_path} (verified_at=unverified)")
        print(f"  action: {rel_path} の verified_at を実際の検証日 (YYYY-MM-DD) に更新せよ")
        warn_count += 1
        continue

    match = date_pattern.search(raw_value)
    if not match:
        print(f"WARN: {rel_path} (verified_at parse failed: {raw_value})")
        print(f"  action: {rel_path} の verified_at を YYYY-MM-DD 形式に修正せよ")
        warn_count += 1
        continue

    verified_date = date.fromisoformat(match.group(1))
    age_days = (today - verified_date).days

    if age_days > 30:
        print(f"STALE: {rel_path} ({age_days} days old; verified_at={raw_value})")
        print(f"  action: {rel_path} を開き verified_at を {today} に更新せよ")
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
    print("  action: 上記 STALE ファイルの verified_at を更新し、bash scripts/gates/gate_knowledge_freshness.sh で再確認せよ")
    raise SystemExit(1)

if warn_count:
    print(
        f"知識鮮度: WARN — fresh={fresh_count} stale={stale_count} "
        f"warn={warn_count} total={total}"
    )
    print("  action: 上記 WARN ファイルの verified_at フィールドを追記/修正し、bash scripts/gates/gate_knowledge_freshness.sh で再確認せよ")
    raise SystemExit(2)

print(
    f"知識鮮度: OK — fresh={fresh_count} stale={stale_count} "
    f"warn={warn_count} total={total}"
)
PY
}

set +e
if [[ -n "$_tmp_output" ]]; then
    run_scan > "$_tmp_output"
else
    run_scan
fi
_rc=$?
set -e

if [[ -n "$_tmp_output" ]]; then
    mv "$_tmp_output" "$_cache_file"
    printf '%s\n' "$_rc" > "$_cache_rc_file"
    cat "$_cache_file"
fi
exit "$_rc"
