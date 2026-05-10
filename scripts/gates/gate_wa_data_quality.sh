#!/usr/bin/env bash
# gate_wa_data_quality.sh — karo_workarounds.yaml データ品質ゲート
# GP-063: WA計測の汚染検出+自動修復
#
# 検出パターン:
#   1. False WA: workaround=true + detail内にcleanキーワード → clean化
#   2. 重複エントリ: 同一cmd_id+ninja → 後勝ち(cleanがあればclean)
#   3. GP-049バイパス: workaround=true + detail<10文字 → WARN
#   4. ninja名汚染: 既知忍者名以外のninja値 → WARN
#
# Usage:
#   CHECK: bash scripts/gates/gate_wa_data_quality.sh
#   FIX:   bash scripts/gates/gate_wa_data_quality.sh --fix
#
# Exit: 0=CLEAN, 1=ISSUES_FOUND(check) or FIXED(fix mode)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WA_FILE="${WA_FILE:-$REPO_ROOT/logs/karo_workarounds.yaml}"
FIX_MODE=false

if [[ "${1:-}" == "--fix" ]]; then
    FIX_MODE=true
fi

if [[ ! -f "$WA_FILE" ]]; then
    echo "PASS: karo_workarounds.yaml not found"
    exit 0
fi

if [[ "$FIX_MODE" == "false" ]]; then
    awk '
    function trim(s) {
        sub(/^[[:space:]]+/, "", s)
        sub(/[[:space:]]+$/, "", s)
        return s
    }
    function scalar(s) {
        s = trim(s)
        if ((substr(s, 1, 1) == "'"'"'" && substr(s, length(s), 1) == "'"'"'") || (substr(s, 1, 1) == "\"" && substr(s, length(s), 1) == "\"")) {
            s = substr(s, 2, length(s) - 2)
        }
        return s
    }
    function set_field(line,    p, key, value) {
        sub(/^[[:space:]]*-[[:space:]]*/, "", line)
        sub(/^[[:space:]]+/, "", line)
        p = index(line, ":")
        if (!p) {
            return
        }
        key = substr(line, 1, p - 1)
        value = scalar(substr(line, p + 1))
        if (key == "cmd_id") {
            cmd[n] = value
        } else if (key == "ninja") {
            ninja[n] = value
        } else if (key == "workaround") {
            workaround[n] = value
        } else if (key == "category") {
            category[n] = value
        } else if (key == "detail") {
            detail[n] = value
        }
    }
    function add_issue(text) {
        issues[++issue_count] = text
    }
    function add_issue_pattern(pattern, text) {
        pattern_counts[pattern]++
        add_issue(text)
    }
    function fix_command(pattern) {
        if (pattern == "FALSE_WA") {
            return "bash scripts/gates/gate_wa_data_quality.sh --fix  # cleanキーワード含有WAをclean化"
        }
        if (pattern == "DUPLICATE") {
            return "bash scripts/gates/gate_wa_data_quality.sh --fix  # 重複cmd/ninjaをclean優先で整理"
        }
        if (pattern == "GP049_BYPASS") {
            return "bash scripts/karo_workaround_log.sh <cmd_id> <ninja> \"<10文字以上のdetail>\" \"<root_cause>\" <category>"
        }
        if (pattern == "NINJA_CORRUPT") {
            return "bash scripts/karo_workaround_log.sh <cmd_id> <known_ninja> \"<detail>\" \"<root_cause>\" <category>"
        }
        return "bash scripts/gates/gate_wa_data_quality.sh --fix"
    }
    /^[[:space:]]*-[[:space:]]/ {
        n++
        set_field($0)
        next
    }
    n > 0 && /^[[:space:]]+[A-Za-z_][A-Za-z0-9_]*:/ {
        set_field($0)
    }
    END {
        known["hayate"] = known["kagemaru"] = known["hanzo"] = known["saizo"] = 1
        known["kotaro"] = known["tobisaru"] = known["unknown"] = 1

        split("workaround不要|WA不要|修正なし|対処不要|修正不要|正規フロー完了|問題なし", clean_keywords, "|")
        for (i = 1; i <= n; i++) {
            if (workaround[i] == "true" && category[i] != "clean") {
                for (k in clean_keywords) {
                    if (index(detail[i], clean_keywords[k]) > 0) {
                        add_issue_pattern("FALSE_WA", sprintf("FALSE_WA[%d]: %s — detail contains \"%s\" but workaround=true", i - 1, cmd[i], clean_keywords[k]))
                        break
                    }
                }
            }
        }

        for (i = 1; i <= n; i++) {
            key = cmd[i] SUBSEP ninja[i]
            if (!(key in seen)) {
                seen[key] = i
                continue
            }

            prev_i = seen[key]
            prev_wa = workaround[prev_i]
            curr_wa = workaround[i]
            if (curr_wa != "true" && prev_wa == "true") {
                add_issue_pattern("DUPLICATE", sprintf("DUPLICATE[%d,%d]: %s/%s — keeping clean entry [%d]", prev_i - 1, i - 1, cmd[i], ninja[i], i - 1))
                seen[key] = i
            } else if (curr_wa == "true" && prev_wa != "true") {
                add_issue_pattern("DUPLICATE", sprintf("DUPLICATE[%d,%d]: %s/%s — keeping clean entry [%d]", prev_i - 1, i - 1, cmd[i], ninja[i], prev_i - 1))
            } else {
                add_issue_pattern("DUPLICATE", sprintf("DUPLICATE[%d,%d]: %s/%s — keeping latest [%d]", prev_i - 1, i - 1, cmd[i], ninja[i], i - 1))
                seen[key] = i
            }
        }

        for (i = 1; i <= n; i++) {
            if (workaround[i] == "true" && category[i] != "clean" && (detail[i] == "none" || detail[i] == "null" || detail[i] == "" || length(detail[i]) < 10)) {
                add_issue_pattern("GP049_BYPASS", sprintf("GP049_BYPASS[%d]: %s — detail=\"%s\" (too short/placeholder)", i - 1, cmd[i], detail[i]))
            }
        }

        for (i = 1; i <= n; i++) {
            if (ninja[i] != "" && !(ninja[i] in known)) {
                add_issue_pattern("NINJA_CORRUPT", sprintf("NINJA_CORRUPT[%d]: %s — ninja=\"%s\" not in known list", i - 1, cmd[i], ninja[i]))
            }
        }

        if (!issue_count) {
            print "PASS: no data quality issues"
            exit 0
        }
        print "ISSUES: " issue_count
        for (i = 1; i <= issue_count; i++) {
            print "  " issues[i]
        }
        print ""
        print "False WAパターン TOP3:"
        for (rank = 1; rank <= 3; rank++) {
            best = ""
            best_count = 0
            for (pattern in pattern_counts) {
                if (pattern in emitted) {
                    continue
                }
                if (pattern_counts[pattern] > best_count || (pattern_counts[pattern] == best_count && (best == "" || pattern < best))) {
                    best = pattern
                    best_count = pattern_counts[pattern]
                }
            }
            if (best == "") {
                break
            }
            emitted[best] = 1
            printf "  %d. category=%s count=%d\n", rank, best, best_count
            printf "     command: %s\n", fix_command(best)
        }
        print ""
        print "action: bash scripts/gates/gate_wa_data_quality.sh --fix を実行して自動修復せよ"
        exit 1
    }
    ' "$WA_FILE"
    exit $?
fi

python3 - "$WA_FILE" "$FIX_MODE" <<'PY'
from __future__ import annotations

import os
import sys
import tempfile

import yaml

wa_file = sys.argv[1]
fix_mode = sys.argv[2].lower() == "true"

loader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

with open(wa_file, encoding="utf-8") as f:
    data = yaml.load(f, Loader=loader)

if isinstance(data, list):
    entries = data
    is_bare_list = True
elif isinstance(data, dict):
    for key in ("workarounds", "entries"):
        if key in data:
            entries = data[key]
            is_bare_list = False
            target_key = key
            break
    else:
        entries = []
        is_bare_list = True
        target_key = "workarounds"
else:
    entries = []
    is_bare_list = True
    target_key = "workarounds"

if not isinstance(entries, list):
    print("FAIL: entries is not a list")
    sys.exit(1)

issues: list[str] = []
fixes: list[str] = []
pattern_counts: dict[str, int] = {}

def add_issue(pattern: str, message: str) -> None:
    pattern_counts[pattern] = pattern_counts.get(pattern, 0) + 1
    issues.append(message)

def fix_command(pattern: str) -> str:
    if pattern == "FALSE_WA":
        return "bash scripts/gates/gate_wa_data_quality.sh --fix  # cleanキーワード含有WAをclean化"
    if pattern == "DUPLICATE":
        return "bash scripts/gates/gate_wa_data_quality.sh --fix  # 重複cmd/ninjaをclean優先で整理"
    if pattern == "GP049_BYPASS":
        return 'bash scripts/karo_workaround_log.sh <cmd_id> <ninja> "<10文字以上のdetail>" "<root_cause>" <category>'
    if pattern == "NINJA_CORRUPT":
        return 'bash scripts/karo_workaround_log.sh <cmd_id> <known_ninja> "<detail>" "<root_cause>" <category>'
    return "bash scripts/gates/gate_wa_data_quality.sh --fix"

known_ninjas = {"hayate", "kagemaru", "hanzo", "saizo", "kotaro", "tobisaru", "unknown"}
clean_keywords = ["workaround不要", "WA不要", "修正なし", "対処不要", "修正不要", "正規フロー完了", "問題なし"]

for i, entry in enumerate(entries):
    if not isinstance(entry, dict):
        continue
    workaround = entry.get("workaround", False)
    detail = str(entry.get("detail", ""))
    category = entry.get("category", "")
    cmd_id = str(entry.get("cmd_id", ""))
    if workaround and category != "clean":
        for keyword in clean_keywords:
            if keyword in detail:
                add_issue("FALSE_WA", f'FALSE_WA[{i}]: {cmd_id} — detail contains "{keyword}" but workaround=true')
                if fix_mode:
                    entry["workaround"] = False
                    entry["category"] = "clean"
                    fixes.append(f"FIX[{i}]: {cmd_id} → workaround=false, category=clean")
                break

seen: dict[str, int] = {}
dup_indices: list[int] = []
for i, entry in enumerate(entries):
    if not isinstance(entry, dict):
        continue
    cmd_id = str(entry.get("cmd_id", ""))
    ninja = str(entry.get("ninja", ""))
    key = f"{cmd_id}|{ninja}"
    if key not in seen:
        seen[key] = i
        continue

    prev_i = seen[key]
    prev_entry = entries[prev_i]
    prev_wa = prev_entry.get("workaround", False)
    curr_wa = entry.get("workaround", False)

    if not curr_wa and prev_wa:
        add_issue("DUPLICATE", f"DUPLICATE[{prev_i},{i}]: {cmd_id}/{ninja} — keeping clean entry [{i}]")
        dup_indices.append(prev_i)
        seen[key] = i
    elif curr_wa and not prev_wa:
        add_issue("DUPLICATE", f"DUPLICATE[{prev_i},{i}]: {cmd_id}/{ninja} — keeping clean entry [{prev_i}]")
        dup_indices.append(i)
    else:
        add_issue("DUPLICATE", f"DUPLICATE[{prev_i},{i}]: {cmd_id}/{ninja} — keeping latest [{i}]")
        dup_indices.append(prev_i)
        seen[key] = i

if fix_mode and dup_indices:
    for idx in sorted(set(dup_indices), reverse=True):
        removed = entries.pop(idx)
        fixes.append(f"REMOVED[{idx}]: {removed.get('cmd_id', '?')}/{removed.get('ninja', '?')}")

for i, entry in enumerate(entries):
    if not isinstance(entry, dict):
        continue
    workaround = entry.get("workaround", False)
    detail = str(entry.get("detail", ""))
    cmd_id = str(entry.get("cmd_id", ""))
    if workaround and entry.get("category") != "clean":
        if detail in ("none", "null", "") or (0 < len(detail) < 10):
            add_issue("GP049_BYPASS", f'GP049_BYPASS[{i}]: {cmd_id} — detail="{detail}" (too short/placeholder)')

for i, entry in enumerate(entries):
    if not isinstance(entry, dict):
        continue
    ninja = str(entry.get("ninja", ""))
    cmd_id = str(entry.get("cmd_id", ""))
    if ninja and ninja not in known_ninjas:
        add_issue("NINJA_CORRUPT", f'NINJA_CORRUPT[{i}]: {cmd_id} — ninja="{ninja}" not in known list')

if not issues:
    print("PASS: no data quality issues")
    sys.exit(0)

print(f"ISSUES: {len(issues)}")
for issue in issues:
    print(f"  {issue}")

print("\nFalse WAパターン TOP3:")
for rank, (pattern, count) in enumerate(
    sorted(pattern_counts.items(), key=lambda item: (-item[1], item[0]))[:3],
    start=1,
):
    print(f"  {rank}. category={pattern} count={count}")
    print(f"     command: {fix_command(pattern)}")

def yaml_scalar(value: object) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    if (
        not text
        or ":" in text
        or "#" in text
        or text.startswith("{")
        or text.startswith("[")
        or "\n" in text
        or text in ("true", "false", "null", "yes", "no")
    ):
        return "'" + text.replace("'", "''") + "'"
    return text

def write_entry_list(handle, entry_list: list[object], base_indent: str = "") -> None:
    for entry in entry_list:
        if not isinstance(entry, dict):
            continue
        first = True
        for key, value in entry.items():
            prefix = f"{base_indent}- " if first else f"{base_indent}  "
            handle.write(f"{prefix}{key}: {yaml_scalar(value)}\n")
            first = False

if fix_mode and fixes:
    tmp_fd, tmp_path = tempfile.mkstemp(dir=os.path.dirname(wa_file), suffix=".tmp")
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as handle:
            if is_bare_list:
                write_entry_list(handle, entries)
            else:
                for key, value in data.items():
                    if key == target_key:
                        handle.write(f"{key}:\n")
                        write_entry_list(handle, entries, "  ")
                    else:
                        handle.write(f"{key}: {yaml_scalar(value)}\n")
        os.replace(tmp_path, wa_file)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise

    print(f"\nFIXED: {len(fixes)} changes applied")
    for fix in fixes:
        print(f"  {fix}")

if not fix_mode:
    print("\naction: bash scripts/gates/gate_wa_data_quality.sh --fix を実行して自動修復せよ")

sys.exit(1)
PY
