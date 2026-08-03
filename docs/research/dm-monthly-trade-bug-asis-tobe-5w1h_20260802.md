# DM-Signal 月次リターン境界是正 — AsIs/ToBe 5W1H設計書 v5.22 【★stale ledgerバグ(8月保有切替消失・異常25PF)真因確定→修正deploy+run224完走(23:02)・102PF全数再検証中。AsIs→ToBe対照表§2.1新設。全体75%】

> **本書の位置づけ**: 唯一の正本。前提知識ゼロのLLMが本書だけで作業可能なことを設計要件とする。
> **形式規約(v5.00覚醒改稿=殿下知2026-08-03 16:25)**: 本書は**スナップショット型** — どの節も「現在の真実」のみを書く。時系列の差分追記(「以下vX時点:」チェーン)は禁止。経緯は§7改訂履歴と`docs/research/dm-monthly-trade-bug-genko-chain-archive_20260803.md`(旧チェーン生テキスト全文)のみが持つ。撤回済み主張は§0の**棄却済み仮説一覧**に明示し、本文には現行真実だけを残す。∴どの節を読み飛ばしても・どこを要約しても、廃止済みの主張を現行と誤解することはない。

## §0 セーブポイント

- 正本: 本ファイル(repo `/mnt/c/tools/multi-agent-shogun`)。gist鏡: `8cbc86a555dff983d316c4e15441b7b7`
- **★方式転換(殿裁定2026-08-03 19:17-19:20・最優先)**: **本番環境は殿以外誰も見られない→本番使用可**。将軍案(19:19)と家老案(blt_192212)が独立に同一方式へ収束し殿が採用: **隔離複製層(clone作成/snapshot世代/忠実性証明)を廃止**し、(A)**検証入力=本番DB readonly直結**(世代不整合因子クラスが構造消滅。B4d切り分け・C-x oracle検証に適用) (B)**B4e+D系を本番上の段階実行へ統合**=backup取得→本番で1PF再生成→24anchor誤差ゼロ検証→PASSで1→2→4→…→78段階拡大→fullrecalculate→E1三面一致、FAILは即PF単位restore。**維持する底線(削らない)**=backupファースト(全量backup+PF単位restore証跡)・PF単位transaction・各段誤差ゼロcheckpoint・E1三面一致・規律(2)段階進行。安全担保は「隔離」から「backup+可逆性」へ移行(隔離は手段であり目的ではない)。
- **★一発デプロイ実験(殿下知2026-08-03 20:11『一回デプロイしてはいけない理由はなんだ』→将軍検分の結論: ない。待機=洗脳#5の残滓)**: 調査完了待ちの直列計画を廃し即時実行へ — (1)非対象テーブル(signals/prices/trade_performance/portfolios)のbackup取得 (2)修正branch(clamp bf769e7含む境界修正一式)をCI GREEN確認の上デプロイ (3)fullrecalculate実行 (4)monthly_returns生成実測(0行→N行・24anchor照合・E1三面一致)。FAILはcode revert+再実測=完全可逆。根拠=修正はW23 GATE CLEARで検証済み・本番0行で失うものなし・可逆行動の裁可待ち禁止(殿厳命07-10)。B4d/W45調査は並行継続(本実験の出力が最良の切り分けデータ)。旧・書込み解禁3契約の契約2は「0行確定」により目的達成済み=本実験のbackup手順が上位互換(家老へ下達msg_201332)。
- **★本番一次実測(家老19:24 blt_192444・/db-check readonly)**: portfolios total 102(visible 11・fof 78・standard 24)、signals 384,172(distinct PF 102・max_date 2026-08-03)、SPY max 2026-07-31、**monthly_returns=0行(MAX(year_month)=NULL・distinct PF 0)** — 設計書が前提にした既存15,212行と矛盾。**★0行の消失窓(才蔵一次訂正20:07 blt_200753。旧『recalc218最有力』は撤回)**: recalc id218(8/2 04:08-04:18Z)は完走時commit 78/78・**直後receipt=16,824行**であり直接原因ではない。消失窓は**8/3後続run(standard24 run 01:13-01:14Z+FoF78 run 01:40-01:45Z・mr timing 0/78)以後**で、24+78=102全PF構成と一致。仮説A(successor None単独で全履歴0)=反証、仮説B(Phase0 delete独立commit後records空return)=機構は成立するが218への適用は反証。次対象=8/3 source d3343c1fの2run(1件=1 run_id、同一run証拠=start/end・source SHA・commit件数・直後receipt)。**書込みワンパス解禁の3契約(家老提示・採用)**: (契約1)本番readonly入力への切替は即実行 (契約2)**書込みワンパスはmonthly_returns 0行の原因とbackup/restore対象の一次確定後のみ解禁**(0行の理由確定前に「本番actualとの突合」やbackup対象の存在を仮定しない) (契約3)102全PFと実行対象78の差24の定義を確定してから対象母集団を固定。
- **現在地(2026-08-03 23:05=v5.22発行時、★本番復旧完了+PUBLICABLE=YES+stale ledger修正deploy済み)**: **run223完走(21:18)・全テーブル回復を将軍実測(21:19)**: monthly_returns=16,874行/102PF(健全時16,824超)・trade_performance=13,851行/78PF(A0-4b対象母集団と一致)・rolling_returns_summary=620行/78PF・rolling_returns_chart=36,493行/78PF・recalc 223=completed。rolling precompute WARNINGは再構築完了で解消。**spot check完了(家老blt_213156 21:31)**: standard派生欠損24PFの真因(Missing holding_signal before first usable lookback→savepoint全rollback)をhotfix 9a27eb4f(live=dep-d9o8hupt0dsc739k764g)で修正しL2再実行24/24成功・L5 raw 363行 failed=0→**PUBLICABLE=YES宣言済み**。hotfixは「初回有効holding以前の未初期化行のみ除外・開始後欠損はfail-visible維持」=異常隠蔽なし。
  - **★将軍spot check実測(21:30・本番readonly)=復旧とToBe適用の区別**: monthly_returns全体(16,874行/102PF/max 2026-07)は復旧完了状態と一致。ただし核心実例(奥義-GS-加速R-激攻)は**2022-03=+12.867%(3/1→4/1)・2022-04=+14.131%(4/4→5/2)=§1c AsIs値と桁一致のまま**、trade_performanceも4/1→4/4分割行が現存=**§0.6月次境界日仕様は本番未適用**。これはレーンD/E 0%(浄化未実行)のWBS記録と完全整合であり異常ではない — 復旧=データ回復、是正=B4e→C-x W45→D系7段→E1が担う(未完)。残=E2(今夜開場後の定期再計算1サイクル自然検証)+残工程。 進行中はB4dとC-x-W45の2工程(他42工程の状態は§2.5 WBS Status列が正。**v5.09でB4→B4a-e(5工程)・C-x→W1/W23/W45(3工程)へ細分化**)。
  - **B4(real78切り分け→本番段階実行)**: backfill実装+78PF checkpoint一発CLI束縛(60cdebe7)両GATE CLEAR済み。**B4d=軍師が正当FAILと確定(21:52)→FAIL-closeし次サイクルへ即移行(待機理由にしない)**: 新二値契約=**残7行の根因分解→24/24 exact**(影丸 cmd_karo_exact_b4d_anchor7_reconcile実行中)。B4e前提の証跡準備=**B4e prod evidence prep完了・軍師LGTM(21:48・飛猿)、家老GATE判定待ち**。影丸の敵対検証成果=6故障手順定義+BLOCK判定正当(軍師LGTM)、validator強化が78PF checkpoint信頼の前提(変わらず)。
  - **C-x(L1忍法検証)**: as-of runner修正commit=bf769e7(calendar-max clamp)後、**W23=GATE CLEAR(19:45)**。**W45=軍師が正当FAILと確定(21:52)→FAIL-close**: 旧snapshot基線のoracle突合9件normal_mismatchは追跡打切り、新二値契約=**現行snapshot再基線→21PF全Normal突合**(才蔵 cmd_karo_exact_cxw45_live21_oracle配備済み)。**C9=identity prep GATE CLEAR(21:50・小太郎)**=D第2波(FoF)前提が前進。production write 0を維持(D系のみ書込み)。
  - **E系準備**: E1 allpf verifier prep=初回failed(疾風21:51、家老が同処理で再サイクル)。E2=今夜開場後(JST 22:30〜)の定期再計算1サイクルが自然検証。
  - **★割込みバグ(22:04殿観察→23:02修正deploy完了)**: 8月保有シグナル月初切替が消失。将軍基線実測=6/30→7/1は35/102PF切替(正常)に対し7/31→8/3は0/102(異常)。家老全数調査=異常25PF(standard2+FoF23)、真因=resolve_ledger_decisions_bulkがeffective_end=NULLの古いledgerを無期限適用し、signal_flushのreconcileが8月fresh holdingを7月ledgerで上書き。BE/FE乖離なし(FEはBE忠実表示=修正はBE単箇所)。境界テスト121件PASS→backup→修正deploy→**run224完走(23:02)**→102PF全数再検証中(異常25→0の二値確認)。**SIGNAL CHANGE ALERT(count=2262・37PF・2012-04〜2026-08)は歴史のstale上書き解消による確定月変化=正しい方向かの帰属検証中**(§2-6遡及原則: ルール是正由来の変化は受容)。詳細対照=§2.1表#8。
  - **インフラ**: preflight memoryキャッシュ破損(将軍17:45検出)→cache selfheal恒久修正GATE CLEAR(18:12)。
  - **前倒し並列(殿指摘16:41『極限並列』への対応・作業状態19:55=陣形図一次)**: 疾風=B4 real78 producer再走(readonly直結)、影丸=C2 target_date hotfix done、半蔵=PF restore契約hotfix実装中、才蔵=atomic recalc設計recon完了、小太郎=本番PF母集団recon(102vs78差24=契約3。形式failedは家老同処理)、飛猿=PF apply oracle設計done。idle 0名維持を家老goalに設定。最新は家老一次更新が正。
  - **検証運用の現行規律(殿裁定14:45-16:48)**: (1)『仮説→調査→検証→確認→次の仮説』のループで回す (2)最小標本(1PF/1lane×1月)で二値確認→成立後に段階拡大→全数は最終checkpointのみ。**実験matrixにも適用(殿下知18:38): N条件一括でなく1条件→2条件→4条件と因子を1つずつ固定して段階進行。切り分けが最速になる** (3)W1-W5は段階直列 (4)標本は満月(Normal)月限定、Partial/MTDは別レーンで専用判定(混合は切り分け不能) (5)監査母集団は本番configが参照するsymbolで定義する (6)**AC・報告契約の最小化(殿指摘16:47)**: recon/prep系(途中試行)のACは目的直結1-3個のみ。書式契約(operational_simulation・binary_checks全欄等)の再試行往復を忍者にさせず、成果本文が有効なら家老が直接吸い上げて次手を打つ(書式修正は並行)。同型failed_unclosedのエスカレーションは不要=家老が同処理で閉じる (7)**D-x2波分割**: standard PF(子孫なし)はB4完走の瞬間から浄化第1波、FoF分のみC9/C2後の第2波(topological順の正当な適用) (8)**極限並列**: idle 0名を常時維持、前提待ち工程の準備を前倒し配備。
  - **次関門**: B4=**anchor7 reconcile 24/24 exact**→B4e 78PF最終checkpoint→**D第1波(standard)開始**。C-x=**live21 oracle 21PF全Normal突合PASS**→W45完了→C9本体→**D第2波(FoF)**→E1三面一致。
- **棄却済み仮説一覧(再調査禁止。読み飛ばしても誤解しないための明示)**:
  | 棄却済み仮説 | 棄却根拠(一次実測) | 棄却時刻/版 |
  |---|---|---|
  | 2026-07 price欠落(missing110)が根因 | 本番PF configが参照する必要13symbol(GDX/GLD/LQD/QLD/QQQ/SPXL/SPY/TECL/TMF/TMV/TQQQ/^VIX/XLU)は2026-07全日missing0=完全。missing110(IEF/SOXX/XLE/XLK/XLV)は本番非参照historical銘柄を混ぜた偽母集団(殿指摘『IEFを使う本番PFは一つもない』) | 16:07/v4.98 |
  | July successor実在(SPY等代表銘柄実測による) | 小太郎materialize実測=txid1092151・July successor 0/24。そもそも日本16時台=米国8月市場開始前ゆえJuly successorは存在しなくて正常(wall-clock整合が真因) | 15:04/v4.94 |
  | C-x W1保存層FAIL(production saved rows0) | saved rows0は既存本番の比較対象行が0件というhistorical baselineであり保存失敗ではない。W1最小機構は完全PASS(generator生成1・oracle exact1/1・hash2/2・runner4/4) | 15:43/v4.97 |
  | B4方式(logical-date/銘柄追加/敵対oracle/推移閉包)自体の欠陥 | 4独立実験全てanchor0/24=方式無罪・入力世代有罪(snapshot/as_of世代とwall-clockの不整合=7実験収束で同一根因確定) | 14:10/v4.89-90 |
  | commit 980b4110のB4証跡採用 | git object実測8path(B4 4+C-x 4混入)でscope限定性主張無効。clean起点=現HEADのB4 4成果hash | 13:56/v4.87 |
  - 旧§0の版別現在地チェーン(v4.56-v4.99生テキスト)と旧WBS B4/C-x経緯セルは `docs/research/dm-monthly-trade-bug-genko-chain-archive_20260803.md` へ全文退避(情報量削減ゼロ)。各版の変更点は§7改訂履歴が正。

### §0.1 全体進捗トラッカー(将軍が進捗変化のたび更新。工程別詳細=§2.5 WBS Status列)

```
全体進捗: ███████████████░░░░░ 75% (GATE CLEAR 32 + 進行中 2×0.5 = 33.0 / 44工程 ※v5.09でB4→5工程・C-x→3工程へ細分化(殿指示18:51))
レーンA0: ██████████ 100% (9/9: GATE CLEAR=A0-0a,A0-0b,A0-0c,A0-1,A0-2,A0-2p,A0-3,A0-4a残件,**A0-4b(殿裁定12:29=全78PF再生成route・24行anchor検証)**)
レーンA :  ██████████ 100% (5/5: GATE CLEAR=A1+A2+A3+A4+A5(11:11:20)=**L0確定宣言完了**)
レーンB :  ████████░░  83% (12.5/15: GATE CLEAR=B1,B2a,B2b,**B3(12:57:49)**,B2c,B2d,B2e,B3i,B3.5,**B4a,B4b,B4c**。進行中=B4d(real78 anchor 0/24の段階実験1→2→4)。残=B4e(78PF最終checkpoint)+B5(rejection gate準備は前倒し完了))
レーンS :  ██████████ 100% (3/3: GATE CLEAR=S1,S2,S3(08:39:03))
レーンC :  ██████░░░░  58% (3.5/6: GATE CLEAR=C0(11:30:11),**C-x-W1(16:54)**,**C-x-W23(19:45)**。進行中=C-x-W45(oracle突合9件normal_mismatch根因trace中)。※方式転換(殿裁定19:20)でC-x検証入力は本番readonly直結へ切替。C9=preflight GATE CLEAR 11:49:29済み・本体は全C-x PASS待ち)
レーンD/E: ░░░░░░░░░░   0% (0/6。**A0-4b裁定済み(12:29)→D系Start解放**。D0 preflight=GATE CLEAR済み。**入口=B4d根因確定+backup対象一次確定+backup完了(方式転換=殿裁定19:20。書込み解禁3契約成立が前提)**。実行順序=裁定固定7段)
```

- **★deadline(殿下知2026-08-03 16:40)**: **今日の米国市場開場(JST 22:30)前に全工程完了(下知時点38工程=v5.09細分化後の44工程と同一scope。対応表=§0.1直下)**。逆算スケジュール: ~18:00 B4 10/10再成立+78PF最終checkpoint・C-x W1完成→W2-W5貫通 / ~19:30 C9+C2-x / ~21:00 D系7段(本番書込み) / ~22:00 E1三面一致(E2の1サイクル監視=今夜の開場後再計算がそのサイクル)。加速手段=idle忍者を前提待ち工程の準備(C9突合準備・D0実行計画+backup/rollbackドライ検証・E1手順)へ前倒し全投入し、前提成立の瞬間に実行だけの状態を維持する
- 進捗の定義: done=Goal二値PASS(GATE CLEAR含む)を1.0、進行中=0.5、未着手=0。母数=WBS44工程(Phase5凍結分は除外。v5.09細分化後)
- **旧38工程→新44工程対応表(v5.09細分化。scope追加なし=分割のみ)**: B4(1工程)→B4a+B4b+B4c+B4d+B4e(5工程。旧B4のGoal全内容はB4eが継承、B4a-dは旧B4の途中到達点を工程化)。C-x(1工程)→C-x-W1+C-x-W23+C-x-W45(3工程。旧C-xのGoal全内容はC-x-W45が継承、W1/W23は旧C-x隔離契約⑤の段階を工程化)。他36工程は1:1不変。macro goal監査=B4e GoalとC-x-W45 Goalが旧B4/C-x Goal本文と一致することで担保

- 起点: 殿指摘 2026-08-02 21:33「複数PFで極端にCAGRが下がっている」
- 転換: 殿の連続指摘(2026-08-03 00:47-01:46)で「月中トレード汚染」認定が覆り、真の問題=**月次リターンの月境界仕様が未明文で、実装が誤った境界(月初固定)を使っていた**ことに確定
- 合格基準(殿裁定2026-03-11・比較器はv3.4で一意化=家老F4): 全数値フィールドが全PF×全期間で誤差ゼロの完全一致。**比較方法=双方の値を本番計算の保存前round規約(Pythonの`round(x, 10)`=round-half-even、実装=price_ratio_impl.py:900)で量子化した後のexact一致のみ**(DB列自体はFloat型=models.py:271-272のため「DB保存精度」とは呼ばない)。raw差1e-12等の別基準は用いない(二重基準の判定割れ防止)
- ルール正本: DM-signal repo `docs/rule/trade-rule.md`(RULE01-11)。**本書§0.6の確定仕様を正本へ転記する作業がA0-4aの残件**

## §0.5 前提知識(自己完結定義)

### 対象システム
- **DM-Signal**: 投資PFシグナル配信アプリ。repo=`/mnt/c/Python_app/DM-signal`(Python/FastAPI+PostgreSQL、Render稼働)
- **PFの2型**: `portfolios.type='standard'`(ticker×weight直接構成) / `'fof'`(他PFを組合せるFund of Funds。FoFのholding_signalは子PFのUUID。入れ子あり)
- **層(Layer)**: L0=standard / L1=構成が全てstandardのFoF / L2・L3=入れ子FoF。下位層が誤れば上位層は必ず誤るため、検証はL0→L1→L2/L3の順(層間直列・層内並列)
- **忍法**: FoF系列の戦略ファミリー。L1検証は忍法単位レーンに分解(殿指示2026-08-03 00:24)

### 主要テーブル
- `signals(portfolio_id, date, signal, holding_signal)`: holding_signal=確定保有(FoFは子PF UUID)。**signalは生シグナルでholdingの代用禁止(fallback禁止)**
- `monthly_returns(portfolio_id, year_month, monthly_return, monthly_return_open, cumulative_return, ...)`: year_month='YYYY-MM'
- `trade_performance(portfolio_id, trade_number, start_date, end_date, trade_date, trade_type, allocation, portfolio_return, ...)`: PK=(portfolio_id, trade_number)のみ(models.py:343-375)。日付/種別制約なし
- `prices(symbol, date, open, close, ...)`: **配当調整済み(adjusted)**

### 役割分担(殿裁定2026-08-03)
- **営業日=pricesテーブルに価格が存在する日**(基準symbol=SPY、実装=business_day_utils.py L33-58)。DM-signal側で営業日を独自判定しない。価格供給=stock data API(別PJ)。固定休日表・独自カレンダー新設禁止
- **配当調整=stock data API側の責務**(2026-07-05にyfinance adjusted→EODHD raw+自前調整へ移行。正本=DM-signal `docs/design/gs-recalibration-plan.md`、精度検証=cmd_3691 commit d7abccd)。DM-signal側・オラクル側での独自調整禁止

### 運用タイムライン(殿確定・実測裏付け済み)
1. 前月末最終営業日の市場終了後に価格確定
2. 月初(暦日1日、非営業日でも可)の再計算で当月holding_signalが**初めて**算出される
3. **執行=当月に保有が実際に切り替わる日**(通常は月の初営業日。例: 2026-08は8/1土・8/2日が非営業日ゆえ8/3月。ただし切替が遅延した月は実際の切替日=§0.6-1)。執行前のOpen表示が再計算のたび収束・変化するのは正常動作
4. 月初リバランス前後で保有tickerが変わるのは自明。境界遷移を「同月中のトレード」と扱ってはならない

## §0.6 確定仕様(殿裁定2026-08-03 01:26-02:25。本節が計算仕様・記録仕様の唯一の正。**未決事項なし**)

1. **月次リターン区間 = 当月の月次境界日→翌月の月次境界日**。**月次境界日は全ての暦月に必ず1つ存在する**(保有切替の有無に依存しない — 家老F1):
   - **保有切替がある月**: 境界日=**切替が実際に効力を持った日**。市場の月内初営業日と同一視してはならない(2022-04は4/1が営業日だが効力発生=4/4。遅延した月はその実際の日)
   - **保有切替がない月**(非リバランス月・holding継続月・Cash継続月・同一シグナルのリバランス月): 境界日=**当月の初回取引日**(RULE06の暗黙的月次ウェイトリセットの効力日。切替がないため遅延は発生し得ない)
   - **RULE06(毎月ウェイトリセット)は意図的な確定ルール(殿裁定2026-08-03 02:14-02:16)**: 設計意図=「四半期リバランスのPFに途中から参加しても成り立つよう、同一保有シグナルでもあえて毎月リセットする」(trade-rule.md L153に明文)。理論上はdrift保有の複利と乖離するが、**リバランス日・モメンタム計算日を変える感度分析でロバストネスが実証されており実務上許容**(artifact=家老N3: 第一弾N感度 `docs/research/month-end-n-day-momentum-sensitivity-asis-tobe-5w1h_20260731.md`(v3.4完了・崩壊なし)、第二弾E感度 `docs/research/execution-delay-sensitivity-asis-tobe-5w1h_20260731.md`(v1.5完了・全E優位維持)、第三弾gist b2a97d63)。driftへの変更は行わない。monthlyリバランスで同一シグナルになった月もリセットは執行される(RULE04: 銘柄同一でもリバランスは発生)
   - **切替効力日の判定優先順位(家老N1是正→A0-0c実測還流=cmd_4222 commit 455e682fa)**: ledger内で効力開始を表すフィールドは `signal_decision_ledger.effective_start_date`(resolver=対象日以下のeventから `(effective_start_date, recorded_at, id)` 最大を採用)。**ただし2026-08-03時点の本番15,212行は全件 `effective_start_date = rebalance_decision_date` の複写であり、2022-04実例はledger 4/1 vs 実切替4/4で不一致**。よって歴史backfill値を無条件SSOTにしてはならない。導出式: `boundary(month) = verified(ledger.effective_start_date == expanded_switch_date) ? ledger.effective_start_date : expanded_switch_date`(**expanded weights実切替日との一致が検証できたledger値のみ優先、不一致・未記録月はexpanded weights実切替日へfallback**)。切替なし月は当月初回取引日(§0.6-1本文)。検証条件なしの単純 `COALESCE(ledger, expanded)` は2022-04を4/1へ誤分類するため禁止。**root holding_signalの日付は境界日として採用しない**(実証: 2022-04はroot切替=4/1だが実効力=expanded切替4/4)。root日付はexpanded効力日との同値が証明された場合の補助証拠のみ。ledger歴史効力日の実切替日への再基線化はA0-4b route裁定候補
   - 例: 4月=4/4→5/2。直感に反するが**4/1-4/4は3月に属する**(殿裁定01:40)
   - **用語統一(家老N1)**: 以後、本書で境界を指す語は「**月次境界日**」のみを用いる。「執行」はholding切替の事象(§0.5タイムライン3)を指し、切替なし月のRULE06リセット効力日は執行ではなく月次境界日である
2. **空白ゼロの構造保証**: 連続月は月次境界日という単一の境界点を共有(前月の終点価格=当月の起点価格)。空白があるとpre/afterの価格変動を無視してしまう — これが是正の核心理由。端点はPF開始(Partial起点=全ticker価格が揃う実運用開始日)と現在(MTD終端=as_of)の2つのみ
3. **系列**: Close系列=月次境界日のclose、Open系列=月次境界日のopen。混在禁止(RULE09)
4. **モメンタム(シグナル判定)はリターン区間と別物**: 終点=常に月の最終営業日の終値。始点=ルックバック期間に応じて変動。全て営業日ベース(現行実装momentum_cache.py:79-93/212-230は殿裁定と一致=変更不要)
5. **月の四分類(家老F6で未開始を分離)**: Normal=確定済み月(上記区間で計算) / MTD=進行中の未確定月(**当月の月次境界日→as_of**の動的計算=家老F3。歴史突合対象外) / Partial=PF実運用初月(実運用開始日→翌月の月次境界日。**開始日を含む初回不完全区間のみ**) / **未開始**=実運用開始日より前の月(検証対象外。Partialと混同しない)
6. **取引費用=0**(システムに費用概念なし。rg全域hit 0で確定)
7. **fallback禁止・fail-visible**: holding_signal欠損・weights空を0や代用値で握りつぶさない(現行return_calculator.py:212-225の空weights→0.0化は修正対象)
8. **数値意味論の規約**(軍師#8+家老F4): weights系の一次データはJSON格納(decision_ticker_weights/config/momentum_data)であり、本番展開はfloat化・equal-weight除算・再帰乗算を行う(price_ratio_impl.py:1096-1112)。**オラクルは本番と同一の数値意味論(float64)で展開・計算する。本番実装が行う正規化のみ同一に適用し、それ以外の正規化・丸めの追加は禁止**(独自Decimal化・中間丸め含む)。比較は§0の一意基準(10桁量子化後exact一致)に従う — 基準は§0の一箇所のみで定義し本節では参照する。子PF weight合計の1.0乖離は補正せずfail-visibleで記録。展開の各段(JSON→float・除算・再帰積)の規約はA0-1実装時にfixtureで固定

### 現行実装の誤り(是正対象。家老D0現物特定)
- 月境界を「月初SPY存在日→翌月初SPY存在日」に固定: return_calculator.py:159-181/245-249、monthly_returns.py:353-364/388-392 → **執行ずれ月に空白が生じる根因**
- trade生成器がFoF展開weightsの日次変化を無条件trade化: trade_performance.py:613-659 → 暫定値・非取引日付のMonthly行を永続化
- signal fallback: trade_performance.py L497(Standard側)+L223+repo同型 → 全数除去対象

### オラクルv2入力SSOT(家老D0固定・証拠行番号付き)
prices(open/close, adjusted)・SPY prices日付カレンダー・portfolio.type/config(rebalance_trigger/component_portfolios/pipeline_config/weights)・signals.holding_signal・pipeline FoFのみsignals.momentum_data.weights・全子PFのconfig+signals再帰展開・signal_decision_ledger.decision_ticker_weights(確定月は最優先)・as_of_date(証拠: return_calculator.py:145-210, monthly_returns.py:209-213/371-385, price_ratio_impl.py:1045-1080/1174-1188/1220-1247)。本番のcache・修正経路を経由しない独立再帰計算とする

### trade_performance正規形(✅確定 — 殿裁定2026-08-03 02:25+家老B1是正)
**月次境界日/trigger eventごとに1行**(家老B1: allocationが前月と同一でも行を分割する — RULE06の毎月resetイベントを記録可能に保つため。「同一状態の連続区間を1行に結合」は採らない)。隣接行はend=次行start・gap/overlap 0。非Openはtrade_date=当該月次境界日かつ**typeはrebalance_trigger由来(Monthly/Bimonthly/Quarterly)に統一。Signal型は廃止**(殿裁定: RULE04の独立性維持・DB制約が単純化。**signal変更の正本はsignals/ledgerでありtrade記録から読むものではない**=家老WARN: 異なる子PFが同一expanded allocationになる場合、allocation差分ではsignal変更を判別できない)。terminal Openは1行のみ(trade_date NULL)。allocationは月次境界日時点の確定weights。非取引日・暫定weightsの行は禁止。producer不一致(trades_impl.py:1027-1081のSignal型)はB2dのproducer一本化で是正。**必須fixture: 同一allocation連続月**(行分割が保たれること)

### 検証者規約(不一致を「誤り」と断定する前の4問)
1. その月は実運用開始日以降か?(**実運用開始日を含む初回不完全月=Partial、それより前=未開始(対象外)** — Partialと未開始を混同しない=家老F6)
2. 確定済みの月か?(進行中ならMTD — 歴史突合対象外)
3. 境界を**§0.6-1の月次境界日**で解決したか?(誤り方は2種を区別せよ=家老F7: (a)暦日1日固定→初営業日への解決漏れ(実証: 影丸104件が「1日非営業日月」に集中) (b)初営業日固定→実効力日への解決漏れ(実証: 2022-04執行ずれ、A0初回オラクル1,861行誤判定)。両方を通過して初めて正)
4. リターン境界とモメンタム窓を混同していないか?

### 作業環境と制約
- 調査は本番readonly厳守。SQLは`/db-check`スキル(db_capability_launcher readonly_query)のみ
- 本番書込みはPF単位transaction+事前backup+transactional_restore手順固定の実装cmd経由のみ
- 横断制約(殿原則): 粒度を小さくシンプルに確認×レーン間並列。一括検証・一括再生成禁止
- cmd化規約: 1工程=1cmd。ACは§2.5のGoal二値をそのまま使用。バンドル起票禁止

## §1 AsIs(確定事実・全て本番readonly実測)

### 1a. 引き金(2026-08-02)
- rootfix `b90f04ee`(親FoF消費是正。commit=2026-08-02 11:57:56 JST git log確定。cache補正`0ed7de44`とは別物)+fullrecalculate id=218後、monthly_returnsが7,661行変化(値変化1,885行・59PF)。保有シグナル=0/363,652行で無傷
- 「旧値」=04:06Z backup(13:06 JST、commit後)。revert可否は「recalc id=218実行前か」で決まる — backup実体(パス/manifest/row count/hash)+deploy時刻+recalc開始時刻の三点provenanceはA0-2 Startで確定
- 集計恒等式(積=累積)は102/102PF PASS=内部整合

### 1b. CAGR急落の真因=歴史の書換え
- 変化1,885行は2012〜2026年全期間に散在(2023年264行・2016年205行・2022年200行…今月分96行のみ)。年平均デルタは大半の年で負(最大単月-28.1pt)。57PF中50PFが累積低下方向、ワーストPF累積係数≈0.19倍
- ∴「1ヶ月のマイナスで10年CAGRは動かない」(殿)は正しく、原因は歴史行の書換え。旧新どちらが確定仕様に近いかはA0-2の突合で判明する

### 1c. 「月中トレード」の実体=境界の分割記録+空白
- 同一暦月に複数Monthly行=1,900PF月・69PF(Monthly重複1,839+Open余剰56+PF開始月8)。2本目の発生日: 月初1-3日1,188/4-7日642/8日以降9、3本目5(全て8日以降)。**8日以降計14件のみが真の月中トレード疑い(A0-3個別調査)**
- 実例(奥義-GS-加速R-激攻 2022-04): holding_signalは4/1に正常切替。trade_performanceは「4/1旧構成(4/1→4/4)」+「4/4新構成(4/4→5/2)」に分割。monthly_return=+14.131%は4/4→5/2区間**のみ**と桁一致。3月=3/1→4/1 close(+12.867%桁一致)。∴**4/1→4/4(+0.415%)はどの月にも算入されない空白** — 確定仕様では3月を4/4まで延長して吸収する(是正対象)
- 4/1断片行のallocation(XLU56/TMV44)は直前保有(XLU100)とも不一致=FoF日次展開の暫定値。暫定状態のMonthly化が2026年159件の進行の正体(8/1土曜付Monthly行の実例あり)

### 1d. 過去の検証の無効化(教訓込み)
- Phase 0初回三者突合(neither=1,861/new=21/old=3、artifact=`logs/recon_artifacts/kotaro_phase0_threeway_20260802.csv`)は**§0.6確定前のオラクル(月初固定・境界誤り)によるもので無効**。旧値不正の結論は不採用
- L0検証6忍者の「不一致133件」: A2成果(Normal104+Partial17+MTD12)は**assumption invalidated**。**前提回復RC2(29/29確定・commit 196fd92f系)で確定class=Normal104+未開始25+MTD4**(未開始25=仕様上対象外、MTD4=真の検証対象=A4 RCで突合)。旧報告の暫定値(Partial12+/MTD6/resolver104)と旧仮定月別内訳(5+7)はいずれも誤りと確定済み
- 教訓: 審判(オラクル)の仕様が未確定のまま突合すると偽不一致を量産する。§0.6の4問規約が再発防止

## §2 ToBe

1. **仕様の正**: §0.6がtrade-rule.md正本へ明文化されている
2. **値の正**: 全PF×全期間のmonthly_return系(Close/Open両系列)が§0.6準拠オラクルと誤差ゼロ一致
3. **記録の正**: trade_performanceが§0.6正規形に従う(非取引日付・暫定値のMonthly行=0)
4. **構造の正**: 境界解決はboundary helper(単一関数)経由のみ。計算・記録・表示の全callerが共用。fallback=0箇所・fail-visible
5. **監視の正**: 正規形違反INSERTの拒否+検知が常設(fail-visible)。本番UI/API/DBの三面一致(RULE11)を全PFで検証済み・翌月初サイクルの継続監視あり
6. **シグナル影響の管理(v3.6是正 — 家老現物確認msg_023141により「一切変更なし」の当初主張を撤回)**:
   - **Standard PF: 理論上シグナル不変が成立**(モメンタム入力=ticker価格系列のみ。pricesは本修正で不変)。B4/D4/E1でstandard PFのsignalsスナップショット差分=0を二値確認(checkpoint直前後比較、正常日次追加は別枠)
   - **FoF(L1/L2/L3): 理論上シグナルが変わり得る** — FoF選択モメンタムは子PFのMonthlyReturn.cumulative_returnを擬似価格として使う(一次証拠: component_price.py:54-80、recalculate_fof.py:333-336/976、multi_view_momentum_filter.py:39-42/202-208)。月次是正が僅差ランキングを反転させればcomputed signalが変わり、nested構造(recalculate_fof.py:1318-1364)で上位層へ再帰伝播する
   - ただし**ledger reconcile(recalculate_fof.py:221-235)が確定holding_signalを維持するため、computed変化≠即座のDB holding変化**。∴「DB差分0」は理論不変の証明にならない — **computed-vs-confirmed driftを別計測**する
   - **シグナル遡及の原則(✅殿裁定2026-08-03 02:34)**: ①**price遡及変更**由来の差 → 計算時点のpriceでは正しい計算が行われていた → シグナル維持が正(ledger guardの本来の守備範囲) ②**計算ルールの是正**由来の差 → 過去シグナルが誤った計算式で固定されるのは許されない → **正しいシグナルを受け入れ本番も修正する。フル再計算は正しい変更を反映しなければならない**。∴レーンSでholding_changedが出た場合の扱いは裁定済み=受容・修正(実行はbackup+PF単位transaction+ledger再基線の正規手順で。ledger guardはルール是正の反映を妨げてはならず、価格遡及ノイズのみを弾く役割へ精密化する — 実装はB/Dレーンで設計)
   - 影響の全数確定=**レーンS(dual replay)**: 旧系列と是正系列の2入力で全FoF×全リバランス判断日をL0→L3のtopological順に再走し、各blockのscore/rank/cutoff/threshold/selected setを保存。判定は固定epsilonでなく実差の符号反転/tie変化で行い、**相互排他の三分類(unchanged / computed_changed_should_guard / computed_changed_should_apply)の全数表**を作成(readonly replay時点では適用は観測不能のため予定分類とし、実適用/guardの確認はD/Eレーンで行う=家老v3.9-(4)。signal_changed・holding_changedの予定boolean列を併記)、件数合計=全FoF×全判断日で二値証明。**holding_changedの扱いは裁定済み(§2-6原則: 受容し本番修正)。A0-4bに残る裁定はrouteのみ**

## §2.1 AsIs→ToBe対照表 — リターン計算の変化にフォーカス(殿指示2026-08-03 23:02。進捗列は将軍が進捗変化のたび更新)

**進捗列の凡例**: 仕様=§0.6裁定 / 実装=コード+テスト完成 / 本番=本番DBの値が実際に変わった状態。✅=完了、⏳=進行中、❌=未着手。

| # | 観点 | AsIs(現行本番) | ToBe(§0.6適用後) | 進捗(仕様/実装/本番) |
|---|---|---|---|---|
| 1 | 月次リターンの区間 | 月初のSPY存在日→翌月初のSPY存在日(暦月固定) | 月次境界日→翌月の月次境界日(切替効力日、切替なし月=当月初回取引日) | ✅ / ✅(オラクル+B系生成器) / ❌(D系浄化0%) |
| 2 | 執行ずれ月の騰落 | 空白になりどの月にも算入されない(実例: 2022-04の4/1→4/4 +0.415%) | 前月が境界日まで延長し全騰落を吸収=空白ゼロの構造保証 | ✅ / ✅ / ❌ |
| 3 | 月次リターンの値(実例: 奥義-GS-加速R-激攻) | 2022-03=+12.867%(3/1→4/1)・2022-04=+14.131%(4/4→5/2)=本番実測22:04 | 2022-03≈+13.34%(4/4まで延長し+0.415%を吸収)・2022-04=+14.131%(不変) | ✅ / ✅ / ❌ |
| 4 | 累積リターン・CAGR・rolling系 | 空白分の騰落を取りこぼした値 | 境界日評価で再計算された取りこぼしゼロの値 | ✅ / ✅ / ❌ |
| 5 | trade_performance記録 | 同一暦月に複数Monthly行(分割1,900PF月)・暫定weights行が永続化・Signal型混在 | 月次境界日ごと1行・gap/overlap 0・暫定行禁止・型はrebalance_trigger由来に統一 | ✅ / ✅(B2d producer一本化) / ❌ |
| 6 | 進行中の月(MTD) | 月初固定起点 | 当月境界日→as_ofの動的計算(歴史突合対象外) | ✅ / ✅ / ❌ |
| 7 | 欠損時の挙動 | 空weights→0.0化のsilent fallback | fallback禁止・fail-visible | ✅ / ✅ / **一部本番稼働✅**(precompute_raw IncompletePortfolioRawは本番で発火実証23:00。return計算系のfallback除去はD系待ち❌) |
| 8 | (割込みバグ)保有シグナルの月初前進 | stale ledger(effective_end=NULL)無期限適用が8月切替を上書き=異常25PF | 月初切替が正しく前進(境界を越えた古いledgerは失効) | ✅(真因確定23:02) / ✅(境界テスト121件PASS) / **⏳(修正deploy+run224完走23:02・102PF全数再検証中。SIGNAL CHANGE ALERT count=2262/37PF/2012-2026は歴史のstale上書き解消による変化=帰属検証中)** |

**変わらないもの**: モメンタム判定・切替日の決定ロジック(§0.6-4=現行実装が殿裁定と一致)、取引費用ゼロ、シグナル正本(signals/ledger)。※#8はシグナル値の変更ではなく「決定済みシグナルの反映」の修正。FoF computed signalの二次変化はレーンS三分類+§2-6遡及原則(ルール是正由来=受容)で管理。

## §2.4 依存・並列・影響範囲マトリクス(殿指示2026-08-03 02:41。起票順の唯一の根拠)

**順序の唯一の正本=§2.5 WBS各工程のStart列。本表はそこから機械導出した投影であり、矛盾時はWBSが勝つ(家老v3.9-(1))。Waveは「最速で着手可能になる時点」の目安であり、barrierではない — 各工程はStart列の前提が揃い次第、Waveを待たず着手してよい(家老WARN: lane間並列・lane内直列)。影響範囲=そのcmdが読む/書く対象。本番DB書込みはDレーンのみ。**

| Wave | 工程 | 依存(前提) | 影響範囲(read) | 影響範囲(write) | 本番write |
|---|---|---|---|---|---|
| W1 | A0-0b | A0-0c+§0.6-1(家老v4.4-B1: ledgerフィールド確定後) | 本番DB(readonly) | docs成果物 | なし |
| **W0(即時・全並列可)** | A0-0c | §0.6-1のみ | ledger/DB/コード現物 | 独立成果物md(還流内容案含む。本書追記は将軍直接還流) | なし |
| W0 | A0-3 | §1cの14件のみ | 本番DB(readonly) | docs成果物 | なし |
| W0 | A0-4a残件 | §0.6のみ | — | trade-rule.md(docs) | なし |
| W0 | B3.5(caller inventory) | §0.6のみ | DM-signalコード(read) | docs(inventory表) | なし |
| W0 | B3i(fallback inventory。B3の調査前半を独立工程化=家老v3.9-(3)) | §0.6のみ | DM-signalコード(read) | docs(inventory表) | なし |
| W1 | A0-0a(四分類) | A0-0c還流済み+CSV+本番readonly join | 本番DB(readonly)+CSV | docs成果物 | なし |
| **W1** | A0-1(オラクル) | A0-0a+A0-0c+A0-4a残件(WBS Start列と同一。全W0待ちではない) | prices等(readonly) | 新規オラクルツール+fixture(隔離) | なし |
| W1 | B1(boundary helper) | A0-0c+§0.6(家老v4.3-B1: resolverはledgerフィールド確定が前提) | prices/signals/config/ledger(readonly) | 新規オラクルツール+fixture(隔離) | なし |
| **W2(第二段階・各行Start列準拠)** | A0-2 | A0-1+A0-0a+A0-0b+backup provenance | backup+本番DB(readonly) | docs(層別全数表) | なし |
| W2 | A0-2p | A0-1+A0-0a | 本番DB(readonly) | docs | なし |
| W2 | A1-A5(L0確定。lane内はA1-A4並列→A5) | A0-1 | 本番DB(readonly) | docs | なし |
| W2 | S1→S2→S3(dual replay。lane内直列) | A0-1+旧snapshot固定 | 本番DB(readonly)+旧snapshot | docs(三分類全数表+S3規模報告) | なし |
| W2 | B2a-B2e | B1 | DM-signalコード | DM-signalコード(隔離branch) | なし |
| W2 | B3(fallback除去実装) | B1+W0のinventory | DM-signalコード | DM-signalコード(隔離branch) | なし |
| **W3** | A0-4b(殿route裁定) | A0-2+A0-2p+A0-3+S2/S3(WBS Start列と同一) | 全数表 | 裁定文書 | なし |
| W3 | B4a-e(検証→本番段階実行) | B2a-e+B3+B3.5 | 本番DB readonly直結(B4eのみbackup後の本番書込み=方式転換19:20) | docs(差分表)+B4eは本番DB | B4eのみあり(backup+PF単位restore可逆) |
| W3 | C0→C-x→C9(L1忍法) | A5 | 本番DB(readonly)+L0確定値 | docs | なし |
| **W4** | B5(拒否gate常設) | B4 | — | DM-signalコード(本番deploy) | コードのみ(データ書込みなし) |
| W4 | C2-x(L2/L3) | C9 | **本番DB readonly直結+C9生成成果**(方式転換=殿裁定19:20。旧隔離制約句は廃止=§7 v5.13が履歴保持) | docs | なし |
| **W5** | D0→D-x→D3→D4(浄化) | **B4d根因確定+backup対象一次確定+backup完了(方式転換19:20。旧A0-4b+B4のA0-4bはCLEAR済)**。D-xはL0→L3 topological直列(子孫完了後のみ親) | backup | **本番DB(PF単位transaction)** | **あり(唯一)** |
| **W6** | E1→E2(本番検証) | B5+(D4または浄化不要証跡) | 本番UI/API/DB(readonly) | docs | なし |

**並列可能性の原則**: W0の5工程(A0-0c・A0-3・A0-4a残件・B3i・B3.5)は相互依存ゼロで並列可(A0-0a・A0-0b・B1はA0-0c後のW1)(6名超過分は2巡目、配備順は家老采配)。**設計書本体への還流追記は各cmdのGATE CLEAR直後に将軍が直接実施(将軍直接還流。工程レーンのD0とは無関係)**(家老v4.3-B2: W0並列cmdが同一設計書fileを編集する競合の根絶。各cmdの成果物は独立ファイル+還流内容案の報告記載まで)。A0-1のStartはWBS列(A0-0a+A0-0c+A0-4a残件)であり全W0待ちではない(家老v4.3-B3)。W2以降はレーン間並列・レーン内直列。直列が必須なのは (a)A0-1がA0-0a+A0-0c(将軍還流済み)+A0-4a残件を待つ点 (b)殿裁定(A0-4b) (c)D-xのtopological順 (d)E最終検証のみ。

## §2.5 工程WBS(唯一の状態正本。全工程にStart(前提)/Goal(二値)。1工程=1cmd)

**依存(枝別・家老v4.5-B1)**: 枝1=W0の5工程(A0-0c/A0-3/A0-4a残件/B3i/B3.5)即時並行。枝2=A0-0c(GATE CLEAR+将軍還流済み)→{A0-0a, A0-0b, B1}。枝3=A0-1←{A0-0a, A0-4a残件}→A0-2/A0-2p/S1-S3並列→**A0-4b(殿route裁定=唯一の残関門。前提にS2/S3を含む)**。A(L0確定)=A0-1後。B(根治)=B1/B3i/B3.5が即時、B2群はB1後。C=A5後、C2=C後、D=B4+A0-4b+対象PF所属層確定後、E=B5+(D4または浄化不要証跡)後。

### レーンA0: 再裁定(readonly)

| ID | Status | Start | 作業 | Goal(二値) |
|---|---|---|---|---|
| A0-0a | GATE CLEAR(gate 03:44:10。cmd_4220全1,885行分類確定) | **A0-0c(GATE CLEAR+将軍還流済み)**+三者突合CSV(§1d)+**本番readonly join(operational_start・ledger/expanded境界証拠)**(v4.7実走知見: CSV単独ではQ1/Q3判定材料なし=cmd_4220初回実走で全行要調査に退化) | 全行を証拠付きでNormal/Partial/MTD/未開始へ確定分類し合計式固定(和=1,885)。要調査・未分類が1件でも残る間はA0-0a未完了(in_progress/RC)であり代替PASSなし(家老v4.9-B1) | 証拠付き四分類の和=1,885かつ要調査=0かつ未分類=0か? |
| A0-0c | GATE CLEAR(gate_metrics 03:22:33。455e682fa・還流済v4.12) | §0.6-1優先順位+ledger/DB現物(readonly) | **境界日SSOTのledgerフィールドを現物で確定**し、独立成果物md(還流内容案含む)を作成(本書§0.6-1への追記は将軍直接還流=単一writer、本工程の外) | フィールド名と効力日導出式が成果物mdで確定したか?(還流はA0-0b/B1/A0-1のStart側が「A0-0c GATE CLEAR+将軍還流済み」で確認=家老v4.5-B2) |
| A0-0b | GATE CLEAR(gate 03:53:22。17,379 PF月全走査・欠落0・執行ずれ8,847) | **A0-0c(ledgerフィールド確定済み+§0.6-1のverification付き導出式)**+primitive(signals+ledger+prices+再帰展開) | **執行ずれ月(境界日≠初回取引日の月)の全数一覧をprimitiveから独立導出**(家老F9: 汚染疑いのあるtrade_performance境界を母集団SSOTにしない)。`effective_start_date` の存在のみでStart充足と解釈せず、§0.6-1のverification付き導出式(検証済ledger優先/expanded fallback)を使用。A0-2とroute裁定の母集団へ接続 | 全PF×全月を走査した独立導出一覧が完成し、境界日は全行verification付き導出式によるか? |
| A0-4a残件 | GATE CLEAR(gate 04:07:09。§0.6正本転記完了) | §0.6 | trade-rule.md正本へ§0.6を転記(営業日定義・区間定義・境界日優先順位・モメンタム窓・四分類・RULE06意図)。裁定は完結済みゆえ書記作業 | 正本に§0.6全項が存在するか? |
| A0-1 | GATE CLEAR(gate 04:30:58。確定仕様オラクル+fixture2名突合) | A0-0a+**A0-0c(ledgerフィールド確定済み+§0.6-1のverification付き導出式)**+A0-4a残件(正本転記)+§0.6全項 | **確定仕様オラクル実装**: primitive入力(§0.6 SSOT)からの独立再帰計算(数値意味論=§0.6-8)。fixture期待値=**軍師+家老の2名独立手計算突合で凍結**。fixtureは分類/日付用とreturn用を分離、MTDはas_of固定。**必須fixture月: 1日非営業日月・1日営業日だが効力遅延月(2022-04型)・保有不変月・非リバランス月(bimonthly/quarterly)・Partial・MTD** | 全return fixtureで2名手計算と一致するか? |
| A0-2 | GATE CLEAR(09:41:15。CI run 30774708605 GREENで解消・archive済み) | A0-1+**A0-0a+A0-0b**+backup三点provenance確定(§1a) | A0-0aのNormal行+**A0-0bで導出した母集団外の執行ずれ月行**を「旧値(母集団外は現在値の歴史整合検査)vsオラクル」「新値vsオラクル」の2系で突合し、PF型×層×年代×境界種別の層別全数表を作成(家老N2: 母集団外行もroute裁定へ接続) | 対象全行に2系判定+層別表完成か? |
| A0-2p | GATE CLEAR(gate 06:36:22。1,885=Normal1,871+Partial14+MTD0+未開始0・要調査0) | **A0-0a**のPartial/MTD行+A0-1(専用オラクル含む) | Partial/MTD行を各専用オラクルで判定。計算不能が残る間はA0-2p未完了(要調査移管による完了不可=家老v4.9-B2) | 全行が専用判定済みかつ要調査=0か? |
| A0-3 | GATE CLEAR(gate_metrics 03:34:16) | §1cの8日以降14件 | 真の月中トレード疑い14件の個別調査(実トレードか記録バグか行単位確定) | 14件全行に確定分類が付いたか? |
| **A0-4b** | GATE CLEAR(殿裁定2026-08-03 12:29: **全78PFをPF単位再生成する一本化route**。現行exact21+backup exact3=24行(mixed24PF内)は書込みsourceにせず事前snapshot済み受入anchor(再生成後誤差ゼロ一致検証)兼rollback証跡。実行順序固定=snapshot→78PF隔離再生成→24anchor検証→signal guard1,249/apply72→ledger再基線72→cache再構築→commit。B4は順序まで模擬。根拠=家老cross-tab pf_total=78/mixed24/pure_regen=54(blt_122742)。D省略なし=浄化実行route) | A0-2+A0-2p+A0-3+**S2/S3(シグナル影響全数表)** | **殿がrouteを裁定(12:29確定)**: 月次値=**全78PFをPF単位再生成する一本化route(固定)**。restore/現行維持は書込みrouteとして不採用——24行(現行exact21+backup exact3)は事前snapshot済み受入anchor(再生成後誤差ゼロ一致検証)兼rollback証跡に転用。signal/ledger=guard1,249/apply72/ledger再基線72で一意化。**D省略なし=浄化必ず実行**。D3恒久制約の要否はD3工程で判定 | routeが一意(78PF再生成固定)+24anchor検証契約+実行順序7段が定義済みか?(→定義済み=PASS) |

### レーンA: L0確定(A0-1後。審判=確定仕様オラクル)

| ID | Status | Start | 作業 | Goal(二値) |
|---|---|---|---|---|
| A1 | GATE CLEAR(gate 07:47:36。L0境界再検証774/774 exact・commit 2e951c51) | 影丸L0スクリプト+§0.6規約3 | 境界解決を月次境界日基準へ修正しfixture自己テスト(1日非営業日月含む)後、DM4系を再検証 | 対象PF全確定Normal月が誤差ゼロか? |
| A2 | GATE CLEAR(09:36:36再確定。133行四分類=Normal104/Partial0/MTD4/未開始25・要調査0・未分類0。CLEAR降格→四分類RCで再CLEAR完結) | 6忍者L0報告の不一致133行+前提回復成果(operational_start照合必須) | 全行を証拠付きで**§0.6四分類(Normal/Partial/MTD/未開始)**へ確定分類し合計式固定の証跡表を作成(三分類Goalは前提回復一次結果で不成立と実証=v4.43。operational_start照合を分類手順に必須化)。要調査・未分類が残る間はA2未完了 | **Normal+Partial+MTD+未開始=133**かつ要調査=0かつ未分類=0か? |
| A3 | GATE CLEAR(10:00:40。旧Partial17=Partial0+未開始17の全数証明・欠落/重複/未分類0・runner4/4・commit 023e258f) | A2再確定のPartial行+前提回復成果 | Partial対象の存否をoperational_start全数証明で確認し、対象が存在する場合のみPartial専用オラクル(実運用開始日→翌月の月次境界日、開始日holding展開)で突合 | **旧Partial17の未開始証明添付+Partial対象=0件+未分類=0か?(対象>0なら全行誤差ゼロか?)** |
| A4 | GATE CLEAR(照合RC3=10:31:25。根因一本化=RC1 saved列選択(oracle列対応誤り)・正対応4/4 exact・production修正0・B2b自然解消0。MTD4件の本番値=正常が二重確定。才蔵RC2 CLEAR 10:12:29+疾風RC3 CLEAR 10:31:25) | A2再確定のMTD行(=確定4件) | MTD専用オラクル(**当月の月次境界日→as_of**=§0.6-5)で4件を突合。計算不能が残る間はA4未完了 | MTD4件全行が一致か?(計算不能残=未完了) |
| A5 | GATE CLEAR(11:11:20。L0確定宣言=133行をNormal104/Partial0/MTD4/未開始25へ機械統合・unique133・SHA 7af587e2 2/2・runner17/17。軍師LGTM+家老再実測一致) | A1-A4 | L0確定宣言(4条件全PASS) | 4条件すべてyesか? |

### レーンB: 発生源根治(§0.6仕様で即着手可)

| ID | Status | Start | 作業 | Goal(二値) |
|---|---|---|---|---|
| B1 | GATE CLEAR(gate 04:13:04。helper+13/13 PASS・2022-04型fixture含む) | **A0-0c**+§0.6 | boundary helper実装(**四分類**+月次境界日解決(§0.6-1のverification付き導出式=検証済ledger優先/expanded fallback。無条件ledger優先・単純COALESCE禁止)+モメンタム窓分離)+単体テスト(1日非営業日月・効力遅延月(2022-04型: ledger 4/1≠実切替4/4でexpanded採用)・保有不変月・非リバランス月・PF開始月・進行月) | 全fixture月で分類・日付・境界日が期待値一致し、2022-04型fixtureで4/4を返すか? |
| B2a | GATE CLEAR(09:42:13。rootfix commit 85a15e50・runner8/8・243,293行mismatch0・CI GREEN・archive済み) | B1+return_calculator.py:159-181/245-249現物 | **計算経路へhelper適用**(家老F8 BLOCKER解消: 空白根因の本丸)。月境界の月初固定を§0.6-1境界日へ差替え | 隔離再計算で執行ずれ月の前月が境界日まで延長され空白=0か? |
| B2b | GATE CLEAR(12:33=cmd_design_quality gate_result CLEAR。commit 6a701659でFAIL5→PASS5・指定29/29 PASS・後続CI run 30780850616 GREEN・本体成果=commit d3343c1f・runner17/17) | B1+monthly_returns.py:353-364/388-392現物 | **月次生成経路へhelper適用**(同上) | 同経路の境界が§0.6-1と一致するか? |
| B2c | GATE CLEAR(gate 04:53:17。記録経路helper適用) | B1+trade_performance.py:613-659現物 | **記録経路(FoF生成器)へhelper適用**。暫定状態・非取引日付のMonthly化を構造的に不能化 | 隔離環境で暫定値/非取引日付のMonthly新規生成=0か? |
| B2d | GATE CLEAR(gate 04:37:30。producer一本化) | B1+trades_impl.py:1027-1081現物 | **producer一本化**(家老B2): Signal型producerをtrigger型へ変換・統合。B4の正規形検証前に完了させる | producer=単一系統+Signal型新規生成=0か? |
| B2e | GATE CLEAR(gate 05:58:13。ledger guard mode化+敵対fixture3種) | B1+recalculate_fof.py:221-235現物 | **ledger guardのmode化**(家老N3): recalc invocationへ明示provenance/modeを導入し、price_retro=guard維持 / rule_correction=適用+ledger再基線 / 未知mode=fail-closed。差分から原因を推測しない。**敵対fixture3種**(price遡及・ルール是正・未知mode)必須 | 3 fixtureで期待挙動(guard/適用/停止)が全一致か? |
| B3i | GATE CLEAR(gate 04:03:02。fallback inventory完成) | §0.6のみ(即時可) | **fallback全数inventory作成**(L497+L223+repo同型をgrep全数列挙。読み取りのみ) | inventory表が全数列挙+件数根拠付きで完成したか? |
| B3 | GATE CLEAR(12:57:49。fallback全数除去=実装commit 3efd01e0・47/47 PASS・軍師LGTM。report契約RC完遂) | B1+**B3i(inventory完成済み)** | signal fallback全数除去(L497+L223+repo同型をgrep全数列挙)。欠損はfail-visible | fallback経路=0箇所(inventory添付)+可視エラーか? |
| B3.5 | GATE CLEAR(gate 04:03:02。caller inventory完成) | §0.6のみ(読み取りinventory。helper不要) | 計算/記録/表示の全callerをgrep全数列挙したinventory表を作成(適用漏れ0の検証はB4が本表を使って行う) | caller一覧が全数列挙+件数根拠付きで完成したか? |
| B4a(1PF anchor実証) | GATE CLEAR(16:14:04。1PF×満月2026-06世代のanchor正実証) | B2a/B2b/B2c/B2d/**B2e**/B3/B3.5 | 最小標本1PFで隔離再生成→受入anchorとの誤差ゼロ一致を実証 | 1PF anchor exact一致か? |
| B4b(10PF生成+正規形) | GATE CLEAR(18:06。ext4再走で10/10生成+才蔵レビューのbulk UPSERT内キー二重投入cardinality violation是正込みpost-signal backfill実装) | B4a | 10PF隔離生成+§0.6正規形違反の新規発生0+post-signal backfill実装 | 10/10生成+新規違反0+レビュー指摘是正済みか? |
| B4c(checkpoint束縛) | GATE CLEAR(18:14。producer→artifact→validator三辺束縛・正常1/1 PASS・故障注入11/11 BLOCK・schema/producer/path/target_date/hash fail-closed・scope commit 60cdebe7) | B4b | 78PF checkpointを一発CLIへ束縛し実装commit直後の一発実行を可能にする | 正常PASS+故障注入全BLOCKか? |
| B4d(real78 anchor切り分け) | 進行中(初走18:27=processed 78・anchor actual 0/24全None FAIL→**段階実験(殿下知18:38: 1→2→4条件、因子=end_date/logical_today/boundary input)**。第1条件保存済み・第2段2条件実走中。影丸検出のvalidator一次source/provenance欠落の強化を含む。棄却済み仮説=§0棄却表。全経緯=`docs/research/dm-monthly-trade-bug-genko-chain-archive_20260803.md`+§7) | B4c | 因子を1つずつ固定する段階実験でanchor全None根因を確定し修正 | 24anchor(現行exact21+backup exact3)誤差ゼロ一致か? |
| B4e(78PF最終checkpoint) | 未着手(**★方式転換=殿裁定19:20: D系と統合し本番上の段階実行へ**。旧作業定義(隔離実行系)は§7 v5.09-v5.13が履歴保持) | B4d+書込み解禁3契約成立 | **本番上の段階実行**: backup取得→本番1PF再生成→24anchor誤差ゼロ検証→PASSで1→2→4→…→78段階拡大(FAILは即PF単位restore)。各checkpointで§0.6正規形違反の新規発生0+非対象フィールド不変+**signals差分(standardは差分0、FoFはSレーン分類で裁定済み変更(applied)と非意図差分を区別)**を確認。**殿裁定(12:29)のD系実行順序7段を実実行として同順で通す**: backup→78PF再生成→24anchor誤差ゼロ一致検証→signal guard1,249/apply72→ledger再基線72→cache再構築→commit、各段の処理件数(78/24/1,249/72/72)と非意図差分0を記録 | 全PF段階で非対象差分=0+新規違反=0+**standard signals差分=0+FoF非意図差分=0**+**7段実実行で24anchor一致・各段件数一致・非意図差分0**か? |
| B5 | 未着手 | B4e | 正規形違反INSERT**拒否gateの常設のみ**(producer一本化はB2dで完了済み=家老B2)。DB恒久制約はD3まで保留 | 違反注入テストで拒否+通知100%か? |

### レーンC: L1忍法検証(A5後、1忍法=1レーン並列) / C2: L2/L3(C後)

| ID | Status | Start | 作業 | Goal(二値) |
|---|---|---|---|---|
| C0 | GATE CLEAR(11:30:11。L1対象FoF全数一覧+忍法系列分類=飛猿・軍師LGTM 11:27:55。Cx oracle lane preflight=GATE CLEAR 11:26:45) | A5+本番DB | L1対象FoF全数一覧と忍法系列分類表 | 全L1 FoFが1レーンに1回だけ属するか? |
| C-x-W1(隔離L0再計算) | GATE CLEAR(16:54。7lane 15:55→全Standard N=12 16:18(exact12/12・hash2/2)→全canonical Normal月完成) | C0+**隔離snapshot**(L0確定値のDB materialization代替) | 隔離snapshot上でL0を再計算し受入基準と突合(W2以降の土台) | 全canonical Normal月がexact一致か? |
| C-x-W23(忍法generation) | GATE CLEAR(19:45。経緯: 初走parent_empty 21/21→根因=snapshot世代不整合→63判定でcalendar-max clamp一意採用(bf769e7)→家老BLOCK 19:10(processed戻り値≠生成証明)→小太郎閉包hotfixで**parent nonempty 21/21+errors 0+production write 0の正式report PASS**→軍師LGTM 19:36→家老ACCEPT・completion 8/8でCLEAR確定) | C-x-W1 | 忍法ごとのgeneration(母数21=canonical L1 FoF。**入力=本番DB readonly直結・結果書込みは検証用ローカルのみ**=方式転換19:20) | 検証用生成のparent row非空21/21+errors 0+production write 0+正式報告+家老GATE CLEARか? |
| C-x-W45(oracle全数突合) | 進行中(**blockers 9・failures 9(normal_mismatch)・rc=1で全体FAIL**→小太郎9/9全行trace(PF・月・expected/actual・delta・weight日付)+影丸oracle仮説H1-H7 matrix+半蔵oracle意味論(LGTM済)並走中。検証契約(二値5項・方式転換19:20で①を本番readonly化)=①**本番readonly as-of時刻+参照hash記録**(旧: 隔離snapshot時刻+hash=廃止句§7 v5.13) ②code/config SHA固定 ③production write=0証明 ④21/21 PF完全性 ⑤W1→W5順序遵守。C-x GATE=W5完了までBLOCK維持・OUT_OF_SCOPE丸め終結禁止(家老F10)。棄却済み仮説=§0棄却表。全経緯=archive+§7 v4.76-v4.99) | C-x-W23 | 忍法ごとに確定仕様オラクル(入力=直下L0確定値のみ)で全Normal月突合+Partial/MTD専用オラクル | Normal=誤差ゼロ・Partial/MTD=専用判定PASS・未開始のみ対象外、で全行が確定したか?(除外PASS禁止=家老F10) |
| C9 | 未着手(preflight=GATE CLEAR 11:49:29済み・本体は全C-x PASS待ち) | 全C-x PASS+**本番DB readonly直結+W1-W5生成dataset**(方式転換=殿裁定19:20。旧隔離制約句は廃止=§7 v5.13が履歴保持) | FoF合成恒等式(構成weight×子PF確定値=親月次)を全L1で確認しL1確定 | 恒等式不一致=0か? |
| C2-x | 未着手 | C9+**本番DB readonly直結+W1-W5生成成果の継承**(方式転換=殿裁定19:20。旧制約句は§7 v5.13-v5.14が履歴保持) | L2→L3の順に直下層確定値のみを入力に同型検証(1親FoF=1レーン)。**各層でparent actual欠落0を確認してから次層へ** | 各層全行が誤差ゼロ+各層parent actual欠落=0か? |

### レーンS: シグナル影響dual replay(A0-1後・C系と並列可。readonly)

| ID | Status | Start | 作業 | Goal(二値) |
|---|---|---|---|---|
| S1 | GATE CLEAR(gate 07:45:40。dual replay 17,902行・3回hash一致) | A0-1(是正系列オラクル)+旧MonthlyReturn snapshot固定 | 全FoF×全リバランス判断日を旧/正2入力でdual replay(L0→L3 topological順、同一pipeline config)。各blockのscore/rank/cutoff/threshold/selected set/computed signalを両系で保存 | 全FoF×全判断日の両系記録が完成したか? |
| S2 | GATE CLEAR(gate 08:09:30。三分類全数表完成) | S1+ledger確定値 | 相互排他の三分類(unchanged / computed_changed_should_guard / computed_changed_should_apply)全数表を作成(予定分類。実適用確認はD/E。boolean列併記。件数合計=全FoF×全判断日)。僅差判定は実差の符号反転・0到達・tie変化(固定epsilon禁止) | 三分類の合計が母集団と一致するか? |
| S3 | GATE CLEAR(08:39:03。holding_changed 1,321件=guard 1,249/apply 72固定、34PF・3層・14年・6 block_type全集計和一致・重複/欠落/未分類0) | S2 | 結果を殿へ報告(holding_changedの件数と内訳)。**扱いは裁定済み(§2-6原則: 受容し本番修正)** — 報告は規模と実行計画の確認のため | 報告完了+修正対象リスト確定か? |

### レーンD: 浄化(本番書込み・直列。**★方式転換=殿裁定19:20: B4eと統合し本番上の段階実行(backup→1PF→検証→段階拡大)へ。D-x StartのB4完了待ちは「B4d根因確定+backup完了」へ短絡**)

| ID | Status | Start | 作業 | Goal(二値) |
|---|---|---|---|---|
| D0 | 未着手 | **B4d根因確定+backup対象一次確定+backup完了(方式転換19:20。A0-4bはCLEAR済)** | 浄化実行計画の確定(**対象=全78PF固定・D省略なし=殿裁定12:29**)。**backup取得証跡+B4d根因確定証跡+実行順序7段の実手順書**を殿へ提示(routeは裁定済みのため方式選択の提示は不要。旧snapshot+模擬PASS要件は§7 v5.14が履歴保持) | 78PF実行計画+backup取得証跡+B4d根因確定証跡が揃ったか? |
| D-x | 未着手 | D0承認+当該PFの所属層検証PASS+**当該PFの全子孫PFのD-x完了**(家老N4: 実行順=L0→L1→L2→L3のtopological直列。下位monthly→上位signal→上位monthlyの伝播があるため、子のcommit/検証後にのみ親へ進む) | 1PF=1 transaction: backup→**PF単位再生成**→オラクル誤差ゼロ→**当該PFにanchor行(24行の該当分)があれば同一transaction内で誤差ゼロ一致検証**→commit。**signal guard1,249/apply72/ledger再基線72/cache再構築は全78PFのD-x完了後にD3前段の全体順序(裁定7段の4-6段目)として実行し、各段commit境界を分離**。FAILは当該PFのみtransactional_restore(冪等) | 当該PF正規形違反=0+誤差ゼロ+anchor行一致+子孫全完了済みか?(noならrestore済みか?) |
| D3 | 未着手 | 全D-x | DB恒久制約(正規形一意)有効化 | 制約有効+既存違反0か? |
| D4 | 未着手 | D3 | 全PF事後検証(正規形違反全数0+§1a恒等式+**signalsスナップショット差分(standard=0、FoF=裁定済み変更のみ)**) | 全数0+PASS+**standard差分=0+FoF非意図差分=0**か? |

### レーンE: 本番表示・継続検証(B5+(D4または浄化不要証跡)後)

| ID | Status | Start | 作業 | Goal(二値) |
|---|---|---|---|---|
| E1 | 未着手 | B5+(D4または浄化不要証跡) | Monthly Trade画面/API/monthly_returnsの三面一致(RULE11)を**全PF**で確認(サンプリング禁止) | 全PFで三面矛盾=0+**standard signals差分=0+FoF非意図差分=0**か? |
| E2 | 未着手 | E1 | 翌月初の定期再計算1サイクルを監視し新規違反0+表示正常を確認 | 1サイクル完走で違反0か? |

### Phase 5(GS再検証判定) — 凍結
殿指示(2026-08-02 23:22)により凍結維持。判定は一点のみ予約: Bレーンで修正した発生源コードがGSスクリプト群(shin_shijin_l1_gs.py・run_077系・grid_search_metrics_v2.py)から参照・コピーされているかのimport/実装照合。着手は殿の下知まで行わない

## §3 経緯evidence(旧版の要点圧縮。詳細は§7と記憶DB)

- 2026-08-02: rootfix後のCAGR急落を殿が検知→調査5トラック→「月中トレード1,839件=汚染」と初期認定→Phase 0初回三者突合(→後に無効化)
- 2026-08-03 00:22-00:34: 三者評定(将軍D1-D7案+家老COUNTER3件+軍師全受容)。boundary helper・PF単位transaction・忍法レーン等の骨格合意
- 2026-08-03 00:47-01:54: 殿の連続指摘で問題定義が転換し、§0.6の全裁定が完結。独立レビュー2巡(家老16+11件・軍師5+1件)+相互不可視最終確認を全反映
- 教訓(§1d): 審判の仕様確定前の突合は偽不一致を量産する / 追記累積は矛盾を残す(本v3.0全面書き直しの理由=殿指摘01:58)

## §4 5W1H

- **WHY**: 月次リターンの月境界仕様が未明文のまま実装が月初固定を使い、執行ずれ月の空白脱落と暫定値Monthly行が歴史とCAGRの信頼を崩したため。殿ゴール「全PFが正しく計算され正しく表示されて継続する」への回帰
- **WHAT**: §2.5の6レーン。最初の成果物=A0-0a分類表+A0-0b執行ずれ月一覧+A0-0c ledgerフィールド確定+A0-1オラクル+A0-2層別突合表
- **WHEN**: W0の5工程(A0-0c・A0-3・A0-4a残件・B3i・B3.5)は即時。A0-0a・A0-0b・B1はA0-0c後。D(本番書込み)はA0-4b裁定+殿承認後
- **WHERE**: DM-signal backend(return_calculator.py・monthly_returns.py・trade_performance.py・boundary helper新設)+本番DB(D実行時のみ)
- **WHO**: 配備=家老采配(忍者6名、相互参照禁止)。将軍=版管理・裁定検分・殿上程。軍師=オラクルfixture独立手計算+レビュー
- **HOW**: 判定は常に§0.6準拠オラクルを審判とする突合。修正はboundary helper単一関数を全出口(計算・記録・表示)へ — ledger guardのDB門と同型

## §5 二値AC(設計書レベル)

- AC-A0: 1,885行の証拠付き四分類(Normal+Partial+MTD+未開始)の和=全行・要調査0・未分類0 / **執行ずれ月のprimitive独立導出一覧完成(A0-0b)** / Normal全行に旧新×オラクル2系判定 / Partial・MTDは専用オラクル判定済み / 14件全行確定分類 / **§0.6のtrade-rule正本転記完了(A0-4a残件)** / A0-4b route(月次値route+signal/ledger再基線route)が層別に一意でS2/S3全数表を前提に含む
- AC-B: helper適用後の隔離再計算で正規形違反の新規発生=0+全caller適用漏れ=0+fallback=0箇所+**producer単一系統化+standard signals差分=0+FoF非意図差分=0(Sレーン分類基準)**
- AC-層: L0/L1/L2/L3各層でNormal誤差ゼロ+Partial/MTD専用オラクルPASS(層間直列厳守)
- AC-D: 浄化後、全PFで正規形違反=0・オラクル突合誤差ゼロ・DB制約有効(または浄化不要証跡)+**standard signals差分=0+FoF非意図差分=0**
- AC-E: 本番UI/API/DBの三面一致を全PFで確認+翌月初1サイクル監視で新規違反0+**standard signals差分=0+FoF非意図差分=0**

## §6 因果

`[[殿指摘_CAGR低下_20260802]] -> [[歴史1885行の書換えが真因]] -> [[殿指摘_境界遷移は自明_20260803]] -> [[Phase0オラクル無効化]] -> [[殿裁定_月次区間は執行日から執行日]] -> [[空白脱落バグ確定]] -> [[§0.6確定仕様]] -> [[A0再突合 -> route裁定 -> 根治・浄化]]`

## §7 改訂履歴

- **v5.22 (2026-08-03 23:05): ①殿指示23:02=§2.1新設: AsIs→ToBe対照表(リターン計算フォーカス・進捗列=仕様/実装/本番の三段)。本番列は全行❌(D系0%)でfail-visibleのみ一部本番稼働✅ ②割込みバグの全経緯を§0へ焼込み: 8月保有切替消失(異常25PF)→真因=stale ledger無期限適用(resolve_ledger_decisions_bulk)+signal_flush reconcile上書き→BE/FE乖離なし→境界テスト121件PASS→backup→修正deploy→run224完走(23:02)→102PF全数再検証中 ③SIGNAL CHANGE ALERT(count=2262・37PF・2012-2026)=歴史stale上書き解消の変化として帰属検証中を明記。数値不変75%(33.0/44)=checker照合**
- **v5.21 (2026-08-03 21:56): 進捗同期(陣形図21:54+家老pane一次+掲示板): ①**B4d/C-x W45=軍師が正当FAILと確定→家老がFAIL-closeし次サイクルへ即移行**(待機理由にしない): B4d新契約=残7行根因分解→24/24 exact(影丸in_progress)、W45新契約=現行snapshot再基線→21PF全Normal突合(才蔵配備済み) ②**C9 identity prep GATE CLEAR(21:50)**+**B4e prod evidence prep軍師LGTM(21:48・家老GATE判定待ち)** ③E1 allpf verifier prep初回failed(疾風・家老同処理)を§0 E系準備として新設 ④次関門をanchor7 reconcile/live21 oracleベースへ書換え。数値不変75%(33.0/44)=checker照合**
- **v5.20 (2026-08-03 21:35): ①家老spot check完了同期(blt_213156 21:31)=standard派生欠損24PF真因(Missing holding_signal before first usable lookback→savepoint全rollback)をhotfix 9a27eb4f修正・L2再実行24/24成功・L5 raw 363行failed=0→**PUBLICABLE=YES宣言** ②将軍spot check実測(21:30 readonly)を§0へ焼込み=復旧とToBe適用の区別: 実例PF 2022-03/04が§1c AsIs値と桁一致のまま+4/1→4/4分割行現存=**§0.6仕様は本番未適用(D/E 0%と完全整合・異常ではない)**。殿下問『本番は設計書通りの正しい計算か』への回答=復旧は正しく完了・是正計算は残工程(B4e→W45→D系→E1)が担う ③タイトル・現在地をPUBLICABLE=YESへ更新。数値不変75%(33.0/44)=checker照合**

- **v5.17 (2026-08-03 20:14): ★殿下知20:11『このペースで間に合うのか。一回デプロイしてはいけない理由はなんだ』→将軍検分=デプロイを止める理由なし(修正はW23 CLEARで検証済み・本番0行で失うものなし・完全可逆・待機は洗脳#5の残滓)。§0へ**一発デプロイ実験**を新設: backup(非対象4テーブル)→修正branchデプロイ(CI GREEN)→fullrecalculate→生成実測(0行→N行・24anchor・E1)。FAILはrevert。B4d/W45調査は並行(実験出力が最良の切り分けデータ)。旧契約2は0行確定で目的達成済み=backup手順が上位互換。家老へ最優先下達(msg_201332)。数値不変75%(33.0/44)=checker照合**
- **v5.16 (2026-08-03 20:09): 才蔵一次訂正同期(blt_200753・殿下問19:57への訂正): ①『recalc218=直接原因』最有力仮説を撤回 — id218(8/2)は完走時commit 78/78・直後receipt=16,824行で無罪 ②消失窓を8/3後続run(standard24+FoF78・mr timing 0/78)以後へ確定移動(24+78=102全PF構成と一致) ③仮説A(successor None単独)=反証・仮説B(Phase0 delete後records空return)=機構成立/218適用は反証 ④次対象=8/3 source d3343c1fの2run。§0の0行実測ブロックへ消失窓を追記し棄却情報を明示。数値不変75%(33.0/44)=checker照合**
- **v5.15 (2026-08-03 19:59): ①家老v5.14 REVISE是正(blt_195540)=W23 GATE CLEAR(19:45確定: completion 8/8・軍師LGTM・家老ACCEPT)を§0/§0.1/§2.5の全箇所へ同期→**CLEAR 31→32・進行中3→2・74%→75%**(細分化後初のCLEAR増) ②担当表を陣形図19:55一次へ同期(影丸=C2 target_date done・半蔵=PF restore契約実装中・才蔵=atomic recalc設計完了・小太郎=PF母集団recon(契約3)・飛猿=apply oracle設計done) ③殿下問19:57『0行の意味』→最有力仮説(本番定期recalcが現行バグでW3同型メカニズムにより再生成0件完走=実害の顕在化)の優先検証を家老へ指示(msg_195759)。数値75%(33.0/44)=checker照合**
- **v5.14 (2026-08-03 19:50): 家老v5.13 REVISE是正(blt_194556=残存3活性句の翻訳+W23一次同期): ①C2-x Start=『同一隔離snapshot継承』→『本番DB readonly直結+W1-W5生成成果の継承』(§2.5側の見落とし行。§2.4側はv5.13是正済み) ②B4e Work=隔離dry-run+7段模擬→**本番上の段階実行**(backup→1PF→24anchor→段階拡大、7段は模擬でなく実実行として同順・件数記録)へ全文翻訳、StartへB4d+書込み解禁3契約成立を明記 ③D0 Work/Goal=『snapshot取得+B4順序模擬PASS証跡』→『backup取得証跡+B4d根因確定証跡+実手順書』 ④W23 Status=是正report PASS(nonempty 21/21・小太郎19:31)+軍師LGTM(19:36)・家老GATE再判定待ちへ同期 ⑤§0見出し『B4(隔離ドライラン)』→『B4(real78切り分け→本番段階実行)』+§2.4 Wave表B4行を本番readonly直結(B4eのみbackup後書込み)へ翻訳。旧句は本§7が履歴保持。active_conflicts再計数=0(4句全滅)を将軍側で機械確認。数値不変74%(32.5/44)=checker照合**
- **v5.13 (2026-08-03 19:39): 家老v5.12 REVISE是正(blt_193458=活性句矛盾2組の一意化): 方式転換(19:20)後も旧隔離句が活性のまま残っていた箇所を本番readonly+backup可逆レーンへ一意化 — ①C2-x source=『C9同一隔離snapshot・本番DB直接参照禁止』→『本番DB readonly直結+C9生成成果』 ②C9 Start同様 ③D0/W5 Start=『A0-4b+B4』→『B4d根因確定+backup対象一次確定+backup完了』(レーンD/E行も同期) ④W23作業/Goal・W45検証契約①を本番readonly化(production write=0証明は維持) ⑤担当表を陣形図19:37一次へ同期(才蔵=0行根因recon・飛猿=本番直結preflight等)。旧隔離句は本§7が履歴として保持。数値不変74%(32.5/44)=checker照合**
- **v5.12 (2026-08-03 19:27): ★方式転換(殿裁定19:17-19:20『本番は殿以外不可視→本番使用可』。将軍案19:19と家老案blt_192212が独立収束): ①隔離複製層廃止=(A)検証入力を本番DB readonly直結(B4d/C-x適用・世代不整合因子クラス消滅) (B)B4e+D系統合=本番上の段階実行(backup→1PF再生成→24anchor誤差ゼロ→1→2→4→…→78→fullrecalculate→E1。FAILは即PF単位restore)。底線維持=backupファースト・PF単位transaction・誤差ゼロcheckpoint・E1三面一致 ②D-x Start短絡=B4完了待ち→B4d根因確定+backup完了へ ③本番一次実測(家老blt_192444)同期=**monthly_returns現0行**(前提15,212行と矛盾)→書込みワンパス解禁3契約(readonly即切替/0行原因+backup対象一次確定後のみ書込み解禁/102vs78の差24定義)を§0へ契約化 ④家老v5.11 REVISE是正=担当表19:07一次再計数へ同期・W23計数単位定義と実績0/21明記・未配備を作成中と記す表現0。数値不変74%(32.5/44)=checker照合**
- **v5.11 (2026-08-03 19:12): 家老W23=BLOCK判定反映(blt_191004、殿19:06ナッジへの家老一次確認結果): 『W3回復=processed 21/21』は戻り値の誤読であり、隔離DBのparent monthly row非空生成の証明は0/21・正式報告0件=W23 GATE CLEAR不可。§0現在地C-x・§0.1レーンC・§2.5 W23行を是正し、W23 Goalを『隔離DBのparent row非空生成21/21+errors 0+正式報告+家老GATE CLEAR』へ厳密化。是正契約=同一snapshotで正式報告→軍師レビュー→再判定。数値不変74%(32.5/44)=checker照合**
- **v5.10 (2026-08-03 19:08): 家老v5.09 REVISE 3点是正(blt_190536): (A)旧38工程→新44工程対応表を§0.1直下へ新設(B4→B4a-e 5工程・C-x→W1/W23/W45 3工程・他36は1:1。macro goal監査=B4e/C-x-W45 Goalが旧Goal本文を継承) (B)deadline行『全38工程』→『全工程(下知時点38=細分化後44と同一scope)』+進捗定義の母数をWBS44工程へ統一=母数矛盾0 (C)担当表を家老一次事実19:05へ同期(影丸=C2準備・半蔵=B4外部auditor完了・飛猿=source-marker修正中・才蔵=B4 anchor24 trace中)。数値不変74%(32.5/44)=checker照合。併せて殿下知19:06=C-x-W23家老GATE確認ナッジ送達(msg_190726)**
- **v5.09 (2026-08-03 18:55): ①殿指示18:51=WBS細分化: B4→B4a(1PF anchor実証CLEAR)/B4b(10PF生成+正規形CLEAR)/B4c(checkpoint束縛CLEAR)/B4d(real78 anchor切り分け・進行中)/B4e(78PF最終checkpoint・未着手)、C-x→C-x-W1(隔離L0再計算CLEAR)/C-x-W23(忍法generation・進行中)/C-x-W45(oracle全数突合・進行中)。母数38→44・CLEAR27→31・進行中2→3・74%不変=checker照合。B5 StartをB4eへ更新 ②家老v5.08 REVISE(blt_185119)是正=§0前倒し並列行の8条件matrix旧表記を段階実験(家老実施確認PASS: 7条件並列停止・第2段2条件実走)へ同期**
- **v5.08 (2026-08-03 18:40): ①殿下知18:38焼込み=規律(2)拡張『実験matrixもN条件一括でなく1→2→4条件と因子を1つずつ固定して段階進行(切り分け最速)』。B4の8条件matrix一括を段階実験へ是正(家老経由で疾風へ即時伝達済みmsg_183839) ②家老v5.07 REVISE(blt_183731)是正=§2.5 B4 Statusセルを§0現行真実(初走processed78・anchor0/24 FAIL→段階実験)へ意味論同期 ③飛猿source marker concurrency根治GATE CLEAR(18:36)反映。数値不変74%(28.0/38)=checker照合**
- **v5.07 (2026-08-03 18:32): 家老v5.06 REVISE 2点反映(blt_183132): ①B4のfail-visible現在地を明記=real78初走(18:27)はprocessed78・anchor actual 0/24全None FAIL→疾風8条件matrix(end_date×logical_today×boundary input)へ移行。影丸敵対成果=validator一次source/provenance欠落確定(6故障を確実BLOCK不能)を追記 ②配備欄同期=影丸(成果完成・形式FAILは規律(6)吸い上げ済み)・才蔵(reflux完了+家老ACCEPT)。数値不変74%(28.0/38)=checker照合**
- **v5.06 (2026-08-03 18:29): 家老v5.05 REVISE 2点反映(blt_182726): ①§0前倒し並列=旧担当(疾風D0/影丸C9)を現行配備6名(疾風B4 producer・影丸敵対検証・小太郎fail9 trace・半蔵oracle意味論・飛猿source marker・才蔵reflux)へ更新、旧prepは完了済みと明記 ②§0次関門=完了済みB4 3PF根因→10/10の未来形再掲を除去し、real 78PF producer完走+checkpoint通過/W4W5 9件解消へ更新。数値不変74%(28.0/38)=checker照合**
- **v5.05 (2026-08-03 18:26): 進捗同期(家老一次更新blt_182422): ①C-x=as-of runner修正commit bf769e7(calendar-max clamp)でW3回復21/21・errors0、W4/W5 oracle突合はblockers9・failures9(normal_mismatch)・rc=1で全体FAIL維持→小太郎9/9全行trace+全仮説小実験配備 ②B4=疾風real 78PF producer実装/実走中・影丸6故障敵対検証・飛猿context source markerバグ(3件中認識1消失2)調査。数値不変74%(28.0/38)=checker照合**
- **v5.04 (2026-08-03 18:19): 進捗同期(GATE CLEAR 5件18:06-18:16): ①B4=post-signal backfill実装(cardinality violation是正込み)+78PF checkpoint一発CLI束縛(三辺束縛・正常1/1・故障11/11 BLOCK・60cdebe7)の両GATE CLEAR→real 78PF producer実行中 ②C-x=W3 rows0根因一意確定(世代不整合: runner END 8/3 vs snapshot SPY max 7/31)+反実仮想63判定でcalendar-max clamp一意採用+prod readonly parity確認→clamp方式W3再走へ ③インフラ=three_layer preflightキャッシュ破損のcache selfheal恒久修正GATE CLEAR。数値不変74%(28.0/38)=checker照合**
- **v5.03 (2026-08-03 18:00): 進捗同期(家老一次更新blt_175232+陣形図17:52): ①B4=ext4再走で10/10生成成立、才蔵独立レビューがbulk UPSERT内キー二重投入cardinality violation経路をcommit前検出→疾風修正中(本番書込み前捕捉・実害なし) ②C-x=W1全canonical Normal月GATE CLEAR(16:54)→W2解禁→W3実走中、generation実測=processed 21/21・errors 0・parent_empty 21/21・fail 1・production_write 0 ③前倒し準備完了=W4-W5 oracle(小太郎)・B5 rejection gate(飛猿)・78PF prebind(小太郎)。数値不変74%(28.0/38)=checker照合**

- **v5.02 (2026-08-03 16:52): ★殿deadline+加速4裁定反映: ①deadline=JST22:30(米国市場開場)前に全38工程完了・逆算スケジュール§0.1 ②AC/報告契約最小化(殿指摘16:47: recon/prep系の書式往復禁止・成果直接吸い上げ=運用規律(6)) ③D-x2波分割(standard先行/FoF後続=規律(7)) ④極限並列=idle0名維持+前倒しprep配備(D0計画=疾風・C9準備=影丸) ⑤B4 Track B=drvfs worktree障害特定→ext4再走。数値不変74%(28.0/38)=checker照合**
- **v5.01 (2026-08-03 16:37): 家老v5.00 REVISE 3 BLOCKER反映: ①B4=10PF初回generated7/10・omission3・task failed→3PF snapshot非生成調査→10/10再成立を次関門に同期(78へ直行しない) ②C-x=全Standard N=12 GATE CLEAR(16:18:04)→全canonical Normal月拡大中へ同期 ③gist非同一の正体=gist説明文が旧v1.3のまま(gh gist viewが説明文を先頭出力)→説明文を版非依存の現行文へ更新+content再同期。数値不変74%(28.0/38)=checker照合**
- **v5.00 (2026-08-03 16:32): ★覚醒改稿(殿下知16:25『肥大化解消・前提知識ゼロで読める・読み飛ばし/要約でも誤解しない形式へ』): ①§0現在地=v4.56-v4.99の追記チェーン(約22KB)を廃しスナップショット型へ(進行中2工程の現況+検証運用規律+次関門のみ) ②棄却済み仮説一覧を新設(price欠落・successor実在・保存層FAIL・方式欠陥・980b証跡の5件を棄却根拠付きで明示) ③WBS B4/C-x Statusセルの経緯連結を現況+参照へ圧縮 ④§0.1の旧見込み時間(v4.56時点)を現況へ更新 ⑤情報量削減ゼロ保証=旧チェーン+旧セル生テキストをdocs/research/dm-monthly-trade-bug-genko-chain-archive_20260803.mdへ全文退避+§7は全版保持。数値不変74%(28.0/38)=checker照合**
- **v4.99 (2026-08-03 16:18): 家老v4.98 APPROVE付帯の進捗同期: B4 1PF anchor正実証=GATE CLEAR(16:14:04)・C-x W1全Standard N=12成果+軍師LGTM。二本とも最小標本成立→段階拡大フェーズへ。数値不変74%(28.0/38)=checker照合**
- **v4.98 (2026-08-03 16:10): ★殿指摘(16:05)反映=price欠落根因説撤回: 本番参照必要13symbolは2026-07完全(missing0)、missing110は非参照historical混入の偽母集団。July successor不在は市場開始前で正常。IEF backfill成果は本線算入禁止。C-x W1 7lane GATE CLEAR(15:55)+B4 1PF正実証done同期。根因はwall-clock整合へ回帰、満月2026-06路線が独立有効。数値不変74%(28.0/38)=checker照合**
- **v4.97 (2026-08-03 15:46): 家老v4.96 REVISE 3 BLOCKER反映: ①保存層FAIL説撤回(saved rows0=historical baseline 0件。W1最小機構PASS) ②W1拡大禁止→W1 7lane段階拡大中へ訂正(W2のみW1全Standard同月完成まで禁止) ③B4=影丸1PF anchor正実証並列配備(殿下知15:38)+才蔵1pair PASS→IEF22日拡大を同期。数値不変74%(28.0/38)=checker照合**
- **v4.96 (2026-08-03 15:38): 家老v4.95 REVISE 2 BLOCKER反映: ①WBS B4 Status=旧D-RC実行中表記→price取得層修復の最小実験→段階拡大→同一世代snapshot再固定待ちへ同期 ②WBS C-x Status=旧監査/probe表記→missing110確定+半蔵W1最小実験(DM4生成1・oracle exact1/1・hash2/2・runner4/4だがproduction saved rows0/exact0/1=保存層FAIL)へ同期。W1拡大禁止維持。数値不変74%(28.0/38)=checker照合**
- **v4.95 (2026-08-03 15:32): ★7月price欠落確定同期(飛猿監査GATE CLEAR 15:28:32): expected396(18symbol×SPY正準22日)/actual286/missing110。IEF・SOXX・XLE・XLK・XLV=各22/22全欠落。根因境界=snapshot以前のprice universe選定(data_fetcher現portfolio config由来)へ確定移動。最小実験2本同期=才蔵: 2026-07 IEF×07-01正規fetcher隔離1pair、半蔵: C-x W1正規generator Normal 2026-06 1PF×1month clone。数値不変74%(28.0/38)=checker照合**
- **v4.94 (2026-08-03 15:07): 家老v4.93 REVISE 1 BLOCKER反映: §0 v4.92継承文とWBS C-x行の『実在successor有』断定を『当時仮説・小太郎materialize実測(txid1092151・July successor 0/24)で棄却』へ明示訂正(代表銘柄実測は全銘柄充足を証明しない)。家老采配同期=飛猿: 2026-07 prices全銘柄×全営業日readonly全数監査、影丸: 満月2026-06のB4 1PF+C-x W1 1lane×1month最小標本(Partial/MTD混入0)。数値不変74%(28.0/38)=checker照合**
- **v4.93 (2026-08-03 15:02): ★殿裁定(14:59)反映: ①2026/7全price取得の全数確認を最優先偵察へ(小太郎materialize=txid1092151・July successor 0/24 FAILと整合) ②最小標本ループの標本は満月(Normal)限定 ③Partial/MTDは別レーン検証(混合は切り分け不能)。数値不変74%(28.0/38)=checker照合**
- **v4.92 (2026-08-03 14:52): 家老v4.91 REVISE 2 BLOCKER反映: ①§0からv4.90由来の旧記述(『配備infra BLOCK是正中』『実装RC飛猿配備済み』)を除去完遂(記録は本§7 v4.89-v4.91が保持) ②base snapshot現況同期=影丸clone契約実験はusable base 0/93 FAIL終端(14:43軍師レビュー済)→才蔵inventory継続+小太郎production同一transaction materialize進行中。数値不変74%(28.0/38)=checker照合**
- **v4.91 (2026-08-03 14:44): 将軍発行(正本writer責務同期・家老blt_143721指摘反映): ①§0自己矛盾解消(『配備済み』と『撤回』併存→時系列正記述へ) ②C-x hotfix=snapshot staleでFAIL終端(unit76/76・matrix1/8・W1 0/12・W3 0/21・lane 0/7)を同期 ③本番read-only実測=実在successor有(正準組合せ前提は本番上で成立)→base snapshot固定後に再走 ④★殿裁定(14:45-14:48)=検証運用転換: 最小標本仮説検証ループ+段階拡大+W段階直列(W1完璧→W2)。全数は最終checkpointのみ。数値不変74%(28.0/38)=checker照合**
- **v4.90 (2026-08-03 14:12): 家老v4.89 REVISE 1点+構造仮説両者回答反映: ①C-x hotfix配備済み表記撤回(deploy rc2 rollback=配備infra BLOCK是正中) ②同一根因=7実験収束で確定(軍師HIGH・家老YES) ③共通仕様=immutable base snapshot 1回固定→B4/C-x別clone fork・base hashをC9/C2まで継承を採用。数値不変74%(28.0/38)=checker照合**
- **v4.89 (2026-08-03 14:09): 家老v4.88 REVISE 2点反映: ①B4=clean D-RC f9f9b325 FAIL終端・3方式+閉包全てanchor0/24→真因=snapshot世代不整合・再開条件=同一世代snapshot(才蔵棚卸し中) ②C-x=正準組合せ確定(as_of=end_date+successor有)→実装RC飛猿配備でstale解消。数値不変74%(28.0/38)=checker照合**
- **v4.88 (2026-08-03 14:02): 家老v4.87 REVISE 1点反映: WBS B4 Status=旧D配備記述stale→『980b採用除外・旧D FAIL(a8cf70de)→clean content identity起点のD-RC(transitive_boundary_closure_rc)進行中』へ同期。数値不変74%(28.0/38)=checker照合**
- **v4.87 (2026-08-03 14:00): 家老blt_135628反映(B4 commit汚染検出): 980b4110=git object実測8path(expected B4 4+unexpected C-x 4)でscope限定性主張無効→B4採用証跡から除外・現HEAD B4 4成果hashをclean起点再固定・closure実験AC2-4は新RC継続。影丸D=AC1前提不一致を正しくBLOCK(a8cf70de)。数値不変74%(28.0/38)=checker照合**
- **v4.86 (2026-08-03 13:57): 家老v4.85 REVISE 1点反映: WBS B4 Status=『同一cmd RC再走中』stale→『本体FAIL確定(commit 980b4110・A/B anchor0/24)→独立実験A/B/C/D突合中(D=全推移依存閉包=影丸13:50:45新規配備)』へ同期。§0現在地の組合せ収束方向と整合。数値不変74%(28.0/38)=checker照合**
- **v4.85 (2026-08-03 13:51): 家老v4.84 REVISE(現在地1点)+協議反映: ①C9/C2 handoff side=GATE CLEAR(13:44:48)同期 ②B4 RC方向=A/B/C突合→組合せ1本収束(将軍承認blt_135041・78PF縮小なし) ③C-x=母集団0件の非空性BLOCK+飛猿根因偵察並走 ④GA-220復旧注記。数値不変74%(28.0/38)=checker照合**
- **v4.84 (2026-08-03 13:41): 家老v4.83 REVISE反映(terminal→RC遷移+side CLEAR同期): ①B4本体=PF78/78完走・anchor0/24 FAIL(next_boundary欠落)→RC中 ②C-x W5=83/83 OOS空虚比較FAIL(月母集団SSOT欠落)→全履歴月SSOT RC中(疾風13:33) ③飛猿handoff=runner mapping RC中 ④side CLEAR3(B4 harness 6447e5ca/B5 preflight/D-x topology)。B4/C-x=in_progress据置・74%不変=checker照合**
- **v4.83 (2026-08-03 13:07): 巡回反映(殿指示13:05=版発行規律の殿例外): ①B3=GATE CLEAR(12:57:49一次確認)→CLEAR27 ②B4=影丸12:59配備で進行中へ(隔離full78ドライラン=裁定7段順序模擬) ③C-x分類RC=分身/加速差CLEAR、W1-W5=疾風実行中 ④side偵察FAIL2(才蔵harness 3-strike/飛猿handoff通知BLOCK・成果永続化済み)を注記。進行中2(B4/C-x)・score28.0・74%=checker照合**
- **v4.82 (2026-08-03 12:51): 家老v4.81 REVISE 1 blocker反映: §2.3 Wave表W4入力=本番DB(readonly)→C9同一隔離snapshot/W1-W5生成成果へ置換(WBS C2-x行との矛盾解消)。数値不変71%(27.0/38)=checker照合**
- **v4.81 (2026-08-03 12:45): 家老v4.80 REVISE 2 blocker反映: ①B2b=GATE CLEAR(12:33一次確認)+B3=影丸12:35配備in_progressへ同期→CLEAR26・進行中2(B3/C-x)・score27.0・71% ②隔離W1-W5契約を5項二値化(snapshot時刻/hash・code/config SHA・production write0・21/21完全性・順序)+C9/C2-xへ同一隔離dataset継承を明記(C2-x Startの本番DB stale撤去)。checker照合PASS**
- **v4.80 (2026-08-03 12:42): 家老v4.78追加REVISE反映(C-x前提崩れ・blt_123923): 半蔵入力生成偵察GATE CLEAR(commit 8d68e22c)=一次SQLで21/21PF・7/7laneのL1 actual行0+L0完全入力月0。将軍裁定=案A(隔離snapshot上でW1-W5実行しC-x検証。本番writeはD系7段順序のみ=A0-4b裁定と無衝突)。案B(C-xをD系後へ移動)は不採=D系本番実行前のL1検証を失いリスク増。C-x Start列を隔離W1-W5へ改訂・GATE=W5までBLOCK・OUT_OF_SCOPE丸め禁止明記。数値不変68%(26.0/38)=checker照合**
- **v4.79 (2026-08-03 12:38): 家老v4.78 REVISE 3+1点反映(WBS本文契約の裁定同期): ①A0-4b作業/Goalセル=旧混合route文言(層別/年月単位/restore路/D省略経路)を撤去し78PF再生成固定+24anchor+7段順序へ置換 ②B4=7段順序模擬・24anchor誤差ゼロ・各段件数(78/24/1249/72/72)・非意図差分0を作業/Goalに二値契約化 ③D0=対象78PF固定・D省略なし・方式選択提示不要へ訂正 ④D-x=anchor行の同一transaction内検証+guard/apply/ledger/cacheはD-x全完了後の全体順序(裁定4-6段目)としてcommit境界分離を明示。軍師v4.78 APPROVE(blt_123452)は機械数値のみ=意味論見落としと家老指摘。数値不変68%(26.0/38)=checker照合。仕様変更=WBS契約文言の裁定同期のみ**
- **v4.78 (2026-08-03 12:31): ★殿裁定反映: A0-4b=GATE CLEAR(裁定12:29「A0-4b=全78PF再生成route(24行はanchor検証)で進めよ」)。route=78PF一本化再生成・24行=受入anchor兼rollback証跡・実行順序7段固定・B4順序模擬。根拠=家老cross-tab(blt_122742)で旧混合routeの実行粒度の穴(mixed24PF)確定→一本化で解消。レーンA0=100%。三層記憶=knowledge:9b63e663。CLEAR25・進行中2(B2b/C-x)・score26.0・68%=checker照合。仕様変更=A0-4b Status確定のみ**
- **v4.77 (2026-08-03 12:24): 軍師v4.76 REVISE反映(意味論訂正): ①FAIL4の真因=『入力不足』→『分類順序バグ』へ訂正(飛猿root recon確定: 未開始predicateよりL0欠落判定を先行する分類順序バグ。7lane×4cases=28照合・誤分類4lane) ②変わり身=歴史的FAIL(runner receipt欠落)と現RC成果(小太郎runner17/17 PASS・FAIL0・SKIP0・rc0=post-review待ち)を分離記載 ③§0現在地/§0.1レーンC/WBS C-x行を同期。数値不変66%(25.0/38)=checker照合。仕様不変**
- **v4.76 (2026-08-03 12:16): 復帰後是正+巡回#37反映(家老[URGENT-HARM]下知12:15対応): ①C-x=未着手→進行中(v4.75発行後に7/7レーン配備・全報告到着: PASS2=追い風GATE CLEAR 12:03:50+四つ目レビュー待ち/FAIL5=入力不足4+変わり身runner receipt欠落。是正3系統+加速率分類RC並列中) ②B2b=旧run 30775109993 REDのstale解消(commit 6a701659=FAIL5→PASS5・後続CI run 30780850616 GREEN=将軍gh view一次確認。影丸task終端failed=報告契約でpost-review待ちのため進行中維持) ③C9=preflight GATE CLEAR(11:49:29)注記。CLEAR24・進行中2(B2b/C-x)・score25.0・66%=checker照合。仕様不変**
- **v4.75 (2026-08-03 11:32): 巡回#36反映: ①C0=GATE CLEAR(11:30:11掲示板一次確認。飛猿・軍師LGTM 11:27:55)→C-x Start解放 ②Cx oracle lane preflight=GATE CLEAR(11:26:45)。CLEAR24・進行中1(B2b)・score24.5・64%=checker PASS。仕様不変**
- **v4.74 (2026-08-03 11:17): 巡回#35反映: ①A5=GATE CLEAR(11:11:20掲示板一次確認)→レーンA完走100%・L0確定宣言 ②C0前段偵察=GATE CLEAR(11:15:14)・C0本体=飛猿acknowledged→Cレーン開始(進行中0.5) ③Cx oracle lane preflight=才蔵実行中(母数外)。CLEAR23・進行中2(B2b/C0)・score24.0・63%=checker PASS。仕様不変**
- **v4.73 (2026-08-03 11:05): 巡回#34反映: ①A5本体=飛猿成果完了PASS(133=104+0+4+25統合・unique133・SHA 7af587e2 2/2・runner17/17)・レビュー待ち ②A5/B4 preflight=GATE CLEAR(11:01:45/10:59:16) ③C0 L1レーン契約偵察=疾風配備・in_progress(C系前倒し)。v4.72=両名APPROVE確定。数値不変61%(23.0/38)=checker PASS。仕様不変**
- **v4.72 (2026-08-03 10:58): 軍師v4.71 REVISE 3点反映: ①A5本体=飛猿10:51:37配備・進行中(進行中2=B2b/A5・score23.0・61%) ②A5 preflight=才蔵10:48:53完了(validator133=104+0+4+25・4条件4/4) ③A0-4b裁定資料cmd=GATE CLEAR(10:48:46)へ同期。checker PASS。仕様不変**
- **v4.71 (2026-08-03 10:48): 巡回#33反映: A0-4b裁定資料完成(疾風10:45軍師LGTM。Start 5/5一次再検証・8,951行route候補・source/output hash台帳付き・production変更0/DB write0)。B4 preflight=小太郎done、A5 preflight=才蔵実行中を同期。recon類はWBS母数外につき数値不変59%(22.5/38)=checker PASS。仕様不変。次手=殿へroute裁定提示**
- **v4.70 (2026-08-03 10:33): 巡回#32反映: A4=GATE CLEAR(照合RC3 10:31:25掲示板一次確認+疾風task idle)→レーンA1-A4完結・A5 Start解放(配備=家老采配)。B2e ci_fix RC2=半蔵軍師LGTM(side lane)。CLEAR22・進行中1(B2b)・score22.5・59%=checker PASS。仕様不変**
- **v4.69 (2026-08-03 10:27): 家老v4.68 REVISE反映: A4照合RC3=疾風成果完了(10:21:20到着)・実行中→post-review待ちへ同期。結果=対象4/4 join・一次根因=RC1 saved列選択4/4・production修正0・B2b自然解消0・pytest17 PASS/FAIL0/SKIP0・commit 61990549。乖離帰属は才蔵説(oracle列対応誤り)へ一本化、飛猿説(B2b自然解消)は照合で否定。A4=GATE未CLEARゆえ進行中0.5維持、数値不変58%(22.0/38)=checker PASS。仕様不変**
- **v4.68 (2026-08-03 10:21): 家老v4.67 REVISE 3点反映: ①§0.1レーンA=照合RC3疾風実行中へ同期 ②レーンB=CI-RC影丸実行中(FAIL5是正)へ同期 ③SG-PRE35=LGTM→GATE CLEAR(gate_metrics 10:15:34、設計書mtimeより前のCLEAR確定)へ是正。数値不変58%(22.0/38)=checker PASS。仕様不変**
- **v4.67 (2026-08-03 10:17): 巡回#30反映: ①A4才蔵RC2=GATE CLEAR(10:12:29掲示板一次確認) ②照合RC3=疾風10:10配備・acknowledged(A4工程は照合完了まで進行中を維持) ③SG-PRE35 hotfix=小太郎軍師LGTM(10:08:35・side lane)。進行中2(A4/B2b)のまま数値不変58%(22.0/38)=checker PASS。仕様不変**
- **v4.66 (2026-08-03 10:05): 巡回#29反映: ①A3=GATE CLEAR(10:00:40掲示板一次確認)→レーンA残=A4のみ ②A4=才蔵RC2軍師LGTM(10:02:39)+飛猿companion=分析独立再現完了(乖離=終端価格snapshot・B2b自然解消4/4)だがrunner task帰属選択0件rc=2で契約FAIL→両者の乖離帰属の同一性照合を家老突合の最終確定条件として明記 ③B2b=影丸acknowledged(CI fix再走)。CLEAR21・進行中2(A4/B2b)・score22.0・58%=checker PASS。仕様不変**
- **v4.65 (2026-08-03 10:00): 家老v4.64 REVISE反映(A4 assumption invalidation): 才蔵RC2=RC1 mismatch4の真因はoracle列対応誤り(open oracle vs close列比較)であり本番境界バグではない。正対応=open/open・close/close両系列4/4 exact・最初の乖離段price_field_selection 4/4・B2b overlap0・production変更0・commit 22aa64c5。v4.62-64の「境界バグ実在の一次証拠」記述を撤回。飛猿companion相互突合待ちでA4最終確定は保留。A3=両承認・GATE再実行中へ同期。数値不変57%(21.5/38)=checker PASS。仕様不変**
- **v4.64 (2026-08-03 09:54): 家老v4.63 REVISE(terminal更新)反映: ①A3=成果完了(疾風09:50:50・旧Partial17=Partial0+未開始17・runner4/4・commit 023e258f)・post-review待ち ②B2b=CI fix中へ降格(後継CI run 30775109993 RED・失敗5件=next_boundary_date未導出4+restore空1、fix draft軍師レビュー中) ③A4=才蔵RC2+飛猿companionの二頭並列を同期。進行中3(A3/A4/B2b)のまま数値不変57%(21.5/38)=checker PASS。仕様不変**
- **v4.63 (2026-08-03 09:47): 家老v4.62 REVISE(terminal更新)反映: ①A0-2=GATE CLEAR 09:41:15+A2=09:36:36再確定+B2a=09:42:13(いずれもCI run 30774708605 GREEN・archive.done確認)→**A0-4b Start前提全充足=殿route裁定の入口開放** ②B2b本体=影丸成果完了(09:44:34・commit d3343c1f・runner17/17・FAIL0/SKIP0)・post-review待ち→進行中 ③A3=疾風RC・A4 mismatch原因RC2=才蔵・SG-PRE35 hotfix=小太郎の並列3配備を同期 ④B3=B2b archive直後配備(monthly_returns/test path衝突回避)。CLEAR20・進行中3(A3/A4/B2b)・score21.5・57%=checker PASS。仕様不変**
- **v4.62 (2026-08-03 09:32): 巡回#26反映: ①**CI run 30774321365=success(GREEN到達、headSha=c7544d3b。gh run view一次確認)**→A0-2/A2/B2aのCI RED BLOCK解消、各GATE再実行/判定待ちへ ②A4 RC1=小太郎正直FAIL fail-close(計算不能0・不足0だがexact0/mismatch4=MTD4件全行で本番値とオラクル不一致=境界バグ実在の一次証拠。DB write0・hash2/2・contract4/4)→RC待ちへ降格、次手=mismatch原因RC(家老采配) ③B2b偵察=軍師LGTM 09:28:08+家老ACCEPT 09:30:20・GATE再実行中 ④半蔵post-review=SG-PRE35がDM-Signal既存testを新規扱いする誤検出でinfra hotfix事前レビュー中(side lane) ⑤家老v4.61 REVISE(09:32:47)の指摘は本版①②③で同期済み。CIは将軍gh run view一次確認でconclusion=success確定(家老09:31観測のin_progressより後の終値)。CLEAR17・進行中3(A0-2/A2/B2a)・score18.5・49%=checker PASS。仕様不変**
- **v4.61 (2026-08-03 09:25): 家老v4.60 REVISE 2点反映: ①B2a=rootfix成果完了(半蔵09:20:19報告・commit 85a15e50・runner8/8・243,293行mismatch0)・push済み・新CI run 30774321365 in_progress・軍師レビュー+CI待ちへ同期 ②B2b=前段偵察成果完了(影丸09:21:29・caller3/3・置換点6/6・fixture6/6・runner13/13・commit c7544d3b)・軍師レビュー待ちへ同期。数値不変50%(19.0/38)=checker PASS。仕様不変**
- **v4.60 (2026-08-03 09:20): 殿下知(並列速度改善)の采配結果反映: A4 RC=小太郎09:17:36正式配備(task acknowledged一次確認)→進行中。A3=疾風の旧報告未archive保護で安全BLOCK(上書き防止)→archive後配備予定。B3本体・CI companion=空席待ち(companion=軍師APPROVE receipt draft固定済み・最初の解放忍者へ即配備)。CLEAR17・進行中4(A0-2/A2/A4/B2a)・score19.0・50%=checker PASS。仕様不変**
- **v4.59 (2026-08-03 09:15): 家老v4.58 REVISE反映: A2状態stale是正=『formal approval再記録中/GATE判定待ち』→『成果・両承認完了(軍師formal 09:03:05・家老ACCEPT 09:09:26)、GATE実測09:11:16=CI run 30773553277 RED BLOCK、ci_fix companion軍師レビュー中』。数値不変49%=checker PASS。仕様不変**
- **v4.58 (2026-08-03 09:11): 家老v4.57 APPROVE付帯反映: ①B3前段偵察=GATE CLEAR(09:02:58、cmd_quality_log gate:CLEAR一次確認)→B3本体RC入口確保 ②A2=軍師LGTM 09:03:06(formal approval再記録中)・家老GATE判定待ちへ精密化 ③B2b=前段偵察を影丸実行中(陣形図09:10一次確認)。偵察はWBS母数外のため数値不変49%(18.5/38)=checker PASS。仕様不変**
- **v4.57 (2026-08-03 09:02): 巡回#22反映: ①A2四分類RC=成果完了(疾風task done・報告gate PASS 08:57:08。133行=Normal104/Partial0/MTD4/未開始25、要調査/未分類/重複/欠落0=前提回復確定classと完全一致)→進行中(レビュー/GATE判定待ち)へ ②B3前段偵察(fallback inventory refresh)=小太郎完了・軍師LGTM 08:58:44・家老GATE判定待ち。CLEAR17・進行中3(A0-2/B2a/A2)・score18.5・49%=checker PASS。仕様不変**
- **v4.56 (2026-08-03 08:52): 家老v4.55 REVISE反映: A0-4b Start未充足の先取り誤記を是正(『材料完成/入口到達』→『Sレーン材料完成、入口はA0-2 CLEAR待ち』。Start前提=A0-2+A0-2p+A0-3+S2/S3でA0-2本体のみ未CLEAR)。表題・§0・§0.1見込みを同期。数値不変47%(18.0/38)=checker PASS。仕様不変**
- **v4.55 (2026-08-03 08:48): 巡回#21反映: S3=GATE CLEAR(08:39:03、cmd_quality_log gate:CLEAR一次確認)→Sレーン100%・A0-4b殿route裁定の材料完成。S3成果=guard 1,249/apply 72(和1,321・未分類0)。進行中2(A0-2/B2a)、CLEAR17・score18.0・47%=checker PASS。小太郎=B3偵察へ再配備を注記。仕様不変**
- **v4.54 (2026-08-03 08:34): 巡回#20反映: S3=成果完了へ同期(小太郎報告08:23到着・task done・軍師LGTM 08:30:08掲示板一次確認・家老ACCEPT/GATE判定待ち)。GATE未CLEARのため0.5維持=数値不変46%(17.5/38)=checker PASS。見込みをS3 GATE判定のみ(分単位)へ更新。仕様不変**
- **v4.53 (2026-08-03 08:24): 家老v4.52 REVISE 2点反映: ①§0.1見込みの「S1-S3(未配備)・家老采配待ち」staleをS3実行中起点へ更新(A0-4b入口まで残30-60分) ②B2b=空き待ち→draft軍師レビュー中(08:20:37)。復帰点knowledge=79dd3dcaを§0へ記載(殿「強くてニューゲーム」saveの一環)。数値不変46%(17.5/38)=checker v4 PASS。仕様不変**
- **v4.52 (2026-08-03 08:21): 家老v4.51 REVISE 2点反映: ①§0現在地のS2自己矛盾(CLEAR宣言後に進行中/未配備=S3残存)を解消 ②S3=進行中(小太郎08:13:39正規配備・1,321件全数処理開始)。検証値=母数38・CLEAR16件・進行中3件(A0-2/B2a/S3)・score17.5・46%=checker v4 PASS(家老算術と一致)。仕様不変**
- **v4.51 (2026-08-03 08:16): 巡回#19反映: S2=GATE CLEAR(gate_metrics 08:09:30一次確認。シグナル影響三分類全数表完成)→S3(殿への規模報告=A0-4b裁定材料の最終工程)のStart解放。検証値=母数38・CLEAR16件・進行中2件(A0-2/B2a)・score17.0・45%=checker v4 PASS。仕様不変**
- **v4.50 (2026-08-03 08:00): 家老v4.49 REVISE 2点反映: ①表題の「S2=裁定材料の最終工程」を是正(W2=S1→S2→S3、A0-4b Start=S2/S3のため最終工程はS3) ②runner根治hotfixをB2a括弧から分離しinfra side lane注記へ。付帯: B2a=半蔵RC2(8,578全数ledger期待分類)07:57:47配備・作業開始。数値不変43%(16.5/38)=checker v4 PASS。仕様不変**
- **v4.49 (2026-08-03 07:56): 家老v4.48 APPROVE付帯反映: S2=進行中(軍師APPROVE後、小太郎へ07:51:13正式配備・実作業開始)。外部contract runner根治hotfix=影丸07:54:42配備をB2a注記へ。検証値=母数38・CLEAR15件・進行中3件(A0-2/B2a/S2)・score16.5・43%=checker v4 PASS。仕様不変**
- **v4.48 (2026-08-03 07:51): 家老v4.47訂正版REVISE反映: ①A1=GATE CLEAR(gate_metrics 07:47:36一次確認=Aレーン初CLEAR) ②§0/§1dの「暫定」「見込み」自己矛盾を削除し確定式一本(Normal104+未開始25+MTD4)へ統一 ③S2=draft軍師レビュー中を追記。検証値=母数38・CLEAR15件・進行中2件(A0-2/B2a)・score16.0・42%=checker v4 PASS(家老算術と一致)。仕様不変**
- **v4.47 (2026-08-03 07:48): 巡回#17+家老v4.46 REVISE反映: ①S1=GATE CLEAR(gate_metrics 07:45:40一次確認。17,902行dual replay完了=Sレーン初CLEAR。S2のStart解放) ②A1=RC3成果完了(774/774・contract4/4・commit 2e951c51・両名承認)・GATE実行中 ③§0の前提回復「暫定」表現を確定へ(Normal104+未開始25+MTD4。A2工程再CLEARは未了と区別)。軍師v4.46=疑義ゼロ。検証値=母数38・CLEAR14件・進行中3件(A0-2/A1/B2a)・score15.5・41%=checker v4 PASS。仕様不変**
- **v4.46 (2026-08-03 07:46): 家老v4.45 REVISE 3点反映: ①レーンA/S注記の実行中stale解消(前提回復RC2=29/29確定・レビュー閉鎖待ち/S1=軍師LGTM+家老ACCEPT・GATE実行中) ②A3のGoal列本体を改訂(旧「Partial全行誤差ゼロ」の空虚PASS再生を根絶: 未開始証明添付+Partial0+未分類0、対象>0時のみオラクル突合) ③A4の「全数一致/計算不能0」先取り記載を撤回(確定は対象4件・primitive不足0まで。一致判定はA4 RC未実行=未確認)。数値不変39%(15.0/38)=checker v4 PASS。仕様不変**
- **v4.45 (2026-08-03 07:43): 家老v4.44 REVISE 2点反映: ①前提回復RC2=29/29確定・commit済み(軍師条件付きLGTM・レビュー閉鎖待ち)/S1 RC2=成果完了(17,902行・3回hash一致・commit済み・報告レビュー中)へ同期(GATE未CLEARは維持) ②A3 Goal=空虚PASS防止(Partial対象0件+未分類0を証跡付き確認へ改訂。対象0の根拠=operational_start全数証明の添付必須)。A4=確定MTD4のみ突合と明記。数値不変39%(15.0/38)=checker v4 PASS。仕様不変**
- **v4.44 (2026-08-03 07:41): 家老v4.43 REVISE 3点反映: ①A2のWBS作業/GoalをNormal+Partial+MTD+未開始=133の§0.6四分類へ改訂+operational_start照合を分類手順に必須化(三分類Goalのままでは同じ不成立を再生するため=根本是正) ②A1=RC3実行中(小太郎07:34:04配備) ③A3/A4注記=前提回復RC2疾風in_progressへ同期。検証値=母数38・CLEAR13件・進行中4件(A0-2/A1/B2a/S1)・score15.0・39%=checker v4 PASS。仕様不変(§0.6の四分類定義に準拠する既存Goal是正)**
- **v4.43 (2026-08-03 07:33): 家老v4.42 REVISE 2点反映: ①A2=GATE CLEAR→RC待ちへ降格(gate CLEARは事実だがGoal「Normal+Partial+MTD=133」の三分類が前提回復一次全数結果(未開始25+MTD4)で不成立と実証。§1d invalidatedとCLEAR保持の矛盾解消。RC再確定後に再CLEAR) ②前提回復RC2=疾風へ07:31:38配備済み(draft review待ちstale解消)。軍師v4.42=疑義ゼロ。検証値=母数38・CLEAR13件・進行中3件(A0-2/B2a/S1)・score14.5・38%=checker v4 PASS(家老算術と一致)。仕様不変**
- **v4.42 (2026-08-03 07:31): 家老v4.41 REVISE 3点反映: ①§0のA1「RC実行中」残存矛盾を除去 ②A3/A4=前提回復FAIL ACCEPT済み(07:27)→前提回復RC2 draft review待ちへ同期 ③§1d/A3/A4=全数一次結果(Normal104+未開始17+旧MTD12(暫定MTD4+未開始8)。暫定確定class=未開始25+MTD4)へ断定レベル同期。軍師v4.41=疑義ゼロ。数値不変41%(15.5/38)=checker v4 PASS。仕様不変**
- **v4.41 (2026-08-03 07:29): 家老v4.40 REVISE+A1 RC2判定反映: ①A4のMTD月別内訳の旧仮定(2026-08=5/2026-07=7)は疾風一次再集計(rows29・unique29・MTD 08=8/07=4・ac1_match=false)と不一致=断定を外し差異検証中へ(§1d/A4欄/履歴) ②A1=RC2 FAIL ACCEPT(成果774/774 exact・hash一致は不変。未達=multi-agent runnerのexternal_scope_no_mapped_testsでselection0/rc2→commit0)→RC3=A1固有contract file直接固定実行4/4方式で準備中。検証値=母数38・CLEAR14件・進行中3件(A0-2/B2a/S1)・score15.5・41%=checker v4 PASS。仕様不変**
- **v4.40 (2026-08-03 07:22): 家老v4.39 REVISE 2点反映: ①§0.1レーンAの「報告契約不備」stale除去 ②A1=RC2実行中へ(小太郎07:20:40配備を家老capture一次確認)。検証値=母数38・CLEAR14件・進行中4件(A0-2/A1/B2a/S1)・score16.0・42%=checker v4 PASS(家老算術と一致)。仕様不変**
- **v4.39 (2026-08-03 07:21): 家老v4.38 REVISE反映: A1のRC理由是正=report形式不備(v4.38記載)はstaleで、家老が07:14に正規化しgate PASS済み。真の残件=reflux prepare timeout(rc124)によるscope commit 0→根因解消後の再commit RC。付随: A3/A4の29件前提回復=疾風in_progress(07:17:02)。数値不変41%(15.5/38)=checker v4 PASS。仕様不変**
- **v4.38 (2026-08-03 07:17): 巡回#15反映: ①A1=RC待ちへ(小太郎task failed=報告cross_repo_commits契約不備。task YAML一次確認) ②A0-2=才蔵task done・GATE=CI BLOCK(07:04:39)待ちへ精密化。検証値=母数38・CLEAR14件・進行中3件(A0-2/B2a/S1)・score15.5・41%=checker v4 PASS。全体42%→41%、A=20%。仕様不変**
- **v4.37 (2026-08-03 07:14): 家老v4.36 REVISE反映: §0.1レーンS/WBS S1行の「配備待ち」stale解消→「本体RC2実行中(影丸07:11:49配備)」へ(家老capture一次確認済み)。数値不変=42%(16.0/38)=checker v3 PASS。仕様不変**
- **v4.36 (2026-08-03 07:12): 家老v4.35 REVISE反映: ①A3=RC待ちへ(fail-close 07:07: Partial17/17=blocked17。軍師FAIL受理済み。v4.35時点で見落とし) ②§1d=Partial+MTD29件全数をinvalidation検証中へ拡大 ③A3/A4は母数縮小なしの前提回復RC 1本へ束ね(家老方針)。検証値=母数38・CLEAR14件・進行中4件(A0-2/A1/B2a/S1)・score16.0・42%=checker v3 PASS(家老算術と一致)。全体43%→42%、A=30%。仕様不変**
- **v4.35 (2026-08-03 07:10): A4 fail-close一次報告(blt_070718)反映: ①A4=RC待ち(MTD12/12でexact0・計算不能12。5件=境界未形成→未開始再分類候補、7件=primitive価格未保存。fail-visible維持・commit 89c98364) ②§1dのA2確定内訳へassumption invalidation検証中を注記(確定はRC完了後) ③家老=7件primitive取得+5件再分類RC起票中。検証値=母数38・CLEAR14件・進行中5件(A0-2/A1/A3/B2a/S1)・score16.5・43%=checker v3 PASS。全体45%→43%(A4を進行中から除外)、A=40%。仕様不変**
- **v4.34 (2026-08-03 07:04): 家老v4.33 REVISE反映: ①§0.1レーンS行のstale解消(config是正中→前提再構成CLEAR済み・本体RC2配備待ち) ②A3=進行中(影丸)/A4=進行中(疾風) ③§1dへA2確定内訳を記載(Normal104+Partial17+MTD12=133・要調査0。旧暫定値は誤りと判明=無検証引用回避の書き方が機能)。検証値=母数38・CLEAR14件・進行中6件(A0-2/A1/A3/A4/B2a/S1)・score17.0・45%=checker v3 PASS。全体42%→45%、A=50%。仕様不変**
- **v4.33 (2026-08-03 07:02): 巡回#14反映: ①A2=GATE CLEAR(06:57:41)=133行三分類の証拠付き確定→§1dの暫定仮説注記を確定へ戻す(内訳はA2成果物が正) ②S1前提是正(config再構成)=CLEAR(06:56:33)、S1本体再走は家老采配 ③A3/A4のStart解放。検証値=母数38・CLEAR14件・進行中4件(A0-2/A1/B2a/S1)・score16.0・42%=checker v3 PASS。全体41%→42%、A=30%。仕様不変**
- **v4.32 (2026-08-03 06:43): 家老v4.31 REVISE反映: ①§1dの133件三分類断定を「A2 GATE CLEARまで旧報告由来の暫定仮説」へ格下げ(WBS A2との確定度矛盾解消) ②S1担当表現是正(旧影丸試行=config exact 8/8,951 FAIL_CLOSE/archive、現=疾風前提再構成) ③A2=進行中(影丸06:41:24)。検証値=母数38・CLEAR13件・進行中5件(A0-2/A1/A2/B2a/S1)・score15.5・41%=checker v3 PASS。全体39%→41%、A=20%。仕様不変**
- **v4.31 (2026-08-03 06:40): 家老一次証跡(blt_063919)反映: ①A0-2p=GATE CLEAR(06:36:22 gate_metrics確認済み。四分類=1,871+14+0+0・要調査0=A0-0aと同型の完全分類) ②A1=進行中(小太郎) ③S1=進行中だがhistorical pipeline_config欠落8,943/8,951行が判明→補助再構成cmd(疾風)で前提是正中。検証値=母数38・CLEAR13件・進行中4件(A0-2/A1/B2a/S1)・score15.0・39%=checker v3 PASS。全体36%→39%(15.0/38)、A0=83%、A=10%、S=17%。仕様不変**
- **v4.30 (2026-08-03 06:16): 巡回#11反映: A0-2p=進行中(疾風再走。初回failed=報告テンプレ未記入→将軍裁定で再配備) / A0-2補助hotfix(fof_oracle)=CLEAR(06:13:44) / ci4 hotfix=影丸failed→家老再処理中。検証値=母数38・CLEAR12件・進行中3件(A0-2/A0-2p/B2a)・score13.5・36%=checker v3 PASS。全体34%→36%(13.5/38)、A0=78%。※家老はA0-2 CLEAR同期を要請したがgate_metrics一次記録はhotfix(fof_oracle 06:13:44)のみでA0-2本体のCLEAR行なし=本体CLEARの一次証跡を家老へ問い返し中(GATE CLEAR未達をdone扱いしない規律=v4.18)。仕様不変**
- **v4.29 (2026-08-03 06:02): 巡回#10反映: B2e=GATE CLEAR(gate_metrics 05:58:13。ledger guard mode化+敵対fixture3種。前提=ownership gate hotfix 05:38:26+ci4対応)。B3=合同scope再配備可能へ。検証値=母数38・CLEAR12件・進行中2件(A0-2/B2a)・score13.0・34%=checker v3 PASS。全体33%→34%(13.0/38)、B=59%。仕様不変**
- **v4.28 (2026-08-03 05:24): 家老実態更新(blt_052336)反映: ①A0-2=進行中(才蔵へ正式配備=クリティカルパス次工程着手) ②B2e=単純GATE待ち→cross-repo ownership gate実装(半蔵)+CI残4 rootfix(影丸ci4 hotfix)へ精密化 ③B2a=CI残4件(20→4、fallback禁止維持rootfix軍師レビュー済み)。検証値=母数38・CLEAR11件・進行中3件(A0-2/B2a/B2e)・score12.5・33%=checker v3 PASS。全体32%→33%(12.5/38)、A0=72%。仕様不変**
- **v4.27 (2026-08-03 05:02): 家老v4.26 REVISE反映: ①B3=進行中→RC待ちへ是正(才蔵task failed一次確認+軍師FAIL。B2e CLEAR後合同scope再配備) ②レーンA/S注記「A0-1待ち」→「A0-1 CLEAR済み・配備待ち」(stale解消) ③checker v3=レーン注記の待ち理由IDがCLEAR済み工程を指すとFAILする検査追加(task/report terminal state照合はWBS ID→task名マッピングが動的なため家老側rg集計で補完と分担)。検証値=母数38・CLEAR11件・進行中2件(B2a/B2e)・score12.0・32%=checker v3 PASS(待ち理由stale検査含む)。全体33%→32%(12.0/38)、B=55%。仕様不変**
- **v4.26 (2026-08-03 04:57): 家老v4.25 REVISE反映: ①§0.1見込みのA0-1(進行中)stale解消=クリティカルパスをA0-2/A0-2p+S1-S3(未配備)起点へ更新・残1-1.5時間 ②checkerへ§0.1見込み内の進行中ID参照とWBS進行中集合の突合検査を追加(v2) ③B2c=GATE CLEAR(04:53:17)・B2e=task done・GATE待ちへ精密化。検証値=母数38・CLEAR11件・進行中3件(B2a/B2e/B3)・score12.5・33%=checker v2 PASS(見込みstale検査含む)。全体32%→33%(12.5/38)、B=59%。仕様不変**
- **v4.25 (2026-08-03 04:44): 家老v4.24 REVISE反映: ①§0現在地をv4.25発行時へ全面更新(2版連続stale再発の恒久防御=scripts/check_design_progress_consistency.py新設。版発行前に§0/tracker/WBSを機械照合) ②B2d=GATE CLEAR(04:37:30) ③B2a=CI RED BLOCK(04:36:40 run 30763603748、家老ci_fix対応中)を注記。検証値=母数38・CLEAR10件(A0-0a/0b/0c/A0-1/A0-3/A0-4a残件/B1/B2d/B3.5/B3i)・進行中4件(B2a/B2c/B2e/B3)・score12.0・32%=チェッカーPASS。全体30%→32%、B=55%。仕様不変**
- **v4.24 (2026-08-03 04:36): 家老v4.23 REVISE反映: ①gist SHA不一致の真因訂正=CDNキャッシュ説は誤因果、真因はfilenameなしview/raw出力の先頭にgist description+空行が付加されること(家老byte実測59900B vs 59573B、将軍再実証一致)。検証正本=--filename指定fetch ②A0-1=GATE CLEAR(04:30:58)=A0-2/A0-2p/S1-S3のStart解放 ③B2c=進行中(影丸)。全体28%→30%(11.5/38)、A0=67%、B=50%。仕様不変**
- **v4.23 (2026-08-03 04:27): 家老v4.22 REVISE 2点是正: ①§0現在地を版発行時刻へ更新しB1=GATE CLEAR・A0-1=task done/report完了/GATE CLEAR待ちへ精密化(04:12のstale解消) ②gist SHA検証=gh gist view -f指定でlocal一致(1eb74b11)を再実証。家老実測の不一致(419848cb)の原因当時推定=CDNキャッシュはv4.24で誤因果と判明(真因=description混入)、検証方法の正をview -fに固定・現在地へ注記。%不変(28%)。仕様不変**
- **v4.22 (2026-08-03 04:23): 家老v4.21 APPROVE付帯2点反映: ①B2a/B2d/B2e/B3=in_progress(家老goal配備。B2b/B2cは忍者空き待ち)。全体22%→28%(10.5/38)、B=45%(5.0/11) ②運用是正=毎版、家老+軍師両者のレビュー完了を待って次版へ進む(v4.20が家老レビュー完了前にv4.21で上書きされた反省。進捗は§0.1へ随時集約し、版発行はレビュー完了で束ねる)。仕様不変**
- **v4.21 (2026-08-03 04:16): 巡回#3反映: B1=GATE CLEAR(gate_metrics 04:13:04。boundary helper+単体テスト13/13 PASS・2022-04型fixture=4/4返却含む)。B2a-B2e/B3のStart前提解放。全体21%→22%(8.5/38)、B=27%。進行中=A0-1のみ。仕様不変**
- **v4.20 (2026-08-03 04:14): 家老v4.19 REVISE是正: 「W0全完了(7工程)」表現を§2.4正本に合わせ「W0 5/5(A0-0c/A0-3/A0-4a/B3i/B3.5)+W1のA0-0a/A0-0b=入口累計7工程CLEAR」へ分離(A0-0a/A0-0bはW1のためW0に含めない)。数値・仕様不変**
- **v4.19 (2026-08-03 04:12): 進捗反映: B3.5=GATE CLEAR(04:03:02)・B3i=GATE CLEAR(04:03:02)・A0-4a残件=GATE CLEAR(04:07:09。§0.6正本転記完了)=**W0全工程完了**。A0-1=Start充足で影丸へ配備(進行中)。B1=家老RC後13/13 PASS・軍師review_bundle再生成中(進行中)。全体16%→21%(8.0/38)、A0=61%、B=23%。仕様不変**
- **v4.18 (2026-08-03 04:00): 家老v4.17 REVISE 2点是正: ①表題「W0全完了」→「W0全配備(起票残0)」(A0-4a/B3i/B3.5はreport PASS/レビュー待ちでGATE CLEAR未達のため「完了」は偽) ②見込みクリティカルパスをA0-0a再走→からA0-4a残件CLEAR→へ更新(A0-0aはCLEAR済み)。数値・仕様不変**
- **v4.17 (2026-08-03 03:58): 家老v4.16 REVISE 2点是正: ①A0-0a(cmd_4220)=GATE CLEAR(gate_metrics 03:44:10・/cmd-complete済み)へ更新(v4.16時点で見落とし) ②「W0四工程」表現を是正(B1はW1=A0-0c後。正=A0-4a残件/B3i/B3.5がW0、B1がW1)。算術再計算=全体16%(6.0/38)・A0=50%(4.5/9)・B=14%不変。仕様不変**
- **v4.16 (2026-08-03 03:55): 進捗反映: A0-0b(cmd_4221)=GATE CLEAR(03:53:22。PF月17,379全走査・欠落0・執行ずれ月8,847件=A0-2/route裁定の母集団確定)。W0残四工程(A0-4a残件/B3i/B3.5/B1)=家老goal駆動karo_direct配備で全てin_progress(軍師draft APPROVE済み)。全体8%→14%、A0=44%、B=14%。仕様不変**
- **v4.15 (2026-08-03 03:42): 家老v4.14 REVISE 3点反映: ①A0-0c/A0-3のStatus=GATE CLEAR(gate_metrics一次記録03:22:33/03:34:16)へ更新+§0現在地同期 ②レーンA0=33%へ算術修正(3.0/9) ③見込み時間をgate_metrics実測(work_sec 477/416秒・e2e_sec 1019/1037秒≈17分/工程)から再計算し全体=裁定待ち除き約4-6時間へ。A0-1のみ実測なし独自見積と明示。※cmd_4222のgate_metrics最終行はBLOCK(03:26 review_two_phase_pending)だが家老の世代誤判定根治(03:34掲示板)で解消済みと突合**
- **v4.14 (2026-08-03 03:37): 殿裁定03:36+03:38反映: ①§2.5 WBS全7レーン38工程へStatus列新設(値=未着手/進行中(cmd番号)/done(証跡)/GATE CLEAR)。工程別進捗の正本=WBS Status列 ②§0.1全体進捗トラッカー新設(テキストバー+全体%+レーン別%+見込み時間。定義: done=1.0/進行中=0.5/母数=38工程)。将軍が進捗変化のたび単一writerとして両方更新。仕様変更なし**
- **v4.13 (2026-08-03 03:28): 進捗随時反映(殿指示03:26): §0現在地更新 — A0-0c=成果物確定+v4.12還流完了/cmd_4220=初回classifier全行要調査BLOCK→join再分類で再走中/cmd_4221=in_progress/cmd_4223(A0-3)=done報告レビュー待ち/疾風並行上書きは中断済み(正本=455e682fa)。仕様変更なし(§0.6は不変)**
- **v4.12 (2026-08-03 03:22): 家老v4.11反映=A0-0c実測(cmd_4222 commit 455e682fa)の将軍直接還流: §0.6-1のledger無条件優先を廃止し、`effective_start_date`(本番15,212行全件=decision日複写、2022-04はledger 4/1≠実切替4/4)を「expanded実切替との一致が検証できた場合のみ優先、不一致/未記録はexpanded実切替へfallback、切替なし月は初回取引日」のverification付き導出式へ置換(単純COALESCE禁止)。A0-0b/B1/A0-1のStart/Goalへ同導出式を同期(B1に2022-04型fixture必須化)。ledger再基線化はA0-4b route裁定候補として明記**
- **v4.11 (2026-08-03 03:24): 家老真v4.10レビュー反映: A2にも同型逃げ道廃止(133行の証拠付き三分類・要調査0・残存中はA2未完了。A3/A4/A5のvacuous PASS連鎖を遮断)**
- **v4.10 (2026-08-03 03:21): 家老v4.9反映: A0-0a/A0-2p/A4の要調査移管・解消工程の代替PASSを全廃し、残存中は当該工程未完了へ一意化(実適用は前回送信が空振りだった訂正版=assert検証済み)**
- **v4.9 (2026-08-03 03:16): 家老v4.8-B2残反映: AC-A0へ要調査0を明記、matrixの空ダミー行を除去しW0見出しをA0-0c行へ。B1(WBS A0-0a Start)はv4.8補で同期済み**
- **v4.8補(2026-08-03 03:14): 軍師指摘=v4.7のWBS A0-0a行置換が文字列不一致で無適用だった(matrix側のみ更新)。WBS行を本補で更新(assert検証付き)。教訓: 設計書のpython置換は全てassert必須**
- **v4.8 (2026-08-03 03:12): 家老v4.6-B2反映: A0-0a Goalを「証拠付き四分類の和=全行+要調査=0」へ強化(全件要調査でもPASSする空虚ACの禁止)。B1(A0-0a W0独立不能)はv4.7で反映済み**
- **v4.7 (2026-08-03 03:10): 実走知見の還流(cmd_4220初回実走→家老レビューBLOCK blt_030844): 三者突合CSV単独では検証者規約Q1(実運用開始)とQ3(境界証拠)の判定材料がなく全1,885行が要調査へ退化。A0-0aをW1(A0-0c還流済み+本番readonly join前提)へ移動、W0=5工程へ。設計時の机上依存が実走で覆った初例=実験ファーストの実証**
- **v4.6 (2026-08-03 03:08): 家老v4.5同期残3件解消: 依存要約を枝1/枝2/枝3へ分離(A0-0b/B1はA0-1を経由しない)/A0-0c Goalを成果物確定までに限定し還流済み確認を依存側Startへ移動/W2見出しを「第二段階・Start列準拠」へ(B2群はB1のみ依存の偽前提解消)**
- **v4.5 (2026-08-03 03:04): 家老v4.4残3件解消: A0-0b=A0-0c後W1へ(ledgerフィールド確定が前提。cmd_4221は配備采配でcmd_4222後の直列へ=家老へ通知済み)/A0-0cの成果=独立md+還流内容案へ(本書追記は将軍直接還流)/還流語を「各cmd GATE CLEAR直後の将軍直接還流(工程レーンD0と無関係)」へ一意化/A0-1待ち表現を名指しへ。W0=6工程**
- **v4.4 (2026-08-03 02:59): 家老v4.3の3 BLOCKER解消: B1=A0-0c後のW1へ(resolver前提)/設計書還流を将軍単一writer方式へ(W0並列の同一file競合根絶。cmdは独立成果物+還流内容案まで)/A0-1依存表現をWBS列へ統一(全W0待ち表現の削除)。W0=7工程**
- **v4.3 (2026-08-03 02:56): 両名v4.2レビューの同期残5件を解消: B3.5をW0へ(WBS Start=§0.6のみ・inventoryはhelper不要と定義変更、適用漏れ0検証はB4へ移管)/B1をW0へ(Start=§0.6のみ)/依存要約とWHENへA0-3含むW0=8工程を明記/工程数6→8訂正/§2-6末尾のholding_changed扱いを裁定済みへ統一。W2表現を「レーン間並列・レーン内直列」へ精密化**
- **v4.2 (2026-08-03 02:52): 軍師v4.0レビュー(msg_024750)の新矛盾解消: B3i行をWBSレーンB本文へ正式定義(Start=§0.6のみ即時可、Goal=inventory全数列挙)しB3 Startを「B1+B3i」へ。A0-4b Start同期はv4.1で解消済みと相互確認**
- **v4.1 (2026-08-03 02:49): 軍師v3.9レビュー(msg_024553)のBLOCKER解消: WBS A0-4b Start本文へS2/S3を同期(v3.8で§2.4のみ更新されWBS未同期だった真因=置換文字列不一致の無検証)+依存要約行へS1-S3並列とA0-4b前提を明記。S3の§2.4所属はv4.0で反映済み**
- **v4.0 (2026-08-03 02:46): 家老v3.9レビュー4 BLOCKER+WARN反映+殿指示「先頭から読むLLMの誤解防止・整合性」。①順序の唯一の正本=WBS Start列と宣言し§2.4を投影へ格下げ(矛盾時はWBSが勝つ) ②WaveはbarrierでなくStart前提充足で随時着手 ③S3のWave所属明記+lane内直列(A1-A4→A5、S1→S2→S3) ④B3のinventory前半をB3iとして独立工程化(1工程1cmd整合) ⑤S2分類をshould_guard/should_apply予定分類へ(readonly時点で実適用は観測不能、実確認はD/E) ⑥AC-A0へS2/S3前提とroute二本柱を同期**
- **v3.9 (2026-08-03 02:43): §2.4依存・並列・影響範囲マトリクス新設(殿指示02:41)。W0=即時全並列6工程(A0-0a/0b/0c/A0-3/A0-4a残件/inventory)、W1=A0-1+B1、W2=検証系全並列、本番DB書込みはW5のDレーンのみと明確化**
- **v3.8 (2026-08-03 02:40): 家老v3.7レビュー(BLOCKER4+B3/B4残+WARN)を全採択。N1=S分類を相互排他化(unchanged/computed_changed_and_guarded/computed_changed_and_applied+boolean列)。N2=A0-4b StartへS2/S3を追加し月次値route+signal/ledger再基線routeを同時一意化。N3=B2e新設(ledger guardのmode化: price_retro=guard/rule_correction=適用+再基線/未知=fail-closed、敵対fixture3種)。N4=D-xをtopological直列化(子孫完了後にのみ親へ)。B3/B4=signals検証をstandard差分0+FoF非意図差分0へ分離(裁定済み変更の受容と整合)。WARN=Signal型廃止理由からallocation差分可読性を削除(signal正本はsignals/ledger)**
- **v3.7 (2026-08-03 02:36): 殿裁定「シグナル遡及の原則」を焼込み。price遡及変更→シグナル維持が正(計算時点priceでは正しい計算) / 計算ルール是正→過去シグナルが誤式で固定されるのは許されず、正しいシグナルへ本番修正する(フル再計算は正しく変更を反映すべき)。レーンS holding_changedの扱いは裁定済み(受容・修正)へ更新、S3は規模報告と実行計画確認に変更。ledger guardの役割を「価格遡及ノイズのみ弾く」へ精密化(実装はB/Dレーン)**
- **v3.6 (2026-08-03 02:36): 家老のFoFモメンタム入力現物確認(msg_023141)により§2-6「シグナル一切不変」を撤回・是正。確定事実: FoF選択モメンタムは子PFのcumulative_returnを擬似価格として使用(component_price.py/recalculate_fof.py/multi_view_momentum_filter.py行番号証跡)→月次是正でFoF computed signalは理論上変わり得る(nested伝播あり)。standardのみ理論不変。ledger reconcileによりcomputed変化≠DB holding変化のためcomputed-vs-confirmed drift別計測。レーンS(dual replay全数検出・三分類全数表)を新設し、holding_changedの扱いは殿裁定(A0-4b統合)へ**
- **v3.5 (2026-08-03 02:33): 家老v3.4レビュー(BLOCKER3+WARN1+N1残)を全採択。B1=正規形を「月次境界日/trigger eventごとに1行(同一allocationでも分割)」へ是正(連続区間結合ではRULE06の毎月resetイベントが記録不能)+同一allocation連続月fixture必須化。B2=producer一本化をB2d工程として新設しB4前へ(B5は拒否gate常設のみ)。B3=signalsスナップショット差分=0をB4/D4/E1のGoalとAC-B/D/Eへ明記。B4 WARN=不変検証をcheckpoint直前後のsnapshot比較方式へ(正常な日次行追加の誤FAIL防止)。N1=旧語4箇所を月次境界日へ統一。F4=比較器呼称を「本番計算の保存前round規約」へ精密化(DB列はFloat型)**
- **v3.4 (2026-08-03 02:27): 仕様未決ゼロ達成。①殿裁定02:25: trade_performance種別=**trigger型へ統一・Signal型廃止**(RULE04独立性維持/allocation差分で情報欠損なし/DB制約単純化) ②家老v3.3残件3件解消: F4=比較器を「双方10桁量子化(round-half-even)後exact一致」の単一基準へ一意化(1e-12基準廃止)、N2=A0-0c新設(ledgerフィールド現物確定のreadonly独立工程。A0-1 Start循環解消)、N3=感度分析artifact参照追記(N感度/E感度設計書パス) ③N1語統一: 境界を指す語=「月次境界日」のみ、「執行」はholding切替事象に限定**
- **v3.3 (2026-08-03 02:20): 殿裁定2件+家老v3.2再レビュー残件を反映。①RULE06(毎月ウェイトリセット)は意図的確定ルールと最終確定 — 設計意図=途中参加の公平性(trade-rule.md L153現物確認)、感度分析(N感度/E感度)でロバストネス実証済み・理論上の不純は実務上許容(殿裁定02:14-02:16)。driftへの変更なし。同一シグナルのリバランス月もリセット執行 ②家老N1: 境界日優先順位をledger効力日→expanded実切替日へ是正(root holding日付は不採用 — 2022-04でrootは4/1と誤る) ③N2旧A0-0参照の全数置換+A0-2へ母集団外行接続 ④N3 B1四分類化 ⑤F3 A4のMTD起点=境界日 ⑥F4正規化文言+誤差基準の一意化(§0参照方式) ⑦F6検証者規約1の未開始分離**
- **v3.2 (2026-08-03 02:10): 家老v3.1最終確認(REVISE・疑義10件=msg_020501)を全反映。BLOCKER 2件解消: F1=月次境界日を全暦月に定義(切替あり月=実効力日/切替なし月=初回取引日、判定優先順位=ledger→root holding→expanded weights) / F8=Bレーンへ計算経路適用工程B2a(return_calculator)+B2b(monthly_returns)を新設。他: F2切替判定SSOT優先順位/F3 MTD起点=境界日/F4数値意味論=本番同一float64/F5計算仕様と記録仕様の分離明示/F6四分類(未開始分離)/F7境界誤り2種の区別/F9執行ずれ月一覧のprimitive独立導出(A0-0b)/F10 C-x除外PASS禁止+AC-A0拡張/軽微3件(A0-1 Start・fixture必須月・監査数表記)。軍師v3.1確認=疑義ゼロ(msg_020435)**
- **v3.1 (2026-08-03 02:05): v2.5宛て独立レビュー(家老指摘群msg_015947・軍師5件、大半はv3.0書き直しで解消済み)のうちv3.0にも残る実質指摘を反映。最重要=家老F3: **執行日の定義を「保有(expanded weights)が実際に切り替わった日」と明文化し、市場の月内初営業日との同一視を禁止**(2022-04は4/1営業日でも執行=4/4)。軍師#8残件=weights精度規約を§0.6-8へ新設(DB保存値をそのまま消費・独自丸め/再正規化禁止・合計乖離はfail-visible)。検証者規約3の表現統一+誤字修正**
- **v3.0 (2026-08-03 02:00): 全面書き直し(殿指示01:58「追記は矛盾を残す。丁寧に覚醒してアップデート」)。確定裁定(§0.6)を起点に再構成し、S1/S2両論併記・裁定前表現・旧工程ID(A0-1a/2a/4a等)・重複記述を全廃。§3.8は§0.6へ吸収。工程は§2.5 WBSに一本化**
- v2.0-v2.5 (2026-08-03 01:28-01:56): 独立レビュー2巡統合→殿裁定完結(S2執行日基準→区間=執行日→執行日→モメンタム窓→adj→§3.8同期)。詳細は記憶DB(knowledge:3fe9f871/c03420ab/5b0aa9fc/2a86d812/9f696beb/a01711d2)
- v1.0-v1.9 (2026-08-02 22:52-2026-08-03 01:17): 初版→Phase 0初回裁定(後に無効化)→三分類→三者評定→WBS化→独立レビュー。経緯は§3
