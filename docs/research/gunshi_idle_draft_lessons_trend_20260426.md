# draft_lessons BLOCK率推移分析 (2026-04-26)

## メタデータ
- 分析者: 軍師(gunshi)
- 日付: 2026-04-26
- トリガー: idle Step 5 (前回分析のフォローアップ)

## §1 計測結果

| 指標 | 値 |
|------|-----|
| 対象期間 | cmd_2282以降(教訓リマインド実装後) |
| unique cmd数 | 32 |
| draft_lessons BLOCK影響cmd | 11 (34%) |
| Eventually CLEAR | 27 (84%) |

## §2 因果分析

draft_lessons BLOCK = 前cmdのBLOCK教訓が未記録のまま次cmdを保存しようとした。
34%が影響 = 将軍がBLOCK後に教訓登録(lesson_write_shogun.sh)を実行せずに次cmdに進んでいる。

因果鎖: BLOCK発生→将軍がcmd修正→CLEAR→次cmd着手→**教訓登録をスキップ**→次cmd保存時draft_lessons BLOCK→修正→再保存

## §3 複利の問い

- 32cmd × 34% × 平均2回再保存 = ~22回の余分なBLOCK→修正→再保存サイクル
- 各サイクル~2分 = 44分のCTX消費(殿の時間ではなく将軍のCTX)
- 10回cmd_save繰り返したら: 正の複利(教訓記録→次BLOCK防止) vs 負の複利(記録スキップ→毎回BLOCK)
- 現状は負の複利パターン(34%が毎回BLOCK)

## §4 結論

教訓リマインド(cmd_2282)は改善効果不十分。「リマインド」は意志依存(Phase 4)。
強制メカニズムの候補:
1. cmd_save.sh: CLEAR後にlesson_write_shogun.sh未実行なら次回保存をBLOCK → Level 4
2. 既にBLOCKしている(draft_lessons)が、将軍がBLOCK→修正→CLEAR→教訓なし→再BLOCKのループが回っている = BLOCKを教訓登録に直結させる仕組みが必要
