#!/bin/bash
# lesson_auto_tag.sh — 教訓一括タグ付与スクリプト
# Usage: bash scripts/lesson_auto_tag.sh [--dry-run|--apply]
# Default: --dry-run (書き込みなし、推定結果のみ出力)
# config/lesson_tags.yamlの辞書を使用し、projects/{id}/lessons.yamlの全教訓にタグ推定

set -e

_lat_self="${BASH_SOURCE[0]}"; [[ "$_lat_self" != /* ]] && _lat_self="$PWD/$_lat_self"
SCRIPT_DIR="${_lat_self%/scripts/lesson_auto_tag.sh}"
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

PYTHONPATH="$SCRIPT_DIR" python3 - <<'PY'
import os, sys, re, yaml
from scripts.lib.yaml_atomic import atomic_yaml_write
_CLoader = getattr(yaml, "CSafeLoader", yaml.SafeLoader)

script_dir = os.environ["SCRIPT_DIR"]
tag_dict_path = os.environ["TAG_DICT"]
projects_path = os.environ["PROJECTS_YAML"]
mode = os.environ["MODE"]

tag_rules = None

def _load_tag_rules():
    global tag_rules
    if tag_rules is not None:
        return tag_rules
    with open(tag_dict_path, "r", encoding="utf-8") as f:
        tag_config = yaml.load(f, Loader=_CLoader)
    tag_rules = tag_config.get("tag_rules", [])
    if not tag_rules:
        print("[ERROR] No tag_rules found in tag dictionary", file=sys.stderr)
        sys.exit(1)
    # Precompile regex patterns: performance + early invalid-pattern detection
    for rule in tag_rules:
        compiled = []
        for pat in rule.get("patterns", []):
            try:
                compiled.append(re.compile(pat))
            except re.error as e:
                tag_name = rule.get("tag", "")
                print(f"[ERROR] Invalid regex in tag {tag_name}: {pat} ({e})", file=sys.stderr)
                sys.exit(1)
        rule["_compiled"] = compiled
    return tag_rules

if mode == "apply":
    _load_tag_rules()

def _match_tags(text):
    matched = []
    for rule in _load_tag_rules():
        tag = rule.get("tag", "")
        for cpat in rule.get("_compiled", []):
            if cpat.search(text):
                if tag not in matched:
                    matched.append(tag)
                break
    return matched

# Load projects
with open(projects_path, "r", encoding="utf-8") as f:
    projects_data = yaml.load(f, Loader=_CLoader)

projects = projects_data.get("projects", [])
active_projects = [p for p in projects if p.get("status") == "active"]

total_tagged = 0
total_skipped = 0
total_universal = 0
total_lessons = 0

def _parse_scalar(value):
    value = value.strip()
    if not value:
        return ""
    if value[0] in ("'", "\"") and value[-1:] == value[0]:
        return value[1:-1]
    return value

def _parse_tags(value):
    value = value.strip()
    if not value:
        return []
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [_parse_scalar(part) for part in inner.split(",")]
    return [_parse_scalar(value)]

def _iter_lessons_fast(path):
    current = None
    in_tags = False
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            if stripped.startswith("- id:"):
                if current is not None:
                    yield current
                current = {"id": _parse_scalar(stripped.split(":", 1)[1]), "tags": []}
                in_tags = False
                continue
            if current is None:
                continue
            if stripped.startswith("- ") and not in_tags:
                continue
            if in_tags and stripped.startswith("- "):
                current["tags"].append(_parse_scalar(stripped[2:]))
                continue
            in_tags = False
            if ":" not in stripped:
                continue
            key, value = stripped.split(":", 1)
            key = key.strip()
            if key in ("title", "summary"):
                current[key] = _parse_scalar(value)
            elif key == "tags":
                parsed = _parse_tags(value)
                current["tags"] = parsed
                in_tags = not parsed and value.strip() == ""
        if current is not None:
            yield current

for project in active_projects:
    pid = project.get("id", "")
    lessons_path = os.path.join(script_dir, "projects", pid, "lessons.yaml")

    if not os.path.exists(lessons_path):
        print(f"[SKIP] {lessons_path} not found")
        continue

    if mode == "dry-run":
        lessons = list(_iter_lessons_fast(lessons_path))
        lessons_data = None
    else:
        with open(lessons_path, "r", encoding="utf-8") as f:
            lessons_data = yaml.load(f, Loader=_CLoader)
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

        # タグルールでマッチング（プリコンパイル済み正規表現を使用）
        matched_tags = _match_tags(text)

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
        header_lines = []
        with open(lessons_path, "r", encoding="utf-8") as orig:
            for line in orig:
                if line.startswith("#"):
                    header_lines.append(line)
                else:
                    break
        try:
            atomic_yaml_write(lessons_path, lessons_data, header="".join(header_lines), sort_keys=False)
            print(f"[APPLY] {pid}: lessons.yaml updated")
        except Exception as e:
            print(f"[ERROR] {pid}: {e}", file=sys.stderr)
            sys.exit(1)

print()
print(f"=== Summary (mode: {mode}) ===")
print(f"Total lessons: {total_lessons}")
print(f"Tagged: {total_tagged}")
print(f"Skipped (existing tags): {total_skipped}")
print(f"Universal (no match): {total_universal}")
PY
