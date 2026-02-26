#!/bin/bash
# lesson_auto_tag.sh — 教訓一括タグ付与スクリプト
# Usage: bash scripts/lesson_auto_tag.sh [--dry-run|--apply]
# Default: --dry-run (書き込みなし、推定結果のみ出力)
# config/lesson_tags.yamlの辞書を使用し、projects/{id}/lessons.yamlの全教訓にタグ推定

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG_DICT="${SCRIPT_DIR}/config/lesson_tags.yaml"
PROJECTS_YAML="${SCRIPT_DIR}/config/projects.yaml"

MODE="dry-run"
if [ "${1:-}" = "--apply" ]; then
    MODE="apply"
fi

if [ ! -f "$TAG_DICT" ]; then
    echo "[ERROR] Tag dictionary not found: $TAG_DICT" >&2
    exit 1
fi

if [ ! -f "$PROJECTS_YAML" ]; then
    echo "[ERROR] Projects config not found: $PROJECTS_YAML" >&2
    exit 1
fi

export TAG_DICT PROJECTS_YAML SCRIPT_DIR MODE

python3 -c '
import os, sys, re, yaml, tempfile, shutil

script_dir = os.environ["SCRIPT_DIR"]
tag_dict_path = os.environ["TAG_DICT"]
projects_path = os.environ["PROJECTS_YAML"]
mode = os.environ["MODE"]

# Load tag dictionary
with open(tag_dict_path, "r", encoding="utf-8") as f:
    tag_config = yaml.safe_load(f)

tag_rules = tag_config.get("tag_rules", [])
if not tag_rules:
    print("[ERROR] No tag_rules found in tag dictionary", file=sys.stderr)
    sys.exit(1)

# Load projects
with open(projects_path, "r", encoding="utf-8") as f:
    projects_data = yaml.safe_load(f)

projects = projects_data.get("projects", [])
active_projects = [p for p in projects if p.get("status") == "active"]

total_tagged = 0
total_skipped = 0
total_universal = 0
total_lessons = 0

for project in active_projects:
    pid = project.get("id", "")
    lessons_path = os.path.join(script_dir, "projects", pid, "lessons.yaml")

    if not os.path.exists(lessons_path):
        print(f"[SKIP] {lessons_path} not found")
        continue

    with open(lessons_path, "r", encoding="utf-8") as f:
        lessons_data = yaml.safe_load(f)

    # L063: lessons.yamlはdict構造。data.get("lessons",[]) でアクセス
    lessons = lessons_data.get("lessons", [])
    if not lessons:
        print(f"[SKIP] {pid}: no lessons found")
        continue

    modified = False
    for lesson in lessons:
        lid = lesson.get("id", "?")
        total_lessons += 1

        # 既存tagsフィールドがある教訓はスキップ
        if "tags" in lesson and lesson["tags"]:
            total_skipped += 1
            if mode == "dry-run":
                existing = lesson["tags"]
                print(f"  [{pid}] {lid}: SKIP (existing tags: {existing})")
            continue

        # title + summary からテキスト生成
        title = str(lesson.get("title", ""))
        summary = str(lesson.get("summary", ""))
        text = title + " " + summary

        # タグルールでマッチング
        matched_tags = []
        for rule in tag_rules:
            tag = rule.get("tag", "")
            patterns = rule.get("patterns", [])
            for pat in patterns:
                try:
                    if re.search(pat, text):
                        if tag not in matched_tags:
                            matched_tags.append(tag)
                        break
                except re.error:
                    pass

        if not matched_tags:
            matched_tags = ["universal"]
            total_universal += 1
        else:
            total_tagged += 1

        if mode == "dry-run":
            print(f"  [{pid}] {lid}: {matched_tags}")
        else:
            lesson["tags"] = matched_tags
            modified = True

    if mode == "apply" and modified:
        # Atomic write: tempfile + shutil.move
        dir_name = os.path.dirname(lessons_path)
        fd, tmp_path = tempfile.mkstemp(suffix=".yaml", dir=dir_name)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as tmp_f:
                # Preserve header comments
                with open(lessons_path, "r", encoding="utf-8") as orig:
                    for line in orig:
                        if line.startswith("#"):
                            tmp_f.write(line)
                        else:
                            break
                yaml.dump(lessons_data, tmp_f, allow_unicode=True,
                          default_flow_style=False, sort_keys=False)
            shutil.move(tmp_path, lessons_path)
            print(f"[APPLY] {pid}: lessons.yaml updated")
        except Exception as e:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
            print(f"[ERROR] {pid}: {e}", file=sys.stderr)
            sys.exit(1)

print()
print(f"=== Summary (mode: {mode}) ===")
print(f"Total lessons: {total_lessons}")
print(f"Tagged: {total_tagged}")
print(f"Skipped (existing tags): {total_skipped}")
print(f"Universal (no match): {total_universal}")
'
