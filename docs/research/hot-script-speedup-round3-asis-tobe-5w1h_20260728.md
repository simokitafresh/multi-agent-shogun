# ホットスクリプト集中高速化 第三弾 — AsIs/ToBe 5W1H設計書 v1.0 (2026-07-28 — ドキュメントのみ。実装は殿裁可まで凍結。第二弾と並行実行可能な素集合設計)

> 第一弾=`hot-script-speedup-asis-tobe-5w1h_20260727.md`(✅CLOSED 12/12)、第二弾=`hot-script-speedup-round2-asis-tobe-5w1h_20260728.md`(v1.2.2・進行中)。本書は殿方針(2026-07-28 12:26)「**第二弾で触るスクリプト以外から選別**」に基づく第三弾 — 第二弾とファイル素集合が交わらないため、**1ファイル=1レーン原理の下で第二弾と完全並行でき、idle忍者を埋める**。様式・計測の憲法・完了条件の型は第一弾を踏襲する。

## §-1 第三弾スコープ決め打ち(数を先に固定)

**決め打ち: 5スクリプト・5標的=5弾以内**(§0表がSSOT):

| 実体スクリプト | 標的 | 既存計器(=計測の正本。新台帳禁止) |
|---|---|---|
| `scripts/ninja_scope_commit.sh` | commit全体27.5s/回の削減 | terminal_ledgerのphase内訳(read_tree/add/scope_sync/guard/git_commit/advance_shared_index/post_check) |
| `scripts/cmd_complete_gate.sh` | 完了処理の純実行時間削減 | gate_metrics.logのfinalize_sec(※混合値。§1参照) |
| `scripts/gates/gate_shogun_startup.sh` | 起動17.7s/回の削減 | 内蔵TIMING行(59check計測済み) |
| `scripts/gates/gate_karo_startup.sh` | 起動16.1s/回の削減 | 同TIMING機構 |
| `scripts/gates/gate_gunshi_startup.sh` | 未実測→計測→削減 | 第一AC=TIMING計装(shogun/karo同型の既存機構移植) |

- **第二弾との衝突ゼロ検証**: 第二弾スコープ=cmd_save.sh/report_field_set.sh/git-pre-commit.sh(+レビュー対象gate_gunshi_report_precheck.sh、計装対象inbox_write.sh)。本弾5スクリプトとの共通ファイル0件。∴**第二弾3レーン+第三弾5レーン=最大8レーンが同時に立ち、忍者6名を常時充填できる**
- **完了条件(同型)**: 各弾=既存計器の同条件before/after Δ実測+品質2原則(正本突合+境界fixture)+選択テストFAIL0・SKIP0。**第三弾完了宣言=5弾全クローズ→全計器再集計→第四弾序列**
- **スコープ外(途中追加禁止)**: 第二弾対象ファイル・three_layer_health系(background保守lane)・deploy_task.sh本体
- **既存deployレーンとの整理(殿裁可事項)**: deployレーン残候補④「ninja_scope_commit 46秒」は本弾#1と同一標的のため**本弾へ吸収し、deployレーンの当該候補をクローズ**する(二重管理=車輪の再発明の解消)。残候補③report_publicationはdeployレーンに残す

## §0 結論 — 標的序列(選別根拠=第二弾対象外で「全員が毎回踏む」実測上位)

**選別の型が第一・第二弾と異なる**: defense_overhead.jsonl台帳内の第二弾対象外は非加算母集団(heavy_job execution/queue_wait・singleflight_hold・deploy_total)のみで標的が無いことをD0再集計で確認済み(固定窓23:36:00Z-03:26:00Z、row_count=4,396行)。∴第三弾は**台帳外だが既存計器に実測がある恒常課税**から序列を引く(第一弾Tier Bの正式昇格)。

| # | 標的 | 実測(既存計器・将軍D0回収 2026-07-28 12:26-12:30) | 型 | 課税対象 |
|---|---|---|---|---|
| 1 | ninja_scope_commit.sh | 本日将軍3回実測: phase_total 13,233/27,453/29,383ms。内訳例(29.4s回): git_commit 9,987/scope_sync 6,538(別回4,755)/post_check 5,827-5,984/advance_shared_index 1,579-2,716/read_tree 1,831-2,129ms | 恒常課税 | **全忍者+指揮官の全commit** |
| 2 | cmd_complete_gate.sh | finalize_sec全量n=431: median 626s/p95 6,345s/max 56,219s — ただし**混合値**(家老ターン待ち込み。§1) | 混合(要区分) | 全cmd完了 |
| 3 | gate_shogun_startup.sh | 17,660ms/回(TIMING_COVERAGE measured=59、今朝実測)。TOP: 三層学習ループ5,217/enforcement遅延2,613/スキルFAIL率1,185/孤立context 1,169ms | 恒常課税 | 将軍の全起動・復帰 |
| 4 | gate_karo_startup.sh | 16.1s/回(第一弾Tier B B2記載の実測) | 恒常課税 | 家老の全起動・復帰(auto-clear頻度が高く回数最多級) |
| 5 | gate_gunshi_startup.sh | **未実測** — 第一AC=shogun/karo同型のTIMING計装移植→実測→標的判断 | 未分類 | 軍師の全起動・復帰 |

## §1 計測境界(第一弾§1の憲法を継承+本弾固有の注意)

- 新台帳禁止。計測の正本=各スクリプトの**既存計器**(terminal_ledger phase内訳/TIMING行/gate_metrics列)。Δ証明も同計器の同条件before/after対で行う
- **★finalize_secは混合値**: gate_metricsのfinalize_secは「GATE CLEAR→完了処理終了」で家老のターン待ち・レビュー往復を含む。**cmd_complete_gate.sh自体の実行時間の区分計測が#2弾の第一AC**(区分前にmedian 626sを標的値として使うことを禁止 — deploy_sec誤計上事故(誤3,321s→真53s)と同じwriter混在の罠)
- startup gate弾の品質底線: 検査の網羅性を落とす削減(check削除)は禁止。「削るな、速くしろ」(殿裁定2026-07-21)— 実装最適化(重複実行排除・cache・並列化・遅延評価)のみ
- 親子非加算: phase内訳とphase_totalは非加算。TIMING行合計とgate全体wallも別掲

## §2 To-Be — 進め方(型を継承)

1. **1標的=1弾・複合弾禁止**。ACは既存計器の同条件before/after Δ+品質2原則+選択テストFAIL0・SKIP0
2. **順序**: #1 ninja_scope_commit(課税対象が最も広い)→#3/#4 startup gates→#2 cmd_complete_gate(区分計測先行)→#5 gunshi startup(計装先行)。ただし1ファイル=1レーンで全弾並行可のため、順序は充填優先で家老裁量
3. **並列構造(原理)**: 最大並列数=スコープ内の対象スクリプト数(1ファイル=1レーン)。本弾は5レーン。第二弾3レーンと合わせ計8レーン>忍者6名 — **常時idle 0名を構造で保証**
4. **凍結解除条件**: 本v1.0の家老忖度なしレビュー完了→殿裁可で順次起票。それまで実装ゼロ
5. 配備=家老自立配備(karo_direct)。完了ごとに掲示板1行報告、5弾全クローズで完了宣言+全計器再集計

## §3 未解決事項

1. gate_gunshi_startup.shの実測ゼロ — #5弾の第一AC(TIMING計装移植)で解消する設計
2. cmd_complete_gate.sh純実行時間の区分値 — #2弾の第一AC(区分計測)で解消する設計
3. ninja_scope_commitのphase別ボトルネックの機構(git_commit 10sはpre-commit hook込みか、scope_sync/post_checkの読み書き量) — #1弾の現読+phase実測で特定
4. startup gate高速化と「復帰の質」の両立基準 — check削除禁止の底線は§1で固定済み。遅延評価(起動時は要約のみ・詳細は参照時)の採否は弾内で家老+軍師検分
5. 本弾とB1復帰税(deepdive追体験68分・家老レーン進行中)の関係 — B1は追体験の「内容」であり本弾のstartup gateは「機構」。素集合は別だが、家老レーンの結論が出たら§0へ反映

## §4 5W1H

- **WHY**: 第二弾は最大3レーンで忍者6名を埋め切れない(殿指摘12:25)。第二弾対象外のスクリプトから「全員が毎回踏む」恒常課税を選別すれば、レーン衝突ゼロで並行でき、idle 0名と高速化が同時に進む
- **WHAT**: 5スクリプト5弾(commit経路1・完了処理1・startup gate 3)の覚醒高速化(設計のみ、実装凍結中)
- **WHEN**: 本v1.0家老レビュー→殿裁可→起票解禁。第二弾と並行実行
- **WHERE**: §-1の5スクリプト+計測の正本=各既存計器
- **WHO**: 偵察・実装=忍者(並列数=対象スクリプト数の原理、本弾5)、配備=家老自立、検分=家老+軍師、裁可=殿
- **HOW**: 恒常課税型=既存計器で現状把握→フェーズ分解→最小差分実装→同計器Δ証明。混合値check=区分計測先行。未実測=計装移植先行。check削除による短縮は禁止

## §5 因果リンク

- → [[hot-script高速化設計書]] 第一弾(CLOSED)。様式・憲法・完了条件の型元。Tier B(B2/B3)の正式昇格
- → 第二弾設計書(gist e13277d8) 並行レーンの相方。素集合交わりゼロの設計根拠
- → [[deploy control-plane速度改善]] 残候補④ninja_scope_commitを本弾#1へ吸収(クローズ提案)
- → [[殿指摘_idle根絶_20260728]] 本弾の直接の発端(6名フル充填)
- origin: `[[殿下知_第三弾先行計画_20260728]] -> [[第二弾対象外から選別]] -> [[台帳外恒常課税5本_8レーン並行でidle0]]`
