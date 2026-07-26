#!/usr/bin/env bash
# gate_gunshi_accuracy.sh — 軍師gate予測精度の公正計算
# 誰でもいつでも: bash scripts/gates/gate_gunshi_accuracy.sh
#
# 公正計算ルール(2026-06-24 v2 — 殿指示: 偽陽性はバグ):
#   FAIL→BLOCK予測→家老修正→CLEAR = 正解(BLOCKを検出し家老が修正した)
#   RC→BLOCK予測→忍者修正→CLEAR = 正解(RC指摘が反映された正常フロー)
#   LGTM→WARN予測→家老迅速処理→CLEAR = 正解(lesson_candidate有→家老処理=予測範囲内)
#   LGTM→CLEAR予測→CLEAR = 正解
#   LGTM→BLOCK予測→CLEAR = 誤答(LGTMならBLOCK予測は判定ミス)
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
skipped = 0
for e in entries:
    cmd_m = re.search(r"^[:\s]*(\S+)", e)
    pred_m = re.search(r"gate_prediction:\s*(\S+)", e)
    result_m = re.search(r"gate_result:\s*(\S+)", e)
    verdict_m = re.search(r"verdict:\s*(\S+)", e)
    # N/A = cmdがrevert等で終端し実GATEが存在しない墓標。予測の当否は評価不能なので
    # 分母から除外する(誤答計上=偽陽性=バグ。殿指示2026-06-24と同原理)
    if not (pred_m and result_m and result_m.group(1) in ("CLEAR", "BLOCK", "WARN", "FAIL")):
        skipped += 1  # 静かに落とさず明示カウント(将軍裁定): 内容は推測・捏造しない
        continue
    cmd = cmd_m.group(1) if cmd_m else "?"
    pred = pred_m.group(1)
    result = result_m.group(1)
    verdict_raw = verdict_m.group(1) if verdict_m else "?"
    # REQ_CHANGES はREQUEST_CHANGESの表記ゆれ(同義語彙)。LGTM/APPROVEは
    # review_type(report/draft)に束縛された別概念のため寄せない(軍師実測:
    # report×LGTM=28/28, draft×APPROVE=23/23, 交差0件)
    verdict = "REQUEST_CHANGES" if verdict_raw == "REQ_CHANGES" else verdict_raw
    # 公正計算: 軍師が問題を検出→修正→CLEARは正解
    if verdict == "FAIL" and pred == "BLOCK" and result == "CLEAR":
        correct = True  # FAIL検出→家老修正→CLEAR
    elif verdict == "REQUEST_CHANGES" and pred == "BLOCK" and result == "CLEAR":
        correct = True  # RC指摘→忍者修正→CLEAR
    elif verdict == "LGTM" and pred == "WARN" and result == "CLEAR":
        correct = True  # lesson_candidate有→家老迅速処理→CLEAR
    else:
        correct = pred == result
    results.append({"cmd": cmd, "pred": pred, "result": result, "verdict": verdict, "correct": correct})

if not results:
    print(f"データなし (skipped={skipped})")
    sys.exit(0)

c_all = sum(1 for r in results if r["correct"])
print(f"全体: {c_all}/{len(results)} ({c_all*100//len(results)}%) skipped={skipped}")

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
