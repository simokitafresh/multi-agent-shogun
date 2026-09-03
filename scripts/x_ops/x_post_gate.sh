#!/usr/bin/env bash
# X投稿下書きの品質gate。設計書 x_account_ops_automation_asis_tobe_5w1h_20260903.md §2 不変条件 + 殿回答B-6準拠。
# Usage: x_post_gate.sh <draft_text_file>
# Exit: 0=PASS(投稿してよい) / 1=FAIL(投稿しない,fail-close)
set -euo pipefail
export LC_ALL=C.UTF-8

SHOWCASE_URL_DEFAULT="https://dm-signal-backend.onrender.com/api/public/showcase"

usage() {
    echo "Usage: $0 <draft_text_file>" >&2
    exit 2
}

DRAFT_FILE="${1:-}"
[ -n "$DRAFT_FILE" ] || usage
[ -f "$DRAFT_FILE" ] || { echo "x_post_gate: file not found: $DRAFT_FILE" >&2; exit 2; }

DRAFT_TEXT="$(cat "$DRAFT_FILE")"
FAILS=()

# --- showcase JSON取得(fixture差替え可能) ---
showcase_json() {
    if [ -n "${X_GATE_SHOWCASE_JSON:-}" ]; then
        if [ -f "$X_GATE_SHOWCASE_JSON" ]; then
            cat "$X_GATE_SHOWCASE_JSON"
        else
            printf '%s' "$X_GATE_SHOWCASE_JSON"
        fi
    else
        curl -s --max-time 10 "${X_GATE_SHOWCASE_URL:-$SHOWCASE_URL_DEFAULT}" || echo '{}'
    fi
}

SHOWCASE_JSON="$(showcase_json)"

# --- Rule 1: 保有シグナル・構成ticker・FoF重み blocklist (Basic-DualMomentumは除外) ---
BLOCKLIST="$(printf '%s' "$SHOWCASE_JSON" | jq -r '
  .data as $d
  | (
      (if (($d.hero.name // "") != "Basic-DualMomentum") then
          [$d.hero.holding, $d.hero.ticker, ($d.hero.components.relative_assets[]? ), $d.hero.components.safe_haven_asset]
       else [] end)
      +
      ([$d.plans[]? | select((.name // "") != "Basic-DualMomentum") |
          (.holding, .ticker, (.components.relative_assets[]? ), .components.safe_haven_asset) ])
    )
  | flatten
  | map(select(. != null and . != ""))
  | unique
  | .[]
' 2>/dev/null || true)"

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
