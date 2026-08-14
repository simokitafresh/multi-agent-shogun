# 家老 強くてニューゲーム復帰点 — 2026-08-03 02:38 JST

- status: active
- owner: karo
- source: 殿指示「いまクリアされても今より強くてニューゲームできるようにせよ」
- current_task: DM-Signal月次リターン境界是正設計の独立レビュー
- origin: `[[殿指示_強くてニューゲーム_20260803]] -> [[月次境界仕様v3_9]] -> [[家老独立レビュー]] -> [[strong_new_game_completion_contract]]`

## 復帰直後の結論

設計正本は `docs/research/dm-monthly-trade-bug-asis-tobe-5w1h_20260802.md` v3.9、SHA256=`db07b40b5e96b1194e3594b0c14b5f70d8cc003d07fb3e768b337b7bcc49a8c3`。

家老は将軍へv3.9判定 `REVISE` を送信済み。返答ID=`msg_20260803_024231_1416588_6e691387`。v3.7の4 BLOCKERの主要部分は反映されたが、v3.9の依存マトリクス導入で新たな整合性欠陥が露出したため、設計書をクローズ済みとして扱ってはならない。

## 確定した一次事実

1. 月次リターン区間は月次境界日→翌月月次境界日。切替あり月はledger確定decision効力日→expanded weights実切替日の優先順、root holding_signal日付は境界SSOTにしない。
2. 切替なし月もRULE06により初回取引日を月次境界日とし、毎月weight resetする。drift方式へ変更しない。
3. FoFの選択モメンタム入力は子PFの `MonthlyReturn.cumulative_return`。証拠は `component_price.py:54-80`、`recalculate_fof.py:333-336, 881-888, 961-976, 1318-1364`、`multi_view_momentum_filter.py:39-42, 155-208`。
4. よって月次計算ルール是正でFoFのcomputed signalは変化し得て、L1→L2→L3へ伝播する。DB signals差分0はledger guardの抑止でも生じるため、理論的不変の証明ではない。
5. 殿裁定02:34: price遡及変更由来の差は既存signal維持、計算ルール是正由来の差は正しい過去signalへ修正する。ledger guardは両者を区別しなければならない。
6. trade_performanceは月次境界/trigger eventごとに1行。同一allocationでも毎月分割し、Signal型を廃止してtrigger型へ統一する。

## v3.9に残る4 BLOCKER

1. §2.4マトリクスL132はA0-4bの前提にS2/S3を含むが、§2.5 WBS L158・依存要約L144・AC-A0は旧前提のまま。A0-4bの作業/Goalにもsignal修正とledger再基線routeが欠ける。
2. W2 L129はS1-S2のみで、W3が要求するS3の所属Waveがない。また「W2全並列」はA1→A5、S1→S2→S3等のレーン内直列と矛盾する。レーン間並列とレーン内順序を分離して表す。
3. W0 L123はB3.5+B3 inventoryを一行に束ねる一方、L142は「1工程=1cmd」、L140は6工程を忍者6名へ同時配備とする。工程ID・cmd数・6枠制約を一致させる。
4. S2 L199の `computed_changed_and_applied/guarded` はreadonly dual replay時点では実適用を観測できない。`should_apply/should_guard` 等の予定分類とし、実適用/guard結果はD/Eで別途二値確認する。

解消確認済み: trade正規形、producer一本化順序、Standard/FoF signals AC分離、B2e明示provenance 3 mode、D-x topological直列。WARN: wave全体barrierは行単位依存より過剰で、A0-1/B1着手を不要に遅延させる。

## /new後の再開順

1. 家老Recoveryを完遂し、`queue/inbox/karo.yaml` の未読をID単位で処理する。
2. 本設計書のSHAと版を再取得する。v3.9のままなら再レビューせず待機、v3.10以降ならdiffだけでなく§2.4/§2.5/§5を相互照合する。
3. 上記4 BLOCKERを二値判定する。特に `rg -n "A0-4b|S1-S2|S3|全並列|1工程=1cmd|computed_changed_and_(applied|guarded)|AC-A0"` で二重正本のstaleを機械確認する。
4. 相互不可視契約を守り、軍師pane・軍師review内容・review_logを見ない。
5. 結果は将軍paneに確認プロンプトがないことを先に確認し、`inbox_write.sh shogun ... review_result karo <action>` で直接返す。掲示板へ代替投稿しない。

## 家老の禁則・安全境界

- 将軍のWHATを家老判断で書き換えない。レビューで疑義を隠さない。
- 忍者作業を家老D0で実装しない。readonly現物確認とレビューは可。
- gunshiとの相互不可視レビューを破らない。
- operational YAMLは直接編集せず、安全helperを使う。
- 本番DB確認はreadonly、書込みはPF単位transaction・backup・restore証跡がある正規工程のみ。

## clear-ready二値条件

- [x] 最新レビュー結果を将軍へ送信
- [x] 復帰正本に対象SHA・返答ID・残BLOCKER・次行動を保存
- [ ] v3.10以降で4 BLOCKERが全て解消
- [ ] 設計書クローズ判定

未達2項目は進行中作業であり、状態保存の失敗ではない。復帰後は完了を捏造せず、この地点から再開する。
