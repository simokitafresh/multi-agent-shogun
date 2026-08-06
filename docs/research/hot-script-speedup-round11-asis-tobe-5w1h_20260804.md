<!-- gist-master: 4571e36dca63e089831abaa8b1d6c275 hot-script-speedup-round11-asis-tobe-5w1h_20260804.md -->
# ホットスクリプト集中高速化 第十一弾 — 二段計測8-15位層(precheck+inbox+singleflight+cmd_save子区分) — AsIs/ToBe 5W1H設計書 v1.4 【✅CLOSED — 2/2 FAIL-close】

> v1.4(2026-08-05 20:42 家老差戻し修正): 進捗台帳のidentifierを提案台帳と完全一致へ修正(短縮形→完全修飾source:check_id)

> v1.3(2026-08-05 20:35 殿指示scope純化): 第10弾v1.7準拠で提案弾台帳と進捗台帳に高速化許可owner pathを一次コード突合で確定。列挙外pathの変更を禁止

> v1.2(2026-08-05 18:53進捗同期): 2026-08-05 18:03将軍下知で起動。#2 inbox_write_totalはfocused 20/20とp50/p95改善を得たが、最終scope commitが既存のscope外テストFAILに阻まれ正式FAIL-close。#3 singleflight_holdはfocused 10/10・full 65/65、joiner p50/p95 641/672ms→414/421msまで成立したが、31 affected testsのpre-commit 60秒timeoutでcommit未成立となり軍師レビューFAILで正式FAIL-close。両laneとも未コミット変更を保全し、完了へ丸めない。

> v1.1(2026-08-05 02:40 殿裁定): §2.6 checkpoint契約を追加(全弾共通)

> 初版起草(2026-08-04 23:46。殿指示23:45『同じ仕組みで第十一弾の設計書も作成せよ。第十弾の候補を除外した8-15番目までをやろう』)

> シリーズ: ホットスクリプト集中高速化。第一弾〜第七弾=✅CLOSED / **第八弾**=✅CLOSED(12/12 CLEAR) / **第九弾**=✅CLOSED(3 CLEAR + 5 FAIL-close) / **第十弾**=一部完了・#6保留 / **第十一弾=本書✅CLOSED(2/2 FAIL-close)**

## §-1 スコープと境界(数と原理を先に固定)

- **標的=直近24時間の累積課税8-15位**(第十弾TOP7を除いた次層8標的)。第八弾・第九弾で補欠・条件付きだった標的も含め、Tier 2で依然上位なら正式攻撃する
- **二段計測(殿設計2026-08-04 23:34 — 第十弾から恒久導入)**:
  - **Tier 1 劣化検知**: 修正後1週間のledger累積課税を前週比で総括
  - **Tier 2 ボトルネック特定**: 直近24時間の絶対値で累積課税を序列化
- **前弾との境界**: 第八弾補欠A(inbox_write)/補欠B(singleflight)/第九弾#4(cmd_save系)/第九弾補欠A(full_precheck)と重複する標的は、前弾の改善成果を引き継いだ上で残課税を攻撃する
- **第十弾との境界**: 第十弾=1-7位、第十一弾=8-15位。writer重複がある場合は直列条件を設定(§2弾台帳の依存関係を参照)
- **writer構造(第五〜十弾の写像)**: 1スクリプト(の1ホットパス)=1弾=1レーン。共有層(`scripts/lib/`)に触れる弾は独立writerかつ先行→固定HEADで再計測→個別弾の直列依存。並列変更禁止
- **品質2原則堅持**: 正本突合判定+境界fixture両方を維持。防御の検証力は1点も削らない(殿裁定2026-07-21『削るな、速くしろ』が憲法)
- **スコープ外**: gate/hookの削除・条件緩和(必須ハーネス保持=LS099)/テスト実行時間(第七弾CLOSED)/DM-Signal側Python(別repo)/第十弾標的全部
- **方式=レーン方式**(殿裁可→将軍下知blt→家老レーン配備→gate_metricsへlane名CLEAR刻印→最終checkpointで品質2原則検分)
- **lane最小AC/wave checkpointの二層契約**(殿恒久裁定2026-08-04 19:26): 【lane最小AC】focused fixture PASS+コード変更確認+p50/p95非悪化のみ。【wave最終checkpoint】全量FAIL0+全lane間独立比較+全量再測定+Tier 1前週比+Tier 2序列更新

## §0 序列SSOT(2026-08-04 23:32 将軍一次実測 — 直近24時間)

**取得方法**: `logs/defense_overhead.jsonl`から直近24時間を抽出し、source:check_id別にwall_msの累積・中央値・max・p95・呼出数を算出(Python statistics.median+sorted percentile)。1件=jsonl 1行=1計測イベント。第十弾標的(1-7位)は表に残すが背景扱い(本弾対象外)。**累積時間はagent-hours(全CLI合算)**=9並列CLIの全呼出しの合計であり壁時計の24h/日を超えうる。

### 累積課税序列(直近24時間・Tier 2)

| 順 | source:check_id | 累積 | n | median | p95 | max | 型 | 前弾帰属 |
|---|---|---|---|---|---|---|---|---|
| - | 1-7位(refresh系3種・affected_tests・execution・deploy_total・queue_wait) | 659,341s合計 | — | — | — | — | — | 第十弾 |
| 8 | `gate_gunshi_report_precheck:full_precheck` | **23,427s(≈6.5h)** | 5,381 | 1.07s | 17.6s | 288.9s | 恒常 | 第九弾補欠A |
| 9 | `inbox_write:inbox_write_total` | **18,822s(≈5.2h)** | 9,197 | 0.33s | 6.1s | 96.2s | 外れ値 | 第八弾補欠A |
| 10 | `gate_report_format:singleflight_hold` | **17,332s(≈4.8h)** | 8,276 | 0.39s | 11.9s | 61.2s | 外れ値 | 第八弾補欠B |
| 11 | `cmd_save:checks_main` | **9,344s(≈2.6h)** | 2,089 | 1.28s | 21.2s | 141.1s | 恒常 | 第九弾#4の一部 |
| 12 | `gate_gunshi_report_precheck:full_precheck_body_rest` | **6,143s(≈1.7h)** | 947 | 5.15s | 15.9s | 48.6s | 恒常 | 第八弾#5 |
| 13 | `report_publish:publish_total` | **3,272s(≈0.9h)** | 3,749 | 0.37s | 1.6s | 55.1s | 外れ値 | 新規 |
| 14 | `cmd_save:q11_semantic_search_overhead` | **3,086s(≈0.9h)** | 645 | 0.00s | 23.7s | 190.8s | 外れ値 | 第九弾#4の一部 |
| 15 | `cmd_save:checks_main.quality_gate` | **2,720s(≈0.8h)** | 780 | 0.45s | 14.4s | 203.4s | 外れ値 | 第九弾#4の一部 |

**読み**: (a)**full_precheck**(8位)はmed 1.07s×5,381回の恒常課税。第九弾補欠A(偵察FAIL-close: 共通run_idなしで一意結合不能)の知見を引き継ぐ。第八弾#5(body_rest=12位)とは同族上流の関係ゆえ直列条件要。(b)**inbox_write_total**(9位)はmed 0.33s×9,197回=最高頻度。1回は軽いが回数で累積する「砂粒型」。第八弾補欠Aだったが正式昇格。(c)**singleflight_hold**(10位)は報告gate同時発火時のlock待ち。med 0.39s×8,276回でinbox_writeと同格の砂粒型。(d)**cmd_save子区分**(11位checks_main・14位q11_semantic・15位quality_gate)は第九弾#4の分解。save_totalが可視化した未計装区間の内訳特定が続く。(e)**publish_total**(13位)は新規標的。med 0.37s×3,749回=配備パイプラインの一部で、deploy_total(第十弾#6)の子区分候補。

## §1 計測境界(憲法・第五〜十弾継承+Tier 2)

- 計測=既存台帳のみ(`logs/defense_overhead.jsonl`)。**新台帳禁止**(knowledge:fbb5716c)
- before/afterは**同一スクリプト・同一check_id・同一環境**のfixed-window比較。異なるcheck_idの混算禁止
- run間ノイズ: 各check_idの分布(p25/p75)を先に取り、Δ有意判定はノイズ帯超のみ
- **Tier 1**: 効果宣言=**修正後1週間の累積課税(total秒)の前週比**を正式確定値とする
- **Tier 2**: 弾標的選定=**直近24時間の累積課税絶対値**で序列化。依然上位なら再攻撃
- 外れ値型(median ≈ 0)は中央値比較が無意味——**p95/p99と裾の総量(total)**で判定する
- 恒常課税型(median > 1s)は**中央値×呼出数=累積課税**で判定する
- **砂粒型**(median < 0.5s but n > 5,000): 1回は軽いが頻度で累積する。削減手筋=呼出回数削減 or 1回あたりの定数項削減

## §2 To-Be — 進め方(型を継承)+品質底線

1. **1標的=1弾・複合弾禁止**。恒常課税型=子区分計測→最大寄与是正/外れ値型=発火条件特定→条件ベース是正/砂粒型=呼出回数削減 or 定数項削減
2. **品質底線**: (a)防御の検証力不変(precheck検証力・inbox配送保証・singleflight排他・cmd_save gate判定は全て固定。検証を弱める高速化禁止) (b)PASS/FAIL挙動不変=是正前後で同一入力の判定完全一致 (c)敵対fixture=是正で変更した独立oracle・副作用境界ごとに1点
3. 仮説在庫(序列裏取り済みの初期観察のみ・事前外挿禁止): full_precheck=run_id結合不能(第九弾補欠A偵察知見)→計装identity追加後に再計測/inbox_write=pre-send capture(Phase 6起源)の累積課税疑い/singleflight=flock競合パターンの同定→wait条件是正/cmd_save子区分=save_total-checks_main差分の中身特定(第九弾#4知見引継ぎ)
4. **反復サイクル型**: ローカル極限化→live計測→差分再検証→再極限化。停止条件=Δがノイズ帯以内でクローズ
5. **read-only冗長並列**: 子区分計測・発火条件記録はread-only冗長2名先着採用可。是正実装は単独所有
6. 個別弾は選択実行(`bash scripts/run_tests.sh file <対象>`)FAIL0・SKIP0のみ。途中try回数最大化
7. 完了宣言=全弾クローズ→Tier 1(前週比)+Tier 2(直近24h序列再計測)→CLOSE刻印
8. **方式=レーン方式**(将軍下知→家老配備→lane名CLEAR→最終checkpoint品質2原則検分)
9. **lane最小AC/wave checkpointの二層契約**(殿恒久裁定2026-08-04 19:26)

### 提案弾台帳(殿裁可で固定 — v1.3 owner path確定)

| # | 標的identifier | 高速化許可owner path | 型 | 現状(直近24h) | 手筋候補(実測で裏取り後) |
|---|---|---|---|---|---|
| 1 | `gate_gunshi_report_precheck:full_precheck` | `scripts/gates/gate_gunshi_report_precheck.sh` | 恒常 | med 1.07s×5,381・total 23,427s | 第九弾補欠A偵察知見(run_id結合不能)引継ぎ。計装identity追加後に子区分計測→最大寄与是正 |
| 2 | `inbox_write:inbox_write_total` | `scripts/inbox_write.sh` | 砂粒 | med 0.33s×9,197・total 18,822s | pre-send captureの寄与率計測→不要呼出削減 or 非同期化。配送保証は不変 |
| 3 | `gate_report_format:singleflight_hold` | `scripts/gates/gate_report_format.sh` | 砂粒 | med 0.39s×8,276・total 17,332s | flock競合パターン同定→wait条件是正。singleflight排他保証は不変 |
| 4 | `cmd_save:checks_main` | `scripts/cmd_save.sh` | 恒常 | med 1.28s×2,089・total 9,344s | 第九弾#4知見(save_total差分)引継ぎ。子check別寄与率計測→最大寄与是正 |
| 5 | `gate_gunshi_report_precheck:full_precheck_body_rest` | `scripts/gates/gate_gunshi_report_precheck.sh` | 恒常 | med 5.15s×947・total 6,143s | 第八弾#5知見引継ぎ。#1(full_precheck)と同族writerゆえ#1→#5直列 |
| 6 | `report_publish:publish_total` | `scripts/report_field_set.sh` | 砂粒 | med 0.37s×3,749・total 3,272s | 新規標的。子区分計測→最大寄与特定。deploy_total(第十弾#6)の子区分候補 |
| 7 | `cmd_save:q11_semantic_search_overhead` | `scripts/cmd_save.sh` | 外れ値 | med 0.00s×645・total 3,086s・max 190.8s | 長裾の発火条件特定。semantic_search.sh内のFTS5/DB呼出しパターン分解 |
| 8 | `cmd_save:checks_main.quality_gate` | `scripts/cmd_save.sh` | 外れ値 | med 0.45s×780・total 2,720s・max 203.4s | 長裾の発火条件特定。#4(checks_main)と同族writerゆえ#4→#8直列 |

**owner path制約**: 上記owner pathのみ高速化・変更可。test/log/call-path依存はread-onlyかつ進捗計上禁止。

- #1→#5は同族writer(gate_gunshi_report_precheck)ゆえ直列。#4→#8は同族writer(cmd_save)ゆえ直列
- #2・#3・#6は独立writerで並列可
- 第十弾#6(deploy_total)と#6(publish_total)は親子関係の可能性あり。第十弾#6偵察で確定後に直列条件を判断

## §2.5 進捗台帳(2026-08-05 20:42 v1.4 identifier完全一致修正)

| # | 標的identifier | 高速化許可owner path | 状態 | 帰結(実測生値) |
|---|---|---|---|---|
| 1 | `gate_gunshi_report_precheck:full_precheck` | `scripts/gates/gate_gunshi_report_precheck.sh` | ⏹️**未配備・閉弾**(2026-08-06) | 第九弾補欠A知見あり。配備前に弾CLOSED |
| 2 | `inbox_write:inbox_write_total` | `scripts/inbox_write.sh` | ⚠️**正式FAIL-close** | `cmd_karo_round11_lane2_inbox_write_total_20260805`: baseline n=9,197/p50=330ms/p95=6,100ms/max=96,200ms/total=18,822s → current n=9,758/p50=327.5ms/p95=6,134ms/max=181,570ms/total=20,376.43s。live resolver再利用で重複tmux scan/pane lookupを除去し、focused pre-send/persist/total=20/20/20、p50/p95=244/391ms、FAIL0/SKIP0。ただしscope-wide 38 testsは既存の`test_ninja_monitor_stall.bats`・`test_deploy_task.bats`失敗でAC4未達、commitなし。家老ACCEPT・archive済み |
| 3 | `gate_report_format:singleflight_hold` | `scripts/gates/gate_report_format.sh` | ⚠️**正式FAIL-close** | `cmd_karo_round11_lane3_singleflight_hold_20260805`: AC1-3 yes、AC4/commit no、軍師レビューverdict=FAIL。現ledger n=8,633/p50=400ms/p95=11,590ms/max=61,250ms/total=17,830.36s、focused 10/10・full 65/65 PASS、joiner p50/p95 641/672ms→414/421ms。変更は`gate_report_format.sh`+contract testに保全中。commit contractを22 pathへ同期した後もaffected 31 testsが60秒上限でPRECOMMIT_TIMEOUT、commit hashなし |
| 4 | `cmd_save:checks_main` | `scripts/cmd_save.sh` | ⏹️**未配備・閉弾**(2026-08-06) | 第九弾#4知見あり。配備前に弾CLOSED |
| 5 | `gate_gunshi_report_precheck:full_precheck_body_rest` | `scripts/gates/gate_gunshi_report_precheck.sh` | ⏹️**未配備・閉弾**(2026-08-06) | #1未着手のため直列待ちのまま閉弾 |
| 6 | `report_publish:publish_total` | `scripts/report_field_set.sh` | ⏹️**未配備・閉弾**(2026-08-06) | 独立writer。配備前に弾CLOSED |
| 7 | `cmd_save:q11_semantic_search_overhead` | `scripts/cmd_save.sh` | ⏹️**未配備・閉弾**(2026-08-06) | 配備前に弾CLOSED |
| 8 | `cmd_save:checks_main.quality_gate` | `scripts/cmd_save.sh` | ⏹️**未配備・閉弾**(2026-08-06) | #4未着手のため直列待ちのまま閉弾 |

## §2.5.1 テスト修正・高速化の共通知見(第八弾実証・以後継承)

第八弾で実証した以下の方式を、本弾の全レーンとwave最終checkpointへ継承する。

1. **FAIL単位で分割**: shardの失敗をテストファイル単位の独立タスクへ分け、heavy admission・three-layer preflight・commit wrapperのように原因を混線させない。
2. **根因を実装側で修正**: テストの期待値・fail-closed境界・検証対象を弱めない。今回もロック/待機境界、三層検証の前提、継承ロック解放を根因として直した。
3. **focused二値検証**: 修正ごとに対象テストだけを再実行し、PASS/FAIL/SKIPを計測する。focused PASSを統合条件とし、SKIPは未完了扱いにする。
4. **固定HEAD統合後に全量確認**: focused PASSを同一固定HEADへ統合し、receipt和集合で宣言数=観測数、重複0、欠損0、FAIL0、SKIP0、HEAD一致を確認する。
5. **高速化の境界**: テスト対象・品質境界を削らず、並列shard、専用fixture、ロック競合解消、不要な再走回避で時間を短縮する。新規実装用testはPASS確認後に削除し、残すcontract testだけ具体的不変量をtest_necessityへ記録する。
6. **完了はreceiptで判定**: 「修正した」「テストした」という出力では完了とせず、complete=1・full_scope=true・rc=0を含む最終receiptを必須証跡とする。

- origin: [[第八弾shard4失敗テスト]] -> [[FAIL単位分割修正]] -> [[focused二値検証]] -> [[固定HEAD全量receipt]] -> [[第九弾_第十二弾へ継承]]


## §2.6 checkpoint契約(殿裁定2026-08-05 — 全弾共通)

full/wave checkpointの全量テストを1名へ一括配備しない。以下の契約に従う。

**Step 0 — test衛生・高速化を先に行う**: 固定HEAD化とshard実走の前に、当該waveで新規/変更した実装用testを `作成→PASS→同一task内で削除` し、永続testは全件に具体的不変量の `test_necessity` があることをN/Nで確認する。重複・陳腐・一時fixture残存を0件化し、残るcontract testは検出力を削らずrunner/fixture/共有資源を高速化してからmanifestを生成する。

| 項 | 契約 |
|---|---|
| 並列度 | 3〜4名。1名一括配備禁止 |
| HEAD固定 | 全shardが同一commit HEADで実走。shard間のHEAD不一致は和集合判定を無効化する |
| shard分割 | 相互排他的LPT(Longest Processing Time)shard。テスト集合の完全分割・重複0 |
| 共有資源 | fixture等の共有資源は専用shard(1名が専有)。共有資源shardと通常shardの並列実行でロック競合しない設計 |
| 隔離 | lane固有worktree・TMPDIR・receipt。shard間の状態共有0 |
| 最終判定 | receipt和集合: N/N(全件)・duplicate 0・missing 0・FAIL 0・SKIP 0・source_head全一致 |
| 再実走 | 全量再実走を既定にせずshard単位で再実走。FAILしたshardのみ再実走 |
| test肥大防止 | 新規/変更testの削除または`test_necessity`宣言率N/N。contract外test 0、不要fixture参照0をmanifest生成前に確認 |

- origin: `[[殿裁定_全量テスト3_4名分割_20260805]] -> [[固定HEAD相互排他shard]] -> [[receipt和集合で全量検収]]`

## §3 decision ledger

| 項 | 状態 |
|---|---|
| checkpoint契約(全弾共通) | **殿裁定2026-08-05**。§2.6参照 |
| 第十一弾の起動 | **全レーン決着・CLOSED**(2026-08-06)。2026-08-05 18:03将軍下知で#2/#3を並列配備→双方正式FAIL-close。残6標的は未配備のまま閉弾 |
| 序列snapshot | 起草時実測済み(§0=2026-08-04 23:32・直近24時間・第十弾と同一snapshot) |
| 弾数・標的固定 | 8-15位の8標的。殿裁可で固定 |
| 同族writer直列条件 | #1→#5(precheck系)、#4→#8(cmd_save系)。裁可対象 |
| 高速化と防御力の境界 | **確定**: 検証力不変・fail-closed維持・チェック間引き禁止(LS099/殿裁定07-21) |

## §4 5W1H

- **WHY**: 第十弾TOP7の下に累積21.4時間/日の次層8標的が控える。砂粒型(低median×高頻度)は個別には目立たないが累積でTOP7に迫る。前弾の補欠として後回しにされた標的を正式攻撃する(殿指摘2026-08-04 23:29『改善後も遅いものを無視してしまう』)
- **WHAT**: 8-15位の8標的。恒常型2弾(precheck+checks_main)+砂粒型3弾(inbox+singleflight+publish)+外れ値型2弾(q11+quality_gate)+恒常型1弾(body_rest)。検証力不変
- **WHEN**: 殿裁可後にレーン配備。独立writerの#2/#3/#6/#7は先行可。同族writer直列弾は前弾完了後
- **WHERE**: `scripts/`配下のgate_gunshi_report_precheck.sh・inbox_write.sh・gate_report_format.sh・cmd_save.sh・report_publish(scripts内)。台帳=`logs/defense_overhead.jsonl`
- **WHO**: 偵察・是正=忍者(read-only冗長2名可+是正は単独所有)、検分=家老+軍師、裁可=殿
- **HOW**: レーン方式(将軍下知→家老配備→lane名CLEAR→最終checkpoint品質2原則検分)。Tier 1+Tier 2の二段計測で効果確認

## §5 因果リンク

- → [[hot-script-speedup-round10-asis-tobe-5w1h_20260804]] 同時起草の姉妹弾(TOP7)。writer重複なし
- → [[hot-script-speedup-round8-asis-tobe-5w1h_20260804]] 補欠A(inbox)/補欠B(singleflight)/#5(body_rest)の成果引継ぎ元
- → [[hot-script-speedup-round9-asis-tobe-5w1h_20260804]] 補欠A(full_precheck)/#4(cmd_save系)の成果引継ぎ元
- → [[殿裁定_削るな速くしろ_20260721]] 品質を保ったまま超速化=憲法(knowledge:569abc55)
- → [[ledger-driven-campaign-lane-pattern_20260714]] レーン方式の型元
- → [[殿裁定_厳密さは最終チェックのみ_20260714]] 途中try最大化・報告整形は最終集約
- origin: `[[殿指示_第十一弾_8_15位_20260804]] -> [[第十弾TOP7除外の次層]] -> [[砂粒型+前弾補欠の正式攻撃]]`
