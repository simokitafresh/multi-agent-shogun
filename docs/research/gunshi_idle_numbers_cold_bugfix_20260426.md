# Numbers Cold Streak根因: Adaptive Gating draft-only集計バグ

## 日時
2026-04-26T20:55:00+09:00 (gunshi idle自走)

## 事象
gate_gunshi_startup.sh Adaptive Gating: numbers zero_streak=7/10。
しかしfinding_categories実データでは直近10件中5件にnumbersを記録。

## 根因
gate_gunshi_startup.sh L232-233が `review_type == "draft"` のみでwindow構成。
report reviewのnumbers findingが集計対象外だった。

```python
# Before (bug)
drafts = [e for e in entries if e["review_type"] == "draft"]
window = drafts[-10:]

# After (fix)
reviews = [e for e in entries if e["review_type"] in ("draft", "report")]
window = reviews[-10:]
```

## 因果鎖
draft-only window → report entries除外 → numbersはreport(実測値検算)で多用 → 偽cold streak → 不必要なLOW confidence再点検 → 時間浪費 = 負の複利

## 影響範囲
- numbers: 1/10→5/10 (zero_streak=7→0) **偽cold streak解消**
- ambiguity: 2/10→3/10 (zero_streak=1→0)
- adversarial: 1/10→0/10 (zero_streak=8→10) reportにadversarial適用なし=正常挙動
- self_study/verify/consultationは除外のまま(CS観点カタログと異なるため)

## 検証
修正後gate実行で全観点の集計値がファイル実態と一致。

## 発見手法
idle Step 2(review_log傾向分析) → grep/tail実測 → gate出力との乖離発見 → gate script読解
