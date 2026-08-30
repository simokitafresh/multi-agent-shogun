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

GATE_METRICS="${GATE_METRICS_LOG:-$SCRIPT_DIR/logs/gate_metrics.log}"

python3 - "$REVIEW_LOG" "$GATE_METRICS" <<'PY'
import sys, yaml, os

# 最終GATE結果の正本=gate_metrics.log(cmd_complete_gateが書く)。
# review_logのgate_resultは初回BLOCK(receipt不備等のinfra BLOCK)のまま残ることがあり
# 最終CLEARを反映しない(2026-08-30 将軍一次確認: 直近"miss"4件が全て最終CLEAR)。
final_gate = {}
if len(sys.argv) > 2 and os.path.isfile(sys.argv[2]):
    with open(sys.argv[2], errors="replace") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 3 and parts[2] in {"CLEAR", "BLOCK"}:
                final_gate[parts[1].strip()] = parts[2]

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
    # 最終GATE(正本)で上書き: 初回infra BLOCK→最終CLEARを"miss"に数えない
    result = final_gate.get(cmd, result)
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
