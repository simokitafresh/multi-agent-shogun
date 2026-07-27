# 指揮官inbox洪水是正 — ASIS/TOBE 5W1H (2026-07-27)

- 起案: 将軍(殿下知 2026-07-27 14:00「家老と軍師にinboxが届きすぎて停止するタイミングがない。これはインフラバグではないか？調査してくれ」→14:06「設計書を書き、家老と軍師にレビューしてもらえ」)
- 一次調査: 将軍(2026-07-27 14:00-14:05、全数計測+コード現物確認)
- origin: `[[殿指摘_指揮官inbox洪水_20260727]] -> [[着信49秒間隔×瞬間idleサンプリング]] -> [[本設計書]]`

## §1 ASIS(現状) — 2欠陥の合成で「停止するタイミングが構造的に存在しない」

### 実測(全数・本日2026-07-27分。queue/inbox + archive/inbox/{agent}_20260727*)

| | 家老 | 軍師 |
|---|---|---|
| 本日着信総数 | **568通** | 160通 |
| 起床型(nudgeで起こすtype) | **558通(98%)** | 136通(85%) |
| 10時以降の着信間隔 中央値 | **49秒** | 59秒 |
| 10時以降の最大静穏 | 438秒 | 6293秒 |
| 300秒超の静穏 | **1回のみ** | 4回 |

- 集計コマンド: python3でyaml全数parse、timestamp 2026-07-27でフィルタ、type別Counter+隣接間隔。1件の定義=inboxメッセージ1通。網羅範囲=当日分のみ(過去日・忍者宛は未走査)
- 家老type上位: bulletin_notify 95 / report_received 89 / gate_alert 50 / skill_hint 45 / review_result 36 / report_review 35 / report_review_result 29 / infra_anomaly 26
- 家老自身の分析(blt_20260727_110002)と整合: 約4割が判断を伴わない再通知。gate_alert GA-391〜399は9回発火して新規の穴0件(家老一次確認)

### F1. 送信側に同一原因の再通知抑止がない(需要側欠陥)

- 自動既読(起こさない)typeは6種のみ: low/info/gate_clear/heartbeat/status_update/retro_answer(`scripts/inbox_mark_read.sh:112`現物)
- bulletin_notify / gate_alert / skill_hint / infra_anomaly は**同一原因の2回目以降も毎回起床型**。送信側dedupは存在しない
- ★受け手のtype拡大は解でない: 2026-07-26「BLOCK回避でtypeを変え忍者宛9通が自動既読化され不達・40分損失」事故の教訓(CLAUDE.md明記)。**typeの意味を変えず、送り手で抑止する**のが正

### F2. /clear機会が「瞬間idleサンプリング」依存(供給側欠陥)

- `scripts/ninja_monitor.sh:7255-7268`(check_karo_clear)現物: 発火条件=**観測した瞬間にidle** かつ CTX>70%
- 着信中央値49秒間隔ではidle窓がサンプリングにほぼ当たらない → /clearが物理的に発火できない
- nudge debounceは30秒(`scripts/inbox_watcher.sh:97` NUDGE_COOLDOWN_SEC=30)で、49秒間隔の着信はdebounceをすり抜けほぼ全て個別nudgeになる

### ASISの帰結(本日実測の実害)

1. 家老CTX 97〜99%まで上昇(13:08-13:10、将軍pre-send capture実測)→ クリーンな/clearでなくautocompact(要約劣化)で凌ぐ
2. 家老の/clear後recovery(deepdive追体験)完了まで約30分(13:36 clear→14:05受領証)。着信に割込まれ続け、その間escalationがgeneration=3まで空回り(14:04発火→22秒後に自己解消の競合)
3. 「9回鳴って収穫0件」のALERT疲れ=次の本物を見逃す構造(家老具申blt_102353)

## §2 TOBE — 原理1行

**「メッセージの永続は不変のまま、起床(nudge)だけを間引く。同一原因は初回のみ起こし、CTX高圧時はnudgeを保留してidle窓を人工的に作る。」**

- 「削るな、速くしろ」(殿裁定07-21): 通知機構・typeの意味・fail-closedは削らない
- LG032: 新規gate/hook/daemonを作らない。inbox_watcher(debounce既存)/inbox_write/ninja_monitorの既存3経路への追加のみ

### T1. 送信側dedup(F1是正・主軸)

- 対象: `inbox_write.sh`送信経路のうち gate_alert / skill_hint / infra_anomaly / bulletin_notify の4type
- 設計: 送信時に**同一原因key**(gate_alert=GA原因key、skill_hint=skill×cmd、infra_anomaly=種別、bulletin_notify=投稿者×cmd)の直近送信を状態ファイルで照合。**窓内(既定案30分)の同一keyは、メッセージ本体はinboxへ永続書込みしつつnudgeを発行しない**(=digest扱い。type自体は変えない)
- 初回は従来通り起床型。窓リセットで再度起こす
- 契約: **メッセージは1通も失わない**(inboxファイル書込みは全件不変)。抑止されるのはsend-keys起床のみ。受け手は次の起床時に未読を一括処理(既存プロトコル通り)
- 見込み効果: 家老の起床型558通のうち再通知系(bulletin_notify+gate_alert+skill_hint+infra_anomaly=216通・38%)の大半を初回のみ化

### T2. CTX高圧時のnudge保留=idle窓の人工生成(F2是正)

- 対象: `inbox_watcher.sh`のnudge発行部(debounce機構が既存: :97,:466-468,:898-910)
- 設計: nudge発行前に対象paneのCTXを確認し、**CTX>70%(check_karo_clearの発火閾値と同一)なら非緊急typeのnudgeを保留**(debounceファイル延長で実現=既存機構の拡張)。保留中に生まれたidle窓をninja_monitorの既存check_karo_clearが検知して/clear → clear_recovery nudgeで復帰後、未読を一括処理
- 緊急type(task_assigned / clear_command / model_switch / escalation / cmd_new)は保留対象外
- 契約: 保留はnudgeのみ。メッセージ永続・既存debounce意味論・「停止中エージェントへ送るな」規則は不変更
- fail-safe: CTX取得失敗時は保留せず従来動作(誤保留より誤起床が安全)

### T3. 効果計測(既存計装に乗せる)

- before(本日実測を基準値として本書§1に固定): 家老起床型558通/日・着信間隔中央値49秒・CTXピーク97-99%・recovery完了30分
- after: 同一コマンドで前後比較。目標=起床型通数4割減・「CTX>90%到達なしで/clear」の実績1件以上
- 記録先: 既存 logs/defense_overhead.jsonl(新台帳を作らない=knowledge:fbb5716c車輪防止)

## §3 5W1H

| | 内容 |
|---|---|
| **WHY** | 指揮官の停止(=クリーン/clear)機会が構造的に消失し、autocompact劣化・recovery遅延・ALERT疲れが実発生 |
| **WHAT** | T1送信側dedup+T2 CTX高圧時nudge保留+T3前後計測。メッセージ永続・type意味論・fail-closedは不変更 |
| **WHEN** | 家老・軍師レビュー→殿裁可→cmd起票(1道具1CMD: T1弾とT2弾は分割) |
| **WHERE** | inbox_write.sh(T1) / inbox_watcher.sh(T2) / defense_overhead.jsonl(T3) |
| **WHO** | 将軍=設計+起票、家老=分解配備、忍者=実装、軍師=本設計レビュー+実装レビュー |
| **HOW** | 境界fixture: (a)同一key窓内2通目→nudgeなし・inboxには2通実在 (b)窓経過後→起床 (c)緊急typeは常時起床 (d)CTX≤70%→保留なし (e)CTX取得失敗→保留なし。前後サイクル所要をdefense_overhead.jsonlで実測 |

## §4 不変更契約(壊してはならないもの)

| 対象 | 契約 |
|---|---|
| inboxファイルへのメッセージ永続(flock書込み) | **不変更。1通も失わない** |
| typeの意味論(起床6種digest既存仕様) | **不変更**(07-26不達事故の再発防止) |
| 「停止中エージェントへ送るな」capture確認規則 | **不変更** |
| fail-closed系hook・三層preflight | **不変更** |

## §5 レビュー論点(家老・軍師への問い)

1. **T1の同一原因keyの粒度**: gate_alert=GA原因key/skill_hint=skill×cmd/infra_anomaly=種別/bulletin_notify=投稿者×cmd で過不足はないか。家老は受信当事者として「本日の568通にこのkeyを適用したら何通に減るか」を検算されたい
2. **T2の保留判定にCTXを使う是非**: CTX取得(tmux capture)のコストと精度。代替案=「GATE CLEAR等のturn境界イベント直後にclearを差し込む」方式との比較
3. **bulletin_notifyのデフォルト全員通知**: BULLETIN_NOTIFY未指定=3者通知の既定を変えるべきか(本設計は変えない判断。理由=既定変更は通知漏れリスクがdedupより大きい)。異論あれば具申されたい
4. **軍師**: T2が「起こさない」ことでレビュー依頼(review_draft)の到達が遅れる副作用の許容範囲。緊急type一覧にreview_draftを含めるべきか

## §6 将軍が確認していないこと

- inbox_watcherのCTX取得可否(watcherプロセスからのtmux capture-pane実行コスト)は未検証 — T2実装AC1で実測させる
- 忍者宛の着信量は未計測(本設計のスコープは指揮官2名)
- autocompact発生回数の正確な台帳が見当たらず、CTXピークはpre-send capture目視実測のみ
- 軍師側の自動/clear機構の有無は未確認(本日6293秒の静穏があり家老より軽症)

## §7 因果リンク

- → [[gunshi_auto_clear_recovery_design_20260727]] 同族(検知は出るが消費されない/停止機会の欠落)。対象が異なる(あちらは忍者stage封鎖、こちらは指揮官起床洪水)
- → [[LG032]] 既に強制されている行動に乗せよ(debounce/check_karo_clear既存機構の拡張)
- → [[殿裁定_削るな速くしろ_20260721]] 通知機構は削らず、起床だけ間引く
- → [[07-26_type迂回9通不達事故]] typeの意味を変えない根拠
