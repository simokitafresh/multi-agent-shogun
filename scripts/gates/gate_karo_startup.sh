#!/bin/bash
# gate_karo_startup.sh — 家老セッション起動時の全チェックを一括実行
# 目的: 5項目を一括チェックし、deepdive必読を自動化×強制
# Usage: bash scripts/gates/gate_karo_startup.sh
# 参考: gate_shogun_startup.sh（構造踏襲）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

overall="OK"
alerts=()

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

# === 高速化: バックグラウンド並列 + WA rateキャッシュ(300s TTL) ===
# cmd_2076: WA rate スクリプト結果を /tmp にキャッシュ (TTL 300秒)
# 前回(python3→awk+statusキャッシュ)との差分: WA rate結果自体をキャッシュ (異なる対象)
# cache hit時: ~2ms。cache miss時: 57ms+53ms (現行と同等)

_WA_RATE_TMP=$(mktemp)
_NINJA_WA_TMP=$(mktemp)
WA_RATE_SCRIPT="$SCRIPT_DIR/scripts/gates/gate_workaround_rate.sh"
NINJA_WA_SCRIPT="$SCRIPT_DIR/scripts/gates/gate_ninja_workaround_rate.sh"
_WA_RATE_CACHE="/tmp/karo_wa_rate_cache"
_NINJA_WA_CACHE="/tmp/karo_ninja_wa_cache"
_SKILL_SUMMARY_CACHE="/tmp/karo_skill_summary_cache"
_AGGREGATE_CACHE="/tmp/karo_startup_aggregate_cache"
_WA_CACHE_TTL=300
_SKILL_SUMMARY_CACHE_TTL=300

_now_epoch=$(date +%s)

# WA rate (cache hit or background refresh)
if [[ -f "$_WA_RATE_CACHE" ]] && (( _now_epoch - $(stat -c %Y "$_WA_RATE_CACHE" 2>/dev/null || echo 0) < _WA_CACHE_TTL )); then
    cp "$_WA_RATE_CACHE" "$_WA_RATE_TMP"
    _WA_RATE_PID=""
elif [ -x "$WA_RATE_SCRIPT" ]; then
    ( bash "$WA_RATE_SCRIPT" --last 10 2>&1 | tee "$_WA_RATE_TMP" > "$_WA_RATE_CACHE" ) &
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

# (B) tmux list-panes を1回だけ呼び出してキャッシュ
_PANE_MAP=$(tmux list-panes -t shogun:2 -F '#{pane_index} #{@agent_id}' 2>/dev/null || true)
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
for _agg_file in \
  "$SCRIPT_DIR"/queue/tasks/{hayate,kagemaru,hanzo,saizo,kotaro,tobisaru}.yaml \
  "$SCRIPT_DIR/queue/inbox/karo.yaml" \
  "$SCRIPT_DIR/logs/gunshi_review_log.yaml" \
  "$SCRIPT_DIR/queue/pending_decisions.yaml" \
  "$SCRIPT_DIR/logs/karo_workarounds.yaml" \
  "$SCRIPT_DIR/queue/shogun_to_karo.yaml"; do
    [[ -f "$_agg_file" ]] && _AGG_FILES+=("$_agg_file")
done
_AGG_SIG="$(stat -c '%Y:%s' "${_AGG_FILES[@]}" 2>/dev/null | tr '\n' ';' || true)"
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
        if (/read: false/) unread++
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
        if (/^- (cmd_id|cmd|timestamp):/) { n++; wa[n]=0; cat[n]="uncategorized"; rc[n]=""; next }
        if (/^  workaround:/) { v=$2; if (v ~ /true|yes/) wa[n]=1; next }
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
        if (cmd != "" && cmd_status == "pending" && has_da) {
            orphan_found++
            orphan_cmds = orphan_cmds (orphan_cmds != "" ? ", " : "") cmd
        }
        print "UNREAD|" unread+0
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
        GP) _gp_pending_count=${_agg_a:-0} ;;
        PD) total_d=${_agg_a:-0}; resolved_d=${_agg_b:-0} ;;
        WA) wa_result="${_agg_a}|${_agg_b}|${_agg_c}|${_agg_d}|${_agg_e}|${_agg_f}" ;;
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
for ninja in hayate kagemaru hanzo saizo kotaro tobisaru; do
    task_status=${_NINJA_STATUS_CACHE[$ninja]:-}
    pane_idx=${_PANE_IDX_BY_AGENT[$ninja]:-}
    _NINJA_PANE_IDX[$ninja]=$pane_idx
    if [[ "$task_status" =~ ^(assigned|in_progress)$ ]] && [ -n "$pane_idx" ]; then
        _tmpf=$(mktemp)
        _CTX_TMPF[$ninja]=$_tmpf
        (
            tmux capture-pane -t "shogun:2.$pane_idx" -p 2>/dev/null \
                | awk '
                    {
                        while (match($0, /CTX:[0-9]+%/)) {
                            ctx = substr($0, RSTART + 4, RLENGTH - 4)
                            $0 = substr($0, RSTART + RLENGTH)
                        }
                    }
                    END { if (ctx != "") print ctx }
                ' > "$_tmpf"
        ) &
        _CTX_PIDS+=($!)
    fi
done
for _pid in "${_CTX_PIDS[@]}"; do wait "$_pid" 2>/dev/null || true; done

stall_count=0
for ninja in hayate kagemaru hanzo saizo kotaro tobisaru; do
    task_status=${_NINJA_STATUS_CACHE[$ninja]:-}
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

# --- Check 5: karo_workarounds直近5件の傾向サマリ ---
echo "■ karo_workarounds傾向"
wa_file="$SCRIPT_DIR/logs/karo_workarounds.yaml"
if [ -f "$wa_file" ]; then
    wa_result=${wa_result:-"0|0|error|awk error|none|0"}
    IFS='|' read -r WA_COUNT WA_TOTAL WA_CATS WA_CAUSES WA_MAX_CAT WA_MAX_COUNT <<< "$wa_result"
    echo "  直近${WA_TOTAL}件: workaround=${WA_COUNT}件"
    if [ "$WA_COUNT" -gt 0 ]; then
        echo "  カテゴリ: ${WA_CATS}"
        echo "  原因: ${WA_CAUSES}"
        if [ "${WA_MAX_COUNT:-0}" -ge 3 ]; then
            echo "  ALERT: 同カテゴリ ${WA_MAX_CAT} が直近5件で ${WA_MAX_COUNT}件累積"
            overall="ALERT"
            alerts+=("workaround同カテゴリ累積: ${WA_MAX_CAT}=${WA_MAX_COUNT}")
        fi
    fi
else
    echo "  karo_workarounds.yaml不在"
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
for ninja in hayate kagemaru hanzo saizo kotaro tobisaru; do
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
rm -f "$_WA_RATE_TMP" "$_NINJA_WA_TMP" \
    "$_aggregate_tmp"

# --- Check 10: スキル品質サマリ ---
echo "■ スキル品質"
skill_summary_script="$SCRIPT_DIR/scripts/skill_execution_log.sh"
if [ -x "$skill_summary_script" ]; then
    _skill_cache_sig=""
    _skill_current_sig=""
    if [ -f "$SCRIPT_DIR/logs/skill_execution_log.yaml" ]; then
        _skill_current_sig="$(stat -c '%Y:%s' "$SCRIPT_DIR/logs/skill_execution_log.yaml" 2>/dev/null || echo '')"
    fi
    if [[ -f "$_SKILL_SUMMARY_CACHE" ]]; then
        IFS= read -r _skill_cache_sig < "$_SKILL_SUMMARY_CACHE" || _skill_cache_sig=""
    fi
    if [[ -f "$_SKILL_SUMMARY_CACHE" ]] \
        && [[ "$_skill_cache_sig" == "$_skill_current_sig" ]] \
        && (( _now_epoch - $(stat -c %Y "$_SKILL_SUMMARY_CACHE" 2>/dev/null || echo 0) < _SKILL_SUMMARY_CACHE_TTL )); then
        skill_summary="$(tail -n +2 "$_SKILL_SUMMARY_CACHE")"
    else
        skill_summary="$(
            SKILL_EXECUTION_LOG_FILE="$SCRIPT_DIR/logs/skill_execution_log.yaml" \
                bash "$skill_summary_script" summary 2>/dev/null || true
        )"
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
echo ""

# --- 総合判定 ---
echo ""
echo "=== 総合判定: $overall ==="
if [ ${#alerts[@]} -gt 0 ]; then
    for a in "${alerts[@]}"; do
        echo "  ⚠ $a"
    done
fi
