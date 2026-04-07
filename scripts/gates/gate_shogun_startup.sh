#!/bin/bash
# gate_shogun_startup.sh — 将軍セッション起動時の全チェックを一括実行
# 目的: 3つの個別gateを覚えて実行する「意志依存」を排除（知性の外部化原則 2026-03-21）
# Usage: bash scripts/gates/gate_shogun_startup.sh [--brief]
# --brief: session_start_inject用。一行サマリのみ出力

set -e

run_gate_shogun_startup() {
local SCRIPT_DIR="${SHOGUN_STARTUP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
local GATE_DIR="$SCRIPT_DIR/scripts/gates"
BRIEF=false
[ "${1:-}" = "--brief" ] && BRIEF=true

overall="OK"
alerts=()
# ダイジェスト用変数（殿裁定2026-03-24: grepフィルタで情報欠落→想像で埋める問題の根本修正）
_d_insights=0
_d_proposals=0
_d_inbox=0
_d_idle_trigger=""

$BRIEF || echo "=== 将軍起動チェック $(date '+%H:%M:%S') ==="
$BRIEF || echo ""

# --- Parallel launch: Gate 1, 12, 13 (独立サブスクリプト並列化 cmd_1516) ---
_TMP_G1=$(mktemp) _TMP_G12=$(mktemp) _TMP_G13=$(mktemp)
trap 'rm -f "$_TMP_G1" "$_TMP_G12" "$_TMP_G13"' EXIT
"$GATE_DIR/gate_shogun_memory.sh" > "$_TMP_G1" 2>&1 &
_PID_G1=$!
bash "$GATE_DIR/gate_loop_health.sh" > "$_TMP_G12" 2>&1 &
_PID_G12=$!
bash "$GATE_DIR/gate_lesson_health.sh" > "$_TMP_G13" 2>&1 &
_PID_G13=$!

# --- Gate 1: Memory健全度 (Step 2.5) ---
$BRIEF || echo "■ Memory健全度"
wait $_PID_G1 || true
result1=$(tail -1 "$_TMP_G1")
$BRIEF || echo "  $result1"
if echo "$result1" | grep -q "ALERT"; then
    overall="ALERT"
    alerts+=("Memory健全度: ALERT")
fi

# --- Gate 2: p̄鮮度 (Step 2.57) ---
$BRIEF || echo "■ p̄鮮度"
result2=$("$GATE_DIR/gate_p_average_freshness.sh" 2>&1 | tail -1)
$BRIEF || echo "  $result2"
if echo "$result2" | grep -q "ALERT\|WARN"; then
    if echo "$result2" | grep -q "ALERT"; then
        overall="ALERT"
        alerts+=("p̄鮮度: ALERT")
    elif [ "$overall" != "ALERT" ]; then
        overall="WARN"
        alerts+=("p̄鮮度: WARN")
    fi
fi

# --- Gate 3: cmd委任状態 (Step 2.6) ---
$BRIEF || echo "■ cmd委任状態"
result3=$("$GATE_DIR/gate_cmd_state.sh" 2>&1 | tail -1)
$BRIEF || echo "  $result3"
if echo "$result3" | grep -q "ALERT"; then
    overall="ALERT"
    alerts+=("cmd委任状態: ALERT")
fi

# --- Gate 4: 未読inbox ---
$BRIEF || echo "■ inbox未読"
inbox_file="$SCRIPT_DIR/queue/inbox/shogun.yaml"
if [ -f "$inbox_file" ]; then
    unread=$(grep -c 'read: false' "$inbox_file" 2>/dev/null) || unread=0
    _d_inbox=$unread
    $BRIEF || echo "  未読: ${unread}件"
    if [ "$unread" -gt 0 ] && [ "$overall" != "ALERT" ]; then
        overall="WARN"
        alerts+=("inbox未読: ${unread}件")
    fi
else
    $BRIEF || echo "  未読: 0件"
fi

# --- Gate 5: 陣形図鮮度 ---
$BRIEF || echo "■ 陣形図鮮度"
snapshot="$SCRIPT_DIR/queue/karo_snapshot.txt"
if [ -f "$snapshot" ]; then
    snap_time=$(head -2 "$snapshot" | grep "Generated:" | sed 's/.*Generated: //')
    $BRIEF || echo "  最終更新: $snap_time"
else
    $BRIEF || echo "  WARNING: karo_snapshot.txt不在"
    if [ "$overall" != "ALERT" ]; then
        overall="WARN"
        alerts+=("陣形図不在")
    fi
fi

# --- Gate 6: 必読ファイル存在チェック ---
REQUIRED_READ="$SCRIPT_DIR/memory/deepdive_why_chain_20260321.md"
$BRIEF || echo "■ 必読ファイル"
if [ -f "$REQUIRED_READ" ]; then
    $BRIEF || echo "  OK: $(basename "$REQUIRED_READ") 存在確認"
else
    overall="ALERT"
    alerts+=("必読ファイル不在: memory/deepdive_why_chain_20260321.md")
    $BRIEF || echo "  ALERT: $REQUIRED_READ が存在しない"
fi

# --- Gate 6.5: 追体験検証 (deepdive読了後の自問強制) ---
# 結論を知っていることが追体験を殺す(2026-04-07殿指摘)。
# 読んだだけでは不十分。各Phaseを今の自分に重ねて自問したかを検証する。
# gateは補助。追体験が主体。追体験が正しく動けば間違いは自然に避けられる。
$BRIEF || echo "■ 追体験検証（CLAUDE.md Step 2.56 — 省略厳禁）"
$BRIEF || echo "  deepdive読了後に以下3問に各1行で回答せよ。回答なしに作業開始するな。"
$BRIEF || echo "  Q1: Phase 3「考えて進む×無限ループ」— 今の自分は考えるだけで止まっていないか？止まっているなら何を確認すべきか？"
$BRIEF || echo "  Q2: 「行動→即確認」— 今の本番は正常か？前セッション以降に本番に入った変更は何か？その結果を確認したか？想像で答えるな。"
$BRIEF || echo "  Q3: 今クリアされても強くてニューゲームできるか？環境に埋め込まれていない学びはないか？"
$BRIEF || echo "  ※ 結論(自動化×強制が大事)を書くな。今の自分の具体的状況を書け。"
$BRIEF || echo "  ※ reason: 結論を知っていることが追体験を殺す。テキスト処理ではなく自己診断(2026-04-07殿指摘)"

# --- Gate 7: 前セッション裁定の知識還流チェック ---
LORD_INDEX="$SCRIPT_DIR/context/lord-conversation-index.md"
$BRIEF || echo "■ 前セッション裁定"
if [ -f "$LORD_INDEX" ]; then
    ruling_count=$(grep -c "^- " <(sed -n '/殿の直近裁定・方針/,/^## /p' "$LORD_INDEX") 2>/dev/null) || ruling_count=0
    if [ "$ruling_count" -gt 0 ]; then
        $BRIEF || echo "  前セッション裁定${ruling_count}件あり。projects/*.yamlへの反映を確認せよ"
    else
        $BRIEF || echo "  裁定なし"
    fi
else
    $BRIEF || echo "  lord-conversation-index.md不在"
fi

# --- Gate 8: 気づきキュー（自動アーカイブ付き） ---
INSIGHTS_FILE="$SCRIPT_DIR/queue/insights.yaml"
INSIGHTS_ARCHIVE="$SCRIPT_DIR/queue/archive/insights_archive.yaml"
$BRIEF || echo "■ 気づきキュー"
if [ -f "$INSIGHTS_FILE" ]; then
    # Auto-archive: done/monitoring/observation/deferred が合計5件以上なら自動アーカイブ
    # 高速パス: grepで先にarchivable件数チェック（閾値未満ならPythonスキップ）
    archivable_count=$(grep -cE 'status: (done|monitoring|observation|deferred)' "$INSIGHTS_FILE" 2>/dev/null) || archivable_count=0
    total_status=$(grep -cE 'status: ' "$INSIGHTS_FILE" 2>/dev/null) || total_status=0
    remaining_count=$((total_status - archivable_count))
    if [ "$archivable_count" -ge 5 ]; then
        # 閾値到達時のみテキストベースでアーカイブ実行（yaml.dump禁止準拠 cmd_training_L4_R7）
        # gawkでinsightsブロックをstatus別に分離→テキスト追記/書戻し
        _ins_tmp_archive=$(mktemp)
        _ins_tmp_remain=$(mktemp)
        _ins_counts=$(gawk -v arc_file="$_ins_tmp_archive" -v rem_file="$_ins_tmp_remain" '
        BEGIN { in_item=0; buf=""; status="" }
        /^insights:/ { next }
        /^- / {
            if (in_item && buf != "") { flush_item() }
            in_item=1; buf=$0; status=""; next
        }
        /^[^ -]/ {
            if (in_item && buf != "") { flush_item() }
            in_item=0; buf=""; next
        }
        in_item {
            buf = buf "\n" $0
            if (/^  status: /) { s=$0; sub(/^  status: /, "", s); status=s }
        }
        function flush_item() {
            if (status == "done" || status == "monitoring" || status == "observation" || status == "deferred") {
                print buf > arc_file; arc++
            } else {
                print buf > rem_file; rem++
            }
        }
        END {
            if (in_item && buf != "") { flush_item() }
            print arc+0, rem+0
        }
        ' "$INSIGHTS_FILE")
        read -r _ins_archived _ins_remaining <<< "$_ins_counts"
        # アーカイブ追記（既存ファイルの末尾に追記。ヘッダなければ追加）
        if [ -s "$_ins_tmp_archive" ]; then
            mkdir -p "$(dirname "$INSIGHTS_ARCHIVE")"
            if [ ! -f "$INSIGHTS_ARCHIVE" ] || [ ! -s "$INSIGHTS_ARCHIVE" ]; then
                echo "insights:" > "$INSIGHTS_ARCHIVE"
            fi
            cat "$_ins_tmp_archive" >> "$INSIGHTS_ARCHIVE"
        fi
        # メインファイル書戻し（残留分のみ）
        {
            echo "insights:"
            if [ -s "$_ins_tmp_remain" ]; then
                cat "$_ins_tmp_remain"
            fi
        } > "${INSIGHTS_FILE}.tmp" && mv "${INSIGHTS_FILE}.tmp" "$INSIGHTS_FILE"
        rm -f "$_ins_tmp_archive" "$_ins_tmp_remain"
        archive_result="ARCHIVED ${_ins_archived}件→insights_archive.yaml, 残${_ins_remaining}件"
    else
        archive_result="アーカイブ対象${archivable_count}件(閾値5未満), pending${remaining_count}件"
    fi
    $BRIEF || echo "  $archive_result"

    # Count pending (after potential archive)
    pending_count=$(grep -c "status: pending" "$INSIGHTS_FILE" 2>/dev/null) || pending_count=0
    _d_insights=$pending_count
    if [ "$pending_count" -gt 0 ]; then
        $BRIEF || echo "  未処理: ${pending_count}件（idle時に確認推奨）"
    else
        $BRIEF || echo "  未処理: 0件"
    fi
else
    $BRIEF || echo "  キューなし"
fi

# --- Gate 9: 将軍パフォーマンスフィードバック ---
$BRIEF || echo "■ 将軍パフォーマンスフィードバック"
DESIGN_QUALITY="$SCRIPT_DIR/logs/cmd_design_quality.yaml"
WORKAROUNDS_FILE="$SCRIPT_DIR/logs/karo_workarounds.yaml"
REWORK_PCT="N/A"
BLOCK_PCT="N/A"
WA_COUNT=0

# 9a: cmd設計品質 (直近10件)
if [ -f "$DESIGN_QUALITY" ]; then
    dq_result=$(awk '
/karo_rework:/ { rw[++n] = ($2 ~ /yes|true/) }
/gate_result:.*BLOCK/ { bl[n] = 1 }
END {
    start = (n > 10) ? n - 9 : 1
    total = n - start + 1
    rc = 0; bc = 0
    for (i = start; i <= n; i++) {
        if (rw[i]) rc++
        if (bl[i]) bc++
    }
    if (total == 0) print "N/A N/A"
    else printf "%d %d\n", int(rc*100/total), int(bc*100/total)
}
' "$DESIGN_QUALITY" 2>/dev/null || echo "N/A N/A")
    read -r REWORK_PCT BLOCK_PCT <<< "$dq_result"
    $BRIEF || echo "  直近10件: rework率=${REWORK_PCT}% blocker率=${BLOCK_PCT}%"
else
    $BRIEF || echo "  cmd_design_quality.yaml不在"
fi

# 9b: 家老workaround (直近5件)
if [ -f "$WORKAROUNDS_FILE" ]; then
    wa_result=$(awk '
/^- cmd_id:/ { n++; wa[n] = 0; cat[n] = "uncategorized" }
/^  workaround: true/ { wa[n] = 1 }
/^  category:/ { sub(/^  category: /, ""); cat[n] = $0 }
END {
    start = (n > 5) ? n - 4 : 1
    total = n - start + 1
    wc = 0
    for (i = start; i <= n; i++) {
        if (wa[i]) { wc++; cats[cat[i]]++ }
    }
    cat_str = ""
    for (c in cats) {
        if (cat_str != "") cat_str = cat_str ", "
        cat_str = cat_str c ":" cats[c]
    }
    if (cat_str == "") cat_str = "none"
    printf "%d %d %s\n", wc, total, cat_str
}
' "$WORKAROUNDS_FILE" 2>/dev/null || echo "0 0 error")
    read -r WA_COUNT WA_TOTAL WA_CATS <<< "$wa_result"
    $BRIEF || echo "  直近${WA_TOTAL}件: workaround=${WA_COUNT}件 (${WA_CATS})"
else
    $BRIEF || echo "  karo_workarounds.yaml不在"
fi

# --- Gate 10: idle自走トリガー ---
$BRIEF || echo "■ idle自走トリガー"
IDLE_TRIGGER="OFF"
if [ -f "$snapshot" ]; then
    # ninja行から稼働中cmd(in_progress/assigned/acknowledged)を数える
    active_cmds=$(grep "^ninja|" "$snapshot" | grep -cE "\|(in_progress|assigned|acknowledged)\|" || true)
    total_ninjas=$(grep -c "^ninja|" "$snapshot" || true)
    idle_or_done=$(grep "^ninja|" "$snapshot" | grep -cE "\|(idle|done)\|" || true)

    if [ "$active_cmds" -eq 0 ] && [ "$total_ninjas" -gt 0 ] && [ "$idle_or_done" -eq "$total_ninjas" ]; then
        IDLE_TRIGGER="ON"
        if ! $BRIEF; then
            echo "  全忍者idle・パイプライン空。idle時自己分析に入れ:"
            echo "  Step 1: insightsキュー消費 (queue/insights.yaml)"
            echo "  Step 2: karo_workarounds直近10件分析"
            echo "  Step 3: cmd_design_quality直近10件分析"
            echo "  Step 4: gunshi_review_log確認"
            echo "  Step 5: パターン発見→why-chain→アクション"
        fi
    else
        $BRIEF || echo "  稼働中cmd: ${active_cmds}件、idle忍者: ${idle_or_done}/${total_ninjas}"
    fi
else
    $BRIEF || echo "  karo_snapshot.txt不在 — 判定不可"
fi

# --- Gate 11: 未処理PROPOSAL (cmd_1256 + cmd_1261) ---
DASHBOARD="$SCRIPT_DIR/dashboard.md"
REVIEW_LOG="$SCRIPT_DIR/logs/gunshi_review_log.yaml"
dash_proposals=0
log_proposals=0

# 11a: ダッシュボードの[PROPOSAL]
if [ -f "$DASHBOARD" ]; then
    dash_proposals=$(grep -c '\[PROPOSAL\]' "$DASHBOARD" 2>/dev/null) || dash_proposals=0
fi

# 11a.5: dashboardで完了済みGP-IDを抽出→review_log pendingフィルタに使用
completed_gps=""
if [ -f "$DASHBOARD" ]; then
    completed_gps=$(grep '完了:.*GP-' "$DASHBOARD" | grep -oP 'GP-[0-9]+[a-z]*' | paste -sd '|' -)
fi

# 11b: gunshi_review_log.yamlのproposals status=pending (completed_gps除外)
pending_gp_ids=""
if [ -f "$REVIEW_LOG" ]; then
    raw_pending=$(awk '/^[[:space:]]*- id: GP-/{id=$NF} /^[[:space:]]*status: pending/{if(id!="") print id; id=""}' "$REVIEW_LOG" 2>/dev/null)
    if [ -n "$completed_gps" ] && [ -n "$raw_pending" ]; then
        filtered=$(echo "$raw_pending" | grep -vE "^($completed_gps)$")
    else
        filtered=$raw_pending
    fi
    pending_gp_ids=$(echo "$filtered" | grep -v '^$' | paste -sd, -)
    log_proposals=$(echo "$filtered" | grep -cv '^$') || log_proposals=0
fi

proposal_total=$((log_proposals))
_d_proposals=$proposal_total
if [ "$proposal_total" -gt 0 ]; then
    $BRIEF || echo "■ 未処理PROPOSAL"
    gp_list_suffix=""
    if [ -n "$pending_gp_ids" ]; then
        gp_list_suffix=" ($pending_gp_ids)"
    fi
    $BRIEF || echo "  WARN: 軍師未処理提案 ${proposal_total}件${gp_list_suffix} (dashboard:${dash_proposals} review_log:${log_proposals})"
    if [ "$overall" != "ALERT" ]; then
        overall="WARN"
        alerts+=("軍師未処理提案: ${proposal_total}件${gp_list_suffix}")
    fi
fi

# --- Gate 12: 三層学習ループ健全性 ---
$BRIEF || echo "■ 三層学習ループ"
if [ -f "$GATE_DIR/gate_loop_health.sh" ]; then
    wait $_PID_G12 || true
    loop_result=$(cat "$_TMP_G12")
    # Extract key metrics for brief summary
    loop_fires=$(echo "$loop_result" | grep "Total fires:" | grep -oP '\d+' || echo "0")
    loop_fail=$(echo "$loop_result" | grep "FAIL:" | head -1 | grep -oP '\d+' | head -1 || echo "0")
    loop_autofix=$(echo "$loop_result" | grep "AUTO-FIXED:" | grep -oP '\d+' || echo "0")
    loop_status=$(echo "$loop_result" | grep "Loop Status" -A1 | tail -1 | sed 's/^ *//')
    if $BRIEF; then
        : # brief output handled in summary below
    else
        echo "  gate発火: ${loop_fires}件, FAIL: ${loop_fail}件, AUTO-FIX: ${loop_autofix}件"
        echo "  $loop_status"
        # Show maturation recommendations if any
        echo "$loop_result" | grep -A20 "成熟提案" | grep "UPGRADE\|INVESTIGATE" | while IFS= read -r rec; do
            echo "  $rec"
        done
    fi
    if echo "$loop_status" | grep -q "WARNING"; then
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
            alerts+=("三層ループ: $loop_status")
        fi
    fi
else
    $BRIEF || echo "  gate_loop_health.sh不在"
fi

# --- Gate 13: 教訓健全度 (lesson_sort trigger) ---
$BRIEF || echo "■ 教訓健全度"
if [ -f "$GATE_DIR/gate_lesson_health.sh" ]; then
    wait $_PID_G13 || true
    lesson_result=$(tail -1 "$_TMP_G13")
    $BRIEF || echo "  $lesson_result"
    if echo "$lesson_result" | grep -q "ALERT"; then
        overall="ALERT"
        alerts+=("教訓健全度: ALERT → /lesson-sort実行せよ")
    elif echo "$lesson_result" | grep -q "WARN"; then
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
            alerts+=("教訓健全度: WARN")
        fi
    fi
else
    $BRIEF || echo "  gate_lesson_health.sh不在"
fi

# --- Gate 14: 軍師分析状態（知識循環チェック） ---
# 起源: cmd_1451事件 — 軍師OPT-6分析完了済みなのに将軍が偵察cmd重複起票
# 目的: 起動時に軍師の最新分析テーマを表示し、cmd起票前の情報基盤を整える
$BRIEF || echo "■ 軍師分析状態"
GUNSHI_CONTEXT_FILES=$(find "$SCRIPT_DIR/context" -name "gunshi-*.md" -type f 2>/dev/null)
if [ -n "$GUNSHI_CONTEXT_FILES" ]; then
    _gunshi_info=""
    while IFS= read -r gfile; do
        [ -z "$gfile" ] || [ ! -f "$gfile" ] && continue
        _g_title=$(head -5 "$gfile" | grep -m1 '^#' | sed 's/^# *//')
        _g_mtime=$(date -r "$gfile" '+%m-%d %H:%M' 2>/dev/null || echo "?")
        _gunshi_info="${_gunshi_info}  $(basename "$gfile") [${_g_mtime}] — ${_g_title}\n"
    done <<< "$GUNSHI_CONTEXT_FILES"
    if [ -n "$_gunshi_info" ]; then
        $BRIEF || echo -e "$_gunshi_info"
        $BRIEF || echo "  → cmd起票前にこれらを確認せよ（cmd_1451重複防止）"
    fi
else
    $BRIEF || echo "  軍師分析ファイルなし"
fi

# --- Gate 15: 進化検知（知識循環の上流検知） ---
# 起源: cmd_1451→なぜなぜ5段 — 失敗は検知するが進化(新能力・新出力)は検知しない
# 目的: context/に知識マップ(CLAUDE.md/MEMORY.md/instructions/config/dashboard)から
#        参照されていないファイルがあれば、進化シグナルとしてフラグ。知識循環を自動促進
# 高速版: 核心ファイルをcatして一括grepで判定(WSL2 /mnt/c でのfull-repo scan回避)
$BRIEF || echo "■ 進化検知（孤立context）"
_evo_orphans=""
_evo_count=0
# 知識マップの核心ファイルを結合（context/自体は含めない = 自己参照除外）
_KMAP_TMP=$(mktemp)
# MEMORY.mdはClaude homeにある（リポジトリ内ではない）
_MEMORY_MD="$HOME/.claude/projects/-mnt-c-tools-multi-agent-shogun/memory/MEMORY.md"
: > "$_KMAP_TMP"
_KMAP_MISSING=()
_append_kmap_source() {
    local _kmap_src="$1"
    if [ -f "$_kmap_src" ]; then
        cat "$_kmap_src" >> "$_KMAP_TMP"
    else
        _KMAP_MISSING+=("$(basename "$_kmap_src")")
    fi
}
_append_kmap_source "$SCRIPT_DIR/CLAUDE.md"
_append_kmap_source "$_MEMORY_MD"
for _kmap_src in "$SCRIPT_DIR"/instructions/*.md; do
    [ -f "$_kmap_src" ] || continue
    _append_kmap_source "$_kmap_src"
done
_append_kmap_source "$SCRIPT_DIR/config/projects.yaml"
_append_kmap_source "$SCRIPT_DIR/dashboard.md"
if [ ${#_KMAP_MISSING[@]} -gt 0 ]; then
    $BRIEF || echo "  INFO: 知識マップ参照元欠落: $(printf '%s, ' "${_KMAP_MISSING[@]}" | sed 's/, $//')"
fi
for cfile in "$SCRIPT_DIR"/context/*.md; do
    [ ! -f "$cfile" ] && continue
    _cbase=$(basename "$cfile")
    [ "$_cbase" = "README.md" ] && continue
    # 知識マップにファイル名の参照があるか？
    if ! grep -q "$_cbase" "$_KMAP_TMP" 2>/dev/null; then
        _c_title=$(head -5 "$cfile" | grep -m1 '^#' | sed 's/^# *//')
        _c_mtime=$(date -r "$cfile" '+%m-%d %H:%M' 2>/dev/null || echo "?")
        _c_author=$(cd "$SCRIPT_DIR" && git log -1 --format='%an' -- "context/$_cbase" 2>/dev/null || echo "?")
        _evo_orphans="${_evo_orphans}  ${_cbase} [${_c_mtime}] by ${_c_author} — ${_c_title}\n"
        _evo_count=$((_evo_count + 1))
    fi
done
rm -f "$_KMAP_TMP"
if [ "$_evo_count" -gt 0 ]; then
    $BRIEF || echo -e "$_evo_orphans"
    $BRIEF || echo "  → ${_evo_count}件: 知識マップ(CLAUDE.md/MEMORY.md/instructions/config)に未参照。進化シグナルか確認し統合せよ"
    if [ "$_evo_count" -ge 3 ]; then
        alerts+=("進化検知: context/に孤立ファイル${_evo_count}件")
        overall="ALERT"
    fi
else
    $BRIEF || echo "  孤立context/ファイルなし（知識マップ完全同期）"
fi

# --- Gate 16: AC注入検証（配備済みタスク vs cmdソース, cmd_1668） ---
# 起源: AC注入失敗WA 6件 — _overwrite_ac_from_cmdのネスト形式未対応/stale AC残留
# 目的: 起動時に稼働中タスクのACがcmdソースと一致するか検証。不一致時WARNING（BLOCK不要）
$BRIEF || echo "■ AC注入検証"
_ac16_warn_msgs=()
_ac16_checked=0
_AC16_STK="$SCRIPT_DIR/queue/shogun_to_karo.yaml"
_AC16_TDIR="$SCRIPT_DIR/queue/tasks"

if [ -d "$_AC16_TDIR" ] && [ -f "$_AC16_STK" ]; then
    for _ac16_tf in "$_AC16_TDIR"/*.yaml; do
        [ ! -f "$_ac16_tf" ] && continue
        _ac16_st=$(awk '/^  status:/{print $2; exit}' "$_ac16_tf")
        case "$_ac16_st" in
            assigned|acknowledged|in_progress) ;;
            *) continue ;;
        esac
        _ac16_pcmd=$(awk '/^  parent_cmd:/{print $2; exit}' "$_ac16_tf")
        [ -z "$_ac16_pcmd" ] && continue

        # Task YAML: AC IDs (sorted). [- ]* handles both "  - id:" and "    id:" formats
        _ac16_tids=$(awk '
            /^  acceptance_criteria:/ { f=1; next }
            f && /^  [a-zA-Z_]/ { exit }
            f && /^  [- ]*id: / { sub(/.*id: */, ""); gsub(/[" ]/, ""); if ($0!="") print }
        ' "$_ac16_tf" | sort)

        # STK: AC IDs from acceptance_criteria list (sorted)
        _ac16_cids=$(awk -v cmd="$_ac16_pcmd" '
            BEGIN { t="  "cmd":" }
            $0==t { c=1; next }
            c && /^  [a-zA-Z_]/ { exit }
            c && /^    acceptance_criteria:/ { a=1; next }
            a && /^    [a-zA-Z_]/ { exit }
            a && /^      [- ]*id: / { sub(/.*id: */, ""); gsub(/[" ]/, ""); if ($0!="") print }
        ' "$_AC16_STK" | sort)

        # Fallback: ac: nested format (AC1:, AC2: as keys)
        if [ -z "$_ac16_cids" ]; then
            _ac16_cids=$(awk -v cmd="$_ac16_pcmd" '
                BEGIN { t="  "cmd":" }
                $0==t { c=1; next }
                c && /^  [a-zA-Z_]/ { exit }
                c && /^    ac:$/ { a=1; next }
                a && /^    [a-zA-Z_]/ { exit }
                a && /^      AC[0-9]/ { sub(/:.*/, ""); gsub(/[[:space:]]/, ""); if ($0!="") print }
            ' "$_AC16_STK" | sort)
        fi

        [ -z "$_ac16_cids" ] && continue
        _ac16_checked=$((_ac16_checked + 1))
        _ac16_nn=$(basename "$_ac16_tf" .yaml)

        if [ "$_ac16_tids" != "$_ac16_cids" ]; then
            _ac16_tc=$(printf '%s\n' "$_ac16_tids" | awk 'NF{n++}END{print n+0}')
            _ac16_cc=$(printf '%s\n' "$_ac16_cids" | awk 'NF{n++}END{print n+0}')
            _ac16_tcsv=$(echo "$_ac16_tids" | paste -sd, -)
            _ac16_ccsv=$(echo "$_ac16_cids" | paste -sd, -)
            _ac16_warn_msgs+=("${_ac16_nn}(${_ac16_pcmd}): task=[${_ac16_tcsv}](${_ac16_tc}) cmd=[${_ac16_ccsv}](${_ac16_cc})")
        fi
    done

    if [ ${#_ac16_warn_msgs[@]} -gt 0 ]; then
        for _ac16_wm in "${_ac16_warn_msgs[@]}"; do
            $BRIEF || echo "  WARNING: AC不一致 — $_ac16_wm"
        done
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
        fi
        alerts+=("AC注入不一致: ${#_ac16_warn_msgs[@]}/${_ac16_checked}件")
    else
        $BRIEF || echo "  OK: 稼働中${_ac16_checked}件のAC整合確認"
    fi
else
    $BRIEF || echo "  SKIP: task/cmd不在"
fi

# --- Gate 17: scripts/未コミット変更チェック (cmd_1675) ---
# 起源: scripts/配下に未コミットの変更があると気付かずに消失するリスク
# 目的: 起動時にscripts/の変更をWARNして把握漏れを防止。変更なしなら無音通過
_scripts_dirty=$(cd "$SCRIPT_DIR" && git status --porcelain -- scripts/ 2>/dev/null) || _scripts_dirty=""
if [ -n "$_scripts_dirty" ]; then
    _sd_count=$(echo "$_scripts_dirty" | wc -l)
    $BRIEF || echo "■ scripts/未コミット変更"
    while IFS= read -r _sd_line; do
        [ -z "$_sd_line" ] && continue
        $BRIEF || echo "  WARN: $_sd_line"
    done <<< "$_scripts_dirty"
    if [ "$overall" != "ALERT" ]; then
        overall="WARN"
    fi
    alerts+=("scripts/未コミット変更: ${_sd_count}件")
fi

# --- 総合判定 ---
if $BRIEF; then
    # session_start_inject用: 一行サマリ
    PERF_BRIEF="rework:${REWORK_PCT}% workaround:${WA_COUNT}件 autofix:${loop_autofix:-0}件"
    _d_unpushed=$(cd "$SCRIPT_DIR" && git rev-list origin/main..HEAD --count 2>/dev/null || echo "?")
    _DIGEST="insights:${_d_insights} proposals:${_d_proposals} unpushed:${_d_unpushed}"
    if [ ${#alerts[@]} -gt 0 ]; then
        echo "startup_gate: ${overall} — $(IFS=', '; echo "${alerts[*]}") | ${_DIGEST} | idle_trigger:${IDLE_TRIGGER} | ${PERF_BRIEF} | 必読: memory/deepdive_why_chain_20260321.md"
    else
        echo "startup_gate: OK | ${_DIGEST} | idle_trigger:${IDLE_TRIGGER} | ${PERF_BRIEF} | 必読: memory/deepdive_why_chain_20260321.md"
    fi
else
    echo ""
    echo "=== 総合判定: $overall ==="
    if [ ${#alerts[@]} -gt 0 ]; then
        for a in "${alerts[@]}"; do
            echo "  ⚠ $a"
        done
    fi
    echo ""
    # ─── ダイジェスト: 全項目1行（grepフィルタ不要化。殿裁定2026-03-24） ───
    _d_unpushed=$(cd "$SCRIPT_DIR" && git rev-list origin/main..HEAD --count 2>/dev/null || echo "?")
    echo "■ DIGEST: inbox=${_d_inbox} insights=${_d_insights} proposals=${_d_proposals} unpushed=${_d_unpushed} idle_trigger=${IDLE_TRIGGER} judge=${overall}"
    echo ""
    echo "■ 必読: memory/deepdive_why_chain_20260321.md（知性の外部化原則 全過程）"

    # Step 6: ALERT項目をinsightsに自動保存（将軍の「後でやる」放置防止）
    if [ "$overall" = "ALERT" ] && [ ${#alerts[@]} -gt 0 ]; then
        for a in "${alerts[@]}"; do
            # 教訓健全度ALERTなど既知パターンのみ自動保存（ノイズ防止）
            case "$a" in
                *教訓健全度*|*三層ループ*|*軍師未処理*)
                    bash "$SCRIPT_DIR/scripts/insight_write.sh" "起動ALERT未対処: $a" 2>/dev/null || true
                    ;;
            esac
        done
    fi
fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" && "${SHOGUN_STARTUP_LIB_ONLY:-0}" != "1" ]]; then
    run_gate_shogun_startup "$@"
fi
