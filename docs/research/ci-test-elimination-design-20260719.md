# CIテスト淘汰・階層化偵察（実装前）

作成: saizo / 2026-07-19  
対象HEAD: `d34039c250edd6f322cc8029aaa6401cb00480bf`  
origin: [[cmd_karo_recon_ci_test_elimination_202607190143]] -> [[CI全件常時実行]] -> [[殿裁定_default_delete_test_20260719]] -> [[実装test即削除と宣言contract永続化]]

## §1 結論

現行の一次母集団は指示時点の4,740件ではなく、最新timing ledgerで **365 test files / 4,922 cases**。4,740との差は **+182** で、探索対象を縮小せず4,922件を分類した。全件台帳は `docs/research/ci-test-elimination-inventory-20260719.csv`（4,923行、header除外4,922、SHA-256 `c58c594239e6f1a28f9c24b37144f9234476b6029f3554deb7dccfc9c1e1260e`）。

最終方針は **実装testを作成→PASS確認→同一task内で即削除し、宣言付きcontractだけを永続化する default-delete**。旧 `削除0 / nightly降格4,435 / push維持487` は偵察時点の観測結果であり、現在推奨ではない。30日観察queue/nightlyを恒久運用にせず、永続test総量を増やさない。

## §2 一次データと算出方法

| 対象 | 一次データ | 実測 |
|---|---|---:|
| workflow | `.github/workflows/test.yml` | workflow 1、job 6（unit/build/shellcheck/e2e/codd/integration） |
| test files/cases | `logs/test_timing_ledger.tsv`, run `20260718T164341.1019233` | 365 files / 4,922 cases |
| full wall | `logs/test_suite_timing_ledger.tsv` 同run | wall 818.139s、sum-file 3,605.705s、PASS |
| receipt cross-check | `logs/test_receipts/run_tests_20260718T163008_1019205.json` | 4,909/4,909 PASS、SKIP0、818.422s |
| Actions 30日窓の取得可否 | `gh run list --workflow test.yml --limit 100` | 最新100 run: failure 70 / cancelled 26 / success 3 / blank 1 |

台帳の各caseには `defense_target`, `fail_30d`, `wall_sec_allocated`, `duplicate_contract`, `fixture_self_reference`, `deprecated_mechanism`, `classification`, `reason` を付与した。case wallは同一fileの実測wallをcase数で均等配賦。これはcase別timingが保存されない現行制約による推定で、file合計は実測と一致する。

30日FAILはrun単位では多数確認できる一方、caseへの完全帰属が不能なため全caseを `unknown_not_attributed` とした。この未知をFAIL0へ読み替えない。fixture自己参照はfile名および先頭4,000文字の `fixture/mock/legacy/deprecated/obsolete/scaffold` 検出、廃止済み機構は裏付け不足のため全件no、重複契約も敵対比較未完のためunknownとした。

## §3 旧方式の観測結果（最終方針ではない）

| 分類 | 二値条件 | 件数 | 推定sum-file wall |
|---|---|---:|---:|
| 削除 | 30日FAIL0 **かつ** 重複/fixture儀式のみ/廃止済みを一次証明 | 0 | 0s |
| nightly | push最小品質境界外。ただし削除条件未証明 | 4,435 | 3,209.960s |
| push維持 | report format / complete gate / D001-D009 / parity / exactly-once・atomic/idempotencyのcanonical filename集合 | 487 | 395.745s |

分類済み4,922 = 母集団4,922、未分類0。分類不能を削除へ送った件数0。`fail_30d=unknown` 4,922件はすべて維持またはnightlyへ残した。

## §4 旧階層化案の観測値（最終方針ではない）

| lane | trigger | 内容 | timeout | artifact | FAIL導線 |
|---|---|---|---:|---|---|
| push/PR | push(main), pull_request | `run_tests.sh affected <changed paths>` + 品質境界487件。affected重複は1回にdedup | 3分 | TAP + receipt JSON/output | required check RED、家老がCI fix忍者へ配備 |
| nightly | cron + workflow_dispatch | nightly 4,435件全件 | 30分 | file timing ledger + TAP + receipt | issue/掲示板へ失敗case、次pushのaffected集合へ昇格 |
| release | tag/release/workflow_dispatch | 4,922件full + build/shellcheck/e2e/codd/integration | 45分 | 全artifact、SKIP count、source SHA | release BLOCK、SKIP1以上もFAIL |

push最小集合のsum-file 395.745sを8並列の現行比率で換算すると約89.8s（`818.139 × 395.745 / 3605.705`）。checkout/install/artifact固定費を30-80s加えて **120-170s（2.0-2.8分）**。affected testsが品質境界外で追加される大変更は3分を超え得るため、3分はp50目標、hard timeoutは5分が安全。

## §5 削減数値とP2整合

| 指標 | 現行 | push案 | 差 |
|---|---:|---:|---:|
| case | 4,922 | 487 + affected | 最小時 -4,435（-90.1%） |
| suite wall | 818.139s | 89.8s純テスト推定 / 120-170s総wall | 純テスト -89.0%、総wall -79.2〜-85.3% |
| 削除 | — | 0 | 30日case帰属未証明のため削除なし |

P2の `1105s中必要158s、改善可能872s=78.9%` と、本案の総wall上限170sでは差12s、削減率差0.3pt（78.9%対79.2%）。ほぼ整合する。下限120sとの差38sは固定費見積幅と、P2の「必要作業」がテスト以外の報告処理も含むため。

なお、指示の4,740基準なら `0 + 4,253 nightly + 487 push` と帳尻を合わせられるが、現行182件を捨てるため採用禁止。現行正本4,922を採用した。

## §6 防御逆引きと空白判定

| 防御対象 | push維持の検索境界 | fallback |
|---|---|---|
| report format | `*report_format*`, `*report_field_set*` | nightly full |
| complete gate | `*cmd_complete*` | nightly full |
| D001-D009 | `*destructive*`, `*d00[1-9]*` | release full |
| 本番parity | `*parity*` | nightly full |
| exactly-once | `*exactly*`, `*idempot*`, `*atomic*` | nightly full |

列挙した全防御対象5/5にpush維持集合が存在し、fallbackも5/5にあるため、対象カテゴリ単位の防御空白は0。ただし個別caseと過去FAILの意味的逆引きは現行台帳に存在せず、削除判断に必要な証拠空白は4,922/4,922。このため推薦は「階層化は進める、物理削除はBLOCK」。

## §7 false-positive敵対測定

- 30日FAIL0判定FP: case帰属不能をFAIL0と誤判定しない実装にしたため、削除候補0/4,922、観測FP 0。ただし判定不能率100%であり削除精度の評価材料にはならない。
- 重複契約判定FP: 重複を自動推定せず全件unknownにしたため、削除へ誤送信0/4,922。重複検出recallは未測定。
- fixture語を含むだけで削除しない。fixture自己参照フラグは説明属性であり、分類条件単独には使用していない。

## §8 旧実装前checkpoint（殿裁定によりsuperseded）

旧二値判定は **階層化推薦=PASS、テスト削除推薦=BLOCK** だったが、これは最終方針ではない。現在は §11 の default-delete 契約を適用し、実装testのPASS直後削除を標準とする。

## §9 軍師FAIL後の30日FAIL帰属全走査

取得範囲をActions run一覧で止めず、GitHub failed log 70/70、local receipt JSON 110/110、local output 110/110、30日test/workflow関連commit 1,203件へ拡張した。file別正本は `docs/research/ci-test-failure-attribution-20260719.csv`（365 files、SHA-256 `fc15fd7ecd8c78380c21c8cd1e1b7f927ebb5ead7db2821c42c5e1dcd20cb7bf`）。

| 帰属集合 | files | cases | 扱い |
|---|---:|---:|---|
| GitHub/local failed logにfile名帰属 | 26 | inventoryで逆引き | 維持またはnightly。削除不可 |
| 30日git変更あり、failed log帰属なし | 306 | inventoryで逆引き | absenceをFAIL0とみなさずnightly |
| failed log帰属なし、30日git変更なし | 59 | inventoryで逆引き | **追加計測後の削除候補集合** |
| 即時削除可能 | 0 | 0 | case別実行分母と意味的重複/廃止証明が同時に揃う対象なし |

現行365 filesの完全同一content hash重複は0。廃止語を含み、かつfailed帰属/30日変更がない4 filesを精読したが、`test_cmd_save_q7_branch`はlegacy filenameだけ、`test_cmd_save_memory_ruling`は廃止workflowへの言及禁止契約、`test_lesson_merge`はdeprecation機能そのもの、`test_ntfy_ack`はremoved auto-ACKの非回帰境界だった。4/4とも廃止済みfixtureではなく現役防御で、即時削除集合へ入れない。

取得不能理由は、TAPが複数fileを連結しcase identityにsource fileを保持しないこと、Actions failed logは失敗したfile/caseしか列挙せず成功実行の分母をcase別30日台帳にしないこと、過去commitは変更事実であり実行成否ではないこと。このため59 filesは「FAIL0」ではなく「失敗帰属なし・変更なし」に限定する。

この二段階案は裁定前の経緯としてのみ保存する。30日nightly観察を最終方針にはせず、現在の実装判断は §11 の二値契約へ一本化する。

## §10 AC evidence mapping

| AC | 証拠 | 二値結果 |
|---|---|---|
| AC1 | timing run `20260718T164341.1019233`: 365 files / 4,922 cases、inventory 4,922/4,922 | yes |
| AC2 | case inventory 12属性、file attribution 365行、GitHub logs 70/70 + local receipt/output 110/110 + commits 1,203 | yes |
| AC3 | push487/nightly4,435/delete0、即時削除0・追加計測59 filesを分離 | yes |
| AC4 | §4 push/nightly/release trigger・timeout・artifact・FAIL導線、push120-170s | yes |
| AC5 | §5 case -90.1%、wall -79.2〜-85.3%、P2 78.9%との差0.3pt | yes |
| AC6 | §6 防御5/5、fallback5/5、空白0。帰属不能は削除せず59 files追加計測集合 | yes |
| AC7 | bulletin `blt_20260719_014828_534be0`、コード/workflow/test削除0 | yes |

## §11 最終default-delete契約

時系列ナビゲーション: **旧方式**=全test永続+push/nightly階層化 → **問題**=一時的な実装検証まで恒久資産化され、実行時間・保守対象・重複防御が増殖 → **最終方針**=実装testは作成→PASS→即削除、宣言付きcontractのみ永続。根拠は [[殿裁定_default_delete_test_20260719]]。

適用単位は1 taskのcommit直前checkpoint。下表はすべて入力・判定・BLOCK条件を持ち、7項目中1項目でも判定不能または不成立ならcommitをBLOCKする。

| ID | 二値仕様 | 入力 | PASS判定 | BLOCK条件 |
|---|---|---|---|---|
| 穴1 | 削除diff/contract混入0 | `git diff --name-status`、taskのtest paths、宣言contract paths | transient実装testが削除diffにあり、削除対象が宣言付きcontractに0件混入 | test削除diffなし、または宣言付きcontractが1件以上混入 |
| 穴2 | 宣言率30%超でtest-hygiene停止 | 変更test全件、各testの永続理由宣言数、宣言率=`宣言付き永続test/変更test` | 宣言率≤30%、または30%超を検知してcommit前に停止 | 宣言率>30%のまま停止せずcommitへ進む、分母/分子が取得不能 |
| 穴3 | 境界内回帰リスク受容とincident昇格 | 変更境界、既存contract、実装test PASS receipt、incident有無 | 境界内は一時test削除後の回帰リスクを明示受容し、実incident発生時だけ永続contract候補へ昇格 | 予測不安だけでtestを永続化、またはincident発生を昇格せず放置 |
| 穴4 | 既存test純減deletion_justification | HEAD前後のtracked test数、削除対象ごとの`deletion_justification` | tracked test数が純減し、全削除対象に重複/契約消滅/fixture廃止のいずれかを一次証拠付きで宣言 | 純減0以下、理由なし、理由とdiff不一致 |
| 穴5 | fixture/helper被参照0 | 削除対象fixture/helper symbol/path、production+test全scopeの参照検索 | 削除後の被参照件数=0 | 参照1件以上、検索scope欠落、動的参照が判定不能 |
| 穴6 | overlap時regression_justification免除 | 新旧testの防御contract ID、入力境界、期待結果 | 3項目が同一で完全overlapなら新testの`regression_justification`を免除し、一時testを削除 | overlap不完全なのに免除、または完全overlapなのに重複testを永続化 |
| 穴7 | commit直前race検知停止 | PASS receiptのsource SHA/test hash、現在のsource SHA/test hash、削除diff | 全hash一致かつ削除diff存在 | PASS後にsource/testが変化、hash取得不能、削除diff消失なら即停止して再test |

永続を許可する「宣言付きcontract」は、`contract_id`、守る本番不変量、入力境界、期待結果、owner、既存contractとの非重複根拠を持つものだけ。実装testのPASS receiptは証跡として報告へ残すが、test file自体は同一taskで削除する。例外追加は行わず、incident昇格も上記宣言を満たした場合だけ永続化する。
