#!/usr/bin/env bash
# semantic-links: [[Silent Fallback品質]]
# gate_silent_fallback.sh — PI-018 Silent Fallback自動検出ゲート
# 用途: except Exception → データ値返却パターン(Silent Fallback)を自動検出
# 正当なパターン(raise/API最上位エラー)は除外
#
# Usage:
#   bash scripts/gates/gate_silent_fallback.sh [--diff <commit>] [--path <dir>]
#   bash scripts/gates/gate_silent_fallback.sh --help
#   --diff <commit>: diffモード。指定commitからの変更のみ検出
#   --path <dir>: 検査対象ディレクトリ（デフォルト: DM-Signal backend/app）
#   引数なし: 全量監査モード

set -euo pipefail

_GSF_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=scripts/lib/project_path.sh
source "${_GSF_ROOT}/scripts/lib/project_path.sh"

usage() {
    cat <<'EOF'
Usage: bash scripts/gates/gate_silent_fallback.sh [--diff <commit>] [--path <dir>]
       bash scripts/gates/gate_silent_fallback.sh --help

Detect except Exception blocks that silently return data fallback values.

Options:
  --diff <commit>  Scan only changed backend/app Python files since commit
  --path <dir>     Scan a specific directory (default: DM-Signal backend/app)
  -h, --help       Show this help
EOF
}

DM_SIGNAL_PATH="$(get_project_path 'dm-signal')"
TARGET_PATH="${DM_SIGNAL_PATH}/backend/app"
DIFF_BASE=""
MODE="audit"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
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

# --- パターン結合（IFS join: forループ廃止、bash組込みのみ） ---
_ifs_saved="$IFS"; IFS='|'
LEGIT_RE="${LEGITIMATE_PATTERNS[*]}"
DATA_RE="${DATA_VALUE_PATTERNS[*]}"
IFS="$_ifs_saved"

# --- 1パスgrep/rg: 全except Exceptionブロックを一括取得 (rg優先) ---
_use_rg=false
command -v rg >/dev/null 2>&1 && _use_rg=true

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
        if [[ "$_use_rg" == true ]]; then
            grep_output=$(rg -n -A 10 'except Exception' --type py "${full_paths[@]}" 2>/dev/null || true)
        else
            grep_output=$(grep -Hn -A 10 'except Exception' "${full_paths[@]}" 2>/dev/null || true)
        fi
    fi
else
    if [[ "$_use_rg" == true ]]; then
        grep_output=$(rg -n -A 10 'except Exception' \
            --type py --glob '!__pycache__' --glob '!test*' --glob '!.venv' \
            "$TARGET_PATH" 2>/dev/null || true)
    else
        grep_output=$(grep -rn -A 10 'except Exception' \
            --include='*.py' --exclude-dir='__pycache__' --exclude-dir='test' --exclude-dir='.venv' \
            "$TARGET_PATH" 2>/dev/null || true)
    fi
fi

[[ -z "$grep_output" ]] && grep_output=""

# --- ブロック解析（awk 1プロセス。WSL2上のbash正規表現ループを回避） ---
analysis_output=$(GSF_LEGIT_RE="$LEGIT_RE" GSF_DATA_RE="$DATA_RE" GSF_ROOT="${DM_SIGNAL_PATH}/" awk '
function reset_block() { file=""; first=""; legit=0; data=0; data_line="" }
function update_flags(content) {
    if (!legit && content ~ legit_re) legit=1
    if (!data && content ~ data_re) {
        data=1; data_line=content; sub(/^[[:space:]]+/, "", data_line)
    }
}
function emit_block( rel) {
    if (file == "") return
    if (first ~ /#.*except/) { reset_block(); return }
    total++
    if (!legit && data) {
        violations++; rel=file; sub("^" root, "", rel)
        print "S\t" rel "\t" line_no "\t" data_line
    }
    reset_block()
}
BEGIN { legit_re=ENVIRON["GSF_LEGIT_RE"]; data_re=ENVIRON["GSF_DATA_RE"]; root=ENVIRON["GSF_ROOT"]; reset_block() }
$0 == "--" { emit_block(); next }
{
    raw=$0
    if (match(raw, /\.py:[0-9]+:/)) {
        marker=substr(raw, RSTART + 4, RLENGTH - 5)
        content=substr(raw, RSTART + RLENGTH)
        if (index(content, "except Exception")) {
            emit_block(); file=substr(raw, 1, RSTART + 2); line_no=marker
            first=content; next
        }
    }
    if (file != "") {
        if (match(raw, /\.py-[0-9]+-/)) update_flags(substr(raw, RSTART + RLENGTH))
        else if (match(raw, /\.py:[0-9]+:/)) update_flags(substr(raw, RSTART + RLENGTH))
        else update_flags(raw)
    }
}
END { emit_block(); print "C\t" total "\t" violations }
' <<< "$grep_output")

VIOLATIONS=0
TOTAL_EXCEPT=0
while IFS=$'\t' read -r kind field1 field2 field3; do
    if [[ "$kind" == "S" ]]; then
        echo "  SUSPECT: ${field1}:${field2} — except Exception + [${field3}]"
    elif [[ "$kind" == "C" ]]; then
        TOTAL_EXCEPT="$field1"
        VIOLATIONS="$field2"
    fi
done <<< "$analysis_output"

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
    echo ""
    echo "action: 上記 SUSPECT 箇所を修正せよ。"
    echo "  修正例1(エラー隠蔽): except Exception as e: raise RuntimeError(f'operation failed: {e}') from e"
    echo "  修正例2(正当なデフォルト): except Exception:  # PI-018: legitimate default — <理由>  return []"
    exit 1  # BLOCK: silent fallbackは消火(PI-018)。忍者に修正させよ
else
    echo "STATUS: OK — No suspect patterns found"
    exit 0
fi
