<!-- gist-master: fc4b27c4031149d7d6b45fde49028942 hot-script-speedup-round8-asis-tobe-5w1h_20260804.md -->
# ホットスクリプト集中高速化 第八弾 — 三層記憶health+常時課税層 — AsIs/ToBe 5W1H設計書 v1.1 【📋設計済・裁可待ち】

> 状態: v1.1覚醒更新(2026-08-04 09:07 殿指示『設計書は覚醒してアップデートせよ』— §0を最新ledger 166,956行で再実測。**序列不変**を確認、弾台帳・境界に変更なし) / 初版起草(2026-08-04 02:50。殿発案02:44『第八弾をやろう。まずは同じ形式で設計書を』)

> シリーズ: ホットスクリプト集中高速化。第一弾=`hot-script-speedup-asis-tobe-5w1h_20260727.md`✅ / 第二弾=`hot-script-speedup-round2-asis-tobe-5w1h_20260728.md`✅ / 第三弾=`hot-script-speedup-round3-asis-tobe-5w1h_20260728.md`✅ / 第四弾=`hot-script-speedup-round4-asis-tobe-5w1h_20260728.md` / 第五弾=`hot-script-speedup-round5-asis-tobe-5w1h_20260729.md`✅ / 第六弾=`throughput-bottleneck-part2-asis-tobe-5w1h_20260728.md`(identity基盤完成・P1b蓄積待ち) / 第七弾=`hot-script-speedup-round7-test-speed-asis-tobe-5w1h_20260729.md`✅(全量wall -3.35%確定) / **第八弾=本書**

## §-1 スコープと境界(数と原理を先に固定)

- **標的=エージェント実働時に毎回課税されるホットスクリプトの実行時間のみ。防御の検証力は1点も削らない**(品質2原則=正本突合判定+境界fixture両方を維持。殿裁定2026-07-21『削るな、速くしろ』が本弾の憲法)
- **弾数=序列確定済みゆえ本書で決め打ち提案**(§0の一次実測に基づくTOP5+補欠2。殿裁可で固定し途中追加しない)
- **writer構造(第五・七弾の写像)**: 1スクリプト(の1ホットパス)=1弾=1レーン。共有層(`scripts/lib/`・三層記憶の共通読み書き)に触れる弾は独立writerかつ先行→固定HEADで再計測→個別弾の直列依存。並列変更禁止
- **スコープ外**: gate/hookの削除・条件緩和(必須ハーネス保持=LS099)/テスト実行時間(第七弾の領分・CLOSED)/DM-Signal側Python(別repo)/deploy_task残候補③report_publication・④ninja_scope_commit(第六弾系譜の残在庫として別管理)

## §0 序列SSOT(2026-08-04 02:47 将軍一次実測 — 既存台帳のみ・新台帳なし)

**取得方法**: `logs/defense_overhead.jsonl`(166,956行 — v1.1覚醒再実測2026-08-04 09:07)から2026-07-28以降の112,089行を抽出し、source:check_id別にwall_msの中央値と累積(=課税総量)を算出。集計コマンドと生出力は本節の値がそのまま転記(1件=jsonl 1行=1計測イベント)。**v1.0(02:47実測・110,111行)→v1.1で+1,978行増えても序列は完全不変**。

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

- 弾#1-#3は同一スクリプト(three_layer_health)の別checkだが、writer共有ゆえ**#1→#2→#3の直列**(共有層先行の原則)。#4以降は独立並列可

## §3 decision ledger

| 項 | 状態 |
|---|---|
| 第八弾の起動 | 殿発案2026-08-04 02:44。**設計書の裁可待ち(本書v1.0)** |
| 序列snapshot | **確定済み**(§0=2026-08-04 09:07将軍再実測v1.1。既存ledger 112,089行・fixed-window。02:47実測比+1,978行で序列不変=構造確認済み) |
| 弾数・標的固定 | **本書で5+補欠2を提案**。殿裁可で固定 |
| three_layer_health 3弾の直列 | 提案(共有writer原則)。裁可対象 |
| 高速化と防御力の境界 | **確定**: 検証力不変・fail-closed維持・チェック間引き禁止(LS099/殿裁定07-21『削るな速くしろ』) |
| 起票解禁 | 設計書裁可→(必要なら家老・軍師レビュー)→1道具1CMDで順次起票。DM-signal月次E2検証・rebalancer cmd_4225/4226レーンを妨げない範囲で配備 |

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
