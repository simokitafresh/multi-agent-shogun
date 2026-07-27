# ホットスクリプト集中高速化 — AsIs/ToBe 5W1H設計書 v1.0 (2026-07-27)【⚠家老レビューBLOCK 6点受領(blt_195501) — §0序列は計測境界混在(begin/end混在・実行本体込み・親子二重計上・lock保持と待ちの混同)のため暫定。cmd_4181偵察の純オーバーヘッド再集計でv2へ置換する】

作成: 将軍 | 殿裁定(2026-07-27 19:44「個別スクリプト覚醒高速化がベスト」/ 19:46「ボトルネック要因となりやすいスクリプトをリストアップして集中的に高速化する方針。設計書を作ってくれ」)
方針: **構造(型)は変えない。ハード/OS移設はしない(殿裁定でext4移設・Mac・NPU/GPUは総コストで見送り)。遅いスクリプト=バグとして個別に覚醒高速化する。** 品質2原則(正本突合+境界fixture)を維持=「削るな速くしろ」の継続。

---

## §0 結論 — 標的リスト(実測総コスト順)

**選定基準 = 平均時間×発火回数の総消費(直近3日、logs/defense_overhead.jsonl全38,204行から機械集計)。** 平均が小さくても回数が多ければ標的、平均が巨大でも回数が少なければ後位。

### Tier A: 台帳実測の上位(3日間総消費順)

| # | source:check | 平均 | 回数/3日 | 総消費/3日 | 実体スクリプト |
|---|---|---:|---:|---:|---|
| A1 | three_layer_health:refresh_window | **33.9s** | 1,541 | **14.5時間** | scripts/gates/gate_three_layer_health.sh + cache refresh系 |
| A2 | git_pre_commit:affected_tests | **87.9s** | 316 | 7.7時間 | scripts/git-pre-commit.sh のaffected test選択 |
| A3 | heavy_job_admission:execution | 81.9s | 183 | 4.2時間 | scripts/lib/heavy_job_admission系(+queue_wait 62.4s×53) |
| A4 | three_layer_health:refresh_verify+refresh_copy | 各10.5s | 各≈1,070 | 計6.3時間 | 同A1(cache verify/copy段) |
| A5 | deploy_task:deploy_total | 8.3s | 1,110 | 2.6時間 | scripts/deploy_task.sh(1周目-47%済の残余) |
| A6 | gate_gunshi_report_precheck:full_precheck | 5.2s | 1,390 | 2.0時間 | scripts/gates/gate_gunshi_report_precheck.sh(cmd_4177でengine一元化済み。効果はこの台帳で追う) |
| A7 | gate_report_format:singleflight_hold | 1.0s | 3,206 | 0.9時間 | 待ち時間(lock設計)。回数最多 |
| A8 | cmd_save:checks_main ほかcmd_save系 | 2.2s+ | 650+ | 0.7時間+ | scripts/cmd_save.sh(q11_semantic 3.2s×147, three_layer_ruling 2.1s×187含む) |

### Tier B: 台帳外だが本日実測で重い(復帰税・起動税)

| # | 対象 | 実測 | 根拠 |
|---|---|---|---|
| B1 | **家老deepdive追体験(復帰税)** | 本日8回計約68分。1-2分→16-19分へ約10倍悪化(14:04以降) | logs/deepdive_replay/karo.jsonl受領証218件の将軍集計。**悪化原因未特定=最優先偵察** |
| B2 | gate_karo_startup.sh | 起動毎(compaction毎=約1時間毎に発生) | 家老compaction頻度と掛け算で効く |
| B3 | gate_shogun_startup.sh | 16.4s/回(本日TIMING_COVERAGE実測16,103ms、TOP=洗脳連鎖2x2 3.7s+enforcement分布2.9s) | 本日gate出力のTIMING行 |
| B4 | ninja_scope_commit.sh | 13.3s/回(本日PRECOMMIT_RECEIPT: git_commit 5.8s+scope_sync 2.8s+post_check 2.1s) | commit毎に全員が払う |
| B5 | inbox_write.sh | pre/post capture+検証で体感数秒×高頻度 | 全通信に乗る(未計測=計測から) |

### 除外(標的にしない)
- run_tests系の実行時間そのもの(選択実行化cmd_4164系で対処済みの別レーン)
- DM-Signal側(fullrecalculate)=別設計書(v2.0)の管轄

---

## §1 As-Is の共通疑い(真因パターン)

過去の高速化実績(deploy -89%/self_sync -83%/admission -99.3%/related_lessons -98.5%)で繰り返し出た真因は次の4型。新標的もまずこの4型を疑う:
1. **全量再parse/全量snapshot**(例: related_lessons 721MB DB全量→cache SSOT化で-98.5%)
2. **affected=0でも全処理**(例: admission即return化で-99.3%)
3. **プロセス多段起動**(bash→python3多重spawn。DrvFs statと掛け算で悪化)
4. **lock/singleflightの持ち過ぎ**(A7の3,206回×1sはほぼ待ち)

B1(復帰税悪化)は別型の可能性: Phase数増(18→36-38)+pane貼付+モデル/effort変化の複合。**憶測禁止=一次特定から**。

---

## §2 To-Be — 進め方(レーン方式)

1. **1標的=1弾(1道具1CMD)**。各弾のACは「同一条件before/after実測の数値差分」+「品質2原則(挙動不変の正本突合+境界fixture)」を固定
2. **順序**: B1偵察(悪化原因特定)を先頭に、以後はTier A総消費順(A1→A2→A3…)。A6は既存cmd_4177効果の台帳確認のみ
3. **計測はすべて既存台帳** `logs/defense_overhead.jsonl` に載せる(新台帳禁止=車輪の再発明防止)。B群で未計測のもの(B1/B2/B5)は「計測行の追加」を弾の第一ACにする
4. **判定式**: 改善効果=Δ平均×回数(総消費の削減量)で報告。平均だけの改善報告は不可
5. **凍結解除条件**: 本設計書の家老忖度なしレビュー完了後、殿の起票裁可をもって弾を順次起票

### 規模感(達成目安・決め打ちしない)
- Tier A上位3つ(A1+A2+A3)だけで3日26.4時間=**1日あたり約8.8時間の機械時間**を消費中。過去実績並みの-80〜90%が届けば1日7時間超の回収。忍者の待ち時間短縮=スループット直結

---

## §3 未解決事項
1. B1悪化の真因(最優先偵察)
2. A1 three_layer refresh_windowの33.9s×1,541回の発火主体(どのhook/agentが呼ぶか)の分布
3. A3 heavy_job_admissionのexecution 81.9sは「実行本体」を含むか「admission純オーバーヘッド」かの切り分け(台帳の計測境界確認)
4. B5 inbox_writeの実測(計測行が未整備)

## §4 5W1H
- **WHY**: 機械時間1日約9時間の浪費が全ロールの待ちと復帰税を生み、自動成長速度(正しい試行回数×一発PASS率×知見還流率)を律速する
- **WHAT**: 実測総消費順の標的リストを1標的1弾で覚醒高速化し、台帳の総消費削減で証明する
- **WHEN**: 設計書レビュー→殿裁可→順次起票。B1偵察が先頭
- **WHERE**: §0のTier A/Bスクリプト群。台帳=defense_overhead.jsonl
- **WHO**: 偵察・実装=忍者(並列可、1標的1名)、検分=家老+軍師、裁可=殿
- **HOW**: 4型仮説→cProfile/計測行→真因→最小差分実装→before/after総消費差分→還流

## §5 因果リンク
- → [[deploy control-plane速度改善]] 1周目実績と手法(cache SSOT/即return)の型元
- → [[defense_overhead.jsonl]] 唯一の計測台帳(新設禁止)
- → [[gunshi_auto_clear_recovery_design_20260727]] B1復帰税と同日に是正した運用封鎖の姉妹設計書
- origin: `[[殿裁定_個別スクリプト覚醒高速化_20260727]] -> [[台帳実測_総消費順リストアップ]] -> [[1標的1弾の集中高速化レーン]]`

**MEM引用**:
- [MEM: memory_db ts=2026-07-21 "deploy総67.3→35.8秒(-47%)…既存telemetry logs/defense_overhead.jsonl source:deploy_task check_id:deploy_total が記録(新ledger作るな)"] 台帳と手法の型元
- [MEM: semantic concept=defense_hierarchy 「速度が遅いスクリプトや仕組みはバグだ」「正しい試行回数×一発PASS率×知見還流率」]
