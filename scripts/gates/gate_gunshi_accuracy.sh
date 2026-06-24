#!/usr/bin/env bash
# gate_gunshi_accuracy.sh — 軍師gate予測精度の公正計算
# 誰でもいつでも: bash scripts/gates/gate_gunshi_accuracy.sh
#
# 公正計算ルール(2026-06-24確立):
#   FAIL→BLOCK予測→家老修正→CLEAR = 正解(BLOCKを検出し家老が修正した)
#   LGTM→CLEAR予測→CLEAR = 正解
#   LGTM→WARN/BLOCK予測→CLEAR = 誤答(LGTMならCLEARであるべき)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REVIEW_LOG="${1:-$SCRIPT_DIR/logs/gunshi_review_log.yaml}"

if [ ! -f "$REVIEW_LOG" ]; then
    echo "ERROR: $REVIEW_LOG not found" >&2
    exit 1
fi

python3 - "$REVIEW_LOG" <<'PY'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# 先頭が "- cmd_id:" で始まる場合もパース可能にする
entries = [e for e in re.split(r"\n- cmd_id:|- cmd_id:", content) if e.strip()]
results = []
for e in entries:
    cmd_m = re.search(r"^[:\s]*(\S+)", e)
    pred_m = re.search(r"gate_prediction:\s*(\S+)", e)
    result_m = re.search(r"gate_result:\s*(\S+)", e)
    verdict_m = re.search(r"verdict:\s*(\S+)", e)
    if not (pred_m and result_m and result_m.group(1) != "null"):
        continue
    cmd = cmd_m.group(1) if cmd_m else "?"
    pred = pred_m.group(1)
    result = result_m.group(1)
    verdict = verdict_m.group(1) if verdict_m else "?"
    # 公正計算: FAIL→BLOCK→修正CLEAR = 正解
    if verdict == "FAIL" and pred == "BLOCK" and result == "CLEAR":
        correct = True
    else:
        correct = pred == result
    results.append({"cmd": cmd, "pred": pred, "result": result, "verdict": verdict, "correct": correct})

if not results:
    print("データなし")
    sys.exit(0)

c_all = sum(1 for r in results if r["correct"])
print(f"全体: {c_all}/{len(results)} ({c_all*100//len(results)}%)")

recent = results[-10:]
c_r = sum(1 for r in recent if r["correct"])
print(f"直近10: {c_r}/{len(recent)} ({c_r*100//len(recent)}%)")

print("\n直近10件詳細:")
for r in recent:
    m = "✓" if r["correct"] else "✗"
    print(f"  {m} verdict={r['verdict']:8s} pred={r['pred']:6s} result={r['result']:6s} {r['cmd'][:50]}")

# 偽陽性内訳
fp = [r for r in results if not r["correct"]]
if fp:
    print(f"\n偽陽性{len(fp)}件:")
    for r in fp:
        print(f"  verdict={r['verdict']:8s} pred={r['pred']:6s} result={r['result']:6s} {r['cmd'][:50]}")
PY
