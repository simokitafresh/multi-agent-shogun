#!/bin/bash
# backfill_lesson_target_files.sh — 既存教訓にtarget_filesを遡及設定
# git履歴からsource_cmdのcommit→変更ファイルを取得し、教訓markdownに**target_files**を追加
# Usage: bash scripts/backfill_lesson_target_files.sh [--dry-run]

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DM_SIGNAL_DIR="/mnt/c/Python_app/DM-signal"
LESSONS_FILE="$DM_SIGNAL_DIR/tasks/lessons.md"
DRY_RUN="${1:-}"

if [ ! -f "$LESSONS_FILE" ]; then
    echo "ERROR: $LESSONS_FILE not found" >&2
    exit 1
fi

export SCRIPT_DIR DM_SIGNAL_DIR LESSONS_FILE DRY_RUN

python3 << 'PYEOF'
import re, subprocess, os, sys

DM_SIGNAL_DIR = os.environ["DM_SIGNAL_DIR"]
SCRIPT_DIR = os.environ["SCRIPT_DIR"]
LESSONS_FILE = os.environ["LESSONS_FILE"]
DRY_RUN = os.environ.get("DRY_RUN", "") == "--dry-run"

with open(LESSONS_FILE, encoding="utf-8") as f:
    lines = f.read().split("\n")

# Phase 1: パースして各教訓のメタデータを収集
lessons = []
current = None

for i, line in enumerate(lines):
    m = re.match(r'^### (L\d+):', line)
    if m:
        if current:
            lessons.append(current)
        current = {"id": m.group(1), "header_idx": i, "source_cmd": None,
                    "has_tf": False, "tags_idx": None}
    elif current:
        m_src = re.match(r'^- \*\*出典\*\*:\s*(cmd_\d+)', line)
        if m_src:
            current["source_cmd"] = m_src.group(1)
        if "**target_files**" in line:
            current["has_tf"] = True
        if "**tags**" in line and current["tags_idx"] is None:
            current["tags_idx"] = i

if current:
    lessons.append(current)

# Phase 2: git履歴からfiles_modified取得 + 挿入位置決定
insertions = []
stats = {"total": len(lessons), "skip_has_tf": 0, "skip_no_cmd": 0,
         "skip_no_tags": 0, "added": 0, "no_git": 0}

for lesson in lessons:
    if lesson["has_tf"]:
        stats["skip_has_tf"] += 1
        continue
    if not lesson["source_cmd"]:
        stats["skip_no_cmd"] += 1
        continue
    if lesson["tags_idx"] is None:
        stats["skip_no_tags"] += 1
        continue

    cmd = lesson["source_cmd"]
    git_files = []

    for repo_dir in [DM_SIGNAL_DIR, SCRIPT_DIR]:
        if not os.path.isdir(os.path.join(repo_dir, ".git")):
            continue
        try:
            result = subprocess.run(
                ["git", "log", f"--grep={cmd}", "--format=", "--name-only"],
                cwd=repo_dir, capture_output=True, text=True, timeout=10
            )
            raw = [f.strip() for f in result.stdout.strip().split("\n") if f.strip()]
            seen = set()
            for f in raw:
                if f not in seen:
                    seen.add(f)
                    git_files.append(f)
                if len(git_files) >= 5:
                    break
        except Exception:
            pass
        if git_files:
            break

    if git_files:
        tf_str = ", ".join(git_files)
        insertions.append((lesson["tags_idx"], f"- **target_files**: [{tf_str}]"))
        stats["added"] += 1
        if DRY_RUN:
            print(f"  {lesson['id']} ({cmd}): [{tf_str}]")
    else:
        stats["no_git"] += 1

print(f"\n=== backfill結果 ===")
print(f"教訓total: {stats['total']}")
print(f"既にtarget_filesあり(skip): {stats['skip_has_tf']}")
print(f"source_cmdなし(skip): {stats['skip_no_cmd']}")
print(f"tagsフィールドなし(skip): {stats['skip_no_tags']}")
print(f"git履歴からファイル取得可能: {stats['added']}")
print(f"git履歴にcommitなし: {stats['no_git']}")

if DRY_RUN:
    print(f"\n[DRY-RUN] 実書込みなし。--dry-runを外して再実行せよ")
    sys.exit(0)

if not insertions:
    print("挿入対象なし。終了")
    sys.exit(0)

# Phase 3: 逆順で挿入（インデックスずれ防止）
for idx, text in sorted(insertions, reverse=True):
    lines.insert(idx + 1, text)

with open(LESSONS_FILE, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

print(f"\n[backfill] {len(insertions)}件の教訓にtarget_filesを挿入完了")
PYEOF
