# cmd_4092 テスト在庫sweep 第1弾 — 軍師確認checkpoint

作成: hayate / 2026-07-20  
対象: `tests/` 全在庫  
origin: [[殿裁定_S3二本立て開始_20260720_0005]] -> [[sweep第1弾cmd_4092]] -> [[軍師必須確認checkpoint]]

## §1 二値結論

削除候補は **0件**。削除は未実施。厳格な積集合 `30日FAIL実績なし AND test_necessity等の契約宣言なし AND 他テストとの重複被覆を一次証明` を満たす対象が0件だったため、未知を安全側へ倒した。

軍師確認前に削除しないというAC1の停止条件に従い、本書確定時点で作業を停止する。

## §2 機械抽出

一次入力:

| 入力 | 件数・hash |
|---|---|
| `docs/research/ci-test-elimination-inventory-20260719.csv` | 4,922 cases / 365 files / SHA-256 `c58c594239e6f1a28f9c24b37144f9234476b6029f3554deb7dccfc9c1e1260e` |
| `docs/research/ci-test-failure-attribution-20260719.csv` | 365 files。GitHub failed log 70/70、local receipt/output 110/110、30日test/workflow関連commit 1,203件から生成済み |
| 契約宣言 | `rg '^# test_necessity:' tests` をfile単位で除外 |
| 重複被覆 | 同一content SHA-256、Bats `@test` 名の跨file一致、参照production pathを機械比較 |

抽出段階:

| 段階 | 件数 | 判定 |
|---|---:|---|
| 全在庫 | 365 files / 4,922 cases | 全件対象。縮小なし |
| failed log帰属なし・30日変更なし | 59 files | 「FAIL0」ではなく追加検分集合。absenceをFAIL0へ読み替えない |
| file content完全一致 | 0組 | 完全重複なし |
| 跨fileで同じBats名 | 1組 | 名称`one`のみ。生成fixture内の一般名で、同一契約の一次証明にならず除外 |
| production pathを契約testと共有 | 1 file | `tests/unit/test_report_field_set_bc_validation.bats`。下記敵対比較で非重複と判定 |
| 三条件の厳格積集合 | **0 files / 0 cases** | 削除候補0 |

## §3 候補別 deletion_justification / 被覆根拠

確定候補が0件のため、削除対象別 `deletion_justification` は0/0件、fixture/helper削除も0件。

除外した唯一の近似候補:

| file | FAIL/契約入口 | 近似被覆 | 敵対比較 | 結論 |
|---|---|---|---|---|
| `tests/unit/test_report_field_set_bc_validation.bats` | failed log帰属なし・30日変更なし、file先頭の`test_necessity`宣言なし | `tests/unit/test_report_field_set_batch_throughput.bats`等も`report_field_set.sh`を実行 | 対象fileはstring/boolean/PASS/FAILの拒否、per-AC/per-item、正しいyes/no、空テンプレート許容の15境界を持つ。batch throughput契約は原子publish/terminal遷移が主で、入力型15境界の同一被覆ではない | 重複被覆なし。削除不可 |

## §4 軍師確認依頼の二値項目

- [ ] 母集団365 files / 4,922 casesを縮小していない
- [ ] `unknown_not_attributed`または失敗帰属なしをFAIL0へ誤変換していない
- [ ] 契約宣言付きtestを削除候補へ混入していない
- [ ] 近似候補のproduction path共有を意味的重複と誤認していない
- [ ] 候補0件につき、削除・fixture参照検査・全量after計測へ進まず再設計/追加証拠を要求する

## §5 次の状態

軍師が候補0件を承認した場合、AC2の削除実走は対象0件のため開始不能。軍師が具体的な重複被覆を一次証拠付きで指摘した場合のみ、確認済みリストを正本へ追記して削除実走へ進む。
