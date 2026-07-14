# 本番再計算の非決定性根治 — AS-IS / TO-BE 5W1H (v2.0 — ledger-bound freezeへ転換)

作成: 2026-07-11 将軍 | v1.1-v1.3.1: 軍師・家老・将軍メタレビュー反映 | **v2.0 (2026-07-14): 殿裁定による戦略転換**
源流: cmd_3827 FAIL → cmd_3840偵察設計 → P1-P3実装GREEN → P4複雑機構の性能不採用連鎖 → **SIGNAL CHANGE ALERT実事故(07-14) → 殿裁定「目的は保有シグナルの不変性」→ ledger-bound freeze採用**
正本設計書: DM-signal `docs/research/cmd_3840_nondeterminism_redesign.md` (v1.4.28) ※P4以降の重厚契約は本転換で退役

---

## 0. 時系列ナビゲーション（旧方式→問題→新版）

| 版 | 方式 | 何が起きたか |
|---|---|---|
| v1.0-v1.3.1 (07-11) | 単一経路化+入力manifest+P4本番決定性証明 | P1-P3は完成しGREEN。P4(本番1run証明)の前提となるwriter fence機構が**trigger 2案・ACL・GUC・RLSと4方式連続で性能/安全不採用**。bundle・keeper・restore契約と複雑機構が肥大化 |
| 転機 (07-14朝) | — | **本番でSIGNAL CHANGE ALERT実事故**: 23FoFの7月確定保有161行が日次cronで6月値へ誤巻き戻し。遡及調査は証跡消失で不能(restore-lockedが診断履歴まで復元) |
| **v2.0 (07-14)** | **ledger-bound freeze** | 殿裁定11:51「複雑な仕組みはすべて無駄。目的は過去の保有シグナルの不変性そのもの」。既存のappend-only ledger+既存reconcileを磨くだけの構造へ転換。実事故の真因も特定済み(下記) |

**一言でいうと**: 「同じデータで再計算してもシグナルが変わらない」を計算の決定性で証明する路線から、**「確定した保有はそもそも再計算で上書きできない」構造で保証する路線へ転換した**。前者は手段、後者が目的だった。

## 1. 実事故と真因（2026-07-14、本転換の決定打）

- **事象**: sync-fof日次cron(01:40 UTC)が23FoFの2026-07-01〜07-10 holding_signal 161行(23PF×7営業日)を上書き。SIGNAL CHANGE ALERTが発報
- **真因(本番実測で確定)**: 凍結機構は既に実装済みで**正しく発火していた**が、`recalculate_fast.py`のledger snapshot取得が**ORDER BYなし**+`signal_decision_ledger.py`のresolverが`applicable[-1]`を最新と仮定→順序非決定なsnapshotで**6月のeventが最新として選ばれ、7月確定値を6月確定値へ誤巻き戻し**。証跡: 変更前値=最新ledger(07-01)と161/161一致、変更後値=旧ledger(06-01)と161/161一致
- **即時対応**: cmd_3905で161行を7/1時点値へ復元完了(バックアップ+161/161 exact照合+ledger突合、家老独立再検証済み)
- **教訓**: 価格改定でも計算非決定性でもなく、**守りの器の選択バグ**。「すでに実装したものが効果を発揮していない」(殿)

## 2. AS-IS（現状 2026-07-14）

| 項目 | 現状 |
|---|---|
| 資産(有効) | P1a-P3a完成: full source identity・logical_date固定・immutable snapshot・strict manifest・共通pure executor(`execute_pipeline_semantics`がSSOT、旧`_compute_pipeline_signals`全廃)・shadow 2run exact・全量テストGREEN |
| ledger | `SignalDecisionLedger`=**append-only(UPDATE/DELETE拒否)**が稼働中。15,160行/102PF、2003-09-02〜2026-07-01被覆。reconcile処理もsignal_flush/monthly_returnsに実装済み |
| 被覆の穴 | 確定域signals 341,409行のうち**ledger未被覆478行/76PF(0.14%)がpass-through** |
| 選択の穴 | resolver最新event選択が順序非決定(上記真因)。**修正cmd_3907実装中** |
| 訂正経路 | 過去訂正の専用経路なし(**cmd_3908で新設**) |
| 退役済み | P4本番bundle/fence/keeper/restore契約(cmd_3902 canceled)・restore証跡artifact(cmd_3904 canceled)・trigger/ACL/GUC/RLS 4方式(反例履歴として保全、再採用禁止) |

## 3. TO-BE（あるべき姿 = ledger-bound freeze）

| 項目 | あるべき姿 |
|---|---|
| 原理(1行) | **保有シグナルの確定域はledgerが正。ledger欠落での確定域書込みはfail-closed** |
| 確定境界 | カレンダー月ではなく**ledger event有無をSSOT**とする |
| 選択の決定性 | 最新applicable event=(effective_start_date, recorded_at, id)明示ソートまたはmax選択。順序非依存 (cmd_3907) |
| 被覆100% | 未被覆478行はcutover時の現保有をbaseline eventとして一度だけ凍結。以後fail-closed (cmd_3909) |
| 変更の一本化 | 過去訂正はreason・actor必須のappend-only correction eventのみ。一般full rebuildでの確定域上書き手段は封鎖 (cmd_3908) |
| 可変なもの | signals.signal(生シグナル)・monthly_returns等の価格評価は再計算可。**不変なのはholding_signal=投資判断の記録のみ** |
| 新規PF/設定変更 | 過去はsimulation扱い。実保有のledger化は将来決定から |
| 決定性検証の位置づけ | P1-P3資産(共通executor+manifest)は維持。決定性試験は**未確定域・オフライン限定へ縮小・低優先化**。本番restore/fenceを不変性のために続けない |

## 4. 5W1H (v2.0)

| | 内容 |
|---|---|
| **Why** | 目的は過去の保有シグナルの不変性。計算の決定性証明は手段であり、確定域を再計算で触れない構造にすれば目的は直接達成される。実事故が「既実装の器+小さな選択バグ」という最短修正点を示した |
| **What** | freeze三段直列: cmd_3907(誤選択根治+fail-closed)→cmd_3908(correction event専用経路+他手段封鎖)→cmd_3909(478行baseline凍結→被覆100%) |
| **When** | 即時。3907は次回sync-fof cron(07-15 01:40 UTC)前のlive反映が期限 |
| **Where** | `recalculate_fast.py`(snapshot取得)・`signal_decision_ledger.py`(resolver)・本番signal_decision_ledger(baseline INSERT 478行のみ) |
| **Who** | 忍者直列(家老配備)。復元(3905)は完了済み |
| **How** | 新規trigger/artifact/複雑機構ゼロ。既存append-only ledger+既存reconcile 1箇所を磨く。二値基準=fullrecalc後ledger被覆holding 340,931+478行全量exact不変・未被覆確定書込reject・correction event以外の変更ゼロ |

## 5. 検証（3層）

1. **即時**: 復元161行の再照合(161/161 exact維持+12:17以降change 0件) — 家老実行中
2. **FE**: monthly tradeページで23FoFの7月保有が復元値と一致(DB→API→FE貫通)
3. **実弾**: cmd_3907 live反映後、**明日のsync-fof cron通過でSIGNAL CHANGE ALERT 0件** = 同じ再計算が走っても確定保有が動かないことの実証

## 6. これで何が変わるか（殿の体験）

- 確定した保有シグナルは**構造的に二度と変わらない**。adj価格がどれだけ遡及改定されても、計算にどんなバグが入っても、確定域はledgerが守る
- SIGNAL CHANGE ALERTは「correction event以外で確定域が動いた」ときだけ鳴る真の異常検知になる
- 原因調査・証跡保全・復元contract等の複雑な事後装置は原理的に不要(変わり得ないものに法医学はいらない)

## 7. 因果

`[[cmd_3827_FAIL]] -> [[P1-P3単一経路化GREEN]] -> [[P4 fence4方式連続不採用]] + [[SIGNAL_CHANGE_ALERT実事故07-14]] -> [[殿裁定_目的は保有不変性]] -> [[真因=ledger選択の順序非決定]] -> [[cmd_3905復元]] -> [[freeze三段: cmd_3907決定的選択 -> cmd_3908 correction経路 -> cmd_3909 baseline凍結]] -> [[確定域不変性の構造保証]]`

## 8. 改訂履歴

- v1.0 (2026-07-11 00:05): 初版
- v1.1 (2026-07-11 01:05): 軍師深層レビューA-H反映(immutable snapshot契約・manifest正本・P1-P4実装順)
- v1.2 (2026-07-11 01:45): 家老運用レビュー反映(書込み順序・standalone L5・cron見かけ成功・二値AC14本)
- v1.3.1 (2026-07-11 02:03): 将軍メタレビューM1-M8反映(P5回帰新設・殿裁定checkpoint・drift三段通知・第6caller被覆)
- **v2.0 (2026-07-14 13:30): 殿裁定による戦略転換。単一経路の決定性証明(P4/P5重厚契約)からledger-bound freeze(確定域の構造的不変性)へ。実事故真因(ledger選択の順序非決定)と復元完了を記録。P1-P3資産は維持、P4複雑機構は退役**
