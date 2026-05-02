#!/usr/bin/env bash
# ============================================================
# gate_skill_quality.sh
# スキル品質ゲート — プロジェクト内 skills/*/SKILL.md を全走査
#
# Usage:
#   bash scripts/gates/gate_skill_quality.sh
#
# チェック項目:
#   (1) description 1024文字以内
#   (2) What+When+NOT When の3要素検出（キーワードベース）
#   (3) SKILL.md 5000語以内
#   (4) フロントマターに < > なし
#   (5) allowed-tools の存在確認
#
# Exit code: 0=全OK, 1=1つ以上FAIL, 2=WARNのみ(FAILなし)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILLS_DIR="${SKILLS_DIR:-$SCRIPT_DIR/skills}"

SKILLS_DIR_ENV="$SKILLS_DIR" python3 - <<'PYEOF'
import os
import re
import sys

skills_dir = os.environ["SKILLS_DIR_ENV"]

what_re = re.compile(r"(What|何をする|スキル|する。)", re.IGNORECASE)
when_re = re.compile(r"(When|TRIGGER|いつ使う|時に使用|時に実行|で使う)", re.IGNORECASE)
not_when_re = re.compile(r"(NOT When|NOT TRIGGER|DO NOT TRIGGER|使用禁止|使わない|発火しない|ではない)", re.IGNORECASE)
top_key_re = re.compile(r"^[A-Za-z_-]+:")


def extract_frontmatter(text: str) -> str:
    lines = text.replace("\r", "").splitlines()
    if not lines or lines[0] != "---":
        return ""
    try:
        end = lines.index("---", 1)
    except ValueError:
        return ""
    return "\n".join(lines[1:end])


def strip_quotes(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def extract_description(frontmatter: str) -> str:
    if not frontmatter:
        return ""

    lines = frontmatter.splitlines()
    for idx, line in enumerate(lines):
        if not line.startswith("description:"):
            continue

        tail = line.split(":", 1)[1].strip()
        if tail in {"|", ">"}:
            chunks = []
            for follow in lines[idx + 1:]:
                if top_key_re.match(follow):
                    break
                if follow[:1].isspace():
                    chunks.append(follow.lstrip())
                    continue
                break
            return "\n".join(chunks).strip()
        return strip_quotes(tail)
    return ""


has_fail = False
has_warn = False
total = 0
passed = 0

entries = []
if os.path.isdir(skills_dir):
    for entry in sorted(os.scandir(skills_dir), key=lambda item: item.name):
        if not entry.is_dir():
            continue
        skill_file = os.path.join(entry.path, "SKILL.md")
        if os.path.isfile(skill_file):
            entries.append((entry.name, skill_file))

for skill_name, skill_file in entries:
    total += 1
    skill_ok = True

    with open(skill_file, "r", encoding="utf-8") as fh:
        text = fh.read().replace("\r", "")

    frontmatter = extract_frontmatter(text)
    desc = extract_description(frontmatter)
    print(f"=== {skill_name} ===")

    if not desc:
        print("  FAIL: (1) description が見つかりません")
        has_fail = True
        skill_ok = False
    else:
        char_count = len(desc)
        if char_count > 1024:
            print(f"  FAIL: (1) description {char_count}文字(>1024)")
            has_fail = True
            skill_ok = False
        else:
            print(f"  OK: (1) description {char_count}文字")

    has_what = bool(what_re.search(desc))
    has_when = bool(when_re.search(desc))
    has_not_when = bool(not_when_re.search(desc))
    found_count = int(has_what) + int(has_when) + int(has_not_when)
    if found_count == 3:
        print("  OK: (2) What+When+NOT When 3/3検出")
    else:
        missing = []
        if not has_what:
            missing.append("What")
        if not has_when:
            missing.append("When")
        if not has_not_when:
            missing.append("NOT_When")
        missing_text = " ".join(missing) + (" " if missing else "")
        if found_count >= 2:
            print(f"  WARN: (2) {found_count}/3検出(不足: {missing_text})")
            has_warn = True
        else:
            print(f"  FAIL: (2) {found_count}/3検出(不足: {missing_text})")
            has_fail = True
        skill_ok = False

    word_count = len(text.split())
    if word_count > 5000:
        print(f"  FAIL: (3) {word_count}語(>5000)")
        has_fail = True
        skill_ok = False
    elif word_count > 4000:
        print(f"  WARN: (3) {word_count}語(>4000 注意)")
        has_warn = True
    else:
        print(f"  OK: (3) {word_count}語")

    if "<" in frontmatter or ">" in frontmatter:
        print("  FAIL: (4) フロントマターに < > を検出")
        has_fail = True
        skill_ok = False
    else:
        print("  OK: (4) フロントマターに < > なし")

    if "allowed-tools" in frontmatter:
        tool_count = sum(1 for line in frontmatter.splitlines() if re.match(r"^\s*-", line))
        print(f"  OK: (5) allowed-tools あり({tool_count}ツール)")
    else:
        print("  WARN: (5) allowed-tools が未定義")
        has_warn = True
        skill_ok = False

    if skill_ok:
        passed += 1
    print()

print("=== 総合判定 ===")
print(f"走査: {total}スキル, PASS: {passed}/{total}")

if has_fail:
    print("--- 総合判定: FAIL ---")
    sys.exit(1)
if has_warn:
    print("--- 総合判定: WARN ---")
    sys.exit(2)
print("--- 総合判定: OK ---")
PYEOF
