#!/usr/bin/env bash
# gate_gunshi_accuracy.sh — 軍師gate予測精度の公正計算
# 誰でもいつでも: bash scripts/gates/gate_gunshi_accuracy.sh
#
# 公正計算ルール(2026-08-01 v3):
#   RC/FAIL往復は修正過程であり、最終GATEとの比較母数に混ぜない。
#   cmd_idごとに最後のgate_prediction+gate_result付きentryのみを1件として計測する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REVIEW_LOG="${1:-$SCRIPT_DIR/logs/gunshi_review_log.yaml}"

if [ ! -f "$REVIEW_LOG" ]; then
    echo "ERROR: $REVIEW_LOG not found" >&2
    exit 1
fi

python3 - "$REVIEW_LOG" <<'PY'
import sys, yaml

with open(sys.argv[1]) as f:
    data = yaml.safe_load(f) or []
entries = data if isinstance(data, list) else data.get("reviews", [])
latest = {}
skipped = 0
for entry in entries:
    if not isinstance(entry, dict):
        skipped += 1; continue
    cmd = str(entry.get("cmd_id") or "").strip()
    pred = str(entry.get("gate_prediction") or "").strip()
    result = str(entry.get("gate_result") or "").strip()
    if not cmd or not pred or result not in {"CLEAR", "BLOCK", "WARN", "FAIL"}:
        skipped += 1; continue
    latest[cmd] = {"cmd": cmd, "pred": pred, "result": result,
                   "verdict": str(entry.get("verdict") or "?"),
                   "correct": pred == result}
results = list(latest.values())

if not results:
    print(f"データなし (skipped={skipped})")
    sys.exit(0)

c_all = sum(1 for r in results if r["correct"])
print(f"全体: {c_all}/{len(results)} ({c_all*100//len(results)}%) skipped={skipped}")

recent = results[-10:]
c_r = sum(1 for r in recent if r["correct"])
print(f"直近10: {c_r}/{len(recent)} ({c_r*100//len(recent)}%)")
print(f"RECENT_FINAL_CMD_ACCURACY={c_r*100//len(recent)} SAMPLE={len(recent)}")

print("\n直近10件詳細:")
for r in recent:
    m = "✓" if r["correct"] else "✗"
    print(f"  {m} verdict={r['verdict']:8s} pred={r['pred']:6s} result={r['result']:6s} {r['cmd'][:50]}")

# 最終cmd不一致内訳
fp = [r for r in results if not r["correct"]]
if fp:
    print(f"\n最終cmd不一致{len(fp)}件:")
    for r in fp:
        print(f"  verdict={r['verdict']:8s} pred={r['pred']:6s} result={r['result']:6s} {r['cmd'][:50]}")
PY
