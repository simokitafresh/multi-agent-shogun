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
    local targets=()
    shopt -s nullglob
    targets+=("$ROOT_DIR"/docs/research/systems-knowledge-base/systems/*.md)
    targets+=("$ROOT_DIR"/docs/research/systems-knowledge-base/sources/*.md)
    shopt -u nullglob

    if [[ "${#targets[@]}" -eq 0 ]]; then
        printf '%s\n' "WARN: systems-knowledge-base targets not found"
        printf '%s\n' "知識鮮度: WARN — fresh=0 stale=0 warn=1 total=0"
        return 2
    fi

    local today total
    if [[ -n "$TODAY_OVERRIDE" ]]; then
        if [[ ! "$TODAY_OVERRIDE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            printf 'WARN: KNOWLEDGE_FRESHNESS_TODAY format invalid: %s\n' "$TODAY_OVERRIDE"
            printf '%s\n' "知識鮮度: WARN — fresh=0 stale=0 warn=1 total=0"
            return 2
        fi
        today="$TODAY_OVERRIDE"
    else
        today="$(date +%F)"
    fi
    total="${#targets[@]}"

    python3 - "$ROOT_DIR" "$today" "$total" "${targets[@]}" <<'PY'
import sys

root = sys.argv[1]
today = sys.argv[2]
total = int(sys.argv[3])
targets = sys.argv[4:]
prefix = root.rstrip("/") + "/"

def trim(value):
    return value.strip()

def days_from_civil(iso):
    y = int(iso[0:4])
    m = int(iso[5:7])
    d = int(iso[8:10])
    y -= m <= 2
    era = (y if y >= 0 else y - 399) // 400
    yoe = y - era * 400
    doy = (153 * (m + (-3 if m > 2 else 9)) + 2) // 5 + d - 1
    doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468

def shell_quote(value):
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-/.,:"
    if value and all(ch in allowed for ch in value):
        return value
    return "'" + value.replace("'", "'\"'\"'") + "'"

today_days = days_from_civil(today)
fresh_count = stale_count = warn_count = 0
stale_entries = []

for path in targets:
    rel_path = path[len(prefix):] if path.startswith(prefix) else path
    raw_value = None
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            stripped = line.strip()
            if stripped.startswith("|"):
                cells = stripped.strip("|").split("|", 2)
                if len(cells) >= 2 and trim(cells[0]) == "verified_at":
                    raw_value = trim(cells[1])
                    break
            elif stripped.startswith("-"):
                item = stripped[1:].lstrip()
                if item.startswith("verified_at:"):
                    raw_value = trim(item.split(":", 1)[1])
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

    verified_iso = ""
    limit = len(raw_value) - 9
    for idx in range(limit if limit > 0 else 0):
        candidate = raw_value[idx:idx + 10]
        if candidate[4:5] == "-" and candidate[7:8] == "-" and candidate[:4].isdigit() and candidate[5:7].isdigit() and candidate[8:].isdigit():
            verified_iso = candidate
            break
    if not verified_iso:
        print(f"WARN: {rel_path} (verified_at parse failed: {raw_value})")
        print(f"  action: {rel_path} の verified_at を YYYY-MM-DD 形式に修正せよ")
        warn_count += 1
        continue

    age_days = today_days - days_from_civil(verified_iso)
    if age_days > 30:
        print(f"STALE: {rel_path} ({age_days} days old; verified_at={raw_value})")
        print(f"  action: {rel_path} を開き verified_at を {today} に更新せよ")
        stale_entries.append((age_days, rel_path, raw_value))
        stale_count += 1
    elif age_days < 0:
        print(f"WARN: {rel_path} (verified_at in future: {raw_value})")
        warn_count += 1
    else:
        print(f"FRESH: {rel_path} ({age_days} days old; verified_at={raw_value})")
        fresh_count += 1

if stale_count:
    print(f"知識鮮度: ALERT — fresh={fresh_count} stale={stale_count} warn={warn_count} total={total}")
    print("■ STALE更新候補 TOP3 (経過日数降順)")
    for idx, (age_days, rel_path, raw_value) in enumerate(sorted(stale_entries, key=lambda item: (-item[0], item[1]))[:3], start=1):
        print(f"  {idx}. {rel_path} ({age_days} days old; verified_at={raw_value})")
        print(f"     command: python3 scripts/update_verified_at.py {shell_quote(rel_path)} {today}")
    print("  action: 上記 STALE ファイルの verified_at を更新し、bash scripts/gates/gate_knowledge_freshness.sh で再確認せよ")
    raise SystemExit(1)

if warn_count:
    print(f"知識鮮度: WARN — fresh={fresh_count} stale={stale_count} warn={warn_count} total={total}")
    print("  action: 上記 WARN ファイルの verified_at フィールドを追記/修正し、bash scripts/gates/gate_knowledge_freshness.sh で再確認せよ")
    raise SystemExit(2)

print(f"知識鮮度: OK — fresh={fresh_count} stale={stale_count} warn={warn_count} total={total}")
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
