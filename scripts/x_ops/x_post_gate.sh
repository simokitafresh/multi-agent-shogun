#!/usr/bin/env bash
# X投稿下書きの品質gate。設計書 x_account_ops_automation_asis_tobe_5w1h_20260903.md §2 不変条件 + 殿回答B-6準拠。
# Usage: x_post_gate.sh <draft_text_file>
# Exit: 0=PASS(投稿してよい) / 1=FAIL(投稿しない,fail-close)
set -euo pipefail
export LC_ALL=C.UTF-8

SIGNALS_URL_DEFAULT="https://dm-signal-backend.onrender.com/api/signals"

_SELF_PATH="${BASH_SOURCE[0]:-$0}"
[[ "$_SELF_PATH" != /* ]] && _SELF_PATH="$PWD/$_SELF_PATH"
_SCRIPT_DIR="$(cd "$(dirname "$_SELF_PATH")/../.." && pwd)"
if [ -f "${_SCRIPT_DIR}/scripts/lib/project_path.sh" ]; then
    # shellcheck source=scripts/lib/project_path.sh
    source "${_SCRIPT_DIR}/scripts/lib/project_path.sh"
fi
_DM_SIGNAL_PATH="${DM_SIGNAL_DIR:-}"
if [ -z "$_DM_SIGNAL_PATH" ] && command -v get_project_path >/dev/null 2>&1; then
    _DM_SIGNAL_PATH="$(get_project_path 'dm-signal' 2>/dev/null || true)"
fi
SIGNALS_ENV_FILE_DEFAULT="${_DM_SIGNAL_PATH:+${_DM_SIGNAL_PATH}/backend/.env}"

usage() {
    echo "Usage: $0 <draft_text_file>" >&2
    exit 2
}

DRAFT_FILE="${1:-}"
[ -n "$DRAFT_FILE" ] || usage
[ -f "$DRAFT_FILE" ] || { echo "x_post_gate: file not found: $DRAFT_FILE" >&2; exit 2; }

DRAFT_TEXT="$(cat "$DRAFT_FILE")"
FAILS=()

fail_close_rule1() {
    printf 'x_post_gate: FAIL rule1 blocklist unavailable (fail-close)\n' >&2
    exit 1
}

# --- 認証情報取得(env優先、無ければbackend/.env。値をlog/stdoutに出さない) ---
_signals_creds() {
    if [ -n "${X_GATE_SIGNALS_USER:-}" ] && [ -n "${X_GATE_SIGNALS_PASS:-}" ]; then
        printf '%s:%s' "$X_GATE_SIGNALS_USER" "$X_GATE_SIGNALS_PASS"
        return 0
    fi
    local env_file="${X_GATE_SIGNALS_ENV_FILE:-$SIGNALS_ENV_FILE_DEFAULT}"
    [ -n "$env_file" ] && [ -f "$env_file" ] || return 1
    local user="" pass=""
    while IFS='=' read -r key value; do
        case "$key" in
            ADMIN_USER) user="$value" ;;
            ADMIN_PASS) pass="$value" ;;
        esac
    done < <(grep -E '^ADMIN_(USER|PASS)=' "$env_file" | tr -d '\r')
    [ -n "$user" ] && [ -n "$pass" ] || return 1
    printf '%s:%s' "$user" "$pass"
}

# --- signals JSON取得(fixture差替え可能。取得失敗はrc!=0で呼び出し元へ通知) ---
signals_json() {
    if [ -n "${X_GATE_SIGNALS_JSON:-}" ]; then
        if [ -f "$X_GATE_SIGNALS_JSON" ]; then
            cat "$X_GATE_SIGNALS_JSON"
        else
            printf '%s' "$X_GATE_SIGNALS_JSON"
        fi
        return 0
    fi

    local creds
    creds="$(_signals_creds)" || return 1

    local url="${X_GATE_SIGNALS_URL:-$SIGNALS_URL_DEFAULT}"
    local body_file http_code
    body_file="$(mktemp)"
    if ! http_code="$(curl -sS --max-time 10 -o "$body_file" -w '%{http_code}' -u "$creds" "$url" 2>/dev/null)"; then
        rm -f "$body_file"
        return 1
    fi
    if [ "$http_code" != "200" ]; then
        rm -f "$body_file"
        return 1
    fi
    cat "$body_file"
    rm -f "$body_file"
}

SIGNALS_JSON="$(signals_json)" || fail_close_rule1

# --- Rule 1: 保有シグナル・構成ticker blocklist (認証付き/api/signals全PFのholdingからBasic-DualMomentumのholdingを除いた集合。取得失敗/空はfail-close) ---
BLOCKLIST="$(printf '%s' "$SIGNALS_JSON" | jq -r -e '
  def tickers(s):
    if (s == null) or (s == "") or (s == "No Data") then []
    else (s | split(",") | map(gsub("^\\s+|\\s+$";"") | gsub("\\s+[0-9.]+%\\s*$";"")) | map(select(. != "")))
    end;
  .data.portfolios as $pf
  | ($pf | map(select(.name == "Basic-DualMomentum")) | map(tickers(.signal)) | flatten | unique) as $basic
  | ($pf | map(select(.name != "Basic-DualMomentum")) | map(tickers(.signal)) | flatten | unique) as $others
  | ($others - $basic) | unique | .[]
' 2>/dev/null)" || fail_close_rule1

if [ -n "$BLOCKLIST" ]; then
    while IFS= read -r tok; do
        [ -z "$tok" ] && continue
        if grep -qF -- "$tok" <<<"$DRAFT_TEXT"; then
            FAILS+=("rule1_holding_or_ticker_leak:${tok}")
        fi
    done <<<"$BLOCKLIST"
fi

# --- Rule 2: 単独倍率(期間/CAGR/MaxDD/ベンチのいずれとも同一段落に無い「N倍」) ---
PARAGRAPHS_FILE="$(mktemp)"
trap 'rm -f "$PARAGRAPHS_FILE"' EXIT
awk 'BEGIN{RS="";ORS="\x00"} {print}' "$DRAFT_FILE" > "$PARAGRAPHS_FILE"

while IFS= read -r -d $'\0' para; do
    [ -z "$para" ] && continue
    if grep -qE '[0-9]+(\.[0-9]+)?[ ]*倍' <<<"$para"; then
        if ! grep -qE '(CAGR|MaxDD|最大ドローダウン|SPY|S&P500|TQQQ|QQQ|ベンチマーク|対[A-Za-z]|[0-9]{4}年|[0-9]+年間|〜)' <<<"$para"; then
            FAILS+=("rule2_standalone_multiplier")
        fi
    fi
done < "$PARAGRAPHS_FILE"

# --- Rule 3: URLは完全ガイド/How toマガジン/dm-signal.comの3種以外があればFAIL ---
URLS="$(grep -oE 'https?://[^ 　\n<>"]+' <<<"$DRAFT_TEXT" || true)"
if [ -n "$URLS" ]; then
    while IFS= read -r url; do
        [ -z "$url" ] && continue
        case "$url" in
            *note.com/tokyojibika/n/n171daa7f92a1*) ;;
            *note.com/tokyojibika/m/mb4377418b422*) ;;
            *dm-signal.com*) ;;
            *) FAILS+=("rule3_disallowed_url:${url}") ;;
        esac
    done <<<"$URLS"
fi

# --- Rule 4: 免責1行(『助言ではない』『保証しない』のいずれか)が無ければFAIL ---
if ! grep -qF '助言ではない' <<<"$DRAFT_TEXT" && ! grep -qF '保証しない' <<<"$DRAFT_TEXT"; then
    FAILS+=("rule4_missing_disclaimer")
fi

# --- Rule 5: 禁止語(無敵/確実/人生が変わる/今これを買え/劇薬) ---
for word in "無敵" "確実" "人生が変わる" "今これを買え" "劇薬"; do
    if grep -qF -- "$word" <<<"$DRAFT_TEXT"; then
        FAILS+=("rule5_forbidden_word:${word}")
    fi
done

# --- Rule 6: 第一文に内部用語(四神/忍法/Ave/FoF/CPCV)があればFAIL ---
FIRST_SEGMENT="$(awk 'BEGIN{RS="。"} {print; exit}' "$DRAFT_FILE")"
for term in "四神" "忍法" "Ave" "FoF" "CPCV"; do
    if grep -qF -- "$term" <<<"$FIRST_SEGMENT"; then
        FAILS+=("rule6_internal_term_in_first_line:${term}")
    fi
done

if [ "${#FAILS[@]}" -gt 0 ]; then
    printf 'FAIL\n' >&2
    for f in "${FAILS[@]}"; do
        printf '%s\n' "$f" >&2
    done
    exit 1
fi

echo "PASS"
exit 0
