<!-- gist-master: 98f42e727bea67ad5dd322e6756bc45b hot-script-speedup-round10-asis-tobe-5w1h_20260804.md -->
# ホットスクリプト集中高速化 第十弾 — 二段計測でTOP7再攻撃 — AsIs/ToBe 5W1H設計書 v1.2

> v1.2(2026-08-05 02:40 殿裁定): §2.6 checkpoint契約を追加(全弾共通)

> v1.1(2026-08-04 23:46覚醒更新): 殿指示『第九弾と同じ粒度同じ水準で覚醒して作成せよ』。§-1スコープ拡充(writer構造・前弾境界・スコープ外)、§1計測境界(第九弾継承+Tier 2追加)、§2 To-Be(9項目)、弾台帳に型・現状・手筋候補追加、§2.5進捗台帳・§3 decision ledger・§5因果リンク新設

> 初版起草(2026-08-04 23:34。殿発案23:29『第十弾は実際に今この瞬間にボトルネックになっている遅いものを改めてやりたい』『トップ7全部をもう一度やるべきだ』『修正後1週間のledger累積課税を前週比で総括は劣化を検知、現在のボトルネックは直近24時間で計測の二段構え』)

> シリーズ: ホットスクリプト集中高速化。第一弾〜第七弾=✅CLOSED / **第八弾**=wave最終checkpoint進行中 / **第九弾**=レーン配備中 / **第十弾=本書** / 第十一弾=8-15位(本書と同時起草)

## §-1 スコープと境界(数と原理を先に固定)

- **標的=直近24時間の累積課税TOP7**。第八弾(refresh系)・第九弾(外れ値型+配備経路)で改善済みでも**依然TOPなら再攻撃する**。「改善済みだからスコープ外」は洗脳#1(早期終了)
- **二段計測(殿設計2026-08-04 23:34 — 本弾から恒久導入)**:
  - **Tier 1 劣化検知**: 修正後1週間のledger累積課税を前週比で総括。退行を機械的に検出。wave最終checkpointの既存契約
  - **Tier 2 ボトルネック特定**: 直近24時間の絶対値で累積課税TOP Nを序列化。「今この瞬間の最大の敵」を機械的に炙り出す。**前週比のみでは「改善済みだが依然遅い」「新たに遅くなった」が盲点**(殿指摘)。Tier 2で補完
- **前弾との境界**: 第八弾・第九弾標的と重複する場合、前弾の改善成果を引き継いだ上で残課税を攻撃する(前弾クローズ後に第十弾へ吸収)。前弾進行中の標的は前弾のwave checkpoint結果を待ってから着手
- **writer構造(第五・七・八・九弾の写像)**: 1スクリプト(の1ホットパス)=1弾=1レーン。共有層(`scripts/lib/`)に触れる弾は独立writerかつ先行→固定HEADで再計測→個別弾の直列依存。並列変更禁止
- **品質2原則堅持**: 正本突合判定+境界fixture両方を維持。防御の検証力は1点も削らない(殿裁定2026-07-21『削るな、速くしろ』が憲法)
- **スコープ外**: gate/hookの削除・条件緩和(必須ハーネス保持=LS099)/テスト実行時間(第七弾CLOSED)/DM-Signal側Python(別repo)
- **方式=レーン方式**(殿裁可後→将軍下知blt→家老レーン配備→gate_metricsへlane名CLEAR刻印→最終checkpointで品質2原則検分。cmd正式起票はしない)
- **lane最小AC/wave checkpointの二層契約**(殿恒久裁定2026-08-04 19:26): 【lane最小AC】focused fixture PASS+コード変更確認+p50/p95非悪化のみ。【wave最終checkpoint】全量FAIL0+全lane間独立比較+全量再測定+Tier 1前週比+Tier 2序列更新

## §0 序列SSOT(2026-08-04 23:32 将軍一次実測 — 直近24時間)

**取得方法**: `logs/defense_overhead.jsonl`から直近24時間を抽出し、source:check_id別にwall_msの累積・中央値・max・p95・呼出数を算出(Python statistics.median+sorted percentile)。1件=jsonl 1行=1計測イベント。durable_trigger_missing(単発46,800s異常値)は除外。**累積時間はagent-hours(全CLI合算)**=9並列CLIの全呼出しの合計であり壁時計の24h/日を超えうる。

### 累積課税序列(直近24時間・Tier 2)

| 順 | source:check_id | 累積 | n | median | p95 | max | 型 | 前弾帰属 |
|---|---|---|---|---|---|---|---|---|
| 1 | `three_layer_health:refresh_window` | **245,481s(≈68.2h)** | 8,300 | 25.64s | 69.3s | 320.0s | 恒常 | 第八弾#1 |
| 2 | `three_layer_health:refresh_copy` | **111,764s(≈31.0h)** | 7,385 | 12.40s | 38.2s | 270.3s | 恒常 | 第八弾#2 |
| 3 | `three_layer_health:refresh_verify` | **92,710s(≈25.8h)** | 7,507 | 12.31s | 18.7s | 72.2s | 恒常 | 第八弾#3 |
| 4 | `git_pre_commit:affected_tests` | **74,925s(≈20.8h)** | 1,132 | 4.82s | 336.8s | 1,334.2s | 恒常+裾 | 第八弾#4(-65%済) |
| 5 | `heavy_job_admission:execution` | **66,859s(≈18.6h)** | 762 | 3.00s | 561.0s | 1,191.0s | 外れ値 | 第九弾#1 |
| 6 | `deploy_task:deploy_total` | **40,592s(≈11.3h)** | 3,934 | 1.81s | 50.0s | 991.1s | 混合 | 第九弾#3 |
| 7 | `heavy_job_admission:queue_wait` | **28,010s(≈7.8h)** | 358 | 3.00s | 509.0s | 1,222.0s | 外れ値 | 第九弾#2 |
| - | 8位以降は第十一弾(別設計書)の領域 | — | — | — | — | — | — | — |

**読み**: (a)TOP3はrefresh系(第八弾標的)で累積125.0時間/日。第八弾wave checkpoint結果次第で残課税を確定する。改善後も依然TOPならば第十弾で再攻撃(Tier 2の本質)。(b)4位affected_testsはmedian 4.82sだがp95=337s・max=1,334s=22分の長裾。恒常+裾の混合型で、中央値は第八弾-65%の成果だが裾が依然巨大。(c)5位・7位のheavy_job系は第九弾#1・#2で偵察GATE CLEAR済み(p99上位jobの同定完了)。是正実装の成果がTier 1で確定するまでは着手を待つ。(d)6位deploy_totalは第九弾#3で偵察GATE CLEAR済み(最大寄与=report_publication特定済み)。

### 第八弾起草時(07-28以降累積)との対照

| check_id | 第八弾(07-28以降) | 第十弾(直近24h) | 24h×7推定週量 | 変化 |
|---|---|---|---|---|
| refresh_window | 165,352s | 245,481s | 1,718,367s | 依然TOP |
| refresh_copy | 85,093s | 111,764s | 782,348s | 依然TOP |
| refresh_verify | 70,362s | 92,710s | 648,970s | 依然TOP |
| affected_tests | 28,868s | 74,925s | 524,475s | 裾悪化 |
| execution | 28,453s | 66,859s | 467,013s | 第九弾偵察済み |
| deploy_total | 17,549s | 40,592s | 284,144s | 第九弾偵察済み |
| queue_wait | 8,764s | 28,010s | 196,070s | 大幅悪化 |

## §1 計測境界(憲法・第五〜九弾継承+Tier 2追加)

- 計測=既存台帳のみ(`logs/defense_overhead.jsonl`)。**新台帳禁止**(knowledge:fbb5716c)
- before/afterは**同一スクリプト・同一check_id・同一環境**のfixed-window比較。異なるcheck_idの混算禁止
- run間ノイズ: 各check_idの分布(p25/p75)を先に取り、Δ有意判定はノイズ帯超のみ
- **Tier 1**: 効果宣言=個別Δの総和ではなく、**修正後1週間の累積課税(total秒)の前週比**を正式確定値とする
- **Tier 2**: 弾標的選定=**直近24時間の累積課税絶対値**で序列化。前弾の成果が出た後も依然TOPなら再攻撃対象
- 外れ値型(median ≈ 0)は中央値比較が無意味——**p95/p99と裾の総量(total)**で判定する
- 恒常課税型(median > 1s)は**中央値×呼出数=累積課税**で判定する

## §2 To-Be — 進め方(型を継承)+品質底線

1. **1標的=1弾・複合弾禁止**。恒常課税型=子区分計測→最大寄与是正/外れ値型=発火条件特定→条件ベース是正
2. **品質底線**: (a)防御の検証力不変(admission制御の排他保証・deploy契約検証・cmd_save gate判定は全て固定。検証を弱める高速化禁止) (b)PASS/FAIL挙動不変=是正前後で同一入力の判定完全一致 (c)敵対fixture=是正で変更した独立oracle・副作用境界ごとに1点
3. 仮説在庫(序列裏取り済みの初期観察のみ・事前外挿禁止): refresh系=第八弾の残課税構造を引き継ぎ/affected_tests裾=少数の巨大テストセットが支配する疑い/heavy_job系=第九弾偵察でp99上位job同定済み/deploy_total=第九弾偵察でreport_publication特定済み
4. **反復サイクル型**: ローカル極限化→live計測→差分再検証→再極限化。停止条件=Δがノイズ帯以内でクローズ(採用またはno-change)
5. **read-only冗長並列**: 子区分計測・発火条件記録はread-only冗長2名先着採用可。是正実装は単独所有
6. 個別弾は選択実行(`bash scripts/run_tests.sh file <対象>`)FAIL0・SKIP0のみ。途中try回数最大化・厳密さは最終checkpointへ集中
7. 完了宣言=全弾クローズ→Tier 1(修正後1週間ledger前週比)+Tier 2(直近24h序列再計測)→CLOSE刻印
8. **方式=レーン方式**(殿裁可→将軍下知blt→家老レーン配備→gate_metricsへlane名CLEAR刻印→最終checkpointで品質2原則検分)
9. **lane最小AC/wave checkpointの二層契約**(殿恒久裁定2026-08-04 19:26)

### 提案弾台帳(殿裁可で固定)

| # | 標的 | 型 | 現状(直近24h) | 手筋候補(実測で裏取り後) |
|---|---|---|---|---|
| 1 | `three_layer_health:refresh_window` | 恒常 | med 25.64s×8,300・total 245,481s | 第八弾#1成果引継ぎ。wave checkpoint後に残課税を確定→残構造を偵察 |
| 2 | `three_layer_health:refresh_copy` | 恒常 | med 12.40s×7,385・total 111,764s | 第八弾#2成果引継ぎ。同上 |
| 3 | `three_layer_health:refresh_verify` | 恒常 | med 12.31s×7,507・total 92,710s | 第八弾#3成果引継ぎ。同上 |
| 4 | `git_pre_commit:affected_tests` | 恒常+裾 | med 4.82s×1,132・total 74,925s・max 1,334s | 第八弾#4(-65%)後の残裾。p95上位のtest set同定→裾削減 |
| 5 | `heavy_job_admission:execution` | 外れ値 | med 3.00s×762・total 66,859s・max 1,191s | 第九弾#1偵察済み(p99上位job同定)。是正実装の残課税を攻撃 |
| 6 | `deploy_task:deploy_total` | 混合 | med 1.81s×3,934・total 40,592s・max 991s | 第九弾#3偵察済み(report_publication特定)。是正実装の残課税を攻撃 |
| 7 | `heavy_job_admission:queue_wait` | 外れ値 | med 3.00s×358・total 28,010s・max 1,222s | 第九弾#2(#1後直列)。lock競合の構造根治 |

- 弾#1-#3は第八弾wave checkpoint確定後に着手。#5・#7は第九弾是正完了後。#4・#6は独立writer
- 前弾進行中の標的は前弾クローズを待つ(重複作業回避)。Tier 2で前弾クローズ後も依然TOPなら第十弾で是正開始

## §2.5 進捗台帳(初版 — 未着手)

| # | 標的 | 状態 | 帰結(実測生値) |
|---|---|---|---|
| 1 | refresh_window | ⏳第八弾wave checkpoint待ち | — |
| 2 | refresh_copy | ⏳第八弾wave checkpoint待ち | — |
| 3 | refresh_verify | ⏳第八弾wave checkpoint待ち | — |
| 4 | affected_tests | ⏳着手可(独立writer) | — |
| 5 | execution | ⏳第九弾#1是正完了待ち | — |
| 6 | deploy_total | ⏳着手可(独立writer) | — |
| 7 | queue_wait | ⏳第九弾#2完了待ち | — |

+## §2.5.1 テスト修正・高速化の共通知見(第八弾実証・以後継承)

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
| 第十弾の起動 | 殿発案2026-08-04 23:29。裁可待ち |
| 二段計測の導入 | 殿設計2026-08-04 23:34(Tier 1劣化検知+Tier 2ボトルネック特定)。第十弾から恒久導入。裁可対象 |
| 序列snapshot | 起草時実測済み(§0=2026-08-04 23:32・直近24時間) |
| 弾数・標的固定 | TOP7。殿裁可で固定 |
| 前弾との直列条件 | #1-#3=第八弾wave後、#5/#7=第九弾是正後。裁可対象 |
| 高速化と防御力の境界 | **確定**: 検証力不変・fail-closed維持・チェック間引き禁止(LS099/殿裁定07-21) |

## §4 5W1H

- **WHY**: 前週比(Tier 1)のみでは「改善済みだが依然遅い」「新たに遅くなった」が盲点。直近24h絶対値(Tier 2)で今この瞬間の最大の敵を炙り出し再攻撃する(殿指摘2026-08-04 23:29)
- **WHAT**: TOP7を全て再標的化。前弾成果引継ぎ+残課税攻撃。恒常型=子区分→最大寄与是正/外れ値型=発火条件→条件是正。検証力不変
- **WHEN**: 第八弾wave checkpoint確定後(refresh系残課税確定)に順次着手。独立writerの#4・#6は先行可
- **WHERE**: `scripts/`配下のthree_layer_health系・git_pre_commit・heavy_job_admission系・deploy_task.sh。台帳=`logs/defense_overhead.jsonl`
- **WHO**: 偵察・是正=忍者(read-only冗長2名可+是正は単独所有)、検分=家老+軍師、裁可=殿
- **HOW**: レーン方式(将軍下知→家老配備→lane名CLEAR→最終checkpoint品質2原則検分)。Tier 1+Tier 2の二段計測で効果確認

## §5 因果リンク

- → [[hot-script-speedup-round8-asis-tobe-5w1h_20260804]] 前弾(wave checkpoint進行中)。refresh系#1-#3の成果引継ぎ元
- → [[hot-script-speedup-round9-asis-tobe-5w1h_20260804]] 前弾(レーン配備中)。execution/#1・queue_wait/#2・deploy_total/#3の成果引継ぎ元
- → [[hot-script-speedup-round11-asis-tobe-5w1h_20260804]] 同時起草の姉妹弾(8-15位)
- → [[殿裁定_削るな速くしろ_20260721]] 品質を保ったまま超速化=憲法(knowledge:569abc55)
- → [[ledger-driven-campaign-lane-pattern_20260714]] レーン方式の型元
- → [[殿裁定_厳密さは最終チェックのみ_20260714]] 途中try最大化・報告整形は最終集約
- origin: `[[殿発案_第十弾_二段計測_20260804]] -> [[直近24hボトルネックTOP7]] -> [[前弾成果引継ぎ+残課税再攻撃]]`
