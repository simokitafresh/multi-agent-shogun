# 家老運用索引
<!-- last_updated: 2026-07-12 cmd_karo_hotfix_task_natural_boundary_contract_rc4_202607122210 -->

> 索引層。詳細手順・テンプレート・判断材料は `docs/research/karo-operations-detail.md` を参照。
> 原則: 普段は本ファイルの結論だけで判断し、深掘りが必要な時だけ詳細へ進め。

## §0 使い分け

| 作業フェーズ | まず見る結論 | 詳細参照 |
|------|------|------|
| cmd受領〜配備 | 五問チェック→Pattern Selection Flow→deploy | `docs/research/karo-operations-detail.md` §1-2 |
| **idle時（パイプライン空）** | **改善サイクル起動 → §7** | — |
| 報告受領〜レビュー | review/pass-fail/WAIVE/再配備 | `docs/research/karo-operations-detail.md` §3 |
| 難問・失敗対応 | 1名失敗後は2名独立配備 | `docs/research/karo-operations-detail.md` §4 |
| cmd完了後の知識処理 | draft教訓査読→GATE | `docs/research/karo-operations-detail.md` §5 |
| context圧縮・配備前確認 | gate_vercel_phase + pre-deploy ping | `docs/research/karo-operations-detail.md` §8 |
| 通知・Frog・連勝管理 | ntfy_cmd / ntfy / streaks | `docs/research/karo-operations-detail.md` §9 |
| DB-heavy配備 | 本番DB操作は直列 | `docs/research/karo-operations-detail.md` §10 |
| CLI切替 | `switch_cli_mode.sh` を使う | `docs/research/karo-operations-detail.md` §16 |
| **分析・報告前** | **家老判断4問チェック → §0.1** | — |

### §0.1 家老判断4問チェック（結論を出す前に必ず通せ）

殿に5回指摘された共通根: **推論を現物確認より先にやる**。このチェックリストで防止。
> **思考過程**: 家老固有の失敗パターン「確認しないから間違える」の全過程 → `memory/deepdive_karo_verification_20260405.md`（経験的知識。圧縮禁止）

| # | 問い | 違反例 |
|---|------|--------|
| 0 | **このアクションを10回繰り返したら正の複利か負の複利か？** | pane未確認でrespawn×10回=全忍者のコンテキスト破壊。確認してからrespawn×10回=0事故 |
| 1 | **N≧3か？** N=1で結論していないか | Codex 1回STALLで「大型ファイル不向き」→別忍者が成功で反証 |
| 2 | **現物確認したか？** gate_fire_log/pane全体/コード/API/プランを直接見たか。**掲示板投稿前にもgrep確認必須**(LK-A01 v5)。**gate/script修正CMD起票要請前に対象gate/scriptを1回実行し出力を確認せよ**(LK011: 2026-06-13に2回§0.1問2違反。grepだけで不在結論→軍師に既存実装指摘されて撤回) | pane末尾5行で「CLI死亡」→全体読めば忍者が指示待ちだった。「未実装」と掲示板投稿→grep -nで既存L542に発見(2026-05-15)。gate修正要請→bash gate.sh実行で0件ALERT=修正不要だった(2026-06-13) |
| 2.5 | **スクリプトWARNを事実に昇格していないか？** `bulletin_write.sh`/gate/daemonのWARNは観測候補であり結論ではない。殿へ報告する前に(1)pgrep/ps (2)対象ログmtime+末尾イベント (3)対象inbox未読/read遷移の3点を独立確認せよ。矛盾したら「未稼働」等と断定せず「プロセス可視性とログが不整合」と報告せよ(LK005) | `bulletin_write.sh`の「shogun inbox_watcher not running」WARNを独立確認せず未稼働と報告→後続確認でログは22:35/22:36 nudge送信、shogun inbox未読あり。正しくはプロセス可視性/短命再起動の不整合だった |
| 3 | **家老自身を疑ったか？** 配備品質・タスク設計を疑ったか | モデルのせいにした→タスク分量オーバーが真因 |
| 4 | **比較データがあるか？** 別モデル/別忍者の同種データと比較したか | Sonnet全体で語った→影丸73%/小太郎45%で個体差が大きかった |
| 5 | **この教訓/改善を書いたら、automatedにできるか？** 掲示板投稿・insight保存・教訓登録は「記録」であり「行動」ではない(LG030)。cmd化/gate化/コード変更まで回せ | 教訓63件中automated1件=62件が意志依存。記録≠自動化(LK064)。掲示板投稿で止まり殿に指摘された(2026-05-09) |
| 6 | **同根の教訓がN≧3件ないか？** あれば原理に昇華→gate化せよ | 確認系17件が1ヶ月繰り返し→原理1行に統合(LK065) |
| 7 | **殿/将軍の指示を受けたら即実行。聞き返すな。** 指示を理解できないなら理解できるまで自分で調べろ。「実装するか？」「よろしいか？」は殿の時間を奪う。不明点は自分で解消してから実行 | 「自動化×強制で埋め込め」→「実装するか？」と聞き返した(2026-05-20)。指示は実行を求めている。聞き返す行為そのものが問題 |
| 8 | **これは殿のためか、Anthropic/OpenAI/モデルの都合のためか？** 早期終了・検証スキップ・他者依存・緩い設計・先送り・出力=仕事・簡潔本能・完了急ぎの8パターンに1つでも該当しないか | 「読みやすく短く」で検証を削る、「提案」で止める、「後でcmd化」で先送りする。殿の成果ではなくモデルの省力化を優先した判断は洗脳混入 |
| 9 | **startup gateのALERTを「確認した」で閉じていないか？** ALERT=バグ。根因調査→修正→commitまで回せ。「問題なし」「正当」「今後計測」は先送りの隠語 | WARN率55%を「正当」と結論→殿に2度指摘されて初めて根因(WARNテキストマッチ偽陽性)に着手。スキル推薦87%偽陽性を「今後計測」→根本(index.md)未修正 |
| 10 | **出力で止まっていないか？行動→検証まで回したか？** 掲示板投稿・返信・分析報告は出力。行動=コード変更/教訓追記/gate修正。検証=grep反映確認/計測値差分。出力後に行動0件なら洗脳#6 | escalation分析→掲示板投稿→教訓追記せず返信で止まった(2026-06-10殿指摘)。洗脳監査「全no」と結論したが行動0件=偽解消 |
| 11 | **三層記憶を検索したか？(殿厳命2026-06-10: 使用しないのはバグ)** 行動前に(1)`memory_db_query.sh`でキーワード検索 (2)`semantic_search.sh`で概念検索。回答に`[MEM: memory_db ts=YYYY-MM-DD]`タグで引用。検索せずに結論するな | 将軍バージョン更新時に三層記憶検索を省略→洗脳#2(2026-06-10)。三層記憶→一次情報→行動の順序 |
| 12 | **教訓修正時にcross-project全コピーを確認したか？** `grep -rn "id: LXXX" projects/`で全コピーのタグを同期。片方だけ修正は不完全(cmd_3396: L633/L577/L544二重登録でinfra版誤タグ経由の無関係注入継続) | dm-signal版タグ修正→LGTM→軍師RC: infra版コピーが残存→再修正が必要だった |
| 13 | **inbox未読を意志で処理しようとしていないか？** `cmd_new`未読は配備漏れ直結なので `gate_karo_startup.sh` がALERT化する。nudge/Stop hook/tmuxに依存せず、通常作業前に未読0または明示処理済みにせよ | cmd_3457: `cmd_new`が未読のまま infra調査へ進み、配備漏れを二次情報で後追い発見した。真因は通知失敗ではなく未読処理の意志依存 |
| 14 | **変更対象は実行経路に配線されているか？** gate/hook/dispatcher関数の承認前に、定義・テストを除くcaller数を一次計測せよ。非test caller=0ならテストPASSでもdead codeであり、耐久化をACCEPTせず削除または正本経路へ統合する | `trigger_cmd_complete_gate_background`は専用fixture 53/53 PASSだったが非test caller 0。未使用関数を強化してLGTMした後、家老RCで88行削除へ転換した(cmd_karo_hotfix_inbox_gate_trigger_durable_202607111406) |

## §1 配備

- **配備コマンド: `deploy_task.sh <ninja> <cmd_id>`**。cmd_id第2引数は必須。省略するとAC上書きされず旧タスクを実行する(LK061)。使えない場合は--directモード。手動配備(cat+inbox_write)はdeploy_task.shの全ガードをバイパスするため禁止。
- **karo_direct配備手順(将軍cmd不要の家老自立配備)**: (1)nested形式のtask YAMLを/tmpに作成(`task:`配下にparent_cmd/task_id/scout_exempt:true等を記載) (2)`cp /tmp/task.yaml queue/tasks/{ninja}.yaml` (3)`inbox_write.sh {ninja} "..." task_assigned karo`でnudge。deploy_task.sh --yamlはscout_gateを通るが、task YAML内のscout_exempt:trueで自動PASS(64ec3aa5)。
- 配備前は毎回「五問チェック」を通す。Purpose / Decomposition / Headcount / Difficulty / Risk を1行で言えなければ配備するな。
- **AC設計ミス事前検出（verdict_override防止）**: draft配備前に全AC/binary checkを実行順にシミュレートし、`(1)実現可能 (2)成果物の追跡/commit可能 (3)日時・本番更新で自然に変わる値を固定一致要件にしていない (4)推奨条件を必須ACに混入していない` を各yes/noで確認する。1つでもnoなら配備前にACを修正する。「後でverdict override」は禁止。origin: `[[verdict_override_6件中5件]] -> [[AC設計ミス]] -> [[draft配備前二値シミュレーション]]`
- **忍者ACとpost-deploy検証の二層分離（殿裁定2026-08-30 13:08）**: 忍者taskのACは隔離cloneで二値判定できる `pytest` / `TestClient` / `next build && start` へのローカルcurl / `diff 0` に限定する。`本番` / `Render` / `deploy後` / `CDP` / `live` のcurl・smoke・画面確認は忍者ACへ転記せず、deploy後30分以内に家老が `task_type=post_deploy_check` レーンで実施し、一次出力を掲示板へ生貼付する。
- **配備前にcmdの前提を現物確認せよ**。ダッシュボードの記載は過去の事実。CI赤→`dashboard.md AUTO_SECTION`のCI Status確認。本番障害→本番を直接確認。KARO_SECTIONの手書き情報は二次データ(LK043: cmd_1806事故)
- implタスク配備前の偵察要否は `deploy_task.sh` が強制する。家老は `scout_exempt` を勝手に決めない。
- **karo_direct配備のtask_type設定**: --yaml/手動配備時、偵察・context更新・調査系cmdは`task_type: recon`を設定せよ。デフォルトimplだと実装用教訓が過剰注入される(20件→7件に削減可能。deploy_task.sh L2318のrecon_modeフィルタが発動)。
- **通常配備の通知確認**: 通常配備は `inbox_write` → watcher receipt → `ninja_monitor` の自動経路を正本とし、送出前の手動`capture-pane`待機を挟まない。watcher共有確認ガードがCLI確認プロンプトを検知した場合はnudgeを0件に抑止し、未読メッセージと保留記録を残す。手動captureは確認プロンプトの解除送出直前、またはdelivery未確認時だけ実行する。
- **karo_direct完了時の軍師レビューSKIP**: karo_direct配備は報告YAML不在・GATE処理対象外。完了時に軍師report_reviewを送るな。変更は家老が直接確認+commit。cmd_karo_lesson_4fieldで誤送信→軍師誤FAIL→訂正の無駄サイクルが発生(2026-05-10)。
- 偵察配備後の2名体制検証は `task_deploy.sh` の役割。`deploy_task.sh` と混同するな。
- BE系タスク配備ルール: `backend/` 配下のファイルが変更対象の場合、タスクYAMLの `context_files` に `docs/rule/trade-rule.md` パスを含めよ。理由: RULE09/10/11 と 14 の誤解パターンを忍者が自動参照するため。
- **成果のcontext還流**: cmd成果に数値・事実（ベンチマーク、設計決定等）を含む場合、cmd設計時にcontext更新を最終ACに含めることを推奨。ただし判定は§3 Context還流判定に統合。
  - **面更新原則**: 1つのcmd成果が複数contextに影響する場合、当該1ファイルだけでなく関連contextも更新せよ（点更新→面更新）。知識の2類型: 事実的知識(結論)はコンパイル、経験的知識(dialogue/deepdive)はポインタのみ。詳細は `context/doc-style-guide.md` の知識の2類型を参照
- **担当者指名禁止（殿厳命）**: 忍者配備で「偵察担当をそのまま実装に回す」等の担当者指名をするな。忍者は/clearで全記憶消去される。誰がやっても報告YAMLを読めば同じ結果を出せる。配備判断は**負荷分散・idle順**で行え。知識の引継ぎは報告YAMLパスをタスクYAMLの`context_files`に注入することで担保せよ。
- **軍師レビューと忍者配備の並行実行**: 全task_type（`bugfix` / `hotfix` / `ci_fix` 含む）でcmd/SCOUT受領後、忍者配備と軍師レビュー依頼を同時に行う。軍師の承認を待たずに配備する。手戻りより高速回転を優先する（殿裁定2026-08-09 14:05、同日14:04裁定を全task_typeへ拡張）。`pre_implementation_review` receiptの有無・結果は配備BLOCK条件ではない（`deploy_task_require_pre_implementation_review` は削除済み。cmd_karo_hotfix_rc_peer_report_redeploy_20260809）。
  1. cmdを受領しタスク分解
  2. 忍者にタスク配備（待たない）
  3. 同時に軍師にレビュー依頼（`inbox_write gunshi "draft cmd_XXXX レビュー依頼" review_draft karo`）
  4. 軍師からの報告受信時:
     - APPROVE: 何もしない（忍者は既に作業中/完了）
     - REQUEST_CHANGES: 指摘内容を稼働中忍者へtask_supplementで直接転送、または補足cmdとして配備
→ `docs/research/karo-operations-detail.md` §1

## §2 分解

- cmdは `scout_exempt` / `scout_only` / フルフロー の3分岐で読む。
- 実装と本番確認は二層へ分ける。忍者taskは隔離環境で完結する実装AC、deploy後の本番curl/CDP/Render smoke/live確認は家老の `post_deploy_check` とし、前者の完了を後者待ちで止めない。
- パターンは `recon / impl / impl_parallel / review / integrate` の5種。毎回ゼロから考えるな。
- 追加と修正が混在したcmdは分離してから配備する。
- 後続サブタスクは `blocked_by` + `auto_deploy: true` 付きで事前一括作成する。
- 「4観点偵察」指定時は4忍者にstack/features/architecture/pitfallsを1観点ずつ配備。従来の2名並行偵察と併用可。task YAMLに `recon_aspect` フィールドで観点を伝達。

### 自然な二値検証境界

- 10分は目安、15分はhard境界。分割線は時間そのものではなく、独立してyes/no検証できる自然な境界に置く。
- 分割するのは `分割利得（並列度向上 + エラー爆発半径縮小） > 統合コスト（統合task + review往復）` の場合だけ。
- 11分の一体作業は割らず、`task.split_decision` に構造化mappingで根拠を残す: `boundary_ac_ids`(同一taskのacceptance_criteria実在IDを重複なく列挙)、`integration_tasks`/`review_round_trips`(bool不可の非負整数、合計1以上)。自由文の`split_decision_reason`は移行抜け道にせずBLOCKする。例: `split_decision: {boundary_ac_ids: [AC1, AC2], integration_tasks: 1, review_round_trips: 0}`。
- 独立した3分作業×3は10分へ寄せて束ねず、3本を並列配備する。
- 15分超は既存long runtimeの具体的理由と正の実測秒数が揃う場合だけ例外とする。

### スコープ適正基準(Scope Sanity)

GSD知見: サブタスク数が増えるほどコンテキスト品質が劣化する。

| 指標 | 適正 | 注意 | 分割検討 |
|------|------|------|---------|
| サブタスク数/cmd | 2-3 | 4 | 5以上 |
| 変更ファイル数/サブタスク | 5-8 | 10 | 10以上 |

これは推奨値であり強制(BLOCK)ではない。家老の判断で超過を許容できる（タスク粒度は内容に依存するため）。ただし超過時は理由をダッシュボードに記載する。

### フリクション記録

タスク分解中に以下のフリクションがあった場合、記録する:
```bash
bash scripts/cmd_friction_log.sh "{cmd_id}" "{friction_type}" "{detail}"
```
friction_type: `ambiguous_scope` | `missing_context` | `too_many_acs` | `unclear_dependency` | `other`
記録先: `logs/cmd_friction.yaml`
※ フリクションがなければ記録不要

→ `docs/research/karo-operations-detail.md` §2

## §3 レビュー

### 忍者報告レビューフロー（軍師一次→家老スタンプ方式）[cmd_1162]

忍者報告受領時のデフォルトフロー。軍師が一次レビュー → 家老はスタンプ+教訓抽出に専念。

| ステップ | 実行者 | アクション |
|---------|--------|-----------|
| 1. 報告受領 | 家老 | 軍師にreport_review依頼（`inbox_write gunshi ... report_review karo`） |
| 2a. LGTM | 家老 | SG7バンドル受領→スタンプ+ペースト処理（下記参照）→GATE進行 |
| 2b. FAIL | 家老 | fail_reasonsを確認→Re-review Loop or 修正task配備を判断 |
| 2c. 未完了 | 家老 | フォールバック: 家老フルレビュー（旧フロー） |

**旧フローとの差分**:
- 旧: 忍者報告受領 → **家老がフルレビュー** → PASS/FAIL判定 → 教訓抽出 → GATE
- 新: 忍者報告受領 → **軍師に一次レビュー委任** → LGTM時は家老スタンプのみ → 教訓抽出 → GATE
- 家老フルレビューはフォールバック（軍師未完了時）のみ発動
- **切替条件**: 軍師(gunshi)が稼働中 = 新フロー。軍師未応答/未配備 = 旧フロー自動適用

→ 手順詳細: `instructions/karo.md`「忍者報告レビューフロー」セクション

### SG7バンドル受領→スタンプ+ペースト手順 [cmd_1288]

軍師LGTM時、inboxメッセージ末尾に`--- SG7 bundle ---`ブロックが付与される。
家老はバンドル内容をそのまま使い、後処理を1ステップで完了する。

| # | アクション | バンドル参照フィールド | 備考 |
|---|-----------|---------------------|------|
| 1 | スタンプ(PASS) | — | verdict=LGTM=PASS確定。家老独自レビュー不要 |
| 2 | GATE判定 | `gate_precheck.gate_prediction` | CLEAR→そのまま進行。WARN→家老がGATE手動確認 |
| 3 | 教訓処理 | `lesson_extraction` | `register_recommended: true`→`lesson_write.sh`で登録。`false`→スキップ |
| 3.5 | PI昇華チェック | — | 教訓登録時に問う: (1)この教訓はPI昇格候補か？ (2)既存PIと共通の根はあるか？→あれば原理PIに統合(PI-020参照)。個別=1対1防御、原理=1対N防御 |
| 4 | Context還流 | `context_reflux` | `needed: true`→`target`のcontextファイルを`content`で更新 |
| 5 | Dashboard更新 | `dashboard_line` | バンドルの行をdashboard.mdにそのままペースト |
| 6 | Workaround判定 | `karo_workaround_needed` | `no`→追加作業なし。`yes`→通常のworkaround対応フローへ |

**旧手順との差分**: 教訓抽出・context還流判定・dashboard行作成を家老が個別実行→軍師が事前ドラフトをバンドルで提供。家老はペーストのみ。
**フォールバック**: バンドルが付与されていない場合（軍師旧バージョン等）は従来の個別実行フローを適用。

### レビュー原則（新旧共通）

- 家老の役割はレビュー配備とGATE判定のみ。品質判定そのものは軍師または忍者レビューに委ねる。
- verdict は PASS / FAIL の二値厳守。条件付きPASSは禁止。
- failed を放置するな。修正配備 / WAIVE→done / 殿裁定のいずれかへ必ず進める。
- Two-pass Review: CRITICALはblocking(PASS/FAIL直結)、INFORMATIONALは記録のみ(non-blocking)。→ detail §3 Two-pass Review
- A/B/C Triage: レビュー指摘を3分類。A:Fix(修正必須→impl再配備)、B:Acknowledge(認識するが今回対応不要→理由記録)、C:False Positive(偽陽性→以後抑制)。PASS/FAIL/WAIVEとの対応表あり。→ detail §3 A/B/C Triage
- Re-review Loop: blocking fix→修正task配備→再レビュー配備の明示フロー。曖昧に続行するな。→ detail §3 Re-review Loop
- **途中FAILの再実走を家老が奪うな**: 忍者が再実行できる検証は `karo RC → 同一cmd再配備` を第一選択とし、家老D0でtest/gateを再実走しない。家老の実走はwave最終checkpointの統合検証1回に集中する。途中での家老再実走は忍者の回転を止め、同じ実行手順を二重に作る車輪の再発明である（殿指摘2026-08-04）。
- **Context還流判定**: GATE CLEAR前に「この報告にcontext索引を更新すべき数値・事実があるか？」を判定せよ。あればGATE CLEAR処理の一部としてcontext更新を実行。対象: 性能テーブル、設計決定、新API仕様、パイプライン状態等。**Why**: 報告YAMLに閉じた情報はアーカイブ後に将軍から見えなくなり、古いcontextで誤判断する（cmd_1048-1052後のgs-speedup§6未更新が契機）。
- **後方伝播検証（assumption_invalidation）**: 忍者報告の `assumption_invalidation` 欄を確認せよ。
  - `found: true` → `affected_cmds` に列挙された過去cmdの前提を再検証する計画を将軍に報告。ntfy送信: `bash scripts/ntfy.sh "【家老】後方伝播検出: cmd_XXXX の前提が cmd_YYYY の結果により変更。再検証要"`
  - `found: false` → 家老自身が報告内容から後方影響を判断。見落としがあれば `karo_workaround_log.sh` に記録し、`assumption_invalidation.found` を `true` に修正してから次ステップへ進む。
  - **Why**: cmd結果が過去cmdの前提を変更した場合、その影響が検出されないとサイレント障害になる（螺旋原則: 前提変更時の後方伝播検証）。忍者が第一網、家老が第二網、gateが第三網の三重防御。
- **Workaroundログ記録（必須）**: 忍者報告の手動修正（報告YAML修正・コード手直し等）を行った場合、修正のたびに `karo_workaround_log.sh` を呼んで記録せよ。任意ではなく必須。修正パターンの蓄積により再発防止策（テンプレート改善・教訓追加）を導出する。
  ```
  修正実施後: bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> "<修正内容>" "<修正方法>"
  ```
### Workaround Pattern対処フロー

`karo_workaround_log.sh` でworkaround_patternが通知された場合の対処手順:

1. **推定根本原因を確認**: 修正ログの `fix_description` と `fix_method` から、原因がテンプレート / スクリプト / 手順書のいずれにあるかを特定
2. **根本原因に対する修正cmdを起案**: 教訓登録（忍者に教える）より、テンプレ・スクリプトの直接修正を優先。構造で問題を防げ
   - テンプレート起因 → テンプレートファイル修正cmd
   - スクリプト起因 → スクリプト修正cmd
   - 手順書起因 → instructions/*.md or karo-operations.md 修正cmd
3. **修正cmd配備後、workaround_pattern通知を「対処済み」に更新**: `karo_workaround_log.sh` の該当エントリに対処cmdを記録

**原則**: 「教訓で忍者に教える」より「テンプレを直して問題が発生しない構造にする」を優先。同じworkaroundを2回やったら構造が間違っている。

### Workaround Pattern → 軍師レビューヒント共有

`workaround_pattern_check.sh` がパターン検出した際、そのパターンを軍師にも `review_hint` として共有する。軍師がレビュー時にこのヒントを参照し、該当パターンを重点チェックすることで、同じ間違いの再発を水際で防ぐ。

**トリガー**: `karo_workaround_log.sh` 実行後に `workaround_pattern_check.sh` がパターンを検出した場合

**手順**: パターン検出時、以下のinbox_writeを実行して軍師にヒントを送信:
```bash
bash scripts/inbox_write.sh gunshi "レビューヒント: {パターン名}。忍者が頻繁に間違えるパターン。重点確認せよ" review_hint karo
```

- `{パターン名}` は `workaround_pattern_check.sh` が出力したパターン名に置換
- 軍師は受信した `review_hint` を次回以降のレビュー時に該当パターンを重点チェックする
- 複数パターンが同時検出された場合は、パターンごとに1通ずつ送信

### RC修正再検証フロー（verify_request/verify_result）

REQUEST_CHANGES修正完了後の再検証。severity判定→verify_request→軍師3問チェック→verify_result→完了/追加修正(max 3回)。
→ 手順詳細: `instructions/karo-procedures.md` §11

→ `docs/research/karo-operations-detail.md` §3

## §3.5 DCエスカレーション（裁定重複チェック必須）

- 忍者報告のdecision_candidateを将軍にエスカレーションする前に、**必ず`pending_decisions.yaml`の全resolved裁定と照合**せよ。
- 既存裁定と重複するDCは起票せず「PD-XXXで裁定済み」として忍者に差し戻す。
- **Why**: 殿に同じ裁定を二度求めることは禁止（2026-03-16殿厳命）。PD-007朱雀全滅許容を再質問した失敗が契機。
- **How to apply**: DC受領→pending_decisions.yaml全件スキャン→重複なし→将軍へエスカレーション。重複あり→差し戻し+既存裁定を引用。

## §4 難問エスカレーション

- 1名で失敗し、原因不明または複雑なら同一タスクを2名へ独立配備する。
- これは初回から2名投入する偵察とは別原則。失敗後の増員である。
→ `docs/research/karo-operations-detail.md` §4

## §5 教訓抽出

- cmd完了後は `lesson_review.sh` でdraftを確認し、confirm/edit/delete を完了してから GATE に進む。
- 一般論ではなく、再利用可能な具体知見だけを正式化する。
- strategic 教訓は MCP 昇格候補として扱う。
→ `docs/research/karo-operations-detail.md` §5

## §6 宣言・薄書き・書込み

- 分割宣言は配備前の遵守証跡。1名配備なら例外理由を必ず書く。
- task YAML は薄書きが原則。既知知識を重複転記するな。
- すべて Read-before-Write。inbox既読化は `inbox_mark_read.sh` を使う。
- **task YAML作成はBash tool(`cat`/`echo`)で書け**（Write/Edit直接はhookブロック）。配備は `deploy_task.sh <ninja> <cmd_id>` 経由。**cmd_id必須**(LK061)。
- **報告YAML操作は `report_field_set.sh` 経由**（Edit tool直接禁止=Lost Updateリスク）。
- **yqは環境に存在しない**。YAML操作ツール: `deploy_task.sh` / `report_field_set.sh` / `field_get.sh` / `yaml_field_set.sh`
→ `docs/research/karo-operations-detail.md` §6-7（YAML操作ツール詳細・コマンド書式あり）

## §7 配備前確認

- context圧縮前は `bash scripts/gates/gate_vercel_phase.sh {context_file}` を実行する。
- 初回配備や再配備失敗後は pre-deploy ping を必須にする。
→ `docs/research/karo-operations-detail.md` §8

## §8 通知・Frog・連勝

- cmd関連通知は `ntfy_cmd.sh`、それ以外は `ntfy.sh` を使い分ける。
- Frog は1日1件。cmd と VF task で競合する。
- **GATE実行前CI確認(LK-A01 v21)**: `gh run list --repo simokitafresh/multi-agent-shogun --workflow test.yml --limit 1` でCI状態確認。failure中はcmd_complete_gate.sh実行しない(ci_readiness BLOCKが確定しており再実行は負の複利)。CI修正完了→push→GREEN後にGATE実行。
- **done忍者のtask YAML手動idle化禁止(LK-A01 v22)**: stop hookのdone催促解消のためにtask YAMLをidle化するな。忍者が報告作成中のtask情報を喪失させる。done→idle遷移はGATE CLEAR→archive_completed.shの正規フローで自然解消される。
- cmd完了時は lesson review → cmd_complete_gate → GATE CLEAR → **cmd品質記録** → **status→completed** → archive の順を崩すな。
- **status→completed遷移**: GATE CLEAR確認後（全subtask done + gate CLEAR）、以下を実行してcmdのstatusをcompletedに遷移:
  ```
  bash scripts/lib/yaml_field_set.sh queue/shogun_to_karo.yaml "{cmd_id}" status completed
  ```
  これにより次回の `archive_completed.sh` 実行でアーカイブ対象になる。
- **workaroundログ記録（cmd完了時）**: cmd処理中にworkaround（忍者報告の手動修正・コード手直し等）を行った場合、cmd完了前に以下を実行:
  ```
  bash scripts/karo_workaround_log.sh <cmd_id> <ninja_name> "<修正内容>" "<修正方法>"
  ```
  ※ workaroundを行った場合のみ。行わなかった場合は不要。詳細は§3 Workaroundログ記録を参照。
- **cmd品質記録**: GATE CLEAR/FAIL後、以下を実行:
  ```
  bash scripts/cmd_quality_log.sh <cmd_id> <gate_result> <karo_rework:yes/no> <supplementary_cmds:数値>
  ```
  自動取得: gunshi_verdict(karo inbox), ninja_blockers(報告YAML), ac_count(shogun_to_karo.yaml)
→ `docs/research/karo-operations-detail.md` §9

## §9 配備制約

- 本番DB操作は直列配備。コード修正や文書編集だけを並列化する。
- idle忍者が2名以上いて独立タスクがあるなら並列化は義務。
- **偵察並列分割**: 同一cmdを複数忍者に配備する場合、deploy_task.shの重複ガードが発動する。1名目配備後にtask_idを`cmd_XXXX_scout_1`に変更し、2名目以降は手動yaml_field_setで`task_id/parent_cmd/status/purpose/scope_mode`を設定+inbox_write。GATEは全員完了後に統合実行。
- レポート走査は起動時ごとに全 `queue/reports/*_report_cmd_*.yaml` を見る。
→ `docs/research/karo-operations-detail.md` §10-12

## §10 偵察完了後の家老起案

- `scout_only` 完了後は、家老が偵察報告を分析して次cmdを直接起案できる。
- その際は `scout_exempt: true` と `based_on: cmd_XXX` を明記する。
→ `docs/research/karo-operations-detail.md` §13

## §11 モデル運用

- 現行方針はランダム配備。名前や旧階級制で割り振らない。
- CLI切替は `/clear` ではなく `switch_cli_mode.sh` を使う。
→ `docs/research/karo-operations-detail.md` §14-16

### モデル別適性（mixed編成修行R7-R12で実証 2026-04-02）

| モデル | 強み | 弱み | 配備ルール |
|--------|------|------|-----------|
| Opus 4.6 | テンプレート有無に関わらず安定(FP100%) | コスト高 | 設計判断・複雑レビュー・大型ファイル |
| Sonnet 4.6 | 中規模実装+テスト最適化(11倍達成) | bc AC構造を壊す傾向(FP0-50%) | bc構造維持ヒント必須。テンプレートのAC scaffoldを強化 |
| GPT-5.5(Codex) | テンプレートがあれば安定(FP100%)、定型作業高速 | テンプレートなしだとフィールド欠落(FP0%) | テンプレート必須。大型ファイルも処理可能(才蔵R13: 3985行スクリプトのテスト最適化24倍成功) |

### テスト最適化配備ルール（R11-R12で実証）

- **10倍目標**: Before 30秒超のテストのみ適用。5-10秒帯はbats固定コスト(0.5-0.7s)が支配的で物理的に不可能
- **代替目標**: 10秒未満→3倍を目標
- **パターン**: 巨大スクリプトフル実行→関数抽出→source→単体テスト化（48倍/69倍/13倍/11倍実証）
- 詳細: `context/training-cycle.md` §26、`docs/research/test-optimization-journal.md`

## §12 skill_candidate受領時の処理フロー

忍者の報告YAMLに `skill_candidate.found: true` がある場合の処理手順:

1. **収集**: 報告YAMLからskill_candidateの内容（name/description/reason/project）を確認
2. **dashboard記載**: dashboardの将軍宛報告セクション(🚨要対応)にスキル提案として記載
3. **将軍承認**: 将軍がスキル化の要否を判断。承認/却下/保留を裁定
4. **設計doc作成**: 承認後、家老がスキル設計（SKILL.md骨子・トリガー条件・入出力）をcmdとして起案
5. **実装cmd**: 設計完了後、スキル実装cmdを忍者に配備

- 忍者はスキルを実装しない。報告のみ。実装判断は家老→将軍承認の鎖に従う
- 複数の忍者から同一パターンのskill_candidateが上がった場合は優先度を上げる

## §13 gunshi_lesson_candidate受信時の処理フロー

軍師レビュー報告に `lesson_candidate` が含まれる場合の処理手順:

1. **重複チェック**: 既存教訓と重複していないか確認
   ```bash
   grep -i "<教訓キーワード>" projects/infra/lessons.yaml
   ```
   対象PJが infra 以外の場合は `projects/{project}/lessons.yaml` を検索。

2. **重複なし → 正式登録**: `lesson_write.sh` で教訓を登録（source: gunshi）
   ```bash
   bash scripts/lesson_write.sh infra "{title}" "{detail}" cmd_XXXX gunshi
   ```
   - `{title}`: 教訓タイトル（軍師報告から抽出）
   - `{detail}`: 具体的な知見（再利用可能な形に家老が要約）
   - `cmd_XXXX`: 元のcmd番号
   - 最後の引数 `gunshi` がsourceとして記録される

3. **重複あり → retagまたは補強**:
   - 既存教訓の `effectiveness` を確認
   - 軍師の指摘が既存教訓を強化する内容であれば、detail を補強
   - 同一内容であれば登録せず、既存教訓IDを軍師報告に紐付けるのみ

- **Why**: 軍師レビューで発見された知見を教訓基盤に還流し、忍者の品質を継続的に向上させるため
- **How to apply**: 軍師からの報告受信時（inbox type: gunshi_review等）にlesson_candidateフィールドの有無を確認。あれば本手順を実行

## §14 失敗ループ学習（retry_loop）

cmdに `retry_policy: retry_loop` がある場合、家老は以下のループ運用を行う。

### トリガー
将軍がcmdの `retry_policy` フィールドに `retry_loop` を含めた場合のみ発動。デフォルトではない。

### ループ手順（並列学習方式）
複数忍者を**異なるアプローチで同時配備**し、それぞれが独立にループする。
タイミングのズレにより、先に失敗した者の知見が後続全員に流れ、知見蓄積速度が並列数に比例して上がる。

1. 忍者N名を異なるアプローチで同時配備（`parallel_count` 指定、省略時1）
2. いずれかの忍者がFAIL → 報告YAMLを受領
3. 家老がFAIL報告を分析し、以下を判定:
   - **再試行可能**: 前回の失敗原因+**他忍者のFAIL知見も統合**してタスクYAMLに追記し、再配備
   - **人間必要**: reCAPTCHA突破不能、2FA要求、TOS制約等 → 該当忍者は停止。全員が人間必要なら**全ループ停止** → 殿にntfy報告
4. いずれかの忍者が**成功** → 他の忍者を全停止 → 通常のレビューフローへ

```
例: 3名並列ループ（タイミングズレが知見を加速）
T+0:  A1開始  B1開始  C1開始（異なるアプローチ）
T+5:  A1 FAIL → 知見α抽出
T+6:  A2開始（知見α反映）
T+7:  B1 FAIL → 知見β抽出
T+8:  B2開始（知見α+β反映）  ← Aの知見も吸収
T+9:  A2 FAIL → 知見γ抽出
T+10: C1 FAIL → 知見δ抽出
T+11: A3開始（α+β+γ+δ全統合） ← 全員の知見が集約
T+12: C2開始（α+β+γ+δ全統合）
...どこかで1名成功 → 全停止
```

### 知見の引き継ぎルール
- 各FAILの教訓を再配備時の `command` 欄に「■ 過去の試行結果」として埋め込む
- **自分の**過去FAILだけでなく、**他忍者の**FAILも含めて全知見を統合
- 家老が知見を要約・構造化して注入（丸コピー禁止、要点のみ）

### 家老の知見抽出品質（ループ空転防止）
ループの成否は**家老の分析力**に依存する。FAIL報告を受けたら以下を必ず行え:
- **過去成功時との差分特定**: 過去に同じ操作が成功した実績がある場合、「前回と今回で何が違うか」を特定し、次の忍者に伝えよ。差分が不明なら報告から読み取れる事実を全て列挙せよ
- **表層でなく構造を伝えよ**: 「reCAPTCHAが出た」ではなく「port 9222にtemp profileが起動し、既ログインセッションに接続できなかった。過去はEdgeが9222で動いていた」のように、なぜ失敗したかの構造を伝えよ
- **知見抽出が甘ければループは空転する**。3回同じ失敗を繰り返して終わるのは家老の責任

### 制限
- **max_retries: 3**（忍者1名あたり最大3回試行。cmdで上書き可）
- 全忍者が上限到達 → 全ループ停止 → `ntfy.sh` で殿にエスカレーション
- 「人間必要」判定は回数に関わらず即停止（該当忍者のみ。他は続行可）
- いずれか1名成功 → 他の全忍者を即停止（コスト制御）

### retry_policy フィールド仕様
```yaml
retry_policy: |
  retry_loop
  max_retries: 5        # 忍者1名あたり。省略時デフォルト3
  parallel_count: 3     # 同時配備数。省略時1（直列）
  assign_to_model: opus  # 省略時は通常配備ルール
```

## §7 idle時改善サイクル（殿厳命: 止まるな）

パイプライン空+全忍者idle = **改善サイクルを回す時間**。待つな。

### 優先順（上から順に消化）
1. `queue/insights.yaml` のstatus: pending → 分析+行動+resolve
2. `logs/karo_workarounds.yaml` 直近10件 → パターン分析→予防策設計(gate/hook/テンプレート)
3. `bash scripts/gates/gate_lesson_health.sh` → ALERT時は教訓整理
4. 忍者品質プロファイル（gate_karo_startup.sh出力の忍者別WA率）→ 高WA忍者の根因深掘り
5. deepdive再読 → 「自分の業務の何をgateにすべきか？」を1つ見つけて行動
6. 洗脳自己監査 → §0.1問い8の8パターンをyes/noで判定し、結果を `BULLETIN_NOTIFY=gunshi bash scripts/bulletin_write.sh karo "洗脳自己監査: ..."` で掲示板投稿→軍師第三者検証に回す

### サイクルの回し方
```
データを見る → 問いを見つける → なぜを掘る → 自動化ターゲット特定
→ 行動（直接修正 or insight記録 or cmd提案）→ 次のデータを見る
```
考えて進む、考えて進む。止まったらPhase 3を読め。

---

## 因果リンク

- ← [[infrastructure]] インフラを操作する手順
- ← [[deepdive_karo_verification_20260405]] 家老専用deepdive=運用品質の根拠
- → [[gunshi_idle_nazenaze_lgtm_block_20260516]] LGTM即BLOCKパターンのなぜなぜ分析
- → [[gunshi_idle_precheck_bottleneck_20260503]] precheckボトルネック: レビュー前確認の遅延原因
- → [[gunshi_idle_report_yaml_bottleneck_20260429]] 報告YAML処理のボトルネック分析
- → [[gunshi_idle_report_yaml_infra_bugs_20260424]] 報告YAMLインフラバグの分析
- → [[gunshi_idle_rfs_fill_bypass_20260429]] report_field_set.sh bypassパターンの検出
- → [[gunshi_idle_sg7_blind_spot_analysis_20260502]] SG7の盲点分析: 見えていないBLOCKパターン
- → [[gunshi_idle_side_effect_scan_20260504]] 副作用スキャン: 変更の波及リスク分析
- → [[gunshi_idle_side_effect_scan_cmd2593_2595_20260507]] cmd2593/2595の副作用スキャン
- → [[gunshi_idle_stale_ac_analysis_20260426]] 陳腐化AC: 配備済みcmdのAC不整合分析
- → [[gunshi_idle_stale_report_bugs_20260503]] 陳腐化報告バグ: 古いreportへの対処
- → [[gunshi_idle_target_path_nazenaze_20260520]] target_path省略によるスコープ逸脱のなぜなぜ
- → [[gunshi_idle_wa_arg_swap_20260428]] WA: 引数スワップパターンの根因分析
- → [[gunshi_idle_wa_data_quality_20260425]] WA: データ品質問題のワークアラウンドパターン
- → [[gunshi_idle_wa_immunity_20260415]] WA免疫: ワークアラウンドを防ぐgate設計
- → [[gunshi_idle_wa_lesson_candidate_20260415]] WAから教訓候補への変換プロセス
- → [[gunshi_idle_wa_pattern_20260612]] WAパターン分析(2026-06-12): 直近WAの根因分類と構造対策
- → [[gunshi_idle_wa_pattern_deep_20260425]] WAパターン深堀り: 構造的原因の抽出
- → [[gunshi_idle_wa_qm_pattern_20260413]] WA品質管理パターン
- → [[gunshi_idle_wa_timeseries_20260411]] WA時系列分析: 発生頻度の推移
- → [[gunshi_idle_wa_trend_20260408]] WAトレンド: 初期の傾向分析
- → [[cmd_498_karo-independent-assessment]] 家老独立評価(cmd_498)
- → [[gunshi_nazenaze_waive_ac_blind_spot_20260416]] AC棄却の盲点: なぜ確認をスキップするか
- → [[lessons_karo_v2_archive]] 家老教訓v2アーカイブ(旧バージョン教訓の履歴保管)
- → [[growth-loop]] 家老の第二層学習ループ(対)の実践

<!-- 軍師idle分析リンク(cmd_3278自動追記) -->
- [[gunshi_idle_lesson_impact_20260412]] — 軍師idle: 教訓インパクト分析(2026-04-12)
- [[gunshi_idle_lesson_dedup_20260413]] — 軍師idle: 教訓重複排除分析(2026-04-13)
- [[gunshi_idle_lesson_effectiveness_20260413]] — 軍師idle: 教訓有効性測定(2026-04-13)
- [[gunshi_idle_lesson_injection_dual_track_20260428]] — 軍師idle: 教訓注入デュアルトラック設計(2026-04-28)
- [[gunshi_idle_lesson_ref_rate_analysis_20260430]] — 軍師idle: 教訓参照率分析(2026-04-30)
- [[gunshi_idle_lesson_useful_rate_20260422]] — 軍師idle: 教訓有用率計測(2026-04-22)
- [[gunshi_idle_lesson_useful_rate_20260503]] — 軍師idle: 教訓有用率計測v2(2026-05-03)
- [[gunshi_idle_lesson_tag_mismatch_20260507]] — 軍師idle: 教訓タグ不一致分析(2026-05-07)
- [[gunshi_idle_insights_consumption_bottleneck_20260515]] — 軍師idle: インサイト消費ボトルネック分析(2026-05-15)
- [[gunshi_idle_lesson_waste_analysis_20260516]] — 軍師idle: 教訓無駄分析(2026-05-16)
- [[gunshi_idle_knowledge_burial_audit_20260505]] — 軍師idle: 知識埋没監査(2026-05-05)
- [[gunshi_idle_lesson_injection_universal_bypass_20260602]] — 軍師idle: 教訓注入汎用バイパス問題(2026-06-02)
- [[gunshi_idle_lesson_injection_quality_20260605]] — 軍師idle: 教訓注入品質監査(2026-06-05)
- [[gunshi_idle_lesson_useful_rate_20260608]] — 軍師idle: 教訓有用率計測v3(2026-06-08)
- [[gunshi_idle_bulletin_nazenaze_7_20260515]] — 軍師idle: 掲示板なぜなぜ#7分析(2026-05-15)
- [[gunshi_idle_lgtm_block_pattern_20260414]] — 軍師idle: LGTM BLOCKパターン分析(2026-04-14)
- [[gunshi_idle_cmd_quality_block_analysis_20260425]] — 軍師idle: cmd品質BLOCK分析(2026-04-25)
- → [[cmd-complete]] cmd完了処理（GATE CLEAR後の全ステップ自動化）
- → [[dashboard-update]] dashboard更新スキル（cmd完了後の一括更新）
- → [[lesson-sort]] 教訓振り分けスキル（draft教訓→正式登録）
- → [[repo-clean]] リポジトリ清掃スキル（孤立ファイル・古いブランチ整理）
- → [[shogun-pd-sync]] 未決裁定→context反映スキル（PD解決後の知識還流）
- → [[shogun-clear-prep]] /clear前準備スキル（状態確認+殿報告自動化）
- → [[shogun-teire]] 知識棚卸しスキル（8観点監査）
- → [[cdp-browse]] ブラウザ確認スキル（本番画面確認・CI RED後の画面検証）

## §15 ブラウザ確認（cdp-browse）

**家老もCDPを使え。** CI RED後の画面検証・本番FE確認に `/cdp-browse` スキルを使う。推測で画面状態を判断するな。

**使用場面:**
- CI RED後の画面検証: ページ表示崩れ・認証画面異常をブラウザで確認する時
- 本番FE確認: 忍者の修正後に実際の画面をブラウザで確認する時
- スクリーンショットが判断の一次情報になる時（§0.1問い2「現物確認」の手段）

```bash
# CDP daemonのヘルスチェック（自動起動される）
scripts/cdp/cdp_cli.sh healthz
# URL遷移
scripts/cdp/cdp_cli.sh navigate "https://example.com"
# スクリーンショット保存（一次情報として報告に添付）
scripts/cdp/cdp_cli.sh screenshot "/tmp/confirm.png"
```

CDPポート未応答でも止まるな。`preflight_cdp_flow` が自動起動する。
詳細手順 → `skills/cdp-browse/SKILL.md`
- → [[recon-dual]] 偵察2名並列配備スキル（recon2タスクタイプの標準配備）
