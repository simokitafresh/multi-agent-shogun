#!/bin/bash
# semantic-links: [[ゲート品質統合フレームワーク]]
# gate_karo_startup.sh — 家老セッション起動時の全チェックを一括実行
# 目的: 5項目を一括チェックし、deepdive必読を自動化×強制
# Usage: bash scripts/gates/gate_karo_startup.sh
# 参考: gate_shogun_startup.sh（構造踏襲）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Round8 lane #0': complete entrypoint wall-clock telemetry.
KARO_STARTUP_TOTAL_T0_US="${EPOCHREALTIME/./}"
KARO_STARTUP_TOTAL_T0_US="${KARO_STARTUP_TOTAL_T0_US:0:16}"
DEFENSE_OVERHEAD_REPO_ROOT="${DEFENSE_OVERHEAD_REPO_ROOT:-$SCRIPT_DIR}"
# shellcheck source=scripts/lib/defense_overhead_writer.sh
source "$SCRIPT_DIR/scripts/lib/defense_overhead_writer.sh"
KARO_STARTUP_TOTAL_RECORDED=0
karo_startup_record_total() {
    local rc="${1:-0}" now_us wall_ms verdict
    [ "${KARO_STARTUP_TOTAL_RECORDED:-0}" -eq 0 ] || return 0
    KARO_STARTUP_TOTAL_RECORDED=1
    now_us="${EPOCHREALTIME/./}"
    now_us="${now_us:0:16}"
    wall_ms=$(( (now_us - KARO_STARTUP_TOTAL_T0_US + 999) / 1000 ))
    verdict=PASS
    [ "$rc" -eq 0 ] || verdict=FAIL
    defense_overhead_write_async gate_karo_startup karo_startup_total "$wall_ms" "$verdict" \
        "gate-karo-startup-${BASHPID}-${KARO_STARTUP_TOTAL_T0_US}" || true
}
karo_startup_total_on_exit() { local rc=$?; karo_startup_record_total "$rc"; return "$rc"; }
trap karo_startup_total_on_exit EXIT
# L821: ハードコード忍者名を排除。get_ninja_namesで動的取得
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/agent_config.sh" 2>/dev/null || true
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/gates/session_alerts_render.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/report_terminal_state.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/task_cmd_match.sh"
_KARO_NINJA_NAMES="$(get_ninja_names 2>/dev/null || echo 'hayate kagemaru hanzo saizo kotaro tobisaru')"

# cmd_4250: K/D分類の受領証を家老レーンで一次記録する。検知本体は
# このgateとninja_monitorの既存機構が担当し、将軍gateへ戻さない。
KARO_MIGRATION_LOG_FIRE=1 bash "$SCRIPT_DIR/scripts/gates/gate_karo_startup_migrated_checks.sh" "$SCRIPT_DIR"

overall="OK"
alerts=()
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/lib/disk_space_watch.sh"
_disk_measure="$(disk_space_watch_measure 2>/dev/null || true)"
IFS='|' read -r _disk_status _disk_available_kb _disk_warn_gb _disk_danger_gb _disk_mount <<< "$_disk_measure"
if [ "$_disk_status" = "BLOCK" ]; then
    _disk_free_gb="$(disk_space_watch_human_gb "$_disk_available_kb")"
    overall="BLOCK"
    alerts+=("disk残量危険: ${_disk_mount} free=${_disk_free_gb}GB < danger=${_disk_danger_gb}GB。回収対応完了まで通常作業開始禁止")
elif [ "$_disk_status" = "WARN" ]; then
    _disk_free_gb="$(disk_space_watch_human_gb "$_disk_available_kb")"
    overall="WARN"
    alerts+=("disk残量警告: ${_disk_mount} free=${_disk_free_gb}GB < warn=${_disk_warn_gb}GB")
elif [ "$_disk_status" != "OK" ]; then
    overall="ALERT"
    alerts+=("disk残量計測失敗: ${DISK_WATCH_MOUNT_PATH:-/mnt/c}")
fi
STARTUP_STDERR_LOG="$SCRIPT_DIR/logs/gate_karo_startup_stderr.log"
STARTUP_ALERT_HISTORY="$SCRIPT_DIR/logs/karo_startup_alert_history.tsv"
STARTUP_ESCALATION_STATE="${KARO_STARTUP_ESCALATION_STATE:-$SCRIPT_DIR/logs/karo_startup_escalation_state.tsv}"
KARO_STARTUP_ESCALATION_RESOLVE_GRACE_SEC="${KARO_STARTUP_ESCALATION_RESOLVE_GRACE_SEC:-3600}"
STARTUP_WARN_STREAK_THRESHOLD="${STARTUP_WARN_STREAK_THRESHOLD:-1}"
# cmd_3658: 到着直後の未読が先送りCRITICAL streakに混入する誤検知の根治。
# 最古未読メッセージがこの分数以上滞留していない限り、streak判定対象のalertを積まない。
KARO_INBOX_UNREAD_DWELL_MIN="${KARO_INBOX_UNREAD_DWELL_MIN:-30}"
KARO_ASSIGNED_STALL_GRACE_SEC="${KARO_ASSIGNED_STALL_GRACE_SEC:-300}"

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

karo_startup_pane_is_active() {
    local output="$1"

    printf '%s\n' "$output" \
        | grep -qE '[•◦] (Working|Ran |Waiting|Running .*([Hh]ook|UserPromptSubmit|PostToolUse))'
}

# cmd_4231: deepdive追体験の起動直後FAILを先送りstreakへ混入させない。
# session markerはこのgenerationの開始時刻であり、markerから猶予閾値を超えても
# gate_deepdive_replayがFAILなら、そのgenerationの受領証が進んでいない実先送りとして
# 呼び出し側がalertへ積む。marker不在/不正はfail-closedで猶予を与えない。
karo_startup_deepdive_replay_within_grace() {
    local marker_file="$1"
    local now_epoch="${2:-$(date +%s)}"
    local marker_ts marker_epoch dwell_sec grace_sec

    [[ -f "$marker_file" ]] || return 1
    marker_ts="$(cat "$marker_file" 2>/dev/null || true)"
    marker_epoch="$(date -d "$marker_ts" +%s 2>/dev/null || echo 0)"
    [[ "$marker_epoch" =~ ^[0-9]+$ && "$marker_epoch" -gt 0 ]] || return 1
    [[ "$now_epoch" =~ ^[0-9]+$ ]] || return 1
    dwell_sec=$((now_epoch - marker_epoch))
    grace_sec=$((KARO_INBOX_UNREAD_DWELL_MIN * 60))
    (( dwell_sec >= 0 && dwell_sec < grace_sec ))
}

phase_guide_cached() {
    local source_file="${1:?source file required}"
    local cache_name="${2:?cache name required}"
    local cache_file="/tmp/${cache_name}.cache"
    local cache_sig current_sig

    [[ -f "$source_file" ]] || return 1
    current_sig="$(stat -c '%n:%y:%s' "$source_file" 2>/dev/null || echo '')"
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

karo_startup_recent_deploy_grace() {
    local task_file="$1"
    local now_epoch="$2"
    local deployed_at deployed_epoch age

    [ -f "$task_file" ] || return 1
    deployed_at=$(awk '
        /^[[:space:]]*deployed_at:[[:space:]]*/ {
            val=$0
            sub(/^[[:space:]]*deployed_at:[[:space:]]*/, "", val)
            gsub(/^["'\'' ]+|["'\'' ]+$/, "", val)
            print val
            exit
        }
    ' "$task_file" 2>/dev/null)
    [ -n "$deployed_at" ] || return 1

    deployed_epoch=$(date -d "$deployed_at" +%s 2>/dev/null || echo 0)
    [ "$deployed_epoch" -gt 0 ] || return 1
    age=$(( now_epoch - deployed_epoch ))
    [ "$age" -ge 0 ] || age=0
    [ "$age" -le "$KARO_ASSIGNED_STALL_GRACE_SEC" ] || return 1

    printf '%s\n' "$age"
    return 0
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
    local semantic_cache_dir semantic_cache_key semantic_cache_file semantic_current_sig
    local backlink_cache_dir

    echo "  ${ninja}: ${cmd_id:-unknown} target_path=${target_path}"
    semantic_cache_dir="${KARO_STARTUP_SEMANTIC_CACHE_DIR:-/tmp/karo_startup_semantic_cache}"
    semantic_current_sig="$(
        {
            printf '%s\n' "$target_path"
            stat -c '%n:%y:%s' "$SCRIPT_DIR/docs/semantic-index/index.md" 2>/dev/null || true
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
    local semantic_index="${KARO_STARTUP_SEMANTIC_INDEX:-$SCRIPT_DIR/docs/semantic-index/index.md}"
    local semantic_index_py="${KARO_STARTUP_SEMANTIC_INDEX_PY:-$SCRIPT_DIR/scripts/semantic_index.py}"
    local recheck_timeout="${KARO_STARTUP_NO_MATCH_RECHECK_TIMEOUT:-3}"

    echo "■ セマンティックNO_MATCH計測"
    if [ ! -f "$deploy_log" ]; then
        echo "  SKIP: logs/deploy_task.log 不在"
        echo ""
        return 0
    fi

    python3 - "$SCRIPT_DIR" "$deploy_log" "$semantic_index" "$semantic_index_py" "$scan_lines" "$recheck_timeout" <<'PY'
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

script_dir, deploy_log, semantic_index, semantic_index_py, scan_lines, timeout_s = sys.argv[1:7]
try:
    scan_lines_i = max(1, int(scan_lines))
except ValueError:
    scan_lines_i = 500
try:
    timeout_s = max(1, int(timeout_s))
except ValueError:
    timeout_s = 3

attempts = 0
historical_no_match = 0
current_no_match = 0
resolved = 0
miss = Counter()

try:
    lines = Path(deploy_log).read_text(encoding="utf-8", errors="replace").splitlines()[-scan_lines_i:]
except OSError:
    lines = []

for raw in lines:
    raw = raw.rstrip("\n")
    if "inject_semantic_concepts:" not in raw:
        continue
    attempts += 1
    if "NO_MATCH" not in raw:
        continue
    historical_no_match += 1
    purpose = re.sub(r"^.*NO_MATCH purpose=", "", raw)
    purpose = re.sub(r"\s+target_path=.*", "", purpose)
    purpose = re.sub(r"\s+", " ", purpose).strip() or "(purposeなし)"
    try:
        rc = subprocess.run(
            [
                "python3",
                semantic_index_py,
                semantic_index,
                purpose,
                "first-layer",
                "silent",
            ],
            cwd=script_dir,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout_s,
            check=False,
        ).returncode
    except Exception:
        rc = 1
    if rc == 0:
        resolved += 1
    else:
        current_no_match += 1
        miss[purpose] += 1

if attempts == 0:
    print("  semantic注入試行: 0件")
    sys.exit(0)

rate = round(current_no_match * 100 / attempts, 1)
hit_rate = round((attempts - current_no_match) * 100 / attempts, 1)
print(f"  NO_MATCH率: {rate:.1f}% ({current_no_match}/{attempts}, scan_lines={scan_lines_i})")
print(f"  ヒット率: {hit_rate:.1f}% ({attempts - current_no_match}/{attempts})")
print(f"  履歴NO_MATCH解消: {resolved}/{historical_no_match}")
if current_no_match == 0:
    print("  TOP3 miss purpose: none")
else:
    print("  TOP3 miss purpose:")
    for idx, (purpose, count) in enumerate(miss.most_common(3), 1):
        shown = purpose if len(purpose) <= 100 else purpose[:97] + "..."
        print(f"    {idx}. {shown} ({count}件)")
PY
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
        # 過去累積FAILではなく、直近PASS以降の未解消FAILだけを通知する。
        # dashboard-updateは履歴に多数の再試行/一時FAILを残すため、累積値
        # (例: FAIL:392)をstartup ALERTへ昇格すると、現行状態と乖離する。
        if (r == "PASS" || r == "SKIP") {
            active_fail_count[skill] = 0
            active_epoch[skill]++
            active_last[skill] = ""
            active_top_point[skill] = ""
            active_top_count[skill] = 0
        } else if (r == "FAIL") {
            active_fail_count[skill]++
            active_last[skill] = ts
            if (point != "") {
                key = skill SUBSEP active_epoch[skill] SUBSEP point
                c = ++active_point_count[key]
                if (c > active_top_count[skill] || (c == active_top_count[skill] && (active_top_point[skill] == "" || point < active_top_point[skill]))) {
                    active_top_point[skill] = point
                    active_top_count[skill] = c
                }
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
    for (s in active_fail_count) {
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
        if (active_fail_count[s] > 0) {
            printf "%d|%s|%s|%s\n", active_fail_count[s], active_last[s], s, active_top_point[s]
        }
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
    local report_task_type_file=""
    local report_cmd_ids_file=""
    [ -f "$review_log" ] || { echo "DATA_MISSING"; return 0; }
    [ -f "$status_file" ] || status_file="/dev/null"
    [ -f "$gate_metrics_file" ] || gate_metrics_file="/dev/null"
    [[ "$limit" =~ ^[0-9]+$ ]] || limit=20
    # Report task_type is the SSOT for verification classification. Missing
    # reports intentionally leave the existing fallback classification intact.
    report_task_type_file="$(mktemp)"
    report_cmd_ids_file="$(mktemp)"
    awk -v limit="$limit" '/^[[:space:]]*-[[:space:]]*cmd_id:/ {
        s = $0
        sub(/^[[:space:]]*-[[:space:]]*cmd_id:[[:space:]]*/, "", s)
        gsub(/^['"'"']|['"'"']$/, "", s)
        n++
        ids[n] = s
    }
    END {
        start = n - limit + 1
        if (start < 1) start = 1
        for (i = start; i <= n; i++) print ids[i]
    }' "$review_log" > "$report_cmd_ids_file"
    while IFS= read -r _review_cmd_id; do
        [ -n "$_review_cmd_id" ] || continue
        for _report_dir in "$SCRIPT_DIR/queue/reports" "$SCRIPT_DIR/queue/archive/reports"; do
            [ -d "$_report_dir" ] || continue
            for _report_file in "$_report_dir"/*"$_review_cmd_id"*.yaml; do
                [ -f "$_report_file" ] || continue
                awk '
function trim(s) { gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); gsub(/^['"'"']|['"'"']$/, "", s); return s }
/^[[:space:]]*parent_cmd:/ {
    s = $0
    sub(/^[[:space:]]*parent_cmd:[[:space:]]*/, "", s)
    parent_cmd = trim(s)
}
/^[[:space:]]*task_type:/ {
    s = $0
    sub(/^[[:space:]]*task_type:[[:space:]]*/, "", s)
    task_type = tolower(trim(s))
}
END {
    if (parent_cmd ~ /^cmd_/ && task_type != "") print parent_cmd "\t" task_type
}' "$_report_file" >> "$report_task_type_file"
            done
        done
    done < "$report_cmd_ids_file"
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
    if (status_cmd != "" && $0 ~ /^[[:space:]]+title:/) {
        s = $0
        sub(/^[[:space:]]+title:[[:space:]]*/, "", s)
        cmd_title[status_cmd] = trim(s)
        next
    }
    if (status_cmd != "" && $0 ~ /^[[:space:]]+purpose:/) {
        s = $0
        sub(/^[[:space:]]+purpose:[[:space:]]*/, "", s)
        cmd_purpose[status_cmd] = trim(s)
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
FILENAME == ARGV[4] {
    if (NF >= 2 && $1 ~ /^cmd_/) {
        # Active reports are listed before archive reports. Keep the first
        # canonical value when a command has both generations present.
        if (!(trim($1) in report_task_type)) report_task_type[trim($1)] = tolower(trim($2))
    }
    next
}
function flush_entry() {
    if (verdict != "" && verdict != "null" && review_type ~ /^(draft|report|verify)$/) {
        n++
        v[n] = verdict
        cid[n] = current_cmd_id
        rt[n] = review_type
        gr[n] = gate_result
        fs[n] = findings_summary " " confidence_reason " " evidence
        if (review_type ~ /^(report|verify)$/ && current_cmd_id != "") {
            terminal_review[current_cmd_id] = 1
        }
        if (review_type ~ /^(draft|report)$/) {
            old_n++
            old_v[old_n] = verdict
        }
    }
    review_type = ""; verdict = ""; current_cmd_id = ""; gate_result = ""; findings_summary = ""; confidence_reason = ""; evidence = ""
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
/^  findings_summary:/ {
    s=$0; sub(/^  findings_summary:[[:space:]]*/, "", s); findings_summary=trim(s); next
}
/^  confidence_reason:/ {
    s=$0; sub(/^  confidence_reason:[[:space:]]*/, "", s); confidence_reason=trim(s); next
}
/未確認|未達|未完了|preflight[[:space:]]+FAIL|commit=no|FAIL_PRECONDITION|test未達/ {
    evidence = evidence " " trim($0)
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
    review_only_total = 0; review_only_warn = 0; review_only_cmds = ""
    false_positive_warn = 0; false_positive_cmds = ""
    pending_draft_total = 0; pending_draft_cmds = ""
    terminal_gap_warn = 0; terminal_gap_cmds = ""
    for (key in last_idx) {
        i = last_idx[key]
        # A draft approval is not a terminal quality outcome.  Do not let a
        # currently active cmd change the denominator while its implementation
        # report is still pending; once report/verify or gate CLEAR exists it
        # is included normally.
        if (rt[i] == "draft" && !terminal_review[key] && gr[i] !~ /^(CLEAR|PASS)$/) {
            pending_draft_total++
            pending_draft_cmds = pending_draft_cmds ((pending_draft_cmds == "") ? "" : ",") cid[i] ":" v[i]
            continue
        }
        ok = (v[i] ~ /^(APPROVE|LGTM|PASS|CLEAR|VERIFIED|VERIFIED_FACTS|CONDITIONAL_PASS)$/)
        if (!ok && gr[i] ~ /^(CLEAR|PASS)$/) ok = 1
        if (!ok && cid[i] != "" && cmd_status[cid[i]] ~ /^(done|completed|cancelled)$/) ok = 1
        if (!ok && cid[i] != "" && gate_clear[cid[i]]) ok = 1
        # 実装品質の母集団は実装cmdのみ。レビュー専用cmdは、cmd台帳の
        # title/purpose（一次データ）を主根拠とし、旧cmdの欠損時だけcmd_idを
        # fallbackにする。一般的な "review" 単語ではなく専用語へ限定し、
        # 実装cmdに付随する通常のdraft/reportレビューを誤除外しない。
        review_basis = tolower(cmd_title[cid[i]] " " cid[i])
        review_purpose = tolower(cmd_purpose[cid[i]])
        # 偵察・reflux・affected-tests計測可否判定も実装ではない。これらの
        # 正当なFAIL（仮説棄却/入力不足）を実装品質WARNへ混ぜない。一方で
        # hotfix/implのFAILは除外せず、品質劣化をそのまま残す。
        non_impl_id = tolower(cid[i])
        report_task_type_value = report_task_type[cid[i]]
        review_only = (review_basis ~ /(delta[_ -]?review|independent[_ -]?review|design[_ -]?review|設計書.*検分|独立レビュー|敵対レビュー)/ \
            || review_purpose ~ /^(設計書(の|を)?.*(検分|独立レビュー)|独立レビュー|敵対レビュー|delta[_ -]?review|independent[_ -]?review|design[_ -]?review)/ \
            || report_task_type_value == "verification" \
            || non_impl_id ~ /^cmd_reflux_/ \
            || non_impl_id ~ /_recon[0-9]*_/ \
            || non_impl_id ~ /_affected_tests_/)
        if (review_only) {
            review_only_total++
            if (!ok) review_only_warn++
            review_only_cmds = review_only_cmds ((review_only_cmds == "") ? "" : ",") cid[i] ":" v[i]
            continue
        }
        new_total++
        # A report can be FAIL while the implementation itself is already
        # proven successful: an unrelated/out-of-scope startup condition may
        # leave one AC unmet.  Counting that terminal report as an
        # implementation-quality WARN creates a false positive and makes the
        # metric punish honest fail-closed reporting.  Keep the command in
        # the denominator, but remove only this explicitly evidenced class
        # from the WARN numerator and expose it for the review audit.
        if (!ok && tolower(fs[i]) ~ /(修正自体は成功|implementation[[:space:]]+itself[[:space:]]+succeed)/ \
            && tolower(fs[i]) ~ /(別件|scope外|out[- _]?of[- _]?scope|unrelated)/) {
            false_positive_warn++
            false_positive_cmds = false_positive_cmds ((false_positive_cmds == "") ? "" : ",") cid[i] ":" v[i]
        } else if (!ok) {
            new_warn++
        }
        # A FAIL after implementation work is often caused by the terminal
        # evidence boundary being left incomplete (production rerun/test
        # evidence/preflight/commit proof), not by the code change itself.
        # Keep it in the WARN denominator; expose the count separately so
        # Karo can block or repair the next deployment without rewriting the
        # historical FAIL or weakening the quality threshold.
        if (!ok && tolower(fs[i]) ~ /(未確認|未達|未完了|preflight[[:space:]]+fail|commit=no|fail_precondition|test未達)/) {
            terminal_gap_warn++
            terminal_gap_cmds = terminal_gap_cmds ((terminal_gap_cmds == "") ? "" : ",") cid[i] ":" v[i]
        }
    }
    if (new_total == 0) {
        print "DATA_MISSING"
        exit
    }
    new_rate = int(new_warn * 100 / new_total)
    old_rate = (old_total > 0) ? int(old_warn * 100 / old_total) : 0
    if (review_only_cmds == "") review_only_cmds = "-"
    printf "RATE %d %d %d %d %d %d %s %d %s %d %s %d %s\n", new_rate, new_warn, new_total, old_rate, review_only_warn, review_only_total, review_only_cmds, terminal_gap_warn, (terminal_gap_cmds == "" ? "-" : terminal_gap_cmds), false_positive_warn, (false_positive_cmds == "" ? "-" : false_positive_cmds), pending_draft_total, (pending_draft_cmds == "" ? "-" : pending_draft_cmds)
}
' "$status_file" "$gate_metrics_file" "$review_log" "$report_task_type_file"
    rm -f "$report_task_type_file" "$report_cmd_ids_file"
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
_QUEUE_YAML_PARSE_TMP=$(mktemp)
WA_RATE_SCRIPT="$SCRIPT_DIR/scripts/gates/gate_workaround_rate.sh"
NINJA_WA_SCRIPT="$SCRIPT_DIR/scripts/gates/gate_ninja_workaround_rate.sh"
WA_DQ_SCRIPT="$SCRIPT_DIR/scripts/gates/gate_wa_data_quality.sh"
QUEUE_YAML_PARSE_SCRIPT="$SCRIPT_DIR/scripts/gates/gate_queue_yaml_parse.sh"
_WA_RATE_CACHE="${KARO_WA_RATE_CACHE:-/tmp/karo_wa_rate_cache}"
_NINJA_WA_CACHE="${KARO_NINJA_WA_CACHE:-/tmp/karo_ninja_wa_cache}"
_SKILL_SUMMARY_CACHE="${KARO_SKILL_SUMMARY_CACHE:-/tmp/karo_skill_summary_cache}"
_AGGREGATE_CACHE="${KARO_AGGREGATE_CACHE:-/tmp/karo_startup_aggregate_cache}"
_THREE_LAYER_HEALTH_CACHE="${KARO_THREE_LAYER_HEALTH_CACHE:-/tmp/karo_three_layer_health_cache}"
_SKILL_RECOMMEND_CACHE="${KARO_SKILL_RECOMMEND_CACHE:-/tmp/karo_skill_recommend_cache}"
_WA_CACHE_TTL=300
_SKILL_SUMMARY_CACHE_TTL=300
_THREE_LAYER_HEALTH_CACHE_TTL=300
_SKILL_RECOMMEND_CACHE_TTL=300

_now_epoch=$(date +%s)
_WA_RATE_SCRIPT_MTIME=$(stat -c %Y "$WA_RATE_SCRIPT" 2>/dev/null || echo 0)
_NINJA_WA_SCRIPT_MTIME=$(stat -c %Y "$NINJA_WA_SCRIPT" 2>/dev/null || echo 0)

# WA rate (cache hit or background refresh)
_WA_RATE_CACHE_MTIME=$(stat -c %Y "$_WA_RATE_CACHE" 2>/dev/null || echo 0)
if [[ -f "$_WA_RATE_CACHE" ]] && (( _now_epoch - _WA_RATE_CACHE_MTIME < _WA_CACHE_TTL )) && (( _WA_RATE_CACHE_MTIME >= _WA_RATE_SCRIPT_MTIME )); then
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
_NINJA_WA_CACHE_MTIME=$(stat -c %Y "$_NINJA_WA_CACHE" 2>/dev/null || echo 0)
if [[ -f "$_NINJA_WA_CACHE" ]] && (( _now_epoch - _NINJA_WA_CACHE_MTIME < _WA_CACHE_TTL )) && (( _NINJA_WA_CACHE_MTIME >= _NINJA_WA_SCRIPT_MTIME )); then
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

# queue全YAML parseは独立検査のため、他のstartup集計と並列実行する。
# 表示地点で必ずwaitして終了コードを評価し、fail-closed契約は維持する。
if [ -x "$QUEUE_YAML_PARSE_SCRIPT" ]; then
    ( bash "$QUEUE_YAML_PARSE_SCRIPT" > "$_QUEUE_YAML_PARSE_TMP" 2>&1 ) &
    _QUEUE_YAML_PARSE_PID=$!
else
    _QUEUE_YAML_PARSE_PID=""
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
_bulletin_action_count=0
_bulletin_action_items=""
if [ -f "$SCRIPT_DIR/queue/bulletin_board.yaml" ]; then
    (
        awk '
            /^- id:/ {
                if (in_entry && rc && !closed && !karo_c) {
                    count++
                    if (count <= 3) printf "ITEM: %s by %s\n", eid, epby
                }
                if (in_entry && ar && !closed && actioned_by == "" && (rc_true || rc_karo || notify_karo || (!rc_seen && !notify_seen))) {
                    action_count++
                    if (action_count <= 5) printf "ACTION_ITEM: %s by %s\n", eid, epby
                }
                eid=$0
                sub(/^- id:[[:space:]]*/, "", eid)
                gsub(/['"'"'"]/, "", eid)
                gsub(/[[:space:]]+$/, "", eid)
                in_entry=1; rc=0; closed=0; karo_c=0; epby=""
                ar=0; actioned_by=""; list_key=""; rc_seen=0; rc_true=0; rc_karo=0; notify_seen=0; notify_karo=0
            }
            in_entry && /^  id:/ { v=$2; gsub(/['"'"'"]/, "", v); eid=v }
            in_entry && /^  posted_by:/ { v=$2; gsub(/['"'"'"]/, "", v); epby=v }
            in_entry && /^  requires_confirmation:/ {
                rc_seen=1
                list_key="requires_confirmation"
                if ($0 ~ /true/) { rc=1; rc_true=1; list_key="" }
                if ($0 ~ /false/) { list_key="" }
            }
            in_entry && /^  notify_targets:/ {
                notify_seen=1
                list_key="notify_targets"
                if ($0 ~ /\[\]/) { list_key="" }
            }
            in_entry && list_key == "requires_confirmation" && /^[[:space:]]*-[[:space:]]*/ {
                v=$0; sub(/^[[:space:]]*-[[:space:]]*/, "", v); gsub(/['"'"'"]/, "", v); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
                if (v == "karo") { rc=1; rc_karo=1 }
            }
            in_entry && list_key == "notify_targets" && /^[[:space:]]*-[[:space:]]*/ {
                v=$0; sub(/^[[:space:]]*-[[:space:]]*/, "", v); gsub(/['"'"'"]/, "", v); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
                if (v == "karo") { notify_karo=1 }
            }
            in_entry && /action_type:.*action_required/ { ar=1 }
            in_entry && /^  actioned_by:/ {
                actioned_by=$0
                sub(/^  actioned_by:[[:space:]]*/, "", actioned_by)
                gsub(/['"'"'"]/, "", actioned_by)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", actioned_by)
            }
            in_entry && /status:.*closed/ { closed=1 }
            in_entry && /- .karo./ { karo_c=1 }
            END {
                if (in_entry && rc && !closed && !karo_c) {
                    count++
                    if (count <= 3) printf "ITEM: %s by %s\n", eid, epby
                }
                if (in_entry && ar && !closed && actioned_by == "" && (rc_true || rc_karo || notify_karo || (!rc_seen && !notify_seen))) {
                    action_count++
                    if (action_count <= 5) printf "ACTION_ITEM: %s by %s\n", eid, epby
                }
                print "COUNT: " count+0
                print "ACTION_COUNT: " action_count+0
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
  "$SCRIPT_DIR/logs/gate_metrics.log" \
  "$SCRIPT_DIR/logs/cmd_design_quality.yaml" \
  "$SCRIPT_DIR/logs/archive/cmd_design_quality.yaml" \
  "$SCRIPT_DIR/queue/shogun_to_karo.yaml" \
  "$SCRIPT_DIR/queue/inbox/karo.yaml" \
  "$SCRIPT_DIR/queue/insights.yaml" \
  "$SCRIPT_DIR/logs/gunshi_review_log.yaml" \
  "$SCRIPT_DIR/queue/pending_decisions.yaml" \
  "$SCRIPT_DIR/logs/karo_workarounds.yaml"; do
    [[ -f "$_agg_file" ]] && _AGG_FILES+=("$_agg_file")
done
_AGG_SIG="$(stat -c '%n:%y:%s' "$SCRIPT_DIR/scripts/gates/gate_karo_startup.sh" "${_AGG_FILES[@]}" 2>/dev/null | tr '\n' ';' || true)"
_QUALITY_MISSING_CUTOFF="${KARO_QUALITY_MISSING_CUTOFF:-$(date -d '24 hours ago' '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -v-1d '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo '')}"
if [[ -f "$_AGGREGATE_CACHE" ]]; then
    IFS= read -r _agg_cache_sig < "$_AGGREGATE_CACHE" || _agg_cache_sig=""
    if [[ "$_agg_cache_sig" == "$_AGG_SIG|quality_cutoff=$_QUALITY_MISSING_CUTOFF" ]]; then
        tail -n +2 "$_AGGREGATE_CACHE" > "$_aggregate_tmp"
        exit 0
    fi
fi
awk -v root="$SCRIPT_DIR" -v quality_cutoff="$_QUALITY_MISSING_CUTOFF" '
    function leading_spaces(line,    i, ch) {
        for (i = 1; i <= length(line); i++) {
            ch = substr(line, i, 1)
            if (ch != " ") return i - 1
        }
        return length(line)
    }
    function message_read_field(line, item_indent,    indent) {
        if (line ~ /^-[[:space:]]*read:[[:space:]]*/) return 1
        if (line !~ /^[[:space:]]*read:[[:space:]]*/) return 0
        indent = leading_spaces(line)
        return (indent == item_indent + 2)
    }
    function read_field_value(line,    v) {
        v = line
        sub(/^-[[:space:]]*/, "", v)
        sub(/^[[:space:]]*read:[[:space:]]*/, "", v)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        gsub(/^["\047]+|["\047]+$/, "", v)
        return tolower(v)
    }
    function extract_cmd_id(text, m) {
        if (match(text, /cmd_[0-9]+/, m)) return m[0]
        return ""
    }
    function extract_cmd_token(text, m) {
        if (match(text, /cmd_[A-Za-z0-9_]+/, m)) return m[0]
        return ""
    }
    function gate_archive_done(cmd_id, path) {
        if (cmd_id == "") return 0
        path = root "/queue/gates/" cmd_id "/archive.done"
        return system("test -f " path) == 0
    }
    function gate_clear_recorded(cmd_id) {
        if (cmd_id == "") return 0
        if (gate_archive_done(cmd_id)) return 1
        if (cmd_id in gate_clear) return 1
        if (cmd_id in quality_logged) return 1
        return 0
    }
    function dependency_clear_recorded(cmd_id) {
        if (cmd_id == "") return 0
        # cmd_design_quality also contains cmd_save PASS/WARN entries before
        # execution.  Only completion evidence may release a dependency.
        if (gate_archive_done(cmd_id)) return 1
        return (cmd_id in gate_clear)
    }
    function should_count_read_actionable(msg_type, msg_content, cmd_id) {
        if (msg_content == "") return 0
        # task_assigned and other actionable notifications can repeat after the
        # referenced command has already been deployed.  Suppress that stale
        # read=true item for every message type, not only cmd_new.
        cmd_id = extract_cmd_id(msg_content)
        # A completed command is no longer present in the ninja current task YAML.
        # Treat its durable CLEAR/archive/quality receipt as terminal too; otherwise
        # every completed cmd_new becomes a permanent "read actionable" warning as
        # soon as the ninja is reused for the next task.
        if (cmd_id != "" && ((cmd_id in deployed_parent_cmd) || gate_clear_recorded(cmd_id))) return 0
        if (msg_type == "cmd_new") {
            # Explicit dependencies are work sequencing, not postponement.  Keep the
            # read cmd_new quiet only while its dependency is unresolved; once the
            # dependency records CLEAR the same inbox item becomes actionable again.
            if (cmd_id != "" && (cmd_id in unresolved_dependency)) return 0
        }
        if (msg_type == "skill_hint" && msg_content ~ /GATE CLEAR/) {
            cmd_id = extract_cmd_token(msg_content)
            if (gate_clear_recorded(cmd_id)) return 0
        }
        return (msg_type == "skill_hint" ||
                msg_content ~ /(実行せよ|配備せよ|future fix|変更対象|即修正候補|対応せよ)/)
    }
    function finalize_cmd_entry() {
        if (cmd == "" || (cmd in finalized_cmd)) return
        finalized_cmd[cmd] = 1
        if (cmd_status == "pending" && has_da) {
            orphan_found++
            orphan_cmds = orphan_cmds (orphan_cmds != "" ? ", " : "") cmd
        }
        if (cmd_dep != "" && cmd_dep != "none" && !dependency_clear_recorded(cmd_dep)) {
            unresolved_dependency[cmd] = cmd_dep
        }
    }
    function trim_brainwash_value(v) {
        sub(/^.*brainwash_check:[[:space:]]*/, "", v)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        gsub(/^["\047]+|["\047]+$/, "", v)
        return v
    }
    function has_real_brainwash_value(v) {
        v = trim_brainwash_value(v)
        return (v != "" && v != "null" && v != "{}" && v != "[]")
    }
    FILENAME ~ /queue\/tasks\/[^/]+\.yaml$/ {
        if (FNR == 1) {
            file = FILENAME
            sub(/^.*\/queue\/tasks\//, "", file)
            sub(/\.yaml$/, "", file)
        }
        if ($0 ~ /^[[:space:]]*status:/) {
            if (!(file in status_printed)) {
                print "STATUS|" file "|" $2
                status_printed[file] = 1
            }
            next
        }
        if ($0 ~ /^[[:space:]]*parent_cmd:/) {
            parent_cmd = $0
            sub(/^[[:space:]]*parent_cmd:[[:space:]]*/, "", parent_cmd)
            gsub(/["'"'"']/, "", parent_cmd)
            gsub(/[[:space:]]+$/, "", parent_cmd)
            if (parent_cmd ~ /^cmd_[0-9]+$/) deployed_parent_cmd[parent_cmd] = 1
            next
        }
        next
    }
    FILENAME ~ /queue\/inbox\/karo\.yaml$/ {
        # shogun_to_karo precedes inbox in _AGG_FILES.  Finalize its last cmd
        # before classifying the first inbox entry (AWK END would be too late).
        if (!inbox_cmds_finalized) {
            finalize_cmd_entry()
            inbox_cmds_finalized = 1
        }
        if (/^[[:space:]]*-[[:space:]]/) {
            if (inbox_entry && inbox_read_false && inbox_type == "cmd_new") {
                unread_cmd_new++
                if (inbox_ts != "" && (oldest_cmd_new_ts == "" || inbox_ts < oldest_cmd_new_ts)) oldest_cmd_new_ts = inbox_ts
                if (unread_cmd_new <= 3) {
                    item = inbox_id
                    if (item == "") item = "unknown"
                    if (inbox_ts != "") item = item "@" inbox_ts
                    if (inbox_content != "") item = item " " inbox_content
                    gsub(/\|/, "/", item)
                    unread_cmd_new_items = unread_cmd_new_items (unread_cmd_new_items != "" ? "; " : "") item
                }
            }
            if (inbox_entry && inbox_read_false && inbox_type == "karo_idle_cycle") {
                unread_idle_cycle++
            }
            if (inbox_entry && inbox_read_false && inbox_type != "karo_idle_cycle" && inbox_ts != "") {
                if (oldest_unread_actionable_ts == "" || inbox_ts < oldest_unread_actionable_ts) oldest_unread_actionable_ts = inbox_ts
            }
            if (inbox_entry && inbox_read_true &&
                should_count_read_actionable(inbox_type, inbox_content)) {
                read_actionable_key = inbox_id "|" inbox_type
                if (!(read_actionable_key in read_actionable_seen)) {
                    read_actionable_seen[read_actionable_key] = 1
                    read_actionable++
                    if (read_actionable <= 5) {
                        item = inbox_id
                        if (item == "") item = "unknown"
                        if (inbox_ts != "") item = item "@" inbox_ts
                        if (inbox_type != "") item = item " [" inbox_type "]"
                        if (inbox_content != "") item = item " " inbox_content
                        gsub(/\|/, "/", item)
                        read_actionable_items = read_actionable_items (read_actionable_items != "" ? "; " : "") item
                    }
                }
            }
            inbox_entry = 1
            inbox_read_false = 0
            inbox_read_true = 0
            inbox_type = ""
            inbox_id = ""
            inbox_ts = ""
            inbox_content = ""
            inbox_item_indent = leading_spaces($0)
        }
        if (inbox_entry && message_read_field($0, inbox_item_indent)) {
            read_value = read_field_value($0)
            if (read_value == "false") {
                unread++
                inbox_read_false = 1
            }
            if (read_value == "true") inbox_read_true = 1
        }
        if (inbox_entry && (/^[[:space:]]*type:/ || /^-[[:space:]]*type:/)) {
            inbox_type = $0
            sub(/^-[[:space:]]*/, "", inbox_type)
            sub(/^[[:space:]]*type:[[:space:]]*/, "", inbox_type)
            gsub(/["'"'"']/, "", inbox_type)
            gsub(/[[:space:]]+$/, "", inbox_type)
        }
        if (inbox_entry && (/^[[:space:]]*id:/ || /^-[[:space:]]*id:/)) {
            inbox_id = $0
            sub(/^-[[:space:]]*/, "", inbox_id)
            sub(/^[[:space:]]*id:[[:space:]]*/, "", inbox_id)
            gsub(/["'"'"']/, "", inbox_id)
            gsub(/[[:space:]]+$/, "", inbox_id)
        }
        if (inbox_entry && (/^[[:space:]]*timestamp:/ || /^-[[:space:]]*timestamp:/)) {
            inbox_ts = $0
            sub(/^-[[:space:]]*/, "", inbox_ts)
            sub(/^[[:space:]]*timestamp:[[:space:]]*/, "", inbox_ts)
            gsub(/["'"'"']/, "", inbox_ts)
            gsub(/[[:space:]]+$/, "", inbox_ts)
        }
        if (inbox_entry && (/^[[:space:]]*content:/ || /^-[[:space:]]*content:/)) {
            inbox_content = $0
            sub(/^-[[:space:]]*/, "", inbox_content)
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
    FILENAME ~ /logs\/gate_metrics\.log$/ {
        gcmd = ""; gresult = ""
        greason = ""
        gts = $1
        gsub(/Z$/, "", gts)
        if (quality_cutoff != "" && gts < quality_cutoff) next
        if (NF >= 3 && $2 ~ /^cmd_/) {
            gcmd = $2
            gresult = $3
            greason = $4
        } else if (NF >= 3 && $3 ~ /^cmd_/) {
            gcmd = $3
            gresult = $2
            greason = $4
        }
        gsub(/["'"'"']/, "", gcmd)
        gsub(/["'"'"']/, "", gresult)
        gsub(/["'"'"']/, "", greason)
        if (greason == "no_task_benchmark_fast_path") next
        if (gcmd != "" && gresult ~ /^(CLEAR|PASS)$/) gate_clear[gcmd] = 1
        next
    }
    FILENAME ~ /logs\/(archive\/)?cmd_design_quality\.yaml$/ {
        if (/^[[:space:]]*-[[:space:]]*cmd_id:/ || /^[[:space:]]*cmd_id:/) {
            qcmd = $0
            sub(/^.*cmd_id:[[:space:]]*/, "", qcmd)
            gsub(/["'"'"']/, "", qcmd)
            gsub(/[[:space:]]+$/, "", qcmd)
            if (qcmd ~ /^cmd_/) quality_logged[qcmd] = 1
        }
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
            in_brainwash_block=0
            cat[n]="uncategorized"
            rc[n]=""
            resolved[n]=0
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
        if (in_brainwash_block && /^  [^ ]/ && $0 !~ /^  brainwash_check:/) {
            in_brainwash_block=0
        }
        if (/^  (cmd_id|cmd):/) {
            wa_cmd[n]=$0
            sub(/^  (cmd_id|cmd):[[:space:]]*/, "", wa_cmd[n])
            gsub(/["'"'"']/, "", wa_cmd[n])
            gsub(/[[:space:]]+$/, "", wa_cmd[n])
            next
        }
        if (/^  brainwash_check:/) {
            has_brainwash_field[n]=1
            in_brainwash_block=1
            if (has_real_brainwash_value($0)) brainwash[n]=1
            next
        }
        if (in_brainwash_block && /^    /) {
            child=$0
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", child)
            gsub(/^["\047]+|["\047]+$/, "", child)
            if (child != "" && child !~ /^#/) brainwash[n]=1
            next
        }
        if (/^  category:/) { sub(/^  category: */, ""); gsub(/["'"'"']/, ""); cat[n]=$0; next }
        if (/^  root_cause:/) { sub(/^  root_cause: */, ""); gsub(/["'"'"']/, ""); rc[n]=substr($0,1,60); next }
        if (/^  resolved_by_cmd:/) {
            val=$0
            sub(/^  resolved_by_cmd:[[:space:]]*/, "", val)
            gsub(/["'"'"']/, "", val)
            gsub(/[[:space:]]+$/, "", val)
            if (val != "") resolved[n]=1
            next
        }
        next
    }
    FILENAME ~ /queue\/shogun_to_karo\.yaml$/ {
        if (/^  [^ ][^ ]*:[[:space:]]*$/) {
            finalize_cmd_entry()
            cmd = $0
            sub(/^  /, "", cmd)
            sub(/:.*/, "", cmd)
            cmd_status = ""
            cmd_dep = ""
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
        if (/^    depends_on:/) {
            cmd_dep = $0
            sub(/.*depends_on:[[:space:]]*/, "", cmd_dep)
            gsub(/["'"'"']/, "", cmd_dep)
            if (match(cmd_dep, /cmd_[0-9]+/)) cmd_dep = substr(cmd_dep, RSTART, RLENGTH)
            else gsub(/[[:space:]]+/, "", cmd_dep)
            next
        }
        if (/^    delegated_at:/) { has_da = 1; next }
    }
    END {
        if (inbox_entry && inbox_read_false && inbox_type == "cmd_new") {
            unread_cmd_new++
            if (inbox_ts != "" && (oldest_cmd_new_ts == "" || inbox_ts < oldest_cmd_new_ts)) oldest_cmd_new_ts = inbox_ts
            if (unread_cmd_new <= 3) {
                item = inbox_id
                if (item == "") item = "unknown"
                if (inbox_ts != "") item = item "@" inbox_ts
                if (inbox_content != "") item = item " " inbox_content
                gsub(/\|/, "/", item)
                unread_cmd_new_items = unread_cmd_new_items (unread_cmd_new_items != "" ? "; " : "") item
            }
        }
        if (inbox_entry && inbox_read_false && inbox_type == "karo_idle_cycle") {
            unread_idle_cycle++
        }
        if (inbox_entry && inbox_read_false && inbox_type != "karo_idle_cycle" && inbox_ts != "") {
            if (oldest_unread_actionable_ts == "" || inbox_ts < oldest_unread_actionable_ts) oldest_unread_actionable_ts = inbox_ts
        }
        if (inbox_entry && inbox_read_true &&
            should_count_read_actionable(inbox_type, inbox_content)) {
            read_actionable_key = inbox_id "|" inbox_type
            if (!(read_actionable_key in read_actionable_seen)) {
                read_actionable_seen[read_actionable_key] = 1
                read_actionable++
                if (read_actionable <= 5) {
                    item = inbox_id
                    if (item == "") item = "unknown"
                    if (inbox_ts != "") item = item "@" inbox_ts
                    if (inbox_type != "") item = item " [" inbox_type "]"
                    if (inbox_content != "") item = item " " inbox_content
                    gsub(/\|/, "/", item)
                    read_actionable_items = read_actionable_items (read_actionable_items != "" ? "; " : "") item
                }
            }
        }
        if (ins_id != "" && ins_status == "pending") {
            pending_insights++
            pending_insight_id[pending_insights] = ins_id
            pending_insight_priority[pending_insights] = ins_priority
            pending_insight_text[pending_insights] = ins_text
        }
        finalize_cmd_entry()
        print "UNREAD|" unread+0
        print "UNREAD_CMD_NEW|" unread_cmd_new+0 "|" unread_cmd_new_items
        print "UNREAD_CMD_NEW_OLDEST_TS|" oldest_cmd_new_ts
        print "UNREAD_IDLE_CYCLE|" unread_idle_cycle+0
        print "UNREAD_OLDEST_ACTIONABLE_TS|" oldest_unread_actionable_ts
        print "READ_ACTIONABLE|" read_actionable+0 "|" read_actionable_items
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
            if (wa[i] && !resolved[i]) break
            clean_streak++
        }
        latest_regression = (n > 0 && wa[n] && !resolved[n]) ? 1 : 0
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
        qmiss = 0
        qmiss_cmds = ""
        for (gcmd in gate_clear) {
            # reflux/karo_direct/training auto-generated cmds carry no quality_gate by design (INS-20260708-094738751)
            if (gcmd ~ /^cmd_(reflux|karo|training)_/) continue
            if (!(gcmd in quality_logged)) {
                qmiss++
                if (qmiss <= 5) qmiss_cmds = qmiss_cmds (qmiss_cmds != "" ? ", " : "") gcmd
            }
        }
        print "QUALITY_MISSING|" qmiss+0 "|" qmiss_cmds
    }
' "${_AGG_FILES[@]}" > "$_aggregate_tmp" 2>/dev/null || true
{
    printf '%s\n' "$_AGG_SIG|quality_cutoff=$_QUALITY_MISSING_CUTOFF"
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
        UNREAD_CMD_NEW_OLDEST_TS) unread_cmd_new_oldest_ts=${_agg_a:-} ;;
        UNREAD_IDLE_CYCLE) unread_idle_cycle=${_agg_a:-0} ;;
        UNREAD_OLDEST_ACTIONABLE_TS) unread_oldest_actionable_ts=${_agg_a:-} ;;
        READ_ACTIONABLE) read_actionable=${_agg_a:-0}; read_actionable_items=${_agg_b:-} ;;
        INSIGHTS) _insight_pending_count=${_agg_a:-0} ;;
        INSIGHT_ITEM) _insight_recent_items="${_insight_recent_items}    ${_agg_a} [${_agg_b:-medium}] ${_agg_c}"$'\n' ;;
        GP) _gp_pending_count=${_agg_a:-0} ;;
        PD) total_d=${_agg_a:-0}; resolved_d=${_agg_b:-0} ;;
        WA) wa_result="${_agg_a}|${_agg_b}|${_agg_c}|${_agg_d}|${_agg_e}|${_agg_f}" ;;
        WACLEAN) wa_clean_result="${_agg_a}|${_agg_b}|${_agg_c}|${_agg_d}|${_agg_e}" ;;
        WABRAINWASH) wa_brainwash_result="${_agg_a}|${_agg_b}" ;;
        ORPHAN) orphan_result="${_agg_a}|${_agg_b}" ;;
        QUALITY_MISSING) quality_missing_result="${_agg_a}|${_agg_b}" ;;
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
            ACTION_COUNT:\ *) _bulletin_action_count=${_blt_line#ACTION_COUNT: } ;;
            ACTION_ITEM:\ *) _bulletin_action_items="${_bulletin_action_items}    ${_blt_line#ACTION_ITEM: }"$'\n' ;;
        esac
    done < "$_bulletin_tmp"
fi
_bulletin_count=${_bulletin_count:-0}
_bulletin_action_count=${_bulletin_action_count:-0}
rm -f "$_phase_guide_1_tmp" "$_phase_guide_2_tmp" "$_session_summary_tmp" "$_bulletin_tmp"

echo "=== 家老起動チェック $(date '+%H:%M:%S') ==="
echo ""

# --- Check 0.9: CI REDは忍者へ配備済みか ---
# origin: [[殿裁定20260716_CI修正忍者配備]] -> [[家老D0修正の属人化]] -> [[ci_fix_delegation_guard]]
# CI RED中も家老の管理操作は必要なためBLOCKで全操作を止めず、ALERT pendingを
# stop hookへ渡す。task_type+ci_run_idの機械証跡ができるまで完了/idleへ逃げられない。
if [ "${KARO_STARTUP_SKIP_CI_CHECK:-0}" != "1" ]; then
    _ci_json="${KARO_STARTUP_CI_JSON:-}"
    _ci_query_failed=0
    if [ -z "$_ci_json" ]; then
        if command -v gh >/dev/null 2>&1; then
            # 一時的なgh blip(ネットワーク/cold auth/rate limit)で偽CRITICALを出さないため
            # 1回リトライしてから失敗と判定する(2026-07-23 将軍: gh実測749-841msでtimeout8sは十分
            # だが単発blipでgeneration=1のCI状態取得失敗→CRITICAL→cmd起票検討 の偽陽性が発生。
            # 『取得できなかった(不明)』を即CRITICALへ直結させず、単発失敗は一過性として吸収する。
            # 今夜の『一時的を永続と誤認』系(WARN累計昇格/DBロック)と同型の是正)。
            _ci_attempt=0
            while [ "$_ci_attempt" -lt 2 ]; do
                _ci_json="$(timeout "${KARO_STARTUP_GH_TIMEOUT:-8}" gh run list \
                    --repo "${KARO_STARTUP_CI_REPO:-simokitafresh/multi-agent-shogun}" \
                    --status completed --limit 1 \
                    --json conclusion,databaseId,headSha 2>/dev/null || true)"
                [ -n "$_ci_json" ] && break
                _ci_attempt=$((_ci_attempt + 1))
            done
            [ -n "$_ci_json" ] || _ci_query_failed=1
        fi
    fi

    if [ "$_ci_query_failed" -eq 1 ]; then
        echo "■ CI RED忍者配備"
        echo "  ALERT: GitHub Actions完了run取得失敗 — CI状態を確認できない"
        overall="ALERT"
        alerts+=("CI状態取得失敗: 忍者配備要否を判定不能")
    elif [ -n "$_ci_json" ]; then
        _ci_parsed="$(python3 - "$_ci_json" <<'PY' 2>/dev/null || true
import json
import sys

try:
    runs = json.loads(sys.argv[1])
except Exception:
    raise SystemExit(0)
if isinstance(runs, list) and runs:
    run = runs[0] or {}
    print(str(run.get("conclusion") or ""))
    print(str(run.get("databaseId") or ""))
    print(str(run.get("headSha") or ""))
PY
)"
        _ci_conclusion="$(printf '%s\n' "$_ci_parsed" | sed -n '1p')"
        _ci_run_id="$(printf '%s\n' "$_ci_parsed" | sed -n '2p')"
        _ci_head_sha="$(printf '%s\n' "$_ci_parsed" | sed -n '3p')"

        if [ "$_ci_conclusion" = "failure" ]; then
            echo "■ CI RED忍者配備"
            echo "  WARN: 最新完了CI=failure${_ci_run_id:+ run_id=${_ci_run_id}}${_ci_head_sha:+ sha=${_ci_head_sha:0:9}}"
            _ci_task_proof="$(python3 - "$SCRIPT_DIR/queue/tasks" "$_ci_run_id" <<'PY' 2>/dev/null || true
from pathlib import Path
import sys
import yaml

tasks_dir = Path(sys.argv[1])
run_id = sys.argv[2]
active = {"assigned", "acknowledged", "in_progress", "done"}
if run_id:
    for path in sorted(tasks_dir.glob("*.yaml")):
        try:
            doc = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
        except Exception:
            continue
        task = doc.get("task", doc) if isinstance(doc, dict) else {}
        if not isinstance(task, dict):
            continue
        if str(task.get("task_type", "")) != "ci_fix":
            continue
        if str(task.get("ci_run_id", "")) != run_id:
            continue
        status = str(task.get("status", ""))
        if status not in active:
            continue
        ninja = str(task.get("assigned_to") or path.stem)
        print(f"{ninja}|{status}|{path.name}")
        break
PY
)"
            if [ -n "$_ci_task_proof" ]; then
                IFS='|' read -r _ci_ninja _ci_task_status _ci_task_file <<< "$_ci_task_proof"
                echo "  OK: 忍者配備証跡 run_id=${_ci_run_id} ninja=${_ci_ninja} status=${_ci_task_status} task=${_ci_task_file}"
                echo "  RULE: 家老は診断・レビュー・push・CI監視のみ。実装修正は忍者が担当"
            else
                echo "  ALERT: run_id=${_ci_run_id:-unknown} のci_fix忍者タスクなし"
                echo "  ACTION: /karo-directでidle忍者へ task_type=ci_fix, ci_run_id=${_ci_run_id:-unknown} を配備せよ"
                echo "  PROHIBITED: 家老自身の実装修正・commitで代替するな"
                overall="ALERT"
                alerts+=("CI RED未配備: run ${_ci_run_id:-unknown} — 忍者ci_fix配備必須・家老D0修正禁止")
            fi
        fi
    fi
fi

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
# --- deepdive追体験受領証検証(殿裁定2026-07-26 23:28: クリア後毎回強制。stop hookがBLOCK層) ---
_dd_replay_out="$(bash "$SCRIPT_DIR/scripts/gates/gate_deepdive_replay.sh" karo 2>/dev/null || true)"
echo "  ${_dd_replay_out:-ERROR: gate_deepdive_replay.sh実行失敗}" | head -3
if [[ "$_dd_replay_out" == DEEPDIVE-REPLAY:\ FAIL* ]]; then
    overall="ALERT"
    _dd_replay_alert="deepdive追体験未完了: 全Phase実行まで作業禁止(stop hookがBLOCKする)。bash scripts/deepdive_replay.sh karo <md> <Phase> \"<自問>\""
    _dd_replay_marker="$SCRIPT_DIR/logs/deepdive_replay/karo.session"
    # marker直後は追体験を開始できる正常な起動直後状態。表示は残すが、
    # 固定alertを積まず、startup streak/escalationの入力から除外する。
    if karo_startup_deepdive_replay_within_grace "$_dd_replay_marker"; then
        _dd_replay_marker_ts="$(cat "$_dd_replay_marker" 2>/dev/null || true)"
        _dd_replay_marker_epoch="$(date -d "$_dd_replay_marker_ts" +%s 2>/dev/null || echo 0)"
        _dd_replay_dwell_min=$(( ($(date +%s) - _dd_replay_marker_epoch) / 60 ))
        echo "  ALERT: ${_dd_replay_alert}"
        echo "  INFO: deepdive generation開始から${_dd_replay_dwell_min}分(閾値${KARO_INBOX_UNREAD_DWELL_MIN}分未満) — 表示のみ、先送りCRITICAL streak/escalation対象外。直ちに追体験を開始せよ"
    else
        echo "  ALERT: ${_dd_replay_alert}"
        alerts+=("$_dd_replay_alert")
    fi
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
echo "  ★ 全Phase必読（スキップ禁止）。1 Phaseずつ bash scripts/deepdive_replay.sh karo <md> <Phase番号> \"<自問>\" で実行せよ。receipt記録される。全文一括禁止。"
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
_stall_now_epoch=$(date +%s)
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
        if [[ "$task_status" == "assigned" && ( "$ctx" == "0%" || -z "$ctx" ) ]]; then
            # The snapshot/task/pane trio can cross a deployment transition while this
            # gate is running.  Re-read the primary pane immediately before counting a
            # STALL so a stale initial capture cannot advance escalation generation.
            _stall_pane_output=$(tmux capture-pane -t "${_AGENTS_WINDOW_TARGET}.${pane_idx}" -p -J -S -30 2>/dev/null || true)
            _stall_fresh_ctx=$(karo_startup_extract_ctx_pct "$_stall_pane_output" || true)
            task_file="$SCRIPT_DIR/queue/tasks/${ninja}.yaml"
            if karo_startup_pane_is_active "$_stall_pane_output" || [[ -n "$_stall_fresh_ctx" && "$_stall_fresh_ctx" != "0%" ]]; then
                echo "  $ninja: CTX=${ctx:-EMPTY}→${_stall_fresh_ctx:-?} status=$task_status → pane一次再照合で稼働中のためSTALL対象外"
            elif _stall_age="$(karo_startup_recent_deploy_grace "$task_file" "$_stall_now_epoch")"; then
                echo "  $ninja: CTX=${ctx:-EMPTY} status=$task_status → 配備直後(${_stall_age}s<=${KARO_ASSIGNED_STALL_GRACE_SEC}s)のためSTALL判定猶予"
            else
                echo "  ⚠ $ninja: CTX=${ctx:-EMPTY} status=$task_status → STALL疑い"
                stall_count=$((stall_count + 1))
            fi
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
    alerts+=("${stall_count}名STALL疑い(assigned+CTX:0%/EMPTY)")
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
        # cmd_3658と同根の誤検知根治(2026-07-08): 委任直後の数秒〜数分をstartup checkが拾い
        # 「先送りCRITICAL」として将軍へ自動エスカレする誤報が同日3回発生(cmd_3773/3774/3775委任の各直後)。
        # DWELL猶予は従来「inbox未読滞留」経路にしか効いていなかった。cmd_newにも同じ猶予を適用し、
        # 猶予未満は即時配備を促すALERT表示のみ(streak/エスカレ対象外)とする。
        _cmd_new_dwell_min=""
        if [ -n "${unread_cmd_new_oldest_ts:-}" ]; then
            _cmd_new_oldest_epoch=$(date -d "$unread_cmd_new_oldest_ts" +%s 2>/dev/null || echo "0")
            if [ "$_cmd_new_oldest_epoch" -gt 0 ]; then
                _cmd_new_dwell_min=$(( ($(date +%s) - _cmd_new_oldest_epoch) / 60 ))
            fi
        fi
        if [ -z "$_cmd_new_dwell_min" ] || [ "$_cmd_new_dwell_min" -ge "$KARO_INBOX_UNREAD_DWELL_MIN" ]; then
            alerts+=("未処理cmd_new: ${unread_cmd_new}件")
        else
            echo "  INFO: 最古cmd_newは${_cmd_new_dwell_min}分前着(閾値${KARO_INBOX_UNREAD_DWELL_MIN}分未満) — 到着直後のため先送りCRITICAL streak対象外。即時配備せよ"
        fi
    elif [ "$unread" -gt 0 ]; then
        echo "  WARN: inbox未読あり。nudge/Stop hookに依存せず通常作業前に処理せよ"
        if [ "${unread_idle_cycle:-0}" -eq "$unread" ]; then
            echo "  INFO: 未読はkaro_idle_cycleのみ。通常処理対象だが先送りCRITICAL streak対象外"
        elif [ "$overall" != "ALERT" ]; then
            overall="WARN"
            # cmd_3658: 先送りCRITICAL streakは「到着直後の未読」を「先送り」と誤分類していた
            # (到着直後→次startup gateで未読カウント→3セッション連続と誤認)。
            # 最古actionable未読の滞留時間を計測し、閾値未満なら固定文字列alertを積まない
            # (=streak対象外)。閾値以上の滞留のみ、固定文字列(分数を含めない)でstreakに乗せる。
            # 分数を含めない理由: streakは前回runと同一文字列一致で判定するため、分数入りだと
            # 実際に滞留していてもrun毎に文字列が変わりstreakが繋がらなくなる。
            _unread_dwell_min=""
            if [ -n "${unread_oldest_actionable_ts:-}" ]; then
                _unread_oldest_epoch=$(date -d "$unread_oldest_actionable_ts" +%s 2>/dev/null || echo "0")
                if [ "$_unread_oldest_epoch" -gt 0 ]; then
                    _unread_dwell_min=$(( ($(date +%s) - _unread_oldest_epoch) / 60 ))
                fi
            fi
            if [ -n "$_unread_dwell_min" ] && [ "$_unread_dwell_min" -ge "$KARO_INBOX_UNREAD_DWELL_MIN" ]; then
                echo "  WARN: 最古未読が${_unread_dwell_min}分滞留(閾値${KARO_INBOX_UNREAD_DWELL_MIN}分) — 先送りCRITICAL streak対象"
                alerts+=("inbox未読滞留: 閾値${KARO_INBOX_UNREAD_DWELL_MIN}分超")
            else
                echo "  INFO: 最古未読は${_unread_dwell_min:-不明}分前(閾値${KARO_INBOX_UNREAD_DWELL_MIN}分未満) — 到着直後のため先送りCRITICAL streak対象外"
            fi
        fi
    fi
    if [ "${read_actionable:-0}" -gt 0 ]; then
        echo "  WARN: 既読actionable候補 ${read_actionable}件。read=trueを処理済みと見なすな"
        [ -n "${read_actionable_items:-}" ] && echo "    ${read_actionable_items}"
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
            _read_actionable_ids=$(printf '%s\n' "${read_actionable_items:-}" | grep -oE 'msg_[A-Za-z0-9_]+' | paste -sd, -)
            alerts+=("既読actionable候補: id=${_read_actionable_ids:-unidentified}")
        fi
    fi
else
    echo "  未読: 0件 (inbox不在)"
    unread=0
fi

echo "■ queue YAML parse"
_queue_yaml_parse_rc=0
if [ -n "${_QUEUE_YAML_PARSE_PID:-}" ]; then
    wait "$_QUEUE_YAML_PARSE_PID" || _queue_yaml_parse_rc=$?
    _queue_yaml_parse_output="$(<"$_QUEUE_YAML_PARSE_TMP")"
    printf '%s\n' "$_queue_yaml_parse_output" | sed 's/^/  /'
    if [ "$_queue_yaml_parse_rc" -ne 0 ]; then
        overall="ALERT"
        alerts+=("queue YAML parse error")
    fi
else
    echo "  WARN: gate_queue_yaml_parse.sh 不在または実行権限なし"
    if [ "$overall" != "ALERT" ]; then
        overall="WARN"
    fi
    alerts+=("queue YAML parse gate不在")
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

# --- Check 3.55: 修正commitのローカル先行(未push乖離) ---
# 2026-08-16 将軍自動化ターゲット: 修正commitがローカル止まりのまま放置されるとパイプライン契約(push→deploy→full並走)が止まる。
echo "■ 対象repo未push乖離"
source "$SCRIPT_DIR/scripts/lib/project_path.sh" 2>/dev/null || true
_cur_pj=$(grep -E '^current_project:' "$SCRIPT_DIR/config/projects.yaml" 2>/dev/null | awk '{print $2}' | tr -d '"'"'")
_pj_path=""
[ -n "$_cur_pj" ] && command -v get_project_path >/dev/null 2>&1 && _pj_path=$(get_project_path "$_cur_pj" 2>/dev/null || true)
for _repo in "$_pj_path" "$SCRIPT_DIR"; do
    [ -n "$_repo" ] && [ -d "$_repo/.git" ] || continue
    _ahead=$(git -C "$_repo" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
    _age_min=0
    if [ "${_ahead:-0}" -gt 0 ]; then
        _first_ts=$(git -C "$_repo" log --reverse --format=%ct '@{u}..HEAD' 2>/dev/null | head -1)
        [ -n "$_first_ts" ] && _age_min=$(( ( $(date +%s) - _first_ts ) / 60 ))
    fi
    if [ "${_ahead:-0}" -gt 0 ] && [ "$_age_min" -ge 30 ]; then
        echo "  ALERT: $(basename "$_repo") ローカル先行${_ahead}commit・最古${_age_min}分未push — 即時pushせよ (集計: git rev-list --count @{u}..HEAD)"
        overall="ALERT"
        alerts+=("未push乖離ALERT: $(basename "$_repo") ${_ahead}commit/${_age_min}分 — 即時pushせよ")
    elif [ "${_ahead:-0}" -gt 0 ] && [ "$_age_min" -ge 15 ]; then
        echo "  WARN: $(basename "$_repo") ローカル先行${_ahead}commit・最古${_age_min}分未push (集計: git rev-list --count @{u}..HEAD)"
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
            alerts+=("未push乖離: $(basename "$_repo") ${_ahead}commit/${_age_min}分")
        fi
    else
        echo "  OK: $(basename "$_repo") 先行${_ahead:-0}commit"
    fi
done
unset _repo _ahead _age_min _first_ts _cur_pj _pj_path

# --- Check 3.6: 掲示板action_required未対応 ---
echo "■ 掲示板action_required未対応"
if [ "${_bulletin_action_count:-0}" -gt 0 ]; then
    echo "  WARN: 未対応action_required掲示板 ${_bulletin_action_count}件"
    [ -n "$_bulletin_action_items" ] && echo "$_bulletin_action_items"
    echo "  → 対応cmdを起票/実行し、actioned_byを埋めよ"
    if [ "$overall" != "ALERT" ]; then
        overall="WARN"
        alerts+=("掲示板action_required未対応: ${_bulletin_action_count}件")
    fi
else
    echo "  未対応: 0件"
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
    read -r _rq_tag _rq_rate _rq_warn _rq_total _rq_old_rate _rq_review_warn _rq_review_total _rq_review_cmds _rq_terminal_gap_warn _rq_terminal_gap_cmds _rq_fp_warn _rq_fp_cmds _rq_pending_draft_total _rq_pending_draft_cmds <<< "$_review_quality_line"
    if [ -n "${_rq_old_rate:-}" ] && [ "${_rq_old_rate}" != "${_rq_rate}" ] 2>/dev/null; then
        echo "  実装品質WARN率 ${_rq_rate}% (${_rq_warn}/${_rq_total}, 実装cmdのみ・cmd_id単位最終verdict集計, 旧方式=${_rq_old_rate}%)"
    else
        echo "  実装品質WARN率 ${_rq_rate}% (${_rq_warn}/${_rq_total}, 実装cmdのみ・cmd_id単位最終verdict集計)"
    fi
    echo "  レビュー専用cmd分離 ${_rq_review_total:-0}件 (WARN ${_rq_review_warn:-0}件): ${_rq_review_cmds:--}"
    echo "  集計偽陽性分離 ${_rq_fp_warn:-0}件: ${_rq_fp_cmds:--}"
    echo "  未終端draft除外 ${_rq_pending_draft_total:-0}件: ${_rq_pending_draft_cmds:--}"
    if [ "${_rq_terminal_gap_warn:-0}" -gt 0 ] 2>/dev/null; then
        echo "  終端検証ギャップ ${_rq_terminal_gap_warn}件: ${_rq_terminal_gap_cmds:--}"
        alerts+=("レビュー終端検証ギャップ: ${_rq_terminal_gap_warn}件")
    else
        echo "  OK: 終端検証ギャップ 0件"
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
        # 「復活」は、最新の未解消WAと同じroot_signatureが過去に一度解消済みだった場合だけ。
        # 初回未解消や別署名を、単に最新がworkaround=trueという理由で復活扱いしない。
        _wa_revival="$(awk '
            function clean(v) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); gsub(/["'"'"']/, "", v); return v }
            function finish() {
                if (!seen) return
                count++
                cmd[count]=cur_cmd; sig[count]=cur_sig; resolved[count]=cur_resolved
            }
            /^[[:space:]]*-[[:space:]]*cmd_id:/ {
                finish(); seen=1; cur_sig=""; cur_resolved=""
                cur_cmd=$0; sub(/^.*cmd_id:[[:space:]]*/, "", cur_cmd); cur_cmd=clean(cur_cmd)
                next
            }
            seen && /^[[:space:]]*root_signature:/ {
                cur_sig=$0; sub(/^.*root_signature:[[:space:]]*/, "", cur_sig); cur_sig=clean(cur_sig); next
            }
            seen && /^[[:space:]]*resolved_by_cmd:/ {
                cur_resolved=$0; sub(/^.*resolved_by_cmd:[[:space:]]*/, "", cur_resolved); cur_resolved=clean(cur_resolved); next
            }
            END {
                finish()
                if (count < 1 || sig[count] == "" || resolved[count] != "") { print "0||"; exit }
                prior=0
                for (i=1; i<count; i++) if (sig[i] == sig[count] && resolved[i] != "") prior=1
                print prior "|" sig[count] "|" cmd[count]
            }
        ' "$wa_file")"
        IFS='|' read -r _wa_is_revival _wa_latest_sig _wa_latest_record_cmd <<< "${_wa_revival:-0||}"
        if [ "${_wa_is_revival:-0}" -eq 1 ]; then
            echo "  ALERT: WA再出現を検出 — 最新cmd ${_wa_latest_record_cmd} の root_signature=${_wa_latest_sig} は過去に解消済み。既存対策の再確認・強化候補"
            overall="ALERT"
            alerts+=("WA再出現: ${_wa_latest_record_cmd} (${_wa_latest_sig})")
        fi
    fi
    if [ "$WA_COUNT" -gt 0 ]; then
        echo "  カテゴリ: ${WA_CATS}"
        echo "  原因: ${WA_CAUSES}"
        if [ "${WA_MAX_COUNT:-0}" -ge 3 ]; then
            # CLEAR済み/resolved_by_cmd付きcmdを除いた実カウントで判定(誤分類・処理済みWAの永続ALERT防止)
            _dq_file="$SCRIPT_DIR/logs/cmd_design_quality.yaml"
            _effective_cat_count="$WA_MAX_COUNT"
            if [ -f "$_dq_file" ] && [ -n "${WA_MAX_CAT:-}" ]; then
                _effective_cat_count="$(awk -v cat_name="$WA_MAX_CAT" '
                    FILENAME == ARGV[1] {
                        if (/^- cmd_id:/) {
                            current=$0
                            sub(/^[[:space:]]*-[[:space:]]*cmd_id:[[:space:]]*/, "", current)
                            gsub(/["'"'"']/, "", current)
                            gsub(/[[:space:]]+$/, "", current)
                            cur_cmd=current
                        }
                        if (/workaround: true/) { wa_cmds[cur_cmd]=1 }
                        if (/^[[:space:]]*category:/) {
                            val=$0
                            sub(/.*category:[[:space:]]*/, "", val)
                            gsub(/[[:space:]]+$/, "", val)
                            cat_map[cur_cmd]=val
                        }
                        if (/^[[:space:]]*resolved_by_cmd:/) {
                            val=$0
                            sub(/.*resolved_by_cmd:[[:space:]]*/, "", val)
                            gsub(/["'"'"']/, "", val)
                            gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
                            if (val != "") resolved[cur_cmd]=1
                        }
                        next
                    }
                    FILENAME == ARGV[2] {
                        if (/^- cmd_id:/) {
                            dq=$0
                            sub(/^[[:space:]]*-[[:space:]]*cmd_id:[[:space:]]*"?/, "", dq)
                            sub(/"[[:space:]]*$/, "", dq)
                            sub(/[[:space:]]*$/, "", dq)
                            cur_dq=dq
                        }
                        if (/gate_result:/ && /CLEAR/) { cleared[cur_dq]=1 }
                        next
                    }
                    END {
                        effective=0
                        for (cmd in wa_cmds) {
                            if (cat_map[cmd] == cat_name && !cleared[cmd] && !resolved[cmd]) effective++
                        }
                        print effective+0
                    }
                ' "$wa_file" "$_dq_file")"
            fi
            if [ "${_effective_cat_count:-0}" -ge 3 ]; then
                echo "  ALERT: 同カテゴリ ${WA_MAX_CAT} が直近5件で ${WA_MAX_COUNT}件累積"
                overall="ALERT"
                alerts+=("workaround同カテゴリ累積: ${WA_MAX_CAT}=${WA_MAX_COUNT}")
            else
                echo "  INFO: 同カテゴリ ${WA_MAX_CAT} 累積=${WA_MAX_COUNT}件 (CLEAR済み除外後実=${_effective_cat_count}件、ALERT閾値3件未満)"
            fi
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
if grep -q '手戻り捕捉: ALERT' "$_WA_RATE_TMP" 2>/dev/null; then
    overall="ALERT"
    alerts+=("完了済みreworkの自動捕捉欠落: gate_workaround_rate.sh")
fi

# --- Check 7: 忍者別workaround率（バックグラウンド結果を回収） ---
echo "■ 忍者別workaround率"
if [ -n "$_NINJA_WA_PID" ]; then wait "$_NINJA_WA_PID" 2>/dev/null || true; fi
cat "$_NINJA_WA_TMP"

# --- Check 8: idle自走プロンプト ---
echo ""
echo "■ 自走チェック"
# 全忍者がidle or completedか確認（Check 2.5のstatusキャッシュを再利用: R3）
active_ninja_count=0
for ninja in $_KARO_NINJA_NAMES; do
    ninja_status=${_NINJA_STATUS_CACHE[$ninja]:-""}
    if [ -z "$ninja_status" ]; then
        task_file="$SCRIPT_DIR/queue/tasks/${ninja}.yaml"
        [ -f "$task_file" ] && ninja_status=$(awk '/^[[:space:]]*status:/{print $2; exit}' "$task_file" 2>/dev/null)
    fi
    if [[ "$ninja_status" =~ ^(assigned|acknowledged|in_progress)$ ]]; then
        active_ninja_count=$((active_ninja_count + 1))
    fi
done
if [ "$active_ninja_count" -eq 0 ] && [ "$unread" -eq 0 ]; then
    echo "  全忍者idle + inbox未読=0。cmd待ち状態。"
    echo "  ★★★ idle時自走プロトコルを実行せよ（instructions/karo.md参照） ★★★"
    echo "  Step 1: workaroundパターン分析(直近10件)"
    echo "  Step 2: 忍者品質プロファイル(個別WA率)"
    echo "  Step 3: 教訓有効性監査(有用率0%→deprecated)"
    echo "  Step 4: deploy_task.sh注入品質(教訓使用実態)"
    echo "  Step 5: パターン発見→なぜなぜ→行動"
    echo "  → 止まるな。1つ完了したら次へ"
else
    echo "  active忍者: ${active_ninja_count}名 / inbox未読: ${unread}件"
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

# --- Check 9.1: GATE CLEAR済みだがcmd品質記録なし ---
echo "■ cmd品質記録漏れチェック"
quality_missing_result=${quality_missing_result:-"0|"}
IFS='|' read -r QUALITY_MISSING_COUNT QUALITY_MISSING_CMDS <<< "$quality_missing_result"
if [ "${QUALITY_MISSING_COUNT:-0}" -gt 0 ]; then
    echo "  WARN: ${QUALITY_MISSING_COUNT}件のGATE CLEAR cmdがcmd_design_quality未記録: ${QUALITY_MISSING_CMDS}"
    echo "  action: /cmd-complete または cmd_quality_log.sh で品質記録まで完了せよ"
    if [ "$overall" != "ALERT" ] && [ "$overall" != "BLOCK" ]; then overall="WARN"; fi
    alerts+=("cmd品質記録漏れ${QUALITY_MISSING_COUNT}件: ${QUALITY_MISSING_CMDS}")
else
    echo "  OK: GATE CLEAR済みcmdはcmd_design_quality記録済み"
fi
echo ""

# --- Check 9.2: karo hotfix反復検知(同一対象反復→根因調査要求, cmd_3665) ---
echo "■ karo hotfix反復検知"
_HOTFIX_DQ_FILE="$SCRIPT_DIR/logs/cmd_design_quality.yaml"
_HOTFIX_RECUR_THRESHOLD="${KARO_HOTFIX_RECUR_THRESHOLD:-2}"
_HOTFIX_RECUR_WINDOW="${KARO_HOTFIX_RECUR_WINDOW:-50}"
if [ -f "$_HOTFIX_DQ_FILE" ]; then
    hotfix_recur_result="$(awk -v window="$_HOTFIX_RECUR_WINDOW" -v threshold="$_HOTFIX_RECUR_THRESHOLD" '
        BEGIN {
            resolved_until["cmd_karo_hotfix_skill_script_refs"] = "cmd_karo_hotfix_skill_script_refs_202607022043"
        }
        function hotfix_target(cmd,    target) {
            target = cmd
            sub(/_[0-9]{12,14}$/, "", target)
            return target
        }
        function has_ts_suffix(cmd) {
            return cmd ~ /_[0-9]{12,14}$/
        }
        /^(-[[:space:]]*cmd_id:|[[:space:]][[:space:]]cmd_id:)/ {
            s = $0
            sub(/^.*cmd_id:[[:space:]]*/, "", s)
            gsub(/["'"'"']/, "", s)
            gsub(/[[:space:]]+$/, "", s)
            if (s ~ /^cmd_karo_hotfix_/ && !(s in seen)) {
                seen[s] = 1
                order_n++
                order[order_n] = s
            }
        }
        END {
            start = order_n - window + 1
            if (start < 1) start = 1
            for (i = start; i <= order_n; i++) {
                cmd_id = order[i]
                target = hotfix_target(cmd_id)
                if (has_ts_suffix(cmd_id)) {
                    window_has_timestamped[target] = 1
                }
            }
            for (i = start; i <= order_n; i++) {
                cmd_id = order[i]
                target = hotfix_target(cmd_id)
                if (target in resolved_until && cmd_id <= resolved_until[target]) {
                    continue
                }
                if (!has_ts_suffix(cmd_id) && window_has_timestamped[target]) {
                    continue
                }
                cnt[target]++
                if (list[target] == "") { list[target] = cmd_id } else { list[target] = list[target] ";" cmd_id }
                last[target] = cmd_id
            }
            for (t in cnt) {
                if (cnt[t] + 0 >= threshold + 0) {
                    printf "%s|%d|%s|%s\n", t, cnt[t], last[t], list[t]
                }
            }
        }
    ' "$_HOTFIX_DQ_FILE" | sort -t'|' -k2 -rn)"

    if [ -n "$hotfix_recur_result" ]; then
        while IFS='|' read -r _hf_target _hf_count _hf_last _hf_list; do
            [ -z "$_hf_target" ] && continue
            echo "  ALERT: hotfix反復検知 — 対象=${_hf_target} 反復${_hf_count}回 直近該当cmd=${_hf_last} 該当cmd一覧=[${_hf_list}]"
            echo "  → 同一対象への反復hotfixは表面対処のサイン。根因調査タスクへ切替えよ(自動消火禁止原則)"
            overall="ALERT"
            alerts+=("karo hotfix反復: ${_hf_target}=${_hf_count}回(直近該当=${_hf_last})→根因調査タスクへ切替要求")
        done <<< "$hotfix_recur_result"
    else
        echo "  OK: 同一対象hotfixの反復なし(閾値${_HOTFIX_RECUR_THRESHOLD}回未満、窓${_HOTFIX_RECUR_WINDOW}件)"
    fi
else
    echo "  SKIP: ${_HOTFIX_DQ_FILE}不在"
fi
echo ""

# --- Check 9.2: failed task without formal FAIL close/archive ---
echo "■ failed task未閉鎖検知"
_failed_unclosed_count=0
for ninja in $_KARO_NINJA_NAMES; do
    _fuc_task_file="$SCRIPT_DIR/queue/tasks/${ninja}.yaml"
    [ -f "$_fuc_task_file" ] || continue
    _fuc_status=$(awk '/^[[:space:]]*status:/ { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["'"'"'[:space:]]/,"",v); print v; exit }' "$_fuc_task_file" 2>/dev/null)
    [ "$_fuc_status" = "failed" ] || continue
    _fuc_task_id=$(awk '/^[[:space:]]*task_id:/ && !/^[[:space:]]*_ac_task_id:/ { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["'"'"']/,"",v); gsub(/^[[:space:]]+|[[:space:]]+$/,"",v); print v; exit }' "$_fuc_task_file" 2>/dev/null)
    _fuc_parent_cmd=$(awk '/^[[:space:]]*parent_cmd:/ { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["'"'"']/,"",v); gsub(/^[[:space:]]+|[[:space:]]+$/,"",v); print v; exit }' "$_fuc_task_file" 2>/dev/null)
    if [ -n "$_fuc_parent_cmd" ]; then
        _fuc_current_files=$(list_current_task_files_for_cmd "$SCRIPT_DIR/queue/tasks" "$_fuc_parent_cmd")
        if [ -n "$_fuc_current_files" ] && ! printf '%s\n' "$_fuc_current_files" | grep -Fxq "$_fuc_task_file"; then
            echo "  INFO: ${ninja} failed task=${_fuc_task_id:-unknown} は新しい同一task_id世代へ再配備済みのため未閉鎖対象外"
            continue
        fi
    fi
    _fuc_report_rel=$(awk '/^[[:space:]]*report_path:/ { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["'"'"']/,"",v); gsub(/^[[:space:]]+|[[:space:]]+$/,"",v); print v; exit }' "$_fuc_task_file" 2>/dev/null)
    _fuc_report_file=""
    if [ -n "$_fuc_report_rel" ] && [ -f "$SCRIPT_DIR/$_fuc_report_rel" ]; then
        _fuc_report_file="$SCRIPT_DIR/$_fuc_report_rel"
    elif [ -n "$_fuc_report_rel" ]; then
        _fuc_base="${_fuc_report_rel##*/}"
        _fuc_report_file=$(find "$SCRIPT_DIR/queue/archive/reports" -maxdepth 1 -name "${_fuc_base%.yaml}*.yaml" -print 2>/dev/null | head -1 || true)
    fi
    _fuc_terminal="MISSING"
    [ -z "$_fuc_report_file" ] || _fuc_terminal=$(report_terminal_state "$_fuc_report_file")
    [ "$_fuc_terminal" = "CLOSED_BLOCKED" ] && continue
    echo "  ALERT: ${ninja} failed_unclosed task=${_fuc_task_id:-unknown} report_state=${_fuc_terminal} action=review_failed_task"
    overall="ALERT"
    alerts+=("${ninja}: failed_unclosed task=${_fuc_task_id:-unknown} report_state=${_fuc_terminal} action=review_failed_task")
    _failed_unclosed_count=$((_failed_unclosed_count + 1))
done
[ "$_failed_unclosed_count" -gt 0 ] || echo "  OK: failed_unclosed 0件"
echo ""

# --- Check 9.2b: completed task with active report but no terminal archive ---
# A completed report is not a closed lifecycle until archive.done and the
# ordered cmd_complete terminal checkpoint are both durable.  This check is
# intentionally independent from the idle/pane checks so a busy Karo cannot
# hide a report that would block the next deployment.
echo "■ completed未archive検知"
_completed_unarchived_count=0
# A terminal report is not archiveable merely because its generation can be
# hashed.  The cmd_complete worker owns the durable CLEAR receipt; require the
# same report generation in that receipt before invoking archive_completed.
_gate_worker_clear_receipt_matches_generation() {
    local marker="$1" expected_cmd="$2" expected_generation="$3"
    python3 - "$marker" "$expected_cmd" "$expected_generation" <<'PY'
import json
import re
import sys

marker, expected_cmd, expected_generation = sys.argv[1:]
try:
    with open(marker, encoding="utf-8") as fh:
        data = json.load(fh)
except (OSError, ValueError, TypeError):
    raise SystemExit(1)

if not isinstance(data, dict):
    raise SystemExit(1)
if data.get("version") != 1 or data.get("state") != "clear":
    raise SystemExit(1)
if data.get("cmd_id") != expected_cmd:
    raise SystemExit(1)
generation = str(data.get("completion_generation") or "")
if not re.fullmatch(r"[0-9a-f]{64}", generation):
    raise SystemExit(1)
if generation != expected_generation:
    raise SystemExit(1)
try:
    if int(data.get("persisted_at_ns")) <= 0:
        raise SystemExit(1)
except (TypeError, ValueError):
    raise SystemExit(1)
PY
}

for _cur_ninja in $_KARO_NINJA_NAMES; do
    _cur_task_file="$SCRIPT_DIR/queue/tasks/${_cur_ninja}.yaml"
    [ -f "$_cur_task_file" ] || continue
    _cur_status=$(awk '/^[[:space:]]*status:/ { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/[[:space:]]/,"",v); gsub(/"/,"",v); print v; exit }' "$_cur_task_file" 2>/dev/null)
    case "$_cur_status" in done|completed|PASS) ;; *) continue ;; esac
    _cur_parent_cmd=$(awk '/^[[:space:]]*parent_cmd:/ { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/[[:space:]]/,"",v); gsub(/"/,"",v); print v; exit }' "$_cur_task_file" 2>/dev/null)
    [ -n "$_cur_parent_cmd" ] || continue
    _cur_gate_dir="$SCRIPT_DIR/queue/gates/$_cur_parent_cmd"
    if [ -f "$_cur_gate_dir/archive.done" ] &&
       [ -f "$_cur_gate_dir/completion_tail.log" ] &&
       grep -Fqx -- "[cmd_complete] COMPLETE $_cur_parent_cmd" "$_cur_gate_dir/completion_tail.log"; then
        continue
    fi
    _cur_active_report=""
    while IFS= read -r _cur_candidate; do
        [ -f "$_cur_candidate" ] && [ ! -L "$_cur_candidate" ] || continue
        _cur_active_report="$_cur_candidate"
        break
    done < <(find "$SCRIPT_DIR/queue/reports" -maxdepth 1 -type f -name "${_cur_ninja}_report_${_cur_parent_cmd}*.yaml" -print 2>/dev/null)
    [ -n "$_cur_active_report" ] || continue
    _cur_archive_script="$SCRIPT_DIR/scripts/archive_completed.sh"
    _cur_generation="$(sha256sum "$_cur_active_report" | awk '{print $1}')"
    _cur_clear_marker="$_cur_gate_dir/gate_worker.clear.json"
    if ! _gate_worker_clear_receipt_matches_generation \
        "$_cur_clear_marker" "$_cur_parent_cmd" "$_cur_generation"; then
        # Do not let a missing/stale worker receipt become a terminal archive.
        # yaml_field_set is the shared atomic task-state writer; failure to
        # revert is itself a BLOCK, never a reason to continue archiving.
        _cur_revert_rc=0
        bash "$SCRIPT_DIR/scripts/lib/yaml_field_set.sh" \
            "$_cur_task_file" task status in_progress >/dev/null 2>&1 || _cur_revert_rc=$?
        if [ "$_cur_revert_rc" -eq 0 ]; then
            echo "  BLOCK: ${_cur_ninja} completed_unarchived task=${_cur_parent_cmd} CLEAR receipt missing or generation mismatch; task→in_progress; archive_completed skipped"
        else
            echo "  BLOCK: ${_cur_ninja} completed_unarchived task=${_cur_parent_cmd} CLEAR receipt missing and task revert failed; archive_completed skipped"
        fi
        overall="BLOCK"
        alerts+=("${_cur_ninja}: completed_unarchived task=${_cur_parent_cmd} clear_receipt_required task_reverted_in_progress=${_cur_revert_rc:-0}")
        _completed_unarchived_count=$((_completed_unarchived_count + 1))
        continue
    fi
    _cur_archive_ok=0
    if [[ -x "$_cur_archive_script" && "$_cur_generation" =~ ^[0-9a-f]{64}$ ]]; then
        if env ARCHIVE_COMPLETED_PROJECT_DIR="$SCRIPT_DIR" \
            ARCHIVE_REQUIRE_CLEAR_RECEIPT=1 \
            SHOGUN_COMPLETION_GENERATION="$_cur_generation" \
            bash "$_cur_archive_script" "$_cur_parent_cmd" >/dev/null 2>&1; then
            _cur_archive_ok=1
        fi
    fi
    if [ "$_cur_archive_ok" -eq 1 ] && [ -f "$_cur_gate_dir/archive.done" ]; then
        echo "  OK: ${_cur_ninja} completed_unarchived task=${_cur_parent_cmd} auto_archived report=$(basename "$_cur_active_report")"
    else
        echo "  ALERT: ${_cur_ninja} completed_unarchived task=${_cur_parent_cmd} report=$(basename "$_cur_active_report") action=archive_terminal_failed"
        overall="ALERT"
        alerts+=("${_cur_ninja}: completed_unarchived task=${_cur_parent_cmd} report=$(basename "$_cur_active_report") action=archive_terminal_failed")
        _completed_unarchived_count=$((_completed_unarchived_count + 1))
    fi
done
[ "$_completed_unarchived_count" -gt 0 ] || echo "  OK: completed_unarchived 0件"
echo ""

# --- Check 9.3: task status=failed × report status=completed 乖離検知 (INS-20260708-165744270-6a1d) ---
# cmd_3771/3772がtask status=failed+報告YAML status=completedの乖離状態で約75分滞留した事故の再発防止
echo "■ failed×report completed 乖離検知"
_FRM_THRESHOLD_MIN="${KARO_FAILED_REPORT_MISMATCH_MIN:-20}"
_frm_now=$(date +%s)
_frm_count=0
_frm_wait_count=0
for ninja in $_KARO_NINJA_NAMES; do
    _frm_task_file="$SCRIPT_DIR/queue/tasks/${ninja}.yaml"
    [ -f "$_frm_task_file" ] || continue
    _frm_task_status=${_NINJA_STATUS_CACHE[$ninja]:-}
    if [ -z "$_frm_task_status" ]; then
        _frm_task_status=$(awk '/^[[:space:]]*status:/ { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["'"'"'[:space:]]/,"",v); print v; exit }' "$_frm_task_file" 2>/dev/null)
    fi
    [ "$_frm_task_status" = "failed" ] || continue
    _frm_report_rel=$(awk '/^[[:space:]]*report_path:/ { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["'"'"']/,"",v); gsub(/^[[:space:]]+|[[:space:]]+$/,"",v); print v; exit }' "$_frm_task_file" 2>/dev/null)
    [ -n "$_frm_report_rel" ] || continue
    _frm_report_full="$SCRIPT_DIR/$_frm_report_rel"
    [ -f "$_frm_report_full" ] || continue
    _frm_report_status=$(awk '/^status:/ { print $2; exit }' "$_frm_report_full" 2>/dev/null)
    [ "$_frm_report_status" = "completed" ] || continue
    # report.status=completed means that the report document is complete; it
    # does not mean that the task succeeded.  A completed report whose verdict
    # is FAIL is the canonical terminal record for a failed task and therefore
    # is not a state mismatch.  Only success-like/unknown verdicts need the
    # stale mismatch escalation below.
    _frm_report_verdict=$(awk '/^verdict:/ { print $2; exit }' "$_frm_report_full" 2>/dev/null)
    _frm_report_status_detail=$(awk '/^status_detail:/ { print $2; exit }' "$_frm_report_full" 2>/dev/null)
    _frm_terminal_state=$(report_terminal_state "$_frm_report_full")
    if [ "$_frm_terminal_state" = "CLOSED_BLOCKED" ]; then
        echo "  CLOSED_BLOCKED: ${ninja} task=failed report=completed verdict=${_frm_report_verdict:-unknown} status_detail=${_frm_report_status_detail:-unknown} (report=${_frm_report_rel})"
        _frm_wait_count=$((_frm_wait_count + 1))
        continue
    fi
    _frm_superseded_by=$(awk '/^[[:space:]]*superseded_by:/ { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["'"'"']/,"",v); gsub(/^[[:space:]]+|[[:space:]]+$/,"",v); print v; exit }' "$_frm_task_file" 2>/dev/null)
    if [ -n "$_frm_superseded_by" ]; then
        if awk -v cmd="$_frm_superseded_by" 'BEGIN { found=0 } $2 == cmd && $3 == "CLEAR" { found=1 } END { exit found ? 0 : 1 }' "$SCRIPT_DIR/logs/gate_metrics.log" 2>/dev/null; then
            echo "  SUPERSEDED: ${ninja} task=failed report=completed covered_by=${_frm_superseded_by} GATE CLEAR (report=${_frm_report_rel})"
            _frm_wait_count=$((_frm_wait_count + 1))
            continue
        fi
    fi
    _frm_wait_reason=$(awk '/^[[:space:]]*wait_reason:/ { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["'"'"']/,"",v); gsub(/^[[:space:]]+|[[:space:]]+$/,"",v); print v; exit }' "$_frm_task_file" 2>/dev/null)
    _frm_wait_connected_cmd=$(awk '/^[[:space:]]*wait_connected_cmd:/ { v=$0; sub(/^[^:]*:[[:space:]]*/,"",v); gsub(/["'"'"']/,"",v); gsub(/^[[:space:]]+|[[:space:]]+$/,"",v); print v; exit }' "$_frm_task_file" 2>/dev/null)
    case "$_frm_wait_reason" in
        external_input|evidence_gathering|dependency)
            if [ -n "$_frm_wait_connected_cmd" ]; then
                echo "  WAIT: ${ninja} task=failed report=completed but wait_reason=${_frm_wait_reason} connected=${_frm_wait_connected_cmd} (report=${_frm_report_rel})"
                _frm_wait_count=$((_frm_wait_count + 1))
                continue
            fi
            ;;
    esac
    _frm_mtime=$(stat -c %Y "$_frm_task_file" 2>/dev/null || echo 0)
    [ "$_frm_mtime" -gt 0 ] || continue
    _frm_age_min=$(( (_frm_now - _frm_mtime) / 60 ))
    if [ "$_frm_age_min" -ge "$_FRM_THRESHOLD_MIN" ]; then
        echo "  ALERT: ${ninja} task=failed report=completed 乖離${_frm_age_min}分継続(report=${_frm_report_rel}) → 再ゲート要検討"
        _frm_count=$((_frm_count + 1))
        overall="ALERT"
        alerts+=("${ninja}: failed×report completed乖離${_frm_age_min}分(要再ゲート)")
    fi
done
if [ "$_frm_count" -eq 0 ]; then
    if [ "$_frm_wait_count" -gt 0 ]; then
        echo "  OK: failed×report completedの未宣言乖離なし(wait=${_frm_wait_count})"
    else
        echo "  OK: failed×report completedの乖離なし"
    fi
fi
echo ""

# tmpファイル削除
rm -f "$_WA_RATE_TMP" "$_WA_RATE_ERR_TMP" "$_NINJA_WA_TMP" "$_WA_DQ_TMP" \
    "$_QUEUE_YAML_PARSE_TMP" \
    "$_aggregate_tmp"

# --- Check 9.5: 三層記憶DB健全性 ---
echo "■ 三層記憶DB健全性"
three_layer_health_script="$SCRIPT_DIR/scripts/gates/gate_three_layer_health.sh"
if [ -x "$three_layer_health_script" ]; then
    _tlh_cache_sig=""
    _tlh_current_sig="$(
        {
            stat -c 'script:%n:%y:%s' "$three_layer_health_script" 2>/dev/null || true
            if [ -n "${SHOGUN_MEMORY_DB_CACHE_PATH:-}" ]; then
                _tlh_cache_path="${SHOGUN_MEMORY_DB_CACHE_PATH}"
                _tlh_cache_dir="${_tlh_cache_path%/*}"
            else
                _tlh_db_path="${SHOGUN_MEMORY_DB:-$SCRIPT_DIR/data/multi_agent_shogun_memory.db}"
                _tlh_cache_dir="${SHOGUN_MEMORY_DB_CACHE_DIR:-/tmp/shogun_memory_db_cache}"
                _tlh_repo_key="${SCRIPT_DIR//[^A-Za-z0-9_.-]/_}"
                _tlh_cache_path="${_tlh_cache_dir}/${_tlh_repo_key}_${_tlh_db_path##*/}"
            fi
            stat -c 'cache:%n:%Y:%s' "$_tlh_cache_path" 2>/dev/null || printf 'cache:%s:missing\n' "$_tlh_cache_path"
            for _tlh_suffix in -wal -shm -journal; do
                stat -c "sidecar:${_tlh_suffix}:%n:%Y:%s" "${_tlh_cache_path}${_tlh_suffix}" 2>/dev/null \
                    || printf 'sidecar:%s:%s:missing\n' "$_tlh_suffix" "${_tlh_cache_path}${_tlh_suffix}"
            done
            if [ -d "$_tlh_cache_dir" ]; then
                stat -c 'cache_dir:%n:%Y:%s' "$_tlh_cache_dir" 2>/dev/null || true
            else
                printf 'cache_dir:%s:missing\n' "$_tlh_cache_dir"
            fi
        } | sha256sum | awk '{print $1}'
    )"
    if [[ -f "$_THREE_LAYER_HEALTH_CACHE" ]]; then
        IFS= read -r _tlh_cache_sig < "$_THREE_LAYER_HEALTH_CACHE" || _tlh_cache_sig=""
    fi
    if [[ -f "$_THREE_LAYER_HEALTH_CACHE" ]] \
        && [[ "$_tlh_cache_sig" == "$_tlh_current_sig" ]] \
        && (( _now_epoch - $(stat -c %Y "$_THREE_LAYER_HEALTH_CACHE" 2>/dev/null || echo 0) < _THREE_LAYER_HEALTH_CACHE_TTL )); then
        _tlh_rc="$(sed -n '2p' "$_THREE_LAYER_HEALTH_CACHE")"
        [ -n "$_tlh_rc" ] || _tlh_rc=1
        three_layer_health_output="$(tail -n +3 "$_THREE_LAYER_HEALTH_CACHE")"
    else
        if three_layer_health_output="$(bash "$three_layer_health_script" 2>&1)"; then
            _tlh_rc=0
        else
            _tlh_rc=$?
        fi
        {
            printf '%s\n' "$_tlh_current_sig"
            printf '%s\n' "$_tlh_rc"
            printf '%s\n' "$three_layer_health_output"
        } > "$_THREE_LAYER_HEALTH_CACHE"
    fi
    printf '%s\n' "$three_layer_health_output" | sed 's/^/  /'
    if [ "$_tlh_rc" -ne 0 ]; then
        if [ "$overall" != "ALERT" ] && [ "$overall" != "BLOCK" ]; then overall="WARN"; fi
        alerts+=("三層記憶DB健全性: WARN")
    fi
else
    echo "  WARN: gate_three_layer_health.sh不在"
    if [ "$overall" != "ALERT" ] && [ "$overall" != "BLOCK" ]; then overall="WARN"; fi
    alerts+=("三層記憶DB健全性: gate不在")
fi

# --- Check 10: スキル実行品質サマリ ---
echo "■ スキル実行品質"
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
        _skill_current_sig="$(stat -c '%n:%y:%s' "$SCRIPT_DIR/logs/skill_execution_log.yaml" 2>/dev/null || echo '')"
    fi
    _skill_current_sig="${_skill_current_sig}|gate:$(stat -c '%n:%y:%s' "$SCRIPT_DIR/scripts/gates/gate_karo_startup.sh" 2>/dev/null || echo '')"
    _skill_current_sig="${_skill_current_sig}|summary:$(stat -c '%n:%y:%s' "$SCRIPT_DIR/scripts/skill_execution_log.sh" 2>/dev/null || echo '')"
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
        echo "  スキル実行品質: ${skill_quality_line}"
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
            alerts+=("スキル実行品質: FAIL記録あり")
        fi
    else
        echo "  スキル実行品質: 全PASS"
    fi
else
    echo "  SKIP: skill_execution_log.sh が存在しないか実行権限なし"
fi

echo "  スキル静的品質Gate:"
for _skill_static_spec in \
    "quality|gate_skill_quality.sh" \
    "health|gate_skill_health.sh" \
    "script_refs|gate_skill_script_refs.sh"; do
    IFS='|' read -r _skill_static_label _skill_static_name <<< "$_skill_static_spec"
    _skill_static_path="$SCRIPT_DIR/scripts/gates/$_skill_static_name"
    if [ ! -x "$_skill_static_path" ]; then
        echo "    ALERT: ${_skill_static_label}: ${_skill_static_name}不在/実行不可"
        overall="ALERT"
        alerts+=("スキル静的品質Gate不在: ${_skill_static_name}")
        continue
    fi
    set +e
    _skill_static_output="$(bash "$_skill_static_path" 2>&1)"
    _skill_static_rc=$?
    set -e
    _skill_static_summary="$(printf '%s\n' "$_skill_static_output" | grep -E -- '--- 総合判定:|走査: .*PASS:' | tail -n 2 | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    [ -n "$_skill_static_summary" ] || _skill_static_summary="rc=${_skill_static_rc}"
    if [ "$_skill_static_rc" -eq 0 ]; then
        echo "    PASS: ${_skill_static_label}: ${_skill_static_summary}"
    elif [ "$_skill_static_rc" -eq 2 ]; then
        if printf '%s\n' "$_skill_static_output" | grep -q '^FOLLOWUP_COVERS_REVIEW_REQUIRED: yes$'; then
            echo "    WARN: ${_skill_static_label}: ${_skill_static_summary} (followup routed; duplicate escalation suppressed)"
            if [ "$overall" != "ALERT" ] && [ "$overall" != "BLOCK" ]; then overall="WARN"; fi
            continue
        fi
        echo "    WARN: ${_skill_static_label}: ${_skill_static_summary}"
        if [ "$overall" != "ALERT" ] && [ "$overall" != "BLOCK" ]; then overall="WARN"; fi
        alerts+=("スキル静的品質WARN: ${_skill_static_name}")
    else
        echo "    ALERT: ${_skill_static_label}: ${_skill_static_summary}"
        overall="ALERT"
        alerts+=("スキル静的品質FAIL: ${_skill_static_name}")
    fi
done
echo "  スキル推薦 precision/recall:"
skill_recommend_metrics_script="$SCRIPT_DIR/scripts/skill_recommend_metrics.sh"
if [ -x "$skill_recommend_metrics_script" ] || [ -f "$skill_recommend_metrics_script" ]; then
    _skill_rec_cache_sig=""
    _skill_rec_current_sig="$(stat -c '%n:%y:%s' "$skill_recommend_metrics_script" 2>/dev/null || echo '')"
    _skill_rec_current_sig="${_skill_rec_current_sig}|$(stat -c '%n:%y:%s' "$SCRIPT_DIR/logs/skill_recommend_log.yaml" 2>/dev/null || echo '')"
    _skill_rec_current_sig="${_skill_rec_current_sig}|$(stat -c '%n:%y:%s' "$SCRIPT_DIR/logs/skill_execution_log.yaml" 2>/dev/null || echo '')"
    if [[ -f "$_SKILL_RECOMMEND_CACHE" ]]; then
        IFS= read -r _skill_rec_cache_sig < "$_SKILL_RECOMMEND_CACHE" || _skill_rec_cache_sig=""
    fi
    if [[ -f "$_SKILL_RECOMMEND_CACHE" ]] \
        && [[ "$_skill_rec_cache_sig" == "$_skill_rec_current_sig" ]] \
        && (( _now_epoch - $(stat -c %Y "$_SKILL_RECOMMEND_CACHE" 2>/dev/null || echo 0) < _SKILL_RECOMMEND_CACHE_TTL )); then
        _skill_rec_status="$(sed -n '2p' "$_SKILL_RECOMMEND_CACHE")"
        [ -n "$_skill_rec_status" ] || _skill_rec_status=1
        _skill_rec_out="$(tail -n +3 "$_SKILL_RECOMMEND_CACHE")"
    else
        set +e
        _skill_rec_out="$(bash "$skill_recommend_metrics_script" 30 2>&1)"
        _skill_rec_status=$?
        set -e
        {
            printf '%s\n' "$_skill_rec_current_sig"
            printf '%s\n' "$_skill_rec_status"
            printf '%s\n' "$_skill_rec_out"
        } > "$_SKILL_RECOMMEND_CACHE"
    fi
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

# --- WA記録あり×教訓未登録の検知(学びの即時登録原則・殿指摘2026-07-25) ---
# 殿の「いまクリアされても今より強くてニューゲーム」の真意は「clear前に荷造りせよ」ではなく
# 「clearは予告なく起こる。学びは発生した瞬間に環境へ埋め、いまが常に復帰可能点であれ」。
# 家老の学びの発生点は karo_workarounds(手動補正の記録)である。WAを記録したのに
# 同日 lessons_karo へ登録が無い場合、その学びは家老個体の中にあり clear で消える。
echo "■ WA記録×教訓登録の追随"
_wa_file="$SCRIPT_DIR/logs/karo_workarounds.yaml"
_lk_file="$SCRIPT_DIR/projects/infra/lessons_karo.yaml"
if [ -f "$_wa_file" ] && [ -f "$_lk_file" ]; then
    _today=$(date +%Y-%m-%d)
    _wa_today=$(python3 -c "import yaml,sys;ws=yaml.safe_load(open(sys.argv[1]))or[];print(sum(1 for w in ws if isinstance(w,dict) and w.get(chr(39)+chr(39)) is None and w.get(\"workaround\") is True and sys.argv[2] in str(w.get(\"timestamp\",\"\"))))" "$_wa_file" "$_today" 2>/dev/null | tr -d "\n" | tr -d " " || true)
    _lk_today=$(grep -c "${_today}" "$_lk_file" 2>/dev/null | tr -d "\n" | tr -d " " || true)
    [ -n "$_wa_today" ] || _wa_today=0
    [ -n "$_lk_today" ] || _lk_today=0
    case "$_wa_today" in *[!0-9]*) _wa_today=0 ;; esac
    case "$_lk_today" in *[!0-9]*) _lk_today=0 ;; esac
    echo "  本日: WA記録 ${_wa_today}件 / 教訓登録 ${_lk_today}件"
    if [ "${_wa_today:-0}" -gt 0 ] && [ "${_lk_today:-0}" -eq 0 ]; then
        echo "  ALERT: WAを記録したが本日の教訓登録が0件。学びが家老個体の中に留まっている"
        echo "  ACTION: bash scripts/lesson_write_karo.sh でそのターン内に登録せよ。clear前の一括登録は荷造り型=手遅れ"
        overall="ALERT"
        alerts+=("WA記録あり×本日の教訓登録0件 — 学びが環境へ埋まっていない")
    else
        echo "  OK: 学びの外部化が追随している"
    fi
else
    echo "  SKIP: WAログまたは教訓ファイル不在"
fi

# --- 教訓enforcement欠落検知 ---
# 2026-07-25: 家老が代行登録したLG065にenforcementが無く、書いただけで起動時に効かない
# 状態だった(軍師が/clear直前に指摘)。実測で lessons_karo 35件中12件(34%)、
# lessons_gunshi 2件が同状態。enforcementの無い教訓は受動的層へ載らず、次の自分に届かない。
# 「登録した」で満足せず「注入される状態か」を毎起動で二値確認する。
echo "■ 教訓enforcement欠落"
_enf_out=$(timeout 10 python3 - "$SCRIPT_DIR" <<'PYEOF' 2>/dev/null || true
import sys, yaml
from pathlib import Path
root = Path(sys.argv[1])
total_missing = 0
for name in ("karo", "gunshi", "shogun"):
    f = root / "projects" / "infra" / f"lessons_{name}.yaml"
    if not f.is_file():
        continue
    try:
        data = yaml.safe_load(f.read_text(encoding="utf-8")) or {}
    except Exception:
        continue
    lessons = data.get("lessons") if isinstance(data, dict) else data
    if not isinstance(lessons, list):
        continue
    missing = [str(x.get("id")) for x in lessons if isinstance(x, dict) and not x.get("enforcement")]
    if missing:
        total_missing += len(missing)
        print(f"  ALERT: lessons_{name} {len(missing)}/{len(lessons)}件 enforcement欠落: {' '.join(missing[:8])}")
if total_missing == 0:
    print("  OK: 全ロールの教訓にenforcement記載あり")
PYEOF
)
echo "${_enf_out:-  SKIP: 検査不能}"
if echo "$_enf_out" | grep -q "ALERT:"; then
    echo "  ACTION: enforcement欄へ注入経路(Level5=起動時全文ロード等)を明記せよ。書いただけの教訓は次の自分に届かない"
    overall="ALERT"
    alerts+=("教訓enforcement欠落 — 書いただけで効かない教訓がある")
fi

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
    function trim_brainwash_value(v) {
        sub(/^.*brainwash_check:[[:space:]]*/, "", v)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        gsub(/^["\047]+|["\047]+$/, "", v)
        return v
    }
    function has_real_brainwash_value(v) {
        v = trim_brainwash_value(v)
        return (v != "" && v != "null" && v != "{}" && v != "[]")
    }
    BEGIN { total=0; has_bc=0; no_bc=0; no_bc_cmds="" }
    /^- (cmd_id|cmd|timestamp):/ { flush(); in_entry=1; wa=0; bc=0; in_bc_block=0; cmd_label="" }
    in_entry && /workaround: true/ { wa=1 }
    in_entry && /^  brainwash_check:/ {
        in_bc_block=1
        if (has_real_brainwash_value($0)) bc=1
        next
    }
    in_entry && in_bc_block && /^    / {
        child=$0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", child)
        gsub(/^["\047]+|["\047]+$/, "", child)
        if (child != "" && child !~ /^#/) bc=1
        next
    }
    in_entry && /^  [^ ]/ { in_bc_block=0 }
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
    [ -f "$STARTUP_ALERT_HISTORY" ] || : > "$STARTUP_ALERT_HISTORY"
    # §3.2: python3→awk置換(~650ms削減)。alert文字列は空白を含むためtmp経由で1行1alertにする。
    _current_alerts_file="$(mktemp)"
    printf '%s\n' "${alerts[@]}" > "$_current_alerts_file"
    # run間隔がgap秒未満のrunは同一セッションに統合する。
    # gateは検分/ninja_monitor/完了フロー等から数分間に複数回実行されるため、
    # run=セッションの代理計測は「2分半で3セッション連続」の誤CRITICALを生む(2026-07-02実証)。
    # __OK__行はクリーンセッションとしてバケットを立てstreakを切る(解消信号の無視はLS078変種)
    _streak_session_gap="${KARO_STREAK_SESSION_GAP_SEC:-1800}"
    _streak_result=$(awk -F'\t' -v threshold="$STARTUP_WARN_STREAK_THRESHOLD" -v min_gap="$_streak_session_gap" '
    function iso_epoch(ts,    d) {
        d = substr(ts, 1, 19)
        gsub(/[-T:]/, " ", d)
        return mktime(d)
    }
    BEGIN { n_runs = 0 }
    NR == FNR {
        if ($0 != "") current[$0] = 1
        next
    }
    NF == 2 {
        if ($1 != prev_run) {
            _ep = iso_epoch($1)
            # タイムスタンプ非パース(レガシーrun ID等)は間隔判定不能→従来通り別セッション扱い
            if (prev_run != "") {
                if (_ep < 0 || prev_ep < 0 || _ep - prev_ep >= min_gap) n_runs++
            }
            prev_run = $1
            prev_ep = _ep
        }
        if ($2 != "__OK__") run_keys[n_runs, $2] = 1
    }
    END {
        if (threshold <= 1) {
            for (k in current) print k
            exit
        }
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
            echo "  先送り判断検出: ${STARTUP_WARN_STREAK_THRESHOLD}セッション連続で未解消。今処理するか、wait_reason(external_input/evidence_gathering/dependency)を宣言して既存cmdへ接続せよ。"
            alerts+=("先送りCRITICAL: ${_streak_key} が${STARTUP_WARN_STREAK_THRESHOLD}セッション連続")
        done <<< "$_streak_result"
        # 家老BLOCKは忍者配備全停止を招くため、BLOCK昇格せず起動は許可する
        # 代わりにntfyで殿/将軍に通知し、CRITICAL表示で注意喚起
        if [ "$overall" != "ALERT" ] && [ "$overall" != "BLOCK" ]; then overall="ALERT"; fi
        bash "$SCRIPT_DIR/scripts/ntfy.sh" "【家老CRITICAL】先送り${STARTUP_WARN_STREAK_THRESHOLD}セッション連続検出。起動は許可するが即対処必須" 2>/dev/null || true
    fi
fi

# --- T3(cmd_karo_hotfix_auto_clear_recovery_20260727 AC4): 直近CLEAR-BLOCKED現況表示 ---
# 設計書§3.2 T3: /clear後に着任した指揮官へ現況を伝える。0件時は無表示。
_clear_blocked_line="$(bash "$SCRIPT_DIR/scripts/gates/lib/clear_blocked_summary.sh" 2>/dev/null || true)"
if [ -n "$_clear_blocked_line" ]; then
    echo ""
    echo "■ CLEAR-BLOCKED現況(直近30分)"
    echo "  $_clear_blocked_line"
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
[ "${_disk_status:-}" = "BLOCK" ] && overall="BLOCK"
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
else
    _alert_flag="$SCRIPT_DIR/queue/gates/karo_alert_pending.txt"
    rm -f "$_alert_flag"
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

# --- session_alerts_karo.txt: 起動時初期生成（stop hookのロール分離対応 cmd_3487） ---
_session_alerts_file="$SCRIPT_DIR/queue/session_alerts_karo.txt"
render_session_alerts_file "$_session_alerts_file" "session_alerts_karo" "$_startup_run_id" "${alerts[@]}"

# --- L1先送り自動エスカレーション: 先送りCRITICAL検出→将軍にinbox送信 ---
KARO_STARTUP_ESCALATION_CORRECTION_COMMAND="${KARO_STARTUP_ESCALATION_CORRECTION_COMMAND:-}"
karo_startup_correction_command() {
    local alert="$1" cmd_id="" report_name="" report_file="" generation=""
    if [ -n "$KARO_STARTUP_ESCALATION_CORRECTION_COMMAND" ]; then
        printf '%s\n' "$KARO_STARTUP_ESCALATION_CORRECTION_COMMAND"
        return 0
    fi
    case "$alert" in
        *"completed_unarchived task="*)
            cmd_id="${alert##*completed_unarchived task=}"
            cmd_id="${cmd_id%% *}"
            report_name="${alert##* report=}"
            report_name="${report_name%% *}"
            if [[ "$report_name" =~ ^[A-Za-z0-9_.-]+\.yaml$ ]]; then
                report_file="$(find "$SCRIPT_DIR/queue/reports" -maxdepth 1 -type f -name "$report_name" -print -quit 2>/dev/null || true)"
            fi
            # 2026-09-01: completed_unarchived の alert 文には " report=" が無く(L2673)、
            # report_name が alert 全文になって上の regex を外れ、常に `false` プレースホルダ
            # →『是正コマンドが非0終了したが出力なし』の CRITICAL escalation を将軍へ毎起動送っていた
            # (本日 4 通、殿指示 13:22 監査で検出)。cmd_id から報告を引き、CLEAR receipt が
            # 要るなら GATE 実行そのものを是正コマンドにする。
            if [ -z "$report_file" ] && [[ "$cmd_id" == cmd_* ]]; then
                report_file="$(find "$SCRIPT_DIR/queue/reports" -maxdepth 1 -type f -name "*_report_${cmd_id}.yaml" -print -quit 2>/dev/null || true)"
            fi
            [ -n "$report_file" ] && generation="$(sha256sum "$report_file" | awk '{print $1}')"
            if [[ "$cmd_id" == cmd_* ]] && [[ "$alert" == *clear_receipt_required* ]] && [ -n "$report_file" ]; then
                printf 'bash scripts/cmd_complete_gate.sh %q\n' "$cmd_id"
                return 0
            fi
            if [[ "$cmd_id" == cmd_* ]]; then
                if [[ "$generation" =~ ^[0-9a-f]{64}$ ]]; then
                    printf 'ARCHIVE_COMPLETED_PROJECT_DIR=%q SHOGUN_COMPLETION_GENERATION=%q bash scripts/archive_completed.sh %q\n' \
                        "$SCRIPT_DIR" "$generation" "$cmd_id"
                else
                    printf 'false # report generation unavailable for %q\n' "$report_name"
                fi
                return 0
            fi
            ;;
    esac
    # All other alert classes use the already-owned Karo migration lane as a
    # bounded corrective verification.  A non-zero result is required before
    # the escalation branch is allowed to notify Shogun.
    printf 'bash scripts/gates/gate_karo_startup_migrated_checks.sh %q\n' "$SCRIPT_DIR"
}

_deferred_alerts_file="$(mktemp)"
for a in "${alerts[@]}"; do
    case "$a" in 先送りCRITICAL:*) printf '%s\n' "$a" >> "$_deferred_alerts_file" ;; esac
done
mkdir -p "$SCRIPT_DIR/queue/locks" "$(dirname "$STARTUP_ESCALATION_STATE")"
_deferred_lock="$SCRIPT_DIR/queue/locks/karo_startup_escalation.lock"
(
flock -x 9
_transition_output="$(python3 - "$STARTUP_ESCALATION_STATE" "$_deferred_alerts_file" "${KARO_STARTUP_ESCALATION_SUPPRESS_PATTERN:-}" "$KARO_STARTUP_ESCALATION_RESOLVE_GRACE_SEC" <<'PY'
import os, re, sys, tempfile
from datetime import datetime, timedelta
from pathlib import Path

state_path, alerts_path, suppress = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
resolve_grace_sec = max(0, int(sys.argv[4]))

def key_for(alert):
    key = re.sub(r'^先送りCRITICAL:\s*', '', alert.strip())
    key = re.sub(r'\s*が\s*\d+\s*セッション連続\s*$', '', key)
    # Rates/counts/session numbers vary between renderings but do not define the incident.
    key = re.sub(r'\d+(?:\.\d+)?(?:%|件|回|分|秒|セッション)', '#', key)
    key = re.sub(r'\s+', ' ', key).strip()
    return key

# Load dismissed keys from shogun's judgment ledger (fail-open: missing/unreadable → escalate normally)
dismissed_keys = set()
ledger_path = state_path.parent / 'shogun_escalation_decisions.tsv'
try:
    if ledger_path.exists():
        _now_dt = datetime.now().astimezone()
        for _line in ledger_path.read_text(encoding='utf-8').splitlines():
            _parts = _line.split('\t')
            if len(_parts) < 4:
                continue
            _lk, _ld, _lt, _le = _parts[0], _parts[1], _parts[2], _parts[3]
            if _ld == 'dismiss':
                _expiry_h = float(_le or '0')
                if _expiry_h == 0:
                    dismissed_keys.add(_lk)
                else:
                    try:
                        if _now_dt < datetime.fromisoformat(_lt) + timedelta(hours=_expiry_h):
                            dismissed_keys.add(_lk)
                    except ValueError:
                        pass
except (OSError, ValueError):
    pass  # fail-open: unreadable ledger → escalate normally

active = {}
for line in alerts_path.read_text(encoding='utf-8').splitlines():
    if line.strip(): active[key_for(line)] = line.strip()

rows = {}
if state_path.exists():
    for line in state_path.read_text(encoding='utf-8').splitlines():
        parts = line.split('\t')
        if len(parts) == 5:
            rows[parts[0]] = [int(parts[1]), parts[2], parts[3], parts[4]]

now_dt = datetime.now().astimezone()
now = now_dt.isoformat(timespec='seconds')
for key, row in list(rows.items()):
    if key not in active and row[1] == 'open':
        try:
            absent_long_enough = (
                now_dt - datetime.fromisoformat(row[3])
            ).total_seconds() >= resolve_grace_sec
        except ValueError:
            absent_long_enough = False
        if absent_long_enough:
            row[1], row[3] = 'resolved', now

for key, alert in active.items():
    suppressed = bool(suppress and re.search(suppress, key))
    if key not in rows:
        rows[key] = [1, 'suppressed' if suppressed else 'open', '0', now]
    elif rows[key][1] in ('resolved', 'suppressed') and not suppressed:
        rows[key] = [rows[key][0] + 1, 'open', '0', now]
    elif suppressed:
        rows[key][1], rows[key][3] = 'suppressed', now
    if rows[key][1] == 'open' and rows[key][2] == '0' and key not in dismissed_keys:
        rows[key][2], rows[key][3] = '1', now
        print(f'SEND\t{key}\t{rows[key][0]}\t{alert}')

state_path.parent.mkdir(parents=True, exist_ok=True)
fd, tmp = tempfile.mkstemp(prefix=state_path.name + '.', dir=state_path.parent)
with os.fdopen(fd, 'w', encoding='utf-8') as fh:
    for key in sorted(rows):
        generation, terminal, notified, updated = rows[key]
        fh.write(f'{key}\t{generation}\t{terminal}\t{notified}\t{updated}\n')
os.replace(tmp, state_path)
PY
 )"
while IFS=$'\t' read -r _action _key _generation _alert; do
    [ "$_action" = "SEND" ] || continue
    _correction_command="$(karo_startup_correction_command "$_alert")"
    _correction_output=""
    _correction_rc=0
    if [ -n "$_correction_command" ]; then
        _correction_output="$(cd "$SCRIPT_DIR" && bash -c "$_correction_command" 2>&1)" || _correction_rc=$?
    else
        _correction_rc=127
    fi
    # A successful Karo-lane correction closes the alert without escalating.
    # Only a measured non-zero correction is eligible for Shogun escalation.
    [ "$_correction_rc" -ne 0 ] || continue
    _correction_gap="${_correction_output//$'\n'/ }"
    _correction_gap="${_correction_gap:0:400}"
    [ -n "$_correction_gap" ] || _correction_gap="家老レーン是正コマンドが非0終了したが出力なし"
    _deferred_message="家老startup先送りCRITICAL案件: key=${_key} generation=${_generation}; ${_alert}。試行コマンド: ${_correction_command}; exit_code: ${_correction_rc}; 特定した不足: ${_correction_gap}; 次の行動: 是正結果を確認し既存cmdへ接続する; 実行者: karo"
    bash "$SCRIPT_DIR/scripts/inbox_write.sh" shogun "$_deferred_message" escalation karo 2>/dev/null || true
done <<< "$_transition_output"
) 9>"$_deferred_lock"
rm -f "$_deferred_alerts_file"
unset _deferred_alerts_file _deferred_lock _deferred_message _transition_output _action _key _generation _alert
