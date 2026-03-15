#!/usr/bin/env bash
# ============================================================
# gate_skill_quality.sh
# スキル品質ゲート — ~/.claude/skills/*/SKILL.md を全走査
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

SKILLS_DIR="$HOME/.claude/skills"
HAS_FAIL=0
HAS_WARN=0
TOTAL=0
PASS=0

# フロントマター抽出（2つ目の---まで）
# CR(\r)を除去してからパース（Windows改行対応）
extract_frontmatter() {
    local file="$1"
    tr -d '\r' < "$file" | sed -n '1,/^---$/p' | tail -n +2 | sed '$d'
}

# description抽出（フロントマター内のdescription:以降、次のトップレベルキーまで）
# YAML形式: "description: inline", 'description: "quoted"', "description: |" (block scalar)
extract_description() {
    local file="$1"
    tr -d '\r' < "$file" | awk '
        /^---$/ { fm++; next }
        fm == 1 && /^description:/ {
            in_desc=1
            if ($0 ~ /^description:[[:space:]]*[|>][[:space:]]*$/) { next }
            val = $0
            sub(/^description:[[:space:]]*/, "", val)
            gsub(/^"/, "", val); gsub(/"$/, "", val)
            if (val != "") print val
            next
        }
        fm == 1 && in_desc && /^[a-zA-Z_-]+:/ { in_desc=0; next }
        fm == 1 && in_desc && /^[[:space:]]/ { sub(/^[[:space:]]+/, ""); print; next }
        fm == 1 && in_desc { in_desc=0; next }
        fm == 2 { exit }
    '
}

# メイン走査
for skill_dir in "$SKILLS_DIR"/*/; do
    skill_file="${skill_dir}SKILL.md"
    [ -f "$skill_file" ] || continue

    skill_name=$(basename "$skill_dir")
    TOTAL=$((TOTAL + 1))
    skill_ok=1

    echo "=== $skill_name ==="

    # ----------------------------------------------------------
    # (1) description 1024文字以内
    # ----------------------------------------------------------
    desc=$(extract_description "$skill_file")
    if [ -z "$desc" ]; then
        echo "  FAIL: (1) description が見つかりません"
        HAS_FAIL=1
        skill_ok=0
    else
        char_count=$(echo "$desc" | wc -m)
        if [ "$char_count" -gt 1024 ]; then
            echo "  FAIL: (1) description ${char_count}文字(>1024)"
            HAS_FAIL=1
            skill_ok=0
        else
            echo "  OK: (1) description ${char_count}文字"
        fi
    fi

    # ----------------------------------------------------------
    # (2) What+When+NOT When の3要素検出
    # ----------------------------------------------------------
    has_what=0
    has_when=0
    has_not_when=0

    # descriptionから検出
    if echo "$desc" | grep -qiE '(What|何をする|スキル|する。)'; then
        has_what=1
    fi
    if echo "$desc" | grep -qiE '(When|TRIGGER|いつ使う|時に使用|時に実行|で使う)'; then
        has_when=1
    fi
    if echo "$desc" | grep -qiE '(NOT When|NOT TRIGGER|DO NOT TRIGGER|使用禁止|使わない|発火しない|ではない)'; then
        has_not_when=1
    fi

    found_count=$((has_what + has_when + has_not_when))
    if [ "$found_count" -eq 3 ]; then
        echo "  OK: (2) What+When+NOT When 3/3検出"
    elif [ "$found_count" -ge 2 ]; then
        missing=""
        [ "$has_what" -eq 0 ] && missing+="What "
        [ "$has_when" -eq 0 ] && missing+="When "
        [ "$has_not_when" -eq 0 ] && missing+="NOT_When "
        echo "  WARN: (2) ${found_count}/3検出(不足: ${missing})"
        HAS_WARN=1
        skill_ok=0
    else
        missing=""
        [ "$has_what" -eq 0 ] && missing+="What "
        [ "$has_when" -eq 0 ] && missing+="When "
        [ "$has_not_when" -eq 0 ] && missing+="NOT_When "
        echo "  FAIL: (2) ${found_count}/3検出(不足: ${missing})"
        HAS_FAIL=1
        skill_ok=0
    fi

    # ----------------------------------------------------------
    # (3) SKILL.md 5000語以内
    # ----------------------------------------------------------
    word_count=$(wc -w < "$skill_file")
    if [ "$word_count" -gt 5000 ]; then
        echo "  FAIL: (3) ${word_count}語(>5000)"
        HAS_FAIL=1
        skill_ok=0
    elif [ "$word_count" -gt 4000 ]; then
        echo "  WARN: (3) ${word_count}語(>4000 注意)"
        HAS_WARN=1
    else
        echo "  OK: (3) ${word_count}語"
    fi

    # ----------------------------------------------------------
    # (4) フロントマターに < > なし
    # ----------------------------------------------------------
    frontmatter=$(extract_frontmatter "$skill_file")
    if echo "$frontmatter" | grep -qE '[<>]'; then
        echo "  FAIL: (4) フロントマターに < > を検出"
        HAS_FAIL=1
        skill_ok=0
    else
        echo "  OK: (4) フロントマターに < > なし"
    fi

    # ----------------------------------------------------------
    # (5) allowed-tools の存在確認
    # ----------------------------------------------------------
    if echo "$frontmatter" | grep -q 'allowed-tools'; then
        tool_count=$(echo "$frontmatter" | grep -c '^\s*-' || true)
        echo "  OK: (5) allowed-tools あり(${tool_count}ツール)"
    else
        echo "  WARN: (5) allowed-tools が未定義"
        HAS_WARN=1
        skill_ok=0
    fi

    [ "$skill_ok" -eq 1 ] && PASS=$((PASS + 1))
    echo ""
done

# 総合判定
echo "=== 総合判定 ==="
echo "走査: ${TOTAL}スキル, PASS: ${PASS}/${TOTAL}"

if [ "$HAS_FAIL" -gt 0 ]; then
    echo "--- 総合判定: FAIL ---"
    exit 1
elif [ "$HAS_WARN" -gt 0 ]; then
    echo "--- 総合判定: WARN ---"
    exit 2
else
    echo "--- 総合判定: OK ---"
    exit 0
fi
