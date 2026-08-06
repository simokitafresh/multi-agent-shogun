<!-- gist-master: 59a5e79368f385cddfdb0656fd8ca3bd hot-script-speedup-round9-asis-tobe-5w1h_20260804.md -->
# ホットスクリプト集中高速化 第九弾 — 外れ値型admission+配備経路+cmd_save本体 — AsIs/ToBe 5W1H設計書 v1.6 【✅CLOSED — 3 CLEAR + 5 FAIL-close】

> v1.6(2026-08-05 18:53進捗同期): #0'' common lifecycleは最終修正commit `3d56941d7c8629b6869e0302b90fb8eeba1e64e0`で実Codex SessionStart・直接SessionStart・nested sourceが各1行、duplicate/missing各0、focused 323/323、計装overhead p95=0.018msを成立させGATE CLEAR。第九弾の実装CLEARは1件となった。一方、Codex/git/basicと#2 Track A/Bほか正式FAIL-close 5本は偽CLEARにせず保留し、2026-08-05 18:03将軍下知により戦力を第十・十一弾へ移した。

> v1.5(2026-08-05 17:47進捗同期): #0''実装をcommon lifecycleとCodex/git/basicの2 shardへ配備。commonは3 commit・focused 323/323・単独ledger 8/8まで成立したが、`session_start_inject.sh`がsource-specific抑止markerを未受理で実Codex SessionStartが2行となるため家老RC中。Codex/git/basicは2 commit・focused 128/128を得た一方、同marker依存とp50非悪化未達(+4.120ms)を正しくFAIL-close。#2 queue_waitは独立Track A/Bを完走し、固定cutoffでqueue=2,558・execution=2,490・queue-only=109・execution-only=41・重複0を確定したが、非同期writerの個別欠落原因を台帳だけでは一意化できず両TrackをFAIL-close。実装CLEARはまだ0件であり、偵察CLEARを実装完了へ数えない。

> v1.4(2026-08-05 02:40 殿裁定): §2.6 checkpoint契約を追加(全弾共通)

> v1.4(2026-08-05 00:14進捗同期): #0''偵察A/B・#1・#3はGATE CLEAR。別parent偵察再利用gate hotfixもcommit `c341e923fba7a3ad427f055569c24a015511a889`・focused 9/9・false判断0/7でGATE CLEAR済み。ただし#0''実装shardは現行task/report/gateが存在せず未配備のため、完了扱いしない。#4はpreflight mode metadata欠落、補欠Aは親子共通run_id欠落を一次特定して正当FAIL-close。両FAILは「数値不足」ではなく、次の高速化を可能にする計装identity欠落の発見である。

> 状態: v1.2(2026-08-04 20:16 殿裁可『よい。追記したらレーン方式で家老にやらせよう』。§0.6母集団漏れ3系(git pre-push/Codex固有hook/セッション境界+基本コマンド)を弾#0''スコープへ同梱) / v1.1(2026-08-04 18:58 §0.6サイレント盲点サーベイ追加+弾#0''をhookチェーン計装として弾台帳へ追加) / v1.0初版起草(2026-08-04 18:46。殿発案『第九弾の設計書を作ろう。以前の設計書を参考にして同じスタイルで。進捗表も』)。序列=将軍一次実測18:46(下記§0)

> シリーズ: ホットスクリプト集中高速化。第一弾〜第四弾✅ / 第五弾=`hot-script-speedup-round5-asis-tobe-5w1h_20260729.md`✅(10レーン) / 第六弾=`throughput-bottleneck-part2-asis-tobe-5w1h_20260728.md`(identity基盤完成・P1b蓄積待ち) / 第七弾=`hot-script-speedup-round7-test-speed-asis-tobe-5w1h_20260729.md`✅(全量wall -3.35%確定) / 第八弾=`hot-script-speedup-round8-asis-tobe-5w1h_20260804.md`(本体12/12 GATE CLEAR・wave checkpoint進行中) / **第九弾=本書**

## §-1 スコープと境界(数と原理を先に固定)

- **標的=エージェント実働時に毎回課税されるホットスクリプトの実行時間のみ。防御の検証力は1点も削らない**(品質2原則=正本突合判定+境界fixture両方を維持。殿裁定2026-07-21『削るな、速くしろ』が憲法)
- **第八弾との境界**: 第八弾標的(three_layer_health 3種・git_pre_commit affected_tests・gunshi precheck body_rest・補欠A/B/C)は本弾で触らない。第八弾#1-#3/#5の進行と本弾は**writer非重複ゆえ並列可**
- **writer構造(第五・七・八弾の写像)**: 1スクリプト(の1ホットパス)=1弾=1レーン。共有層(`scripts/lib/`)に触れる弾は独立writerかつ先行→固定HEADで再計測→個別弾の直列依存。並列変更禁止
- **スコープ外**: gate/hookの削除・条件緩和(必須ハーネス保持=LS099)/テスト実行時間(第七弾CLOSED)/DM-Signal側Python(別repo)/第八弾標的全部
- **第0手=序列覚醒(第五弾RC1教訓の恒久化)**: 本書§0は起草時snapshot。**殿裁可(起票解禁)時に最新ledgerでfixed-window再実測し、序列不変を確認してからレーン配備する**。弾#0'計装(第八弾)で新たに台帳へ載った*_total群(startup gate三本・semantic_index_update・ninja_scope_commit・cmd_delegate等)は蓄積が浅いため、第0手の再実測で序列入りすれば補欠へ昇格させる

## §0 序列SSOT(2026-08-04 18:46 将軍一次実測 — 既存台帳のみ・新台帳なし)

**取得方法**: `logs/defense_overhead.jsonl`(174,227行)から2026-07-28以降の行を抽出し、source:check_id別にwall_msの中央値と累積を算出(1件=jsonl 1行=1計測イベント)。集計はPython statistics.median+sum、生出力を下表へそのまま転記。第八弾標的は表に残すが背景色扱い(本弾対象外)。**累積時間はagent-hours(全CLI合算)**=9並列CLIの全呼出しの合計であり壁時計の24h/日を超えうる。

### 累積課税序列(第八弾標的を除いた次層)

| 順 | source:check_id | 累積 | median | n | 帰属 |
|---|---|---|---|---|---|
| - | three_layer_health 3種 | 338,205s | - | - | 第八弾#1-#3 |
| - | `git_pre_commit:affected_tests` | 31,669s | 4.05s | 720 | 第八弾#4(済 -65%) |
| 1 | `heavy_job_admission:execution` | **30,957s** | 0.00s | 1,250 | **本弾** |
| 2 | `deploy_task:deploy_total` | **19,275s** | 1.86s | 2,383 | **本弾** |
| - | `inbox_write:inbox_write_total` | 18,021s | 0.33s | 8,864 | 第八弾補欠A |
| - | `gate_report_format:singleflight_hold` | 13,014s | 0.32s | 4,167 | 第八弾補欠B |
| 3 | `gate_gunshi_report_precheck:full_precheck` | **10,164s** | 1.22s | 2,136 | 条件付き(下記) |
| 4 | `heavy_job_admission:queue_wait` | **8,839s** | 0.00s | 1,313 | **本弾**(#1と同族) |
| 5 | `cmd_save:checks_main` | **4,826s** | 1.31s | 881 | **本弾** |
| 6 | `cmd_save:save_total` | 893s | **2.47s** | 155 | **本弾**(#5と同scriptゆえ合同) |

**読み**: 第八弾標的を除くと、(a)**heavy_job_admission系**(execution+queue_wait合算≈39,800s)がmedian 0の外れ値型で最大——「何が長い裾を作るか」の発火条件特定が先。(b)**deploy_task:deploy_total**は全cmd配備に乗る恒常課税(med 1.86s×2,383)。第六弾系譜で-47%済みだが残余が依然として次層TOP。(c)**cmd_save系**はsave_total計装(第八弾#0')で全体wall med 2.47sが可視化された——checks_main 1.31sとの差分+--preflight実測≈150sとの乖離の内訳特定が本弾で可能になった。(d)full_precheck本体は第八弾#5(body_rest)の同族上流ゆえ、**#5の帰結確定後にのみ着手**(条件付き)。

## §0.6 サイレント盲点サーベイ(v1.1追加 — 殿指示2026-08-04 18:55『台帳に乗っていないスクリプト・デーモン・hook・gate・基本コマンドを覚醒調査』)

**手法**: (1)台帳全期間のsource一覧をPython Counterで抽出(1件=jsonl 1行) (2)母集団を4系で列挙: .claude/settings.json登録hook/dispatch経由hook実体/ps実測の常駐デーモン/基本コマンドscript (3)各実体をrg -c defense_overheadで突合 (4)未接続の代表4本をdummy payloadでwall実測。

**結論: エージェントの全tool呼出し・全prompt・全Stopに乗る「hookチェーン」全体が台帳に1行も載っていない。** 台帳接続済み27 sourceは「scriptが自分で書く」型のみで、CLIライフサイクル層(PreToolUse/PostToolUse/UserPromptSubmit/Stop/SessionStart)は完全な暗黒地帯。

**未接続実体一覧(rg -c defense_overhead=0を確認)**:

| 系 | 実体 | 発火頻度 | 将軍サンプル実測(2026-08-04 18:57 dummy payload 1回) |
|---|---|---|---|
| 毎tool呼出し | pretool-dispatch.sh(+pre-bash-combined他5本) | 全agentの全tool call | **204ms/回** |
| 毎tool呼出し | posttool-dispatch.sh(+post-bash-combined他6本) | 同上 | **357ms/回** |
| 毎prompt | prompt_state_inject.sh(三層preflight注入込み) | 全agentの全UserPromptSubmit | **1,207ms/回** |
| 毎Stop | stop_check_inbox.sh+stop_session_alerts.sh+stop-lint-gate.sh | 全agentの全ターン終了 | stop_check_inbox=**943ms/回** |
| セッション境界 | session_start_inject.sh / session_end_clear_check.sh | 毎/clear・毎起動 | 未実測(startup gate側は第八弾#0'で計装済み) |
| 常駐デーモン | inbox_watcher.sh×9 / ninja_monitor.sh / ntfy_listener.sh | 常時ポーリング(WSL2 statポーリング) | 未実測(*_total型でなくcycle計装が要る) |
| 基本コマンド | semantic_search.sh / bulletin_write.sh / inbox_mark_read.sh / lesson_write.sh | agent操作の度 | 未実測 |

**規模感(概算・網羅保証なし)**: pretool+posttool≈0.56s/tool callは、全agentのtool call数(台帳proxy: inbox_write 24,712行/全期間と同オーダー以上)を掛けると**three_layer_health級(数万秒/週)の暗黒課税**になりうる。prompt_state_inject 1.2s×全promptも同格。ただしdummy payload 1回の点推定であり、分布・実頻度は計装後のledgerでのみ確定する。

**含意**: 第八弾#0'の原理「エントリポイントには必ず*_total計装」を**CLIライフサイクルhook層へ拡張**する弾(仮称**弾#0''**)が、序列確定の前提として本弾の全是正弾に先行すべき。デーモンはcycle単位計装(1ポーリング=1row)を別型で設計する。

**v1.2追記(母集団漏れ3系 — 将軍突合実測2026-08-04 20:15)**: (a)**git hooks**: `.git/hooks/pre-commit`はdefense_overhead接続済みだが、`grep -l defense_overhead`でpre-push/commit-msg/post-commitは不検出=未接続。忍者の全commit/pushに乗る層 (b)**Codex固有hook**(`.codex/hooks.json`の`codex_skill_execution_guard.sh`等): dispatch共有分は弾#0''で自動カバーされるが、Codex専用実体は別途1行計装が要る(multi-CLI大原則=CLI固有実装はCLI別に計装) (c)**セッション境界2本+基本コマンド4本**(semantic_search/bulletin_write/inbox_mark_read/lesson_write): §0.6表で未実測のまま。いずれもsave_total型と同型ゆえ**弾#0''スコープへ同梱**(追加コストほぼゼロ)。デーモンcycle計装のみ別型として分離を維持。

**注意(計測の再帰課税)**: hook計装自体がhookを遅くしては本末転倒。defense_overhead_write_asyncの非同期書込み(既存live実装)を使い、計装オーバーヘッド<5ms/回をfixtureで確認してから展開する。

## §1 計測境界(憲法・第五〜八弾継承)

- 計測=既存台帳のみ(`logs/defense_overhead.jsonl`)。**新台帳禁止**(knowledge:fbb5716c)
- before/afterは**同一スクリプト・同一check_id・同一環境**のfixed-window比較。異なるcheck_idの混算禁止
- run間ノイズ: 各check_idの分布(p25/p75)を先に取り、Δ有意判定はノイズ帯超のみ
- 効果宣言=個別Δの総和ではなく、**修正後1週間の累積課税(total秒)の前週比**を正式確定値とする
- 外れ値型(median 0)は中央値比較が無意味——**p95/p99と裾の総量(total)**で判定する

## §2 To-Be — 進め方(型を継承)+品質底線

1. **1標的=1弾・複合弾禁止**。恒常課税型=子区分計測→最大寄与是正/外れ値型=発火条件特定→条件ベース是正
2. **品質底線**: (a)防御の検証力不変(admission制御の排他保証・deploy契約検証・cmd_save gate判定は全て固定。検証を弱める高速化禁止) (b)PASS/FAIL挙動不変=是正前後で同一入力の判定完全一致 (c)敵対fixture=是正で変更した独立oracle・副作用境界ごとに1点
3. 仮説在庫(序列裏取り済みの初期観察のみ・事前外挿禁止): heavy_job execution med 0×total 31,000s=少数の長裾job(全量テスト・GS級)が総量を支配する疑い→p99上位の実jobを台帳から同定/deploy_total=第六弾で-47%後の残余の子区分(inject系・contract生成)未分解/cmd_save save_total 2.47s vs checks_main 1.31s=未計装区間≈1.2sの同定+--preflight経路150sの別経路特定
4. **反復サイクル型**: ローカル極限化→live計測→差分再検証→再極限化。停止条件=Δがノイズ帯以内でクローズ(採用またはno-change)
5. **read-only冗長並列**: 子区分計測・発火条件記録はread-only冗長2名先着採用可。是正実装は単独所有
6. 個別弾は選択実行(`bash scripts/run_tests.sh file <対象>`)FAIL0・SKIP0のみ。途中try回数最大化・厳密さは最終checkpointへ集中
7. 完了宣言=全弾クローズ→修正後1週間のledger累積課税を前週比で総括→CLOSE刻印
8. **方式=レーン方式**(第五・七・八弾の型): 殿裁可→将軍下知(掲示板blt)→家老レーン配備→gate_metricsへlane名CLEAR刻印→最終checkpointで品質2原則検分。cmd正式起票はしない
9. **lane最小AC/wave checkpointの二層契約**(**殿裁定2026-08-04 19:26『今後もレーン方式ではこのスタイルでいこう』で恒久化**。経緯=殿AC過剰厳格性監査→軍師blt_192103の5観点→将軍検分採用19:25。原理=殿19:10『再実走よりも再配備が高速回転に直結』): 【lane最小AC】focused fixture PASS+コード変更確認+p50/p95非悪化のみ。scope外全量テスト・並行中固定HEAD比較・commit後全量再測定を途中レーンに課すな(小太郎9回BLOCK実測=回転税)。設計baseline差は数値報告して続行(停止はwave判断)。【wave最終checkpoint】全量FAIL0+全lane間独立比較+全量再測定+正式効果確定(1週間ledger前週比)。検証の総量は不変、実施位置を正しい場所へ

### 提案弾台帳(殿裁可で固定)

| # | 標的 | 型 | 現状 | 手筋候補(実測で裏取り後) |
|---|---|---|---|---|
| 1 | `heavy_job_admission:execution` | 外れ値 | med 0s×1,250・total 30,957s | p95/p99の実job同定→長裾jobの条件ベース是正(admission排他保証は不変) |
| 2 | `heavy_job_admission:queue_wait` | 外れ値(待機) | med 0s×1,313・total 8,839s | #1の裾同定と合同で真因特定→wait発生条件の是正。#1と同scriptゆえ直列(#1→#2) |
| 3 | `deploy_task:deploy_total` | 恒常課税 | med 1.86s×2,383・total 19,275s | 残余の子区分計測→最大寄与是正(第六弾-47%の続き。inject系・contract生成の分解) |
| 4 | `cmd_save:save_total`+`checks_main` | 恒常課税 | save_total med 2.47s×155 / checks_main med 1.31s×881 | 未計装区間≈1.2sの同定+--preflight実測≈150s経路の別経路特定→最大寄与是正 |
| **弾#0''** | **CLIライフサイクルhook層の計装**(pretool/posttool dispatch・prompt_state_inject・stop hooks **+v1.2同梱: git pre-push等未接続git hooks・Codex固有hook・セッション境界2本・基本コマンド4本**) | 計測基盤 | §0.6: 全て台帳未接続。サンプル実測=pre 204ms+post 357ms/毎tool、prompt 1,207ms/毎prompt、stop 943ms/毎Stop | save_total型のdispatch入口T0+EXIT trap 1行write(非同期・計装overhead<5ms fixture確認)。**全是正弾に先行** |
| 補欠A | `gate_gunshi_report_precheck:full_precheck` | 恒常課税 | med 1.22s×2,136・total 10,164s | **第八弾#5(body_rest)帰結確定後のみ着手**(同族writer衝突回避の直列条件) |
| 補欠B | 弾#0'計装で新規に載る*_total群 | 計測覚醒待ち | startup gate三本・semantic_index_update・ninja_scope_commit・cmd_delegate等(蓄積<1日) | 第0手の序列再実測で序列入りすれば昇格。特にninja_scope_commit(体感46s・本日index.lock競合3件の主戦場)とstartup gate(毎/clear分単位) |
| 補欠C | 共有lock競合ファミリー | 待機(横断) | 本日実証3件: prompt_consumed_ledger flock timeout(殿prompt消失)・git index.lock競合・DASHBOARD flock timeout(archive worker 5件) | lock保持時間の計測row追加→保持長の真因特定のみ本弾。是正は判断後(DrvFS上の共有lockは設計変更を伴うため) |

- 弾#1→#2は同一script(heavy_job_admission)ゆえ直列。#3・#4は独立writerで並列可。補欠は条件成立後に殿へ昇格提案

## §2.5 進捗台帳(第七弾§-2.4様式 — 2026-08-05 18:53家老更新。gate_metrics/report/task/commit一次突合)

| # | 標的 | 状態 | 帰結(実測生値) |
|---|---|---|---|
| 0'' | CLIライフサイクルhook層計装 | ✅**common shard GATE CLEAR** / ⚠️**Codex・git・basic shard FAIL-close・保留** | common=`cmd_karo_round9_lane0pp_impl_common_20260805`: final commit `3d56941d7c8629b6869e0302b90fb8eeba1e64e0`(先行 `f40638966`+`eea1ebcd3`+`8e6527a3c`)、focused 323/323・FAIL0・SKIP0。直接SessionStart=1、実Codex SessionStart=1、nested source=1、duplicate=0、missing=0、overhead p95=0.018ms。`logs/gate_metrics.log` 18:07:26 CLEAR、完了処理済み。Codex/git/basic=`cmd_karo_round9_lane0pp_impl_codex_git_basic_20260805`: commits `9ec61cb06`+`bf682d194`、focused 128/128・FAIL0・SKIP0だがmarker依存未解消かつp50差分+4.120msで正式FAIL-close。実装GATE CLEAR=1 |
| 1 | `heavy_job_admission:execution` | ✅**偵察GATE CLEAR** | `cmd_karo_round9_lane1_heavy_execution_recon_20260804`: n=2490/zero=1729/nonzero=761/p95=132550ms/p99=733110ms/max=1191000ms/total=66858000ms。p99上位25件をevent_id分類。実装0件 |
| 3 | `deploy_task:deploy_total` | ✅**偵察GATE CLEAR** | `cmd_karo_round9_lane3_deploy_total_recon_20260804`: n=3930/p50=1815.0ms/p95=49980.4ms/max=991086ms/total=40537853ms。`check_yaml_freshness`結合486件・子179171ms、未計装残差40358682ms。最大子区分`report_publication`=366回/2145960ms |
| 4 | `cmd_save:save_total`+`checks_main` | ⚠️**偵察FAIL-close** | `cmd_karo_round9_lane4_cmd_save_recon_20260804`: save_total 155件、checks_main 2088件、結合108組。preflight mode metadata 0/155で全件分類不能、task wildcard実行0件、ac_version不一致。偽CLEARにせず計装課題へ還流 |
| 2 | `heavy_job_admission:queue_wait` | ⚠️**独立Track A/B完走・両FAIL-close** | Track A=`cmd_karo_round9_lane2_queue_wait_recon_20260805`: 全期間queue n=2,665/zero=2,276/nonzero=389/p95=10,000ms/p99=333,000ms/max=1,222,000ms/total=29,070,000ms、execution pair=2,518、queue側欠落147・execution側欠落58、focused 152/152。Track B=`cmd_karo_round9_lane2_queue_wait_recon2_20260805`: 固定cutoff queue=2,558/execution=2,490/common=2,449/queue-only=109/execution-only=41/重複0。非同期queue writerの個別欠落原因を一意化できず実装へ進まずBLOCK |
| 補欠A | `full_precheck`本体 | ⚠️**条件成立→偵察FAIL-close** | `cmd_karo_round9_spare_a_full_precheck_recon_20260804`: parent n=5362/child n=5039、共通run_idなし、unmatched=823・child-after-parent=9で一意結合不能。明示Bats 34/34 PASS。数値は正本再配備後に再結合する |
| 補欠B | 新規*_total群 | 🔒計測蓄積待ち | 現行queue task/report/gateなし |
| 補欠C | 共有lock競合ファミリー | ⏳未配備 | 直近下知の昇格撤回に従い元の条件待ちへ復帰。短期ノイズで追加契約を積まない |

- **第九弾関連GATE CLEAR 6件**: 既存5件(#0'' Track A/B、#1、#3、再利用gate hotfix)に、#0'' common実装CLEAR 1件を追加。実装CLEARは1件、偵察/先行gate CLEARは5件。
- **実装進捗**: #0'' commonのみ実装GATE CLEAR。Codex/git/basicはFAIL-close。#1・#3は偵察CLEAR後の実装0件。#2は独立二重偵察まで完走したがidentity不足で実装0件。#4・補欠Aもidentity計装待ち。
- **正式FAIL-close 5本**: #0'' Codex/git/basic 1本、#2 Track A/B 2本、#4 1本、補欠A 1本。いずれも未達をPASSへ丸めず、欠損identityまたは性能非悪化未達を保持した。偽CLEAR 0件。
- **先行インフラ根治**: `scout_reports`明示再利用hotfixはcommit `c341e923fba7a3ad427f055569c24a015511a889`・focused 9/9・false判断0/7・GATE CLEAR済み。
- **現行方針(2026-08-05 18:03将軍下知)**: 第九弾は#0'' common CLEARをcheckpointとして、正式FAIL-close群を一時保留。独立忍者は第十・十一弾へ移す。再開時の順序は (1)Codex/git/basicを統合HEADで再検証 (2)#2 queue/execution共通identity計装 (3)#1→#2是正 (4)#3実装 (5)#4 mode metadata・補欠A共通run_id。
- **正式効果**: 全是正弾完了後、修正後1週間ledger累積課税の前週比で確定。現時点は偵察段階ゆえ未確定。

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
| 第九弾の起動 | 殿発案2026-08-04 18:46。**殿裁可2026-08-04 20:16『よい。追記したらレーン方式で家老にやらせよう』(v1.2)** |
| 序列snapshot | 起草時実測済み(§0=2026-08-04 18:46・174,227行)。**第0手=裁可時に再実測**(第五弾RC1教訓) |
| 弾数・標的固定 | **裁可で固定(2026-08-04 20:16)**: 弾#0''(v1.2同梱スコープ)+4弾+補欠3 |
| heavy_job 2弾の直列 | 提案(同一script writer原則)。裁可対象 |
| 高速化と防御力の境界 | **確定**: 検証力不変・fail-closed維持・チェック間引き禁止(LS099/殿裁定07-21『削るな速くしろ』) |
| 起票解禁 | **配備済み・進行中**。#0''と#2の実測結果は§2.5へ同期済み。次の依存順序は§2.5「次レーン順序」を正とする |

## §4 5W1H

- **WHY**: 第八弾標的の外に、heavy_job admission系≈39,800s+deploy経路19,275s+cmd_save系の未計装乖離が残存。ホットスクリプトの遅さはスループットと自動成長の回転数への直接税(殿裁定2026-07-21『削るな、速くしろ』)
- **WHAT**: 外れ値型2弾(発火条件特定→条件是正)+恒常課税2弾(子区分→最大寄与是正)。検証力不変で実行時間のみ削る
- **WHEN**: 設計書裁可後、第0手(序列覚醒)→レーン配備。効果確定=修正後1週間ledger前週比
- **WHERE**: `scripts/`配下のheavy_job_admission系・deploy_task.sh・cmd_save.sh。台帳=`logs/defense_overhead.jsonl`
- **WHO**: 子区分計測=忍者(read-only冗長2名可)、是正実装=忍者(単独所有)、検分=家老+軍師、裁可=殿
- **HOW**: レーン方式(将軍下知→家老配備→lane名CLEAR刻印→最終checkpoint品質2原則検分)。敵対fixtureで是正ごとに検出力を確認

## §5 因果リンク

- → [[hot-script-speedup-round8-asis-tobe-5w1h_20260804]] 直前弾(進行中)。標的境界とwriter非重複の根拠
- → [[殿裁定_削るな速くしろ_20260721]] 品質を保ったまま超速化=憲法(knowledge:569abc55)
- → [[ledger-driven-campaign-lane-pattern_20260714]] レーン方式の型元
- → [[殿裁定_厳密さは最終チェックのみ_20260714]] 途中try最大化・報告整形は最終集約
- → [[codd_refactor_deploy_control_plane_20260723]] deploy_total -47%の先行実績(弾#3の続き)
- origin: `[[殿発案_第九弾_20260804]] -> [[第八弾標的外の次層一次実測]] -> [[外れ値型+配備経路+cmd_save本体v1.0]]`
