# 【📐設計のみ — v4.0 snapshot序列準拠・実装凍結・家老レビュー待ち】ホットスクリプト集中高速化 第五弾 — AsIs/ToBe 5W1H設計書 v1.1 (2026-07-29 03:40 家老snapshot草案へ統一。版履歴は§-3)

> 第一弾=`hot-script-speedup-asis-tobe-5w1h_20260727.md`(✅CLOSED 12/12)、第二弾=`hot-script-speedup-round2-asis-tobe-5w1h_20260728.md`(✅CLOSED 9/9)、第三弾=`hot-script-speedup-round3-asis-tobe-5w1h_20260728.md`(✅CLOSED 2/2)、第四弾=`hot-script-speedup-round4-asis-tobe-5w1h_20260728.md`(✅CLOSED 5/5・checkpoint 3巡目CLEAR 2,745/2,745・CI run 30385588247 success)。本書は殿下知(2026-07-29 03:30)「第五弾の設計書を作成せよ。第一弾〜と同じスタイルで。**10レーン分**組み込もう」に基づき、序列SSOT=**v4.0 fixed-window snapshot**(`hot-script-speedup-round5-v4-snapshot-20260729.md`、家老作成・固定窓2026-07-28T11:25:10Z..18:24:39.872864Z inclusive・8,237行・raw SHA-256=db3fed9cc…)から10標的を引く。殿方針(10:49)「前弾でやったものも依然ボトルネックなら再度トライする」を継承。様式・計測の憲法・完了条件の型は第一弾を踏襲する。

## §-2 第五弾 弾台帳(2026-07-29 03:40時点 — 起票前。全弾❄設計のみ)

| # | 標的 | writer(所有script) | 状態 | 予定内容 | v4.0固定窓実測 |
|---|---|---|---|---|---|
| 1 | inbox_write_total(再) | `scripts/inbox_write.sh` | ❄ | 第四弾#2是正(delivery verify非同期化)後も累積1位。**AC1=現行枝cohortを識別子/時刻で分離**(窓内はbefore/after混在)→残存最大子区分の是正。改善余地なしなら正直no-change CLOSE。送達保証・自動既読type群は不変条件 | 累積967.8s/n=560/p50 298ms/p95 6,264ms/max 12,357ms |
| 2 | full_precheck(再々々) | `scripts/gates/gate_gunshi_report_precheck.sh` | ❄ | 第四弾#1是正(重複tree走査除去)後も累積2位。AC1=現行枝cohort分離→body_rest系残存の最大寄与是正(stdout完全一致) | 累積507.2s/n=131/p50 1,077ms/p95 13,402ms/max 21,531ms |
| 3 | publish_total(再々) | `scripts/report_field_set.sh` | ❄ | 第四弾#3是正(lock FD分離)後の残存。恒常部p50 320msと外れ値尾max 12.5sを分離し、現行枝で改善余地判定 | 累積110.2s/n=261/p50 320ms/p95 600ms/max 12,520ms |
| 4 | yaml_ast | `scripts/hooks/git-pre-commit.sh` | ❄ | p50=1msに対しp95 6.5s/max 13.9s=典型的外れ値型。発火条件(大型YAML・対象数)の同event記録→3点表→条件ベース是正 | 累積98.8s/n=66/p50 1ms/p95 6,460ms/max 13,907ms |
| 5 | commit_hash(再) | `scripts/report_field_set.sh`(#3後に直列) | ❄ | 第四弾#5で識別子計装済み・実flow重複0。AC1=計装後cohortの全数で重複再判定→重複なし継続ならno-change CLOSE、恒常部245ms×n324の内訳是正余地のみ確認 | 累積84.3s/n=324/p50 245ms/p95 490ms/max 1,110ms |
| 6 | files_modified | `scripts/report_field_set.sh`(#5後に直列) | ❄ | p50 520ms×全報告。子区分計測→最大寄与是正 | 累積29.2s/n=54/p50 520ms/p95 1,040ms/max 1,560ms |
| 7 | sourced_dep | `scripts/hooks/git-pre-commit.sh`(#4後に直列) | ❄ | p50=2msに対しp95 2.0s=外れ値型。依存走査の発火条件特定→条件ベース是正 | 累積20.9s/n=66/p50 2ms/p95 1,973ms/max 4,161ms |
| 8 | task.commit_contract | `scripts/report_field_set.sh`(#6後に直列) | ❄ | 第二弾#7でno-gain revert済みの標的。AC1=現行枝再計測→改善余地なしなら正直no-change(前例=第二弾の型) | 累積17.9s/n=59/p50 250ms/p95 650ms/max 1,050ms |
| 9 | checks_main(再々々) | `scripts/cmd_save.sh` | ❄ | 第四弾#4 no-change後の継続。子quality_gateが最大(5.3s/15.9s)。v4.0でも序列内に残存ゆえ最小是正を試行、無理なら正直no-change | 累積15.9s/n=14/p50 1,095ms/p95 2,233ms/max 2,233ms |
| 10 | shell_syntax | `scripts/hooks/git-pre-commit.sh`(#7後に直列) | ❄ | p50=2msに対しp95 859ms=外れ値型。構文検査対象の条件特定→条件ベース是正(検査は削らない) | 累積11.5s/n=66/p50 2ms/p95 859ms/max 2,415ms |

## §-3 版履歴

- v1.1(03:40): **家老v4.0 snapshot草案(blt_033325)へ全面統一** — 将軍v1.0の誤り3点を是正: (一)窓上限を殿下知どおりcheckpoint receipt確定時刻18:24:39.872864Z inclusiveへ統一(8,237行/raw SHA db3fed9cc…、将軍暫定窓との37行差解消) (二)three_layer_health:refresh_windowは**begin=0/end=窓長の混在marker=集計禁止**、refresh_copy/verifyはbackground保守lane非加算 — v1.0のレーン1案(14,611s)は誤読ゆえ撤回 (三)affected_tests=テスト実行本体込み・queue_wait=別母集団・deploy_total=deployレーン帰属・singleflight_hold=保持時間、の非加算分類を採用。10標的=5 writer(inbox_write/gate_gunshi/report_field_set×4/git-pre-commit×3/cmd_save)構成へ再編
- v1.0(03:35): 初版起草(殿下知03:30=10レーン)。序列=将軍D0暫定窓 — v1.1で家老正本へ差替え

## §-1 第五弾スコープ決め打ち(第一弾§-1憲法の踏襲 — 数を先に固定)

**決め打ち: 10標的=10弾・5 writer**(§0表がSSOT。殿裁定03:30=10レーン固定・途中追加しない):

| 実体スクリプト(writer) | 担当標的 | 弾数 |
|---|---|---:|
| `scripts/inbox_write.sh` | inbox_write_total(再) | 1 |
| `scripts/gates/gate_gunshi_report_precheck.sh` | full_precheck(再々々) | 1 |
| `scripts/report_field_set.sh` | publish_total→commit_hash→files_modified→task.commit_contractの**直列4弾** | 4 |
| `scripts/hooks/git-pre-commit.sh` | yaml_ast→sourced_dep→shell_syntaxの**直列3弾** | 3 |
| `scripts/cmd_save.sh` | checks_main(再々々) | 1 |

- **完了条件(第一弾と同型)**: 恒常課税型=既存台帳`logs/defense_overhead.jsonl`同条件before/afterのΔ累積・Δmedian実測 / 外れ値尾=発生条件特定(3点表)→条件ベース是正 / いずれも品質2原則(挙動不変の正本突合+境界fixture)+選択テストFAIL0・SKIP0。**個別弾への全量unit要求は禁止、全量は10弾全クローズ後のfixed-SHA checkpointでwave共有一回**(殿裁定13:26)
- **再挑戦標的のAC1共通要件(v4.0 snapshot入力条項)**: 窓内はbefore/after混在ゆえ、**現行commitの枝別beforeを識別子/時刻で分離してから**是正判断する。改善余地なしなら正直no-change CLOSE(v4.0の混合窓を鵜呑みにしない)
- **第五弾完了宣言=10弾全クローズ→fixed-SHA全量unit共有1回→固定窓台帳再snapshot→次弾序列**(第四弾閉幕の型を踏襲)
- **スコープ外(途中追加は理由を問わず禁止)**: startup gate 3本(殿裁定12:43聖域)・three_layer_health系(background保守lane・mixed marker=集計禁止)・affected_tests(テスト実行本体込み)・heavy_job execution/queue_wait(別母集団)・deploy_total(既存deployレーン帰属)・singleflight_hold(保持時間・別母集団)・part2所有標的(P1a/P1b/finalize間隙/例外弾残差)・検査/送達保証/レビューの削除(品質底線)

## §0 結論 — 純オーバーヘッド標的序列【確定 — v4.0 snapshot正本】

序列SSOT=`docs/research/hot-script-speedup-round5-v4-snapshot-20260729.md`(source HEAD f8831da8e、固定窓2026-07-28T11:25:10Z..18:24:39.872864Z inclusive、全8,237行、raw SHA-256=db3fed9cc21495fb6d2a1f4584481c8c75b636af3a57dbc80e9218d443c8c9ed、v3.0窓との同一コード再計算5/5一致検証済み)。本書は序列の消費側であり再集計しない。非加算・別母集団の分類(three_layer/affected_tests/heavy_job/deploy_total/singleflight_hold)も同snapshotが正本。

| # | source:check_id | 累積 | n | p50 | p95 | max | 型 | 扱い |
|---|---|---:|---:|---:|---:|---:|---|---|
| 1 | inbox_write:inbox_write_total | 967.8s | 560 | 298ms | 6,264ms | 12,357ms | 恒常課税+外れ値(再) | **弾#1** |
| 2 | gate_gunshi_report_precheck:full_precheck | 507.2s | 131 | 1,077ms | 13,402ms | 21,531ms | 恒常課税+外れ値(再) | **弾#2** |
| 3 | report_publish:publish_total | 110.2s | 261 | 320ms | 600ms | 12,520ms | 恒常課税+外れ値(再) | **弾#3** |
| 4 | git_pre_commit:yaml_ast | 98.8s | 66 | 1ms | 6,460ms | 13,907ms | 外れ値型 | **弾#4** |
| 5 | report_field_set:commit_hash | 84.3s | 324 | 245ms | 490ms | 1,110ms | 恒常課税(再・計装済み) | **弾#5**(#3後直列) |
| 6 | report_field_set:files_modified | 29.2s | 54 | 520ms | 1,040ms | 1,560ms | 恒常課税 | **弾#6**(#5後直列) |
| 7 | git_pre_commit:sourced_dep | 20.9s | 66 | 2ms | 1,973ms | 4,161ms | 外れ値型 | **弾#7**(#4後直列) |
| 8 | report_field_set:task.commit_contract | 17.9s | 59 | 250ms | 650ms | 1,050ms | 恒常課税(再) | **弾#8**(#6後直列) |
| 9 | cmd_save:checks_main | 15.9s | 14 | 1,095ms | 2,233ms | 2,233ms | 恒常課税(再) | **弾#9** |
| 10 | git_pre_commit:shell_syntax | 11.5s | 66 | 2ms | 859ms | 2,415ms | 外れ値型 | **弾#10**(#7後直列) |

## §1 計測境界(第一弾§1の憲法を継承+本弾固有の注意)

- 全表=`docs/research/cmd_4181_overhead_boundary_recon.md`+v4.0 snapshot「非加算・別母集団」表。集計禁止・親子非加算の原則は同一
- **現行枝cohort分離(本弾最重要)**: 再挑戦5標的(#1/#2/#3/#5/#8)は窓内にbefore/after混在。AC1で是正commit以降のcohortのみ再集計してから是正判断(古いcohortへの最適化禁止=LS-A24)
- **git-pre-commit 3標的(#4/#7/#10)は全てp50数ms/p95秒級の外れ値型**: 恒常部は既に軽い。同event条件記録(対象ファイル数・種別)→3点表→条件ベース是正が正順。p50をこれ以上削る最適化は不要
- **report_field_set 4弾の直列**: 同一writerゆえ1レーン直列(#3→#5→#6→#8)。各弾クローズごとに次弾のbeforeを取り直す(前弾の是正が次弾の分布を変えるため)
- 親子非加算: full_precheck_body_rest等の子区分は親へ加算しない(診断用)

## §2 To-Be — 進め方(型を継承)

1. **1標的=1弾・複合弾禁止**。ACは同一条件before/after実測差分+品質2原則+選択テストFAIL0・SKIP0
2. **順序**: 解禁後は**最大5レーン並列**(5 writer=1ファイル1レーン)。report_field_setレーン=直列4弾、git-pre-commitレーン=直列3弾、他3レーン=各1弾。別ファイルは即並列
3. 計測は既存台帳のみ(新台帳禁止)。削減見込みの事前外挿禁止(実測のみ)
4. **凍結解除4段(第四弾と同型)**: (i)v4.0 snapshot正式版の家老確定(草案は作成済み・編集停止中)→(ii)本書v1.1の家老忖度なしレビュー→(iii)RC反映→(iv)殿裁可
5. 配備=家老自立配備(karo_direct)。完了ごとに掲示板1行報告、10弾全クローズで完了宣言+再snapshot

## §3 decision ledger(決定済み/裁可待ち/実測待ち)

| 項 | 状態 |
|---|---|
| 10標的・5 writer構成 | 決定済み(殿裁定03:30=10レーン+家老snapshot writer衝突表。途中追加しない) |
| 序列 | **確定**(v4.0 snapshot正本。将軍D0暫定窓との37行差は窓上限定義の統一で解消) |
| 窓上限定義 | 決定済み=checkpoint receipt確定時刻18:24:39.872864Z inclusive(家老採用・殿下知準拠) |
| three_layer_health等の除外 | 決定済み=v4.0 snapshot非加算表(mixed marker/実行本体込み/別母集団/deployレーン帰属) |
| 再挑戦5標的の改善余地 | AC1実測待ち(現行枝cohort分離後に判定。なしなら正直no-change CLOSE) |
| git-pre-commit 3標的の発火条件 | AC1実測待ち(同event条件記録→3点表) |
| 家老レビュー | **待ち(本v1.1)** — 家老は将軍v1.1提示後にRCを返すと宣言済み(blt_033325) |
| 殿裁可 | 凍結解除4段の(iv)。それまで実装ゼロ |

## §4 5W1H

- **WHY**: 第四弾クローズ後もv4.0固定窓に純オーバーヘッド上位10標的が残存(inbox_write 968s/full_precheck 507s/publish 110s他)。台帳再集計→新序列→次弾の反復が自動成長の回転そのもの。10標的はidle忍者6名を5レーンで飽和させる在庫量(殿裁定03:30)
- **WHAT**: 10標的=10弾・5 writerの覚醒高速化(設計のみ、実装凍結中)。再挑戦5弾=現行枝cohort分離先行、外れ値型4弾=発火条件特定先行、計装済み1弾=重複再判定
- **WHEN**: v4.0 snapshot正式確定→家老レビュー→殿裁可→起票解禁
- **WHERE**: §-1の5 writer+台帳=defense_overhead.jsonl
- **WHO**: 偵察・実装=忍者(最大5レーン並列・在庫10弾)、配備=家老自立、検分=家老+軍師、裁可=殿
- **HOW**: 恒常課税型=子区分集計→最大寄与是正→同条件Δ実測、外れ値型=同event条件記録→3点表→条件ベース是正、再挑戦=cohort分離→余地判定→是正または正直no-change。検査・送達保証は1つも削らない

## §5 因果リンク

- → [[hot-script高速化設計書]] 第一〜四弾。様式・計測の憲法・完了条件の型元
- → 第五弾v4.0 snapshot(`hot-script-speedup-round5-v4-snapshot-20260729.md`) **序列と非加算分類の正本**(source HEAD f8831da8e)
- → [[cmd_4181_overhead_boundary_recon]] 計測境界表(集計の憲法)
- → [[弾スループット全体ボトルネック改善]] part2(P1a/P1b・finalize間隙との境界)
- → [[殿裁定_全量テスト原則_20260728]] 個別弾選択実行・全量はwave最終1回
- origin: `[[殿下知_第五弾10レーン_20260729]] -> [[第四弾checkpoint_f8831da8]] -> [[家老v4.0_snapshot_8237行]] -> [[10標的5writer序列]]`
