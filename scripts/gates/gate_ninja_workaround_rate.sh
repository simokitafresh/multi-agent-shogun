#!/bin/bash
# gate_ninja_workaround_rate.sh — 忍者別workaround率を集計
# 目的: karo_workarounds.yamlから直近N cmd分の忍者別workaround件数/率を出力
# Usage: bash scripts/gates/gate_ninja_workaround_rate.sh [--last N] [--quiet] [--ninja NAME]
#   --last N     : 直近N件を対象 (default: 30)
#   --quiet      : サマリ1行のみ出力 (gate_karo_startup.sh統合用)
#   --ninja NAME : 指定忍者のみの履歴を表示 (SG9用)

set -e

_gate_wa_self="${BASH_SOURCE[0]}"
[[ "$_gate_wa_self" != /* ]] && _gate_wa_self="$PWD/$_gate_wa_self"
SCRIPT_DIR="${_gate_wa_self%/scripts/gates/gate_ninja_workaround_rate.sh}"
unset _gate_wa_self
WA_FILE="$SCRIPT_DIR/logs/karo_workarounds.yaml"

LAST_N=30
QUIET=false
NINJA_FILTER=""

while [ $# -gt 0 ]; do
    case "$1" in
        --last) LAST_N="$2"; shift 2 ;;
        --quiet) QUIET=true; shift ;;
        --ninja) NINJA_FILTER="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [ ! -f "$WA_FILE" ]; then
    if [ "$QUIET" = true ]; then
        echo "  workaround集計: データなし (karo_workarounds.yaml不在)"
    else
        echo "ERROR: $WA_FILE が存在しない"
    fi
    exit 0
fi

# WSL2 NTFS最適化: python3起動(150ms)をmtimeキャッシュで回避
_WA_CACHE="/tmp/shogun_wa_rate_cache_${NINJA_FILTER:-all}_${LAST_N}.txt"
_WA_MTIME=$(stat -c%Y "$WA_FILE" 2>/dev/null || echo 0)
_WA_CACHED_MTIME=-1
if [ -f "$_WA_CACHE" ]; then
    IFS= read -r _WA_CACHED_MTIME < "$_WA_CACHE" || _WA_CACHED_MTIME=-1
fi
if [ "$_WA_MTIME" = "$_WA_CACHED_MTIME" ] && [ -f "$_WA_CACHE" ]; then
    awk 'NR > 1 { print }' "$_WA_CACHE"
    exit 0
fi

_WA_TMP=$(mktemp /tmp/shogun_wa_wrk.XXXXXX)
awk -v quiet="$QUIET" -v last_n="$LAST_N" -v ninja_filter="$NINJA_FILTER" '
function trim(s) {
    sub(/^[ \t\r\n]+/, "", s)
    sub(/[ \t\r\n]+$/, "", s)
    return s
}
function unquote(s) {
    s = trim(s)
    if (length(s) >= 2) {
        if (substr(s, 1, 1) == "\"" && substr(s, length(s), 1) == "\"") {
            s = substr(s, 2, length(s) - 2)
            gsub(/\\"/, "\"", s)
        } else if (substr(s, 1, 1) == "'"'"'" && substr(s, length(s), 1) == "'"'"'") {
            s = substr(s, 2, length(s) - 2)
        }
    }
    return trim(s)
}
function parse_bool(s, lower) {
    lower = tolower(unquote(s))
    return (lower == "true" || lower == "yes") ? 1 : 0
}
function extract_ninja(explicit, detail, root_cause, issue, workaround_detail, text) {
    explicit = trim(explicit)
    if (explicit == "hayate" || explicit == "kagemaru" || explicit == "hanzo" || explicit == "saizo" || explicit == "kotaro" || explicit == "tobisaru") {
        return explicit
    }

    text = tolower(detail " " root_cause " " issue " " workaround_detail)
    if (index(text, "疾風") > 0) return "hayate"
    if (index(text, "影丸") > 0) return "kagemaru"
    if (index(text, "半蔵") > 0) return "hanzo"
    if (index(text, "才蔵") > 0) return "saizo"
    if (index(text, "小太郎") > 0) return "kotaro"
    if (index(text, "飛猿") > 0) return "tobisaru"
    if (index(text, "hayate") > 0) return "hayate"
    if (index(text, "kagemaru") > 0) return "kagemaru"
    if (index(text, "hanzo") > 0) return "hanzo"
    if (index(text, "saizo") > 0) return "saizo"
    if (index(text, "kotaro") > 0) return "kotaro"
    if (index(text, "tobisaru") > 0) return "tobisaru"
    return "unknown"
}
function reset_current() {
    current_cmd = ""
    current_ninja = ""
    current_category = "uncategorized"
    current_detail = ""
    current_root_cause = ""
    current_issue = ""
    current_workaround_detail = ""
    current_has_wa = 0
    current_wa = 0
    current_has_kwa = 0
    current_kwa = 0
    current_started = 0
}
function assign_pair(key, value) {
    value = unquote(value)
    if (key == "cmd_id" || key == "cmd") current_cmd = value
    else if (key == "ninja") current_ninja = value
    else if (key == "category") current_category = (value == "" ? "uncategorized" : value)
    else if (key == "detail") current_detail = value
    else if (key == "root_cause") current_root_cause = value
    else if (key == "issue") current_issue = value
    else if (key == "workaround_detail") current_workaround_detail = value
    else if (key == "workaround") {
        current_has_wa = 1
        current_wa = parse_bool(value)
    } else if (key == "karo_workaround") {
        current_has_kwa = 1
        current_kwa = parse_bool(value)
    }
}
function flush_current(    ninja, wa) {
    if (!current_started) return
    ninja = extract_ninja(current_ninja, current_detail, current_root_cause, current_issue, current_workaround_detail)
    wa = current_has_wa ? current_wa : (current_has_kwa ? current_kwa : 0)
    entry_count++
    entry_ninja[entry_count] = ninja
    entry_wa[entry_count] = wa
    entry_cat[entry_count] = current_category
    entry_cmd[entry_count] = (current_cmd == "" ? "?" : current_cmd)
    reset_current()
}
function sort_names(arr, n,    i, j, tmp) {
    for (i = 1; i <= n; i++) {
        for (j = i + 1; j <= n; j++) {
            if (stats_wa[arr[j]] > stats_wa[arr[i]] || (stats_wa[arr[j]] == stats_wa[arr[i]] && arr[j] < arr[i])) {
                tmp = arr[i]
                arr[i] = arr[j]
                arr[j] = tmp
            }
        }
    }
}
BEGIN {
    quiet_flag = (quiet == "true")
    reset_current()
}
/^workarounds:[[:space:]]*$/ { next }
/^- [A-Za-z0-9_]+:[[:space:]]*/ || /^  - [A-Za-z0-9_]+:[[:space:]]*/ {
    flush_current()
    current_started = 1
    line = $0
    sub(/^  - /, "", line)
    sub(/^- /, "", line)
    key = line
    sub(/:.*/, "", key)
    value = line
    sub(/^[^:]+:[[:space:]]*/, "", value)
    assign_pair(key, value)
    next
}
/^[[:space:]]+[A-Za-z0-9_]+:[[:space:]]*/ {
    if (!current_started) next
    line = trim($0)
    key = line
    sub(/:.*/, "", key)
    value = line
    sub(/^[^:]+:[[:space:]]*/, "", value)
    assign_pair(key, value)
    next
}
END {
    flush_current()

    if (entry_count == 0) {
        if (quiet_flag) print "  忍者別workaround: データなし"
        else print "対象エントリなし"
        exit 0
    }

    start = (entry_count > last_n) ? entry_count - last_n + 1 : 1
    total = entry_count - start + 1

    for (i = start; i <= entry_count; i++) {
        ninja = entry_ninja[i]
        if (!(ninja in stats_seen)) {
            stats_seen[ninja] = 1
            ordered_names[++ordered_count] = ninja
        }
        stats_total[ninja]++
        if (entry_wa[i]) {
            stats_wa[ninja]++
            total_wa++
            if (ninja_filter != "" && ninja == ninja_filter) {
                filter_wa_count++
                filter_cmd[filter_wa_count] = entry_cmd[i]
                filter_cat[filter_wa_count] = entry_cat[i]
            }
        }
    }

    if (ninja_filter != "") {
        ninja_total = stats_total[ninja_filter] + 0
        ninja_wa = stats_wa[ninja_filter] + 0
        printf "=== %s workaround履歴 (直近%d件中) ===\n", ninja_filter, total
        if (ninja_total == 0) {
            print "  担当件数: 0 — 対象期間にエントリなし"
            exit 0
        }

        rate = (ninja_total > 0) ? (ninja_wa / ninja_total * 100) : 0
        printf "  担当件数: %d  WA件数: %d  WA率: %.1f%%\n", ninja_total, ninja_wa, rate
        if (filter_wa_count > 0) {
            print "  直近workaround詳細:"
            detail_start = (filter_wa_count > 5) ? filter_wa_count - 4 : 1
            for (i = detail_start; i <= filter_wa_count; i++) {
                printf "    - %s: %s\n", filter_cmd[i], filter_cat[i]
            }
        } else {
            print "  workaroundなし: clean"
        }
        exit 0
    }

    for (i = 1; i <= ordered_count; i++) {
        name = ordered_names[i]
        if (name != "unknown" && stats_total[name] >= 2) {
            rate = stats_wa[name] / stats_total[name] * 100
            if (rate > 50) {
                alert[++alert_count] = sprintf("%s(%.0f%%)", name, rate)
                alert_detail[++alert_detail_count] = sprintf("%s — WA率%.0f%% (%d/%d件) [閾値50%%超]", name, rate, stats_wa[name], stats_total[name])
            } else if (rate > 30) {
                warn[++warn_count] = sprintf("%s(%.0f%%)", name, rate)
                warn_detail[++warn_detail_count] = sprintf("%s — WA率%.0f%% (%d/%d件) [閾値30%%超]", name, rate, stats_wa[name], stats_total[name])
            }
        }
        if (stats_wa[name] > 0) ranked[++ranked_count] = name
    }

    gate_level = (alert_count > 0) ? "ALERT" : ((warn_count > 0) ? "WARN" : "OK")
    sort_names(ordered_names, ordered_count)
    sort_names(ranked, ranked_count)

    if (quiet_flag) {
        if (ranked_count > 0) {
            line = ""
            for (i = 1; i <= ranked_count; i++) {
                name = ranked[i]
                if (line != "") line = line ", "
                line = line sprintf("%s:%d/%d", name, stats_wa[name], stats_total[name])
            }
            printf "  忍者別workaround(直近%d件): %s\n", total, line
        } else {
            printf "  忍者別workaround(直近%d件): 全員clean\n", total
        }
        if (alert_count > 0) {
            line = ""
            for (i = 1; i <= alert_count; i++) {
                if (line != "") line = line ", "
                line = line alert[i]
            }
            print "  ALERT: WA率50%超 — " line
        } else if (warn_count > 0) {
            line = ""
            for (i = 1; i <= warn_count; i++) {
                if (line != "") line = line ", "
                line = line warn[i]
            }
            print "  WARN: WA率30%超 — " line
        }
        exit 0
    }

    printf "=== 忍者別workaround率 (直近%d件) ===\n\n", total
    printf "%-12s %7s %8s %7s\n", "忍者", "WA件数", "担当件数", "WA率"
    print "--------------------------------------"
    for (i = 1; i <= ordered_count; i++) {
        name = ordered_names[i]
        rate = (stats_total[name] > 0) ? (stats_wa[name] / stats_total[name] * 100) : 0
        printf "%-12s %7d %8d %6.1f%%\n", name, stats_wa[name], stats_total[name], rate
    }
    print "--------------------------------------"
    printf "%-12s %7d %8d %6.1f%%\n\n", "合計", total_wa, total, (total > 0 ? total_wa / total * 100 : 0)
    print "判定: " gate_level
    if (alert_detail_count > 0) {
        for (i = 1; i <= alert_detail_count; i++) print "  ALERT: " alert_detail[i]
    }
    if (warn_detail_count > 0) {
        for (i = 1; i <= warn_detail_count; i++) print "  WARN: " warn_detail[i]
    }
    if (alert_detail_count == 0 && warn_detail_count == 0) {
        print "  全員clean: 閾値超過なし (サンプル2件未満の忍者は除外)"
    }
}
' "$WA_FILE" > "$_WA_TMP" 2>/dev/null || true

{
    echo "$_WA_MTIME"
    cat "$_WA_TMP"
} > "$_WA_CACHE" 2>/dev/null || true
cat "$_WA_TMP"
rm -f "$_WA_TMP"
