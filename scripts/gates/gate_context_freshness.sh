#!/usr/bin/env bash
# ============================================================
# gate_context_freshness.sh
# dashboardと同じ監視対象に対してlast_updated鮮度を自動チェックする
#
# Usage:
#   bash scripts/gates/gate_context_freshness.sh
#
# チェック内容:
#   scripts/context_freshness_check.sh --dashboard-warnings と同じ対象
#   （直近completed cmdがあるactive projectのcontext）のみを監視する
#   各context/*.mdの先頭コメントから last_updated を解析
#   フォーマット: <!-- last_updated: YYYY-MM-DD --> または
#                <!-- last_updated: YYYY-MM-DD cmd_XXX ... -->
#   基準日からの経過日数:
#     7日超 → WARN
#     14日超 → ALERT
#     last_updated未記載 → WARN（「未記載」と明示）
#
# Exit code: 0=全OK, 1=1つ以上ALERT, 2=WARNのみ(ALERTなし)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ROOT_DIR="${CONTEXT_FRESHNESS_ROOT:-$SCRIPT_DIR}"
CHECK_SCRIPT="${CONTEXT_FRESHNESS_CHECK_SCRIPT:-$ROOT_DIR/scripts/context_freshness_check.sh}"
NTFY_SCRIPT="${CONTEXT_FRESHNESS_NTFY_SCRIPT:-$ROOT_DIR/scripts/ntfy.sh}"
TODAY_OVERRIDE="${CONTEXT_FRESHNESS_TODAY:-}"
CACHE_TTL="${CONTEXT_FRESHNESS_GATE_CACHE_TTL:-2}"

HAS_ALERT=0
HAS_WARN=0
ALERT_LIST=()

emit_actionable() {
    local message="$1"
    local action="$2"
    echo "$message"
    echo "  action: $action"
}

if [[ -n "$TODAY_OVERRIDE" ]]; then
    TODAY_EPOCH=$(date -d "$TODAY_OVERRIDE" +%s 2>/dev/null) || {
        echo "WARN: CONTEXT_FRESHNESS_TODAY の日付形式不正: $TODAY_OVERRIDE"
        echo "  action: YYYY-MM-DD 形式に修正せよ。"
        exit 2
    }
else
    TODAY_EPOCH=$(date +%s)
fi

if [[ ! -f "$CHECK_SCRIPT" ]]; then
    echo "WARN: context_freshness_check.sh not found"
    echo "  action: scripts/context_freshness_check.sh を復旧せよ。"
    exit 2
fi

warnings_output() {
    local cache_file=""
    if [[ "${CONTEXT_FRESHNESS_GATE_DISABLE_CACHE:-0}" != "1" && "$CACHE_TTL" =~ ^[0-9]+$ && "$CACHE_TTL" -gt 0 ]]; then
        local root_key
        root_key="${ROOT_DIR//[^A-Za-z0-9._-]/_}"
        local today_key="${TODAY_OVERRIDE:-today}"
        local stale_key="${CONTEXT_STALE_DAYS:-7}"
        local sig_parts=()
        local path
        for path in \
            "$CHECK_SCRIPT" \
            "$ROOT_DIR/config/projects.yaml" \
            "$ROOT_DIR/context" \
            "$ROOT_DIR/context/cmd-chronicle.md" \
            "$ROOT_DIR/queue/archive/cmds"
        do
            if [[ -e "$path" ]]; then
                sig_parts+=("$(stat -c '%Y:%s' "$path" 2>/dev/null || printf '0:0')")
            else
                sig_parts+=("missing")
            fi
        done
        local sig
        sig="$(printf '%s|' "${sig_parts[@]}")"
        cache_file="/tmp/gate_context_freshness_${root_key}_${today_key}_${stale_key}_${sig//[^A-Za-z0-9._-]/_}.cache"
        local now cache_mtime
        now="$(date +%s)"
        if [[ -f "$cache_file" ]]; then
            cache_mtime="$(stat -c '%Y' "$cache_file" 2>/dev/null || printf 0)"
            if (( now - cache_mtime < CACHE_TTL )); then
                cat "$cache_file"
                return 0
            fi
        fi
    fi

    if [[ -n "$cache_file" ]]; then
        local tmp_cache="${cache_file}.$$"
        bash "$CHECK_SCRIPT" --dashboard-warnings > "$tmp_cache" 2>/dev/null
        mv "$tmp_cache" "$cache_file"
        cat "$cache_file"
    else
        bash "$CHECK_SCRIPT" --dashboard-warnings 2>/dev/null
    fi
}

declare -A seen_paths=()
target_rel_paths=()
while IFS= read -r rel_path; do
    [[ -n "$rel_path" ]] || continue
    if [[ -n "${seen_paths[$rel_path]:-}" ]]; then
        continue
    fi
    seen_paths["$rel_path"]=1
    target_rel_paths+=("$rel_path")
done < <(
    warnings_output \
        | sed -nE 's/^WARN: ([^ ]+) last_updated .*$/\1/p'
)

if [[ "${#target_rel_paths[@]}" -eq 0 ]]; then
    echo "--- 総合判定: OK ---"
    exit 0
fi

for rel_path in "${target_rel_paths[@]}"; do
    file="$ROOT_DIR/$rel_path"
    [[ -f "$file" ]] || continue

    basename_file=$(basename "$file")
    last_updated=""
    line_count=0
    while IFS= read -r line && (( line_count < 10 )); do
        line_count=$((line_count + 1))
        if [[ "$line" =~ last_updated:[[:space:]]*([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
            last_updated="${BASH_REMATCH[1]}"
            break
        fi
    done < "$file"

    if [[ -z "$last_updated" ]]; then
        emit_actionable \
            "WARN: ${basename_file} (last_updated 未記載)" \
            "${basename_file} に <!-- last_updated: YYYY-MM-DD --> を追記せよ。"
        HAS_WARN=1
        continue
    fi

    file_epoch=$(date -d "$last_updated" +%s 2>/dev/null) || {
        emit_actionable \
            "WARN: ${basename_file} (last_updated日付パース失敗: ${last_updated})" \
            "${basename_file} の last_updated 日付形式を YYYY-MM-DD に修正せよ。"
        HAS_WARN=1
        continue
    }

    days_ago=$(( (TODAY_EPOCH - file_epoch) / 86400 ))

    if [[ "$days_ago" -gt 14 ]]; then
        emit_actionable \
            "ALERT: ${basename_file} (${days_ago}日前更新)" \
            "${basename_file} の内容を確認し、最新情報へ更新せよ。"
        HAS_ALERT=1
        ALERT_LIST+=("${basename_file}(${days_ago}日)")
    elif [[ "$days_ago" -gt 7 ]]; then
        emit_actionable \
            "WARN: ${basename_file} (${days_ago}日前更新)" \
            "${basename_file} の鮮度を確認し、必要なら更新せよ。"
        HAS_WARN=1
    else
        echo "OK: ${basename_file} (${days_ago}日前更新)"
    fi
done

if [[ "$HAS_ALERT" -gt 0 && "${#ALERT_LIST[@]}" -gt 0 && -f "$NTFY_SCRIPT" ]]; then
    alert_summary=$(IFS=', '; echo "${ALERT_LIST[*]}")
    bash "$NTFY_SCRIPT" "【将軍】context鮮度ALERT: ${alert_summary}" >/dev/null 2>&1 || true
fi

if [[ "$HAS_ALERT" -gt 0 ]]; then
    echo "--- 総合判定: ALERT ---"
    exit 1
elif [[ "$HAS_WARN" -gt 0 ]]; then
    echo "--- 総合判定: WARN ---"
    exit 2
else
    echo "--- 総合判定: OK ---"
    exit 0
fi
