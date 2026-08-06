<!-- gist-master: fc4b27c4031149d7d6b45fde49028942 hot-script-speedup-round8-asis-tobe-5w1h_20260804.md -->
# ホットスクリプト集中高速化 第八弾 — 三層記憶health+常時課税層 — AsIs/ToBe 5W1H設計書 v1.7 【✅CLOSED】

> **CLOSED**(2026-08-06 将軍刻印): 実装GATE CLEAR 12/12、品質checkpoint完了(214/214 PASS、3,122/3,122 PASS、FAIL 0、SKIP 0)。旧偵察FAIL 3/3は正式FAIL-closeで偽CLEARなし。正式効果は修正後1週間ledger前週比で別途確定(v1.6時点で未成熟)。

> v1.6(2026-08-05 15:25): shard4固定HEAD `5aad3a61ecdd826a10271e296b3c8ed14b3cbec7` の全量unit receiptを確定。214/214ファイル、宣言/観測3,122/3,122、FAIL 0、SKIP 0、rc=0、`complete=1`、`full_scope=true`。品質checkpointをCLOSEし、第八弾の実装・品質ゲートを完了扱いとする。

> v1.5(2026-08-05 02:38 殿裁定): §2.6 checkpoint契約を追加。full/wave全量テストの3〜4名並列分割・固定HEAD・receipt和集合判定を全弾共通契約として明記

> v1.4(2026-08-04 23:10進捗同期): 第八弾本体・偵察・実装の対象12/12 GATE CLEARを一次台帳で確認。旧偵察FAIL 3件は後続是正へ還流済みとして正式FAIL-close 3/3。効果checkpointは8/8lane再計数・48/48 PASS、品質checkpointはv1.6で完了。1時間fixed-windowは対照群ドリフトを含むため正式効果へ昇格せず、修正後1週間ledger前週比を待つ。

> v1.3(2026-08-04 15:36 殿裁可『開始しよう』): 弾台帳固定。**レーン方式で開始**(第五・七弾の型: 将軍下知blt_154140→家老レーン配備。cmd正式起票はしない=殿指摘15:39で方式確認済み)。弾#0'(計測盲点根絶)を先行、以後#1→#2→#3直列+#4以降独立並列

> 状態: v1.2(2026-08-04 11:45 殿指示『計測可能にせよ』『第八弾の設計書をアップデートせよ。他に未計測で漏れているモノがないかも調査せよ』— §0.5計測盲点サーベイを追加。cmd_save save_total計装をD0実装済み(将軍・動作確認row出力済み)。弾台帳へ弾#6と計測盲点根絶レーンを追加) / v1.1覚醒更新(2026-08-04 09:07 殿指示『設計書は覚醒してアップデートせよ』— §0を最新ledger 166,956行で再実測。**序列不変**を確認、弾台帳・境界に変更なし) / 初版起草(2026-08-04 02:50。殿発案02:44『第八弾をやろう。まずは同じ形式で設計書を』)

> シリーズ: ホットスクリプト集中高速化。第一弾=`hot-script-speedup-asis-tobe-5w1h_20260727.md`✅ / 第二弾=`hot-script-speedup-round2-asis-tobe-5w1h_20260728.md`✅ / 第三弾=`hot-script-speedup-round3-asis-tobe-5w1h_20260728.md`✅ / 第四弾=`hot-script-speedup-round4-asis-tobe-5w1h_20260728.md` / 第五弾=`hot-script-speedup-round5-asis-tobe-5w1h_20260729.md`✅ / 第六弾=`throughput-bottleneck-part2-asis-tobe-5w1h_20260728.md`(identity基盤完成・P1b蓄積待ち) / 第七弾=`hot-script-speedup-round7-test-speed-asis-tobe-5w1h_20260729.md`✅(全量wall -3.35%確定) / **第八弾=本書**

## §-1 スコープと境界(数と原理を先に固定)

- **標的=エージェント実働時に毎回課税されるホットスクリプトの実行時間のみ。防御の検証力は1点も削らない**(品質2原則=正本突合判定+境界fixture両方を維持。殿裁定2026-07-21『削るな、速くしろ』が本弾の憲法)
- **弾数=序列確定済みゆえ本書で決め打ち提案**(§0の一次実測に基づくTOP5+補欠2。殿裁可で固定し途中追加しない)
- **writer構造(第五・七弾の写像)**: 1スクリプト(の1ホットパス)=1弾=1レーン。共有層(`scripts/lib/`・三層記憶の共通読み書き)に触れる弾は独立writerかつ先行→固定HEADで再計測→個別弾の直列依存。並列変更禁止
- **スコープ外**: gate/hookの削除・条件緩和(必須ハーネス保持=LS099)/テスト実行時間(第七弾の領分・CLOSED)/DM-Signal側Python(別repo)/deploy_task残候補③report_publication・④ninja_scope_commit(第六弾系譜の残在庫として別管理)

## §0 序列SSOT(2026-08-04 02:47 将軍一次実測 — 既存台帳のみ・新台帳なし)

**取得方法**: `logs/defense_overhead.jsonl`(166,956行 — v1.1覚醒再実測2026-08-04 09:07)から2026-07-28以降の112,089行を抽出し、source:check_id別にwall_msの中央値と累積(=課税総量)を算出。集計コマンドと生出力は本節の値がそのまま転記(1件=jsonl 1行=1計測イベント)。**v1.0(02:47実測・110,111行)→v1.1で+1,978行増えても序列は完全不変**。**累積時間はagent-hours(全CLI合算)**=9並列CLI(忍者6+家老+軍師+将軍)の全呼出しの合計であり、壁時計の24h/日を超えうる。

### 中央値序列(1回あたりの重さ)

| 順 | source:check_id | median | n | 累積 |
|---|---|---|---|---|
| 1 | `three_layer_health:refresh_verify` | **12.44s** | 5,540 | 70,362s |
| 2 | `three_layer_health:refresh_copy` | **12.28s** | 5,603 | 85,093s |
| 3 | `gate_gunshi_report_precheck:full_precheck_body_rest` | 5.27s | 791 | 5,260s |
| 4 | `git_pre_commit:affected_tests` | 3.87s | 666 | 28,868s |
| 5 | `deploy_task:deploy_total` | 1.86s | 2,324 | 17,549s |
| 6 | `gate_gunshi_report_precheck:full_precheck` | 1.22s | 1,898 | 9,205s |

### 累積課税序列(システム全体の重さ)

| 順 | source:check_id | 累積 | median | n |
|---|---|---|---|---|
| 1 | `three_layer_health:refresh_window` | **165,352s(≈45.9h)** | 0.00s | 11,141 |
| 2 | `three_layer_health:refresh_copy` | **85,093s(≈23.6h)** | 12.28s | 5,603 |
| 3 | `three_layer_health:refresh_verify` | **70,362s(≈19.5h)** | 12.44s | 5,540 |
| 4 | `git_pre_commit:affected_tests` | 28,868s | 3.87s | 666 |
| 5 | `heavy_job_admission:execution` | 28,453s | 0.00s | 1,235 |
| 6 | `deploy_task:deploy_total` | 17,549s | 1.86s | 2,324 |
| 7 | `inbox_write:inbox_write_total` | 16,960s | 0.33s | 8,400 |
| 8 | `gate_report_format:singleflight_hold` | 11,138s | 0.25s | 3,644 |
| 9 | `gate_gunshi_report_precheck:full_precheck` | 9,205s | 1.22s | 1,898 |
| 10 | `heavy_job_admission:queue_wait` | 8,764s | 0.00s | 1,299 |

**読み**: 両序列でthree_layer_health系が圧倒的TOP。refresh_copy+refresh_verify+refresh_windowの3 check合算で**約320,800s≈89.1時間/週**の課税。中央値12秒級×1万回超の反復=恒常課税型の教科書例。median 0.00sのrefresh_window/heavy_job系は長い裾(外れ値型)であり、恒常型と別の手筋が要る。v1.1追記: 本セッション(CI RED対応で高頻度活動)でも序列・中央値とも安定=標的選定はノイズでなく構造。

## §0.5 計測盲点サーベイ(v1.2追加 — 殿指示2026-08-04 11:38『計測可能にせよ』『未計測で漏れているモノを調査せよ』)

**発端**: cmd_save --preflightのwall実測≈150s/回に対し、ledger計装済みcheck合計は≈12s/回(2026-08-04将軍実測: checks_main max5.2s+three_layer 6.2s+pre_session 1.0s)。**差分≈9割が台帳の外**=序列に載らず改善対象に上がらない構造欠陥。計測なき区間は存在しないのと同じに扱われる。

**D0是正済み(2026-08-04 11:43将軍実装・動作確認済み)**: cmd_save.shへ`save_total`(script開始→EXITの全wall・未計装区間込み)を計装。検証row実出力: `{"source":"cmd_save","check_id":"save_total","wall_ms":2231,"verdict":"PASS"}`。以後、preflight全体の実コストが台帳の序列へ自動で載る。

**サーベイ結果A — 台帳接続済みだがtotal計測なし(7 source、区間の切れ端のみで全体像不明)**:

| source | 現状checks | 欠落 |
|---|---|---|
| three_layer_health | 5(refresh_copy/verify/window等) | **script全体total**(現TOP課税源なのに全体walが無い) |
| git_pre_commit | 13 | total(affected_tests単体は有るが全hook wall無し) |
| gate_report_format | 3 | total |
| completion_finalize / dashboard_update / review_approval / self_retro | 各1-2 | total |

**サーベイ結果B — 台帳完全未接続のホットスクリプト(grep defense_overhead=0件)**:

| script | 性質 |
|---|---|
| gate_shogun_startup.sh / gate_karo_startup.sh / gate_gunshi_startup.sh | 毎/clear必発。体感で分単位だが1行も計測なし |
| semantic_index_update.sh | 高頻度デーモン系 |
| ninja_scope_commit.sh | 全commit経路(第六弾残候補④=46sの体感値のみ) |
| cmd_delegate.sh | 全cmd配備経路 |

**原理(本弾憲法への追記)**: 「エントリポイントには必ず*_total計装を置く」。子区分の精密化より先に、まず全体walを台帳に載せる(載らないものは序列に上がらず、序列に上がらないものは改善されない)。

## §1 計測境界(憲法・第五〜七弾継承)

- 計測=既存台帳のみ(`logs/defense_overhead.jsonl`)。**新台帳禁止**(車輪の再発明防止 knowledge:fbb5716c)
- before/afterは**同一スクリプト・同一check_id・同一環境**のfixed-window比較(修正commit時刻を境に前後同日数のmedian±分布)。異なるcheck_idの混算禁止
- run間ノイズ: 各check_idの分布(p25/p75)を先に取り、Δ有意判定はノイズ帯超のみ
- 効果宣言=個別Δの総和ではなく、**修正後1週間の累積課税(total秒)の前週比**を正式確定値とする(第七弾の「focused Δ≠全量Δ」教訓の写像)

## §2 To-Be — 進め方(型を継承)+品質底線

1. **1標的=1弾・複合弾禁止**。恒常課税型(three_layer_health)=子区分計測→最大寄与是正/外れ値型(refresh_window・heavy_job)=発火条件特定→条件ベース是正
2. **品質底線**: (a)防御の検証力不変=三層health検証のfail-closed挙動・検証対象・判定閾値を全て固定。検証を弱める高速化(サンプリング化・チェック間引き)は禁止 (b)PASS/FAIL挙動不変=是正前後で同一入力の判定完全一致 (c)敵対fixture=是正で変更した独立oracle・副作用境界ごとに1点(破損DB・staleコピー・部分書込みを検出できることを確認)
3. 仮説在庫(序列裏取り済みの初期観察のみ・事前外挿禁止): refresh_copy 12.3s=721MB級DB実コピーの疑い(第六弾cmd_4111でrelated_lessonsの同型問題をcache SSOT化で-98.5%にした前例あり)/refresh_verify 12.4s=コピー後の全量検証の疑い→incremental verify・mtime+hash短絡・WAL checkpoint方式の検討/refresh_window median 0=発火条件(何が11,069回も起きているか)の特定が先
4. **反復サイクル型**(殿裁定2026-07-29 13:26): ローカル極限化→live計測→差分再検証→再極限化。停止条件=Δがノイズ帯以内でクローズ(採用またはno-change)
5. **read-only冗長並列**(殿裁定13:28): 序列子区分計測・発火条件記録はread-only冗長2名先着採用可。是正実装は単独所有
6. 個別弾は選択実行(`bash scripts/run_tests.sh file <対象>`)FAIL0・SKIP0のみ。途中try回数最大化・厳密さは最終checkpointへ集中(殿裁定2026-07-14)
7. 完了宣言=全弾クローズ→修正後1週間のledger累積課税を前週比で総括→CLOSE刻印
8. **lane最小AC/wave checkpointの二層契約(殿裁定2026-08-04 19:26で恒久化・本弾進行中レーンへ即時適用)**: 【lane最小AC】focused fixture PASS+コード変更確認+p50/p95非悪化のみ。scope外全量テスト・並行中固定HEAD比較・commit後全量再測定を途中レーンに課すな(小太郎補欠Aレーン9回BLOCK実測=再実走税)。設計baseline差は数値報告して続行。【wave最終checkpoint】全量FAIL0+全lane間独立比較+全量再測定+正式効果確定(1週間ledger前週比)。原理=殿19:10『再実走よりも再配備が高速回転に直結』。経緯=殿AC過剰厳格性監査→軍師5観点(blt_192103)→将軍検分採用→殿恒久裁定

### 提案弾台帳(殿裁可で固定)

| # | 標的 | 型 | 現状 | 手筋候補(実測で裏取り後) |
|---|---|---|---|---|
| 1 | `three_layer_health:refresh_copy` | 恒常課税 | med 12.32s×5,567 | DBコピーの差分化/cache SSOT化(cmd_4111型)/copy自体の要否再設計 |
| 2 | `three_layer_health:refresh_verify` | 恒常課税 | med 12.45s×5,504 | 全量検証→incremental verify+hash短絡(fail-closed維持) |
| 3 | `three_layer_health:refresh_window` | 外れ値 | total 164,549s・med 0s×11,069 | 発火条件特定→呼出し頻度と裾の是正 |
| 4 | `git_pre_commit:affected_tests` | 恒常課税 | med 3.72s×647 | affected解決のキャッシュ化(検出集合は不変) |
| 5 | `gate_gunshi_report_precheck:full_precheck_body_rest` | 恒常課税 | med 5.28s×774 | 子区分計測→最大寄与是正 |
| 補欠A | `inbox_write:inbox_write_total` | 頻度課税 | med 0.33s×8,170 | 呼出し頻度が主因ゆえ効果/リスク比を計測後判断 |
| 補欠B | `gate_report_format:singleflight_hold` | 待機 | total 10,736s | hold時間の分布から真因(lock競合)特定のみ本弾、是正は判断後 |
| 補欠C | review_notifyフェーズ(self_retro支配コスト) | 恒常課税 | INS-20260804-031401742(priority=high・検証passed) | self_retro台帳の遅延分析で支配的コストと特定(殿裁定03:29で台帳合流)。SG7検証の品質不変でレビュー通知フェーズを削減。`gate_gunshi_report_precheck`系(#5)の上流同族ゆえ#5の子区分計測と合同で真因特定 |
| **弾#0'** | **計測盲点根絶(*_total一斉計装)** | 計測基盤 | §0.5サーベイ: total欠落7 source+台帳未接続6 script(startup gate 3本/semantic_index_update/ninja_scope_commit/cmd_delegate) | cmd_save save_totalの実装型(script冒頭T0+EXIT trapで1行write)を全エントリポイントへ横展開。**全弾に先行**(序列に載らないものは改善されない)。cmd_saveの未計装≈140s/回の内訳特定は計装後1週間のledgerで自動判明 |

- 弾#1-#3は同一スクリプト(three_layer_health)の別checkだが、writer共有ゆえ**#1→#2→#3の直列**(共有層先行の原則)。#4以降は独立並列可

## §2.5 進捗台帳(第七弾§-2.4様式 — 2026-08-04 23:10家老更新。gate_metrics/report/task一次突合)

| # | 標的 | 状態 | 帰結(実測生値) |
|---|---|---|---|
| 0' | 計測盲点根絶(*_total一斉計装) | ✅**GATE CLEAR** | 9 entrypoint計装 |
| 4 | `git_pre_commit:affected_tests` | ✅**GATE CLEAR** | **p50 -65%** |
| 5 | `gate_gunshi_report_precheck:full_precheck_body_rest` | ✅**GATE CLEAR** | lane計測 p50 -95.6%。wave正式効果は1週間待ち |
| 1 | `three_layer_health:refresh_copy` | ✅**GATE CLEAR** | append-only差分snapshot |
| 2 | `three_layer_health:refresh_verify` | ✅**偵察A/B+impl GATE CLEAR** | SQL alias 1行補正→9/9 PASS |
| 3 | `three_layer_health:refresh_window` | ✅**偵察Track A/B GATE CLEAR** | begin/end混在→phase分離 |
| 補欠A | `inbox_write:inbox_write_total` | ✅**GATE CLEAR** | caller計装完了 |
| 補欠B | `gate_report_format:singleflight_hold` | ✅**GATE CLEAR** | **logging寄与 -93%** |
| CI fix | missed_sg | ✅**GATE CLEAR** | telemetry非阻害化 |
| reflux fix | insight scope根治 | ✅**GATE CLEAR** | 9回BLOCK根治 |
| RC race fix | archive競合 | ✅**GATE CLEAR** | report-unit lock直列化 |
| skill_refs dup | followup重複根治 | ✅**GATE CLEAR** | 17件→0件 |
| capture guard | watcher自動ガード | ✅**GATE CLEAR** | nudge誤送信防止 |
| same-cmd fix | pending symlink補完 | ✅**GATE CLEAR** | active pending切離し |
| scout gate | 偵察報告再利用 | ✅**GATE CLEAR** | fail-closed検証7ケース |
| active-stall fix | active静止盲点 | ✅**軍師LGTM・GATE CLEAR** | 25分静止・子処理0・prompt0のみ家老通知。自己介入0 |
| wave効果checkpoint | 8lane固定窓再集計 | ✅**完了・正式効果待ち** | 177,600行、8/8lane、48/48 PASS、欠損0・外れ値除外0。正式効果は修正後一週間ledger前週比で確定 |
| wave品質checkpoint | 全量FAIL0/SKIP0+lane独立性 | ✅**完了** | shard4固定HEAD、214/214ファイル、3,122/3,122 PASS、FAIL0、SKIP0、rc=0、complete=1、full_scope=true |

- **本体集計(23:10)**: 第八弾対象の本体・偵察・実装レーンは**GATE CLEAR 12/12**。後続是正へ繋いだ旧偵察FAILは**正式FAIL-close 3/3**で、偽CLEAR 0件。
- **checkpoint**: 効果レーン=完了(8/8lane、48/48 PASS、FAIL0、SKIP0)。品質レーン=完了(214/214ファイル、3,122/3,122 PASS、FAIL0、SKIP0、rc=0)。実装・品質ゲートはCLOSE。正式効果のみ修正後1週間ledger前週比で確定する。
- **局所観測**: lane focused値は#4=-65%、#5=-95.6%、補欠B logging寄与=-93%。これは実装局所の方向確認であり、wave正式効果ではない。
- **wave即時固定窓**: #1と補欠Aはp50/totalとも減少。#2/#5/#0'/補欠Bは件数変動またはp50/total不一致、#3/#4は観測上悪化。対照群も大幅変動し、正式確定可能lane=0/8。
- **正式効果**: §1計測憲法どおり「修正後1週間のledger累積課税の前週比」。2026-08-04時点では未成熟ゆえ未確定。

## §2.7 最終品質checkpoint記録(2026-08-05)

| 項目 | 実測結果 | 判定 |
|---|---|---|
| 固定HEAD | `5aad3a61ecdd826a10271e296b3c8ed14b3cbec7` | PASS |
| receipt | `/mnt/c/tools/multi-agent-shogun/.karo_worktrees/round8-shard-4/logs/test_receipts/run_tests_20260805T060402_523518.json` | PASS |
| 対象ファイル | 214/214 (selected/discovered/executed) | PASS |
| テスト数 | declared/observed = 3,122/3,122 | PASS |
| FAIL / SKIP | 0 / 0 | PASS |
| 終了・範囲 | `rc=0`, `complete=1`, `full_scope=true` | PASS |

**CLOSE境界**: 第八弾の実装・品質checkpointは上記receiptにより完了。正式な速度効果値は品質判定と混同せず、修正後一週間の `logs/defense_overhead.jsonl` 累積課税の前週比で確定する。

## §2.6.1 テスト修正・高速化の知見(今回の実証)

1. **FAIL単位で分割する**: shardの失敗を一括修正せず、失敗したテストファイルごとに独立タスク化する。今回のheavy admission・three-layer preflight・commit wrapperを別担当へ分け、原因の混線と手戻りを防いだ。
2. **テストを弱めず、根因を実装側で直す**: 判定条件・fail-closed境界・検証対象は維持する。heavy admissionはロック/待機境界、preflightは三層検証の前提、wrapperは継承ロックの解放を根因として修正した。
3. **focused結果を先に二値確認する**: 各修正は対象ファイルだけを再実行し、PASS件数・FAIL件数・SKIP件数を即時計測する。実績はheavy **86/86 PASS**、preflight **52/52 PASS**、wrapper **28/28 PASS**、いずれもSKIP 0。
4. **固定HEADへ統合してから全量確認する**: focused PASSを採用条件とし、同一固定HEADへ統合後に全量を一度だけ実走する。最終receiptは214/214ファイル、3,122/3,122 PASS、FAIL 0、SKIP 0、`rc=0`、`complete=1`、`full_scope=true`となった。
5. **高速化は実行機構で行う**: テスト対象・品質境界を削らず、並列shard、専用fixture、ロック競合解消、不要な再走回避で時間を短縮する。今回の全量検証は品質を維持したまま、失敗shardだけを再実行する契約に適合した。
6. **完了条件を出力でなくreceiptに固定する**: 「修正した」「テストした」では完了にせず、宣言数=観測数、重複0、欠損0、FAIL 0、SKIP 0、HEAD一致、`complete/full_scope`成立を必須条件にする。

- origin: `[[shard4失敗テスト]] -> [[FAIL単位分割修正]] -> [[focused二値検証]] -> [[固定HEAD全量receipt]] -> [[第八弾品質CLOSE]]`

## §2.6 checkpoint契約(殿裁定2026-08-05 — 全弾共通)

full/wave checkpointの全量テストを1名へ一括配備しない。以下の契約に従う。

**Step 0 — test衛生・高速化を先に行う**: 固定HEAD化とshard実走の前に、当該waveで新規/変更した実装用testを `作成→PASS→同一task内で削除` し、永続testは全件に具体的不変量の `test_necessity` があることをN/Nで確認する。重複・陳腐・一時fixture残存を0件化し、残るcontract testは検出力を削らずrunner/fixture/共有資源を高速化してからmanifestを生成する。現進行中の第八弾で取得済みの同一HEAD PASS receiptは無効化せず再利用し、以後のfailed/missing再実走から適用する。

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
| 第八弾の起動 | 殿発案2026-08-04 02:44。**実施完了(v1.6品質checkpoint CLOSE)** |
| 序列snapshot | **確定済み**(§0=2026-08-04 09:07将軍再実測v1.1。既存ledger 112,089行・fixed-window。02:47実測比+1,978行で序列不変=構造確認済み) |
| 弾数・標的固定 | **5+補欠2で固定・実施完了** |
| three_layer_health 3弾の直列 | **共有writer原則で実施完了** |
| 高速化と防御力の境界 | **確定**: 検証力不変・fail-closed維持・チェック間引き禁止(LS099/殿裁定07-21『削るな速くしろ』) |
| 起票解禁 | **1道具1CMDで順次実施完了**。正式効果のみ修正後一週間ledger前週比待ち |

## §4 5W1H

- **WHY**: three_layer_health系だけで週約88.6時間の計算課税(全エージェントの全promptに乗る)。ホットスクリプトの遅さはスループットと自動成長の回転数への直接税。『問題は速度が遅いこと。品質を保ったまま超速化せよ』(殿再訂正2026-07-21 13:56)
- **WHAT**: 恒常課税TOP(三層記憶health refresh 3 check)+高頻度層の是正。検証力不変で実行時間のみ削る
- **WHEN**: 設計書裁可後、1道具1CMDで順次。効果確定=修正後1週間ledger前週比
- **WHERE**: `scripts/`配下のthree_layer_health系・git pre-commit hook・gate_gunshi_report_precheck。台帳=`logs/defense_overhead.jsonl`(164,978行)
- **WHO**: 子区分計測=忍者(read-only冗長2名可)、是正実装=忍者(単独所有)、検分=家老+軍師、裁可=殿
- **HOW**: 恒常課税=子区分計測→最大寄与是正(cache SSOT化・差分検証・hash短絡)、外れ値=発火条件→条件ベース是正。敵対fixtureで「壊れた三層状態を検出できる」ことを是正ごとに確認

## §5 因果リンク

- → [[hot-script高速化設計書]] 第一〜七弾。様式・計測憲法・完了条件の型元
- → [[殿裁定_削るな速くしろ_20260721]] 品質を保ったまま超速化=本弾の憲法(knowledge:569abc55)
- → [[cmd_4111_related_lessons_snapshot]] 721MB DB全量→cache SSOT化 -98.5%の前例(弾#1の手筋候補の型元)
- → [[殿裁定_厳密さは最終チェックのみ_20260714]] 途中try最大化・報告整形は最終集約
- → [[three-layer-penetrate]] 三層記憶の検証力契約(弾#1-#3が守る底線)
- origin: `[[殿発案_第八弾_20260804]] -> [[three_layer_health週88時間課税の一次実測]] -> [[恒常課税TOP是正v1.0]]`
