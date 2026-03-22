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

# --- Check 3: inbox未読件数 ---
echo "■ inbox未読"
inbox_file="$SCRIPT_DIR/queue/inbox/karo.yaml"
if [ -f "$inbox_file" ]; then
    unread=$(python3 -c "
import yaml
with open('$inbox_file') as f:
    data = yaml.safe_load(f)
msgs = data.get('messages', []) if data else []
print(sum(1 for m in msgs if not m.get('read', False)))
" 2>/dev/null || echo "0")
    echo "  未読: ${unread}件"
else
    echo "  未読: 0件 (inbox不在)"
    unread=0
fi

# --- Check 4: pending_decisions未解決件数 ---
echo "■ pending_decisions"
pd_file="$SCRIPT_DIR/queue/pending_decisions.yaml"
if [ -f "$pd_file" ]; then
    pending_count=$(python3 -c "
import yaml
with open('$pd_file') as f:
    data = yaml.safe_load(f)
decisions = data.get('decisions', []) if data else []
print(sum(1 for d in decisions if d.get('status') != 'resolved'))
" 2>/dev/null || echo "0")
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
    wa_result=$(WAFILE="$wa_file" python3 -c '
import yaml, re, os
filepath = os.environ["WAFILE"]
items = []
try:
    with open(filepath) as f:
        data = yaml.safe_load(f)
    items = data.get("workarounds", []) if data else []
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
            val = val.strip().strip("\"").strip("'"'"'")
            if key == "workaround":
                current["workaround"] = val.lower() in ("true", "yes")
            elif key == "category":
                current["category"] = val
            elif key == "root_cause":
                current["root_cause"] = val
    if current is not None:
        items.append(current)
try:
    last5 = items[-5:] if len(items) >= 5 else items
    total = len(last5)
    wa_count = sum(1 for i in last5 if i.get("workaround", False))
    cats = {}
    for i in last5:
        if i.get("workaround", False):
            cat = i.get("category", "uncategorized")
            cats[cat] = cats.get(cat, 0) + 1
    parts = [f"{k}:{v}" for k, v in sorted(cats.items(), key=lambda x: -x[1])]
    cat_str = ", ".join(parts) if parts else "none"
    causes = []
    for i in last5:
        if i.get("workaround", False):
            rc = i.get("root_cause", "")
            if rc:
                causes.append(rc[:60])
    cause_str = " / ".join(causes) if causes else "none"
    print(f"{wa_count}|{total}|{cat_str}|{cause_str}")
except Exception as e:
    print(f"0|0|error|{e}")
' 2>/dev/null || echo "0|0|error|python error")
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
