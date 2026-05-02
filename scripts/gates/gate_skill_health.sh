#!/usr/bin/env bash
# ============================================================
# gate_skill_health.sh
# スキル健全性ゲート — プロジェクト内 skills/*/SKILL.md を全走査
#
# Usage:
#   bash scripts/gates/gate_skill_health.sh [SKILLS_DIR]
#   SKILLS_DIR=/path/to/skills bash scripts/gates/gate_skill_health.sh
#
# チェック項目:
#   (A) 到達可能性: 各スキルにTRIGGER定義が存在するか
#   (B) MECE: TRIGGERキーワードの衝突検出（複数スキルに同一キーワード）
#   (C) DRY: NOT TRIGGERの→参照先スキルが実在するか
#
# Exit code: 0=PASS, 1=FAIL(parse error), 2=WARN(健全性問題あり)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILLS_DIR="${1:-${SKILLS_DIR:-$SCRIPT_DIR/skills}}"

run_gate_skill_health_scan() {
SKILLS_DIR_ENV="$SKILLS_DIR" python3 - <<'PYEOF'
import os
import re
import sys

skills_dir = os.environ["SKILLS_DIR_ENV"]
top_key_re = re.compile(r"^[A-Za-z_-]+:")


def extract_frontmatter(text):
    """YAMLフロントマターを抽出"""
    lines = text.replace("\r", "").splitlines()
    if not lines or lines[0] != "---":
        return ""
    try:
        end = lines.index("---", 1)
    except ValueError:
        return ""
    return "\n".join(lines[1:end])


def extract_description(frontmatter):
    """フロントマターからdescriptionフィールドを抽出"""
    if not frontmatter:
        return ""
    lines = frontmatter.splitlines()
    for idx, line in enumerate(lines):
        if not line.startswith("description:"):
            continue
        tail = line.split(":", 1)[1].strip()
        if tail in ("|", ">"):
            chunks = []
            for follow in lines[idx + 1:]:
                if top_key_re.match(follow):
                    break
                if follow[:1].isspace():
                    chunks.append(follow.lstrip())
                else:
                    break
            return "\n".join(chunks).strip()
        return tail.strip("\"'")
    return ""


def extract_triggers(description):
    """TRIGGER:行からキーワードリストを抽出"""
    triggers = []
    for line in description.splitlines():
        if re.match(r"^\s*TRIGGER\s*:", line, re.IGNORECASE):
            content = line.split(":", 1)[1]
            parts = re.split(r"[、,]", content)
            for p in parts:
                p = p.strip()
                if p:
                    triggers.append(p)
    return triggers


def extract_cross_refs(description):
    """NOT TRIGGER / DO NOT TRIGGER行から→参照スキル名を抽出

    スキル名は [a-z][a-z0-9-]* かつ直後が _ / . でないこと
    (→dashboard_auto_section.sh → "dashboard" と誤検出を防ぐ)
    """
    refs = []
    for line in description.splitlines():
        if re.match(
            r"^\s*(DO\s+NOT\s+TRIGGER|NOT\s+TRIGGER|NOT\s+WHEN)\s*:",
            line,
            re.IGNORECASE,
        ):
            # →/skill-name または →skill-name パターンを抽出
            # 負の先読みで a-z0-9_/. の継続を除外
            # (→dashboard_auto_section.sh や →outputs/analysis/ の誤検出を防ぐ)
            matches = re.findall(
                r"→[/\s]*([a-z][a-z0-9-]*)(?![a-z0-9_/.])", line
            )
            refs.extend(matches)
    return refs


# ─── スキル走査 ───────────────────────────────────────
skills = {}
parse_errors = []

if os.path.isdir(skills_dir):
    for entry in sorted(os.scandir(skills_dir), key=lambda x: x.name):
        if not entry.is_dir():
            continue
        skill_file = os.path.join(entry.path, "SKILL.md")
        if not os.path.isfile(skill_file):
            continue
        try:
            with open(skill_file, "r", encoding="utf-8") as fh:
                text = fh.read()
        except OSError as e:
            parse_errors.append(f"{entry.name}: 読取エラー ({e})")
            continue

        fm = extract_frontmatter(text)
        if not fm:
            parse_errors.append(f"{entry.name}: フロントマターなし (--- 区切り未検出)")
            continue

        desc = extract_description(fm)
        triggers = extract_triggers(desc)
        cross_refs = extract_cross_refs(desc)
        skills[entry.name] = {
            "triggers": triggers,
            "cross_refs": cross_refs,
            "desc": desc,
        }

skill_names = set(skills.keys())
has_fail = False
has_warn = False
total = len(skills)

# parse errorはFAIL
if parse_errors:
    print("=== 解析エラー ===")
    for err in parse_errors:
        print(f"  FAIL: {err}")
    has_fail = True
    print()

# ─── (A) 到達可能性チェック ─────────────────────────────
print("=== (A) 到達可能性チェック ===")
reachability_issues = []
for name in sorted(skills):
    info = skills[name]
    if not info["triggers"]:
        print(f"  WARN [{name}]: TRIGGER未定義 — スキルのルーティング曖昧")
        has_warn = True
        reachability_issues.append(name)
    else:
        has_slash = any(t.strip().startswith("/") for t in info["triggers"])
        if has_slash:
            print(f"  OK   [{name}]: {len(info['triggers'])}件 (スラッシュコマンドあり)")
        else:
            print(f"  WARN [{name}]: {len(info['triggers'])}件 (スラッシュコマンドなし)")
            has_warn = True

if not reachability_issues:
    print("  → 全スキルにTRIGGER定義あり")
print()

# ─── (B) MECEチェック: TRIGGERキーワード衝突 ─────────────
print("=== (B) MECEチェック (TRIGGERキーワード衝突検出) ===")
keyword_to_skills = {}
for name, info in skills.items():
    for trigger in info["triggers"]:
        # スラッシュコマンドはスキル名固有なので衝突チェック除外
        key = trigger.strip().lower().lstrip("/")
        if not key:
            continue
        # /skill-name 形式は衝突対象外
        if trigger.strip().startswith("/"):
            continue
        keyword_to_skills.setdefault(key, []).append(name)

collision_found = False
for keyword in sorted(keyword_to_skills):
    skill_list = keyword_to_skills[keyword]
    if len(skill_list) > 1:
        print(
            f"  WARN: 衝突キーワード '{keyword}' → {', '.join(sorted(skill_list))}"
        )
        has_warn = True
        collision_found = True

if not collision_found:
    print("  OK: TRIGGERキーワードの衝突なし")
print()

# ─── (C) DRYチェック: NOT TRIGGER参照先の実在確認 ──────────
print("=== (C) DRYチェック (NOT TRIGGER参照先確認) ===")

# スラッシュコマンドからスキル名への逆引きマップを構築
# 例: /weekly-report → weekly-report-writer
slash_to_skill = {}
for name, info in skills.items():
    for trigger in info["triggers"]:
        t = trigger.strip()
        if t.startswith("/"):
            slash_cmd = t.lstrip("/").lower()
            slash_to_skill[slash_cmd] = name


def ref_exists(ref, skill_names, slash_to_skill):
    """参照が実在するか確認 (ディレクトリ名 or スラッシュコマンド名)"""
    return ref in skill_names or ref in slash_to_skill


dry_issues = []
for name in sorted(skills):
    for ref in skills[name]["cross_refs"]:
        if not ref_exists(ref, skill_names, slash_to_skill):
            print(
                f"  WARN [{name}]: NOT TRIGGER参照 '→{ref}' が不在"
                f" (スキル名・スラッシュコマンドどちらでもヒットなし)"
            )
            has_warn = True
            dry_issues.append((name, ref))

if not dry_issues:
    print("  OK: 全NOT TRIGGER参照先が実在")
print()

# ─── 総合判定 ──────────────────────────────────────────
print(f"走査: {total}スキル")
if has_fail:
    print("--- 総合判定: FAIL ---")
    sys.exit(1)
if has_warn:
    print("--- 総合判定: WARN ---")
    sys.exit(2)
print("--- 総合判定: PASS ---")
sys.exit(0)
PYEOF
}

maybe_cache_gate_skill_health() {
    local default_skills_dir="$SCRIPT_DIR/skills"
    [ "$SKILLS_DIR" = "$default_skills_dir" ] || return 90
    [ "${SKILL_HEALTH_DISABLE_CACHE:-0}" != "1" ] || return 90

    local cache_ttl
    cache_ttl="${SKILL_HEALTH_CACHE_TTL_SECONDS:-5}"
    [ "$cache_ttl" -gt 0 ] 2>/dev/null || return 90

    local cache_key cache_base cache_out cache_code now cache_mtime cache_age
    cache_key="$(printf '%s\0%s\0%s' "$SCRIPT_DIR" "$SKILLS_DIR" "$(stat -c %Y "$0" 2>/dev/null || printf 0)" | md5sum | cut -c1-16)"
    cache_base="/tmp/shogun_gate_skill_health_${cache_key}"
    cache_out="${cache_base}.out"
    cache_code="${cache_base}.code"
    printf -v now '%(%s)T' -1

    if [ -f "$cache_out" ] && [ -f "$cache_code" ]; then
        cache_mtime="$(stat -c %Y "$cache_out" 2>/dev/null || printf 0)"
        cache_age=$((now - cache_mtime))
        if [ "$cache_age" -ge 0 ] && [ "$cache_age" -le "$cache_ttl" ]; then
            cat "$cache_out"
            return "$(cat "$cache_code")"
        fi
    fi

    local tmp_out tmp_code scan_code
    tmp_out="$(mktemp "${cache_base}.XXXXXX")"
    tmp_code="${cache_code}.tmp"
    set +e
    run_gate_skill_health_scan >"$tmp_out"
    scan_code=$?
    set -e
    printf '%s\n' "$scan_code" >"$tmp_code"
    mv "$tmp_out" "$cache_out"
    mv "$tmp_code" "$cache_code"
    cat "$cache_out"
    return "$scan_code"
}

if maybe_cache_gate_skill_health; then
    exit 0
else
    cache_status=$?
    if [ "$cache_status" -ne 90 ]; then
        exit "$cache_status"
    fi
fi

run_gate_skill_health_scan
