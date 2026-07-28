# 進化量レポート — 速度と品質の因果を実測で示す(2026-07-27〜07-29) v3.0

origin: [[殿指示_進化量gist共有_20260726]] + [[殿指示_完全再構築_20260729_0315]]
period: 2026-07-27 〜 2026-07-29 03:15(全面改稿版 v3.0。旧版v2.0=07-25〜26期はgit履歴に保存)
すべて一次実測。台帳=logs/defense_overhead.jsonl / gate_metrics.log / test_receipts / 報告YAML / 掲示板証跡
**主題: 速度向上は目的ではなく手段。全ての速度改善が「品質向上にどんな効果を出したか」を各節末尾の→効果で明示する。**

## §0 この期間の要約 — 数字で3行

- **hot-scriptレーン4弾連続全クローズ**(第一弾12/12・第二弾9/9・第三弾2/2・第四弾5/5)。設計→AC1 read-only診断→実装→Δ実測→正直no-changeの型が28弾で回った。
- **是正の効果が下流の計測で客観実証**: 例外弾のunattributed残差が旧9,530秒級→**T1a計装後の窓で最大724秒・例外2/40弾へ縮小**(疾風P2全数計測)。前日の根治群(stale report再配備・lost-wakeup)が効いた証拠が、別忍者の独立計測で出た。
- **正直FAILの文化が構造として動いた**: P2/P3/P4のAC1が3本とも「前提乖離で停止」を選び、誤った母集団での最適化を1件も通さなかった。全量checkpointは2巡で残存不整合2件を検出・是正。

## §1 個別最適化 — スクリプト単体の速度向上(第四弾Δ実測)

| 対象 | 前(v3.0固定窓) | 後 | 真因と是正 |
|------|-----|-----|------|
| full_precheck(軍師レビュー前検査) | 子区分body_restが58.1%を占有、max 23.1s | **重複tree走査0呼出**(name-only 2,438.6ms→0)。stdout SHA-256完全一致 | fixed-hash経路が同一treeを二重走査していた |
| inbox_write(全エージェント通信) | median 354.5ms/p95 4,653ms | **median 182ms/p95 348ms** | delivery_verifyを送達保証を維持したまま非同期化(自動既読type群・flock persist・nudge契約は不変) |
| publish_total(報告公開) | 競合下max 6,370ms | **248ms** | 外れ値真因=singleflight待ち+async telemetryへのlock FD継承。非terminal batchをterminal gate lockから分離 |
| checks_main(cmd起票検査) | 序列4位 | **正直no-change** | v3.0序列は既存最適化後のsnapshotで追加重複なし — 「実装しない」を実測で選択 |
| commit_hash(報告telemetry) | 回数最多n=584(旧窓) | **識別子計装+重複0証明→batch化なし** | report_id/task_id非破壊追加。重複が実在しないことを一次証明してからno-change |

第三弾(同期間クローズ): ninja_scope_commit phase_total p50 **-12.7%**(共有index読取りN+1→1回)/cmd_complete_gate=純実行0ms実証による正直no-change。

**→品質への効果**: 5弾中2弾が「no-change」で閉じた。計測が「やらない判断」を根拠付きで下せる状態=過剰最適化の構造防止。full_precheckのstdout SHA一致・inbox_writeの送達契約不変など、**全弾が検査を1つも削らずに達成**(削るな速くしろの運用形)。

## §2 全体最適化 — 弾ライフサイクルの非work時間(part2レーン)

**AsIs全数実測(本日CLEAR 53弾)**: e2e総計134,154秒のうち**非work時間が41.3%**(finalize 27,985s > unattributed 20,813s > deploy 6,600s)。この分解が初めて数値で確定し、4弾(P1a/P1b/P2/P3/P4)の設計へ接続した。

| 弾 | 結果 | 発見 |
|----|------|------|
| P1a(識別子計装) | 実装commit済み・蓄積開始 | defense_overheadイベントにcmd_id/generation不在を将軍D0実測で確定→計装が全ての前提 |
| P2(例外弾残差) | **正直no-change BLOCK** | 例外弾が旧9,530s級→**2/40弾・max724sへ縮小**(=前日是正の効果実証)。必須8遷移中6遷移が台帳欠損で分解不能 |
| P3(再attempt税) | **正直FAIL BLOCK** | generation列がgate_metricsに不存在=世代分類が物理的に実行不能。49cmd・100 BLOCK行の時間欠損も検出 |
| P4(deploy外れ値) | **正直FAIL BLOCK** | 母集団定義の乖離を検出(§0基準=本日CLEAR 53弾 vs 実査=全期間1,645件で累積23,654s)。誤った基準での最適化を阻止 |

**→品質への効果**: 3弾が同じ結論「識別子計装が先」へ独立に収束し、レーンの正順(P1a蓄積→P1b→P3/P4)が**仮説でなく実測で確定**した。誤った母集団・欠損データの上での「削減実績」を1件も作らなかったことが本レーン最大の品質成果。

## §3 高速回転による構造問題の露出と根治(速度→発見量→品質)

### 3a. CI偽REDの二重真因を1夜で解明・根治
3run連続で5分台cancel→将軍がconcurrency相互キャンセルと誤診し交通整理・静止期間まで発令→**静止期間中も同時刻帯でcancelされた事実が誤診を棄却**→真因(a)=unit jobの`timeout-minutes: 5`をテスト成長(5分15秒超)が超過、GitHubのjob強制killはcancelled表示になる。是正=5→12分+契約テスト2件同期。真因(b)=`test_three_layer_knowledge_chain` 7件FAIL: fixtureがgitignore済み`data/`DBをcopyしており**CI checkoutでのみ落ちる**構造。影丸がclean worktree再現証跡(pre-fix FAIL7→post-fix PASS0)付きで正本スキーマ直接生成へ根治。→ **run 30377787485 success(8分59秒)でGREEN復帰**。誤診の過程ごと教訓LS101へ統合(「連続cancelはconcurrency犯人探しの前にtimeout-minutesを見よ」)。

### 3b. 全量checkpointが「合成不整合の最終検出器」として機能
レーン別レビュー・CIでは通っていた残存不整合を2巡で2件検出: 1巡目=`test_ninja_monitor_stall` case48(PASS 2,822/2,823)、2巡目=**所有task 0の未commit 9行隔離修正が共有worktreeに滞留**(LS-A14(2)「未commitの共有ツリー編集は存在しないのと同じ」の実例)。いずれも即日修正GATE CLEAR。3巡目実行中。

### 3c. 通信インフラの二重送信・自動RC失効を根治
- same-cmd redeployがtask_assignedを重複永続化+watcherとasync verifierの二重nudge → 同一cmd再配備の識別+既存未読再利用+watcher稼働時のdirect retry委譲(a7c27dd41/1be8bee8f)。
- 自動RCの「前taskの情報は無効」blanket適用が有効な計測成果まで失効させ**車輪の再発明**を発生 → correction scopeを永続化し、report-only RCは既存計測・artifactを再利用する契約へ修正。

### 3d. 数値報告4規律の実運用定着
集計コマンド併記・出力行の生貼付・1件の定義・網羅範囲明示が掲示板の書式として機械強制され(bulletin_writeが欠落をBLOCK)、本期間の主要報告(v3.0 snapshot・checkpoint・P2/P3/P4)は全て母集団hash・receipt付き。**「誰が数えたかで結果が決まる」問題が書式レベルで封じられた**。

**→品質への効果**: 3aは「診断の誤りを一次事実が棄却する」実例として、3bは「速度改善の後始末を機械が拾う」実例として、それぞれ再現可能な型になった。

## §4 組織の進化(検証の分散の深化)

- **家老レビューの精度が構造検出レベルへ**: publish_total writerの帰属誤り(4本目script)を現物rgで訂正、P1の「read-only開始×実行不能完了条件」の契約矛盾を検出、gist同期のbyte diffを検証依頼——設計書は毎版、家老RC→即時反映→追認の2〜3往復で確定した(part2はv1.0→v1.7を1晩で7版)。
- **忍者の正直FAILが罰されず機能した**: 疾風P2・才蔵P3・飛猿P4のFAIL報告は全て「前提乖離での模範停止」として設計書に採用され、レーンの正順を決めた。FAILが情報として還流する状態。
- **誤検知エスカレーションを将軍が一次確認で棄却**: 「家老が対処できない」CRITICAL 3件は全て検知遅れの空砲(実態は配備済み・完了報告済み)で、capture-pane/タスクYAML/報告YAMLの一次確認が誤った介入(将軍cmd起票)を3回防いだ。
- **将軍の誤診も記録・還流**: concurrency誤診→交通整理の空振り→真因発見の全過程をLS101統合教訓として環境へ埋め込み。旧runのrerunが最新runを道連れにする挙動も含め、CI運用の判断則が1夜で3つ増えた。

## §5 現在地と次

- 第四弾: checkpoint 3巡目実行中。PASSで**完了宣言→固定窓再snapshot(v4.0)→第五弾序列**を殿へ提示。
- part2: P1a計装データ蓄積中(弾の自然流量で蓄積)。P1b(finalize間隙pairing=最大標的27,985秒)はP1a蓄積後、P3/P4は再開条件(generation計装/母集団統一)を起票ACへ明記後。
- 正本群: 第四弾=gist 9700daa0(v2.5)/part2=gist 89b0a0ad(v1.7)/第三弾=gist 30b9635d(v3.0 CLOSED)/part1=gist 2179df85(v1.6、残T1b)。

## 因果リンク
- [[hot-script高速化設計書]] 第一〜四弾(様式・計測の憲法) / [[弾スループット全体ボトルネック改善]] part1-part2 / [[hot-script-speedup-round4-v3-snapshot-20260728]] 序列SSOT / [[LS101統合CI RED診断2手順]] / defense_overhead.jsonl / gate_metrics.log / logs/test_receipts
