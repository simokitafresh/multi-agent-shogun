#!/usr/bin/env bash
# =============================================================================
# api_usage.sh — API Usage Markdown output for Android WebView
#
# Usage:
#   bash scripts/api_usage.sh claude   # Claude Max Plan usage
#   bash scripts/api_usage.sh openai   # OpenAI organization usage
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_usage() {
    echo "Usage: $0 claude|openai" >&2
    exit 1
}

show_fetch_error() {
    local title="$1"
    local message="$2"

    cat <<MD
# ${title}

> ${message}
MD
}

read_usage_status() {
    local provider="$1"
    local raw=""

    if [[ "$provider" == "codex" ]]; then
        raw=$(PROVIDER=codex "${SCRIPT_DIR}/usage_monitor.sh" --status 2>/dev/null) || true
    else
        raw=$("${SCRIPT_DIR}/usage_monitor.sh" --status 2>/dev/null) || true
    fi

    [[ -z "$raw" ]] && return 1

    local slot_pct slot_reset week_pct week_reset
    IFS=$'\t' read -r slot_pct slot_reset week_pct week_reset <<< "$raw"

    [[ -z "${slot_pct:-}" ]] && return 1
    [[ -z "${slot_reset:-}" ]] && return 1
    [[ -z "${week_pct:-}" ]] && return 1
    [[ -z "${week_reset:-}" ]] && return 1

    printf '%s\t%s\t%s\t%s\n' "$slot_pct" "$slot_reset" "$week_pct" "$week_reset"
}

format_claude() {
    local raw
    raw=$(read_usage_status claude) || true

    if [[ -z "$raw" ]]; then
        show_fetch_error "Claude Usage" "データ取得に失敗しました"
        return
    fi

    local d_pct d_reset w_pct w_reset
    IFS=$'\t' read -r d_pct d_reset w_pct w_reset <<< "$raw"

    local d_bar w_bar
    d_bar=$(make_bar "$d_pct")
    w_bar=$(make_bar "$w_pct")

    cat <<MD
# Claude Usage

## 5時間枠
- **使用率**: ${d_pct}%
- **リセット**: ${d_reset}

${d_bar}

## 7日間枠
- **使用率**: ${w_pct}%
- **リセット**: ${w_reset}

${w_bar}

---

| 区間 | 使用率 | リセット |
|------|--------|----------|
| 5時間 | ${d_pct}% | ${d_reset} |
| 7日間 | ${w_pct}% | ${w_reset} |
MD
}

format_openai() {
    local codex_db="${HOME}/.codex/state_5.sqlite"
    if ! command -v sqlite3 >/dev/null 2>&1; then
        show_fetch_error "OpenAI (Codex) Usage" "sqlite3 が見つかりません"
        return
    fi

    if [[ ! -f "$codex_db" ]]; then
        show_fetch_error "OpenAI (Codex) Usage" "Codex CLIデータが見つかりません"
        return
    fi

    local now
    now=$(date +%s)
    local h5_ago=$((now - 5 * 3600))
    local d1_ago=$((now - 86400))
    local d7_ago=$((now - 7 * 86400))
    local active_ago=$((now - 1800))

    # Single query: all aggregates in one pass (7→1 sqlite3 invocation)
    local h5_tokens=0 h5_sessions=0 d1_tokens=0 d1_sessions=0 d7_tokens=0 d7_sessions=0 active=0
    local _result
    _result=$(sqlite3 -separator $'\t' "$codex_db" \
        "SELECT COALESCE(SUM(CASE WHEN updated_at>$h5_ago THEN tokens_used ELSE 0 END),0),\
COUNT(CASE WHEN updated_at>$h5_ago THEN 1 ELSE NULL END),\
COALESCE(SUM(CASE WHEN updated_at>$d1_ago THEN tokens_used ELSE 0 END),0),\
COUNT(CASE WHEN updated_at>$d1_ago THEN 1 ELSE NULL END),\
COALESCE(SUM(CASE WHEN updated_at>$d7_ago THEN tokens_used ELSE 0 END),0),\
COUNT(CASE WHEN updated_at>$d7_ago THEN 1 ELSE NULL END),\
COUNT(CASE WHEN updated_at>$active_ago THEN 1 ELSE NULL END)\
 FROM threads WHERE model_provider='openai';" 2>/dev/null) || _result=""
    if [[ -n "$_result" ]]; then
        IFS=$'\t' read -r h5_tokens h5_sessions d1_tokens d1_sessions d7_tokens d7_sessions active <<< "$_result"
    fi

    # Format token counts (K/M) — pure bash, no awk
    local h5_fmt d1_fmt d7_fmt
    h5_fmt=$(format_tokens "$h5_tokens")
    d1_fmt=$(format_tokens "$d1_tokens")
    d7_fmt=$(format_tokens "$d7_tokens")

    local status_raw h5_left h5_reset d7_left d7_reset
    status_raw=$(read_usage_status codex) || true
    if [[ -n "$status_raw" ]]; then
        IFS=$'\t' read -r h5_left h5_reset d7_left d7_reset <<< "$status_raw"
    else
        h5_left="--"
        h5_reset="--"
        d7_left="--"
        d7_reset="--"
    fi

    cat <<MD
# OpenAI (Codex) Usage

## トークン使用量

| 区間 | トークン | セッション数 |
|------|---------|-------------|
| 5時間 | ${h5_fmt} | ${h5_sessions} |
| 24時間 | ${d1_fmt} | ${d1_sessions} |
| 7日間 | ${d7_fmt} | ${d7_sessions} |

## ステータス
- **5時間残量**: ${h5_left}% (リセット: ${h5_reset})
- **7日間残量**: ${d7_left}% (リセット: ${d7_reset})
- **アクティブセッション** (30分内): ${active}
- **認証モード**: ChatGPT (Pro)
- **データソース**: Codex CLI ローカルDB + usage_monitor.sh
MD
}

format_tokens() {
    local tokens="$1"
    if (( tokens >= 1000000 )); then
        local _int=$(( tokens / 1000000 ))
        local _dec=$(( (tokens % 1000000 + 50000) / 100000 ))
        if (( _dec >= 10 )); then _int=$(( _int + 1 )); _dec=0; fi
        echo "${_int}.${_dec}M"
    elif (( tokens >= 1000 )); then
        echo "$(( (tokens + 500) / 1000 ))K"
    else
        echo "${tokens}"
    fi
}

make_bar() {
    local pct="$1"
    if [[ "$pct" == "ERR" || -z "$pct" ]]; then
        echo "\`[----------] N/A\`"
        return
    fi
    # Clamp pct to 0-100 range for safe bar rendering
    if (( pct < 0 )); then pct=0; fi
    if (( pct > 100 )); then pct=100; fi
    local filled=$(( pct / 10 ))
    local empty=$(( 10 - filled ))
    local bar=""
    for ((i = 0; i < filled; i++)); do bar+="█"; done
    for ((i = 0; i < empty; i++)); do bar+="░"; done
    echo "\`[${bar}] ${pct}%\`"
}

case "${1:-}" in
    claude) format_claude ;;
    openai) format_openai ;;
    *)      show_usage ;;
esac
