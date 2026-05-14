#!/usr/bin/env bash
# PreToolUse Skill project guard
# SKILL.mdのallowed_projectsとcurrent_projectを照合し、不整合ならexit 2でBLOCK
# L164: set -eu only (pipefailは使うな)
set -eu

REPO="/mnt/c/tools/multi-agent-shogun"

payload="$(cat)"
[[ -z "${payload//[[:space:]]/}" ]] && exit 0
# Skill tool呼出しでなければスキップ
[[ "$payload" != *'"Skill"'* ]] && exit 0

# スキル名をJSONから抽出(awk: jq不要)
skill_name="$(printf '%s' "$payload" | awk '
    match($0, /"skill"[[:space:]]*:[[:space:]]*"/) {
        s = substr($0, RSTART + RLENGTH)
        n = length(s); result = ""
        for (i = 1; i <= n; i++) {
            c = substr(s, i, 1)
            if (c == "\\" && i < n) { result = result substr(s, i, 2); i++; continue }
            if (c == "\"") break
            result = result c
        }
        print result
        exit
    }
')"

[[ -z "$skill_name" ]] && exit 0

# SKILL.md確認
skill_md="$REPO/skills/$skill_name/SKILL.md"
[[ ! -f "$skill_md" ]] && exit 0

# allowed_projectsフィールドを取得
# 形式: allowed_projects: [dm-signal, infra] または allowed_projects: dm-signal
allowed_line="$(grep -m1 '^allowed_projects:' "$skill_md" 2>/dev/null || true)"
[[ -z "$allowed_line" ]] && exit 0  # 制約なし → 全プロジェクトで使用可

# current_projectを取得
current_project="$(grep -m1 '^current_project:' "$REPO/config/projects.yaml" 2>/dev/null | awk '{print $2}' | tr -d ' ' || true)"
[[ -z "$current_project" ]] && exit 0

# allowed_projects値をパース: ブラケット・カンマを除去してspace区切りに
allowed_raw="${allowed_line#allowed_projects:}"
allowed_raw="${allowed_raw//[\[\]]/}"
allowed_raw="${allowed_raw//,/ }"

# current_projectがallowed_listに含まれるか確認
found=0
for p in $allowed_raw; do
    p_trim="${p// /}"
    if [[ "$p_trim" == "$current_project" ]]; then
        found=1
        break
    fi
done

if [[ $found -eq 0 ]]; then
    # word-splitで先頭/末尾スペースを除去してカンマ区切りに整形
    allowed_display="$(echo "$allowed_raw" | tr ' ' ','| tr -s ',' | sed 's/^,//; s/,$//')"
    echo "BLOCK: スキル '$skill_name' は [${allowed_display}] 専用です。" >&2
    echo "current_project='$current_project' での使用はDO NOT TRIGGERに該当します。" >&2
    echo "→ このプロジェクト向けの正しいスキルか手順を使用してください。" >&2
    exit 2
fi

exit 0
