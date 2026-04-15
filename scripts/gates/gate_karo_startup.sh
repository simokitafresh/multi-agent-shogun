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
REQUIRED_READ2="$SCRIPT_DIR/memory/deepdive_karo_verification_20260405.md"
if [ -f "$REQUIRED_READ2" ]; then
    echo "  OK: $(basename "$REQUIRED_READ2") 存在確認"
else
    overall="ALERT"
    alerts+=("必読ファイル不在: memory/deepdive_karo_verification_20260405.md")
    echo "  ALERT: $REQUIRED_READ2 が存在しない"
fi
echo ""

# Phase逐次読込ガイド（全文一括禁止 — 2026-04-15殿指示）
echo "  ■ Phase逐次読込ガイド（全文一括Read禁止。1 Phaseずつ読み、自問してから次へ）"
for _ddfile in "$REQUIRED_READ" "$REQUIRED_READ2"; do
    [ -f "$_ddfile" ] || continue
    echo "  $(basename "$_ddfile"):"
    python3 -c "
import sys
lines = []
with open(sys.argv[1]) as f:
    for i, line in enumerate(f, 1):
        if line.startswith('## Phase'):
            lines.append((i, line.strip().replace('## ', '')))
    total = i
if lines:
    print(f'    前文: Read(offset=1, limit={lines[0][0]-2})')
for j, (start, title) in enumerate(lines):
    end = lines[j+1][0]-1 if j+1 < len(lines) else total
    limit = end - start + 1
    print(f'    {title}: Read(offset={start}, limit={limit})')
" "$_ddfile"
done
echo "  ★ 1 Phaseずつ Read(offset, limit) で読め。各Phase後に1行自問。全文一括禁止。"
echo ""

# --- Check 1.5: 追体験検証Q4 (前セッション出来事注入) ---
_prev_session_summary=$(python3 - "$SCRIPT_DIR/queue/lord_conversation.jsonl" 2>/dev/null <<'PY'
import sys, json
log_file = sys.argv[1]
summary = "(前セッション要約なし)"
try:
    with open(log_file, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                if entry.get("direction") == "session_summary":
                    s = entry.get("summary", "").strip()
                    if s:
                        summary = s
            except (json.JSONDecodeError, Exception):
                continue
except (FileNotFoundError, OSError):
    pass
print(summary)
PY
) || _prev_session_summary="(取得失敗)"
echo "■ 追体験検証Q4（CLAUDE.md Step 2.88 — 省略厳禁）"
echo "  Q4: deepdive_why_chain Phase NがPhase Mで覆された例を1つ挙げよ。なぜ覆されたか？（時系列×因果）"
echo "  [前セッション出来事] ${_prev_session_summary}"
echo "  ※ Q4は前セッションの出来事を手がかりに因果をたどれ。暗記したPhase例を貼るな。"
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
        if [[ "$task_status" =~ ^(assigned|in_progress)$ && ( "$ctx" == "0%" || -z "$ctx" ) ]]; then
            echo "  ⚠ $ninja: CTX=${ctx:-EMPTY} status=$task_status → STALL疑い"
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

# --- Check 3.5: 掲示板未確認 ---
echo "■ 掲示板未確認"
bulletin_file="$SCRIPT_DIR/queue/bulletin_board.yaml"
if [ -f "$bulletin_file" ]; then
    bulletin_result=$(python3 - "$bulletin_file" karo <<'PY'
import sys, yaml
path, agent = sys.argv[1:3]
with open(path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
entries = data.get("entries") or []
pending = []
for entry in entries:
    if not isinstance(entry, dict):
        continue
    rc = entry.get("requires_confirmation", False)
    if not rc:
        continue
    if isinstance(rc, list) and agent not in rc:
        continue
    if str(entry.get("status", "")).lower() == "closed":
        continue
    confirmed = entry.get("confirmed_by") or []
    if agent in confirmed:
        continue
    text = str(entry.get("content", "")).splitlines()
    head = text[0] if text else ""
    pending.append(f"{entry.get('id', '?')} by {entry.get('posted_by', '?')} — {head[:60]}")
print(len(pending))
for item in pending[:3]:
    print(item)
PY
)
    bulletin_count=$(printf '%s\n' "$bulletin_result" | head -1)
    if [ "${bulletin_count:-0}" -gt 0 ]; then
        echo "  WARN: 未確認掲示板 ${bulletin_count}件"
        printf '%s\n' "$bulletin_result" | tail -n +2 | sed 's/^/    /'
        if [ "$overall" != "ALERT" ]; then
            overall="WARN"
            alerts+=("掲示板未確認: ${bulletin_count}件")
        fi
    else
        echo "  未確認: 0件"
    fi
else
    echo "  掲示板なし"
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
    bash "$NINJA_WA_SCRIPT" --quiet --last 30 || echo "  [INFO] gate_ninja_workaround_rate.sh failed (non-blocking)"
else
    echo "  SKIP: gate_ninja_workaround_rate.sh が存在しないか実行権限なし"
fi

# --- Check 8: idle自走プロンプト ---
echo ""
echo "■ 自走チェック"
# 全忍者がidle or completedか確認
active_ninjas=0
for ninja in hayate kagemaru hanzo saizo kotaro tobisaru; do
    task_file="$SCRIPT_DIR/queue/tasks/${ninja}.yaml"
    if [ -f "$task_file" ]; then
        ninja_status=$(awk '/^  status:/{print $2; exit}' "$task_file" 2>/dev/null)
        if [[ "$ninja_status" =~ ^(assigned|acknowledged|in_progress)$ ]]; then
            active_ninjas=$((active_ninjas + 1))
        fi
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
    orphan_result=$(awk '
    /^  [^ ][^ ]*:[[:space:]]*$/ {
        if (cmd != "" && status == "pending" && has_da) {
            found++
            cmds = cmds (cmds != "" ? ", " : "") cmd
        }
        cmd = $0
        sub(/^  /, "", cmd)
        sub(/:.*/, "", cmd)
        status = ""
        has_da = 0
        next
    }
    /^    status:/ {
        s = $0
        sub(/.*status: */, "", s)
        gsub(/["'"'"']/, "", s)
        gsub(/ /, "", s)
        status = s
    }
    /^    delegated_at:/ {
        has_da = 1
    }
    END {
        if (cmd != "" && status == "pending" && has_da) {
            found++
            cmds = cmds (cmds != "" ? ", " : "") cmd
        }
        printf "%d|%s\n", found + 0, cmds
    }
    ' "$stk_file" 2>/dev/null || echo "0|")
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

# --- 総合判定 ---
echo ""
echo "=== 総合判定: $overall ==="
if [ ${#alerts[@]} -gt 0 ]; then
    for a in "${alerts[@]}"; do
        echo "  ⚠ $a"
    done
fi
