# GP-193: T1違反予防(binary_checks no→gate_prediction BLOCK予告)

## 問題
cmd_1897とcmd_1900で2回のLGTM→BLOCK(T1違反)。
両方ともbinary_checks result:no → GP-128(verdict↔bc整合性)でgate機械的BLOCK。

軍師が忍者の成果物品質を正しく評価(LGTM)しても、
binary_checks result:noが存在するとgateが機械的にBLOCKする。
軍師がgate_prediction:BLOCKを付記しないと、家老が予期しないBLOCKに遭遇する。

## なぜなぜ5回
1. なぜLGTMを出した？→ 報告の品質は正しかった
2. なぜgate BLOCKを予測しなかった？→ SG7 gate_predictionにBLOCK予測を書かなかった
3. なぜ書かなかった？→ review_logヘッダにルールがあるが読み飛ばした
4. なぜ読み飛ばした？→ ヘッダ34行。毎回全行適用は意志依存
5. なぜ意志依存？→ **ヘッダルールを自動チェックに変換していない** (Phase 4)

## 修正
gate_gunshi_report_precheck.sh にSG-PRE9追加。
engine.pyでbinary_checks result:noを検出→precheck.shでWARN表示。

- 防御Level: 5 (事前コンテキスト提供)
- 実装: engine.py +15行、precheck.sh +11行
- テスト: result:no→WARN検出確認、result:yes→PASS確認

## 検証結果
```
■ SG-PRE9: T1違反予防(binary_checks no検出)
  ★★★ WARN: binary_checks result:no検出: AC1/commit
  → LGTM判定時はgate_prediction: BLOCK/WARN必須
  → GP-128: verdict PASS + result:no → gate機械的BLOCK
  → 見落とし実績: cmd_1897, cmd_1900 (T1違反2回)
```
