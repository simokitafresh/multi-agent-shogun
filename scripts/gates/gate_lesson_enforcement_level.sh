#!/usr/bin/env bash
# semantic-links: [[教訓のLevel分布不可視]] [[殿指示_三層学習ループ極限化_20260707]]
# gate_lesson_enforcement_level.sh — 教訓 enforcement_level 分布計測 gate
#
# 目的(cmd_3724): 教訓は全件automated:trueだが、防御階層(growth-loop.md §11 Level1-6)の
# どのLevelに到達しているかの分布が計測されておらず、doc止まり(時間減衰する層)の教訓が
# 見えなかった。全ロールのlessonsのenforcement記述からLevelを判定・集計し、
# 恒久防御(Level4以上)未到達の教訓を昇格候補として可視化する。
#
# 対象:
#   - ロール別 lessons (enforcement fieldあり): lessons_shogun.yaml / lessons_karo.yaml / lessons_gunshi.yaml
#   - PJ別 lessons (忍者教訓, enforcement field無し): projects/*/lessons.yaml
#     → Level判定不能につき件数のみ報告(計測対象外として明示。昇格候補には含めない)
#
# 判定方式:
#   1) 明示Levelマーカー("Level4" "L5:" 等)をテキストから抽出し最大値を採用
#      lesson ID(L978等)との誤検出を避けるため `L[1-6]` の前後は非英数字境界を要求
#   2) 明示マーカー無し → キーワードヒューリスティック(BLOCK/ガード=L4, 自動注入/自動表示=L5, weak_points=L6等)
#   3) 何もヒットしない → Level1(事後検出)を保守的デフォルトとする
#
# Usage: bash scripts/gates/gate_lesson_enforcement_level.sh
# Env:
#   LESSON_ENFORCEMENT_ROOT — リポジトリroot上書き(テスト用)
# Exit: 常に0(情報提供gate。BLOCK/ALERT判定はしない — 可視化がAC2のスコープ)
# Output markers (gate_shogun_startup.sh向け):
#   ##ENFORCEMENT_LEVEL_BELOW4_COUNT##\n<件数>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT_DIR="${LESSON_ENFORCEMENT_ROOT:-$SCRIPT_DIR}"

ROLE_FILES=(
    "$ROOT_DIR/projects/infra/lessons_shogun.yaml"
    "$ROOT_DIR/projects/infra/lessons_karo.yaml"
    "$ROOT_DIR/projects/infra/lessons_gunshi.yaml"
)

PJ_FILES=()
shopt -s nullglob
for f in "$ROOT_DIR"/projects/*/lessons.yaml; do
    PJ_FILES+=("$f")
done
shopt -u nullglob

python3 - "${#ROLE_FILES[@]}" "${ROLE_FILES[@]}" "${#PJ_FILES[@]}" "${PJ_FILES[@]}" <<'PY'
import re
import sys

import yaml

argv = sys.argv[1:]
n_role = int(argv[0])
role_files = argv[1:1 + n_role]
n_pj = int(argv[1 + n_role])
pj_files = argv[2 + n_role: 2 + n_role + n_pj]

LEVEL_NAMES = {
    1: "事後検出",
    2: "事前予防(doc)",
    3: "事前強制(auto-gen)",
    4: "フロー内BLOCK",
    5: "事前コンテキスト提供",
    6: "学習速度最大化",
}

# lesson ID(L978, L1655等)との誤検出を避けるため、L[1-6]の前後に英数字が
# 続かないことを要求する(境界チェック)。"Level4" / "L5:" / "L5)" / "L5貫通" は
# マッチし、"L978" / "L2684" / "L551" のような多桁の行番号・教訓ID参照は除外する。
EXPLICIT_RE = re.compile(
    r'(?:(?<![0-9A-Za-z])L(?P<l1>[1-6])(?![0-9A-Za-z]))'
    r'|(?:Level[ \t]?(?P<l2>[1-6])(?![0-9]))'
)

KEYWORD_RULES = [
    (6, re.compile(r'weak_points|弱点.{0,4}注入|学習速度|次回配備時に自動注入')),
    (5, re.compile(r'自動表示|自動提案|自動生成して渡す|自動注入|強制表示|コピーするだけ')),
    (4, re.compile(r'BLOCK|ガード|[Gg]uard|即停止')),
    (3, re.compile(r'テンプレート自動生成|auto-gen|自動生成')),
    (2, re.compile(r'記載のみ|ドキュメント記載|手順書|必読')),
]


def explicit_levels(text):
    return [int(m.group('l1') or m.group('l2')) for m in EXPLICIT_RE.finditer(text)]


def classify(text):
    levels = explicit_levels(text)
    if levels:
        return max(levels), 'explicit'
    for lvl, pat in KEYWORD_RULES:
        if pat.search(text):
            return lvl, 'keyword'
    return 1, 'default'


def load_lessons(path):
    try:
        with open(path, encoding='utf-8') as fh:
            data = yaml.safe_load(fh)
    except Exception as exc:
        print(f"  WARN: {path} 読込失敗: {exc}")
        return []
    if not isinstance(data, dict):
        return []
    lessons = data.get('lessons', [])
    return lessons if isinstance(lessons, list) else []


print(f"=== 教訓 enforcement_level 分布計測 {__import__('datetime').datetime.now().isoformat(timespec='seconds')} ===")
print("")
print("[ロール別: enforcement記載あり]")

role_total = 0
role_level_hist = {n: 0 for n in range(1, 7)}
candidates = []  # (file_basename, id, level, title)

for path in role_files:
    import os
    basename = os.path.basename(path)
    lessons = load_lessons(path)
    file_hist = {n: 0 for n in range(1, 7)}
    measured = 0
    for entry in lessons:
        if not isinstance(entry, dict):
            continue
        enforcement = entry.get('enforcement')
        if not enforcement or not isinstance(enforcement, str):
            continue
        measured += 1
        level, source = classify(enforcement)
        file_hist[level] += 1
        role_level_hist[level] += 1
        if level < 4:
            candidates.append((basename, entry.get('id', '?'), level, entry.get('title', '')))
    role_total += measured
    below4 = sum(file_hist[n] for n in range(1, 4))
    pct = (100.0 * below4 / measured) if measured else 0.0
    hist_str = ' '.join(f"L{n}:{file_hist[n]}" for n in range(1, 7))
    print(f"  {basename}: enforcement記載{measured}件 / {hist_str} / L4未満:{below4}件({pct:.1f}%)")

print("")
print("[PJ別: enforcement field無し(忍者教訓。Level判定不能=計測対象外)]")
pj_total = 0
for path in pj_files:
    import os
    basename = os.path.basename(os.path.dirname(path))
    lessons = load_lessons(path)
    total = len(lessons)
    with_enf = sum(1 for e in lessons if isinstance(e, dict) and e.get('enforcement'))
    pj_total += total
    if with_enf:
        print(f"  {basename}: {total}件 (enforcement記載あり{with_enf}件を検出 — 想定外。要確認)")
    else:
        print(f"  {basename}: {total}件 (enforcement field無し)")

print("")
print("[総合]")
role_below4 = sum(role_level_hist[n] for n in range(1, 4))
role_at4plus = sum(role_level_hist[n] for n in range(4, 7))
pct_at4plus = (100.0 * role_at4plus / role_total) if role_total else 0.0
hist_str = ' '.join(f"L{n}:{role_level_hist[n]}" for n in range(1, 7))
print(f"  ロール別enforcement記載合計: {role_total}件 / {hist_str}")
print(f"  L4以上(恒久防御)到達: {role_at4plus}件({pct_at4plus:.1f}%) / L4未満(昇格候補): {role_below4}件")
print(f"  PJ別(忍者教訓)合計: {pj_total}件(enforcement field無し、Level分布の集計対象外)")

print("")
print(f"=== 昇格候補一覧(L4未満、恒久防御未到達) {len(candidates)}件 ===")
for basename, lesson_id, level, title in candidates:
    print(f"  - [{basename}] {lesson_id} (L{level}:{LEVEL_NAMES[level]}): {title}")

print("")
print("##ENFORCEMENT_LEVEL_BELOW4_COUNT##")
print(len(candidates))
PY
exit 0
