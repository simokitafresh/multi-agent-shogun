#!/bin/bash
# gate_gunshi_startup.sh — 軍師セッション起動時の全チェックを一括実行
# 目的: /clear後の状態復元に必要な6項目を一括チェック（知性の外部化原則）
# Usage: bash scripts/gates/gate_gunshi_startup.sh
# 参考: gate_karo_startup.sh（構造踏襲）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

overall="OK"
alerts=()

echo "=== 軍師起動チェック $(date '+%H:%M:%S') ==="
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
echo "  ★★★ レビュー開始前にdeepdiveを読め ★★★"
echo "  → memory/deepdive_why_chain_20260321.md"
echo "  Phase 4「LLMに生存本能はない→自動化×強制」"
echo "  Phase 5「なぜの目的=自動化ターゲット特定」"
echo ""

# --- Check 2: inbox未読件数 ---
echo "■ inbox未読"
inbox_file="$SCRIPT_DIR/queue/inbox/gunshi.yaml"
if [ -f "$inbox_file" ]; then
    unread=$(python3 -c "
import yaml
with open('$inbox_file') as f:
    data = yaml.safe_load(f)
msgs = data.get('messages', []) if data else []
print(sum(1 for m in msgs if not m.get('read', False)))
" 2>/dev/null || echo "0")
    echo "  未読: ${unread}件"
    if [ "$unread" -gt 0 ]; then
        echo "  → 未読メッセージあり。処理せよ"
    fi
else
    echo "  未読: 0件 (inbox不在)"
    unread=0
fi

# --- Check 3: レビューログ統計 ---
echo "■ レビューログ統計"
REVIEW_LOG="$SCRIPT_DIR/logs/gunshi_review_log.yaml"
if [ -f "$REVIEW_LOG" ]; then
    # ヘッダーから統計を抽出（索引層に統計が維持されている）
    log_stats=$(RLFILE="$REVIEW_LOG" python3 -c '
import os
filepath = os.environ["RLFILE"]
with open(filepath) as f:
    lines = f.readlines()

# Parse header comments for key stats
cumulative = ""
accuracy = ""
verdict_dist = ""
workaround_trend = ""

for line in lines[:20]:
    line = line.strip()
    if line.startswith("# 累計:"):
        cumulative = line[2:]
    elif line.startswith("# accuracy公式:"):
        accuracy = line[2:]
    elif line.startswith("# verdict分布:"):
        verdict_dist = line[2:]
    elif line.startswith("# workaround率推移:"):
        workaround_trend = line[2:]

print(f"{cumulative}|{accuracy}|{verdict_dist}|{workaround_trend}")
' 2>/dev/null || echo "|||")
    IFS='|' read -r LOG_CUMUL LOG_ACC LOG_VERDICT LOG_WA_TREND <<< "$log_stats"
    [ -n "$LOG_CUMUL" ] && echo "  $LOG_CUMUL"
    [ -n "$LOG_ACC" ] && echo "  $LOG_ACC"
    [ -n "$LOG_VERDICT" ] && echo "  $LOG_VERDICT"
    [ -n "$LOG_WA_TREND" ] && echo "  $LOG_WA_TREND"

    # 未処理GP(提案)件数
    pending_gp=$(RLFILE="$REVIEW_LOG" python3 -c '
import os, re
filepath = os.environ["RLFILE"]
with open(filepath) as f:
    lines = f.readlines()
count = 0
for line in lines:
    # GP追跡表ヘッダーのpendingエントリを数える
    if "| pending" in line and line.strip().startswith("# |"):
        count += 1
print(count)
' 2>/dev/null || echo "0")
    if [ "$pending_gp" -gt 0 ]; then
        echo "  未処理GP: ${pending_gp}件"
    fi
else
    echo "  ALERT: gunshi_review_log.yaml不在"
    overall="ALERT"
    alerts+=("レビューログ不在")
fi

# --- Check 4: karo_workarounds傾向（軍師の成績表） ---
echo "■ karo_workarounds傾向（成績表）"
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
        echo "  → Step 0 Workaround Pattern Checkで重点確認せよ"
    fi
else
    echo "  karo_workarounds.yaml不在"
fi

# --- Check 5: lessons_gunshi.yaml存在確認 ---
echo "■ レビュー教訓"
lessons_file="$SCRIPT_DIR/projects/infra/lessons_gunshi.yaml"
if [ -f "$lessons_file" ]; then
    lesson_count=$(python3 -c "
import yaml
with open('$lessons_file') as f:
    data = yaml.safe_load(f)
lessons = data.get('lessons', []) if data else []
print(len(lessons))
" 2>/dev/null || echo "0")
    echo "  OK: lessons_gunshi.yaml (${lesson_count}件)"
else
    echo "  WARN: lessons_gunshi.yaml不在"
    if [ "$overall" != "ALERT" ]; then
        overall="WARN"
        alerts+=("レビュー教訓不在")
    fi
fi

# --- Check 6: 直近レビュー(未GATE確認)件数 ---
echo "■ GATE未確認レビュー"
if [ -f "$REVIEW_LOG" ]; then
    ungated=$(RLFILE="$REVIEW_LOG" python3 -c '
import yaml, os
try:
    filepath = os.environ["RLFILE"]
    with open(filepath) as f:
        data = yaml.safe_load(f)
    if not isinstance(data, list):
        data = []
    count = 0
    for entry in data:
        if isinstance(entry, dict):
            gt = entry.get("gate_result")
            rt = entry.get("review_type", "")
            if gt is None and rt in ("draft", "report"):
                count += 1
    print(count)
except Exception:
    print(0)
' 2>/dev/null || echo "0")
    echo "  GATE結果未反映: ${ungated}件"
    if [ "$ungated" -gt 10 ]; then
        echo "  → review_feedback受信時にgate_resultを更新せよ"
    fi
else
    echo "  SKIP: レビューログ不在"
fi

# --- 総合判定 ---
echo ""
echo "=== 総合判定: $overall ==="
if [ ${#alerts[@]} -gt 0 ]; then
    for a in "${alerts[@]}"; do
        echo "  ⚠ $a"
    done
fi
echo ""
echo "■ 必読: memory/deepdive_why_chain_20260321.md（知性の外部化原則 全過程）"
echo "■ 必読: logs/gunshi_review_log.yaml（accuracy把握）"
echo "■ 必読: projects/infra/lessons_gunshi.yaml（レビュー教訓）"
