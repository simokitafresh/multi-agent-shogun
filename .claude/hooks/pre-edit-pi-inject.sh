#!/usr/bin/env bash
# pre-edit-pi-inject.sh — DM-Signal PIコンテキスト注入
# PreToolUse:Write|Edit — DM-Signalプロジェクトファイル編集時に関連PIを表示
# PI動的取得: projects/dm-signal.yaml production_invariants
# パス条件: config/projects.yaml path値
# DM-Signal以外のパスでは無発火
set -eu

payload="$(cat 2>/dev/null || true)"
case "$payload" in
    *[![:space:]]*) ;;
    *) exit 0 ;;
esac

# Fast-path: Write/Edit のみ
case "$payload" in
    *'"Write"'*|*'"Edit"'*) ;;
    *) exit 0 ;;
esac

# file_path 抽出
file_path="$(printf '%s' "$payload" | jq -r '(.tool_input // .toolInput // {}) | .file_path // .filePath // .path // ""' 2>/dev/null)" || exit 0
[[ -z "$file_path" ]] && exit 0

# DM-Signal path を config/projects.yaml から動的取得
REPO_ROOT="${REPO_ROOT:-/mnt/c/tools/multi-agent-shogun}"
PROJECTS_YAML="${REPO_ROOT}/config/projects.yaml"
PI_YAML="${REPO_ROOT}/projects/dm-signal.yaml"

DM_PATH="$(awk '/id: dm-signal/{found=1} found && /path:/{match($0, /"([^"]+)"/, a); print a[1]; found=0; exit}' "$PROJECTS_YAML" 2>/dev/null)" || DM_PATH=""
[[ -z "$DM_PATH" ]] && DM_PATH="/mnt/c/Python_app/DM-signal"

INFRA_PATH="$(awk '/id: infra/{found=1} found && /path:/{match($0, /"([^"]+)"/, a); print a[1]; found=0; exit}' "$PROJECTS_YAML" 2>/dev/null)" || INFRA_PATH=""
[[ -z "$INFRA_PATH" ]] && INFRA_PATH="/mnt/c/tools/multi-agent-shogun"

is_under_path() {
    local child="$1"
    local parent="${2%/}"

    [[ -n "$parent" ]] || return 1
    [[ "$parent" != "/" && "$parent" != "/mnt" && "$parent" != "/mnt/c" ]] || return 1
    [[ "$child" == "$parent" || "$child" == "$parent/"* ]]
}

# infra platform files are outside DM-Signal and must never receive DM-Signal PI injection.
if is_under_path "$file_path" "$INFRA_PATH"; then
    exit 0
fi

# DM-Signal以外は無発火 (AC3)
if ! is_under_path "$file_path" "$DM_PATH"; then
    exit 0
fi

emit_context() {
    printf '%s' "$1" | jq -Rs '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":.}}'
}

# backend/app/ → DB操作系PI (PI-003/013/018/023/025) (AC1)
if [[ "$file_path" == "${DM_PATH}/backend/app/"* ]]; then
    pi_info="$(awk '
        /^    - id: /{
            id = $NF
            if (id == "PI-003" || id == "PI-013" || id == "PI-018" || id == "PI-023" || id == "PI-025") {
                cur = id
            } else {
                cur = ""
            }
        }
        cur != "" && /^      fact:/{
            line = $0
            sub(/^      fact: "?/, "", line)
            sub(/"?[[:space:]]*$/, "", line)
            print cur ": " line
            cur = ""
        }
    ' "$PI_YAML" 2>/dev/null)" || pi_info=""

    emit_context "【backend/app/ 編集前確認】DB操作系PI:
${pi_info}"
    exit 0
fi

# frontend/ → FE系注意事項 (AC2)
if [[ "$file_path" == "${DM_PATH}/frontend/"* ]]; then
    pi021_fact="$(awk '
        /^    - id: PI-021/{cur=1; next}
        cur && /^      fact:/{
            line = $0
            sub(/^      fact: "?/, "", line)
            sub(/"?[[:space:]]*$/, "", line)
            print line
            exit
        }
        cur && /^    - id:/{exit}
    ' "$PI_YAML" 2>/dev/null)" || pi021_fact=""

    emit_context "【frontend/ 編集前確認】FE系注意事項:
PI-021: ${pi021_fact}
static export制約: 'use client'必須コンポーネント確認。API routesはサポートされない。server componentからclient componentへの変更は慎重に。"
    exit 0
fi

exit 0
