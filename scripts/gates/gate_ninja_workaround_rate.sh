#!/bin/bash
# semantic-links: [[ゲート品質統合フレームワーク]]
# gate_ninja_workaround_rate.sh — 忍者別workaround率を集計
# 目的: karo_workarounds.yamlのWAログ直近N件から忍者別workaround件数/率を出力
# Usage: bash scripts/gates/gate_ninja_workaround_rate.sh [--last N] [--quiet] [--ninja NAME]
#   --last N     : WAログ直近N件を対象 (default: 30)
#   --quiet      : サマリ1行のみ出力 (gate_karo_startup.sh統合用)
#   --ninja NAME : 指定忍者のみの履歴を表示 (SG9用)
#   NINJA_WA_ACTIVE_DAYS: 未解消WAを現行警告に含める日数窓 (default: 7, 0=無効)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$SCRIPT_DIR/scripts/lib/agent_config.sh" 2>/dev/null || true
_NINJA_LIST="$(get_ninja_names 2>/dev/null || echo 'hayate kagemaru hanzo saizo kotaro tobisaru')"

_gate_wa_self="${BASH_SOURCE[0]}"
[[ "$_gate_wa_self" != /* ]] && _gate_wa_self="$PWD/$_gate_wa_self"
SCRIPT_DIR="${_gate_wa_self%/scripts/gates/gate_ninja_workaround_rate.sh}"
unset _gate_wa_self
WA_FILE="$SCRIPT_DIR/logs/karo_workarounds.yaml"
GATE_LOG="$SCRIPT_DIR/logs/gate_metrics.log"
REPORTS_DIR="${NINJA_WA_REPORTS_DIR:-$SCRIPT_DIR/queue/reports}"

LAST_N=30
RECENT_N="${NINJA_WA_RECENT_N:-10}"
ACTIVE_DAYS="${NINJA_WA_ACTIVE_DAYS:-7}"
NOW_EPOCH="${NINJA_WA_NOW_EPOCH:-}"
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
_WA_ROOT_KEY="$(printf '%s' "$SCRIPT_DIR" | cksum | awk '{print $1}')"
_WA_CACHE="/tmp/shogun_wa_rate_cache_${_WA_ROOT_KEY}_${NINJA_FILTER:-all}_${LAST_N}_${RECENT_N}_${ACTIVE_DAYS}_${NOW_EPOCH:-now}.txt"
_WA_MTIME=$(stat -c%Y "$WA_FILE" 2>/dev/null || echo 0)
_GATE_MTIME=$(stat -c%Y "$GATE_LOG" 2>/dev/null || echo 0)
_WA_SELF_MTIME=$(stat -c%Y "${BASH_SOURCE[0]}" 2>/dev/null || echo 0)
# 一次分母(terminal task/report)のキャッシュ署名: report YAML群のfile:mtime一覧をハッシュ化
_REPORTS_SIG="0"
if [ -d "$REPORTS_DIR" ]; then
    _REPORTS_SIG=$(find "$REPORTS_DIR" -maxdepth 2 -name "*.yaml" 2>/dev/null | LC_ALL=C sort | xargs -r stat -c '%n:%Y' 2>/dev/null | cksum | tr ' ' '_')
fi
_WA_CACHE_VERSION="5"
_WA_CACHE_SIG="${_WA_CACHE_VERSION}:${_WA_MTIME}:${_GATE_MTIME}:${_WA_SELF_MTIME}:${_REPORTS_SIG}"
_WA_CACHED_SIG=""
if [ -f "$_WA_CACHE" ]; then
    IFS= read -r _WA_CACHED_SIG < "$_WA_CACHE" || _WA_CACHED_SIG=""
fi
if [ "$_WA_CACHE_SIG" = "$_WA_CACHED_SIG" ] && [ -f "$_WA_CACHE" ]; then
    sed '1d' "$_WA_CACHE"
    exit 0
fi

# ─── 一次分母構築: terminal task/report実績 index (cmd_id -> 最新report YAMLのworker_id) ───
# AC2: WAログ自身のninja:system偏在バイアスを迂回する一次ソース。status:pending(未提出)は除外。
_REPORT_INDEX="/tmp/shogun_wa_report_index_$$"
_REPORT_INDEX_RAW="/tmp/shogun_wa_report_index_raw_$$"
: > "$_REPORT_INDEX_RAW"
if [ -d "$REPORTS_DIR" ]; then
    shopt -s nullglob
    _report_files=("$REPORTS_DIR"/*.yaml "$REPORTS_DIR"/archive/*.yaml)
    shopt -u nullglob
    for _rf in "${_report_files[@]}"; do
        case "$_rf" in *.bak|*.lock) continue ;; esac
        [ -f "$_rf" ] || continue
        _worker=$(grep -m1 '^worker_id:' "$_rf" 2>/dev/null | sed -E "s/^worker_id:[[:space:]]*//; s/^['\"]//; s/['\"][[:space:]]*\$//")
        _cmd=$(grep -m1 '^parent_cmd:' "$_rf" 2>/dev/null | sed -E "s/^parent_cmd:[[:space:]]*//; s/^['\"]//; s/['\"][[:space:]]*\$//")
        _rstatus=$(grep -m1 '^status:' "$_rf" 2>/dev/null | sed -E "s/^status:[[:space:]]*//; s/^['\"]//; s/['\"][[:space:]]*\$//")
        [ -n "$_worker" ] && [ -n "$_cmd" ] || continue
        [ "$_rstatus" = "pending" ] && continue
        _mtime=$(stat -c%Y "$_rf" 2>/dev/null || echo 0)
        printf '%s\t%s\t%s\n' "$_mtime" "$_cmd" "$_worker" >> "$_REPORT_INDEX_RAW"
    done
fi
if [ -s "$_REPORT_INDEX_RAW" ]; then
    # 同一cmd_idに複数報告(report archive移動/failed後RC再提出)がある場合はmtime最新を採用
    LC_ALL=C sort -t "$(printf '\t')" -k2,2 -k1,1n "$_REPORT_INDEX_RAW" | awk -F'\t' '{ w[$2]=$3 } END { for (c in w) print c "\t" w[c] }' > "$_REPORT_INDEX"
else
    : > "$_REPORT_INDEX"
fi
rm -f "$_REPORT_INDEX_RAW"

# 高速化: mktemp(13ms)をPID固定パスに変更
_WA_TMP="/tmp/shogun_wa_wrk_$$"
awk -v quiet="$QUIET" -v last_n="$LAST_N" -v recent_n="$RECENT_N" -v active_days="$ACTIVE_DAYS" -v now_epoch="$NOW_EPOCH" -v ninja_filter="$NINJA_FILTER" -v ninja_list="$_NINJA_LIST" -v gate_log="$GATE_LOG" -v report_index_file="$_REPORT_INDEX" '
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
function timestamp_epoch(s, raw) {
    raw = unquote(s)
    if (raw !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/) return 0
    return mktime(substr(raw, 1, 4) " " substr(raw, 6, 2) " " substr(raw, 9, 2) " " substr(raw, 12, 2) " " substr(raw, 15, 2) " " substr(raw, 18, 2))
}
function timestamp_is_active(ts) {
    if (active_days + 0 <= 0) return 1
    if (ts + 0 <= 0) return 1
    return (ts >= active_cutoff) ? 1 : 0
}
function extract_ninja(explicit, detail, root_cause, issue, workaround_detail, text) {
    explicit = trim(explicit)
    if (index(" " ninja_list " ", " " explicit " ") > 0) {
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
function effective_category(cat, detail, root_cause, issue, workaround_detail, text) {
    text = tolower(detail " " root_cause " " issue " " workaround_detail)
    if (cat == "commit_missing") {
        if (text ~ /commit_hash|files_modified|command_files_modified_mismatch|偵察commit不要|commit不要|binary_checks\.commit|報告yaml.*commit|report.*commit/) {
            return "report_yaml_format"
        }
        if (text !~ /commit.*漏れ|commit.*なし|commit.*missing|コミット.*漏れ|コミット.*なし|未commit|未コミット|untracked|modified/) {
            return "uncategorized"
        }
    }
    return cat
}
function is_known_ninja(name) {
    return (index(" " ninja_list " ", " " name " ") > 0) ? 1 : 0
}
function is_pre_execution(cat, detail, root_cause,    text) {
    # AC3: 配備前BLOCK/家老task契約不備等でworkerが着手していないWAは
    # 忍者責任率(worker-attributable)へ算入しない。executor exposureとして別集計する。
    if (cat == "deploy_contract") return 1
    text = tolower(detail " " root_cause)
    if (text ~ /配備前.*block|初回block|契約不足|契約不備|worker.*未着手|着手していない|pre-?deploy.*block|task契約不備|配備契約/) return 1
    return 0
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
    current_resolved = 0
    current_ts = 0
    current_started = 0
}
function assign_pair(key, value) {
    value = unquote(value)
    if (key == "cmd_id" || key == "cmd") current_cmd = value
    else if (key == "ninja") current_ninja = value
    else if (key == "category") current_category = (value == "" ? "uncategorized" : value)
    else if (key == "timestamp" || key == "created_at") current_ts = timestamp_epoch(value)
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
    } else if (key == "resolved_by_cmd") {
        current_resolved = (value != "") ? 1 : 0
    }
}
function flush_current(    ninja, wa) {
    if (!current_started) return
    ninja = extract_ninja(current_ninja, current_detail, current_root_cause, current_issue, current_workaround_detail)
    # AC2: WAログ自身がninja:systemへ寄せる自己選択バイアス(clean完了のauto capture)を
    # 一次分母(terminal task/report実績=report_ninja index)で復元する。
    if (!is_known_ninja(ninja) && (current_cmd in report_ninja)) {
        ninja = report_ninja[current_cmd]
    }
    wa = current_has_wa ? current_wa : (current_has_kwa ? current_kwa : 0)
    entry_count++
    entry_ninja[entry_count] = ninja
    entry_wa[entry_count] = wa
    entry_active_wa[entry_count] = (wa && !current_resolved && timestamp_is_active(current_ts)) ? 1 : 0
    entry_resolved[entry_count] = current_resolved
    entry_cat[entry_count] = effective_category(current_category, current_detail, current_root_cause, current_issue, current_workaround_detail)
    entry_cmd[entry_count] = (current_cmd == "" ? "?" : current_cmd)
    entry_ts[entry_count] = current_ts
    entry_excluded[entry_count] = is_pre_execution(current_category, current_detail, current_root_cause)
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
    current_epoch = (now_epoch != "") ? now_epoch + 0 : systime()
    active_cutoff = current_epoch - ((active_days + 0) * 86400)
    # AC2: 一次分母 index (cmd_id -> 最新report YAMLのworker_id) の読込
    if (report_index_file != "") {
        while ((getline rline < report_index_file) > 0) {
            rn = split(rline, rf, "\t")
            if (rn >= 2 && rf[1] != "" && rf[2] != "") {
                report_ninja[rf[1]] = rf[2]
            }
        }
        close(report_index_file)
    }
    has_gate = 0
    if (gate_log != "") {
        cmd = "test -f \"" gate_log "\" && tac \"" gate_log "\""
        while ((cmd | getline line) > 0) {
            n = split(line, f, "\t")
            if (f[3] == "CLEAR" && !seen_clear[f[2]]++) {
                clear_set[f[2]] = 1
                clear_order[++clear_count] = f[2]
                if (clear_count <= recent_n) recent_clear_set[f[2]] = 1
                if (clear_count >= last_n) break
            }
        }
        close(cmd)
        has_gate = (clear_count > 0) ? 1 : 0
    }
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

    # This gate measures the workaround log itself.  Filtering by recent
    # gate_metrics CLEAR commands hides fresh WA records whose parent cmd has
    # not been CLEARed yet, which makes active ninja WA look like "all clean".
    start = (entry_count > last_n) ? entry_count - last_n + 1 : 1
    total = entry_count - start + 1
    recent_start = (entry_count > recent_n) ? entry_count - recent_n + 1 : 1

    # ─── 一次分母(terminal task/report) + WAログ(worker-attributable)の統合集計 ───
    # AC2: (ninja, cmd) 単位でdedupし、一次分母(report_ninja)とWAログを union して分母とする。
    #      同一cmdの重複WAは1件に集約する(AC4)。report/task不在のactive未解消WAは
    #      unit_seen/unit_wa双方へ1件のみ算入されるため自然にfail-closedとなる。
    # AC3: 配備前BLOCK等でworkerが未着手のWAはexposure_flagへ分離し、
    #      report実績が別途あれば正規のunitへ吸収、なければ責任率から除外する。
    for (i = start; i <= entry_count; i++) {
        ninja = entry_ninja[i]
        if (!is_known_ninja(ninja)) continue
        ckey = ninja SUBSEP entry_cmd[i]
        if (entry_excluded[i]) {
            if (!(ckey in unit_seen)) exposure_flag[ckey] = 1
            continue
        }
        delete exposure_flag[ckey]
        unit_seen[ckey] = 1
        if (entry_active_wa[i]) {
            unit_wa[ckey] = 1
            unit_wa_cat[ckey] = entry_cat[i]
            if (i >= recent_start) unit_recent_wa[ckey] = 1
            if (!(ckey in unit_wa_order_seen)) {
                unit_wa_order_seen[ckey] = 1
                wa_unit_order[++wa_unit_order_count] = ckey
            }
        }
    }
    for (rcmd in report_ninja) {
        ninja = report_ninja[rcmd]
        if (!is_known_ninja(ninja)) continue
        ckey = ninja SUBSEP rcmd
        if (!(ckey in unit_seen)) {
            unit_seen[ckey] = 1
            delete exposure_flag[ckey]
        }
    }
    for (ckey in unit_seen) {
        split(ckey, ckparts, SUBSEP)
        ninja = ckparts[1]
        if (!(ninja in stats_seen)) {
            stats_seen[ninja] = 1
            ordered_names[++ordered_count] = ninja
        }
        stats_total[ninja]++
        grand_denom++
        if (ckey in unit_wa) {
            stats_wa[ninja]++
            total_wa++
            if (ckey in unit_recent_wa) stats_recent_wa[ninja]++
        }
    }
    for (ckey in exposure_flag) {
        split(ckey, ckparts, SUBSEP)
        exposure_count[ckparts[1]]++
        exposure_total++
    }
    for (i = 1; i <= wa_unit_order_count; i++) {
        ckey = wa_unit_order[i]
        split(ckey, ckparts, SUBSEP)
        if (ninja_filter != "" && ckparts[1] == ninja_filter) {
            filter_wa_count++
            filter_cmd[filter_wa_count] = ckparts[2]
            filter_cat[filter_wa_count] = unit_wa_cat[ckey]
        }
    }

    # ─── category別集計（直近last_n件、WA=true のみ）───
    for (i = start; i <= entry_count; i++) {
        if (entry_active_wa[i] && entry_cat[i] != "" && entry_cat[i] != "clean" && !clear_set[entry_cmd[i]]) {
            wa_cat[entry_cat[i]]++
        }
    }
    cat_warn_line = ""
    for (wa_cat_key in wa_cat) {
        if (wa_cat[wa_cat_key] >= 3) {
            if (cat_warn_line != "") cat_warn_line = cat_warn_line ", "
            cat_warn_line = cat_warn_line sprintf("%s:%d件", wa_cat_key, wa_cat[wa_cat_key])
        }
    }

    if (ninja_filter != "") {
        ninja_total = stats_total[ninja_filter] + 0
        ninja_wa = stats_wa[ninja_filter] + 0
        printf "=== %s workaround履歴 (WAログ直近%d件中) ===\n", ninja_filter, total
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
        if (cat_warn_line != "") {
            print "  ★ WARN: category集計(WAログ直近" last_n "件中3件以上) — " cat_warn_line
        }
        if (exposure_count[ninja_filter] > 0) {
            printf "  OK: 除外(pre-execution/未着手, 忍者責任率対象外): %d件\n", exposure_count[ninja_filter]
        }
        exit 0
    }

    for (i = 1; i <= ordered_count; i++) {
        name = ordered_names[i]
        if (name != "unknown" && stats_total[name] >= 2) {
            rate = stats_wa[name] / stats_total[name] * 100
            if (stats_recent_wa[name] == 0) {
                if (stats_wa[name] > 0) {
                    stale[++stale_count] = sprintf("%s(%d/%d)", name, stats_wa[name], stats_total[name])
                }
            } else if (rate > 50) {
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
            printf "  忍者別workaround(WAログ直近%d件): %s\n", total, line
        } else {
            printf "  忍者別workaround(WAログ直近%d件): 全員clean\n", total
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
        if (cat_warn_line != "") {
            print "  WARN: category集計(WAログ直近" last_n "件中3件以上) — " cat_warn_line
        }
        if (stale_count > 0) {
            line = ""
            for (i = 1; i <= stale_count; i++) {
                if (line != "") line = line ", "
                line = line stale[i]
            }
            print "  OK: stale WA履歴は閾値判定外(WAログ直近" recent_n "件clean) — " line
        }
        if (exposure_total > 0) {
            line = ""
            for (name in exposure_count) {
                if (line != "") line = line ", "
                line = line sprintf("%s(%d)", name, exposure_count[name])
            }
            print "  OK: 除外(pre-execution/未着手, 忍者責任率対象外) — " line
        }
        exit 0
    }

    printf "=== 忍者別workaround率 (WAログ直近%d件) ===\n\n", total
    printf "%-12s %7s %8s %7s\n", "忍者", "WA件数", "担当件数", "WA率"
    print "--------------------------------------"
    for (i = 1; i <= ordered_count; i++) {
        name = ordered_names[i]
        rate = (stats_total[name] > 0) ? (stats_wa[name] / stats_total[name] * 100) : 0
        printf "%-12s %7d %8d %6.1f%%\n", name, stats_wa[name], stats_total[name], rate
    }
    print "--------------------------------------"
    printf "%-12s %7d %8d %6.1f%%\n\n", "合計", total_wa, grand_denom, (grand_denom > 0 ? total_wa / grand_denom * 100 : 0)
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
    if (stale_count > 0) {
        printf "  OK: stale WA履歴は閾値判定外(WAログ直近%d件clean): ", recent_n
        for (i = 1; i <= stale_count; i++) {
            if (i > 1) printf ", "
            printf "%s", stale[i]
        }
        printf "\n"
    }
    if (cat_warn_line != "") {
        printf "\nWARN: category集計(WAログ直近%d件中3件以上): %s\n", total, cat_warn_line
    }
    if (exposure_total > 0) {
        line = ""
        for (name in exposure_count) {
            if (line != "") line = line ", "
            line = line sprintf("%s(%d)", name, exposure_count[name])
        }
        print "  OK: 除外(pre-execution/未着手, 忍者責任率対象外) — " line
    }
}
' "$WA_FILE" > "$_WA_TMP" 2>/dev/null || true

{
    echo "$_WA_CACHE_SIG"
    cat "$_WA_TMP"
} > "$_WA_CACHE" 2>/dev/null || true
cat "$_WA_TMP"
rm -f "$_WA_TMP" "$_REPORT_INDEX"
