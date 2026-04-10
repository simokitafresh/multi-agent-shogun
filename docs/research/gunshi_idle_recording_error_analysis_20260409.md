# recording_error分析 — karo_workarounds WA品質
<!-- gunshi idle自走 2026-04-09 -->

## 結論
recording_error 6件/920行(0.65%)。直近10件中0件。**収束傾向**。gate_wa_data_quality.sh(GP-049)+yaml.dump除去(cmd_karo_fix_wa_yaml_dump)でデータ品質は改善済み。追加対策のROI低。

## 6件の内訳

| cmd_id | 日付 | ninja | 分類 | 根因 |
|--------|------|-------|------|------|
| cmd_1409 | 2026-03-26 | kotaro | **誤分類** | detail有り（binary_check修正）だがcategory=recording_error。実質はbinary_check修正 |
| cmd_1449 | 2026-03-28 | false | 完全欠損 | karo_workaround_log.sh引数quoting。ninja_id=false |
| cmd_1456 | 2026-03-28 | false | 完全欠損 | 同上 |
| cmd_1457 | 2026-03-28 | false | 完全欠損 | 同上 |
| cmd_1671 | 2026-04-01 | hayate | 呼出し構文エラー | 家老のbash呼出し引数不正 |
| cmd_1774 | 2026-04-07 | hanzo | 呼出し構文エラー | 家老のbash呼出し引数不正 |

## 因果推論
家老がkaro_workaround_log.shを手動呼出し→引数のquoting不足→ninja_id/detailが空→validate_ninja_idはWARN止まり(exit しない)→不正エントリが書き込まれる。

## 対策評価
- 3/28の3件は集中発生後にgate_wa_data_quality.sh(GP-049)で検出できるようになった
- 直近のcmd_1774以降(04-07〜04-09)は0件
- validate_ninja_idのWARN→BLOCKは可能だが、家老の手動呼出しをBLOCKすると緊急WA記録を阻害するリスク
- ROI: 低頻度(0.65%)+収束傾向→追加gate投資のROI不足

## 判断
**監視継続**。3件連続(LG014閾値)なら家老にGP提案。現時点は行動不要。
