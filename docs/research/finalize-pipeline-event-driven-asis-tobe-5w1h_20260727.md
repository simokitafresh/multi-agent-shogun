# 完了パイプライン(finalize段)イベント駆動化 — ASIS/TOBE 5W1H (2026-07-27)

- 起案: 将軍(殿下知 2026-07-27 14:24「次のボトルネックは何だ」→14:27「設計書を作成し、家老と軍師にレビューしてもらえ。忖度なしで実装前提で未調査や未検証、未決定事項がない設計書が必要だ」)
- 一次調査: 将軍(2026-07-27 14:27-14:40、コード現物精読+ログ全数走査)
- origin: `[[殿問い_次のボトルネック_20260727]] -> [[finalize663s>work552s]] -> [[本設計書]]`

## §1 ASIS — finalize段が作業本体より重い

### 実測(3系統の独立した一次データが同じ場所を指す)

| # | 証拠 | 数値 | 取得コマンド |
|---|---|---|---|
| E0 | throughput計器(母集団368完了cmd) | `e2e_median=2210s / work_median=552.5s / finalize_median=663.5s / overhead_rate_median=56.9%` — **finalizeがworkを上回る** | `bash scripts/loop_ledger_update.sh` 出力の生貼付。1件=完了cmd 1件 |
| E1 | gate空振り | `review_two_phase_pending` BLOCK **本日45件中32件(71%)**、うち27件が1cmdに集中し**05:10:22〜05:16:59の6分37秒・約12秒間隔** | `grep '2026-07-27' logs/gate_metrics.log \| grep BLOCK \| awk '{print $4}' \| sort \| uniq -c`(家老blt_110002)+将軍再読。1件=gate_metrics BLOCK行1行 |
| E2 | rc=75偽BLOCK | CLEAR成立後のcmd_complete再実行4回→`review_two_phase_pending`偽BLOCK 1件がgate_metricsへ記録→追記型訂正が必要化 | 家老自己申告blt_103624+knowledge:a00a2948ba1c5b36。1件=誤BLOCK記録1行 |
| E3 | auto-push空振り | pre-push BLOCK **32件/日**(全てGA-PUSH1=未commit重複path)。cmd_complete_gateのauto-pushが完了処理のたびに試行 | 家老blt_102353(全数集計45件中32件)。1件=hook_failures.yamlレコード1行 |
| E4 | self_retro支配因 | dominant cause=**completion_pipeline**(13:23)と**review_notify**(13:38)、いずれもverification=passed | logs/self_retro.jsonl(INSIGHT_FIX_KNOWN自動分析2本) |

### 欠陥の構造(コード現物で確定)

**D1. gateの起動経路は2本+起動主体を記録しない第三経路が実在する**
- 正規経路(1): `scripts/cmd_complete.sh:258`(run_checkpointed経由。checkpoint成功時マークのためBLOCK時は再入で再実行)
- 正規経路(2): `scripts/review_approval.sh:471`(LGTM+ACCEPT両承認成立時にsetsid非同期起動。`.gate_triggered.$manifest`のnoclobberで同一manifest 1回に制限=**ここは既にイベント駆動かつexactly-once**)
- **第三経路(未特定=特定不能が確定事実)**: E1の27回連続BLOCKは、(a)当該cmdのtrigger.logに`review_two_phase_pending`が0件(grep -c実測)、(b)completion_tail.logはSKIP群のみのclean実行、のため正規経路2本のどちらにも帰属しない。将軍がlogs/全体を横断走査(05:10:34/05:10:49の秒一致grep)しても主体は出ない。**理由はcmd_complete_gate.shが起動主体(pid/ppid/呼出し元)をどこにも記録しないこと**。∴「誰が27回叩いたか」は現行実装では観測不能 — これ自体がASISの欠陥である(T0で是正)
- 12秒間隔の解釈: gateはBLOCK時に即exit 1(`cmd_complete_gate.sh:6452-6457`現物)で自己リトライを持たない。∴約12秒はgate 1実行のwall time≒呼び手が終了を待って即再実行する密ループの周期(27回の間隔実測 12〜15s)

**D2. 二相承認チェックがgate実行の深部にあり、空振りでもフル実行コストを払う**
- `cmd_complete_gate.sh:6443-6457`: `review_all_reports_ready`判定はtask_type検出・report解決の後段。未承認状態での起動1回ごとに約12秒(E1周期実測)と、gate_metricsへのBLOCK行1本(統計汚染)を必ず支払う

**D3. rc=75ロック競合時、既にCLEAR済みかを機械が判定しない**
- CMD_IDロック(rc=75)→呼び手が再試行→ロック解放後にgateが再実行→報告archive済みの状態を`review_two_phase_pending`と誤判定して偽BLOCK記録(E2の機序、家老実証)。skills/cmd-complete SKILL.md Step5に「archive済みならstatus更新不要」と**文章では**書いてあるが機械強制がない(意志依存)

**D4. auto-pushが結果の分かっている状態でも毎回試行する**
- `cmd_complete_gate.sh`のGATE CLEAR後push(:466付近のDRY_RUN分岐実在をgrepで確認)は、未commit変更と同一pathが残る間は必ずGA-PUSH1でBLOCKされるのに毎完了処理で試行→hook_failures 32件/日とGA再通知の源泉(inbox洪水の一因にも接続)

## §2 TOBE — 原理1行

**「完了gateの実走は『承認が揃った』イベントで一度だけ。それ以外の呼出しは状態を読んで即返る。全起動に主体を刻む。」**
二相承認の実質(gunshi LGTM+karo ACCEPT+fingerprint一致)・fail-closed・既存checkpoint機構は一切緩めない(殿裁定07-21「削るな、速くしろ」)。

### T0. 起動主体の記録(D1の観測不能性是正・最初に入れる)
- `cmd_complete_gate.sh`冒頭に1行: `caller pid=$$ ppid=$PPID cmdline=$(tr '\0' ' ' </proc/$PPID/cmdline)` を当該cmdのtrigger.logへ追記
- 効果: 第三経路の次回発火時に主体が自動特定される。追加コスト=/proc読み1回(ms未満)
- 決定: 記録先は既存trigger.log(新ファイルを作らない)

### T1. 二相承認pre-checkのfast-path化(D2是正・主軸)
- gate冒頭(重い処理の前)で承認台帳(`queue/gates/<cmd>/review_approvals/{gunshi,karo}.yaml`)の存在+fingerprint一致を軽量チェック
- **未承認なら即exit**: フル実行に入らない。gate_metricsへは**同一承認状態での2回目以降は記録しない**(初回のみ`BLOCK review_two_phase_pending`を記録。判定: `.pending_recorded.$manifest_state`のnoclobber — review_approval.sh:465の既存`.gate_triggered.$manifest`と同一パターンの再利用)
- 決定(忖度なしの断): 2回目以降を「skip行として記録」ではなく**無記録**とする。理由=E1の27件はスパムであり、初回BLOCK+T0のcaller記録で監査性は足りる。反証歓迎
- 効果見込み(算術): E1型の空振り1件あたり約12秒×26回=約5分/cmdの尾を除去+品質統計の汚染源71%を根絶

### T2. rc=75/再入時の終局状態先読み(D3是正)
- `cmd_complete.sh`入口で`gate_metrics.log`の当該cmd最新終局行を読み、**CLEARなら**gate再実行をスキップして残checkpoint(dashboard/ntfy/archive)のみ再開
- 既存部品の再利用: 集計が「cmd毎最新1件採用」である事実(knowledge:a00a2948)と、checkpoint機構(`run_checkpointed`:103-112現物)をそのまま使う。新規状態ファイルなし
- 効果: E2の偽BLOCK機序を機械的に封じる(SKILL.md Step5の意志依存を構造化)

### T3. auto-pushの事前判定(D4是正)
- push試行前に`git status --porcelain`と対象pathの重複を照合し、**GA-PUSH1確定の状態なら試行せず1行ログでスキップ**(判定はpre-push hookと同一条件の先読み)
- 効果: hook_failures 32件/日とGA再通知の源泉除去。push自体の契約(CI GREEN・保留裁定)は不変更

### T4. 効果計測(既存計装のみ)
- before固定値(本設計書§1): finalize_median=663.5s / review_two_phase_pending BLOCK 45件中32件 / pre-push BLOCK 32件/日
- after: 同一コマンド(`loop_ledger_update.sh` / gate_metrics grep / hook_failures集計)で前後比較。目標=**空振りBLOCK 0件/日・finalize_median 20%以上短縮**
- 記録先: 既存logs/defense_overhead.jsonl(`source:cmd_complete_gate`)。新台帳なし(knowledge:fbb5716c)

## §3 5W1H

| | 内容 |
|---|---|
| **WHY** | finalize(663.5s)がwork(552.5s)を上回り、その主成分に空振り実行・偽BLOCK・無駄push試行という「結果の分かっている仕事」が含まれる |
| **WHAT** | T0起動主体記録+T1 pre-check fast-path+T2終局先読み+T3 push事前判定+T4前後計測。承認の実質・fail-closedは不変更 |
| **WHEN** | 家老・軍師レビュー→殿裁可→cmd起票。1道具1CMD: T0+T1を第1弾(同一ファイル同一関数域)、T2第2弾、T3第3弾 |
| **WHERE** | cmd_complete_gate.sh(T0/T1/T3) / cmd_complete.sh(T2) / defense_overhead.jsonl(T4) |
| **WHO** | 将軍=設計+起票、家老=分解配備、忍者=実装、軍師=本設計レビュー+実装レビュー |
| **HOW** | 境界fixture(§4) + 前後実測(§2 T4) |

## §4 境界fixture(実装ACへ転記する。最低8件)

1. 承認0/2でgate起動→即exit・フル実行なし・gate_metricsにBLOCK 1行(初回)
2. 同一承認状態で2回目起動→即exit・gate_metrics追記なし・trigger.logにcaller行あり
3. 承認1/2(LGTMのみ)→fixture 1と同挙動(部分承認は未承認扱い)
4. 承認2/2揃い→フル実行に入る(fast-pathが誤って塞がない)
5. 承認2/2だがfingerprint不一致→BLOCK(二相の実質は緩めない)
6. CLEAR済みcmdへのcmd_complete再入→gate再実行なし・残checkpointのみ進む・偽BLOCK 0
7. GA-PUSH1確定状態でのCLEAR後push→試行せずスキップ1行(hook_failures増加0)
8. 重複pathなし+CI GREEN→pushは従来通り実行される(T3が正常pushを塞がない)

## §5 不変更契約

| 対象 | 契約 |
|---|---|
| 二相承認の実質(LGTM+ACCEPT+fingerprint一致) | 不変更。fast-pathは順序を前へ出すだけで判定条件は同一関数(review_all_reports_ready/review_gate_manifest_ready)を使う |
| fail-closed(承認なしにCLEARしない) | 不変更 |
| checkpoint機構・exactly-once fence(.gate_triggered.$manifest) | 不変更。T1の.pending_recordedは同パターンの追加であり置換ではない |
| push契約(CI GREEN・保留裁定・pre-push hook) | 不変更。T3はhookと同一判定の先読みのみ |

## §6 決定事項(未決定を残さない)

| 論点 | 決定 | 根拠 |
|---|---|---|
| 空振り2回目以降のgate_metrics記録 | **無記録**(初回のみ記録) | E1の27件はスパム。監査はT0のcaller記録+初回BLOCKで足りる |
| T1判定の実装位置 | cmd_complete_gate.sh冒頭(CMD_ID解決直後) | 空振り時のコストを最小化。判定関数は既存を呼ぶだけ |
| pending_recordedのリセット条件 | 承認manifest状態の変化(=fingerprint集合が変わる) | review_approval.sh:465の既存manifest計算を再利用 |
| 弾の分割 | T0+T1/T2/T3の3弾 | 1道具1CMD(LS-A04(14))。T4は各弾のACに内蔵 |
| W(リトライ間隔)等の新チューニング値 | **なし** | 本設計はポーリング値の調整ではなく実行そのものの除去 |

## §7 将軍が調査済みで「不能」と確定した事項(未調査ではない)

- E1の27回起動の主体: **現行実装では特定不能**(gateが起動主体を記録しないため)。将軍はtrigger.log(該当0件)・completion_tail.log(clean)・logs/全横断(秒一致grep)まで走査済み。T0導入後の次回発火で自動特定される — 特定を待たずにT1が空振り自体を無害化するため、主体特定は本設計の前提条件ではない
- finalize 663.5sの完全な内訳分解: gate_metricsのdeploy/work/finalize 3分割までが現行計装の粒度。関数単位の帰属はT4のdefense_overhead計装(check_id単位)が埋める — 実装弾AC1に「変更前のbaseline計測(check_id単位)」を含めることで、本設計の効果測定と同時に取得する

## §8 因果リンク

- → [[commander-inbox-flood-asis-tobe-5w1h_20260727]] E3/GA再通知で接続(同族: 結果の分かっている仕事の反復)
- → [[LS096]] 同一結論を繰り返す検知器=情報価値ゼロ(E1のBLOCK 27連は同型)
- → [[knowledge:a00a2948ba1c5b36]] rc=75偽BLOCKの機序と追記型訂正
- → [[殿裁定_削るな速くしろ_20260721]] 承認・fail-closedは削らず、無駄な実行だけを除去
