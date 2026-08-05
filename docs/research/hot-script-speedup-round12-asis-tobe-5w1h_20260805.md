<!-- gist-master: c325edf9169d327b290a38cdf9e0352c hot-script-speedup-round12-asis-tobe-5w1h_20260805.md -->
# ホットスクリプト集中高速化 第十二弾 — 二段計測16-25位層(cmd_save子区分+配送検証+dashboard+precheck内訳) — AsIs/ToBe 5W1H設計書 v1.3

> v1.3(2026-08-05 20:44 家老差戻し修正): 進捗台帳を1集約行→全10行展開。identifier完全一致+owner path列追加。見出し+残存修正

> v1.2(2026-08-05 20:38 殿指示scope純化): 第10弾v1.7準拠で提案弾台帳に高速化許可owner pathを一次コード突合で確定。列挙外pathの変更を禁止

> v1.1(2026-08-05 02:40 殿裁定): §2.6 checkpoint契約を追加(全弾共通)

> 初版起草(2026-08-05 00:00。殿指示23:59『第十二弾も作成してくれ16位〜25位だ』)

> シリーズ: ホットスクリプト集中高速化。第一弾〜第七弾=✅CLOSED / **第八弾**=wave最終checkpoint進行中 / **第九弾**=レーン配備中 / **第十弾**=TOP7再攻撃(裁可待ち) / **第十一弾**=8-15位(裁可待ち) / **第十二弾=本書**

## §-1 スコープと境界(数と原理を先に固定)

- **標的=直近24時間の累積課税16-25位**(第十弾TOP7・第十一弾8-15位を除いた次層10標的)
- **二段計測(殿設計2026-08-04 23:34 — 第十弾から恒久導入)**:
  - **Tier 1 劣化検知**: 修正後1週間のledger累積課税を前週比で総括
  - **Tier 2 ボトルネック特定**: 直近24時間の絶対値で累積課税を序列化
- **前弾との境界**: 多くが上位弾標的の子区分(cmd_save子区分→第九弾#4/第十一弾#4系、precheck子区分→第十一弾#1系、inbox子区分→第十一弾#2系)。上位弾の是正が子区分の累積を変えるため、上位弾完了後にTier 2で残課税を再確認してから着手する
- **writer構造**: 1スクリプト(の1ホットパス)=1弾=1レーン。共有層に触れる弾は独立writerかつ先行→固定HEAD再計測→直列依存。並列変更禁止
- **品質2原則堅持**: 正本突合判定+境界fixture両方を維持。防御の検証力は1点も削らない(殿裁定2026-07-21『削るな、速くしろ』が憲法)
- **スコープ外**: gate/hookの削除・条件緩和(LS099)/テスト実行時間(第七弾)/DM-Signal側Python/第十弾・第十一弾標的
- **方式=レーン方式**(殿裁可→将軍下知blt→家老レーン配備→gate_metricsへlane名CLEAR刻印→最終checkpoint品質2原則検分)
- **lane最小AC/wave checkpointの二層契約**(殿恒久裁定2026-08-04 19:26)

## §0 序列SSOT(2026-08-04 23:59 将軍一次実測 — 直近24時間)

**取得方法**: `logs/defense_overhead.jsonl`から直近24時間を抽出し、source:check_id別にwall_msの累積・中央値・max・p95・呼出数を算出(Python statistics.median+sorted percentile)。1件=jsonl 1行=1計測イベント。第十弾(1-7位)・第十一弾(8-15位)は除外。**累積時間はagent-hours(全CLI合算)**=9並列CLIの全呼出しの合計であり壁時計の24h/日を超えうる。

### 累積課税序列(直近24時間・Tier 2)

| 順 | source:check_id | 累積 | n | median | p95 | max | 型 | 上位弾との関係 |
|---|---|---|---|---|---|---|---|---|
| - | 1-15位は第十弾・第十一弾の領域 | — | — | — | — | — | — | — |
| 16 | `cmd_save:three_layer_memory_ruling_overhead` | **2,401s(≈0.7h)** | 758 | 0.00s | 16.0s | 62.0s | 外れ値 | 第九弾#4(cmd_save)子区分 |
| 17 | `inbox_write:inbox_write_delivery_verify` | **2,364s(≈0.7h)** | 6,932 | 0.00s | 3.8s | 23.7s | 外れ値 | 第十一弾#2(inbox_write)子区分 |
| 18 | `report_field_set:commit_hash` | **2,081s(≈0.6h)** | 6,259 | 0.27s | 0.8s | 3.1s | 砂粒 | 新規 |
| 19 | `dashboard_update:dashboard_update_total` | **2,024s(≈0.6h)** | 63 | 10.30s | 96.1s | 230.7s | 恒常 | 新規 |
| 20 | `git_pre_commit:self_sync` | **1,989s(≈0.6h)** | 1,773 | 0.07s | 5.9s | 36.6s | 外れ値 | 第十弾#4(affected_tests)同族 |
| 21 | `gate_gunshi_report_precheck:full_precheck_memory_search` | **1,775s(≈0.5h)** | 1,029 | 0.42s | 1.3s | 937.0s | 外れ値 | 第十一弾#1(precheck)子区分 |
| 22 | `gate_gunshi_report_precheck:full_precheck_batch_git` | **1,720s(≈0.5h)** | 1,087 | 0.79s | 6.3s | 18.5s | 砂粒 | 第十一弾#1(precheck)子区分 |
| 23 | `report_publish:inbox_write` | **1,508s(≈0.4h)** | 2,661 | 0.01s | 0.1s | 56.1s | 外れ値 | 第十一弾#6(publish)子区分 |
| 24 | `git_pre_commit:yaml_ast` | **1,470s(≈0.4h)** | 1,602 | 0.00s | 3.6s | 14.9s | 外れ値 | 第十弾#4(affected_tests)同族 |
| 25 | `gate_gunshi_report_precheck:full_precheck_sg_pre21` | **1,464s(≈0.4h)** | 1,067 | 0.98s | 3.2s | 5.7s | 砂粒 | 第十一弾#1(precheck)子区分 |

**読み**: (a)個別累積は0.4-0.7h/日と上位弾に比べ小さいが、10標的合計で**18,796s(≈5.2h/日)**。(b)10標的中7標的が上位弾標的の子区分——上位弾の是正が子区分を自動的に改善する可能性が高い。**上位弾wave checkpoint後にTier 2で再計測し、依然残存する標的のみ是正する**のが効率的。(c)新規標的はcommit_hash(18位)とdashboard_update(19位)の2本。dashboard_updateはmed 10.3s×63回で回数は少ないが1回が重い恒常型。(d)full_precheck_memory_searchはmax 937sの極端な外れ値を持つ——第十一弾#1の偵察で真因が判明する可能性が高い。

## §1 計測境界(憲法・第五〜十一弾継承+Tier 2)

- 計測=既存台帳のみ(`logs/defense_overhead.jsonl`)。**新台帳禁止**(knowledge:fbb5716c)
- before/afterは**同一スクリプト・同一check_id・同一環境**のfixed-window比較
- run間ノイズ: p25/p75でΔ有意判定
- **Tier 1**: 修正後1週間の累積課税前週比 / **Tier 2**: 直近24h絶対値で序列化
- 外れ値型=p95/p99+裾総量で判定 / 恒常型=中央値×呼出数 / 砂粒型=呼出回数削減 or 定数項削減

## §2 To-Be — 進め方(型を継承)+品質底線

1. **1標的=1弾・複合弾禁止**
2. **品質底線**: 検証力不変・PASS/FAIL挙動不変・敵対fixture
3. 仮説在庫: 上位弾子区分7本は上位弾是正で自動改善の可能性大→Tier 2再計測後に判断/commit_hash=git rev-parse呼出し頻度の最適化/dashboard_update=dashboard_auto_section.shの子区分計測→最大寄与是正
4. **反復サイクル型**: 極限化→計測→検証→再極限化。停止=Δがノイズ帯以内
5. **read-only冗長並列**: 子区分計測は2名可。是正は単独所有
6. 選択実行FAIL0・SKIP0のみ。途中try最大化
7. 完了宣言=Tier 1+Tier 2→CLOSE刻印
8. **レーン方式** / 9. **lane最小AC/wave checkpoint二層契約**

### 提案弾台帳(殿裁可で固定 — v1.2 owner path確定)

| # | 標的identifier | 高速化許可owner path | 型 | 現状(直近24h) | 手筋候補 | 上位弾依存 |
|---|---|---|---|---|---|---|
| 1 | `cmd_save:three_layer_memory_ruling_overhead` | `scripts/cmd_save.sh` | 外れ値 | med 0.00s×758・total 2,401s・max 62s | ruling cache hit率計測→miss時の裾削減 | 第十一弾#4後 |
| 2 | `inbox_write:inbox_write_delivery_verify` | `scripts/inbox_write.sh` | 外れ値 | med 0.00s×6,932・total 2,364s・max 24s | 配送検証の裾条件特定→条件是正 | 第十一弾#2後 |
| 3 | `report_field_set:commit_hash` | `scripts/report_field_set.sh` | 砂粒 | med 0.27s×6,259・total 2,081s・max 3.1s | git rev-parse呼出し回数削減 or cache化 | 独立writer |
| 4 | `dashboard_update:dashboard_update_total` | `scripts/dashboard_update.sh` | 恒常 | med 10.30s×63・total 2,024s・max 231s | dashboard_auto_section子区分→最大寄与是正 | 独立writer |
| 5 | `git_pre_commit:self_sync` | `scripts/hooks/git-pre-commit.sh` | 外れ値 | med 0.07s×1,773・total 1,989s・max 37s | 裾の発火条件特定 | 第十弾#4後 |
| 6 | `gate_gunshi_report_precheck:full_precheck_memory_search` | `scripts/gates/gate_gunshi_report_precheck.sh` | 外れ値 | med 0.42s×1,029・total 1,775s・max 937s | max 937s外れ値の真因特定 | 第十一弾#1後 |
| 7 | `gate_gunshi_report_precheck:full_precheck_batch_git` | `scripts/gates/gate_gunshi_report_precheck.sh` | 砂粒 | med 0.79s×1,087・total 1,720s・max 19s | git呼出し回数削減 or batch化 | 第十一弾#1後 |
| 8 | `report_publish:inbox_write` | `scripts/report_field_set.sh` | 外れ値 | med 0.01s×2,661・total 1,508s・max 56s | 裾条件特定 | 第十一弾#6後 |
| 9 | `git_pre_commit:yaml_ast` | `scripts/hooks/git-pre-commit.sh` | 外れ値 | med 0.00s×1,602・total 1,470s・max 15s | YAML解析の裾条件特定 | 第十弾#4後 |
| 10 | `gate_gunshi_report_precheck:full_precheck_sg_pre21` | `scripts/gates/gate_gunshi_report_precheck.sh` | 砂粒 | med 0.98s×1,067・total 1,464s・max 5.7s | SG-PRE21チェックの定数項削減 | 第十一弾#1後 |

**owner path制約**: 上記owner pathのみ高速化・変更可。test/log/call-path依存はread-onlyかつ進捗計上禁止。

- 独立writerの#3・#4は先行着手可。残り8標的は上位弾完了後にTier 2で再計測してから着手判断
- 上位弾の是正で自動改善された標的はno-changeクローズ

## §2.5 進捗台帳(2026-08-05 20:44 v1.3 全10行展開+identifier完全一致)

| # | 標的identifier | 高速化許可owner path | 状態 | 帰結(実測生値) |
|---|---|---|---|---|
| 1 | `cmd_save:three_layer_memory_ruling_overhead` | `scripts/cmd_save.sh` | ⏳第十一弾#4完了後 | — |
| 2 | `inbox_write:inbox_write_delivery_verify` | `scripts/inbox_write.sh` | ⏳第十一弾#2完了後 | — |
| 3 | `report_field_set:commit_hash` | `scripts/report_field_set.sh` | ⏳着手可(独立writer) | — |
| 4 | `dashboard_update:dashboard_update_total` | `scripts/dashboard_update.sh` | ⏳着手可(独立writer) | — |
| 5 | `git_pre_commit:self_sync` | `scripts/hooks/git-pre-commit.sh` | ⏳第十弾#4完了後 | — |
| 6 | `gate_gunshi_report_precheck:full_precheck_memory_search` | `scripts/gates/gate_gunshi_report_precheck.sh` | ⏳第十一弾#1完了後 | — |
| 7 | `gate_gunshi_report_precheck:full_precheck_batch_git` | `scripts/gates/gate_gunshi_report_precheck.sh` | ⏳第十一弾#1完了後 | — |
| 8 | `report_publish:inbox_write` | `scripts/report_field_set.sh` | ⏳第十一弾#6完了後 | — |
| 9 | `git_pre_commit:yaml_ast` | `scripts/hooks/git-pre-commit.sh` | ⏳第十弾#4完了後 | — |
| 10 | `gate_gunshi_report_precheck:full_precheck_sg_pre21` | `scripts/gates/gate_gunshi_report_precheck.sh` | ⏳第十一弾#1完了後 | — |

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
| 第十二弾の起動 | 殿指示2026-08-04 23:59。裁可待ち |
| 序列snapshot | 起草時実測済み(§0=2026-08-04 23:59・直近24時間) |
| 弾数・標的固定 | 16-25位の10標的。殿裁可で固定 |
| 上位弾依存 | 10標的中8標的が上位弾子区分。上位弾完了後にTier 2再計測で残課税を確認 |
| 高速化と防御力の境界 | **確定**: 検証力不変(LS099/殿裁定07-21) |

## §4 5W1H

- **WHY**: 16-25位層は個別小さいが合計5.2h/日。上位弾の子区分が多く、上位弾是正後の残課税攻撃で効率的に削減できる
- **WHAT**: 10標的。外れ値型5弾(裾条件特定)+砂粒型3弾(頻度削減)+恒常型1弾(子区分→最大寄与)+新規1弾(commit_hash)。検証力不変
- **WHEN**: 上位弾(第十弾・第十一弾)wave checkpoint後にTier 2再計測→残存標的を着手。独立writerの#3/#4は先行可
- **WHERE**: `scripts/`配下のcmd_save.sh・inbox_write.sh・report_field_set.sh・dashboard_update関連・git_pre_commit関連・gate_gunshi_report_precheck.sh。台帳=`logs/defense_overhead.jsonl`
- **WHO**: 偵察・是正=忍者、検分=家老+軍師、裁可=殿
- **HOW**: レーン方式+Tier 1/2二段計測

## §5 因果リンク

- → [[hot-script-speedup-round10-asis-tobe-5w1h_20260804]] TOP7再攻撃(姉妹弾)
- → [[hot-script-speedup-round11-asis-tobe-5w1h_20260804]] 8-15位(姉妹弾。子区分の上位弾)
- → [[殿裁定_削るな速くしろ_20260721]] 憲法(knowledge:569abc55)
- → [[ledger-driven-campaign-lane-pattern_20260714]] レーン方式の型元
- origin: `[[殿指示_第十二弾_16_25位_20260804]] -> [[上位弾子区分7本+新規3本]] -> [[上位弾完了後のTier2残課税攻撃]]`
