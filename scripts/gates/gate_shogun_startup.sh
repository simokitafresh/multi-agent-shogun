#!/bin/bash
# gate_shogun_startup.sh — 将軍セッション起動時の全チェックを一括実行
# 目的: 3つの個別gateを覚えて実行する「意志依存」を排除（知性の外部化原則 2026-03-21）
# Usage: bash scripts/gates/gate_shogun_startup.sh [--brief]
# --brief: session_start_inject用。一行サマリのみ出力

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE_DIR="$SCRIPT_DIR/scripts/gates"
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

# --- Gate 1: Memory健全度 (Step 2.5) ---
$BRIEF || echo "■ Memory健全度"
result1=$("$GATE_DIR/gate_shogun_memory.sh" 2>&1 | tail -1)
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
    unread=$(python3 -c "
import yaml
with open('$inbox_file') as f:
    data = yaml.safe_load(f)
msgs = data.get('messages', []) if data else []
print(sum(1 for m in msgs if not m.get('read', False)))
" 2>/dev/null || echo "0")
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
    archive_result=$(IFILE="$INSIGHTS_FILE" AFILE="$INSIGHTS_ARCHIVE" python3 -c '
import yaml, os
ifile = os.environ["IFILE"]
afile = os.environ["AFILE"]
with open(ifile) as f:
    data = yaml.safe_load(f) or {}
items = data.get("insights", [])
archivable_statuses = {"done", "monitoring", "observation", "deferred"}
archivable = [i for i in items if i.get("status") in archivable_statuses]
remaining = [i for i in items if i.get("status") not in archivable_statuses]
if len(archivable) >= 5:
    if os.path.exists(afile):
        with open(afile) as f:
            archive_data = yaml.safe_load(f) or {}
    else:
        archive_data = {}
    archive_list = archive_data.get("insights", [])
    archive_list.extend(archivable)
    archive_data["insights"] = archive_list
    with open(afile, "w") as f:
        yaml.dump(archive_data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    data["insights"] = remaining
    with open(ifile, "w") as f:
        yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    print(f"ARCHIVED {len(archivable)}件→insights_archive.yaml, 残{len(remaining)}件")
else:
    print(f"アーカイブ対象{len(archivable)}件(閾値5未満), pending{len(remaining)}件")
' 2>/dev/null || echo "ERROR: アーカイブ処理失敗")
    $BRIEF || echo "  $archive_result"

    # Count pending (after potential archive)
    pending_count=$(python3 -c "
import yaml
with open('$INSIGHTS_FILE') as f:
    data = yaml.safe_load(f) or {}
items = data.get('insights', [])
print(sum(1 for i in items if i.get('status') == 'pending'))
" 2>/dev/null || echo "0")
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
    dq_result=$(DQFILE="$DESIGN_QUALITY" python3 -c '
import yaml, os
try:
    filepath = os.environ["DQFILE"]
    with open(filepath) as f:
        data = yaml.safe_load(f) or {}
    entries = data.get("entries", [])
    last10 = entries[-10:] if len(entries) >= 10 else entries
    total = len(last10)
    if total == 0:
        print("N/A N/A")
    else:
        rework = sum(1 for e in last10 if str(e.get("karo_rework", "no")).lower() in ("yes", "true"))
        block = sum(1 for e in last10 if e.get("gate_result") == "BLOCK")
        print(f"{int(rework*100/total)} {int(block*100/total)}")
except Exception:
    print("N/A N/A")
' 2>/dev/null || echo "N/A N/A")
    read -r REWORK_PCT BLOCK_PCT <<< "$dq_result"
    $BRIEF || echo "  直近10件: rework率=${REWORK_PCT}% blocker率=${BLOCK_PCT}%"
else
    $BRIEF || echo "  cmd_design_quality.yaml不在"
fi

# 9b: 家老workaround (直近5件)
if [ -f "$WORKAROUNDS_FILE" ]; then
    wa_result=$(WAFILE="$WORKAROUNDS_FILE" python3 -c '
import yaml, re, os
try:
    filepath = os.environ["WAFILE"]
    items = []
    try:
        with open(filepath) as f:
            data = yaml.safe_load(f)
        items = data.get("workarounds", [])
    except yaml.YAMLError:
        with open(filepath) as f:
            lines = f.readlines()
        current = None
        for line in lines:
            s = line.rstrip()
            if re.match(r"^- cmd:", s):
                if current is not None:
                    items.append(current)
                current = {}
            elif current is not None and s.startswith("  ") and ":" in s and not s.strip().startswith("- "):
                key, _, val = s.strip().partition(":")
                key = key.strip()
                val = val.strip()
                if key == "workaround":
                    current["workaround"] = val.lower() in ("true", "yes")
                elif key == "category":
                    current["category"] = val
        if current is not None:
            items.append(current)
    last5 = items[-5:] if len(items) >= 5 else items
    wa_count = sum(1 for i in last5 if i.get("workaround", False))
    cats = {}
    for i in last5:
        if i.get("workaround", False):
            cat = i.get("category", "uncategorized")
            cats[cat] = cats.get(cat, 0) + 1
    parts = [f"{k}:{v}" for k, v in sorted(cats.items(), key=lambda x: -x[1])]
    cat_str = ", ".join(parts) if parts else "none"
    print(f"{wa_count} {len(last5)} {cat_str}")
except Exception:
    print("0 0 error")
' 2>/dev/null || echo "0 0 error")
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

# 11b: gunshi_review_log.yamlのproposals status=pending
if [ -f "$REVIEW_LOG" ]; then
    log_proposals=$(RLFILE="$REVIEW_LOG" python3 -c '
import yaml, os
try:
    filepath = os.environ["RLFILE"]
    with open(filepath) as f:
        data = yaml.safe_load(f)
    if not isinstance(data, list):
        data = []
    count = 0
    for entry in data:
        proposals = entry.get("proposals", [])
        if proposals:
            for p in proposals:
                if isinstance(p, dict) and p.get("status") == "pending":
                    count = count + 1
    print(count)
except Exception:
    print(0)
' 2>/dev/null || echo "0")
fi

proposal_total=$((dash_proposals + log_proposals))
_d_proposals=$proposal_total
if [ "$proposal_total" -gt 0 ]; then
    $BRIEF || echo "■ 未処理PROPOSAL"
    $BRIEF || echo "  WARN: 軍師未処理提案 ${proposal_total}件 (dashboard:${dash_proposals} review_log:${log_proposals})"
    if [ "$overall" != "ALERT" ]; then
        overall="WARN"
        alerts+=("軍師未処理提案: ${proposal_total}件")
    fi
fi

# --- Gate 12: 三層学習ループ健全性 ---
$BRIEF || echo "■ 三層学習ループ"
if [ -f "$GATE_DIR/gate_loop_health.sh" ]; then
    loop_result=$(bash "$GATE_DIR/gate_loop_health.sh" 2>&1 || true)
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
    lesson_result=$(bash "$GATE_DIR/gate_lesson_health.sh" 2>&1 | tail -1)
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
fi
