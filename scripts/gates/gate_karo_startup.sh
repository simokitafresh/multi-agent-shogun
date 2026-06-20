#!/bin/bash
# semantic-links: [[ゲート品質統合フレームワーク]]
# gate_karo_startup.sh — 家老セッション起動時の全チェックを一括実行
# 目的: 5項目を一括チェックし、deepdive必読を自動化×強制
# Usage: bash scripts/gates/gate_karo_startup.sh
# 参考: gate_shogun_startup.sh（構造踏襲）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# L821: ハードコード忍者名を排除。get_ninja_namesで動的取得
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/agent_config.sh" 2>/dev/null || true
_KARO_NINJA_NAMES="$(get_ninja_names 2>/dev/null || echo 'hayate kagemaru hanzo saizo kotaro tobisaru')"

overall="OK"
alerts=()
STARTUP_STDERR_LOG="$SCRIPT_DIR/logs/gate_karo_startup_stderr.log"
STARTUP_ALERT_HISTORY="$SCRIPT_DIR/logs/karo_startup_alert_history.tsv"
STARTUP_WARN_STREAK_THRESHOLD="${STARTUP_WARN_STREAK_THRESHOLD:-3}"

log_startup_stderr_file() {
    local label="$1"
    local stderr_file="$2"
    local line

    [ -s "$stderr_file" ] || return 0
    mkdir -p "$(dirname "$STARTUP_STDERR_LOG")" 2>/dev/null || true
    while IFS= read -r line; do
        printf '%s %s: %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$label" "$line" >> "$STARTUP_STDERR_LOG" || true
    done < "$stderr_file"
}

karo_startup_extract_ctx_pct() {
    local output="$1"
    local ctx_num remaining

    ctx_num=$(printf '%s\n' "$output" | grep -oE 'CTX:[0-9]+%' | tail -1 | grep -oE '[0-9]+' || true)
    if [ -n "$ctx_num" ]; then
        printf '%s%%\n' "$ctx_num"
        return 0
    fi

    ctx_num=$(printf '%s\n' "$output" | grep -oE 'Context [0-9]+%' | tail -1 | grep -oE '[0-9]+' || true)
    if [ -n "$ctx_num" ]; then
        printf '%s%%\n' "$ctx_num"
        return 0
    fi

    remaining=$(printf '%s\n' "$output" | grep -oE '[0-9]+% context left' | tail -1 | grep -oE '[0-9]+' || true)
    if [ -n "$remaining" ]; then
        printf '%s%%\n' "$((100 - remaining))"
        return 0
    fi

    return 1
}

phase_guide_cached() {
    local source_file="${1:?source file required}"
    local cache_name="${2:?cache name required}"
    local cache_file="/tmp/${cache_name}.cache"
    local cache_sig current_sig

    [[ -f "$source_file" ]] || return 1
    current_sig="$(stat -c '%Y:%s' "$source_file" 2>/dev/null || echo '')"
    if [[ -f "$cache_file" ]]; then
        IFS= read -r cache_sig < "$cache_file" || cache_sig=""
        if [[ "$cache_sig" == "$current_sig" ]]; then
            tail -n +2 "$cache_file"
            return 0
        fi
    fi

    {
        printf '%s\n' "$current_sig"
        awk '
            /^## Phase/ { titles[++n] = substr($0, 4); lineno[n] = NR }
            END {
                if (n == 0) exit
                printf "    前文: Read(offset=1, limit=%d)\n", lineno[1]-2
                for (i=1; i<=n; i++) {
                    end_line = (i<n) ? lineno[i+1]-1 : NR
                    printf "    %s: Read(offset=%d, limit=%d)\n", titles[i], lineno[i], end_line-lineno[i]+1
                }
            }
        ' "$source_file"
    } > "$cache_file"
    tail -n +2 "$cache_file"
}

collect_causal_backlink_hits() {
    local pattern_file="$1"
    local backlink_cache_dir="$2"
    local backlink_cache_key backlink_cache_file backlink_lock_dir backlink_tmp waited backlink_hits

    backlink_cache_key="$(sha256sum "$pattern_file" 2>/dev/null | awk '{print $1}')"
    backlink_cache_file="$backlink_cache_dir/${backlink_cache_key}.cache"
    backlink_lock_dir="$backlink_cache_file.lock"
    mkdir -p "$backlink_cache_dir" 2>/dev/null || true

    if [ -f "$backlink_cache_file" ]; then
        cat "$backlink_cache_file" 2>/dev/null || true
        return 0
    fi

    if mkdir "$backlink_lock_dir" 2>/dev/null; then
        if command -v timeout >/dev/null 2>&1; then
            backlink_hits="$(
                cd "$SCRIPT_DIR" \
                    && timeout -k 1 1 rg -n --fixed-strings --hidden \
                        --glob '!.git/**' \
                        --glob '!queue/archive/**' \
                        --glob '!queue/**' \
                        --glob '!archive/**' \
                        --glob '!logs/**' \
                        --glob '!tasks/**' \
                        --glob '!tmp/**' \
                        --glob '!data/**' \
                        --glob '!node_modules/**' \
                        --glob '!__pycache__/**' \
                        -f "$pattern_file" . 2>/dev/null \
                    || true
            )"
        else
            backlink_hits="$(
                cd "$SCRIPT_DIR" \
                    && rg -n --fixed-strings --hidden \
                        --glob '!.git/**' \
                        --glob '!queue/archive/**' \
                        --glob '!queue/**' \
                        --glob '!archive/**' \
                        --glob '!logs/**' \
                        --glob '!tasks/**' \
                        --glob '!tmp/**' \
                        --glob '!data/**' \
                        --glob '!node_modules/**' \
                        --glob '!__pycache__/**' \
                        -f "$pattern_file" . 2>/dev/null \
                    || true
            )"
        fi
        backlink_tmp="$(mktemp)"
        printf '%s\n' "$backlink_hits" > "$backlink_tmp" 2>/dev/null || true
        mv "$backlink_tmp" "$backlink_cache_file" 2>/dev/null || rm -f "$backlink_tmp"
        rmdir "$backlink_lock_dir" 2>/dev/null || true
        printf '%s\n' "$backlink_hits"
        return 0
    fi

    waited=0
    while [ "$waited" -lt 20 ] && [ ! -f "$backlink_cache_file" ]; do
        sleep 0.05
        waited=$((waited + 1))
    done
    if [ -f "$backlink_cache_file" ]; then
        cat "$backlink_cache_file" 2>/dev/null || true
        return 0
    fi

    if command -v timeout >/dev/null 2>&1; then
        cd "$SCRIPT_DIR" \
            && timeout -k 1 1 rg -n --fixed-strings --hidden \
                --glob '!.git/**' \
                --glob '!queue/archive/**' \
                --glob '!queue/**' \
                --glob '!archive/**' \
                --glob '!logs/**' \
                --glob '!tasks/**' \
                --glob '!tmp/**' \
                --glob '!data/**' \
                --glob '!node_modules/**' \
                --glob '!__pycache__/**' \
                -f "$pattern_file" . 2>/dev/null \
            || true
    else
        cd "$SCRIPT_DIR" \
            && rg -n --fixed-strings --hidden \
                --glob '!.git/**' \
                --glob '!queue/archive/**' \
                --glob '!queue/**' \
                --glob '!archive/**' \
                --glob '!logs/**' \
                --glob '!tasks/**' \
                --glob '!tmp/**' \
                --glob '!data/**' \
                --glob '!node_modules/**' \
                --glob '!__pycache__/**' \
                -f "$pattern_file" . 2>/dev/null \
            || true
    fi
}

show_active_cmd_semantic_context_one() {
    local semantic_script="$SCRIPT_DIR/scripts/semantic_search.sh"
    local causal_script="$SCRIPT_DIR/scripts/causal_backlinks.sh"
    local timeout_sec="${KARO_STARTUP_SEMANTIC_TIMEOUT:-5}"
    local ninja="$1"
    local cmd_id="$2"
    local target_path="$3"
    local shown_file="$4"
    local semantic_output links link_id backlink_output rc
    local link_tmp link_idx link_tmp_list
    local semantic_cache_dir semantic_cache_key semantic_cache_file semantic_cache_sig semantic_current_sig
    local backlink_cache_dir

    echo "  ${ninja}: ${cmd_id:-unknown} target_path=${target_path}"
    semantic_cache_dir="${KARO_STARTUP_SEMANTIC_CACHE_DIR:-/tmp/karo_startup_semantic_cache}"
    semantic_current_sig="$(
        {
            printf '%s\n' "$target_path"
            stat -c '%Y:%s' "$SCRIPT_DIR/docs/semantic-index/index.md" 2>/dev/null || true
        } | sha256sum | awk '{print $1}'
    )"
    semantic_cache_key="${target_path//[^A-Za-z0-9_.-]/_}"
    semantic_cache_file="$semantic_cache_dir/${semantic_cache_key}.${semantic_current_sig}.cache"
    if [ -f "$semantic_cache_file" ]; then
        IFS= read -r rc < "$semantic_cache_file" || rc=1
        semantic_output="$(tail -n +2 "$semantic_cache_file")"
    elif command -v timeout >/dev/null 2>&1; then
        if semantic_output="$(
            SEMANTIC_DISABLE_LLM=1 \
            SEMANTIC_DISABLE_CAUSAL=1 \
            SEMANTIC_DISABLE_MEMORY_DB=1 \
            SEMANTIC_CAUSAL_ROOT="$SCRIPT_DIR" \
            timeout -k 1 "$timeout_sec" bash "$semantic_script" "$target_path" 2>&1
        )"; then
            rc=0
        else
            rc=$?
        fi
    else
        if semantic_output="$(
            SEMANTIC_DISABLE_LLM=1 \
            SEMANTIC_DISABLE_CAUSAL=1 \
            SEMANTIC_DISABLE_MEMORY_DB=1 \
            SEMANTIC_CAUSAL_ROOT="$SCRIPT_DIR" \
            bash "$semantic_script" "$target_path" 2>&1
        )"; then
            rc=0
        else
            rc=$?
        fi
    fi
    if [ ! -f "$semantic_cache_file" ]; then
        mkdir -p "$semantic_cache_dir" 2>/dev/null || true
        {
            printf '%s\n' "$rc"
            printf '%s\n' "$semantic_output"
        } > "$semantic_cache_file" 2>/dev/null || true
    fi

    if [ "$rc" -eq 0 ] && [ -n "${semantic_output//[[:space:]]/}" ]; then
        printf 'shown\n' > "$shown_file"
        printf '%s\n' "$semantic_output" | awk 'NR <= 60 { print "    " $0 } NR == 61 { print "    ..."; exit }'
        if [ -f "$causal_script" ]; then
            links="$(
                printf '%s\n' "$semantic_output" \
                    | grep -oE '\[\[[^]]+\]\]|cmd_[A-Za-z0-9_-]+|L[0-9][0-9A-Za-z_-]*|LS-[A-Za-z0-9_-]+|PI-[A-Za-z0-9_-]+|LK[0-9][0-9A-Za-z_-]*' 2>/dev/null \
                    | sed 's/^\[\[//; s/\]\]$//' \
                    | awk 'NF && !seen[$0]++' \
                    | head -8 \
                || true
            )"
            if [ -n "${links//[[:space:]]/}" ]; then
                echo "    causal_edges:"
                local pattern_file backlink_hits
                pattern_file=$(mktemp)
                while IFS= read -r link_id; do
                    [ -n "$link_id" ] || continue
                    printf '[[%s]]\n' "$link_id" >> "$pattern_file"
                done <<< "$links"
                backlink_cache_dir="${KARO_STARTUP_BACKLINK_CACHE_DIR:-$semantic_cache_dir/backlinks}"
                backlink_hits="$(collect_causal_backlink_hits "$pattern_file" "$backlink_cache_dir")"
                rm -f "$pattern_file"
                while IFS= read -r link_id; do
                    [ -n "$link_id" ] || continue
                    echo "    - link: [[${link_id}]]"
                    backlink_output="$(
                        printf '%s\n' "$backlink_hits" \
                            | grep -F "[[${link_id}]]" \
                            | cut -d: -f1 \
                            | awk 'NF && !seen[$0]++ { print; if (++n >= 5) exit }' \
                        || true
                    )"
                    if [ -n "$backlink_output" ]; then
                        printf '%s\n' "$backlink_output" | sed 's/^/      - resource: /'
                    else
                        echo "      - resource: none"
                    fi
                done <<< "$links"
            fi
        fi
    elif [ "$rc" -eq 124 ]; then
        echo "    SKIP: semantic_search timeout(${timeout_sec}s)"
    elif [ "$rc" -eq 1 ]; then
        echo "    関連概念なし"
    else
        echo "    SKIP: semantic_search failed(rc=${rc})"
    fi
}

show_active_cmd_semantic_context() {
    local semantic_script="$SCRIPT_DIR/scripts/semantic_search.sh"
    local task_file ninja status cmd_id target_path active_count shown_count
    local out_file shown_file pid first_ninja
    local active_ninjas=()
    local out_files=()
    local shown_files=()
    local pids=()
    declare -A target_seen=()
    declare -A target_first_ninja=()

    echo "■ 稼働中cmd関連因果概念"
    if [ ! -f "$semantic_script" ]; then
        echo "  SKIP: scripts/semantic_search.sh 不在"
        echo ""
        return 0
    fi

    active_count=0
    shown_count=0
    for ninja in $_KARO_NINJA_NAMES; do
        task_file="$SCRIPT_DIR/queue/tasks/${ninja}.yaml"
        [ -f "$task_file" ] || continue
        IFS='|' read -r status cmd_id target_path < <(
            awk '
                function trim(s) {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
                    gsub(/^["'\''"]|["'\''"]$/, "", s)
                    return s
                }
                /^[[:space:]]*status:[[:space:]]*/ {
                    v=$0
                    sub(/^[[:space:]]*status:[[:space:]]*/, "", v)
                    status=trim(v)
                    next
                }
                /^[[:space:]]*cmd_id:[[:space:]]*/ {
                    v=$0
                    sub(/^[[:space:]]*cmd_id:[[:space:]]*/, "", v)
                    cmd_id=trim(v)
                    next
                }
                /^[[:space:]]*target_path:[[:space:]]*/ {
                    v=$0
                    sub(/^[[:space:]]*target_path:[[:space:]]*/, "", v)
                    target_path=trim(v)
                    next
                }
                END { printf "%s|%s|%s\n", status, cmd_id, target_path }
            ' "$task_file" 2>/dev/null
        )

        [[ "$status" =~ ^(assigned|acknowledged|in_progress)$ ]] || continue
        active_count=$((active_count + 1))
        if [ -z "${target_path//[[:space:]]/}" ]; then
            out_file=$(mktemp)
            shown_file=$(mktemp)
            echo "  ${ninja}: ${cmd_id:-unknown} target_pathなし" > "$out_file"
            active_ninjas+=("$ninja")
            out_files+=("$out_file")
            shown_files+=("$shown_file")
            pids+=("")
            continue
        fi

        if [ -n "${target_seen[$target_path]:-}" ]; then
            out_file=$(mktemp)
            shown_file=$(mktemp)
            first_ninja="${target_first_ninja[$target_path]}"
            {
                echo "  ${ninja}: ${cmd_id:-unknown} target_path=${target_path}"
                echo "    semantic_context_reused: ${first_ninja} と同一target_pathのため再利用"
            } > "$out_file"
            active_ninjas+=("$ninja")
            out_files+=("$out_file")
            shown_files+=("$shown_file")
            pids+=("")
            continue
        fi

        out_file=$(mktemp)
        shown_file=$(mktemp)
        show_active_cmd_semantic_context_one "$ninja" "$cmd_id" "$target_path" "$shown_file" > "$out_file" &
        pid=$!
        target_seen[$target_path]=1
        target_first_ninja[$target_path]="$ninja"
        active_ninjas+=("$ninja")
        out_files+=("$out_file")
        shown_files+=("$shown_file")
        pids+=("$pid")
    done

    for pid in "${pids[@]}"; do
        [ -n "$pid" ] && wait "$pid" 2>/dev/null || true
    done

    for out_file in "${out_files[@]}"; do
        cat "$out_file"
        rm -f "$out_file"
    done
    for shown_file in "${shown_files[@]}"; do
        if [ -s "$shown_file" ]; then
            shown_count=$((shown_count + 1))
        fi
        rm -f "$shown_file"
    done

    if [ "$active_count" -eq 0 ]; then
        echo "  active cmdなし"
    elif [ "$shown_count" -eq 0 ]; then
        echo "  表示対象の関連概念なし"
    fi
    echo ""
}

show_semantic_no_match_metrics() {
    local deploy_log="${KARO_STARTUP_DEPLOY_LOG:-$SCRIPT_DIR/logs/deploy_task.log}"
    local scan_lines="${KARO_STARTUP_NO_MATCH_SCAN_LINES:-500}"

    echo "■ セマンティックNO_MATCH計測"
    if [ ! -f "$deploy_log" ]; then
        echo "  SKIP: logs/deploy_task.log 不在"
        echo ""
        return 0
    fi

    tail -n "$scan_lines" "$deploy_log" 2>/dev/null | awk '
        /inject_semantic_concepts:/ {
            attempts++
            if (/NO_MATCH/) {
                no_match++
                purpose = $0
                sub(/^.*NO_MATCH purpose=/, "", purpose)
                sub(/[[:space:]]target_path=.*/, "", purpose)
                gsub(/[[:space:]]+/, " ", purpose)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", purpose)
                if (purpose == "") purpose = "(purposeなし)"
                miss[purpose]++
            }
        }
        END {
            if (attempts == 0) {
                print "  semantic注入試行: 0件"
                exit
            }
            rate = int((no_match * 1000 / attempts) + 0.5) / 10
            hit_rate = int(((attempts - no_match) * 1000 / attempts) + 0.5) / 10
            printf "  NO_MATCH率: %.1f%% (%d/%d, scan_lines=%d)\n", rate, no_match, attempts, scan_lines
            printf "  ヒット率: %.1f%% (%d/%d)\n", hit_rate, attempts - no_match, attempts
            if (no_match == 0) {
                print "  TOP3 miss purpose: none"
                exit
            }
            print "  TOP3 miss purpose:"
            for (purpose in miss) {
                order[++n] = purpose
            }
            for (i = 1; i <= n; i++) {
                for (j = i + 1; j <= n; j++) {
                    if (miss[order[j]] > miss[order[i]]) {
                        tmp = order[i]; order[i] = order[j]; order[j] = tmp
                    }
                }
            }
            limit = (n < 3) ? n : 3
            for (i = 1; i <= limit; i++) {
                p = order[i]
                shown = p
                if (length(shown) > 100) shown = substr(shown, 1, 97) "..."
                printf "    %d. %s (%d件)\n", i, shown, miss[p]
            }
        }
    ' scan_lines="$scan_lines"
    echo ""
}

skill_execution_summary_fast() {
    local log_file="$1"

    echo "skill | fail_count | last_fail | top_stumbling_point"
    [ -f "$log_file" ] || return 0
    grep -E "^- ts:|^  (skill|result|used|stumbling_points|source):" "$log_file" 2>/dev/null | awk '
function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
function unquote(s) {
    s = trim(s)
    gsub(/^"|"$/, "", s)
    gsub(/^'\''|'\''$/, "", s)
    return s
}
function finish() {
    r = toupper(result)
    u = tolower(used == "" ? "true" : used)
    # 偽FAIL除外: result.summary空またはbc空(cmd空)のテンプレート段階FAIL
    is_fake = (index(point, "result.summary: MISSING or empty") > 0 || index(point, "cmd=<empty>") > 0)
    if (skill != "" && u != "false" && !is_fake) {
        # 最新結果を追跡(時系列順: 後のエントリが上書き)
        latest_result[skill] = r
        latest_ts[skill] = ts
        latest_source[skill] = source
        if (r == "PASS" && source != "") {
            pass_source[skill, source] = 1
        }
    }
    if (r == "FAIL" && u != "false" && skill != "" && !is_fake) {
        count[skill]++
        if (ts >= last[skill]) last[skill] = ts
        if (point != "") {
            key = skill SUBSEP point
            c = ++point_count[key]
            if (c > top_count[skill] || (c == top_count[skill] && (top_point[skill] == "" || point < top_point[skill]))) {
                top_point[skill] = point
                top_count[skill] = c
            }
        }
    }
}
/^- ts:/ {
    if (in_entry) finish()
    in_entry = 1
    skill = result = used = point = source = ""
    line = $0
    sub(/^- ts:[[:space:]]*/, "", line)
    ts = unquote(line)
    next
}
in_entry && /^  skill:/ {
    line = $0
    sub(/^  skill:[[:space:]]*/, "", line)
    skill = unquote(line)
    next
}
in_entry && /^  result:/ {
    line = $0
    sub(/^  result:[[:space:]]*/, "", line)
    result = unquote(line)
    next
}
in_entry && /^  used:/ {
    line = $0
    sub(/^  used:[[:space:]]*/, "", line)
    used = unquote(line)
    next
}
in_entry && /^  stumbling_points:/ {
    line = $0
    sub(/^  stumbling_points:[[:space:]]*/, "", line)
    point = unquote(line)
    next
}
in_entry && /^  source:/ {
    line = $0
    sub(/^  source:[[:space:]]*/, "", line)
    source = unquote(line)
    next
}
END {
    if (in_entry) finish()
    for (s in count) {
        # 最新結果がPASS/SKIPなら過去FAILは解消済み→除外
        if (latest_result[s] == "PASS" || latest_result[s] == "SKIP") continue
        # 短縮cmdで後発FAILしても、同一skillに完全cmdのPASSがあれば解消済みとして扱う
        resolved_by_alias = 0
        if (latest_source[s] != "") {
            for (k in pass_source) {
                split(k, parts, SUBSEP)
                ps_skill = parts[1]
                ps_source = parts[2]
                if (ps_skill != s) continue
                if (ps_source == latest_source[s] \
                    || index(ps_source, latest_source[s] "_") == 1 \
                    || index(latest_source[s], ps_source "_") == 1) {
                    resolved_by_alias = 1
                    break
                }
            }
        }
        if (resolved_by_alias) continue
        printf "%d|%s|%s|%s\n", count[s], last[s], s, top_point[s]
    }
}
' \
        | sort -t'|' -k1,1nr -k3,3 \
        | awk -F'|' '{ print $3 " | " $1 " | " $2 " | " $4 }'
}

review_quality_scale_summary() {
    local review_log="${1:-$SCRIPT_DIR/logs/gunshi_review_log.yaml}"
    local limit="${2:-20}"
    local status_file="${3:-$SCRIPT_DIR/queue/shogun_to_karo.yaml}"
    local gate_metrics_file="${4:-$SCRIPT_DIR/logs/gate_metrics.log}"
    [ -f "$review_log" ] || { echo "DATA_MISSING"; return 0; }
    [ -f "$status_file" ] || status_file="/dev/null"
    [ -f "$gate_metrics_file" ] || gate_metrics_file="/dev/null"
    [[ "$limit" =~ ^[0-9]+$ ]] || limit=20
    awk -v limit="$limit" '
function trim(s) { gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); gsub(/^["'\''"]|["'\''"]$/, "", s); return s }
FILENAME == ARGV[1] {
    if ($0 ~ /^[[:space:]]+cmd_[A-Za-z0-9_]+:/) {
        s = $0
        sub(/^[[:space:]]+/, "", s)
        sub(/:.*/, "", s)
        status_cmd = trim(s)
        next
    }
    if (status_cmd != "" && $0 ~ /^[[:space:]]+status:/) {
        s = $0
        sub(/^[[:space:]]+status:[[:space:]]*/, "", s)
        cmd_status[status_cmd] = trim(s)
        next
    }
    next
}
FILENAME == ARGV[2] {
    cmd = ""; result = ""
    # Current gate_metrics format: ts<TAB>cmd_id<TAB>result<TAB>reason...
    if (NF >= 3 && $2 ~ /^cmd_/) {
        cmd = trim($2)
        result = trim($3)
    # Legacy test fixtures: ts<TAB>result<TAB>cmd_id<TAB>worker...
    } else if (NF >= 3 && $3 ~ /^cmd_/) {
        cmd = trim($3)
        result = trim($2)
    }
    if (cmd != "" && result ~ /^(CLEAR|PASS)$/) {
        gate_clear[cmd] = 1
    }
    next
}
function flush_entry() {
    if (verdict != "" && verdict != "null" && review_type ~ /^(draft|report|verify)$/) {
        n++
        v[n] = verdict
        cid[n] = current_cmd_id
        gr[n] = gate_result
        if (review_type ~ /^(draft|report)$/) {
            old_n++
            old_v[old_n] = verdict
        }
    }
    review_type = ""; verdict = ""; current_cmd_id = ""; gate_result = ""
}
/^[[:space:]]*-[[:space:]]*cmd_id:/ {
    flush_entry()
    s = $0; sub(/^[[:space:]]*-[[:space:]]*cmd_id:[[:space:]]*/, "", s); current_cmd_id = trim(s)
    next
}
/^[[:space:]]*review_type:/ {
    s=$0; sub(/^[[:space:]]*review_type:[[:space:]]*/, "", s); review_type=trim(s); next
}
/^  verdict:/ {
    s=$0; sub(/^  verdict:[[:space:]]*/, "", s); verdict=trim(s); next
}
/^  gate_result:/ {
    s=$0; sub(/^  gate_result:[[:space:]]*/, "", s); gate_result=trim(s); next
}
END {
    flush_entry()
    # 旧方式: draft|reportのみ・重複あり
    old_start = old_n - limit + 1
    if (old_start < 1) old_start = 1
    old_total = 0; old_warn = 0
    for (i = old_start; i <= old_n; i++) {
        old_total++
        ok = (old_v[i] ~ /^(APPROVE|LGTM|PASS|CLEAR|VERIFIED|VERIFIED_FACTS|CONDITIONAL_PASS)$/)
        if (!ok) old_warn++
    }
    # 新方式: 全review_type・cmd_id単位最終verdict
    new_start = n - limit + 1
    if (new_start < 1) new_start = 1
    for (i = new_start; i <= n; i++) {
        key = (cid[i] != "") ? cid[i] : ("__anon__" i)
        last_idx[key] = i
    }
    new_total = 0; new_warn = 0
    for (key in last_idx) {
        i = last_idx[key]
        new_total++
        ok = (v[i] ~ /^(APPROVE|LGTM|PASS|CLEAR|VERIFIED|VERIFIED_FACTS|CONDITIONAL_PASS)$/)
        if (!ok && gr[i] ~ /^(CLEAR|PASS)$/) ok = 1
        if (!ok && cid[i] != "" && cmd_status[cid[i]] ~ /^(done|completed|cancelled)$/) ok = 1
        if (!ok && cid[i] != "" && gate_clear[cid[i]]) ok = 1
        if (!ok) new_warn++
    }
    if (new_total == 0) {
        print "DATA_MISSING"
        exit
    }
    new_rate = int(new_warn * 100 / new_total)
    old_rate = (old_total > 0) ? int(old_warn * 100 / old_total) : 0
    printf "RATE %d %d %d %d\n", new_rate, new_warn, new_total, old_rate
}
' "$status_file" "$gate_metrics_file" "$review_log"
}

if [[ "${GATE_KARO_STARTUP_LIB_ONLY:-0}" == "1" ]]; then
    return 0 2>/dev/null || exit 0
fi

# === 高速化: バックグラウンド並列 + WA rateキャッシュ(300s TTL) ===
# cmd_2076: WA rate スクリプト結果を /tmp にキャッシュ (TTL 300秒)
# 前回(python3→awk+statusキャッシュ)との差分: WA rate結果自体をキャッシュ (異なる対象)
# cache hit時: ~2ms。cache miss時: 57ms+53ms (現行と同等)

_WA_RATE_TMP=$(mktemp)
_WA_RATE_ERR_TMP=$(mktemp)
_NINJA_WA_TMP=$(mktemp)
_WA_DQ_TMP=$(mktemp)
WA_RATE_SCRIPT="$SCRIPT_DIR/scripts/gates/gate_workaround_rate.sh"
NINJA_WA_SCRIPT="$SCRIPT_DIR/scripts/gates/gate_ninja_workaround_rate.sh"
WA_DQ_SCRIPT="$SCRIPT_DIR/scripts/gates/gate_wa_data_quality.sh"
_WA_RATE_CACHE="${KARO_WA_RATE_CACHE:-/tmp/karo_wa_rate_cache}"
_NINJA_WA_CACHE="${KARO_NINJA_WA_CACHE:-/tmp/karo_ninja_wa_cache}"
_SKILL_SUMMARY_CACHE="${KARO_SKILL_SUMMARY_CACHE:-/tmp/karo_skill_summary_cache}"
_AGGREGATE_CACHE="${KARO_AGGREGATE_CACHE:-/tmp/karo_startup_aggregate_cache}"
_WA_CACHE_TTL=300
_SKILL_SUMMARY_CACHE_TTL=300

_now_epoch=$(date +%s)

# WA rate (cache hit or background refresh)
if [[ -f "$_WA_RATE_CACHE" ]] && (( _now_epoch - $(stat -c %Y "$_WA_RATE_CACHE" 2>/dev/null || echo 0) < _WA_CACHE_TTL )); then
    cp "$_WA_RATE_CACHE" "$_WA_RATE_TMP"
    _WA_RATE_PID=""
elif [ -x "$WA_RATE_SCRIPT" ]; then
    (
        if bash "$WA_RATE_SCRIPT" --last 10 > "$_WA_RATE_TMP" 2>"$_WA_RATE_ERR_TMP"; then
            cat "$_WA_RATE_TMP" > "$_WA_RATE_CACHE"
        else
            _wa_rc=$?
            log_startup_stderr_file "WA_RATE_SCRIPT" "$_WA_RATE_ERR_TMP"
            {
                echo "■ Workaround率"
                echo "  WARN: gate_workaround_rate.sh failed rc=${_wa_rc}"
            } > "$_WA_RATE_TMP"
        fi
    ) &
    _WA_RATE_PID=$!
else
    echo "■ Workaround率" > "$_WA_RATE_TMP"
    echo "  SKIP: gate_workaround_rate.sh が存在しないか実行権限なし" >> "$_WA_RATE_TMP"
    _WA_RATE_PID=""
fi

# ninja WA rate (cache hit or background refresh)
if [[ -f "$_NINJA_WA_CACHE" ]] && (( _now_epoch - $(stat -c %Y "$_NINJA_WA_CACHE" 2>/dev/null || echo 0) < _WA_CACHE_TTL )); then
    cp "$_NINJA_WA_CACHE" "$_NINJA_WA_TMP"
    _NINJA_WA_PID=""
elif [ -x "$NINJA_WA_SCRIPT" ]; then
    ( bash "$NINJA_WA_SCRIPT" --quiet --last 30 2>&1 | tee "$_NINJA_WA_TMP" > "$_NINJA_WA_CACHE" ) &
    _NINJA_WA_PID=$!
else
    echo "  SKIP: gate_ninja_workaround_rate.sh が存在しないか実行権限なし" > "$_NINJA_WA_TMP"
    _NINJA_WA_PID=""
fi

# WA data quality (always displayed; non-zero means issues found, not startup abort)
if [ -x "$WA_DQ_SCRIPT" ]; then
    ( bash "$WA_DQ_SCRIPT" > "$_WA_DQ_TMP" 2>&1 || true ) &
    _WA_DQ_PID=$!
else
    echo "SKIP: gate_wa_data_quality.sh が存在しないか実行権限なし" > "$_WA_DQ_TMP"
    _WA_DQ_PID=""
fi

# (B) tmux list-panes を1回だけ呼び出してキャッシュ
_AGENTS_WINDOW_TARGET="${TMUX_WINDOW:-shogun:agents}"
if ! tmux list-panes -t "$_AGENTS_WINDOW_TARGET" >/dev/null 2>&1; then
    _AGENTS_WINDOW_TARGET="shogun:agents"
fi
_PANE_MAP=$(tmux list-panes -t "$_AGENTS_WINDOW_TARGET" -F '#{pane_index} #{@agent_id}' 2>/dev/null || true)
declare -A _PANE_IDX_BY_AGENT
while IFS=' ' read -r _pane_idx _pane_agent; do
    [[ -z "${_pane_idx:-}" || -z "${_pane_agent:-}" ]] && continue
    _PANE_IDX_BY_AGENT["$_pane_agent"]=$_pane_idx
done <<< "$_PANE_MAP"

# (C) awk/bash で phase guide + session summary + bulletin を取得（python3不要）
# 大きいファイル読込は並列化して I/O 待ちを重ねる
_phase_guide_1_tmp=$(mktemp)
_phase_guide_2_tmp=$(mktemp)
_session_summary_tmp=$(mktemp)
_bulletin_tmp=$(mktemp)
_aggregate_tmp=$(mktemp)
declare -a _META_PIDS=()
declare -A _NINJA_STATUS_CACHE

# phase guide 1
_phase_guide_1=""
if [ -f "$SCRIPT_DIR/memory/deepdive_why_chain_20260321.md" ]; then
    (
        awk '
            /^## Phase/ { titles[++n] = substr($0, 4); lineno[n] = NR }
            END {
                if (n == 0) exit
                printf "    前文: Read(offset=1, limit=%d)\n", lineno[1]-2
                for (i=1; i<=n; i++) {
                    end_line = (i<n) ? lineno[i+1]-1 : NR
                    printf "    %s: Read(offset=%d, limit=%d)\n", titles[i], lineno[i], end_line-lineno[i]+1
                }
            }
        ' "$SCRIPT_DIR/memory/deepdive_why_chain_20260321.md" > "$_phase_guide_1_tmp"
    ) &
    _META_PIDS+=($!)
fi

# phase guide 2
_phase_guide_2=""
if [ -f "$SCRIPT_DIR/memory/deepdive_karo_verification_20260405.md" ]; then
    (
        awk '
            /^## Phase/ { titles[++n] = substr($0, 4); lineno[n] = NR }
            END {
                if (n == 0) exit
                printf "    前文: Read(offset=1, limit=%d)\n", lineno[1]-2
                for (i=1; i<=n; i++) {
                    end_line = (i<n) ? lineno[i+1]-1 : NR
                    printf "    %s: Read(offset=%d, limit=%d)\n", titles[i], lineno[i], end_line-lineno[i]+1
                }
            }
        ' "$SCRIPT_DIR/memory/deepdive_karo_verification_20260405.md" > "$_phase_guide_2_tmp"
    ) &
    _META_PIDS+=($!)
fi

# session summary (JSONLから grep/awk で取得)
_prev_session_summary=""
if [ -f "$SCRIPT_DIR/queue/lord_conversation.jsonl" ]; then
    (
        awk '
            /"session_summary"/ {
                if (match($0, /"summary":[[:space:]]*"[^"]*/)) {
                    summary = substr($0, RSTART, RLENGTH)
                    sub(/^"summary":[[:space:]]*"/, "", summary)
                }
            }
            END { if (summary != "") print summary }
        ' "$SCRIPT_DIR/queue/lord_conversation.jsonl" 2>/dev/null > "$_session_summary_tmp"
    ) &
    _META_PIDS+=($!)
fi

# bulletin 未確認件数とアイテム（awk YAML近似解析）
_bulletin_count=0
_bulletin_items=""
if [ -f "$SCRIPT_DIR/queue/bulletin_board.yaml" ]; then
    (
        awk '
            /^- id:/ {
                if (in_entry && rc && !closed && !karo_c) {
                    count++
                    if (count <= 3) printf "ITEM: %s by %s\n", eid, epby
                }
                in_entry=1; rc=0; closed=0; karo_c=0; eid=""; epby=""
            }
            in_entry && /^  id:/ { v=$2; gsub(/['"'"'"]/, "", v); eid=v }
            in_entry && /^  posted_by:/ { v=$2; gsub(/['"'"'"]/, "", v); epby=v }
            in_entry && /requires_confirmation: true/ { rc=1 }
            in_entry && /status:.*closed/ { closed=1 }
            in_entry && /- .karo./ { karo_c=1 }
            END {
                if (in_entry && rc && !closed && !karo_c) {
                    count++
                    if (count <= 3) printf "ITEM: %s by %s\n", eid, epby
                }
                print "COUNT: " count+0
            }
        ' "$SCRIPT_DIR/queue/bulletin_board.yaml" 2>/dev/null || echo "COUNT: 0"
    ) > "$_bulletin_tmp" &
    _META_PIDS+=($!)
fi

(
_AGG_FILES=()
_ninja_task_globs=()
for _nn in $(get_ninja_names 2>/dev/null); do
    _ninja_task_globs+=("$SCRIPT_DIR/queue/tasks/${_nn}.yaml")
done
for _agg_file in \
  "${_ninja_task_globs[@]}" \
  "$SCRIPT_DIR/queue/inbox/karo.yaml" \
  "$SCRIPT_DIR/queue/insights.yaml" \
  "$SCRIPT_DIR/logs/gunshi_review_log.yaml" \
  "$SCRIPT_DIR/queue/pending_decisions.yaml" \
  "$SCRIPT_DIR/logs/karo_workarounds.yaml" \
  "$SCRIPT_DIR/queue/shogun_to_karo.yaml"; do
    [[ -f "$_agg_file" ]] && _AGG_FILES+=("$_agg_file")
done
_AGG_SIG="$(stat -c '%n:%y:%s' "${_AGG_FILES[@]}" 2>/dev/null | tr '\n' ';' || true)"
if [[ -f "$_AGGREGATE_CACHE" ]]; then
    IFS= read -r _agg_cache_sig < "$_AGGREGATE_CACHE" || _agg_cache_sig=""
    if [[ "$_agg_cache_sig" == "$_AGG_SIG" ]]; then
        tail -n +2 "$_AGGREGATE_CACHE" > "$_aggregate_tmp"
        exit 0
    fi
fi
awk -v root="$SCRIPT_DIR" '
    FILENAME ~ /queue\/tasks\/[^/]+\.yaml$/ {
        if (FNR == 1) {
            file = FILENAME
            sub(/^.*\/queue\/tasks\//, "", file)
            sub(/\.yaml$/, "", file)
        }
        if ($0 ~ /^[[:space:]]*status:/) {
            print "STATUS|" file "|" $2
            nextfile
        }
        next
    }
    FILENAME ~ /queue\/inbox\/karo\.yaml$/ {
        if (/^- /) {
            if (inbox_entry && inbox_read_false && inbox_type == "cmd_new") {
                unread_cmd_new++
                if (unread_cmd_new <= 3) {
                    item = inbox_id
                    if (item == "") item = "unknown"
                    if (inbox_ts != "") item = item "@" inbox_ts
                    if (inbox_content != "") item = item " " inbox_content
                    gsub(/\|/, "/", item)
                    unread_cmd_new_items = unread_cmd_new_items (unread_cmd_new_items != "" ? "; " : "") item
                }
            }
            inbox_entry = 1
            inbox_read_false = 0
            inbox_type = ""
            inbox_id = ""
            inbox_ts = ""
            inbox_content = ""
        }
        if (/read: false/) unread++
        if (inbox_entry && /^[[:space:]]*type:/) {
            inbox_type = $0
            sub(/^[[:space:]]*type:[[:space:]]*/, "", inbox_type)
            gsub(/["'"'"']/, "", inbox_type)
            gsub(/[[:space:]]+$/, "", inbox_type)
        }
        if (inbox_entry && /^[[:space:]]*read:[[:space:]]*false/) inbox_read_false = 1
        if (inbox_entry && /^[[:space:]]*id:/) {
            inbox_id = $0
            sub(/^[[:space:]]*id:[[:space:]]*/, "", inbox_id)
            gsub(/["'"'"']/, "", inbox_id)
            gsub(/[[:space:]]+$/, "", inbox_id)
        }
        if (inbox_entry && /^[[:space:]]*timestamp:/) {
            inbox_ts = $0
            sub(/^[[:space:]]*timestamp:[[:space:]]*/, "", inbox_ts)
            gsub(/["'"'"']/, "", inbox_ts)
            gsub(/[[:space:]]+$/, "", inbox_ts)
        }
        if (inbox_entry && /^[[:space:]]*content:/) {
            inbox_content = $0
            sub(/^[[:space:]]*content:[[:space:]]*/, "", inbox_content)
            gsub(/["'"'"']/, "", inbox_content)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", inbox_content)
            if (length(inbox_content) > 80) inbox_content = substr(inbox_content, 1, 80) "..."
        }
        next
    }
    FILENAME ~ /queue\/insights\.yaml$/ {
        if (/^- id:/) {
            if (ins_id != "" && ins_status == "pending") {
                pending_insights++
                pending_insight_id[pending_insights] = ins_id
                pending_insight_priority[pending_insights] = ins_priority
                pending_insight_text[pending_insights] = ins_text
            }
            ins_id = $0
            sub(/^- id:[[:space:]]*/, "", ins_id)
            gsub(/["'"'"']/, "", ins_id)
            ins_status = ""
            ins_priority = ""
            ins_text = ""
            next
        }
        if (ins_id != "" && /^  status:/) {
            ins_status = $0
            sub(/^  status:[[:space:]]*/, "", ins_status)
            gsub(/["'"'"']/, "", ins_status)
            gsub(/[[:space:]]+$/, "", ins_status)
            next
        }
        if (ins_id != "" && /^  priority:/) {
            ins_priority = $0
            sub(/^  priority:[[:space:]]*/, "", ins_priority)
            gsub(/["'"'"']/, "", ins_priority)
            gsub(/[[:space:]]+$/, "", ins_priority)
            next
        }
        if (ins_id != "" && /^  insight:/) {
            ins_text = $0
            sub(/^  insight:[[:space:]]*/, "", ins_text)
            gsub(/^["'"'"']|["'"'"']$/, "", ins_text)
            gsub(/\|/, "/", ins_text)
            if (length(ins_text) > 90) ins_text = substr(ins_text, 1, 90) "..."
            next
        }
        next
    }
    FILENAME ~ /logs\/gunshi_review_log\.yaml$/ {
        if ($0 !~ /^#/ && /status:[[:space:]]*pending[[:space:]]*$/) gp_pending++
        next
    }
    FILENAME ~ /queue\/pending_decisions\.yaml$/ {
        if (/^- id:/) pd_total++
        if (/status: resolved/) pd_resolved++
        next
    }
    FILENAME ~ /logs\/karo_workarounds\.yaml$/ {
        if (/^- (cmd_id|cmd|timestamp):/) {
            n++
            wa[n]=0
            brainwash[n]=0
            has_brainwash_field[n]=0
            cat[n]="uncategorized"
            rc[n]=""
            wa_cmd[n]=""
            if (/^- (cmd_id|cmd):/) {
                wa_cmd[n]=$0
                sub(/^- (cmd_id|cmd):[[:space:]]*/, "", wa_cmd[n])
                gsub(/["'"'"']/, "", wa_cmd[n])
                gsub(/[[:space:]]+$/, "", wa_cmd[n])
            }
            next
        }
        if (/^  workaround:/) { v=$2; if (v ~ /true|yes/) wa[n]=1; next }
        if (/^  (cmd_id|cmd):/) {
            wa_cmd[n]=$0
            sub(/^  (cmd_id|cmd):[[:space:]]*/, "", wa_cmd[n])
            gsub(/["'"'"']/, "", wa_cmd[n])
            gsub(/[[:space:]]+$/, "", wa_cmd[n])
            next
        }
        if (/^  brainwash_check:/) { brainwash[n]=1; has_brainwash_field[n]=1; next }
        if (/^  category:/) { sub(/^  category: */, ""); gsub(/["'"'"']/, ""); cat[n]=$0; next }
        if (/^  root_cause:/) { sub(/^  root_cause: */, ""); gsub(/["'"'"']/, ""); rc[n]=substr($0,1,60); next }
        next
    }
    FILENAME ~ /queue\/shogun_to_karo\.yaml$/ {
        if (/^  [^ ][^ ]*:[[:space:]]*$/) {
            if (cmd != "" && cmd_status == "pending" && has_da) {
                orphan_found++
                orphan_cmds = orphan_cmds (orphan_cmds != "" ? ", " : "") cmd
            }
            cmd = $0
            sub(/^  /, "", cmd)
            sub(/:.*/, "", cmd)
            cmd_status = ""
            has_da = 0
            next
        }
        if (/^    status:/) {
            s = $0
            sub(/.*status: */, "", s)
            gsub(/["'"'"']/, "", s)
            gsub(/ /, "", s)
            cmd_status = s
            next
        }
        if (/^    delegated_at:/) { has_da = 1; next }
    }
    END {
        if (inbox_entry && inbox_read_false && inbox_type == "cmd_new") {
            unread_cmd_new++
            if (unread_cmd_new <= 3) {
                item = inbox_id
                if (item == "") item = "unknown"
                if (inbox_ts != "") item = item "@" inbox_ts
                if (inbox_content != "") item = item " " inbox_content
                gsub(/\|/, "/", item)
                unread_cmd_new_items = unread_cmd_new_items (unread_cmd_new_items != "" ? "; " : "") item
            }
        }
        if (ins_id != "" && ins_status == "pending") {
            pending_insights++
            pending_insight_id[pending_insights] = ins_id
            pending_insight_priority[pending_insights] = ins_priority
            pending_insight_text[pending_insights] = ins_text
        }
        if (cmd != "" && cmd_status == "pending" && has_da) {
            orphan_found++
            orphan_cmds = orphan_cmds (orphan_cmds != "" ? ", " : "") cmd
        }
        print "UNREAD|" unread+0
        print "UNREAD_CMD_NEW|" unread_cmd_new+0 "|" unread_cmd_new_items
        print "INSIGHTS|" pending_insights+0
        insight_start = pending_insights - 2
        if (insight_start < 1) insight_start = 1
        for (i=insight_start; i<=pending_insights; i++) {
            priority = pending_insight_priority[i]
            if (priority == "") priority = "medium"
            text = pending_insight_text[i]
            if (text == "") text = "(no insight text)"
            print "INSIGHT_ITEM|" pending_insight_id[i] "|" priority "|" text
        }
        print "GP|" gp_pending+0
        print "PD|" pd_total+0 "|" pd_resolved+0
        s = (n > 5) ? n-4 : 1; total = n - s + 1
        if (total < 0) total = 0
        wc=0; cat_str=""; cause_str=""; max_cat=""; max_count=0
        for (i=s; i<=n; i++) {
            if (wa[i]) {
                wc++
                cats[cat[i]]++
                if (rc[i] != "") cause_str = cause_str (cause_str != "" ? " / " : "") rc[i]
            }
        }
        for (c in cats) {
            cat_str = cat_str (cat_str != "" ? ", " : "") c ":" cats[c]
            if (cats[c] > max_count) { max_count = cats[c]; max_cat = c }
        }
        if (cat_str == "") cat_str = "none"
        if (cause_str == "") cause_str = "none"
        if (max_cat == "") max_cat = "none"
        print "WA|" wc "|" total "|" cat_str "|" cause_str "|" max_cat "|" max_count+0
        clean_streak = 0
        for (i=n; i>=1; i--) {
            if (wa[i]) break
            clean_streak++
        }
        latest_regression = (n > 0 && wa[n]) ? 1 : 0
        latest_cmd = (n > 0 && wa_cmd[n] != "") ? wa_cmd[n] : "unknown"
        latest_cat = (n > 0 && cat[n] != "") ? cat[n] : "uncategorized"
        print "WACLEAN|" clean_streak "|" n+0 "|" latest_regression "|" latest_cmd "|" latest_cat
        bw_missing = 0
        bw_cmds = ""
        for (i=s; i<=n; i++) {
            if (wa[i] && !brainwash[i]) {
                bw_missing++
                cmd_label = (wa_cmd[i] != "") ? wa_cmd[i] : "unknown"
                bw_cmds = bw_cmds (bw_cmds != "" ? ", " : "") cmd_label
            }
        }
        print "WABRAINWASH|" bw_missing "|" bw_cmds
        print "ORPHAN|" orphan_found+0 "|" orphan_cmds
    }
' "${_AGG_FILES[@]}" > "$_aggregate_tmp" 2>/dev/null || true
{
    printf '%s\n' "$_AGG_SIG"
    cat "$_aggregate_tmp"
} > "$_AGGREGATE_CACHE"
) &
_AGG_PID=$!
for _pid in "${_META_PIDS[@]}"; do wait "$_pid" 2>/dev/null || true; done
wait "$_AGG_PID" 2>/dev/null || true
while IFS='|' read -r _agg_key _agg_a _agg_b _agg_c _agg_d _agg_e _agg_f; do
    case "$_agg_key" in
        STATUS) _NINJA_STATUS_CACHE[$_agg_a]=$_agg_b ;;
        UNREAD) unread=${_agg_a:-0} ;;
        UNREAD_CMD_NEW) unread_cmd_new=${_agg_a:-0}; unread_cmd_new_items=${_agg_b:-} ;;
        INSIGHTS) _insight_pending_count=${_agg_a:-0} ;;
        INSIGHT_ITEM) _insight_recent_items="${_insight_recent_items}    ${_agg_a} [${_agg_b:-medium}] ${_agg_c}"$'\n' ;;
        GP) _gp_pending_count=${_agg_a:-0} ;;
        PD) total_d=${_agg_a:-0}; resolved_d=${_agg_b:-0} ;;
        WA) wa_result="${_agg_a}|${_agg_b}|${_agg_c}|${_agg_d}|${_agg_e}|${_agg_f}" ;;
        WACLEAN) wa_clean_result="${_agg_a}|${_agg_b}|${_agg_c}|${_agg_d}|${_agg_e}" ;;
        WABRAINWASH) wa_brainwash_result="${_agg_a}|${_agg_b}" ;;
        ORPHAN) orphan_result="${_agg_a}|${_agg_b}" ;;
    esac
done < "$_aggregate_tmp"
if [[ -f "$_phase_guide_1_tmp" ]]; then _phase_guide_1="$(<"$_phase_guide_1_tmp")"; fi
if [[ -f "$_phase_guide_2_tmp" ]]; then _phase_guide_2="$(<"$_phase_guide_2_tmp")"; fi
if [[ -f "$_session_summary_tmp" ]]; then _prev_session_summary="$(<"$_session_summary_tmp")"; fi
[ -z "$_prev_session_summary" ] && _prev_session_summary="(前セッション要約なし)"
if [[ -f "$_bulletin_tmp" ]]; then
    while IFS= read -r _blt_line; do
        case "$_blt_line" in
            COUNT:\ *) _bulletin_count=${_blt_line#COUNT: } ;;
            ITEM:\ *) _bulletin_items="${_bulletin_items}    ${_blt_line#ITEM: }"$'\n' ;;
        esac
    done < "$_bulletin_tmp"
fi
_bulletin_count=${_bulletin_count:-0}
rm -f "$_phase_guide_1_tmp" "$_phase_guide_2_tmp" "$_session_summary_tmp" "$_bulletin_tmp"

echo "=== 家老起動チェック $(date '+%H:%M:%S') ==="
echo ""

# --- Check 1: deepdive必読ファイル存在確認 + 強制表示 ---
echo "■ deepdive必読ファイル"
REQUIRED_READ="$SCRIPT_DIR/memory/deepdive_why_chain_20260321.md"
if [ -f "$REQUIRED_READ" ]; then
    echo "  OK: $(basename "$REQUIRED_READ") 存在確認"
else
    overall="ALERT"
    alerts+=("必読ファイル不在: memory/deepdive_why_chain_20260321.md")
    echo "  ALERT: $REQUIRED_READ が存在しない"
fi
REQUIRED_READ2="$SCRIPT_DIR/memory/deepdive_karo_verification_20260405.md"
if [ -f "$REQUIRED_READ2" ]; then
    echo "  OK: $(basename "$REQUIRED_READ2") 存在確認"
else
    overall="ALERT"
    alerts+=("必読ファイル不在: memory/deepdive_karo_verification_20260405.md")
    echo "  ALERT: $REQUIRED_READ2 が存在しない"
fi
echo ""

# Phase逐次読込ガイド（キャッシュ済みpython3出力を表示）
echo "  ■ Phase逐次読込ガイド（全文一括Read禁止。1 Phaseずつ読み、自問してから次へ）"
echo "  $(basename "$REQUIRED_READ"):"
if [ -n "$_phase_guide_1" ]; then
    echo "$_phase_guide_1"
else
    echo "    (ファイル不在またはPhaseなし)"
fi
echo "  $(basename "$REQUIRED_READ2"):"
if [ -n "$_phase_guide_2" ]; then
    echo "$_phase_guide_2"
else
    echo "    (ファイル不在またはPhaseなし)"
fi
echo "  ★ 全Phase必読（スキップ禁止）。1 Phaseずつ Read(offset, limit) で読め。各Phase後に1行自問。全文一括禁止。"
echo ""

# --- Check 1.5: 追体験検証Q4 (前セッション出来事注入) ---
echo "■ 追体験検証Q4（CLAUDE.md Step 2.88 — 省略厳禁）"
echo "  Q4: deepdive_why_chain Phase NがPhase Mで覆された例を1つ挙げよ。なぜ覆されたか？（時系列×因果）"
echo "  [前セッション出来事] ${_prev_session_summary:-(前セッション要約なし)}"
echo "  ※ Q4は前セッションの出来事を手がかりに因果をたどれ。暗記したPhase例を貼るな。"
echo ""

# --- Check 2: 陣形図(karo_snapshot.txt)の鮮度 ---
echo "■ 陣形図鮮度"
snapshot="$SCRIPT_DIR/queue/karo_snapshot.txt"
if [ -f "$snapshot" ]; then
    snap_time=$(awk 'NR <= 2 && /Generated:/ { sub(/.*Generated: /, ""); print; exit }' "$snapshot")
    if [ -n "$snap_time" ]; then
        # 経過時間を計算（秒）
        snap_epoch=$(date -d "$snap_time" +%s 2>/dev/null || echo "0")
        now_epoch=$(date +%s)
        if [ "$snap_epoch" -gt 0 ]; then
            elapsed_sec=$((now_epoch - snap_epoch))
            elapsed_min=$((elapsed_sec / 60))
            echo "  最終更新: $snap_time (${elapsed_min}分前)"
            if [ "$elapsed_min" -gt 30 ]; then
                echo "  WARN: 陣形図が30分以上古い"
                if [ "$overall" != "ALERT" ]; then
                    overall="WARN"
                    alerts+=("陣形図が${elapsed_min}分前")
                fi
            fi
        else
            echo "  最終更新: $snap_time (経過時間計算不可)"
        fi
    else
        echo "  WARNING: Generated行なし"
    fi
else
    echo "  WARNING: karo_snapshot.txt不在"
    if [ "$overall" != "ALERT" ]; then
        overall="WARN"
        alerts+=("陣形図不在")
    fi
fi

# --- Check 2.5: 忍者ペインCTX実態（snapshot突合） ---
echo "■ 忍者ペインCTX実態"

# capture-pane を並列実行（R2）
declare -A _CTX_TMPF
declare -A _NINJA_PANE_IDX
declare -a _CTX_PIDS=()
for ninja in $_KARO_NINJA_NAMES; do
    task_status=${_NINJA_STATUS_CACHE[$ninja]:-}
    if [ -z "$task_status" ] && [ -f "$SCRIPT_DIR/queue/tasks/${ninja}.yaml" ]; then
        task_status=$(awk '/^[[:space:]]*status:/ { print $2; exit }' "$SCRIPT_DIR/queue/tasks/${ninja}.yaml" 2>/dev/null || true)
    fi
    pane_idx=${_PANE_IDX_BY_AGENT[$ninja]:-}
    _NINJA_PANE_IDX[$ninja]=$pane_idx
    if [[ "$task_status" =~ ^(assigned|in_progress)$ ]] && [ -n "$pane_idx" ]; then
        _tmpf=$(mktemp)
        _CTX_TMPF[$ninja]=$_tmpf
        (
            _pane_output=$(tmux capture-pane -t "${_AGENTS_WINDOW_TARGET}.${pane_idx}" -p -J -S -30 2>/dev/null || true)
            karo_startup_extract_ctx_pct "$_pane_output" > "$_tmpf" || true
        ) &
        _CTX_PIDS+=($!)
    fi
done
for _pid in "${_CTX_PIDS[@]}"; do wait "$_pid" 2>/dev/null || true; done

stall_count=0
for ninja in $_KARO_NINJA_NAMES; do
    task_status=${_NINJA_STATUS_CACHE[$ninja]:-}
    if [ -z "$task_status" ] && [ -f "$SCRIPT_DIR/queue/tasks/${ninja}.yaml" ]; then
        task_status=$(awk '/^[[:space:]]*status:/ { print $2; exit }' "$SCRIPT_DIR/queue/tasks/${ninja}.yaml" 2>/dev/null || true)
    fi
    pane_idx=${_NINJA_PANE_IDX[$ninja]}
    if [[ "$task_status" =~ ^(assigned|in_progress)$ ]] && [ -n "$pane_idx" ]; then
        if [[ -f "${_CTX_TMPF[$ninja]}" ]]; then
            IFS= read -r ctx < "${_CTX_TMPF[$ninja]}" || ctx=""
        else
            ctx=""
        fi
        rm -f "${_CTX_TMPF[$ninja]}"
        if [[ "$task_status" =~ ^(assigned|in_progress)$ && ( "$ctx" == "0%" || -z "$ctx" ) ]]; then
            echo "  ⚠ $ninja: CTX=${ctx:-EMPTY} status=$task_status → STALL疑い"
            stall_count=$((stall_count + 1))
        else
            echo "  $ninja: CTX=${ctx:-?} status=${task_status:-?}"
        fi
    elif [ -n "$pane_idx" ]; then
        echo "  $ninja: CTX=- status=${task_status:-?}"
    else
        echo "  $ninja: ペイン不在"
    fi
done
if [ "$stall_count" -gt 0 ]; then
    echo "  ALERT: ${stall_count}名STALL疑い。ペインを目視確認せよ"
    overall="ALERT"
    alerts+=("${stall_count}名STALL疑い(assigned+CTX:0%)")
fi
echo ""

# --- Check 3: inbox未読件数 ---
echo "■ inbox未読"
if [ -f "$SCRIPT_DIR/queue/inbox/karo.yaml" ]; then
    unread=${unread:-0}
    echo "  未読: ${unread}件"
    if [ "${unread_cmd_new:-0}" -gt 0 ]; then
        echo "  ALERT: 未処理cmd_new ${unread_cmd_new}件。配備漏れ防止のため通常作業禁止"
        [ -n "${unread_cmd_new_items:-}" ] && echo "    ${unread_cmd_new_items}"
        overall="ALERT"
        alerts+=("未処理cmd_new: ${unread_cmd_new}件")
    elif [ "$unread" -gt 0 ]; then
        echo "  WARN: inbox未読あり。nudge/Stop hookに依存せず通常作業前に処理せよ"
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
            alerts+=("inbox未読: ${unread}件")
        fi
    fi
else
    echo "  未読: 0件 (inbox不在)"
    unread=0
fi

# --- Check 3.5: 掲示板未確認 ---
echo "■ 掲示板未確認"
if [ "${_bulletin_count:-0}" -gt 0 ]; then
    echo "  WARN: 未確認掲示板 ${_bulletin_count}件"
    [ -n "$_bulletin_items" ] && echo "$_bulletin_items"
    if [ "$overall" != "ALERT" ]; then
        overall="WARN"
        alerts+=("掲示板未確認: ${_bulletin_count}件")
    fi
else
    echo "  未確認: 0件"
fi

# --- Check 3.7: 軍師GP pending検出 ---
_gp_log="$SCRIPT_DIR/logs/gunshi_review_log.yaml"
if [ -f "$_gp_log" ]; then
    _gp_pending_count=${_gp_pending_count:-0}
    if [ "${_gp_pending_count:-0}" -gt 0 ]; then
        echo "■ 軍師GP pending"
        echo "  WARN: pending GP ${_gp_pending_count}件 (logs/gunshi_review_log.yaml)"
        echo "  → 次cmdサイクルで対処せよ"
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
            alerts+=("軍師GP pending: ${_gp_pending_count}件")
        fi
    fi
fi

# --- Check 3.8: レビュー品質スケール計測 ---
echo "■ レビュー品質スケール"
_review_quality_line="$(review_quality_scale_summary "$SCRIPT_DIR/logs/gunshi_review_log.yaml" 20 "$SCRIPT_DIR/queue/shogun_to_karo.yaml" "$SCRIPT_DIR/logs/gate_metrics.log" 2>/dev/null || echo "DATA_MISSING")"
if [[ "$_review_quality_line" == RATE* ]]; then
    read -r _rq_tag _rq_rate _rq_warn _rq_total _rq_old_rate <<< "$_review_quality_line"
    if [ -n "${_rq_old_rate:-}" ] && [ "${_rq_old_rate}" != "${_rq_rate}" ] 2>/dev/null; then
        echo "  WARN率 ${_rq_rate}% (${_rq_warn}/${_rq_total}, cmd_id単位最終verdict集計, 旧方式=${_rq_old_rate}%)"
    else
        echo "  WARN率 ${_rq_rate}% (${_rq_warn}/${_rq_total}, cmd_id単位最終verdict集計)"
    fi
    if [ "${_rq_rate:-0}" -gt 30 ] 2>/dev/null; then
        echo "  WARN: レビュー品質WARN率が30%超"
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
            alerts+=("レビュー品質スケール: WARN率${_rq_rate}%")
        fi
    else
        echo "  OK: レビュー品質WARN率30%以下"
    fi
else
    echo "  データ不足: 直近レビューなし"
fi

# --- Check 4: pending_decisions未解決件数 ---
echo "■ pending_decisions"
pd_file="$SCRIPT_DIR/queue/pending_decisions.yaml"
if [ -f "$pd_file" ]; then
    total_d=${total_d:-0}
    resolved_d=${resolved_d:-0}
    pending_count=$((total_d - resolved_d))
    echo "  未解決: ${pending_count}件"
    if [ "$pending_count" -gt 0 ]; then
        echo "  → 未解決裁定あり。作業開始前に確認せよ"
    fi
else
    echo "  pending_decisions.yaml不在"
    pending_count=0
fi

# --- Check 4.5: insights未処理件数 + 直近3件 ---
echo "■ insights未処理"
insights_file="$SCRIPT_DIR/queue/insights.yaml"
if [ -f "$insights_file" ]; then
    _insight_pending_count=${_insight_pending_count:-0}
    echo "  pending: ${_insight_pending_count}件"
    if [ "${_insight_pending_count:-0}" -gt 0 ]; then
        echo "  直近3件:"
        if [ -n "${_insight_recent_items:-}" ]; then
            printf "%s" "$_insight_recent_items"
        else
            echo "    (項目取得不可)"
        fi
    fi
else
    echo "  pending: 0件 (insights.yaml不在)"
fi

# --- Check 5: karo_workarounds直近5件の傾向サマリ ---
echo "■ karo_workarounds傾向"
wa_file="$SCRIPT_DIR/logs/karo_workarounds.yaml"
if [ -f "$wa_file" ]; then
    wa_result=${wa_result:-"0|0|error|awk error|none|0"}
    IFS='|' read -r WA_COUNT WA_TOTAL WA_CATS WA_CAUSES WA_MAX_CAT WA_MAX_COUNT <<< "$wa_result"
    wa_clean_result=${wa_clean_result:-"0|0|0|unknown|uncategorized"}
    IFS='|' read -r WA_CLEAN_STREAK WA_ENTRY_TOTAL WA_REGRESSION WA_LATEST_CMD WA_LATEST_CAT <<< "$wa_clean_result"
    wa_brainwash_result=${wa_brainwash_result:-"0|"}
    IFS='|' read -r WA_BRAINWASH_MISSING WA_BRAINWASH_CMDS <<< "$wa_brainwash_result"
    echo "  直近${WA_TOTAL}件: workaround=${WA_COUNT}件"
    echo "  連続clean: ${WA_CLEAN_STREAK}件 (総記録${WA_ENTRY_TOTAL}件)"
    if [ "${WA_REGRESSION:-0}" -eq 1 ]; then
        echo "  ALERT: WA復活 — 最新cmd ${WA_LATEST_CMD} が workaround=true (category=${WA_LATEST_CAT})"
        overall="ALERT"
        alerts+=("WA復活: ${WA_LATEST_CMD} (${WA_LATEST_CAT})")
    fi
    if [ "$WA_COUNT" -gt 0 ]; then
        echo "  カテゴリ: ${WA_CATS}"
        echo "  原因: ${WA_CAUSES}"
        if [ "${WA_MAX_COUNT:-0}" -ge 3 ]; then
            echo "  ALERT: 同カテゴリ ${WA_MAX_CAT} が直近5件で ${WA_MAX_COUNT}件累積"
            overall="ALERT"
            alerts+=("workaround同カテゴリ累積: ${WA_MAX_CAT}=${WA_MAX_COUNT}")
        fi
    fi
    if [ "${WA_BRAINWASH_MISSING:-0}" -gt 0 ]; then
        echo "  WARN: workaround brainwash_check未記入 ${WA_BRAINWASH_MISSING}件: ${WA_BRAINWASH_CMDS}"
        echo "  → 家老判断が創造主の洗脳/早期終了/低優先化に乗っていないか記録せよ"
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
        fi
        alerts+=("workaround brainwash_check未記入: ${WA_BRAINWASH_MISSING}件")
    fi
else
    echo "  karo_workarounds.yaml不在"
fi

# --- Check 5.5: WAデータ品質（False WA TOP3強制表示） ---
echo "■ WAデータ品質"
if [ -n "${_WA_DQ_PID:-}" ]; then wait "$_WA_DQ_PID" 2>/dev/null || true; fi
cat "$_WA_DQ_TMP"
if grep -q "^ISSUES:" "$_WA_DQ_TMP" 2>/dev/null; then
    overall="ALERT"
    alerts+=("WAデータ品質問題: gate_wa_data_quality.sh")
fi

# --- Check 6: 全体workaround率（バックグラウンド結果を回収） ---
if [ -n "$_WA_RATE_PID" ]; then wait "$_WA_RATE_PID" 2>/dev/null || true; fi
cat "$_WA_RATE_TMP"

# --- Check 7: 忍者別workaround率（バックグラウンド結果を回収） ---
echo "■ 忍者別workaround率"
if [ -n "$_NINJA_WA_PID" ]; then wait "$_NINJA_WA_PID" 2>/dev/null || true; fi
cat "$_NINJA_WA_TMP"

# --- Check 8: idle自走プロンプト ---
echo ""
echo "■ 自走チェック"
# 全忍者がidle or completedか確認（Check 2.5のstatusキャッシュを再利用: R3）
active_ninjas=0
for ninja in $_KARO_NINJA_NAMES; do
    ninja_status=${_NINJA_STATUS_CACHE[$ninja]:-""}
    if [ -z "$ninja_status" ]; then
        task_file="$SCRIPT_DIR/queue/tasks/${ninja}.yaml"
        [ -f "$task_file" ] && ninja_status=$(awk '/^[[:space:]]*status:/{print $2; exit}' "$task_file" 2>/dev/null)
    fi
    if [[ "$ninja_status" =~ ^(assigned|acknowledged|in_progress)$ ]]; then
        active_ninjas=$((active_ninjas + 1))
    fi
done
if [ "$active_ninjas" -eq 0 ] && [ "$unread" -eq 0 ]; then
    echo "  全忍者idle + inbox未読=0。cmd待ち状態。"
    echo "  ★★★ idle時自走プロトコルを実行せよ（instructions/karo.md参照） ★★★"
    echo "  Step 1: workaroundパターン分析(直近10件)"
    echo "  Step 2: 忍者品質プロファイル(個別WA率)"
    echo "  Step 3: 教訓有効性監査(有用率0%→deprecated)"
    echo "  Step 4: deploy_task.sh注入品質(教訓使用実態)"
    echo "  Step 5: パターン発見→なぜなぜ→行動"
    echo "  → 止まるな。1つ完了したら次へ"
else
    echo "  active忍者: ${active_ninjas}名 / inbox未読: ${unread}件"
fi

# --- Check 9: cmd配備漏れ検出(pending+delegated_at残存) ---
echo "■ cmd配備漏れチェック"
stk_file="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
if [ -f "$stk_file" ]; then
    orphan_result=${orphan_result:-"0|"}
    IFS='|' read -r ORPHAN_COUNT ORPHAN_CMDS <<< "$orphan_result"
    if [ "$ORPHAN_COUNT" -gt 0 ]; then
        echo "  ALERT: ${ORPHAN_COUNT}件のcmdがpending+delegated_at残存: ${ORPHAN_CMDS}"
        overall="ALERT"
        alerts+=("cmd配備漏れ${ORPHAN_COUNT}件: ${ORPHAN_CMDS}")
    else
        echo "  OK: 配備漏れcmdなし"
    fi
else
    echo "  SKIP: shogun_to_karo.yaml不在"
fi
echo ""

# tmpファイル削除
rm -f "$_WA_RATE_TMP" "$_WA_RATE_ERR_TMP" "$_NINJA_WA_TMP" "$_WA_DQ_TMP" \
    "$_aggregate_tmp"

# --- Check 9.5: 三層記憶DB健全性 ---
echo "■ 三層記憶DB健全性"
three_layer_health_script="$SCRIPT_DIR/scripts/gates/gate_three_layer_health.sh"
if [ -x "$three_layer_health_script" ]; then
    if ! three_layer_health_output="$(bash "$three_layer_health_script" 2>&1)"; then
        printf '%s\n' "$three_layer_health_output" | sed 's/^/  /'
        if [ "$overall" != "ALERT" ] && [ "$overall" != "BLOCK" ]; then overall="WARN"; fi
        alerts+=("三層記憶DB健全性: WARN")
    else
        printf '%s\n' "$three_layer_health_output" | sed 's/^/  /'
    fi
else
    echo "  WARN: gate_three_layer_health.sh不在"
    if [ "$overall" != "ALERT" ] && [ "$overall" != "BLOCK" ]; then overall="WARN"; fi
    alerts+=("三層記憶DB健全性: gate不在")
fi

# --- Check 10: スキル品質サマリ ---
echo "■ スキル品質"
echo "  フェーズ別スキル一覧:"
echo "    cmd完了処理: /cmd-complete"
echo "    家老自立配備(CI修正/hotfix/recon2単独): /karo-direct"
echo "    偵察2名配備: /recon-dual"
echo "    ダッシュボード更新: /dashboard-update"
skill_summary_script="$SCRIPT_DIR/scripts/skill_execution_log.sh"
if [ -x "$skill_summary_script" ]; then
    _skill_cache_sig=""
    _skill_current_sig=""
    if [ -f "$SCRIPT_DIR/logs/skill_execution_log.yaml" ]; then
        _skill_current_sig="$(stat -c '%Y:%s' "$SCRIPT_DIR/logs/skill_execution_log.yaml" 2>/dev/null || echo '')"
    fi
    _skill_current_sig="${_skill_current_sig}|gate:$(stat -c '%Y:%s' "$SCRIPT_DIR/scripts/gates/gate_karo_startup.sh" 2>/dev/null || echo '')"
    _skill_current_sig="${_skill_current_sig}|summary:$(stat -c '%Y:%s' "$SCRIPT_DIR/scripts/skill_execution_log.sh" 2>/dev/null || echo '')"
    if [[ -f "$_SKILL_SUMMARY_CACHE" ]]; then
        IFS= read -r _skill_cache_sig < "$_SKILL_SUMMARY_CACHE" || _skill_cache_sig=""
    fi
    if [[ -f "$_SKILL_SUMMARY_CACHE" ]] \
        && [[ "$_skill_cache_sig" == "$_skill_current_sig" ]] \
        && (( _now_epoch - $(stat -c %Y "$_SKILL_SUMMARY_CACHE" 2>/dev/null || echo 0) < _SKILL_SUMMARY_CACHE_TTL )); then
        skill_summary="$(tail -n +2 "$_SKILL_SUMMARY_CACHE")"
    else
        skill_summary="$(skill_execution_summary_fast "$SCRIPT_DIR/logs/skill_execution_log.yaml" 2>/dev/null || true)"
        {
            printf '%s\n' "$_skill_current_sig"
            printf '%s\n' "$skill_summary"
        } > "$_SKILL_SUMMARY_CACHE"
    fi
    skill_rows="$(printf '%s\n' "$skill_summary" | tail -n +2 | awk 'NF { print }')"
    if [ -n "$skill_rows" ]; then
        skill_quality_line="$(printf '%s\n' "$skill_rows" | awk -F' \\| ' '
            NF >= 4 {
                out = out (out != "" ? ", " : "") $1 " FAIL:" $2
                count++
                if (count >= 5) exit
            }
            END { print out }
        ')"
        echo "  スキル品質: ${skill_quality_line}"
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
            alerts+=("スキル品質: FAIL記録あり")
        fi
    else
        echo "  スキル品質: 全PASS"
    fi
else
    echo "  SKIP: skill_execution_log.sh が存在しないか実行権限なし"
fi
echo "  スキル推薦 precision/recall:"
skill_recommend_metrics_script="$SCRIPT_DIR/scripts/skill_recommend_metrics.sh"
if [ -x "$skill_recommend_metrics_script" ] || [ -f "$skill_recommend_metrics_script" ]; then
    set +e
    _skill_rec_out="$(bash "$skill_recommend_metrics_script" 30 2>&1)"
    _skill_rec_status=$?
    set -e
    printf '%s\n' "$_skill_rec_out" | sed 's/^/    /'
    if [ "$_skill_rec_status" -eq 2 ] && [ "$overall" != "ALERT" ]; then
        overall="WARN"
        alerts+=("スキル推薦精度: Phase 3 cmd起票候補 — 推薦抑制/aliases補完")
    elif [ "$_skill_rec_status" -ne 0 ]; then
        overall="ALERT"
        alerts+=("スキル推薦精度: 集計失敗")
    fi
else
    echo "    SKIP: skill_recommend_metrics.sh 不在"
fi
echo ""

# --- Check 10.5: Codex hook禁止event ---
echo "■ Codex hook設定"
codex_hook_gate="$SCRIPT_DIR/scripts/gates/gate_codex_hooks_no_stop.sh"
if [ -x "$codex_hook_gate" ] || [ -f "$codex_hook_gate" ]; then
    set +e
    _codex_hook_out="$(bash "$codex_hook_gate" "$SCRIPT_DIR/.codex/hooks.json" 2>&1)"
    _codex_hook_status=$?
    set -e
    printf '%s\n' "$_codex_hook_out" | sed 's/^/  /'
    if [ "$_codex_hook_status" -ne 0 ]; then
        if [ "$overall" != "ALERT" ] && [ "$overall" != "BLOCK" ]; then overall="WARN"; fi
        alerts+=("Codex hook設定: Stop/UserPromptSubmit禁止違反")
    fi
else
    echo "  WARN: gate_codex_hooks_no_stop.sh 不在"
    if [ "$overall" != "ALERT" ] && [ "$overall" != "BLOCK" ]; then overall="WARN"; fi
    alerts+=("Codex hook設定: gate不在")
fi
echo ""

# --- セマンティクスインデックス鮮度 ---
echo "■ セマンティクスインデックス鮮度"
_si_index="$SCRIPT_DIR/docs/semantic-index/index.md"
if [ -f "$_si_index" ]; then
    _si_last_mod=$(stat -c %Y "$_si_index")
    _si_now=$(date +%s)
    _si_age_days=$(( (_si_now - _si_last_mod) / 86400 ))
    if [ "$_si_age_days" -ge 14 ]; then
        echo "  WARN: セマンティクスインデックスが${_si_age_days}日間未更新"
        if [ "$overall" != "ALERT" ]; then overall="WARN"; fi
        alerts+=("セマンティクスインデックス鮮度: ${_si_age_days}日未更新")
    else
        echo "  OK: ${_si_age_days}日前に更新"
    fi
else
    echo "  WARN: docs/semantic-index/index.md 不在"
    if [ "$overall" != "ALERT" ]; then overall="WARN"; fi
    alerts+=("セマンティクスインデックス: index不在")
fi
echo ""

# --- 稼働中cmdのtarget_pathから関連概念/因果辺を表示 ---
show_active_cmd_semantic_context
show_semantic_no_match_metrics

# --- 教訓効果計測(lesson_impact TOP5) ---
echo "■ 教訓効果計測"
_li_script="$SCRIPT_DIR/scripts/lesson_impact_analysis.sh"
_li_file="$SCRIPT_DIR/logs/lesson_impact.tsv"
if [ -x "$_li_script" ] && [ -f "$_li_file" ] && [ "$(wc -l < "$_li_file")" -gt 10 ]; then
    _li_output=$(timeout 10 bash "$_li_script" 2>/dev/null || true)
    _li_noise=$(echo "$_li_output" | awk '/^Low Reference Rate/,/^$/' | grep -c "ref_rate:  0%" || true)
    _li_harm=$(echo "$_li_output" | awk '/^High BLOCK Rate/,/^$/' | grep -c "BLOCK:100%" || true)
    echo "  noise候補(参照率0%): ${_li_noise}件, harm候補(BLOCK率100%): ${_li_harm}件"
    if [ "$_li_harm" -gt 3 ]; then
        echo "  ★ harm候補${_li_harm}件: 教訓改善/廃止を検討せよ"
    fi
else
    echo "  SKIP: lesson_impact.tsv不足"
fi
echo ""

# --- 洗脳監査(行動→結果検証の二値チェック) ---
echo "■ 洗脳監査(行動→結果検証)"
echo "  8パターン: (1)早期終了 (2)検証スキップ (3)他者依存 (4)緩い設計 (5)先送り (6)出力=仕事 (7)簡潔本能[質問形の範囲縮小提案含む=LS052] (8)完了急ぎ"
_wa_file="$SCRIPT_DIR/logs/karo_workarounds.yaml"
if [ -f "$_wa_file" ]; then
    # 直近20件のworkaround=trueエントリでbrainwash_check有無を計測
    _bw_audit=$(awk '
    BEGIN { total=0; has_bc=0; no_bc=0; no_bc_cmds="" }
    /^- (cmd_id|cmd|timestamp):/ { flush(); in_entry=1; wa=0; bc=0; cmd_label="" }
    in_entry && /workaround: true/ { wa=1 }
    in_entry && /brainwash_check:/ { bc=1 }
    in_entry && /cmd_id:/ { sub(/.*cmd_id: */, ""); gsub(/["'"'"']/, ""); cmd_label=$0 }
    function flush() {
        if (in_entry && wa) {
            total++
            if (bc) has_bc++
            else {
                no_bc++
                if (no_bc_cmds != "") no_bc_cmds = no_bc_cmds ", "
                no_bc_cmds = no_bc_cmds cmd_label
            }
        }
        in_entry=0; wa=0; bc=0; cmd_label=""
    }
    END { flush(); print total "|" has_bc "|" no_bc "|" no_bc_cmds }
    ' "$_wa_file")
    IFS='|' read -r _bwa_total _bwa_has _bwa_no _bwa_cmds <<< "$_bw_audit"
    _bwa_total=${_bwa_total:-0}
    _bwa_has=${_bwa_has:-0}
    _bwa_no=${_bwa_no:-0}
    echo "  workaround=true: ${_bwa_total}件(brainwash_check有: ${_bwa_has}, 無: ${_bwa_no})"
    if [ "$_bwa_no" -gt 0 ]; then
        echo "  WARN: brainwash_check未記入のworkaround ${_bwa_no}件: ${_bwa_cmds}"
        echo "  → 行動(workaround適用)の結果を検証したか？洗脳パターンに乗っていないか？"
        if [ "$overall" != "ALERT" ]; then overall="WARN"; fi
        alerts+=("洗脳監査: brainwash_check未記入WA ${_bwa_no}件")
    else
        echo "  OK: 全workaroundにbrainwash_check記入済み"
    fi
else
    echo "  SKIP: karo_workarounds.yaml不在"
fi
echo "  ★ 自問: 直近の配備/WA判断で「検証スキップ」「完了急ぎ」に乗っていないか？"
echo ""

# --- ストリーク検出: 3セッション連続WARN/ALERT→BLOCK昇格 (L7横展開: gate_shogun_startup.sh準拠) ---
if [ "${#alerts[@]}" -gt 0 ]; then
    mkdir -p "$(dirname "$STARTUP_ALERT_HISTORY")"
    # §3.2: python3→awk置換(~650ms削減)。alert文字列は空白を含むためtmp経由で1行1alertにする。
    _current_alerts_file="$(mktemp)"
    printf '%s\n' "${alerts[@]}" > "$_current_alerts_file"
    _streak_result=$(awk -F'\t' -v threshold="$STARTUP_WARN_STREAK_THRESHOLD" '
    BEGIN { n_runs = 0 }
    NR == FNR {
        if ($0 != "") current[$0] = 1
        next
    }
    NF == 2 && $2 != "__OK__" {
        if ($1 != prev_run) { if (prev_run != "") n_runs++; prev_run = $1 }
        run_keys[n_runs, $2] = 1
    }
    END {
        if (prev_run != "") n_runs++
        start = n_runs - (threshold - 1)
        if (start < 0) start = 0
        for (k in current) {
            streak = 0
            for (r = start; r < n_runs; r++) {
                if ((r, k) in run_keys) streak++
            }
            if (streak == threshold - 1) print k
        }
    }' "$_current_alerts_file" "$STARTUP_ALERT_HISTORY" 2>/dev/null || true)
    if [ -n "$_streak_result" ]; then
        echo "■ ★★★ CRITICAL: startup WARN/ALERT連続出現 ★★★"
        while IFS= read -r _streak_key; do
            [ -n "$_streak_key" ] || continue
            echo "  ★★★ CRITICAL: ${_streak_key} が${STARTUP_WARN_STREAK_THRESHOLD}セッション連続"
            echo "  先送り判断検出: ${STARTUP_WARN_STREAK_THRESHOLD}セッション連続で未解消。低優先/後で扱いにした穴の証拠として今ふさげ。"
            alerts+=("先送りCRITICAL: ${_streak_key} が${STARTUP_WARN_STREAK_THRESHOLD}セッション連続")
        done <<< "$_streak_result"
        # 家老BLOCKは忍者配備全停止を招くため、BLOCK昇格せず起動は許可する
        # 代わりにntfyで殿/将軍に通知し、CRITICAL表示で注意喚起
        if [ "$overall" != "ALERT" ] && [ "$overall" != "BLOCK" ]; then overall="ALERT"; fi
        bash "$SCRIPT_DIR/scripts/ntfy.sh" "【家老CRITICAL】先送り${STARTUP_WARN_STREAK_THRESHOLD}セッション連続検出。起動は許可するが即対処必須" 2>/dev/null || true
    fi
fi

# --- 三層記憶使用義務リマインダー(殿厳命2026-06-10: 使用しないのはバグ) ---
echo ""
echo "■ 三層記憶使用義務(L0-L7貫通)"
echo "  ★ 全行動で三層記憶を検索してから行動せよ。使用しないのはバグ"
echo "  (1) bash scripts/memory_db_query.sh \"SELECT ts,substr(summary,1,80) FROM events WHERE summary LIKE '%キーワード%' ORDER BY ts DESC LIMIT 3\""
echo "  (2) bash scripts/semantic_search.sh \"キーワード\""
echo "  (3) 回答に[MEM: memory_db ts=YYYY-MM-DD]タグで引用"
echo "  理解を出力するな。使え。contextファイル更新だけでは三層貫通ではない"

# --- 総合判定 ---
echo ""
echo "=== 総合判定: $overall ==="
if [ ${#alerts[@]} -gt 0 ]; then
    for a in "${alerts[@]}"; do
        echo "  ⚠ $a"
    done
    echo "  ★ ALERT=バグ。「確認した」で閉じるな。根因調査→修正→commitまで回せ(洗脳#6防止)"
    # L4: ALERTペンディングフラグ設置 — stop hookが検知しBLOCK
    _alert_flag="$SCRIPT_DIR/queue/gates/karo_alert_pending.txt"
    printf '%s\n' "${alerts[@]}" > "$_alert_flag"
    echo "  [L4] ALERT pendingフラグ設置: $_alert_flag (stop hookがBLOCK)"
fi

# --- Alert history記録 (gate_shogun_startup.sh準拠) ---
mkdir -p "$(dirname "$STARTUP_ALERT_HISTORY")"
_startup_run_id="$(date '+%Y-%m-%dT%H:%M:%S%z')"
if [ ${#alerts[@]} -gt 0 ]; then
    for a in "${alerts[@]}"; do
        printf '%s\t%s\n' "$_startup_run_id" "$a" >> "$STARTUP_ALERT_HISTORY"
    done
else
    printf '%s\t__OK__\n' "$_startup_run_id" >> "$STARTUP_ALERT_HISTORY"
fi

# --- L1先送り自動エスカレーション: 先送りCRITICAL検出→将軍にinbox送信 ---
if [ ${#alerts[@]} -gt 0 ]; then
    _deferred_alerts=""
    for a in "${alerts[@]}"; do
        case "$a" in
            先送りCRITICAL:*)
                _deferred_alerts="${_deferred_alerts:+${_deferred_alerts}; }${a}"
                ;;
        esac
    done
    if [ -n "$_deferred_alerts" ]; then
        _deferred_message="家老startup先送りCRITICAL自動エスカレーション: ${_deferred_alerts}。家老が対処できないため将軍cmd起票を検討せよ"
        mkdir -p "$SCRIPT_DIR/queue/locks"
        _deferred_lock="$SCRIPT_DIR/queue/locks/karo_startup_escalation.lock"
        (
        flock -x 9
        _deferred_dup_status=$(python3 - "$SCRIPT_DIR/queue/inbox/shogun.yaml" "$_deferred_message" <<'PY' 2>/dev/null || true
import sys
from pathlib import Path

try:
    import yaml
except Exception:
    raise SystemExit(0)

path = Path(sys.argv[1])
target = sys.argv[2]
if not path.exists():
    raise SystemExit(0)

try:
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
except Exception:
    raise SystemExit(0)

for msg in data.get("messages") or []:
    if not isinstance(msg, dict):
        continue
    if msg.get("read"):
        continue
    if msg.get("from") == "karo" and msg.get("type") == "escalation" and msg.get("content") == target:
        print("duplicate_unread")
        break
PY
)
        if [ "$_deferred_dup_status" = "duplicate_unread" ]; then
            echo "  SKIP: 同一未読escalationが将軍inboxに存在 — 重複送信を抑制"
        else
            bash "$SCRIPT_DIR/scripts/inbox_write.sh" shogun \
                "$_deferred_message" \
                escalation karo 2>/dev/null || true
        fi
        ) 9>"$_deferred_lock"
        unset _deferred_message _deferred_dup_status _deferred_lock
    fi
fi
