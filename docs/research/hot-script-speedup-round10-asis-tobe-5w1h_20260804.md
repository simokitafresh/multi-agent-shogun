<!-- gist-master: 98f42e727bea67ad5dd322e6756bc45b hot-script-speedup-round10-asis-tobe-5w1h_20260804.md -->
# ホットスクリプト集中高速化 第十弾 — 二段計測でTOP7再攻撃 — AsIs/ToBe 5W1H設計書 v1.18 【🚀裁可済み・#3測定可能no-change確定】

> v1.18(2026-08-06 01:00正式判定同期): #3 `refresh_verify`は軍師がFAIL判断を妥当とレビューし、家老ACCEPT後に正式FAIL-close。1.036GB fixture・5方式×3反復の比較で、既存quick+FTS oracleを全て保持し10%以上改善する候補は0/5だったため、tracked変更0の測定可能no-changeとして閉じた。これにより#3を未完了実装へ誤遷移させず、提案台帳の次標的だけへ進む。

> v1.17(2026-08-06 00:54実測同期): #3 r2は固定1.036GB fixtureで現行refresh全体3反復、verify 5方式×各3反復を完走。現行pair=13,215/14,298/15,368ms、quick_only=7,561/7,579/7,757ms、fts_search=132/153/159ms、row_count_max=224/237/240ms、schema_sample=173/202/212ms。ただし既存quick+FTS oracleを全て守るのはcurrent_pairだけで、品質不変かつ10%以上改善する採用候補は0/5。直近24hはverify n=355/p50=14,649ms/p95=53,271ms/max=108,827ms/total=6,430,343ms、group欠損=copy有verify無22・verify有copy無7・window begin/end片側47。FAIL0・SKIP0・row mismatch0、tracked owner変更0。報告は軍師レビュー中で、正式判定前に実装へ進めない。

> v1.16(2026-08-06 00:39契約是正): #3初回taskはAC2本文が未引用`#2`で始まりYAMLコメント扱いとなって`null`化したため実行前BLOCK。旧task/reportを`cancelled`終端し、AC1-AC4非空4/4・task/report fingerprint `a9e7075f`一致のr2 `cmd_karo_round10_lane3_refresh_verify_recon_r2_20260806`を正規再配備した。才蔵paneでr2読込・旧世代不適用を一次確認し、軍師もr2 APPROVE（evidence `msg_20260806_003831_944283_7c113aaf`）。標的・owner・最低5方式・1GB級fixture契約は不変。

> v1.15(2026-08-06 00:33進捗同期): #2固定HEAD `180a3894`で同一writerを解放し、#3 `three_layer_health:refresh_verify` のread-only偵察 `cmd_karo_round10_lane3_refresh_verify_recon_20260806` を才蔵へ配備。nudge到達・SessionStart・作業開始をpane一次確認済み。1GB級同一fixture×3反復以上、内部phase分解、最低5方式の/tmp独立probe総当たり、品質oracle全PASSかつp50/p95非悪化・一方10%以上改善の候補一意化を要求。tracked変更0、提案外owner混入0を維持する。

> v1.14(2026-08-06 00:27進捗同期): #2 `three_layer_health:refresh_copy` は軍師LGTM・家老ACCEPT・`cmd_complete_gate` CLEAR・`/cmd-complete`完了。commit `180a3894`、1GB同一fixture×3反復でrefresh_copy p50/p95=7,897/10,464ms→4,300/9,724ms、refresh_window p50/p95=28,081/29,442ms→18,165/24,422ms。FAIL0・SKIP0・row mismatch0、家老独立敵対試験込み10/10 PASS、変更owner `scripts/memory_db_live_insert.py`一件のみ。これにより同一writer直列の#3 `refresh_verify` は着手可能となった。

> v1.13(2026-08-06 00:18進捗同期): #2 commit `180a3894`は厳密な全prefix全列比較を維持し、1GB同一fixture×3反復でrefresh_copy p50/p95=7,897/10,464ms→4,300/9,724ms、refresh_window p50/p95=28,081/29,442ms→18,165/24,422ms。FAIL0・SKIP0・row mismatch0。家老独立でtimestamp不変prefix敵対試験を含む10/10 PASSを確認し、現在は軍師最終レビュー待ち。ACCEPT前なので#3は未着手を維持する。

> v1.12(2026-08-05 23:53進捗同期): #2再是正commit `a44de3202`はtimestamp不変の旧行内容変更+append敵対試験を家老pytestで1/1 PASSし、任意prefix mutationの品質穴は閉じた。一方、方式を`maxts`比較から全prefix全列のATTACH JOIN比較へ変更した後の1GB性能を再測定せず、reportは旧方式のp50/p95を再掲していたためAC4未達で再RC。現commitを同じ1GB fixture・同じ3反復で測り、品質不変と10%以上改善を同時に満たすまで#2をCLOSEしない。

> v1.11(2026-08-05 23:30進捗同期): #2初回RC是正commit `df400ee75`は、既存試験（旧行`updated_at`変更+append）1/1とcontract 9/9をPASSしたが、家老の追加敵対試験（旧行`raw_content`のみ変更・timestamp不変+append）でfull fallback期待1回に対し実測0回となり、任意prefix mutation拒否契約の偽緑を検出した。軍師LGTM後も家老ACCEPTせず、正式RCへ戻して同じowner `scripts/memory_db_live_insert.py`一件だけで再是正中。#3は引き続き未着手。

> v1.10(2026-08-05 22:34進捗同期): #1固定HEAD後の同一owner直列レーンとして、#2 `three_layer_health:refresh_copy` 実装 `cmd_karo_round10_lane2_refresh_copy_impl_20260805` を軍師LGTM(fingerprint `0bc4c2ef`)後に影丸へ配備し、nudge到達・作業開始を一次確認。本番同等容量または容量スケーリング3点以上でfull/incremental/source read/output write/fsync-replace/競合/残差を全実測し、小DBだけの誤PASSを禁止する。変更許可は引き続きowner `scripts/memory_db_live_insert.py`一件のみ。

> v1.9(2026-08-05 22:28進捗同期): #1実装は小ledger fixtureの初回PASSを家老が41MB/194,673行の本番同等ledgerで再測定し、同期batch p50=703.954ms・旧方式比約2.64倍遅延を検出してRC。RC後commit `4875ea831` はbytes一括探索へ改め、41MB級同一fixtureのrefresh全window p50/p95=1,040.98/1,040.98ms→596.47/596.47ms(42.7%改善)、家老独立再測定batch p50=104.986ms、既存contract 9/9 PASS、FAIL0、SKIP0、最終変更owner 1件でGATE CLEAR。#2 refresh_copyは同一writer直列条件を満たし着手可。

> v1.8(2026-08-05 21:59進捗同期): #1 read-only偵察は全期間n=8,608/p50=26.028s/p95=70.956s/max=320.043s/total=259,641.604s、p95 tail=432件、duplicate=0、完全group=229件、いずれかidentity欠測group=203件を確定して正式FAIL-close。正しいowner `scripts/memory_db_live_insert.py:681-855`だけを変更可能とする実装レーン `cmd_karo_round10_lane1_refresh_window_impl_20260805` を軍師LGTM(fingerprint `684489d3`)後に半蔵へ配備した。5仮説を同一fixture・同一反復数で総当たりし、品質不変かつp50/p95非悪化・一方10%以上改善を満たすまで、#2/#3は同一writer直列待ちを維持する。

> v1.7(2026-08-05 20:22 scope正規化): 提案弾台帳と進捗台帳の標的identifierは7/7一致していたが、実装owner pathが未定義で、#1-#3を`gate_three_layer_health.sh` writerと誤記していた。一次コード突合により#1-#3=`scripts/memory_db_live_insert.py`、#4=`scripts/hooks/git-pre-commit.sh`、#5/#7=`scripts/heavy_job_admission.sh`、#6=`scripts/deploy_task.sh`と確定。両台帳を同じidentifier+owner pathへ正規化し、列挙外pathの高速化・変更を禁止する。進行中#1はread-only対応証明までで停止し、実装変更0件を維持する。

> v1.6(2026-08-05 20:16再開): #1 refresh_window偵察 `cmd_karo_round10_lane1_refresh_window_recon_20260805` を配備。read-onlyで現ledger再計数→p95以上の発火条件・call path・phase全件分類→最大寄与または追加identity契約を一意化する。nudge到達・SessionStart・作業開始をcapture-paneで一次確認し、軍師draftレビューもLGTM。#2/#3は同一writerのため#1固定HEAD後まで直列待ちを維持する。

> v1.5(2026-08-05 19:05依存訂正): v1.4まで第八弾#1-#3をwave checkpoint待ちとしたのは誤り。第八弾v1.6は2026-08-05 15:25に固定HEAD `5aad3a61ecdd826a10271e296b3c8ed14b3cbec7`、214/214ファイル、3,122/3,122 PASS、FAIL0、SKIP0、`complete=1`、`full_scope=true`で実装・品質checkpoint CLOSE済み。よって第十弾#1を即着手可へ解除し、同一writer `gate_three_layer_health.sh` のため#1→#2→#3直列とする。前弾依存待ちは第九弾に依存する#5/#7の2件だけへ訂正した。

> v1.4(2026-08-05 18:59進捗・判断整合同期): 一次実績自体はv1.3から不変。実走1/7、実装GATE CLEAR 0、正式FAIL-close 1、配備前保留1、前弾依存待ち5。§2.5に進捗総括・再開順序・完了条件を追加し、§3/§4に残っていた「裁可対象」「先行可」を現行裁定・実態へ更新した。#4は親hook event↔test timing identity計装後に再開、#6は`deploy_task.sh`の既存owner解放後に配備する。

> v1.3(2026-08-05 18:53進捗同期): 2026-08-05 18:03将軍下知で起動。#4 affected_testsは現行ledgerの劣化と親hook↔test timing identity欠落を一次確定し、focused実走のFAILも隠さず正式FAIL-close。#6 deploy_totalは配備案レビューLGTMまで完了したが、既存dirtyな`deploy_task.sh`とのwriter衝突を検知して未配備保留。その他は依存wave待ち。

> v1.2(2026-08-05 02:40 殿裁定): §2.6 checkpoint契約を追加(全弾共通)

> v1.1(2026-08-04 23:46覚醒更新): 殿指示『第九弾と同じ粒度同じ水準で覚醒して作成せよ』。§-1スコープ拡充(writer構造・前弾境界・スコープ外)、§1計測境界(第九弾継承+Tier 2追加)、§2 To-Be(9項目)、弾台帳に型・現状・手筋候補追加、§2.5進捗台帳・§3 decision ledger・§5因果リンク新設

> 初版起草(2026-08-04 23:34。殿発案23:29『第十弾は実際に今この瞬間にボトルネックになっている遅いものを改めてやりたい』『トップ7全部をもう一度やるべきだ』『修正後1週間のledger累積課税を前週比で総括は劣化を検知、現在のボトルネックは直近24時間で計測の二段構え』)

> シリーズ: ホットスクリプト集中高速化。第一弾〜第七弾=✅CLOSED / **第八弾**=✅実装・品質checkpoint CLOSED(正式速度効果のみ1週間ledger待ち) / **第九弾**=一部CLEAR・FAIL群保留 / **第十弾=本書(進行中)** / 第十一弾=8-15位(進行中)

## §-1 スコープと境界(数と原理を先に固定)

- **標的=直近24時間の累積課税TOP7**。第八弾(refresh系)・第九弾(外れ値型+配備経路)で改善済みでも**依然TOPなら再攻撃する**。「改善済みだからスコープ外」は洗脳#1(早期終了)
- **二段計測(殿設計2026-08-04 23:34 — 本弾から恒久導入)**:
  - **Tier 1 劣化検知**: 修正後1週間のledger累積課税を前週比で総括。退行を機械的に検出。wave最終checkpointの既存契約
  - **Tier 2 ボトルネック特定**: 直近24時間の絶対値で累積課税TOP Nを序列化。「今この瞬間の最大の敵」を機械的に炙り出す。**前週比のみでは「改善済みだが依然遅い」「新たに遅くなった」が盲点**(殿指摘)。Tier 2で補完
- **前弾との境界**: 第八弾は実装・品質checkpoint CLOSE済みのため#1-#3の依存条件を満たした。第九弾標的と重複する#5/#7だけは同弾の該当是正を待ち、成果を引き継いだ残課税を攻撃する
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

| # | 標的identifier | 高速化許可owner path | 型 | 現状(直近24h) | 手筋候補(実測で裏取り後) |
|---|---|---|---|---|---|
| 1 | `three_layer_health:refresh_window` | `scripts/memory_db_live_insert.py` | 恒常 | med 25.64s×8,300・total 245,481s | 第八弾#1成果引継ぎ。wave checkpoint後に残課税を確定→残構造を偵察 |
| 2 | `three_layer_health:refresh_copy` | `scripts/memory_db_live_insert.py` | 恒常 | med 12.40s×7,385・total 111,764s | 第八弾#2成果引継ぎ。同上 |
| 3 | `three_layer_health:refresh_verify` | `scripts/memory_db_live_insert.py` | 恒常 | med 12.31s×7,507・total 92,710s | 第八弾#3成果引継ぎ。同上 |
| 4 | `git_pre_commit:affected_tests` | `scripts/hooks/git-pre-commit.sh` | 恒常+裾 | med 4.82s×1,132・total 74,925s・max 1,334s | 第八弾#4(-65%)後の残裾。p95上位のtest set同定→裾削減 |
| 5 | `heavy_job_admission:execution` | `scripts/heavy_job_admission.sh` | 外れ値 | med 3.00s×762・total 66,859s・max 1,191s | 第九弾#1偵察済み(p99上位job同定)。是正実装の残課税を攻撃 |
| 6 | `deploy_task:deploy_total` | `scripts/deploy_task.sh` | 混合 | med 1.81s×3,934・total 40,592s・max 991s | 第九弾#3偵察済み(report_publication特定)。是正実装の残課税を攻撃 |
| 7 | `heavy_job_admission:queue_wait` | `scripts/heavy_job_admission.sh` | 外れ値 | med 3.00s×358・total 28,010s・max 1,222s | 第九弾#2(#1後直列)。lock競合の構造根治 |

- **scope不変量**: 高速化・変更を許可するのは上表4 owner pathだけ。テスト・台帳・call path依存はread-only参照に限り、進捗行・高速化対象・変更scopeへ混ぜない。owner追加は提案弾台帳を先に改版してから行う
- 第八弾wave checkpointは完了済み。refresh三標的は同一writer `scripts/memory_db_live_insert.py` のため#1→#2→#3を直列実施する。#5・#7も同一writerゆえ#5→#7直列。#4・#6は独立writer
- 第八弾完了後もrefresh三標的はTier 2で依然TOPのため、第十弾で再攻撃する。前弾待ちを理由に停止しない

## §2.5 進捗台帳(2026-08-06 01:00家老更新)

| # | 標的identifier | 高速化許可owner path | 状態 | 帰結(実測生値) |
|---|---|---|---|---|
| 1 | `three_layer_health:refresh_window` | `scripts/memory_db_live_insert.py` | ✅**GATE CLEAR** | `cmd_karo_round10_lane1_refresh_window_impl_20260805`。41MB級同一fixtureの全window p50/p95=1,040.98/1,040.98ms→596.47/596.47ms(42.7%改善)。家老独立再測定batch p50=104.986ms、contract 9/9 PASS、FAIL0、SKIP0。commit `7c461e2a0`+RC `4875ea831`、最終変更owner 1件 |
| 2 | `three_layer_health:refresh_copy` | `scripts/memory_db_live_insert.py` | ✅**GATE CLEAR** | `cmd_karo_round10_lane2_refresh_copy_impl_20260805`。commit `180a3894`。1GB×3反復でcopy p50 45.5%、window p50 35.3%改善、両p95非悪化。FAIL0・SKIP0・row mismatch0。家老独立10/10 PASS、軍師LGTM・家老ACCEPT・`/cmd-complete`完了。変更owner一件のみ |
| 3 | `three_layer_health:refresh_verify` | `scripts/memory_db_live_insert.py` | ⏹️**測定可能no-change・正式FAIL-close** | `cmd_karo_round10_lane3_refresh_verify_recon_r2_20260806`。1.036GB、5方式×3反復完走。既存quick+FTS oracleを全維持して10%以上改善する候補0/5。24h group欠損22/7/47を検出。FAIL0・SKIP0・row mismatch0、tracked変更0。軍師レビュー妥当・家老ACCEPT済み |
| 4 | `git_pre_commit:affected_tests` | `scripts/hooks/git-pre-commit.sh` | ⚠️**正式FAIL-close** | `cmd_karo_round10_lane4_affected_tests_20260805`: baseline n=1,132/p50=4.82s/p95=336.8s/max=1,334.2s/total=74,925s → current n=1,187/p50=4.85s/p95=342.841s/max=1,975.901s/total=82,794.087s。p95上位60/60にtest set・selection_count・files_selected・call-path属性なし、hook event_idとtest_timing run_idのjoin不能。focusedは6ファイル選択・1 FAIL。コード変更/commitなし、家老ACCEPT・archive済み。次手は親hook event↔test timing identity計装 |
| 5 | `heavy_job_admission:execution` | `scripts/heavy_job_admission.sh` | ⏳第九弾#1是正完了待ち | — |
| 6 | `deploy_task:deploy_total` | `scripts/deploy_task.sh` | ⏸️**配備前保留(writer衝突)** | draft review LGTM済み。ただし`deploy_task.sh`が既存dirty(MM)でlane所有権を確保できず、変更を重ねず未配備。既存owner解放後に再判断 |
| 7 | `heavy_job_admission:queue_wait` | `scripts/heavy_job_admission.sh` | ⏳第九弾#2完了待ち | — |

- **進捗総括(7標的母数)**: 実装GATE CLEAR#1/#2=2/7、測定可能no-change#3=1/7、正式FAIL-close#4=1/7、配備前保留#6=1/7、第九弾依存待ち#5/#7=2/7。閉鎖済み4/7、提案外ownerの進捗混入0件、第八弾依存待ち0件。
- **確定した次手**: (1)#4 identity計装後に再実走 (2)`deploy_task.sh`既存owner解放後に#6配備 (3)第九弾該当是正確定後に#5→#7。#3へ品質を落とす実装は行わない。
- **完了条件**: 7標的を全てGATE CLEARまたは測定可能なno-changeで閉じ、§2.6の固定HEAD分割checkpointをFAIL0・SKIP0・duplicate0・missing0で通過後、Tier 1前週比とTier 2直近24h序列を再計測してCLOSEする。現時点の終了目処は#1→#2→#3直列、#4 identity、#6 owner、第九弾#5/#7依存の解消順で規定する。

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
| 第十弾の起動 | **裁可・起動済み**。#4正式FAIL-close後、2026-08-05 20:16に#1 refresh_window偵察を配備・作業開始一次確認。#6はwriter衝突で配備前保留 |
| 二段計測の導入 | **確定**。殿設計2026-08-04 23:34(Tier 1劣化検知+Tier 2ボトルネック特定)を第十弾から恒久導入 |
| 序列snapshot | 起草時実測済み(§0=2026-08-04 23:32・直近24時間) |
| 弾数・標的固定 | **確定**。TOP7を母数とし、途中FAIL/保留でも標的を削らない |
| 前弾との直列条件 | **第八弾条件は充足済み**。#1→#2→#3は同一writer直列で即開始可。#5/#7のみ第九弾是正待ち。#4はidentity待ち、#6はwriter owner待ち |
| 高速化と防御力の境界 | **確定**: 検証力不変・fail-closed維持・チェック間引き禁止(LS099/殿裁定07-21) |

## §4 5W1H

- **WHY**: 前週比(Tier 1)のみでは「改善済みだが依然遅い」「新たに遅くなった」が盲点。直近24h絶対値(Tier 2)で今この瞬間の最大の敵を炙り出し再攻撃する(殿指摘2026-08-04 23:29)
- **WHAT**: TOP7を全て再標的化。前弾成果引継ぎ+残課税攻撃。恒常型=子区分→最大寄与是正/外れ値型=発火条件→条件是正。検証力不変
- **WHEN**: 起動済み。第八弾checkpoint完了により#1を即時開始し、#1→#2→#3を同一writer直列で進める。#4はidentity計装後に再開、#6はwriter owner解放後、#5/#7は第九弾該当是正後に着手
- **WHERE**: `scripts/`配下のthree_layer_health系・git_pre_commit・heavy_job_admission系・deploy_task.sh。台帳=`logs/defense_overhead.jsonl`
- **WHO**: 偵察・是正=忍者(read-only冗長2名可+是正は単独所有)、検分=家老+軍師、裁可=殿
- **HOW**: レーン方式(将軍下知→家老配備→lane名CLEAR→最終checkpoint品質2原則検分)。Tier 1+Tier 2の二段計測で効果確認

## §5 因果リンク

- → [[hot-script-speedup-round8-asis-tobe-5w1h_20260804]] 前弾(実装・品質checkpoint CLOSED)。refresh系#1-#3の依存解除・成果引継ぎ元
- → [[hot-script-speedup-round9-asis-tobe-5w1h_20260804]] 前弾(レーン配備中)。execution/#1・queue_wait/#2・deploy_total/#3の成果引継ぎ元
- → [[hot-script-speedup-round11-asis-tobe-5w1h_20260804]] 同時起草の姉妹弾(8-15位)
- → [[殿裁定_削るな速くしろ_20260721]] 品質を保ったまま超速化=憲法(knowledge:569abc55)
- → [[ledger-driven-campaign-lane-pattern_20260714]] レーン方式の型元
- → [[殿裁定_厳密さは最終チェックのみ_20260714]] 途中try最大化・報告整形は最終集約
- origin: `[[殿発案_第十弾_二段計測_20260804]] -> [[直近24hボトルネックTOP7]] -> [[前弾成果引継ぎ+残課税再攻撃]]`
