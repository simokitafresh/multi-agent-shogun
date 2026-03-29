#!/usr/bin/env bash
# gate_silent_fallback.sh — PI-018 Silent Fallback自動検出ゲート
# 用途: except Exception → データ値返却パターン(Silent Fallback)を自動検出
# 正当なパターン(raise/API最上位エラー)は除外
#
# Usage:
#   bash scripts/gates/gate_silent_fallback.sh [--diff <commit>] [--path <dir>]
#   --diff <commit>: diffモード。指定commitからの変更のみ検出
#   --path <dir>: 検査対象ディレクトリ（デフォルト: DM-Signal backend/app）
#   引数なし: 全量監査モード

set -euo pipefail

DM_SIGNAL_PATH="/mnt/c/Python_app/DM-signal"
TARGET_PATH="${DM_SIGNAL_PATH}/backend/app"
DIFF_BASE=""
MODE="audit"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --diff) DIFF_BASE="$2"; MODE="diff"; shift 2 ;;
        --path) TARGET_PATH="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- データ値パターン（Silent Fallbackの証拠） ---
# except後にこれらの代入/返却があればPI-018違反の疑い
DATA_VALUE_PATTERNS=(
    '[^=!<>]= 0\.0'
    '[^=!<>]= 0$'
    '[^=!<>]= 1\.0'
    '[^=!<>]= \[\]'
    '[^=!<>]= \{\}'
    '[^=!<>]= True$'
    '[^=!<>]= False$'
    '[^=!<>]= ""'
    "[^=!<>]= ''"
    '= "Cash"'
    "= 'Cash'"
    '= "SPY"'
    "= 'SPY'"
    '= "monthly"'
    "= 'monthly'"
    'or 0\.0'
    'or 1\.0'
    'or "Cash"'
    "or 'Cash'"
    'return 0[^,]'
    'return \[\]'
    'return \{\}'
    'return True$'
    'return False$'
    'return ""'
    "return ''"
)

# --- 正当パターン（除外対象） ---
# except後にこれらがあれば正当
LEGITIMATE_PATTERNS=(
    'raise'
    'raise RuntimeError'
    'raise ValueError'
    'raise HTTPException'
    'return JSONResponse'
    'return Response'
    'return False, str'
    'return False, f"'
    '\["success"\] = False'
    '"running"\] = False'
)

# --- パターン結合（1回のgrepで全パターン検査） ---
LEGIT_RE=""
for pat in "${LEGITIMATE_PATTERNS[@]}"; do
    [[ -n "$LEGIT_RE" ]] && LEGIT_RE+="|"
    LEGIT_RE+="$pat"
done
DATA_RE=""
for pat in "${DATA_VALUE_PATTERNS[@]}"; do
    [[ -n "$DATA_RE" ]] && DATA_RE+="|"
    DATA_RE+="$pat"
done

# --- 1パスgrep: 全except Exceptionブロックを一括取得 ---
if [[ "$MODE" == "diff" ]]; then
    cd "$DM_SIGNAL_PATH"
    mapfile -t diff_files < <(
        git diff "$DIFF_BASE" --name-only --diff-filter=AM -- 'backend/app/**/*.py' |
            grep -v '__pycache__' | grep -v 'test'
    )
    if [[ ${#diff_files[@]} -eq 0 ]]; then
        grep_output=""
    else
        full_paths=()
        for f in "${diff_files[@]}"; do full_paths+=("${DM_SIGNAL_PATH}/$f"); done
        grep_output=$(grep -Hn -A 10 'except Exception' "${full_paths[@]}" 2>/dev/null || true)
    fi
else
    grep_output=$(grep -rn -A 10 'except Exception' \
        --include='*.py' --exclude-dir='__pycache__' --exclude-dir='test' --exclude-dir='.venv' \
        "$TARGET_PATH" 2>/dev/null || true)
fi

[[ -z "$grep_output" ]] && grep_output=""

# --- ブロック解析 ---
VIOLATIONS=0
TOTAL_EXCEPT=0
FLAGGED_FILES=()

cur_file="" cur_line=""
declare -a cur_block=()

emit_block() {
    [[ -z "$cur_file" ]] && return
    # コメント行のexceptは除外
    if [[ "${cur_block[0]}" == *'#'*'except'* ]]; then
        cur_file=""; cur_block=(); return
    fi
    TOTAL_EXCEPT=$((TOTAL_EXCEPT + 1))
    # 正当パターン（raise等）があればスキップ
    if printf '%s\n' "${cur_block[@]}" | grep -qE "$LEGIT_RE"; then
        cur_file=""; cur_block=(); return
    fi
    # データ値パターン検出
    if printf '%s\n' "${cur_block[@]}" | grep -qE "$DATA_RE"; then
        VIOLATIONS=$((VIOLATIONS + 1))
        local relpath="${cur_file#"${DM_SIGNAL_PATH}"/}"
        local match_line
        match_line=$(printf '%s\n' "${cur_block[@]}" | grep -E "$DATA_RE" | head -1 | sed 's/^[[:space:]]*//')
        echo "  SUSPECT: ${relpath}:${cur_line} — except Exception + [${match_line}]"
        FLAGGED_FILES+=("${relpath}:${cur_line}")
    fi
    cur_file=""; cur_block=()
}

while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "--" ]]; then
        emit_block; continue
    fi
    # match行検出 (filepath:lineno:content)
    if [[ "$line" =~ ^(.+\.py):([0-9]+):(.*)$ ]]; then
        matched_content="${BASH_REMATCH[3]}"
        if [[ "$matched_content" == *"except Exception"* ]]; then
            emit_block  # 前ブロック処理
            cur_file="${BASH_REMATCH[1]}"
            cur_line="${BASH_REMATCH[2]}"
            cur_block=("$matched_content")
            continue
        fi
    fi
    # コンテキスト行: プレフィックス除去してブロックに追加
    if [[ -n "$cur_file" ]]; then
        if [[ "$line" =~ ^.+\.py[-][0-9]+[-](.*)$ ]]; then
            cur_block+=("${BASH_REMATCH[1]}")
        elif [[ "$line" =~ ^.+\.py:[0-9]+:(.*)$ ]]; then
            cur_block+=("${BASH_REMATCH[1]}")
        else
            cur_block+=("$line")
        fi
    fi
done <<< "$grep_output"
emit_block  # 最終ブロック処理

# --- 結果サマリ ---
echo ""
echo "=== PI-018 Silent Fallback Gate ==="
echo "Total except Exception: ${TOTAL_EXCEPT}"
echo "Legitimate (raise/HTTP): $((TOTAL_EXCEPT - VIOLATIONS))"
echo "Suspect (data value fallback): ${VIOLATIONS}"

if [[ $VIOLATIONS -gt 0 ]]; then
    echo "STATUS: WARN — ${VIOLATIONS} suspect pattern(s) found"
    echo ""
    echo "Each suspect should be reviewed:"
    echo "  - Is the data value hiding an error? → PI-018 violation (fix)"
    echo "  - Is it a legitimate default? → Add comment explaining why"
    exit 0  # WARNであってBLOCKではない（人間判断が必要）
else
    echo "STATUS: OK — No suspect patterns found"
    exit 0
fi
