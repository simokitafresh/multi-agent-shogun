#!/bin/bash
# gate_karo_startup.sh — 家老セッション起動時の全チェックを一括実行
# 目的: 5項目を一括チェックし、deepdive必読を自動化×強制
# Usage: bash scripts/gates/gate_karo_startup.sh
# 参考: gate_shogun_startup.sh（構造踏襲）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

overall="OK"
alerts=()

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
echo ""
echo "  ★★★ inbox処理前にdeepdiveを読め ★★★"
echo "  → memory/deepdive_why_chain_20260321.md"
echo "  Phase 4「LLMに生存本能はない→自動化×強制」"
echo "  Phase 5「なぜの目的=自動化ターゲット特定」"
echo ""

# --- Check 2: 陣形図(karo_snapshot.txt)の鮮度 ---
echo "■ 陣形図鮮度"
snapshot="$SCRIPT_DIR/queue/karo_snapshot.txt"
if [ -f "$snapshot" ]; then
    snap_time=$(head -2 "$snapshot" | grep "Generated:" | sed 's/.*Generated: //')
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
stall_count=0
for ninja in hayate kagemaru hanzo saizo kotaro tobisaru; do
    pane_idx=$(tmux list-panes -t shogun:2 -F '#{pane_index} #{@agent_id}' 2>/dev/null | awk -v n="$ninja" '$2==n{print $1}')
    if [ -n "$pane_idx" ]; then
        ctx=$(tmux capture-pane -t "shogun:2.$pane_idx" -p 2>/dev/null | grep -oP 'CTX:\K[0-9]+%' | tail -1)
        task_status=$(awk '/^  status:/{print $2; exit}' "$SCRIPT_DIR/queue/tasks/${ninja}.yaml" 2>/dev/null)
        if [[ "$task_status" =~ ^(assigned|in_progress)$ && "$ctx" == "0%" ]]; then
            echo "  ⚠ $ninja: CTX=$ctx status=$task_status → STALL疑い"
            stall_count=$((stall_count + 1))
        else
            echo "  $ninja: CTX=${ctx:-?} status=${task_status:-?}"
        fi
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
inbox_file="$SCRIPT_DIR/queue/inbox/karo.yaml"
if [ -f "$inbox_file" ]; then
    unread=$(grep -c 'read: false' "$inbox_file" 2>/dev/null) || unread=0
    echo "  未読: ${unread}件"
else
    echo "  未読: 0件 (inbox不在)"
    unread=0
fi

# --- Check 4: pending_decisions未解決件数 ---
echo "■ pending_decisions"
pd_file="$SCRIPT_DIR/queue/pending_decisions.yaml"
if [ -f "$pd_file" ]; then
    total_d=$(grep -c '^\- id:' "$pd_file" 2>/dev/null) || total_d=0
    resolved_d=$(grep -c 'status: resolved' "$pd_file" 2>/dev/null) || resolved_d=0
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
    wa_result=$(awk '
    /^- (cmd_id|cmd|timestamp):/ {
        n++; wa[n]=0; cat[n]="uncategorized"; rc[n]=""
    }
    /^  workaround:/ {
        v=$2; if (v ~ /true|yes/) wa[n]=1
    }
    /^  category:/ {
        sub(/^  category: */, ""); gsub(/["'"'"']/, ""); cat[n]=$0
    }
    /^  root_cause:/ {
        sub(/^  root_cause: */, ""); gsub(/["'"'"']/, ""); rc[n]=substr($0,1,60)
    }
    END {
        s = (n > 5) ? n-4 : 1; total = n - s + 1
        wc=0; cat_str=""; cause_str=""
        for (i=s; i<=n; i++) {
            if (wa[i]) {
                wc++
                cats[cat[i]]++
                if (rc[i] != "") {
                    cause_str = cause_str (cause_str != "" ? " / " : "") rc[i]
                }
            }
        }
        for (c in cats) cat_str = cat_str (cat_str != "" ? ", " : "") c ":" cats[c]
        if (cat_str == "") cat_str = "none"
        if (cause_str == "") cause_str = "none"
        printf "%d|%d|%s|%s\n", wc, total, cat_str, cause_str
    }
    ' "$wa_file" 2>/dev/null || echo "0|0|error|awk error")
    IFS='|' read -r WA_COUNT WA_TOTAL WA_CATS WA_CAUSES <<< "$wa_result"
    echo "  直近${WA_TOTAL}件: workaround=${WA_COUNT}件"
    if [ "$WA_COUNT" -gt 0 ]; then
        echo "  カテゴリ: ${WA_CATS}"
        echo "  原因: ${WA_CAUSES}"
    fi
else
    echo "  karo_workarounds.yaml不在"
fi

# --- Check 6: 全体workaround率 (cmd_1308) ---
WA_RATE_SCRIPT="$SCRIPT_DIR/scripts/gates/gate_workaround_rate.sh"
if [ -x "$WA_RATE_SCRIPT" ]; then
    bash "$WA_RATE_SCRIPT" --last 10 2>&1 || echo "  [INFO] gate_workaround_rate.sh failed (non-blocking)"
else
    echo "■ Workaround率"
    echo "  SKIP: gate_workaround_rate.sh が存在しないか実行権限なし"
fi

# --- Check 7: 忍者別workaround率 (GP-011) ---
echo "■ 忍者別workaround率"
NINJA_WA_SCRIPT="$SCRIPT_DIR/scripts/gates/gate_ninja_workaround_rate.sh"
if [ -x "$NINJA_WA_SCRIPT" ]; then
    bash "$NINJA_WA_SCRIPT" --quiet --last 30
else
    echo "  SKIP: gate_ninja_workaround_rate.sh が存在しないか実行権限なし"
fi

# --- 総合判定 ---
echo ""
echo "=== 総合判定: $overall ==="
if [ ${#alerts[@]} -gt 0 ]; then
    for a in "${alerts[@]}"; do
        echo "  ⚠ $a"
    done
fi
