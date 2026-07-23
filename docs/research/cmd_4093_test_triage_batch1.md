# cmd_4093 テスト在庫三層振り分け — 小batch第1弾

作成: hayate / 2026-07-20  
対象: cmd_4092抽出資産 365 files / 4,922 cases  
origin: [[殿裁定_二条件小batch+振り分け型_20260720]] -> [[三層振り分けcmd_4093]] -> [[軍師必須確認checkpoint]]

## §1 入力と鮮度照合

| 入力 | 一次証跡 |
|---|---|
| case台帳 | `docs/research/ci-test-elimination-inventory-20260719.csv`: 4,922 cases / 365 files / SHA-256 `c58c594239e6f1a28f9c24b37144f9234476b6029f3554deb7dccfc9c1e1260e` |
| FAIL台帳 | `docs/research/ci-test-failure-attribution-20260719.csv`: 365 files |
| 現行契約宣言 | 現HEADの `rg '^# test_necessity:' tests` をfile単位で照合 |
| 資産生成commit | FAIL台帳 `daa33e59d7f72705055140425a7ab79e3da05f07` (2026-07-19 01:57 JST) |

鮮度差分: 現HEADでは台帳365 files中284 filesが既に不存在、81 filesが現存する。これはcommit `36fe2add45abb8d7ceb18a128ee756ccc6a7ba1a` が333 test filesを削除し、その後一部が再追加された結果である。不存在284件を今回の削除実走対象へ混入させず、分類母集団からも落とさない。

## §2 三層全量分類

優先順位は `現行test_necessity宣言あり → 保全`、残りをFAIL台帳で二分した。これにより365/365 filesを分類し、母集団縮小0件とした。

| 層 | files | 判定・次処理 |
|---|---:|---|
| 宣言あり | 55 | 保全。削除候補へ入れない |
| 宣言なし ∧ FAIL実績なし | 290 | 削除資格層。ただし現存は26 files、不存在は264 files。今回の選定は現存26件のみ |
| 宣言なし ∧ FAIL実績あり | 20 | **昇格済み(cmd_4095完了)。移植済み3＋復元宣言17＝20/20。test_necessity宣言全件確認済み。2026-07-24** |
| 合計 | **365** | 55 + 290 + 20 = 365 |

cases母集団はfile分類に従属し4,922/4,922を維持する。`github_or_local_failed_log=no`は台帳上のFAIL実績なしとして本cmdの二条件判定に使用するが、意味的重複の証明とは扱わない。

## §3 小batch削除候補

候補は1 file / 5 cases。削除は軍師承認まで実施しない。

| file | cases / 台帳秒 | 二条件 | 被テスト対象の大改修証跡 | deletion_justification |
|---|---:|---|---|---|
| `tests/unit/test_gate_report_format_cmd_3558.bats` | 5 / 4.044秒 | `test_necessity`なし、FAIL帰属なし | 作成commit `2643ec628` 以後、`gate_report_format.sh` / `gate_report_format_main.py` / `gate_report_format_combined.py` に33 commits。元のcmd固有fixtureは旧report構造。現行 `tests/test_gate_report_format.bats` がshort/full commit_hash境界を `T-GP287-1/2` として保持 | 実装時に消費済みのcmd_3558固有test。主要commit_hash境界は現行統合testへ移行済みで、旧fixtureを永続保守する価値を消費済み。1 fileだけの可逆な小batchとして削除資格あり |

敵対確認: `tests/test_gate_report_format.bats` にshort hash拒否と40文字hash受理が存在する。一方、空pathの旧GP-288 WARN境界は現行統合testで同名一致を確認できないため、軍師はこの境界消滅を許容できるかを必ず判定すること。許容不可なら候補0件へ戻す。

## §4 昇格候補 → 昇格済み（cmd_4095完了 2026-07-24）

宣言なし∧FAIL実績あり20 filesは削除対象外。現HEADで全20 filesが不存在であるため、次弾ではFAIL台帳の20件を正本リストとして、(a)現行統合testに境界が移植済み、(b)復元して`test_necessity`宣言を付ける、の二択で1件ずつ処理する。今回の小batchへ混入0件。

**cmd_4095完了確認(2026-07-24 tobisaru)**: 移植済み3＋復元宣言17＝20/20。全17復元filesにtest_necessity宣言確認。宣言率: 123/187(現HEAD)。

## §5 軍師必須確認

- [x] 365 files / 4,922 casesの母集団縮小が0件
- [x] 宣言あり55件が削除資格層へ混入していない
- [x] FAIL実績あり20件が削除候補へ混入していない
- [x] 現HEAD不存在284件を今回の削除実走へ混入していない
- [x] `test_gate_report_format_cmd_3558.bats` の旧GP-288空path WARN境界を消滅させてもよい、または候補0件へ戻す

**承認証跡:** 軍師 `msg_20260720_005010_1353029_0448614d` と5/5 YES、同 `msg_20260720_005050_1361990_23f364e2` で候補1件を明示承認。

## §6 削除実走と計測

| 検査 | 結果 |
|---|---|
| 削除 | 承認済み `tests/unit/test_gate_report_format_cmd_3558.bats` 1 fileのみ |
| 非test参照 | `scripts/config/skills/instructions/projects/context` 対象rgで0 files。`scripts/lib/report_contract_test_selector.sh` の旧参照1件を同時除去 |
| before | receipt `run_tests_20260719T155045_1360372.json`: 1553/1553 PASS、SKIP 0、318.463秒 |
| after | receipt `run_tests_20260719T160117_1522662.json`: 1551/1551 PASS、SKIP 0、387.784秒 |
| 時間差 | +69.321秒。同時期のHEAD更新・他者test差分があり、小batchの短縮効果は未達/不確定。対象縮小なしで事実値を記録 |
| 削除競合 | commit直前 `git diff --name-status -- tests` で自分の削除1件以外の削除は0件。他者の変更差分には不触 |
| 昇格候補 | §4の20 filesを削除せず次弾入力として保存 |
