# 本番再計算の非決定性根治 — AS-IS / TO-BE 5W1H (v2.3.2 — 本体CLOSED+運用追補収束: 反復真因実測特定・rootfix本番実証済み)

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

## 6.5 実装完了状況（v2.2 CLOSED、2026-07-15 17:15確定）

**freeze三段の実装は全段本番到達済み**（殿指示07-15 00:28「3907、3908、3909をやろう」から約3.5時間）:

| 段 | cmd | 状態 | 一次証跡 |
|---|---|---|---|
| 第1弾 決定的選択+fail-closed | cmd_3907 | ✅ GATE CLEAR | commit 3fe227e9、全量pytest 2010 PASS・FAIL0・SKIP0（露払い=FoF golden CI fix含む） |
| 第2弾 correction event専用経路 | cmd_3908 | ✅ GATE CLEAR | commit e0279aa0、focused 32/32+全量2010/2010、他手段封鎖テスト固定 |
| 第3弾 baseline凍結 | cmd_3909→**cmd_3947へ置換** | ✅ GATE CLEAR | 前提数値478行が第1・2弾効果+cron進行で52行に縮み失効→**述語導出型**（実行時点の未被覆全行を不変量から機械導出、LS-A09(37)適用）で再起票。本番実行: **被覆341,799/341,799=100%**・既存ledger不変・全量pytest 2017 PASS・FAIL0・SKIP0、DM-Signal commit 317b8c1e9 |

- 本番PF数の一次確認済み（殿の指摘07-15 03:02を受けlauncher readonly実測）: **portfolios=102、全102PFがledger event保有**。第3弾の「52行/52PF」は行レベルの残未被覆であり、PF漏れではない
- §5検証1(復元161行維持)・2(FE貫通)は完了済み。ALERT穴（新規INSERT drift非検知）修正も05a45d83でmain到達済み

**クローズ条件（全達成 → CLOSED）**:
1. ✅ cmd_3947 GATE CLEAR完了
2. ✅ §5検証3=**07-15 10:40 JST（01:40 UTC）sync-fof cron通過でsignal_change_log=0件・ledger被覆100%未被覆0件を将軍が本番DB一次確認**——「同じ再計算が走っても確定保有が動かない」ことの実弾実証が完了

## 9. CLOSED後の運用実績と残穴（v2.3追補、2026-08-02 12:45）

freeze三段(v2.2 CLOSED)は以後も**確定域を一度も破らせていない**。一方で運用の中で「守りの器」ではなく「通知の分類」と「FoF階層の消費側」に残穴が露出した。

### 9.1 実績（構造は守り切っている）

| 日付 | 事象 | ledgerの挙動 |
|---|---|---|
| 07-16〜 | 日次sync-fof cron継続 | 確定域holding_signalの実変更なし |
| 08-01 | **FoF月次11717行消失事故**(L3 StatementTooComplex→cleanup後書込み失敗)。monthly_returns系の消失であり確定保有は対象外 | 同日中に完全復旧(chunk化+SourceSelectGuard根治 00949558+バックアップ復元+8月78行生成+precompute 102/102+cron再開)。**holding_signal確定域は不変** |
| 08-02 | SIGNAL CHANGE ALERT 21PF発報(10:48 JST) | 家老一次調査(blt_110011): **実変更0件**。signals 2026-08-02は102PF前日比changed=0/unchanged=102。proposed vs ledger 21/21不一致・保存値 vs ledger 21/21一致=**guardが全21件の誤書込みを弾いた正常動作の監査行** |

### 9.2 残穴（次工程 = 殿下知2026-08-02 12:24「DM-Signal最優先」の対象）

| # | 残穴 | 真因 | 状態 |
|---|---|---|---|
| 1 | **ALERT日次反復**(同一補正が毎日「新規変化」として鳴る) | cmd_4195(07-30)で根因確定: ledger安全補正(prevented drift)をconfirmed changeとして通知に混ぜる分類バグ。cmd_4196で是正したが08-02に6件の明確な反復漏れが再発。**反復メカニズムの断定は二転**: 家老一次調査(blt_110011)は「署名にdate含み」、軍師コード検証(blt_124754)は**REFUTE=署名4要素は(portfolio_id,proposed,ledger,rebalance_decision_date)でSignal row dateは署名外**(signal_flush.py L214/L218-226生確認)。∴反復真因は署名の粒度ではなく別(候補: 反復判定のpending flagがDB非永続で復元・再起動時に消失=軍師指摘)。**真因未確定=調査対象**。prevented driftはactual changeと別チャネルで通知すべき(分離設計自体は軍師CONFIRM) | 真因調査+分類是正第2弾が必要 |
| 2 | **FoF cascade drift**(下位FoFの未補正候補が上位FoF計算へ連鎖) | 日次再計算がFoF子の未到達ローカル候補値を親FoF計算に消費→親側でもledger guard補正が発生し補正件数が階層的に拡大(08-02: 下位6PF→上位15件へ連鎖) | **コード根治済み**(影丸, commit 0ed7de44+b90f04ee): 『親FoFは到達済みledger確定子値のみを消費し、未到達・不存在はcomputedへfallback』を実装+contract test宣言。fixture実証=修正前drift子1/親込み2→修正後0/0、focused 8/8 PASS・FAIL0・SKIP0。**軍師独立検証CONFIRM**(blt_124754): reconcile L1265→signal_cache消費L674、topological sort保証、consumer被覆1/1 |
| 3 | **本番driftデータ残 43件** | 2026-08-01本番readonly照合: ledger対象102件中保存一致59・drift43(UUID全量証跡化済み)。コード根治(#2)は今後の発生を止めるが、既発生分のデータ解消は別工程 | 未解消(報告はfail-closed FAIL)。家老へ最優先配備下命済み(backup先行+readonly検証の型)。**軍師独立検証CONFIRM**(blt_124754): 45-2pending=43はコード整合。ただし**2UUIDはUNCLEAR**(pending flagがDB非永続で復元不能)→解消工程で当該2件は個別照合が必要 |

### 9.2b 残穴の収束（2026-08-02 13:38追記 — cronを待たない実弾検証済み）

| # | 収束状態 | 一次証跡 |
|---|---|---|
| 1 反復真因 | **実測特定完了**(才蔵recon GATE CLEAR 13:24): date仮説を3PF×3連日=9/9同一ledger署名で棄却。将軍提示のescape候補4件(effective期間外・ledger row未取得・proposed日次変動・前日rollback非永続)を独立実験4/4で判定=いずれもrepeat_suppressed=False。反復の実体はprevented driftの通知分類であり、pending判定はプロセス内bool(DB列mutation 0/9)。**現HEAD b79d5abeは同一ledger decisionの跨日反復を抑止し、別decisionの通知は維持** | queue/archive/reports/saizo_report_cmd_karo_dm_alert_daily_repeat_recon_20260802_20260802.yaml |
| 2+3 rootfix本番反映+drift閉鎖 | **本番閉鎖達成**(飛猿 13:25報告): rootfix b90f04eeのRender live確認(dep-d9nb6mbbc2fs73e8befg)→18表backup+restore dry-run→正規APIでfullrecalculate実走(DB id=218, 04:08:56Z→04:18:47Z)=completed・end_time非NULL。**post parity 102/102・不一致0・change-log追加0・SIGNAL CHANGE ALERT 0件**。raw prevented driftは3PFだが保存変更0・alert0。restore不要。∴「同じ再計算が走っても鳴らない」を**cronを待たず同一経路実走で実証済み**(殿指示13:36: 待機は先送り) | queue/reports/tobisaru_report_cmd_karo_dm_fof_production_closure_20260802.yaml |
| 3残務 | AC1「exact 43 UUID」は構造的に再現不能(43は時点値。pending 2件フラグ非永続で45件supersetから分離不能)→飛猿はfail-close FAIL報告+45 UUID superset全数をsha256追跡・post照合済み。実害なし。教訓=時点値の絶対数をACへ焼き込むな(LS110と同型、家老AC設計にも適用) | 同上 status_detail/assumption_check |

明朝01:40 cronは追加確認(実弾実証は完了済み)。残る是正候補=prevented drift/actual changeの通知チャネル分離(表示層の明瞭化のみ。抑止ロジック自体は現HEADで機能)。

### 9.3 原理の再確認（殿の言葉 2026-08-02 12:33）

**「株価の遡及によって月初の保有シグナルが変わるのが異常。日々のシグナルが日々の株価で変わるのは正常」** — signal(日々の導出値・可変)とholding_signal(月初確定の投資判断の記録・不変)の区別が本設計の根。ALERTは後者の変化だけを検知する装置であり、前者には鳴らない。残穴1の是正は「prevented drift(守った記録)」と「actual change(破られた記録)」の通知分離であり、この原理の通知層への貫通である。

## 7. 因果

`[[cmd_3827_FAIL]] -> [[P1-P3単一経路化GREEN]] -> [[P4 fence4方式連続不採用]] + [[SIGNAL_CHANGE_ALERT実事故07-14]] -> [[殿裁定_目的は保有不変性]] -> [[真因=ledger選択の順序非決定]] -> [[cmd_3905復元]] -> [[freeze三段: cmd_3907決定的選択 -> cmd_3908 correction経路 -> cmd_3909 baseline凍結]] -> [[確定域不変性の構造保証]]`

## 8. 改訂履歴

- v1.0 (2026-07-11 00:05): 初版
- v1.1 (2026-07-11 01:05): 軍師深層レビューA-H反映(immutable snapshot契約・manifest正本・P1-P4実装順)
- v1.2 (2026-07-11 01:45): 家老運用レビュー反映(書込み順序・standalone L5・cron見かけ成功・二値AC14本)
- v1.3.1 (2026-07-11 02:03): 将軍メタレビューM1-M8反映(P5回帰新設・殿裁定checkpoint・drift三段通知・第6caller被覆)
- **v2.0 (2026-07-14 13:30): 殿裁定による戦略転換。単一経路の決定性証明(P4/P5重厚契約)からledger-bound freeze(確定域の構造的不変性)へ。実事故真因(ledger選択の順序非決定)と復元完了を記録。P1-P3資産は維持、P4複雑機構は退役**
- **v2.1 (2026-07-15 04:12): freeze三段の実装全段本番到達を記録(§6.5)。cmd_3907/3908 GATE CLEAR、第3弾はcmd_3909の前提数値失効(478→52行)によりcmd_3947述語導出型へ置換して本番凍結完了=被覆341,799/341,799(100%)。クローズ条件2つ(cmd_3947 GATE+本日10:40 JST cron実弾検証)を明記**
- **v2.2 (2026-07-15 17:15) CLOSED: クローズ条件2つ達成を確認しCLOSED。cmd_3947 GATE CLEAR完了。07-15 10:40 JST cron通過でsignal_change_log=0件・ledger被覆100%未被覆0件を将軍本番DB一次確認(11:43記憶DB記録済み)。freeze三段は全段本番稼働中・構造的不変性が実弾実証された**
- **v2.3 (2026-08-02 12:45): CLOSED本体は不変のまま§9運用追補を追加。実績=8/1 FoF月次11717行消失事故でも確定域不変・8/2 ALERT 21PFは実変更0件のguard正常動作。残穴3件を確定: (1)cmd_4196反復署名にdate含みで日次反復抑止不能=prevented drift/actual changeの通知分離が未了 (2)FoF cascade消費側はcommit 0ed7de44+b90f04eeでコード根治済み (3)本番drift 43件のデータ解消が未了。(2)(3)+通知分離=殿下知08-02 12:24 DM-Signal最優先レーン**
- **v2.3.2 (2026-08-02 13:38): §9.2b残穴収束を追記。反復真因=才蔵recon実測特定(escape実験4/4・date仮説棄却9/9・現HEADが同一decision跨日反復を抑止)。rootfix b90f04ee本番反映+同一経路fullrecalculate実走でSIGNAL CHANGE ALERT 0件・parity 102/102を実証(cronを待たない検証=殿指示13:36)。exact43は時点値ゆえ45 superset追跡で終端。残=通知チャネル分離のみ**
- **v2.3.1 (2026-08-02 12:50): 軍師独立検証(blt_124754)を反映。残穴1の将軍断定「署名にdate含み」は**REFUTE**=署名4要素は(portfolio_id,proposed,ledger,rebalance_decision_date)でSignal row dateは署名外(signal_flush.py L218-226生確認)。反復真因は未確定へ訂正(候補=pending flag DB非永続)。残穴2=CONFIRM(consumer被覆1/1・topological sort保証)、残穴3=CONFIRM(43件コード整合、ただし2UUIDはUNCLEAR=個別照合要)**
