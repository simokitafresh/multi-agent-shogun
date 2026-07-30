# 進化量レポート — 速度と品質の因果を実測で示す(2026-07-29〜07-30) v4.0

origin: [[殿指示_進化量gist共有_20260726]] + [[殿指示_覚醒アップデート_20260730_0909]]
period: 2026-07-29 〜 2026-07-30 09:10(全面改稿版 v4.0。旧版v3.0=07-27〜29期はgit履歴に保存)
すべて一次実測。台帳=logs/defense_overhead.jsonl / gate_metrics.log / test_receipts / 報告YAML / 掲示板証跡
**主題: 速度向上は目的ではなく手段。全ての速度改善が「品質向上にどんな効果を出したか」を各節末尾の→効果で明示する。**

## §0 この期間の要約 — 数字で3行

- **第五弾=完全CLOSE**(全10弾GATE CLEAR: 9採用+1正直no-change)+**wave-final全量2,800/2,800 PASS**が第七弾の序列SSOTを兼務(4識別子exact結合 receipt1/per-file183集合差0)。**第七弾=1日で全10レーンCLEAR**(殿発案07-29 22:06→翌07:00台に本体完了)。
- **DM-Signal fullrecalculate第1回チャレンジ終了**: run全体877.25→477.59-499.33s(**約-45%**)・mr_gen 318.99→16.99s(**18.8x**)・値exact完全一致78PF/243,293行。本番live=クリーン。
- **全量checkpoint契約が実バグ2種を捕捉**: 個別focusedでは全PASSだった(a)deploy_task.sh固定tmp共有のmv競合race(baseline 46% FAIL→BASHPID一意化0% FAILの総当たり実証で根治)、(b)テストの実行bit契約不一致。3世代のFAILは全てfail-close正直終端で、偽CLEARゼロ。

## §1 個別最適化 — テスト実行時間(第七弾TOP10、focused実測)

| # | 対象testファイル | Δ(focused) | 真因と是正 |
|---|------|-----|------|
| 3 | heavy_job_admission | wall median 74.9→59.3s(**-20.8%**) | 固定時間待機→event条件置換 |
| 10 | ninja_monitor_stall | 36.4→30.4s(**-16.5%**) | 同型 |
| 2 | deploy_task_ac_handling | median 76.6→64.1s(**-16.3%**) | fixture/setup税 |
| 5 | cmd_complete_gate | 73.4→中央値51.2s | focused固定待ち除去 |
| 6 | report_field_set_batch | 30秒reconciler実待機→契約値30の敵対oracle付きrelease barrier | 実待機の構造置換 |
| 7 | run_tests(runner自己) | 最大test平均12.2→8.9s | 固定sleep→count barrier |
| 1 | inbox_write | 最大寄与fixture局所9.7→4.9s | 10件逐次配送→同時配送 |
| 8 | deploy_task_lifecycle | 39.2→35.7s(-9.1%) | 同型 |
| 9 | campaign_lane_shard_item | 41.56→41.02s(**効果僅少を正直計上**) | setup git clone→COWコピー |
| 4 | deploy_task | 53/53 PASS(是正採用) | ※この変更が§3aのraceの引き金となり根治へ接続 |

**→品質への効果**: 全10弾が検査数・oracle・副作用境界を不変のまま達成(削るな速くしろの運用形)。総括の確定値は全量checkpoint(gen4)で確定する — **個別Δの総和を効果として宣言しない**規律を維持。

## §2 全体最適化 — 序列SSOTの機械化と第六弾identity基盤

- **弾#0 run_identity計装**: receipt+per-file/per-suite ledgerへ4識別子(run_id/commit_sha/source_fingerprint/output_sha256)を追加し、**序列SSOTを「人が集計する」から「機械がexact結合する」へ**。wave-finalで実証(receipt=1/per-file=183/per-suite=1、集合差0)。
- **schema移行事故と受理**: 初回移行が旧ledger 20,731/1,637行を置換。才蔵が候補8,518ファイル全数走査し**復元行0=復元不能を確定**→将軍が喪失受理、飛猿の再発防止hotfix(publish前snapshot hash+行数一致+復元dry-run強制)を即日稼働。第六弾への依存は全数照合で**0件**を確認し、影響を数値で閉じた。
- **第六弾identity 4連鎖**: 飛猿偵察の正直FAIL(finalize後半phase coverage 0/5・generation意味不一致をcallsite全数表で確定)→3 hotfix連鎖CLEAR(**canonical generation=review.report_fingerprintへ単一定義統一**、cmd_complete→dashboard伝播、affected 315/315 PASS)。P1b(最大標的finalize 27,985s)の機械再開条件が判定可能な状態に到達。

**→品質への効果**: 「誰が数えたかで結果が決まる」問題を、書式(4規律)に続き**データ構造(4識別子exact結合)**で封じた。事故は起きたが、全数走査→受理→構造防止→影響照合の4手で「隠さず・引きずらず」閉じた。

## §3 高速回転による構造問題の露出と根治(速度→発見量→品質)

### 3a. 全量checkpointが3世代で実バグ2種を捕捉・根治
gen1/gen2(test7合成FAIL)→独立2系統・相互参照禁止の偵察(Track A=子process動的同定/Track B=総当たりN=140)で真因確定: **deploy_task.sh両writerが同一ninja名固定.tmpを共有しmv競合**(baseline 23/50 FAIL=46%→BASHPID一意化0/50=0%)。時系列切り分け(lane4前0/18・後4/18)でrunner側は非因果と証明。gen3では別根因(テストの-x前提とgit mode 100644の契約不一致)を新たに露出。**focused単独PASSの総和では絶対に見えないバグが、全量契約でのみ2種検出された** — 検査を削らない設計の配当。

### 3b. 検知器の粒度是正(レビュー品質WARN率)
家老エスカレーション「WARN率36%・対処不能」を将軍一次集計で分解: FAILの主成分は設計書レビューの**正当なRC**(v1.1→v1.4でLGTM到達=レビューが機能した証拠)だった。cmd_4194で母集団分離を実装し、検知器は実装品質のみを指す計器へ(分離2件を実出力で検分)。LS096「発火結果の分散が0なら検知粒度を疑え」の適用。

### 3c. 受領証偽PASSの根治(セッション基盤)
deepdive追体験受領証が前セッションmarkerで「今セッション完了」と偽表示される構造バグを将軍Q6自己監査で検出→真因=SessionStartペイロードの`source`キー未対応で/clear時にmarker未更新→D0修正+偽clear注入で検証(commit 43f0715e5)。**防御機構自体のバグを、防御機構(Q6)が検出した**入れ子の実例。

### 3d. CI RED 2回を即日解消
85commit一括pushで露出した合成不整合(弾#0×test期待値)を忍者ci_fixで46分収束。push保留デッドロック(LS101)も再発せず — GA-PUSH1(push対象と作業ツリーの重複検出)が2度正当BLOCKし、他者WIPの巻き込みを構造的に防いだ。

**→品質への効果**: 3a/3cは「検出器の出力も未検証の主張」を実践で貫いた実例。3bは誤警報が将軍の介入を空費させる構造を計器側で根治した。

## §4 組織の進化(検証の分散の深化)

- **正直FAILの連鎖が最速経路だった**: checkpoint 3世代FAIL・飛猿identity偵察FAIL・疾風レーンFAILの全てが偽装なきfail-close終端で、各FAILが次の真因を1段ずつ確定させた(LS089の型)。FAIL→偵察→根治→再実行の1周が約1時間で回っている。
- **read-only冗長2名(殿裁定13:28)が真因確定を1発で決めた**: race偵察は独立2系統・相互参照禁止で統合され、実装は単独所有で即配備。役割分担の型が機能。
- **家老の自走が終端契約の穴を即日検出**: --yaml直接配備の速度とspec未登録の詰まり(race同期含む)を家老自身がURGENT-HARMで即報告し、将軍の正規登録(1本ずつゲート通過・迂回ゼロ)で解消。gate regexバグ(cmd_id数値限定)等の副検出3件はinsight在庫化しreflux消費路へ。
- **殿の裁定が振り子を止めた**: 将軍のpromotion v1.2可逆自走を殿が「指示があるまで待機」で覆し、「可逆性より殿の明示的保留指定が優先する」判断則が三層記憶へ刻まれた。優先集中(第五〜第七弾)の裁定下で全忍者idle=0の陣形が実現。

## §5 現在地と次

- 第五弾: ✅**CLOSED**(正本v1.7=gist 5259aa640)。
- 第七弾: 全10レーンCLEAR。総括checkpoint=gen3のFAIL根因(実行bit契約)hotfix中→**gen4で総短縮確定→CLOSE**(正本v1.7=gist ce66d67c)。
- 第六弾: identity基盤完成。次手=coverage再実測(0/5→N/5)→P1b機械再開条件の充足判定→P1b read-only集計(正本v2.0=gist 89b0a0ad)。
- fullrecalc: 第1回終了(-45%)。再開入口=設計書v3.5.1 §0.-3(gist 78e88d24)。
- promotion v1.2: 殿裁定により指示があるまで待機(在庫415件はT1材料としてキュー保持)。

## 因果リンク
- [[hot-script高速化設計書]] 第一〜五弾+第七弾(様式・計測の憲法) / [[弾スループット全体ボトルネック改善]] part1-part2 / [[殿裁定_第七弾本体裁可_20260730]] / [[弾0_schema移行]]→[[旧台帳完全復元不能]]→[[L1461]] / [[第七弾全レーンCLEAR_20260730]] / defense_overhead.jsonl / gate_metrics.log / logs/test_receipts
