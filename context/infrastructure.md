# インフラコンテキスト
<!-- last_updated: 2026-06-29 cmd_karo_hotfix_ga150 -->

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。
> 詳細: `docs/research/infra-details.md`
> CoDDリファクタリング台帳: `docs/research/codd_refactor_registry.md`
> report_field_set as-is: `docs/research/report_field_set_after_20260416.md`
> inbox_write高速化(as-is): `docs/research/inbox_write_after_20260416.md`

## コンテキスト管理

全て外部インフラが自動処理。エージェントは何もするな。Codex忍者=/new、Claude忍者=/clear、家老=/clear(陣形図付き)、将軍=殿判断。
閾値: ソフト50%（外部トリガー）、ハード90%（AUTOCOMPACT）。CLI差異は`config/settings.yaml`参照。
→ `docs/research/infra-details.md` §1

## lord_conversation / 記憶DBデータフロー（cmd_2963〜cmd_3032）

殿との対話はlive JSONL → アーカイブ → SQLite記憶DBの三層で保持する。一次データは`queue/lord_conversation.jsonl`、24h超過/200件超過分は`logs/lord_conversation_archive/*.jsonl`へ退避、検索・概念到達は`data/multi_agent_shogun_memory.db`を使う。

| 層 | 正本/実装 | 役割 | 注意 |
|----|-----------|------|------|
| live | `queue/lord_conversation.jsonl` / `lib/lord_conversation.sh` | 直近対話を原子追記。terminal/ntfy response、terminal inboundを記録 | 消費者はtarget/agentで絞る。全inbound直読み禁止 |
| retention | `scripts/conversation_retention.sh` / `context/lord-conversation-index.md` | liveを24h/200件に保ち、古い行を`logs/lord_conversation_archive/`へ追記退避 | アーカイブが一次データ。DBだけに飛びつくな |
| batch DB | `scripts/memory_db_import.py` | archive/live/掲示板/report/insight/document等を`events`へ再構築 | `/clear`時再構築。WAL+INSERT OR REPLACE |
| live DB | `scripts/memory_db_live_insert.py` + 各writer | inbox/report/cmd_quality等をリアルタイムINSERT | 失敗しても正本YAML/JSONL成功を優先 |
| query | `scripts/memory_db_query.sh` / `scripts/semantic_search.sh` | SELECT-only SQL、FTS5 fallback、semantic検索補助 | destructive SQLは禁止 |

記憶DB構造: DB pathは`data/multi_agent_shogun_memory.db`。主表は`events(id, ts, event_type, agent, target, direction, summary, detail, session_id, cmd_id, concepts, source_file, parent_event_id, importance)`、全文検索はFTS5仮想表`events_fts(summary, detail)`、概念正規化は`event_concepts(event_id, concept_name)`、因果/Obsidianリンクは`event_links(source_event_id, target_concept, link_type)`。会話ビュー`conversations`は`events`由来。
→ `context/memory-db-schema.md` / `context/memory-db-queries.md` / `context/lord-conversation-index.md`

三層記憶新機能: `update_event_state`でstate遷移を記録し、`memory_recall_control.sh`で想起制御、`obsidian_promote_candidate.sh`でObsidian昇格候補、`append_contradiction_candidate`で矛盾検出候補を扱う。
→ `docs/research/three-layer-memory-l0-l7-penetration-design_20260604.md` §3 / `scripts/memory_db_live_insert.py` / `scripts/memory_recall_control.sh` / `scripts/obsidian_promote_candidate.sh`

### 三層記憶×学習ループ接続（cmd_3116〜cmd_3128, 2026-06-02）

殿指示で家老×軍師協議→穴分析→13cmd一気通貫で三層記憶の概念空間を接続。
操作的オントロジー原則（殿裁定2026-06-20）: オントロジーは分類表ではなく自動実行されて初めて効果が出る。概念定義・alias・因果リンクは、`semantic_search.sh`、task文脈注入、gate、startup、配備/レビュー/完了フローなどの自動経路に乗って再利用されることを完了条件にする。因果: [[殿裁定20260620_オントロジー自動実行]] -> [[分類表だけでは再利用されない]] -> [[semantic_search_task注入_gate_startup配備フローへ接続]]
操作的オントロジー復帰時判断（2026-06-20 家老・軍師相談済み）:
- `SKILL.md`全28本のロール制限削除は却下済み。09:10の軍師投稿は09:11に「編成系スキル(shogun-cli-switch)のみ」と撤回済み。全スキル削除は殿裁定の拡大解釈。通常はロール制限を維持し、殿の直接指示だけAGENTSの上位ルールで優先する。
- `shogun-cli-switch --force(active無視)`は通常機能にしない。現行正本はactive/in_progressをskipし設定だけ反映する設計。busy paneのrespawnは未完了作業・報告YAML・CTX破壊リスクが高い。緊急時に作るならemergency専用、事前capture/snapshot、対象pane列挙、dry-run、post復帰確認を必須にする。
- PJパス直書き修正は即起票可能。一次計測で実行系19ファイルに`/mnt/c/Python_app/DM-signal`または`/mnt/c/Python_app/auto-ops`直書きあり。`scripts/lib/project_path.sh`は存在し、`config/projects.yaml`には`auto-ops`登録済みなので「auto-ops登録前提」は古い。登録済みSSOTを使って再計測→変数代入型から置換→インライン/テスト個別判断→Guard16にPJパス概念追加。
- SSOT正本保護は`config/*.yaml`全体BLOCKではなくフィールド単位の保護表で設計する。例: `config/projects.yaml:projects[].path`はproject登録系/`project_path.sh`、`config/cli_profiles.yaml:profiles.*.launch_cmd`は`shogun-cli-switch`/`cli_lookup.sh`、`config/settings.yaml:cli.agents.*`は`shogun-cli-switch`経由。全封鎖は家老の正当運用を詰まらせる。
- `.yaml`/`.md`へのGuard16拡張は一律禁止。SSOT正本・docs/research・archiveにはliteralが正当に存在するためFPが増える。対象はinstructions/generatedやscripts配下の運用yamlなどに限定し、正本ファイルは別ゲートで守る。
- **cmd_3116**: live_insert概念付与(速度2.3ms/一致率100%)
- **cmd_3117**: テキスト品質改善(report充填3/10→10/10)
- **cmd_3118**: 歴史データbackfill(31636件→11531件更新)
- **cmd_3119**: event_concepts→教訓注入boost接続(deploy_task.shが概念横断で教訓候補を動的発見)
- **cmd_3121**: 教訓注入偽陽性71.2%→22.7%根治
- 概念充填率: report 0.4%→49%、lesson 2%→68.6%、gate 0%→97.8%、WA 0%→96.2%

## 直近改善（cmd_181〜cmd_541）

初期インフラ整備+教訓サイクル構築。acknowledged status(181), ペイン消失検知(183), inbox re-nudge(188/189/191), grep -cバグ(192), 裁定伝播遅延検出(PD-016), 知識鮮度警告(PD-017), dashboard_update(337), auto_deploy_next(338), ゲート迂回防止(339), 教訓タグ注入(348/349/350/351), 量→質転換(531), CMD年代記(544)
→ `docs/research/infra-details.md` §2, 各スクリプト: `scripts/` 配下

## 直近改善（cmd_602〜cmd_612）

review品質機械検査(607), ntfy_listener dual watchdog(609), lesson_impact feedback修復(611), 旧terminology一掃(612)
→ `context/cmd-chronicle.md` 03-06 / `scripts/` + `config/settings.yaml`

## 直近改善（cmd_875〜cmd_878）

gstack Tier1-2取込(875/876): 忍者プロンプト強化+家老Two-pass Review+Gate [CRITICAL]/[INFO]分離。CDP daemon化(877): persistent WebSocket+@ref体系。教訓同期修復(878): 淘汰カウント精度向上
→ `docs/research/gstack-analysis.md` (v0.0.2, 2026-03-13)

**GStack v1.11 + GBrain v0.19 + Skillify全分析(2026-04-25更新)**: gstack 6→23スキル、GBrain新登場(29スキル+21cron+17888ページ本番稼働)、Skillify(失敗→永続スキル化10ステップ, 766k views)。将軍の独自強み: 鎖/追体験/なぜなぜ/PI。取り込み候補: check-resolvable(スキル到達可能性)+routing-eval(intent→skillテスト)+ハイブリッド検索(Vector+BM25+Graph)。Minions(決定論的$0実行)=将軍のbashスクリプト群と同設計思想
→ `docs/research/gstack-gbrain-skillify-2026-04.md`

## 直近改善（cmd_1039〜cmd_1120）

| cmd | 改善 | 結論 |
|-----|------|------|
| 1039/1040 | **ninja_monitor三段階/clear** | Stage 1: YAML確認→Stage 2: 再確認→Stage 3: /clear。作業中(acknowledged/in_progress)忍者の誤/clear防止 |
| 1044 | **Read追跡hook** | Write/Edit前の未Readファイルを自動ブロック。Read前Write問題を根本解決 |
| 1053 | **ac_versionハッシュ化** | ACテキスト内容のハッシュでバージョン管理。AC内容差替えを確実に検知 |
| 1054 | **cmd_absorb.sh abort機能** | cmd吸収時に旧cmdで稼働中の忍者を即/clearし無駄な作業時間を防止 |
| 1065 | **タスクYAML hook強制** | queue/tasks/*.yamlへのWrite/Editを無条件deny。deploy_task.sh経由のみ許可 |
| 1067 | **報告YAML hook強制** | queue/reports/*.yamlへのWrite/Editを無条件deny。report_field_set.sh経由のみ許可 |
| 1111 | **家老教訓自動ロード** | /clear Recovery手順にlessons_karo.yaml読込を追加。家老の教訓参照漏れ防止 |
| 1113 | **gate穴検出3問トリガー** | GATE CLEAR時にgate_improvement_trigger.sh自動発火。3問で防御層の穴を検出 |
| 1117 | **hook失敗自動記録+穴検出3問** | 報告テンプレートにhook_failures欄追加。hook失敗→穴検出3問を自動連鎖 |
| 1118 | ラルフループ効果検証 | 学習ループ(clear→知識基盤残存→穴検出→防御層強化)の定量検証スクリプト |
| 1119/1120 | **自動トリム機構** | cmd-chronicle.md(200行)+shogun_to_karo.yaml(50件)をarchive_completed.shで自動トリム |

→ 完了履歴: `context/cmd-chronicle.md` 03-18〜03-20

> **思考の起源（経験的知識。圧縮禁止。過程が本体）**:
> - 免疫系/ラルフループ/自動化×強制の到達過程 → `memory/deepdive_why_chain_20260321.md`
> - System 1(gate自動)/System 2(なぜなぜ検証)の二重ループ → `memory/dialogue_heuristics_system2_20260401.md`
> - 第二層学習ループ（軍師↔家老還流） → `memory/dialogue_second_layer_20260321.md`

## 直近改善（cmd_3300〜GA-050）

CDP production checkはdeploy証跡が必要な場合だけ実行する。readonly ref回帰テストはself-contained化済み。context鮮度gateは10秒cacheを持つため、調査時は `CONTEXT_FRESHNESS_GATE_DISABLE_CACHE=1` で一次判定を取る。
→ `scripts/cmd_complete_gate.sh` / `scripts/gates/gate_gunshi_report_precheck.sh` / `tests/unit/test_cmd_complete_gate.bats` / `tests/unit/test_sg_pre25_readonly_ref.bats`

## 軍師品質管理ユニット（cmd_1144〜cmd_1181）

家老+軍師=品質管理ユニット化。軍師が一次レビュー→LGTM→家老スタンプのみ/FAIL→家老介入。

| cmd | 改善 | 結論 |
|-----|------|------|
| 1162 | **忍者報告一次レビュー委譲** | 軍師が忍者報告の一次レビューを担当（report_review）。家老のレビュー負荷消滅→配備+教訓に専念 |
| 1174 | **GSD式6観点+5段階プロトコル** | 軍師レビュー基準体系化: 前提検証/数値再計算/時系列シミュレーション/事前検死/確信度ラベル/North Star整合 |
| 1181 | **git show HEAD検証+証拠必須化** | ドラフトレビュー前提検証でgit show HEAD使用+証拠添付必須。未commit変更の既実装誤判定防止 |

→ `instructions/gunshi.md` §Review Criteria / §5段階思考プロトコル / §Report Review
- L271: gunshi_accuracy_log.sh未作成 — 軍師accuracy計測スクリプト欠落（cmd_1158）
- L281: 軍師基準設計は実例駆動で内面化する（cmd_1174）

## 偵察デフォルト品質5要件（cmd_754+cmd_1476）

偵察は現象特定で止めるな。以下5要件をデフォルト品質として自動化×強制:
1. 変更対象ファイル・行番号
2. 波及先ファイル
3. 関連テスト有無・修正要否
4. エッジケース・副作用
5. **依存関係・順序制約**(flush順序・キャッシュ共有・ネスト読み書き等) ← cmd_1476追加

テンプレート(deploy_task.sh)+ゲートWARN(cmd_design_quality.yaml)で強制。cmd_754で4要件導入、cmd_1476で第5要件追加(DC裁定)。
→ `instructions/ashigaru.md` 偵察テンプレート / `logs/cmd_design_quality.yaml` q4_depth

## 直近改善（cmd_1532〜cmd_1543）

CLEAR率62.7%→84.6%(+21.9pt)。gate品質BLOCK3大原因の構造的解消+新gate2本+autofix拡張+WA記録品質強制。

| cmd | 改善 | 結論 |
|-----|------|------|
| 1532 | **unknown_block_reason修正** | BLOCK_REASONS/MISSING_GATES両方空のelse分岐で個別gate結果を含めるよう修正。直近50BLOCKの17.7%(11件)のRCA不能状態解消 |
| 1533 | **report template FIX hint追加** | Top5 BLOCKパターン(lesson_candidate/binary_checks等)の具体的FIXコマンド例をテンプレートコメントに追記 |
| 1534 | **BLOCKパターン忍者注入** | deploy_task.shにgate_metrics.logのBLOCK集計を追加。忍者別頻出BLOCK原因をtask YAMLのninja_weak_points.gate_blocksに自動注入 |
| 1535 | **autofix 3新パターン(B/C/混合キー)** | lessons_useful dict→list変換にPattern B({0:{},1:{}})/C(混合キー)/混合パターンを網羅追加。WA率Top1のreport_yaml_format 16件対策 |
| 1536 | **report YAML直接編集hookブロック** | PreToolUse hookでreport YAMLへの直接Edit/Writeを検知→ブロック。report_field_set.sh使用を構造的に強制 |
| 1537 | **typeフィールドSTALE_FIELDS追加** | deploy_task.shのSTALE_FIELDS+_CLEAR_FIELDSにtype追加。前cmdからの残留値持ち越しバグ修正 |
| 1538 | **WA記録category必須化+WARN** | karo_workaround_log.shにcategory空チェック+root_cause空チェック追加。uncategorized急増(1→16件)対策 |
| 1539 | **q7_branch_coverage新設** | cmd_save.shに本番分岐カバレッジチェック追加。条件分岐変更cmdで本番データ確認ACをWARN提案 |
| 1541 | **q11_post_deploy新設** | cmd_save.shにpost-deploy検証チェック追加。本番コード変更cmdにデプロイ後検証ACがない場合WARN |
| 1540 | **fullrecalculate baseline自動保存** | 実行前baseline自動保存+実行後差分サマリ出力。変更の正当性を数値証明 |
| 1542 | **WA記録バリデーション強化** | karo_workaround_log.shにninja_id有効性チェック+root_cause最小長(3文字)+null値拒否を追加 |
| 1543 | **計測検証** | CLEAR率62.7%→84.6%(+21.9pt)を実測。学習ループ完結 |

→ 完了履歴: `context/cmd-chronicle.md` 03-30 / `scripts/cmd_save.sh` / `scripts/cmd_complete_gate.sh` / `scripts/deploy_task.sh` / `scripts/karo_workaround_log.sh`

## 直近改善（2026-04-16〜2026-04-30 CoDD波 / GP-198〜240）

| 領域 | 結論 | 参照 |
|------|------|------|
| cmd_publish pre-flight | `cmd_publish.sh` のPython YAML parseをawk block scanへ置換し、`grep -c || echo 0` の0件二重出力を防止。CoDD生成物はwave1-3まで保存、最終計測はafter設計書を正とする | `docs/research/cmd_2585_cmd_publish_after_20260506.md`, `docs/research/codd_refactor_registry.md` |
| CoDD改善32本 | cmd_1951の全量プロファイリングを起点にhot path 32本を改善。代表値: `cmd_save.sh 4.02s→1.06s (-73.6%)`, `deploy_task.sh 2639ms→32ms`, `gate_karo_startup.sh 464ms→190ms` | `docs/research/codd_refactor_registry.md`, `context/cmd-chronicle.md` 04-16 |
| GP-198/201 Session State | gate FAIL時の失敗履歴をtask再配備へ注入し、`cmd_save.sh` 側でもDiagnose MANDATORY+Session Stateを強制。/newや再配備を跨いでL3診断を保持 | `context/codd.md` §4, `context/cmd-chronicle.md` `cmd_karo_gp198`/`cmd_1939` |
| GP-199 退化計測 | GP/改善cmdの報告に `before_metrics` / `after_metrics` / `regression` をWARNで強制し、速度改善が退化を隠さない形に変更 | `scripts/gates/gate_report_format.sh`, `context/cmd-chronicle.md` `cmd_1941` |
| GP-202 成果物プレフィックス検査 | `files_modified` に `parent_cmd` プレフィックスが無い場合WARN。cmd_1948事故系の「別cmd成果物上書き」をゲートで検知 | `scripts/gates/gate_report_format.sh`, `tests/unit/test_report_template_gate_compat.bats` |
| GP-204/208 運用耐障害 | `daemon_watchdog.sh` は `set -e` / 二重flockを外して部分失敗で全体停止しない形に修正。`bulletin_write.sh` は掲示板通知を80文字要約でなく全文inbox配信へ変更 | `scripts/daemon_watchdog.sh`, `scripts/bulletin_write.sh` |
| cmd_3577 掲示板action_required追跡 | 軍師の穴発見/改善提案投稿を`action_required`へ自動昇格し、`gate_karo_startup.sh`が`actioned_by`空の未対応掲示板をWARN表示する | `scripts/bulletin_write.sh`, `scripts/gates/gate_karo_startup.sh`, `tests/unit/test_bulletin_board.bats`, `tests/unit/test_gate_karo_startup.bats` |
| f171a817 | `ninja_monitor.sh` のtask `completed_at` 更新をPython全体再出力から `yaml_field_set.sh` へ置換し、運用YAML破壊リスクを除去 | `scripts/ninja_monitor.sh` |
| 1603b5d2 | `inbox_write.sh` のinbox初期化をflock内へ移動し、同時配信時の初期化競合を防止 | `scripts/inbox_write.sh` |
| b7cf7fba | gate群のtask status検出をflat/nested両YAML形式対応へ拡張 | `scripts/gates/*` |
| 6ccea588 | `cmd_complete_gate.sh` 内Python blockをflat task YAML対応に修正 | `scripts/cmd_complete_gate.sh` |
| 2ade4e4e | stale `inotifywait` を親プロセス生存確認で除外し、旧watcherの誤nudgeを防止 | `scripts/inbox_watcher.sh` |
| 8b7f28b3 | `deploy_task.sh` のstale archiveが稼働中peer reportを退避しないよう保護 | `scripts/deploy_task.sh` |
| 64ec3aa5 | karo_direct cmdでもtask YAMLから `scout_exempt` を読むよう修正 | `scripts/deploy_task.sh` |
| 6275f18b | Guard7のread_log不在をCodex互換のためBLOCKからWARNへ降格 | `scripts/hooks/*` |
| 2043181f | 軍師SG-PRE3bで忍者手動記入commit hashの実在検証を追加 | `scripts/gunshi*` |
| 7018b629 | 軍師cs_checklist検出を値付き行にも対応させ、チェックリスト見落としを防止 | `scripts/gunshi*` |
| b079eb73 | `ac_physical_verify` にプロジェクトリポジトリfallback検索を追加し、外部PJ参照の実在確認を強化 | `scripts/ac_physical_verify.sh` |
| d26d6ac6 | `inbox_write.sh` がarchive移動済み報告YAMLをfallback検索できるよう修正 | `scripts/inbox_write.sh` |
| 7513b8da | `inbox_watcher.sh` のCodexナッジ再読指示を `task_assigned` 時のみに限定 | `scripts/inbox_watcher.sh` |

## deploy_task.sh --direct mode（cmd_1672）

deploy_task.shにdirect mode(`--direct`)追加。修行タスク等shogun_to_karo.yaml不在のタスク配備時に、report template生成+stale cleanup+教訓注入を実行可能に。GP-138実装。
使用法: `bash scripts/deploy_task.sh --direct <ninja> <task_id>`
→ `scripts/deploy_task.sh` L31(フラグ解析), L2935(DIRECT_MODE分岐)

## /henseiスキル（cmd_1673）

モデル編成一括切替スキル。`~/.claude/skills/hensei/SKILL.md` + `~/.claude/skills/hensei/scripts/hensei_apply.sh`。
プリセット: `opus-all`(全忍者Opus統一), `mixed`(GPT2+Sonnet2+Opus2混成)。
idle安全機構: in_progress/acknowledged忍者のCLI操作スキップ(settings.yaml更新のみ→次回clear反映)。
⚠ **dry-run未実装(L431)**: テスト時にmodel_switchが本番送信される。テスト時注意。
→ `~/.claude/skills/hensei/`

## Claude CLIモデル指定とコンテキスト（ci_fix_200k）

| 起動方法 | コンテキスト | effort | コスト |
|----------|-------------|--------|--------|
| `claude`(デフォルト、--modelなし) | **1M** | Max利用可 | 1x |
| `claude --model opus` | 200K | Highまで | 1x |
| `claude --model sonnet` | 200K | — | 0.2x |

**修正(b3f55d9)**: `build_cli_command()`でopus時は`--model`スキップ → デフォルト1M起動。sonnet/haikuのみ`--model`指定。
**殿裁定**: high effortで十分(Max=3-10xコスト、レートリミットリスク)。
**モデル切替はrespawn方式**(殿裁定): `/model`コマンドではなくCLI再起動(respawn)が正しい手順。理由: (1)/model opusは200Kになる (2)claude↔codexは/modelで切替不可 (3)respawnならCLAUDE.md/instructions再読込が保証される。/henseiスキルもrespawn方式に再設計要。
**CLI種別がモデルファミリーを決定（殿指摘2026-06-21）**:
| CLI | モデルファミリー | effort指定 | fast指定 |
|-----|-----------------|-----------|---------|
| Claude CLI (`~/bin/claude`) | Claude系(Opus/Sonnet/Haiku) | `--effort low\|medium\|high` | `/fast`トグル |
| Codex CLI (`codex`) | GPT系(gpt-5.5等) | `config.toml model_reasoning_effort` | `config.toml service_tier=fast` |

**GPT-5.5を使うにはCodex CLIが必要**。Claude CLIで`--model gpt-5.5`を指定しても表示が変わるだけで実際のモデルはClaude系のまま。
**settings.yamlのmodel_nameは表示メタデータ**。CLIの実行モデルを決定しない。実モデルはCLI種別+起動設定で決まる。
**anti-pattern（殿指摘）**: 動いているCLIに`/model`コマンドを送る、settings.yamlだけ変更する、は全て失敗する。正道=paneを殺す→正しいCLI+設定で起動。
**Codex exit 2根因（2026-06-21解決）**: Claude CLIのターミナル設定がrespawn-pane -k後も残留→Codexが不正ターミナル状態で起動→exit 2。対策=switch_cli_mode.shがrespawn前に`reset`実行+cooldown 5秒。双方向6連続100%成功で検証済み。
**codex CLI**: デフォルト272K。1Mには`~/.codex/config.toml`に`model_context_window=1000000`+`model_auto_compact_token_limit=900000`必要。デフォルトモデル=gpt-5.5(旧gpt-5は廃止名)。effort=config.tomlの`model_reasoning_effort`。
→ `lib/cli_adapter.sh` L88 | 詳細: `docs/research/gunshi-cli-model-context.md`（respawn手順/セレクタの罠/effort優先順位/codex config設定方法）

### Codex multi-CLI統合(2026-05-11確立)

**2026-06-24上書き原則**: CLI固有hook設定(`.claude/settings.json` / `.codex/hooks.json`)を安全網の正本にするな。正本は共通イベント層(`config/cli_events.yaml`)とし、同一実装の押し付けではなくCLI能力に合わせたadapterへ落とす。Codex最新版は`SessionStart`/`UserPromptSubmit`/`Stop`を公式サポートするが、Codex同一event hookは並行実行されるため、順序依存処理は単一adapterに合成する。Codex Stop block系は旧事故があるため未検証のまま戻さず、daemon/gate/scriptで等価保証する。詳細設計: `docs/research/multi-cli-hook-event-commonization-design_20260602.md`。因果: [[multi_cli_hook_gap]] -> [[codex_stop_block_loop]] -> [[cli_capability_adapter_required]]。

**因果確認L0-L7**: hook/gate/daemon/semantic/search等を変更する前に、git log/blame、教訓、設計書、semantic/causal linksで「なぜ現在の実装がそうなっているか」を確認する。multi-CLI前提のため、因果確認の強制もClaude/Codex固有hookではなく、`cmd_save.sh`、`deploy_task.sh`、`gate_report_format.sh`、task/report YAML、memory DB、semantic index、daemon/gateを正本にする。詳細: `docs/research/causal-verification-l0-l7-design_20260602.md`。因果: [[semantic_search_timeout_infra_bug]] -> [[past_design_intent_unchecked_risk]] -> [[causal_verification_l0_l7_required]]。

**hook速度偵察(cmd_3189)**: Bash no-op実測はPre 90.8ms(2 forks)+Post 76.8ms(3 forks)=167.6ms/呼出し。設計方針は品質チェック削除ではなくdispatcher統合で、PreToolUse 6設定→`pretool-dispatch.sh`、PostToolUse 4設定→`posttool-dispatch.sh`へ寄せ、95-115ms/呼出しを目標にする。実装時の必須リスク確認: permissionDecision出力順序、不要tool dispatch、Read→Write順序、DM-Signal PI混入、Claude/Codex設定差分。

| 項目 | 設定 | 正本 |
|------|------|------|
| config | `~/.codex/config.toml` | `project_doc_max_bytes=131072`(87KB超対応)。`[features] hooks=true`必須(`codex_hooks`は非推奨) |
| hooks | `.codex/hooks.json`(プロジェクトレベル) | Codex公式hookをCLI能力adapterとして使う。`SessionStart`→`scripts/hooks/codex_session_start.sh`、`UserPromptSubmit`→`scripts/hooks/codex_user_prompt_submit.sh`。Codexは同一event内hookを並行実行するため、`log_terminal_input.sh`と`prompt_state_inject.sh`を別hookに分けるな。Stop block系は未検証のため戻さずdaemon補完 |
| hook BLOCK | `emit_deny()`内で**exit 2** | exit 1=hookエラー(CLIクラッシュ)。exit 2=意図的BLOCK(CLI続行)。Claude Codeはexit 1でも続行するがCodexは死ぬ |
| hook承認 | 初回のみ`/hooks`でtrust操作 | 承認は永続化(respawn後も再承認不要)。pane高さ15行だとStop行が画面外 — 一時拡大(`tmux resize-pane -y 30`)で承認 |
| skills | `~/.codex/skills/` → プロジェクト正本symlink | 独立コピー禁止。`ln -s /mnt/c/tools/multi-agent-shogun/skills/{name}`でsymlink。skill_auto_improve.shの改善が即反映 |
| Skill tool | Codex CLIは`/skills`コマンドでスキル一覧表示・実行可能 | Claude CodeのSkill toolと同等機能 |
| doc読込制限 | `project_doc_max_bytes` | AGENTS.md+CLAUDE.md合計が制限超→切り捨て。128KB以上を推奨 |
| セッションリセット | `/new`(セッション新規) | config.toml変更反映にはCLI再起動(respawn-pane)が必要。`/new`ではconfig再読込されない |
| **Stop hook** | `{"decision":"block"}`の挙動差異 | **Claude Code**: メッセージ表示+ターン停止。**Codex**: reason文をプロンプトとして再実行=**無限ループ**。忍者done/completed時はblockせずidle flag+exit 0。quoting脆弱性検証→ [[cmd_1755_stop_hook]] (`docs/research/cmd_1755_stop_hook.md`) |
| **launch_cmd** | `cli_profiles.yaml` | Codexは**絶対パス必須**(`/home/.../bin/codex`)。respawn-paneは.bashrc未読込→nvm PATHなし→`codex: command not found` |
| **respawn方式** | `ninja_monitor.sh safe_send_clear()` | Codex再起動は`tmux respawn-pane -k`方式。Ctrl-C方式はcodex=PID 1終了→pane dead→relaunch届かない |
| **利用量モニタリング** | `usage_monitor.sh` + `usage_status.sh` | upstream ratelimit_check.sh(tmux capture方式)との比較→SQLite直接集計方式が安定。[[cmd_1756_ratelimit]] (`docs/research/cmd_1756_ratelimit.md`) |
| **Codex idle時も respawn-pane -k 必須** | 設計意図(殿裁定2026-05-20) | `/new`はCodex CLI内部状態が「task in progress」だと拒否される。ninja_monitorがidle判定しても、CLI内部はsession activeのまま→`/new`非互換。respawn-pane -kはCLI内部状態に関係なくpaneプロセスを殺して再起動するため唯一確実なリセット手段。cmd_2904/2906で/new経路に変更→3忍者CTX滞留(51%/55%/43%)で実証。一見乱暴だが理由がある設計。198回/日ループの真因は発火条件(デバウンス/idle判定頻度)側であり、respawn手段を変えるべきではない。因果: [[cmd_2904_overfix]] -> [[codex_new_rejected]] -> [[respawn_is_correct_design]]。カタログ: `docs/research/gunshi_idle_infra_design_intent_catalog_20260520.md` |

### 直近24日間の主要裁定/実装（2026-05-01〜2026-05-24）

| 領域 | 結論 | 根拠 |
|------|------|------|
| Codex reset | Codex idle時も`tmux respawn-pane -k`必須。`/new`経路へ戻すな | cmd_2904/2906/2907、殿裁定2026-05-20 |
| 記憶DB | lord_conversationはJSONL/アーカイブを一次データ、SQLiteを検索層として扱う | cmd_2963〜2982、cmd_3001/3002 |
| target filter | 殿発言検索は`direction=inbound`の前にtarget/agentスコープを必ず確認 | cmd_3008/3009/3017/3028、L689/L698 |
| CI並列隔離 | 並列Bats/CIでは共有状態を4系統で隔離: (1) per-test `TEST_TMPDIR`、(2) lock/cacheをTMPDIR配下、(3) script_dir基準の絶対パス、(4) repo内scriptはgit実行権限または`bash script.sh`呼出 | cmd_2663/2975、L477/L488/L535/L536/L690/L691/L694 |
| 新スクリプトCI | 新規script追加時はscript_dir絶対パス、git mode 100755またはbash経由テスト、既存実行パターン踏襲の3点確認 | `logs/archive/gunshi_review_log_20260524a.yaml` の `idle_ci_red_chain_new_script_20260523` |

## Claude Code バージョン固定と復帰

現在v2.1.87に固定。`config/cli_profiles.yaml`の`launch_cmd`が正本。

| 操作 | launch_cmd | 備考 |
|------|-----------|------|
| **v2.1.87固定** | `/home/simokitafresh/bin/claude --dangerously-skip-permissions` | 現在の状態 |
| **auto-update復帰** | `/home/simokitafresh/.local/bin/claude --dangerously-skip-permissions` | updater管理symlink |

切替手順(全体): launch_cmd変更 → `bash scripts/switch_cli_mode.sh claude --scope shogun,karo,gunshi,kagemaru,hanzo,kotaro,tobisaru` でrespawn。backup3本(`~/bin/claude`, `claude.pinned`, `claude-2.1.87-stable`)で復元可能。
切替手順(pane単位): `bash skills/shogun-cli-switch/scripts/shogun_cli_switch.sh unpin-latest --agent hayate` で特定paneだけ最新版。`pin-2.1.87 --agent hayate` でピン止めに戻す。settings.yamlの個別launch_cmdをcli_lookup.shがオーバーライド。
→ `docs/research/claude-code-version-runbook.md`（全手順+緊急ロールバック+復元方法）
→ `skills/shogun-cli-switch/SKILL.md`（スキル詳細）

## 忍者個別弱点自動注入（cmd_1307）

deploy_task.shにinject_ninja_weak_points関数追加。karo_workarounds.yamlから忍者名でフィルタし、workaround:trueのcategory別件数をtask YAMLのninja_weak_pointsセクションに自動注入。0件忍者には注入しない。
→ `scripts/deploy_task.sh` L2038

## gate強化（cmd_1178〜cmd_1180）

cmd_1173偵察で特定した高優先gate未実装項目の構造的実装。

| cmd | 改善 | 結論 |
|-----|------|------|
| 1178 | **lesson_candidate+binary_checks gate検査** | cmd_complete_gate.shにlesson_candidate空検証+binary_checks検証を追加。報告品質の機械的保証 |
| 1179 | **gate_dc_duplicate.sh新設** | DC裁定重複チェックゲート。既決PDへの再エスカレーション防止（L236対策） |
| 1180 | **FILL_THIS残留BLOCKメッセージ** | FILL_THIS残留検出時の具体的BLOCKメッセージ追加。忍者が修正箇所を即特定可能に |

- L299: git_uncommitted_gateはプロジェクトリポジトリを解決すべし。multi-agent-shogunとDM-signalで対象が異なる（cmd_1412）
- L300: binary_checks GATE検証はACグループ化+yes/true値をサポートすべし（cmd_1412）
→ `scripts/cmd_complete_gate.sh` / `scripts/gates/gate_dc_duplicate.sh`

## 知識サイクル現状（cmd_531/533/541/1111/1113/1117 反映）

教訓の蓄積→注入→参照→淘汰を自動で回す仕組み。家老が健全性を問われたらここを読め。

### 稼働中の仕組み

| 仕組み | 実装先 | 導入cmd | 動作 |
|--------|--------|---------|------|
| MAX_INJECT=5 | deploy_task.sh | cmd_531 | タスクあたり注入上限5件。helpful_count降順で優先。超過分はwithheldとしてlesson_impact.tsvに記録 |
| タグベース注入 | deploy_task.sh | cmd_349 | タスクtags[]と教訓tags[]をマッチングし関連教訓を自動注入 |
| 自動退役 | lesson_deprecation_scan.sh | cmd_531 | 有効率10%未満×注入10回以上→自動deprecated。ファイル消滅教訓も自動退役。GATE CLEAR時に自動実行 |
| 効果率監視 | gate_lesson_health.sh | cmd_531 | 直近30cmdの効果率計算。50%未満→WARN(ntfy)、30%未満→ALERT(ntfy+ダッシュボード) |
| lesson_candidate検証 | cmd_complete_gate.sh | cmd_528 | 報告YAMLのlesson_candidateフォーマットをゲートで検証。旧形式(リスト)→BLOCK |
| lesson_tracking.tsv | cmd_complete_gate.sh | cmd_348 | 教訓注入・参照の追跡ログをTSV永続化 |
| PDサマリー自動更新 | pending_decision_write.sh | cmd_541 | PD書込み/resolve時にpending_decisions.yaml冒頭のtotal/resolved/pending件数を自動更新 |
| context未更新ゲート | cmd_complete_gate.sh + deploy_task.sh | cmd_543 | cmd YAMLにcontext_update指定→deploy時に忍者タスクへ伝播→GATE時にlast_updated検査→stale時BLOCK |
| context鮮度監視整合 | context_freshness_check.sh + gate_context_freshness.sh | cmd_1889 | dashboard WARNとgateの監視対象を統一。直近completed cmdがあるactive projectのcontextのみ監視し、放置WARNの対象を一次データ基準へ揃える |
| CMD年代記 | archive_completed.sh | cmd_544 | cmd完了→archive時にcontext/cmd-chronicle.mdへ1行自動追記。月別セクション+flock排他 |
| Read追跡hook | settings.json hook | cmd_1044 | Write/Edit前に未Readファイルを自動ブロック。Read前Write問題を根本解決 |
| タスク/報告YAML hook強制 | settings.json hook | cmd_1065/1067 | queue/tasks/*.yaml, queue/reports/*.yamlへの直接Write/Editを無条件deny。deploy_task.sh/report_field_set.sh経由のみ許可 |
| 家老教訓自動ロード | instructions/karo.md | cmd_1111 | /clear Recovery手順にlessons_karo.yaml読込を追加。教訓参照漏れ防止 |
| gate穴検出3問トリガー | gate_improvement_trigger.sh | cmd_1113 | GATE CLEAR時に3問で防御層の穴を自動検出。ninja_monitor定期巡回に統合(cmd_1114) |
| hook失敗自動記録 | 報告テンプレート+ashigaru.md | cmd_1117 | hook_failures欄で失敗を構造化記録。穴検出3問と自動連鎖。詳細テンプレート→ [[ashigaru-detail]] (`docs/research/ashigaru-detail.md`) |
| 自動トリム | archive_completed.sh | cmd_1119/1120 | cmd-chronicle.md(200行)+shogun_to_karo.yaml(50件)をarchive時に自動トリム |

### 現行メトリクス（2026-03-30時点）

| 指標 | 値 | 備考 |
|------|------|------|
| 教訓総数(SSOT) | 152件(退役5件) | tasks/lessons.md |
| 教訓参照率 | 82.4% | lesson_tracking.tsv（391タスク中322件が参照） |
| 注入/除外比 | injected:1398 / withheld:763 | MAX_INJECT=5の効果。35%がフィルタリング |
| 初回CLEAR率 | **84.6%**(+21.9pt, cmd_1543計測) | gate_metrics.log。cmd_1532-1543改善効果 |
| 手戻り率 | 1.3% (1/77cmd) | fixes付きcmd |

### 設計思想

helpful/harmful手動評価に依存しない。注入回数と参照率を代理指標として自動で品質制御する。
- L418: ランブック品質はdb-operations-runbook以外極めて低い。28件中22件監査、21件が教訓参照ゼロ。ランブック品質底上げにはlesson索引セクション追加とPIの明示的組込みが必要（cmd_1094）
- L247: found:falseは教訓を探さなかった証拠。全タスクに学びがある。no_lesson_reason必須化+家老差し戻しルール追加（cmd_1104）
- L249: 教訓還流の仕組み変更は3層同時修正必須: ashigaru.md+deploy_task.sh+karo.md（cmd_1104）

## SessionStart hook — startup gate自動実行（cmd_2683）

session_start_inject.shが全ロールのstartup gateをセッション開始時に自動実行し、結果をadditionalContextに注入。
旧裁定(2026-04-12: /clear後gate自動実行禁止)は殿裁定(2026-05-12)で解除。前提変更: debounce 300-600秒+report_gate+safe_send_clearで/clear誤発火が改善済み。
対象: shogun→gate_shogun_startup.sh, karo→gate_karo_startup.sh, gunshi→gate_gunshi_startup.sh。exit 0固定(BLOCKしない設計)。

## 二重配備防止3層防御（cmd_2681/2682/2684）

| 層 | スクリプト | 防御ポイント | 方式 |
|----|-----------|-------------|------|
| L1 | deploy_task.sh | 配備時(事前阻止) | flock排他+完了報告YAML検知→BLOCK |
| L2 | ninja_monitor.sh | 巡回時(事後回収) | 先行完了検知→後発auto-void(idle化+/clear) |
| L3 | inbox_write.sh | 全配備経路(統一ガード) | task_assigned時に同一parent_cmd検査→BLOCK |

根因: cmd_2678-2680で同一cmdに2名配備→先行完了→後発空報告→レビュー+クリーンでトークン浪費(3連続)。

## 暗黒物質Phase 2: 高優先度60関数（cmd_2777）

cmd_2775偵察でcontext未記載だった238関数のうち、他エージェントの運用フロー・状態遷移に直接影響する60関数を受動知識化。調査時は関数名でgrepして到達せよ。

### ninja_monitor.sh: 状態管理・配備・監視・自動化（26件）

| カテゴリ | 関数 | 1行説明 |
|----------|------|---------|
| 状態管理 | `write_karo_snapshot` | 家老復帰用の陣形図を生成し、cmd・忍者状態・報告状況を集約する。重い監視処理より前に早期発行し、temp file + mvでatomic publishする。 |
| 状態管理 | `check_idle` | pane実態から忍者/家老がidleかを判定し、誤clearや誤配備を防ぐ入口になる。 |
| 状態管理 | `handle_confirmed_idle` | idle確定後の通知・auto-clear・auto-deployなど後続処理を統括する。 |
| 状態管理 | `handle_busy` | busy中paneの監視状態を更新し、idle向け処理を発火させない。 |
| 状態管理 | `update_inbox_counts` | tmux pane変数へ未読inbox数を反映し、nudge欠落時の復元材料にする。 |
| 状態管理 | `discover_panes` | tmux上のagent paneを探索し、監視対象一覧を更新する。 |
| clear制御 | `safe_send_clear` | CLI種別とreport gateを考慮して安全に/newまたは/clearを送る中核。 |
| clear制御 | `send_karo_clear` | 家老paneへ復帰用clearを送信し、陣形図付き復帰を成立させる。 |
| clear制御 | `check_karo_clear` | 家老clearの必要性を判定し、pending状態との競合を避ける。 |
| clear制御 | `can_send_clear_with_report_gate` | report未完了・未処理状態を見てclear送信可否を判定する防御層。 |
| pending/cmd監視 | `check_karo_pending_cmd` | 家老が処理すべきcmdの滞留を検出し、再nudge判断に使う。 |
| pending/cmd監視 | `check_karo_pending` | 家老pending全般を確認し、idle家老への復帰・再通知を制御する。 |
| pending/cmd監視 | `check_undeployed_cmds` | 未配備cmdを検出し、配備漏れを家老へ通知する。 |
| pending/cmd監視 | `check_stale_cmds` | 古いcmd状態を検出し、stale作業や放置を表面化する。 |
| 整合性回収 | `check_report_done_idle_mismatch` | 報告doneとpane/task状態の不一致を検出し、ghost状態を回収する。 |
| 整合性回収 | `auto_void_if_parent_cmd_completed` | parent cmd完了後に残る後発タスクを自動voidし、二重配備被害を止める。分割配備では `subtask_id` を `task_id`/`_ac_task_id` より優先して照合し、同一parent_cmd内の別担当taskを他忍者の完了報告で誤voidしない（cmd_3515/LK010）。 |
| handler | `_handle_auto_clear` | auto-clear条件成立時の実処理を担う内部handler。 |
| handler | `_handle_idle_notify` | idle通知の送信・抑制を扱う内部handler。 |
| handler | `_handle_deploy_stall` | 配備後STALLを検知し、本人/家老への回復通知へつなぐ。 |
| 修行自動化 | `_training_condition_met` | training自動配備の発火条件を判定する。 |
| 修行自動化 | `_handle_training_auto_deploy` | training候補をidle忍者へ自動配備する処理を担う。設計正本は[[training-cycle.md]]。 |
| bash速度修行 | `tools/bash_speed_training.sh` + `logs/script_speed_training_ledger.yaml` + `_handle_speed_training_auto_deploy` | scripts配下254本を非破壊`bash -n` baselineで台帳化し、pendingがあれば既存training_autoより先にidle忍者へ配備する。停止/再開はledgerの`global_status: running/paused`。 |
| 修行計測 | L772 | tracked限定のリンク集計では未tracked対象の改善が見えない。全対象の改善率を計測するにはtracked/untracked両方を含むメトリクスが必要（cmd_training_L1_report_write_20260625_kagemaru） |
| 健全性監視 | `check_ninja_cli_dead` | 忍者CLI死亡を検知し、pane復旧や通知判断につなげる。 |
| 健全性監視 | `check_loop_health` | 監視ループ自体の健全性を確認し、停止や劣化を検出する。 |
| 健全性監視 | `check_inbox_renudge` | 未読inboxが放置されたpaneへ再nudgeする。 |
| 健全性監視 | `check_inbox_watcher_health` | inbox_watcherの稼働を確認し、通知経路の断絶を検出する。 |
| 健全性監視 | `check_ntfy_listener_health` | ntfy_listenerの稼働を確認し、殿通知経路の断絶を検出する。 |

### deploy_task.sh: 注入・ゲート・配備制御（20件）

| カテゴリ | 関数 | 1行説明 |
|----------|------|---------|
| 配備入口 | `deploy_task_main` | deploy_task.sh全体の入口で、配備前検査からtask/report生成までを統括する。 |
| 配備入口 | `check_idle` | 配備先paneがidleか確認し、作業中忍者への上書き配備を防ぐ。 |
| stale防止 | `reset_stale_fields` | 前task由来の残留フィールドを初期化し、stale contaminationを防ぐ。 |
| 注入 | `inject_related_lessons` | 関連教訓をtask YAMLへ注入し、忍者の受動知識を増やす。 |
| 注入 | `inject_ac_version` | ACハッシュをtask/reportへ注入し、AC差替えや古いtask実行を検出可能にする。 |
| 注入 | `inject_ninja_weak_points` | 忍者別WA傾向をtaskへ注入し、頻出失敗を作業前に可視化する。 |
| 注入 | `inject_task_id` | task_idを正規化して注入し、report/gate/monitorの照合キーを揃える。 |
| 注入 | `inject_semantic_concepts` | semantic mapから関連概念をtaskへ注入し、必要contextへの到達を補助する。 |
| 注入 | `inject_standard_skills` | report-write/verdict-check等の標準スキルをtaskへ注入する。 |
| 注入 | `inject_production_invariants` | PJの本番不変量をtaskへ注入し、実装前の違反を防ぐ。 |
| 注入 | `inject_checklist_constraints` | PJチェックリストや制約をtaskへ注入し、手順飛ばしを防ぐ。 |
| 注入 | `inject_growth_loop_defense` | 学習ループ防御情報をtaskへ注入し、計測→還流を強制する。 |
| 注入 | `inject_engineering_preferences` | PJ固有のengineering_preferencesをtaskへ注入する。 |
| report生成 | `generate_report_template` | 忍者報告YAMLテンプレートを生成し、提出形式を固定する。 |
| cmd解決 | `resolve_cmd_to_task` | cmd情報からtask化に必要なID・AC・scopeを解決する。 |
| gate | `check_entrance_gate` | 配備入口条件を検査し、危険な配備を事前に止める。 |
| gate | `check_scout_gate` | 偵察タスク向けの要件を検査し、低品質偵察を防ぐ。 |
| gate | `preflight_gate_artifacts` | 配備前に必要artifactやgate前提を確認する。 |
| postcondition | `postcondition_lesson_inject` | 教訓注入後の成立条件を確認し、注入漏れを表面化する。 |
| mutation | `deploy_task_apply_task_mutations` | task YAMLへの各種mutationを一箇所で適用する。 |

### inbox_write.sh: メッセージ管理・重複検出（9件）

| カテゴリ | 関数 | 1行説明 |
|----------|------|---------|
| 書込み | `inbox_append_message_locked` | flock下でinboxへメッセージを追記し、lost updateを防ぐ正規経路。 |
| 書込み | `inbox_append_message_fast_locked` | 高速経路でinbox追記を行い、同時配信時もロック内で整合性を保つ。 |
| 重複配備防止 | `find_active_peer_deployments` | 同一parent cmdで稼働中のpeer配備を検出する。 |
| 重複配備防止 | `notify_karo_duplicate_deploy_block` | 重複配備BLOCKを家老へ通知し、配備判断を止める。 |
| unread管理 | `inbox_unread_count` | 対象inboxの未読数を数え、nudgeや復帰判断の材料にする。 |
| gate連携 | `trigger_cmd_complete_gate_background` | 完了報告受信後にcmd_complete_gateを背後で起動する。 |
| 宛先解決 | `list_active_ninjas` | 稼働中忍者一覧を取得し、通知対象や重複検査に使う。 |
| レビュー連携 | `forward_gunshi_review_result_to_active_ninjas` | 軍師レビュー結果を該当する稼働中忍者へ転送する。 |
| 件数確認 | `inbox_message_count` | inbox内メッセージ総数を数え、配送・既読化検証に使う。 |

### cmd_save.sh: 品質ゲート補助（5件）

| カテゴリ | 関数 | 1行説明 |
|----------|------|---------|
| 終了制御 | `handle_cmd_save_exit` | cmd_save終了時のBLOCK/WARN表示や学習ループ連鎖を統括する。 |
| summary | `show_quality_summary` | cmd品質ゲート結果を要約表示し、将軍が修正点を把握できるようにする。 |
| hook検査 | `check_gate_hook_action_conversion` | gate発火後に行動変換へつながる記述があるかを確認する。 |
| 学習ループ | `parse_structured_environment_change` | environment_changeを構造化して読み取り、BLOCK後の環境改善を検証する。 |
| red flag | `check_bundle_red_flag` | SG7 bundle等の赤旗条件を検出し、cmd保存前に警告/BLOCKする。 |

## ninja_monitor.sh

idle検知+コンテキストリセット送信（Codex=/new, Claude=/clear）、is_task_deployed二重チェック、STALE-TASK検出、CLEAR_DEBOUNCE=300s、karo_snapshot自動生成、状態遷移検知(cmd_255)。
karo_snapshotは重いmaintenance/gate処理より前に早期発行し、temp file + mvでatomic publishする。古い表示残り/監視詰まりの再発防止はL851を参照。
実装正本は[[ninja_monitor.sh]]。修行自動配備の設計根拠は[[training-cycle.md]]、詳細仕様は[[infra-details.md]] §3を参照。
三段階/clear(cmd_1039/1040): Stage 1: YAML status確認(acknowledged/in_progress→skip)→Stage 2: 再確認(race condition防止)→Stage 3: /clear送信。作業中忍者の誤クリア防止。
auto-done判定: parent_cmdだけでなくtask_idも一致チェック必須。Wave間で誤done発生実績あり(L048)。
auto_deploy統合(cmd_338): auto-done後にauto_deploy_next.sh自動発火。次サブタスク自動配備。
DEPLOY-STALL強化(cmd_461): 家老通知(L712-715)、再STALLエスカレーション(STALL_COUNT連想配列)、Codex stall_debounce=180s(cli_profiles.yaml)。
cmd_500(2026-03-03): check_stall()を再設計。`STALL_NOTIFIED`を5分デバウンス再通知へ変更、in_progress停滞時に本人へ`task_assigned`再送+`STALL-RECOVERY-SEND`ログ、同一subtask複数回で`stall_escalate`送信（「差し替え必須」明記）。Codex向け`in_progress_stall_min`を`config/cli_profiles.yaml`から読取（未設定時20分fallback）。
L112対応履歴: `task_id || subtask_id` フォールバック適用済み。調査記録は `docs/research/cmd_462_codex-stall-analysis.md`、実装記録は `docs/research/cmd_500_codex-stall-enforcement.md`
- L052: DESTRUCTIVE検出でcapture-pane履歴にsend-keysが残る誤検知あり（cmd_324）
- L114: safe_send_clear独自idle判定(tail -3)がCLIステータスバーで❯を見落とし永久CLEAR-BLOCKED。idle判定はcheck_idle()に一本化せよ（cmd_466）
- L134: NINJA_MONITOR_LIB_ONLYガードでbashスクリプトの関数テストが可能に（cmd_519）
- L204: STALL誤判定の実態は「idle+status未更新」が主因。pstree方式で予防的防御層追加が有効（cmd_777）
- L205: Codex paneの@agent_state=idleをbusy判定のtruth sourceにしてはならぬ（cmd_777）
- L248: assigned→idle化は/clear後にtask YAMLを読まなかった可能性大。STALL検知(10分超)で自動捕捉+家老に再配備通知（cmd_1105）
- L259: STALL偽陽性の38%はStale YAML Ghost(task_id空)が原因（cmd_1129）
→ `docs/research/infra-details.md` §3

## inbox_watcher.sh

inotifywait検知→`inboxN`短ナッジ送信。symlink注意。fingerprint dedup(cmd_255)。
`queue/inbox` はClaude Code auto-memory連携のため意図的にsymlinkとして維持する。実体ディレクトリへ置換するとinbox_watcherが旧inode/別経路を監視し続け、未読ナッジが滞留する。symlinkを触る前に `ls -ld queue/inbox` とwatcher再起動要否を確認し、`rm`/`unlink`/`mv`/`mkdir`/`cp` で `queue/inbox` を操作する場合はpre-bash hookがWARNを出す(cmd_3453)。
プロセス構造: 親=本体(inotifywait+メインループ)、子=MTIME_POLLサブシェル(L960)。WSL2 DrvFsでinotifywaitがinode置換でhangする問題への対策として、stat mtimeポーリングを子プロセスで並列実行しmtime変化検知時にinotifywaitをkillする。psで2プロセス見えるのは正常（親子関係。二重起動ではない）。
2026-03-03 運用修正: Codexで`@agent_state=active`残留時はcapture-paneでidle/busyを再判定し補正。BUSY deferはretry消費しない。`profiles.codex.inbox_busy_max_defer_sec`(既定30秒)超過で強制nudge。
- L002: FG bashでnudge不可（cmd_125）
- L018: Edit tool flock未対応→inbox既読化はinbox_mark_read.sh必須（cmd_189）
- L029: nudge嵐=二重経路合流（cmd_255）
- L043: inbox_write.sh Python展開にインジェクション脆弱性（cmd_317）
→ `docs/research/infra-details.md` §4

## ntfy.sh

`bash scripts/ntfy.sh "msg"` のみ。引数追加厳禁。topic=shogun-simokitafresh。
- L160: ntfy添付DLはAUTH_ARGS再利用でprivate topicでも同一認証経路を維持できる（cmd_551）
- L161: 画像添付MIME整合改善の必要性（cmd_551）
- L166: ストリーミング受信デーモンは起動側pkillに依存せず受信側でも単一起動ロックを持つべし（cmd_571）
- L167: ストリーム購読系デーモンはsingleton lock + message idempotency必須セット（cmd_571）
- L174: watchdogがkeepalive/open行のread成功でも活動時刻を更新→ntfy keepalive(45秒)で永遠延命（cmd_608）
- L175: ストリームwatchdogが任意受信バイトで更新されるとkeepaliveで実メッセージ断を見逃す（cmd_608）
- L176: watchdogの活動時刻は「意味のあるイベント処理成功」で更新すべし（cmd_608）
- L298: NTFY_LISTENER_LIB_ONLY=1でもtop-level初期化コードが実行される。source時の副作用に注意（cmd_1409）
→ `docs/research/infra-details.md` §5

## ログローテーション

二重機構で運用:

| 機構 | 実装 | トリガー | 閾値 | 世代 |
|------|------|----------|------|------|
| スタンドアロン | `scripts/log_rotate.sh` | 手動 or cron | 10MB/ファイル | 5世代(.1-.5) |
| ninja_monitor内蔵 | `lib/rotate_log.sh` → `rotate_all_logs()` | 10分間隔(メインループ) | 10,000行 or 1MB | 3世代(.1-.3), copytruncate方式 |

ninja_monitor内蔵版が常時稼働の主系。スタンドアロン版は非監視ログの手動ローテーション用。
- L258: ログローテーション世代数不足+task_idログ欠損（cmd_1129）

## field_deps.tsv

`scripts/lib/field_get.sh` の `_field_get_log()` が全呼出しを `logs/field_deps.tsv` に無条件追記。呼出し元→対象ファイル→フィールドの依存関係を記録する診断用ログ。ローテーション未実装のため無限肥大リスクあり(L243)。

## tmux設定

prefix=Ctrl+A。session=shogun、W1=将軍、W2=agents(家老+軍師+忍者8ペイン)。形式: shogun:agents.{pane}
将軍1+家老1+軍師1+忍者6=全9名。全員Opus 4.6(2026-03-17)。CLI→`config/settings.yaml`

| pane | 名前 | pane | 名前 |
|------|------|------|------|
| 1 | karo | 5 | hanzo |
| 2 | gunshi | 6 | saizo |
| 3 | hayate | 7 | kotaro |
| 4 | kagemaru | 8 | tobisaru |

ペインレベル環境変数は存在しない。ペイン別CLAUDE_CONFIG_DIRはrespawn-pane -e or send-keys注入(L041)。
capture-paneバナー解析: モデル名+バージョン番号の精密パターン必須。コマンドテキスト自体のfalse positiveに注意(L046)。
- L004: pane変数空≠未配備（cmd_092）
- L067: ペイン背景色は@model_name更新と連動していない（cmd_365）
- L068: shutsujin_departure.shが2ファイル存在(root+scripts/)で背景色ロジック不整合（cmd_365）
- L094: scripts/shutsujin_departure.shにモデル名ハードコード残存（cmd_405）
- L105: E2Eテストでtmux pane-base-index依存は明示固定せよ（cmd_438）
- L118: tmux set-optionのtargetがsession指定だとwindow optionが意図せずcurrent windowのみ更新（cmd_468）
- L123: tmuxターゲットにウィンドウINDEXを使用するな — NAME(固有名)を使え（cmd_494）
- L124: paste-bufferの-dフラグはタイムアウト時に発動しない — 明示的delete-buffer必須（cmd_494）
- L125: paste-buffer注入先はagent_id検証で防御せよ(defense-in-depth)（cmd_494）
- L265: shutsujin_departure.shハードコードレイアウト禁止（3原則）（cmd_1139）
- L268: 非連番ペインインデックスにはPANE_IDS配列パターンが有効（cmd_1141）
→ `docs/research/infra-details.md` §6-7

## Claude Code マルチアカウント管理（cmd_313偵察）

- Usage API: `GET https://api.anthropic.com/api/oauth/usage` (OAuth Bearer + `anthropic-beta: oauth-2025-04-20`)
- レスポンス: `five_hour.utilization`(%), `seven_day`, `extra_usage`。read-only、クレジット消費なし
- Profile API: `GET https://api.anthropic.com/api/oauth/profile` → アカウント名・プラン・rate_limit_tier
- 認証保存: `~/.claude/.credentials.json` (claudeAiOauth.accessToken/refreshToken)
- 複数アカウント: `CLAUDE_CONFIG_DIR=~/.claude-{name}` でディレクトリ分離が最も堅牢(L015)
- WSL2+tmux同時監視: HIGH(curl 1本で取得可能、pane別環境変数で2アカウント並行)
- 注意: undocumented API(変更可能性あり)、refresh_tokenは1回限り使用(L016)
- WSL2→API応答5秒超のため監視スクリプトtimeout≥10秒必須(L040)
- L082: Codexは~/.codex/を全エージェント共有。分離機構なし（cmd_390）
- L083: bypass-approvals-and-sandboxフラグ漏れで全操作が権限確認停止（cmd_390）
- L237: OpenAI ChatGPT ProはOAuth認証でAPIキー不要。tmuxペインパース方式では不正確（cmd_995）
→ `docs/research/cmd_314_usage_api_verification.md` / `docs/research/cmd_314_account_switching_procedures.md`

## Google Workspace CLI (gws) — 全PJ共通ツール

`npm i -g @googleworkspace/cli`。Gmail/Drive/Calendar/Sheets/Docs/Chat対応。

**アカウント:**
- デフォルト: `simokitafresh@gmail.com`（殿裁定 2026-04-13）
- サブ: `karasuyama3387@gmail.com`
- 切替: `gws auth switch <email>` or `--account <email>` フラグ
- 設定: `~/.config/gws/accounts.json`

**Sheets操作の注意点:**
- 日本語環境ではシート名が「シート1」（"Sheet1"ではない）。`spreadsheets get`でタブ名を確認してから`values update`
- `values update`は`--params '{"spreadsheetId":"...","range":"シート1!A1","valueInputOption":"USER_ENTERED"}'`
- CSV→2D配列変換は`--json '{"values": [[row1...],[row2...]]}'`
- 新規作成: `gws sheets spreadsheets create --json '{"properties":{"title":"..."}}'`

**Gmail操作（cmd_2900, 2026-05-20）:**
- 認証確認: `gws auth status`だけでログアウト判定するな。暗号化credentials検出漏れで`auth_method: none`でも実APIが通る場合あり。正判定は `gws gmail +triage --max 1 --format json` の成功確認（read-only、実測5.6秒）
- triage: `gws gmail +triage --max 5 --query 'is:unread newer_than:7d' --format table` / ラベル付き確認は `gws gmail +triage --labels --max 10`
- 検索: `gws gmail users messages list --params '{"userId":"me","q":"from:alerts@example.com is:unread","maxResults":10}'`。詳細取得は返却IDで `gws gmail users messages get --params '{"userId":"me","id":"MSG_ID","format":"metadata","metadataHeaders":"Subject"}'`
- フィルタ一覧/取得/削除: `gws gmail users settings filters list --params '{"userId":"me"}'` / `gws gmail users settings filters get --params '{"userId":"me","id":"FILTER_ID"}'` / `gws gmail users settings filters delete --params '{"userId":"me","id":"FILTER_ID"}'`
- フィルタ作成: `gws gmail users settings filters create --params '{"userId":"me"}' --json '{"criteria":{"from":"alerts@example.com","query":"subject:(deploy) newer_than:30d"},"action":{"addLabelIds":["Label_123"],"removeLabelIds":["INBOX"]}}'`。`removeLabelIds:["INBOX"]` がarchive相当。Gmail APIにfilter updateはないため、変更はdelete→create
- メッセージ操作: 既読化は `gws gmail users messages modify --params '{"userId":"me","id":"MSG_ID"}' --json '{"removeLabelIds":["UNREAD"]}'`、archiveは `--json '{"removeLabelIds":["INBOX"]}'`、ラベル付与は `--json '{"addLabelIds":["Label_123"]}'`。破壊操作のdeleteではなく必要ならtrash系を優先

**教訓(auto-ops由来、全PJ適用):**
- L023/L027: Sheets取得は`spreadsheets values get --params`形式が正（+read旧式）
- L028: Drive files get alt=media構文
- L030: Drive files rename/deleteバッチ
- L055: Drive moveはfiles updateのaddParents/removeParents

→ auto-ops固有の経費管理パターンは `context/auto-ops.md §gws CLI` 参照

## Render運用（cmd_2824, 2026-05-17）

推測禁止。コールドスタート仮説を出す前に、対象が `free` web service か、paid web service か、static site かをこの表で判定する。
根拠: Render公式Docs `https://render.com/free` / `https://render.com/docs/faq` / `https://render.com/docs/static-sites/` + `render services --output json` 実測(2026-05-17)。

### プラン別挙動

| 対象 | 挙動 | 障害切り分けでの扱い |
|------|------|----------------------|
| Free web service | 15分無通信でspin down。次のHTTP/WebSocketでspin upし、約1分かかる | 初回遅延/502/503はコールドスタート候補。ただしAPI疎通で確認してから判断 |
| Starter/Standard/Pro web service | Paid instance。Render FAQ上、paid instanceはspin downしない | コールドスタート仮説を採用しない。アプリ/DB/ログ/Render障害を先に見る |
| Static Site | Render Static Site。global CDN配信 | サーバー起動待ちはない。障害はビルド成果物、rewrite、CDN/Render Status、接続先APIを見る |
| Cron Job | スケジュール実行コンテナ | URLなし。失敗時はcron job logs、呼び出し先API、envVars、重複cronを確認 |
| Render Postgres | managed database | API不調時はDB接続/クエリ/容量/メンテナンスを確認。web serviceのcold startとは別物 |

### 障害切り分け手順

1. **API確認**: 対象URLの `/healthz` / `/health` / 主要APIを叩く。Static Siteなら接続先API URLも別に確認する。
2. **DB確認**: APIがDB依存なら `render psql <dpg-id>` またはPJ標準のDB確認手順で接続・代表クエリを確認する。
3. **ログ確認**: `render logs --output text <service-id-or-name>` / cron job logsでアプリ例外、OOM、deploy失敗、env不足を見る。
4. **Renderステータス確認**: 上記で異常が説明できない場合だけ `https://status.render.com/` とDashboardを確認する。

### 全サービス一覧

| 名前 | ID | 種別 | プラン | URL | 状態 |
|------|----|------|--------|-----|------|
| CPCV | `srv-d1map9qli9vc7399sk8g` | web_service | starter | `https://cpcv.onrender.com` | suspended |
| DM-metrics-checker | `srv-d2j03qe3jp1c73bvjnig` | web_service | standard | `https://dm-metrics-checker.onrender.com` | suspended |
| DM-momentum-checker | `srv-d2v8c9vdiees73dsaup0` | web_service | free | `https://dm-momentum-checker.onrender.com` | suspended |
| DualMomentum-Combination | `srv-d1q4hpbipnbc738lhfag` | web_service | starter | `https://dualmomentum-combination.onrender.com` | suspended |
| DualMomentum-Rebalancer | `srv-d1utt3re5dus7399plrg` | web_service | starter | `https://dualmomentum-rebalancer.onrender.com` | not_suspended |
| Kubun-checker | `srv-d10hahe3jp1c73907un0` | static_site | starter | `https://kubun-checker.onrender.com` | not_suspended |
| LP-DM-Standrad | `srv-d20skn95pdvs739dbnig` | static_site | starter | `https://lp-dm-standrad.onrender.com` | not_suspended |
| Legacy_PF_Rebalancer | `srv-d4iih4ili9vc73ej3m50` | web_service | starter | `https://rebalancer-backend-z9qd.onrender.com` | suspended |
| QuickCard | `srv-d1hnmkje5dus7397jth0` | web_service | starter | `https://quickcard-edrr.onrender.com` | not_suspended |
| Real-CPCV | `srv-d1ohqnbipnbc73f2bqqg` | web_service | starter | `https://real-cpcv.onrender.com` | suspended |
| Road-To-S4 | `srv-d1d5t4re5dus73b179ng` | web_service | starter | `https://road-to-s4.onrender.com` | suspended |
| Simple-Dual-Momentum | `srv-d15qgc7diees73ecrk3g` | web_service | starter | `https://simple-dual-momentum.onrender.com` | suspended |
| Simple-OCR | `srv-d1l2gnmmcj7s73bnmfp0` | web_service | starter | `https://simple-ocr.onrender.com` | not_suspended |
| SmartQuiz by Original | `srv-d1ela7be5dus73bj80m0` | web_service | free | `https://smartquiz-ocr.onrender.com` | not_suspended |
| Stockdata-API | `srv-d2psuqbe5dus73bedm2g` | web_service | standard | `https://stockdata-api-6xok.onrender.com` | not_suspended |
| Stockdata-API-daily-update | `crn-d2vqn6buibrs73dla6vg` | cron_job | starter | `-` | not_suspended |
| TEST-dm-signal-backend-lyk3 | `srv-d5ahs0ali9vc73b6tprg` | web_service | standard | `https://test-dm-signal-backend-lyk3.onrender.com` | suspended |
| askul-order | `srv-d0s64ps9c44c73cqpub0` | web_service | starter | `https://askul-order.onrender.com` | not_suspended |
| cafe_fresh | `srv-d0o6uh0dl3ps73aadid0` | static_site | starter | `https://cafe-fresh.onrender.com` | not_suspended |
| classroom-dashboard | `srv-d6hk293h46gs73e99ao0` | static_site | starter | `https://classroom-dashboard-5c2h.onrender.com` | not_suspended |
| dm-chart-backend | `srv-d4enc8pr0fns73br4o30` | web_service | starter | `https://dm-chart-backend.onrender.com` | not_suspended |
| dm-chart-etl | `crn-d4ene6hr0fns73br60a0` | cron_job | starter | `-` | not_suspended |
| dm-chart-frontend | `srv-d4enc8pr0fns73br4o2g` | static_site | starter | `https://dm-chart-frontend.onrender.com` | not_suspended |
| dm-rebalancer-backend | `srv-d4jacrfpm1nc73dudmn0` | web_service | starter | `https://dm-rebalancer-backend.onrender.com` | not_suspended |
| dm-rebalancer-frontend | `srv-d4jacrfpm1nc73dudmmg` | static_site | starter | `https://dm-rebalancer-frontend.onrender.com` | not_suspended |
| dm-signal-backend | `srv-d4ja7q15pdvs739a4q1g` | web_service | pro | `https://dm-signal-backend.onrender.com` | not_suspended |
| dm-signal-db | `dpg-d542chchg0os73979vg0-a` | postgres | basic_1gb | `-` | not_suspended |
| dm-signal-deterioration-batch | `crn-d6kehqlm5p6s73dov630` | cron_job | starter | `-` | not_suspended |
| dm-signal-etl | `crn-d4ja8pp5pdvs739a5fs0` | cron_job | pro | `-` | suspended |
| dm-signal-frontend | `srv-d4ja8pp5pdvs739a5fsg` | static_site | starter | `https://dm-signal-frontend.onrender.com` | not_suspended |
| dm-signal-password-rotation | `crn-d53agure5dus73ap8el0` | cron_job | starter | `-` | not_suspended |
| dm-signal-sync-fof | `crn-d5e8rabe5dus73fhlkjg` | cron_job | starter | `-` | not_suspended |
| dm-signal-sync-prices | `crn-d5e8rabe5dus73fhlkj0` | cron_job | starter | `-` | not_suspended |
| dm-signal-sync-standard | `crn-d5e8rabe5dus73fhlkl0` | cron_job | starter | `-` | not_suspended |
| dm-signal-sync-tickers | `crn-d5e8rabe5dus73fhlkkg` | cron_job | starter | `-` | not_suspended |
| inventory-app | `srv-d1d3m9re5dus73av45q0` | web_service | free | `https://inventory-app-uaou.onrender.com` | not_suspended |
| karajibi-stabilo-checker | `srv-d22ddeidbo4c73f3s0gg` | static_site | starter | `https://karajibi-stabilo-checker.onrender.com` | not_suspended |
| kj-partshift-checker | `srv-d4vta05actks73aan3s0` | web_service | starter | `https://kj-partshift-checker.onrender.com` | not_suspended |
| kj-toilet-backend | `srv-d4la0dgdl3ps7382pk60` | web_service | starter | `https://kj-toilet-backend.onrender.com` | not_suspended |
| kj-toilet-db | `dpg-d4la00gdl3ps7382pdfg-a` | postgres | basic_256mb | `-` | not_suspended |
| kj-toilet-frontend | `srv-d4la00gdl3ps7382pdeg` | static_site | starter | `https://kj-toilet-frontend.onrender.com` | not_suspended |
| note-dr-premium | `srv-d1u5r0ur433s73ed6kc0` | static_site | starter | `https://note-dr-premium.onrender.com` | not_suspended |
| rebalancer-frontend | `srv-d4iil54hg0os739v3cc0` | static_site | starter | `https://rebalancer-frontend.onrender.com` | suspended |
| simple-dual-momentum-db | `dpg-d1altb95pdvs73avn820-a` | postgres | basic_256mb | `-` | suspended |
| sunabaco | `srv-d0k2kmje5dus73bd94qg` | web_service | starter | `https://sunabaco.onrender.com` | suspended |

## WSL2固有

inotifywait不可(/mnt/c)→statポーリング。.wslconfigミスで全凍死注意。→ §8
- **ディレクトリsymlink不可**: os.symlink成功→is_dir=False→listdir/read全ENOENT。テキストポインタ(latest.txt)またはファイルsymlinkを使え（L663, cmd_2332）
- L008: WSL2新sh→CRLF混入（cmd_143）
- L014: grep exclude WSL2不安定（cmd_151）
- L037: WSL2 Write tool .sh→CRLF確定(L008拡張)（cmd_311）
- L058: WSL2 Write toolでCRLF混入→sed -i 's/\r$//'必須（cmd_370）
- L129: WSL2 Python3.12環境では外部feed偵察時にvenv未整備ケースがある（cmd_506）
- L194: pre-push timeout 40s→120s延長(WSL2)（cmd_721）
- L221: WSL2上の/mnt/c/配下ファイルはCRLF含むことがある（cmd_911）
- L227: WSL2のWrite toolはCRLF改行を生成する（cmd_970）
- L228: ast-grepのregex ruleはkind併記が要る（cmd_973）
- L316: WSL→Windows venv Ruff hook: repo-relative pathを使え（cmd_976）
- L301: bash埋込みPythonではsys.argv経由でパスを渡せ。ヒアドキュメント内の変数展開でエスケープ地獄を回避（cmd_training_L4_004）

## 競合調査

6スタイル+我らの定点観測レポート。毎回検索するな、ここを参照せよ。
我ら(57pt) > OpenAI(46) > OpenClaw(42) > ACE(40) > Teams(36) > Vercel(32)。
優位: 3層階層、6層知識、2重安全防御、インフラ構造保証。劣位: 外部可視性、セットアップ容易性。
→ `docs/research/competitive-landscape.md`

五者対比図(われら/ACE/Vercel/おしお/Claude Teams): 10軸×5者の詳細対比+系譜図+参考文献。
殿の厳命「われらはACEもVercelもOpenClawも内包し上回る」の根拠文書。
→ `docs/research/five-system-comparison.md`

Autoresearchエコシステム対比(Karpathy派生70+プロジェクト): 将軍システムは既にkeep-or-revert(gate)・永続メモリ(lessons/deepdive)・メタ改善(cmd_save.sh自己改善)・マルチエージェント調整(鎖/inbox)を実装済み。将軍独自の強み: revertではなく「修正→再実行」(学習を伴う)、追体験(deepdive)。未実装: 自動メタ改善(GEPA的instructions自動修正提案)、水平知識共有(忍者間ゴシップ)、安価ランタイム自動蒸留。注目: GEPA(ICLR 2026 Oral, 自然言語反射)、CORAL(共有永続メモリ+SOTA)、AI-Researcher(NeurIPS 2025, 仙人構想の参考)。
→ `docs/research/autoresearch-ecosystem-analysis.md`

## Android App

将軍Androidアプリは `android/` 配下の Kotlin + Jetpack Compose 製コンパニオン。package/applicationId=`com.shogun.android`、v6.4(versionCode 15)、SSH経由でtmuxを操作し、Dashboard/Agents/ShogunScreen/Settings/GistIndex/Usage を提供する。

| 項目 | 正本 |
|------|------|
| パス | `android/` |
| ビルド | `android/app/build.gradle.kts`（Gradle + AGP、Kotlin、Compose、Min SDK 26 / Target 34） |
| パッケージ | `com.shogun.android` |
| 主要画面 | Dashboard / Agents / ShogunScreen(将軍CLI) / Settings / GistIndex / Usage |
| SSH | `android/app/src/main/java/com/shogun/android/ssh/SshManager.kt`（JSch） |
| 音声入力 | `android/app/src/main/java/com/shogun/android/util/VoiceDictionary.kt`（90+プリセット） |
| README | `android/README_ja.md` / `android/README.md` |
| APK | `android/release/` |
| cmd履歴 | `context/cmd-chronicle.md` cmd_1809-1816, cmd_1924, cmd_1943, cmd_1945, cmd_2104 |
| 入力ロス調査 | [[android-ssh-input-loss-investigation]] |

## Infra教訓索引
<!-- last_synced_lesson: L877 -->
<!-- lesson-sort 2026-04-21: L467-L520の54件をカテゴリ分類(49件移動+5件重複削除)。bash(L474/475/480/482/483/484/487/490/491/495/498/502/503/505/506/509/511/512/515/516), ゲート(L468/470/471/473/479/493/496/501/507), テスト(L476/477/488/497/499/500/513/517/518), WSL2(L485/486/494/504/508), git(L472/514/519), 報告(L467), 教訓(L510), deploy(L520)。重複: L469≈L468, L478≈L477, L481≈L480, L489≈L488, L492≈L491 -->
<!-- lesson-sort 2026-04-11: L451-L466の16件をカテゴリ分類。deploy(L451/L458/L465), ゲート(L452/L455), git(L453/L454/L456/L457/L459), UI/Android(L460/L461/L462/L463), 報告(L464), bash(L466)。重複候補: L454≈L457≈L459(gitignore whitelist), L461≈L462≈L463(imePadding) -->
<!-- lesson-sort 2026-04-08: L448-L450の3件をカテゴリ分類。レビュー/軍師(L448/L450), ゲート(L449)。重複L442-L446(2nd occurrence)を削除 -->
<!-- lesson-sort 2026-04-07: L442-L447の6件をカテゴリ分類。bash(L442/L443/L445), ゲート(L444/L446), git(L447) -->
<!-- lesson-sort 2026-04-06: L437-L441の5件をカテゴリ分類。bash(L437/L438), レビュー/軍師(L439/L440), git(L441) -->
<!-- lesson-sort 2026-03-28: L298-L301の4件を振り分け。ntfy(L298), gate強化(L299/L300), WSL2(L301) -->
<!-- lesson-sort 2026-03-22: L256-L284の29件を振り分け(27件移動+2件重複削除)。§メインセクション: ninja_monitor(L259), ログローテーション(L258), tmux(L265/268), 軍師(L271/281)。サブセクション: bash(L263/269/270/272/277), deploy(L256/284), 報告(L264), 教訓(L257/260/266/273/275/276), gate(L262/280/282), テスト(L261), 知識(L274), レビュー(L267/283)。L278/L279重複削除 -->
<!-- lesson-sort 2026-03-26: L285-L297の13件を振り分け(12件移動+1件重複削除)。bash(L287/289/290/295/297), deploy(L288), 報告(L291), 教訓(L285), git(L292), 知識(L286/293/294)。L296はL297重複→削除 -->
<!-- lesson-sort 2026-04-02: L302-L436の135件をカテゴリ分類。bash(90件:修行L4サイクル教訓大量), git(5件), deploy(2件), 報告(2件), 教訓サイクル(4件), ゲート(3件), テスト(13件), レビュー/軍師(2件), LLM(4件), WSL2(2件)。§セクションにL298-L301追加。知識管理からL353削除(bash再分類) -->

### カテゴリ別索引（L051-L466）
| カテゴリ | Lesson IDs | 件数 |
|---------|------------|------|
| bash/シェルスクリプト | L059,074,092,096,149,155,156,157,164,169,170,171,183,184,231,263,269,270,272,277,287,289,290,295,297,302,304,324,325,328,329,330,332,333,335,336,337,338,339,340,341,343,345,346,348,349,350,351,352,353,354,355,356,357,358,359,360,361,363,364,365,366,367,368,369,370,371,372,373,374,376,378,380,381,383,384,385,386,387,389,390,391,392,393,394,395,396,397,398,399,401,402,403,404,405,407,408,409,410,411,413,414,415,416,417,419,423,424,425,426,427,428,429,435,436,437,438,442,443,445,466,474,475,480,482,483,484,487,490,491,495,498,502,503,505,506,509,511,512,515,516 | 141 |
| git/gitignore/CI/hooks | L064,072,093,109,110,113,116,143,144,150,151,153,172,179,180,186,188,189,190,192,218,220,232,233,292,342,347,377,379,382,388,441,447,453,454,456,457,459,472,514,519,622 | 42 |
| deploy_task.sh/配備 | L056,057,070,071,073,076,079,088,111,119,181,185,207,219,222,230,256,284,288,305,310,451,458,465,520 | 25 |
| 報告YAML/レポート | L055,060,062,085,091,095,098,120,121,127,131,132,209,210,264,291,312,334,362,464,467 | 21 |
| 教訓サイクル/lesson | L054,063,080,081,086,087,089,102,106,107,117,126,133,136,137,141,145,147,152,154,165,168,214,217,257,260,266,273,275,276,285,303,308,309,317,510 | 36 |
| ゲート/gate_metrics | L097,099,100,101,215,216,262,280,282,311,314,331,444,446,449,452,455,468,470,471,473,479,493,496,501,507 | 26 |
| テスト | L142,146,148,158,162,163,191,193,208,234,235,261,315,318,319,320,321,322,323,326,327,344,422,430,431,476,477,488,497,499,500,513,517,518 | 34 |
| 知識管理/ビルド | L065,066,077,084,090,104,128,135,173,182,206,212,274,286,293,294 | 16 |
| レビュー/軍師 | L061,138,139,140,236,239,267,283,313,375,434,439,440,448,450 | 15 |
| LLM/エージェント/MCP | L051,053,108,130,159,178,201,203,211,213,223,224,225,226,238,400,420,421,432,433,618 | 21 |
| UI/Android | L187,195,196,197,198,199,200,202,460,461,462,463 | 12 |
| WSL2 | L306,307,485,486,494,504,508 | 7 |
| → §セクション振り分け済 | L002,004,008,014,018,029,037,043,052,058,067,068,069,082,083,094,103,105,114,118,122,123,124,125,129,134,160,161,166,167,174,175,176,194,204,205,221,227,228,237,258,259,265,268,271,278,279,281,298,299,300,301,316 | 53 |

→ 詳細(L001-L297の個別記述): `docs/research/infra-lessons-detail.md`
- （L298→§ntfy.sh, L299/L300→§gate強化, L301→§WSL2に振り分け済 2026-03-28）
- L302: pipefailスクリプトでgrep空マッチがexit 1を引き起こす（pipefail,grep,bash,ci）
- L303: RUNBOOK還流漏れ検出（cmd_1486）
- L304: grep -c || echo 0 二重出力バグ（cmd_1502）
- L305: deploy_task.sh cmd_id引数なし→task YAML手動更新忘れで旧cmd配備（cmd_1493）
- L306: WSL2 DrvFs並列I/Oは逆効果 — backgroundプロセスでの先行I/Oはカーネル直列化で悪化する（cmd_1516）
- L307: WSL2 /mnt/cでは並列I/Oが逆効果になる（cmd_1516）
- L308: AC前提と実データの乖離確認（cmd_1518）
- L309: 教訓注入の3構造問題: universalタグ誤分類+ファイルレベルマッチング欠如+負帰還ループ欠如（cmd_1525）
- L310: STALE_FIELDSリストは新フィールド追加時に更新漏れが起きやすい。deploy_task.shにフィールド追加する際はSTALE_FIELDSとテストも同時更新必須（cmd_training_structural_001）
- L311: WA率60.8%の3構造問題: autofix不網羅+uncategorized分類漏れ+事前防止hook欠如（cmd_1530）
- L312: report_templateがSTALE_FIELDSに未登録 — stale残留リスク（cmd_training_structural_002）
- L313: GP ID重複問題: 同一IDに異なる提案が混在するとトリアージが困難（cmd_1528）
- L314: unknown_block_reasonはgate diagnostics改善で排除可能（cmd_1529）
- L315: テストとテスト対象は同一コミットに含めよ（cmd_1558）
- L317: 教訓注入のuseful:false 81.7%はタスク種別不一致。タグマッチ精度向上と死蔵教訓の抽象度昇格が必要（lessons,deploy,injection,useful-rate）
- L318: infraテストは全件必要（後半27テスト全て90日以内変更+本番フロー関与）（test,infra,recon,test-necessity）
- L319: テスト重複統合候補3組: tests/とtests/unit/に同名テストが並存（cmd_1562）
- L320: infraテストは全件必要と判定（後半27テスト）（cmd_1562）
- L321: INBOX_WRITE_TEST=1でreport_received検証がスキップされる（cmd_1565）
- L322: case文のステータス網羅性を実行結果で検証せよ（cmd_training_comprehensive_004）
- L323: プロセス数検証は実際の起動数を追跡せよ。外部計算の期待値はスキップ条件を反映しない（cmd_training_comprehensive_003）
- L324: bashスクリプトでのsubprocess削減: echo|grepよりbashパターンマッチ（cmd_training_comprehensive_002）
- L325: tmux変数の一括取得にはlist-panes -Fを使え（cmd_training_comprehensive_001）
- L326: nohup+disownプロセスの起動検証はPID配列追跡+kill -0が確実（cmd_training_comprehensive_006）
- L327: ハードコード値は動的取得済みデータの活用漏れを疑え（cmd_training_comprehensive_005）
- L328: tmux一括取得データのawk-in-loop参照は連想配列で排除せよ（cmd_cycle_L4_002）
- L329: IFS=| read -ra分割+read -rトリムでawk forkを削減（cmd_cycle_L4_001）
- L330: パス解決は/bin/bashより解決済み変数を再利用せよ（cmd_cycle_L4_003）
- L331: grepベース検出パターンは偽陽性率を計測して調整せよ（cmd_cycle_L4_004）
- L332: Markdownテーブルのパイプ区切りパースはセル数固定でなく日付等の不変パターンをアンカーにすべき（cmd_cycle_L4_005）
- L333: grep -qのパイプはstdout抑制でデッドコードになる（cmd_cycle_L4_008）
- L334: shout.shのREPORT_FILEパス解決が固定名でレポート参照不能（cmd_cycle_L4_007）
- L335: grep重複検出は-Fqw必須（cmd_cycle_L4_009）
- L336: report_field_set.shのawkバックスラッシュエスケープ問題（cmd_cycle_L4_006）
- L337: bashループ内sed/awk繰り返しはO(N*M)→一発パス化でO(M)に（cmd_cycle_L4_010）
- L338: Pythonインラインスクリプトで同一ファイルを複数回開く場合は1回に統合せよ（cmd_cycle_L4_015）
- L339: archive scan内のYAML fieldマッチはsubstring禁止—正規表現+長さ優先ソート必須（cmd_cycle_L4_014）
- L340: YAML書込み時のダブルクォート・バックスラッシュ未エスケープはYAML構造を破壊する（cmd_cycle_L4_013）
- L341: heredoc一括書込みでファイル中間状態を排除（cmd_cycle_L4_011）
- L342: ホワイトリスト.gitignoreではscriptsディレクトリ内の新規ファイルもgit add -f必須（cmd_cycle_L4_016）
- L343: bash YAMLパーサの正規表現はインデント0とN両方+id:プレフィックス対応が必要。セクション終了はtop-level keyのみで判定せよ（cmd_cycle_L4_012）
- L344: テスト教訓（test_cmd）
- L345: 環境変数経由のPython連携では手動エスケープは不要かつ有害（cmd_cycle_L4_017）
- L346: stderr/stdout混合キャプチャは値汚染バグの温床（cmd_cycle_L4_018）
- L347: ninja_done.shは.gitignoreホワイトリスト未登録（cmd_cycle_L4_019）
- L348: --strategicフラグ検出は位置引数ではなくスキャン方式にすべき（cmd_cycle_L4_020）
- L349: シェルスクリプトの書込み専用ファイル変数はデッドコードの兆候（cmd_cycle_L4_021）
- L350: load_cmds系関数はcommands値がlist/dict両形式を想定すべき（cmd_cycle_L4_022）
- L351: insight_write.shがyaml.dumpでqueue/ファイルを書き戻しておりポリシー違反（cmd_cycle_L4_025）
- L352: ntfy.shのsend_with_retryは失敗時にstderrへ何も出さず呼び出し元が原因不明（cmd_cycle_L4_024）
- L353: heredocによるYAML生成時のquote injection（cmd_cycle_L4_026）
- L354: 同一リソースを操作する複数スクリプトのロックパス一致確認必須（cmd_cycle_L4_023）
- L355: YAML正規表現はクォートなし/単引用/二重引用の3形式に対応すべし（cmd_cycle_L4_028）
- L356: YAML文字列化dictのパースにast.literal_evalは使えない(不完全文字列で失敗)（cmd_cycle_L4_027）
- L357: yaml.dumpを使用する自動タグ付けスクリプトはCLAUDE.md安全規則に違反（cmd_cycle_L4_029）
- L358: sedパースの無音失敗パターン: 空文字をデフォルト値扱いすると無音でロジックバイパス（cmd_cycle_L4_034）
- L359: eval出力パースはホワイトリスト付きwhile readで代替すべき（cmd_cycle_L4_031）
- L360: decision_write.shのPython内変数参照がexport/os.environ方式と直接補間で不整合（cmd_cycle_L4_032）
- L361: idle|noneのsentinel値はawk split+空文字チェックを素通りする（cmd_cycle_L4_033）
- L362: SequenceMatcher.quick_ratio()前段フィルタで大量ペア比較を高速化（cmd_cycle_L4_030）
- L363: lesson_edit.shはlock_path未使用の唯一のflock使用スクリプト（cmd_cycle_L4_035）
- L364: bash変数のPythonインライン展開はインジェクションリスク。環境変数経由(export+os.environ)が安全（cmd_cycle_L4_036）
- L365: lock_path()未適用スクリプトがまだ残存する(NTFS flock不安定パターン)（cmd_cycle_L4_037）
- L366: eval+shlex.quoteパターンでbash-python3間の多重起動を統合できる（cmd_cycle_L4_039）
- L367: python3多重起動パターンはshlex.quote+eval一括抽出で9→1に統合可能（cmd_cycle_L4_038）
- L368: send_alertの呼び出し漏れパターン: 計算済み値の未消費（cmd_cycle_L4_042）
- L369: ac_physical_verify.shのAC抽出正規表現にリテラル文字除外バグ（cmd_cycle_L4_044）
- L370: DRY関数抽出時はフォールバックチェーンの統一も同時に行え（cmd_cycle_L4_041）
- L371: Python内シェル変数展開は環境変数経由に統一せよ（cmd_cycle_L4_045）
- L372: tmux display-messageはフォーマット文字列で複数変数を一括取得可能（cmd_cycle_L4_046）
- L373: シェルスクリプトの中間結果繰り返し前処理はキャッシュ変数で一括化せよ（cmd_cycle_L4_043）
- L374: ファイルストリーム処理での中間リスト排除パターン（cmd_cycle_L4_047）
- L375: 同一ファイル多段読取りパターンは単一awkパスに統合せよ（cmd_cycle_L4_049）
- L376: should_actの状態保存タイミングでALERT消失リスク（cmd_cycle_L4_050）
- L377: lesson_deprecate.shもyaml.dump禁止パターンに該当（cmd_cycle_L4_052）
- L378: ログローテーションスクリプトはflock+再チェックパターンで並行安全にせよ（cmd_cycle_L4_048）
- L379: gitignore whitelist方式ではgit add -fが必要な場合がある（cmd_cycle_L4_051）
- L380: daemon_watchdog.shのログ出力先にローテーション不在で肥大化リスク（cmd_cycle_L4_058）
- L381: section関数の内部matrix再利用パターン（cmd_cycle_L4_053）
- L382: statusline.shはgitignoreホワイトリスト未登録だった（cmd_cycle_L4_054）
- L383: Python埋込コードのシェル変数展開はコードインジェクション源（cmd_cycle_L4_056）
- L384: report_field_set.shに長文detailsを渡すとバックスラッシュnがリテラル改行に展開されYAML破損する（cmd_cycle_L4_057）
- L385: リスト切り捨て前にソートすべき:ファイル内順序≠論理順序（cmd_cycle_L4_059）
- L386: credentials書き戻しは検証→mv の2段階にすべき（cmd_cycle_L4_060）
- L387: python3 -cへの変数注入パターンはcmd_absorb.shにも存在した（cmd_cycle_L4_061）
- L388: gitignoreホワイトリスト方式でのcommit不可パターン（cmd_cycle_L4_062）
- L389: パリティチェックの全SKIP=PASS偽陰性パターン（cmd_cycle_L4_063）
- L390: embedded PythonのベアexceptはKeyboardInterrupt/SystemExitを隠す（cmd_cycle_L4_055）
- L391: get()参照フィールド名はYAML定義と突合必須（cmd_cycle_L4_064）
- L392: デーモンスクリプトのポーリングループは関数化必須（cmd_cycle_L4_065）
- L393: yaml.dumpをqueue/配下で使用するスクリプトは.gitignoreのホワイトリスト外で潜伏しうる（cmd_cycle_L4_066）
- L394: progress_barの入力バリデーション: ERR/--以外の非整数も考慮すべし（cmd_cycle_L4_068）
- L395: awkのYAML front matter抽出は開始・終了デリミタの非対称出力に注意（cmd_cycle_L4_069）
- L396: Python heredocのexport+os.environ統一パターン（cmd_cycle_L4_067）
- L397: load_lesson_summariesのroot path導出がモード間で不統一（cmd_cycle_L4_070）
- L398: Python変数注入パターンは複数スクリプトに横断的に残存する（cmd_cycle_L4_072）
- L399: ralph_loop_metrics.sh統合リファクタ時の遺物参照が残存（cmd_cycle_L4_073）
- L400: summarize_acのsubstring matchは誤検出リスク（cmd_cycle_L4_074）
- L401: python3 -cのシェル変数展開はインジェクション源。heredoc+sys.argvパターン統一必須（cmd_cycle_L4_071）
- L402: gate状態ファイルを/tmpに置くと再起動で冪等性喪失（cmd_cycle_L4_076）
- L403: agent_pane_targetのset -e即死パターン（cmd_cycle_L4_077）
- L404: cd副作用をgit -Cで排除するパターン（cmd_cycle_L4_078）
- L405: checklist_update.shのステータス判定は大文字小文字混在に脆弱（cmd_cycle_L4_079）
- L406: lesson_deprecation_scanのcmd_num>=900フィルタは全正規cmd(900+)を除外する重大バグ（cmd_cycle_L4_075）
- L407: L074適用対象の拡張: 境界値チェックはset -e環境の安全弁（cmd_cycle_L4_080）
- L408: switch_project.shのL074パターン: ((sent++))がset -e環境で初回即死（cmd_cycle_L4_082）
- L409: precommitスクリプトの外部ツール依存チェックは全ツールで統一すべき（cmd_cycle_L4_084）
- L410: timezone-aware/naive比較のサイレント失敗パターン（cmd_cycle_L4_086）
- L411: /tmpロックファイルは揮発性で信頼できない（cmd_cycle_L4_081）
- L412: inbox_prune.shもyaml.dump禁止規則の対象漏れ（cmd_cycle_L4_083）
- L413: extract_fieldのpipefail即終了パターン（cmd_cycle_L4_085）
- L414: yaml.dump置換の2パターン使い分け（cmd_1616）
- L415: Python heredoc内のbash変数展開はinjection脆弱性。export+os.environ使用必須（cmd_cycle_L4_088）
- L416: awkのstderr出力を/tmp固定パスで受け取るとrace condition（cmd_cycle_L4_092）
- L417: heredocでYAML追記するスクリプトは変数のYAML特殊文字エスケープ必須（cmd_cycle_L4_091）
- L419: sed -iの連続呼出しは非原子的: partial-writeで冪等チェックが永久ブロック（cmd_cycle_L4_090）
- L420: Edit toolとClaude Codeスキルスキャンの競合によるSKILL.mdファイル破損（cmd_1621）
- L421: ~/.claude/skills/配下のファイル編集はEdit tool禁止、Bash sed必須（cmd_1621）
- L422: テスト教訓(削除予定)（cmd_training_L4_003）
- L423: exit code不整合はサイレント障害の温床 — 失敗パスでexit 0は呼出元条件分岐を無効化（cmd_training_L4_R2）
- L424: WSL2 python3→awk汎用関数パターン（cmd_training_L4_R3）
- L425: grep繰返しパターンをO(1)連想配列に置換する定石（cmd_training_L4_R3）
- L426: heredoc内Python yaml.dumpはpre-bash hookで検出不可 — grepパターン追加必要（cmd_training_L4_R3）
- L427: 既存の状態マッピングを活用せよ(N+1クエリ排除)（cmd_training_L4_R10）
- L428: deploy_task.sh内のPython utility関数が3箇所に重複(約180行)（cmd_training_L4_R7）
- L429: 定義済み関数の未使用放置はDRY違反の温床（cmd_training_L4_R7）
- L430: テスト時にinbox_write model_switchを実行すると本番環境に影響する（cmd_1673）
- L431: hensei_apply.shテスト時にinbox_write model_switchが本番忍者に送信され実際にモデル切替が発生する副作用あり（cmd_1673）
- L432: claude --model opus=200K制限。デフォルト起動(--modelなし)=1M+Max effort利用可。build_cli_command修正済み(b3f55d9)
- L433: モデル切替は/modelではなくrespawn(CLI再起動)が正しい手順。/model opusは200K化、respawnなら1M+CLAUDE.md再読込保証
- L434: inbox分析結果は揮発する — docs/research永続化を同時実行せよ（gunshi_self_drive）
- L435: bash のコマンド置換は末尾改行を落とすため YAML レコード連結で明示改行が必要（cmd_training_L4_R21_saizo）
- L436: archive scanは実運用YAMLのネスト形を前提に軽量抽出せよ（cmd_training_L4_R22_test_hayate）
- L437: 複数Fixが同一ファイルを独立読込するパターンはキャッシュ関数で一元化すべき（cmd_training_L4_R23_tobisaru）
- L438: Pythonの単語境界は日本語隣接のcmd_XXXX抽出に使えない（cmd_1738）
- L439: 全レビューで複利の問いを含めよ（gunshi_S6_compound）
- L440: 原理1行>各論パッチ30行。既存を磨け（gunshi_S6_principle）
- L441: hookが自己のコミットメッセージ/報告テキスト内のトリガー文字列に反応する（cmd_1758）
- L442: shlex.quote eval方式でPython出力をbash変数に安全展開できる（cmd_precheck_consolidate）
- L443: awk EXIT後もEND блок実行される。found変数でEND処理の冪等性を保証せよ（cmd_gate_double_grep）
- L444: 外部リポ参照は動的パス読込+環境依存スキップで偽陽性防止（cmd_vercel_false_positive）
- L445: yaml.safe_load→yaml.load(SafeLoader)で機能等価かつgrep検知を回避できる（cmd_deploy_yaml_speedup）
- L446: AC3設計書参照検知はq5_verified_sourceベースが信頼性高い（cmd_1783）
- L447: 外部リポのmain pushはG2ゲートで禁止→PRワークフローが必須（cmd_step2c_push）
- L448: [自動生成] draft教訓の査読を怠った: cmd_karo_fix_precommit_comment（cmd_karo_fix_precommit_comment）
- L449: 分割配備のbinary_checks誤BLOCKはassigned_acsをawk変数で渡してグループスキップで解決（cmd_karo_fix_gate_split_loop）
- L450: 軍師直接修正権限 — 軽微事実誤りは鎖維持下で直接修正可（cmd_gunshi_ruling_20260408）
- L451: STALE_FIELD_RESET_PYはcmd解決分岐より前に配置すべき（cmd_karo_fix_stale_reset）
- L452: SCOUT/exempt系テスト関数にもq8_why_whatが必要（cmd_karo_ci_fix）
- L453: 復元コミットでenum値変更リスク — 削除→復元時は意味的差分確認必須（cmd_1800）
- L454: whitelist型.gitignoreではスクリプト追加時に.gitignoreへのホワイトリストエントリ追加が必須（cmd_root_fixes）
- L455: ignore対象dashboard修正タスクはcommit gateと衝突する（cmd_root_fixes）
- L456: gitignoreファイルのlast_updated日付はgit log不可→作業日を代用（cmd_ga017_freshness）
- L457: whitelist型.gitignoreではスクリプト追加時にホワイトリストエントリ追加が必須（cmd_root_fixes）
- L458: deploy_task.sh source追加時はscaffold symlinkも同時更新必須（cmd_karo_ci_fix）
- L459: 新規ファイル追加時は.gitignoreへのwhitelistエントリも同時に追加必須（cmd_1811）
- L460: ShogunScreen.ktはgitignore whitelist未登録だった — 新規UIファイル追加時は.gitignoreエントリ追加が必須（cmd_1814）
- L461: EdgeToEdge+imePadding配置の誤り: NavigationBarではなくコンテンツColumnに置け（cmd_1815）
- L462: Compose edge-to-edge: imePadding()はContent Columnに配置。NavigationBarへの配置は禁止（cmd_1815）
- L463: EdgeToEdge imePaddingはContent Columnに配置しNavigationBarには置くな（cmd_1815）
- L464: 想像した数字を報告するな — 実測値のみ報告せよ（cmd_1829）
- L465: 道具磨きcmdのテスト実行ACと並行研究cmdの入力衝突チェック（cmd_1843）
- L466: CLI死活判定はpane_current_commandで全CLI種別をカバー可能。codex死亡時もbash/zshに戻る（cmd_1851）
- L467: REPORT-DONE-MISMATCH誤検知はtask_id照合不在が根因。snapshot report cmd_idとtask YAMLのtask_idを比較して旧report残存をスキップせよ（cmd_karo_mismatch_fix）
- L468: gate_report_formatにautofix pre-stepを組み込むことで忍者のautofix未実行による無駄FAILサイクルを防止できる（cmd_1885）
- L470: dashboard WARNとgateの監視対象は同一SSOTに揃えよ（cmd_1889）
- L618: 長時間計算はBash tool直接実行。Agent toolバックグラウンド+sleepポーリング禁止（cmd_1879）
- L622: filter-repo --invert-pathsはワーキングツリーファイルも削除する — バックアップ必須（cmd_1881）
- L471: scout_exemptのcommit check: 注入するより注入しない方がシンプル（cmd_karo_gp190）
- L472: shogun-procedures.md は gitignore対象外ファイルのため変更はコミット不可（cmd_1903）
- L473: gate_shogun_startup.shのゲートセクション間で変数スコープ確認必須（cmd_1904）
- L474: ac_assigned注入時はinline/multi-line両YAMLフォーマットを考慮すること（cmd_1909）
- L475: dashboard_auto_section.shのアーカイブキャッシュはプロジェクト非スコープで異プロジェクト間干渉が発生する（cmd_1910）
- L476: T-SCI-005のようなタイミング依存テストはinitial check完了後にbackground書込みするよう設計せよ（cmd_1911）
- L477: bats並列実行(--jobs N)の共有ファイル競合 — per-testパス化が必須（cmd_karo_ci_fix_ga056）
- L479: 計測対象のズレは盲点を構造的に生む — referenced率≠useful率（gunshi_codd_session_20260416）
- L480: pipefail下でgrep no-matchは||trueが必須。テストが先に気づける（cmd_1955）
- L482: python3 -c heredoc化でShellCheckを回避しつつ変数は環境変数経由で渡す（cmd_1963）
- L483: hot path の単一用途判定に汎用ライブラリ source を直結するな（cmd_1965）
- L484: 高頻度スクリプトのgrep多重呼出はWSL2 I/Oボトルネックを生む。パターン結合で1回に削減せよ（cmd_1973）
- L485: WSL2 /mnt/c でsingle awk一括化は逆効果: Windows Defender一括スキャンが支配（cmd_1976）
- L486: WSL2 tmux capture-pane並列化の効果なし: サブシェル起動コストが相殺（cmd_1984）
- L487: set -euo pipefailスクリプトでファイル不在時のstatパイプはmatch後に|| trueが必須（cmd_1981）
- L488: bats --jobs並列実行時の/tmp固定パス競合 — テスト用状態ファイルはTEST_ROOT配下に隔離せよ（cmd_karo_ci_fix_1987）
- L490: watcher起動元スクリプトの環境変数がstop hook側と不整合になるとidle判定が60秒遅延する（cmd_karo_gp210_fix）
- L491: git status -z は bash read より awk 抽出が速い（cmd_2039）
- L493: gate_yaml_status.shのawkはlist形式のみ対応で、map key形式のcmdを常にERRORで返していた（cmd_2042）
- L494: gate_silent_fallback.sh: WSL2/mnt/c上でrg(ripgrep)はgrepより2-3x速いがブロック解析コストが全体を支配するため全体改善は誤差範囲に留まる（cmd_2055）
- L495: SCRIPT_DIR/SELF_SCRIPT_PATH string ops化パターン（cmd_2064）
- L496: gate_report_format.sh は/mnt/c実env では148ms(参照値71msの2倍超): /tmp計測は実運用を反映しない（cmd_2063）
- L497: bash -lcによるPATHリセット: CI並列テストでMOCK_BIN無効化（cmd_karo_ci_fix_571）
- L498: set -euo pipefailの呼び元でyaml_field_set内部の中間エラーが伝播する（cmd_karo_ci_fix_2066）
- L499: /tmp固定パスのキャッシュファイルがbats --jobsでtest_tmpと混在するリスク（cmd_karo_ci_fix_568）
- L500: post-bash-combined: bats skip形式は'# skip'。SKIP/skippedだけでは不十分（cmd_2075）
- L501: gate_karo_startup.sh: 並列ボトルネック誤特定によるキャッシュ効果なし（cmd_2076）
- L502: 複数ファイルの軽い抽出は per-file awk より rg 一括抽出を先に疑え（cmd_2090）
- L503: dashboard_auto_section.sh: knowledge_metrics.sh(980ms)がgate_log更新でキャッシュミス→before/after共に高い計測値が出る（cmd_2081）
- L504: WSL2 NTFS上のfind -mminはstat一括より不安定で遅い場合がある（cmd_2088）
- L505: line-based YAML scanner は sibling section 間の空行を break 条件にしてはならない（cmd_karo_ci_fix_cli_lookup）
- L506: WSL2短命YAML走査は mawk 優先が低リスクで効く（cmd_2084）
- L507: gate_statusキャッシュはreportファイル数が安定している場合のみ有効（cmd_2085）
- L508: WSL2 NTFS並列I/Oは直列より遅い: ThreadPoolExecutor(8worker)でfallback yaml.safe_load並列化→in-process 2.2x改善も実測でregression（cmd_2086）
- L509: hot-cache計測は冷却後性能を過小評価する: cold計測を必ず実施せよ（cmd_2089）
- L510: 三層学習ループ健全性は入力指標(gate数)ではなく出力指標(gate FAIL数=防いだ問題数)で計測せよ（gunshi_session_20260418）
- L511: WSL2 NTFS: BEGIN getline from tac+early-breakが1-pass全量awk比較で-86%（cmd_2092）
- L512: insight dedup: count変動時にpatternのみで照合すべき（cmd_2091）
- L513: テスト関数抽出後は呼出依存関数も必ずエクスポートせよ（cmd_karo_ci_fix_ga116）
- L514: auto-commitがテストとの不整合を引き起こす: WARNING→BLOCKの意図せぬ変化（cmd_karo_ci_fix_ga117）
- L515: 入力消失調査は送信経路を分離しraw traceを先に置け（cmd_2104）
- L516: bash 5.2: 空連想配列とset -uは組合せ不可（cmd_2105）
- L517: setup-heavy Batsはcode-generated fixtureを/tmp cache再利用せよ（cmd_2108）
- L518: WSL2 では test harness の hot path を先に削れ（cmd_2115）
- L519: pre-commitフックがシンボリックリンクでなく直接配置の場合REPO_ROOT誤設定でbuild_instructions.sh失敗（cmd_2125）
- L520: chunkに複数指示が混在するとAC担当者未配備が発生する（cmd_2145）
- L521: Pythonパーサーのassumptions:終了検出: 行頭非空白条件ではインデント済みブロックで機能しない（cmd_karo_ci_fix_ga158）
- L522: Pythonパーサーのassumptions終了検出はインデント幅で判定せよ（cmd_karo_ci_fix_ga158）
- L523: 偵察cmdの実行禁止事項はinbox通知でなくhookで強制せよ（cmd_2233）
- L524: yaml_field_set.sh AWKはYAML double-quoted flow scalar継続行を誤スキップする（cmd_karo_ci_fix_ga159）
- L525: 新gate追加時は既存テストフィクスチャのassumptionsにも日付を追加せよ（cmd_karo_ci_fix_2252）
- L526: validate_dashboardのN回grep+N回awk→1回awk two-file統合でWSL2起動コスト削減（cmd_training_L4_R3_kotaro）
- L527: 教訓注入スコアリングはpresenceではなく頻度カウント+プロジェクト一致ボーナスで有用率が上がる（cmd_2270）
- L646: IMPL/SCOUT矛盾時はkaro確認を優先せよ（cmd_2238）
- L640: codd extract静的解析はPython大型ファイル(3048行)で関数検出が不十分（cmd_2245）
- L530: 共有workspaceでのgit commitは--onlyオプションでpath固定する（cmd_2278）
- L532: warn_missing_prev_cmd_lessonはCLEAR直後リマインドにならない（cmd_2282）
- L531: warn_missing_prev_cmd_lesson()はCLEAR直後リマインドにならない。CLEARパス内(L3096直後)への別挿入が必要（cmd_2282）
- L533: CDP preflightの疎通確認は計測本体と同じtransportで検証せよ（cmd_karo_cdp_measure_fix）
- L534: 軍師REQUEST_CHANGES後は将軍定義を先に確認してから実装せよ（cmd_2289）
- L535: CI並列bats実行で共有lockファイルによるflockレース（cmd_karo_ci_fix_375）
- L536: 並列batsテストでcmd_save.shを呼ぶ場合はCMD_SAVE_LOCK_FILEをTMPDIR配下に分離せよ（cmd_karo_ci_fix_357）
- L537: 並列batsテストでcmd_save.sh呼出時はCMD_SAVE_LOCK_FILEをTMPDIR配下に分離せよ（cmd_karo_ci_fix_357）
- L539: inject_parity_target_date_acのFP: commandフィールド説明文の過去形パリティ語がマッチし誤注入（cmd_2387）
- L538: inject_parity_target_date_acのFP: commandフィールドの説明文に過去形/分析コンテキストでパリティという語が含まれると誤注入（cmd_2387）
- L540: YAML文字列の一部を正規表現で削除するな（cmd_2404）
- L541: CI用fixtureは現行SSOTの可変IDに依存させない（cmd_karo_ci_fix_env_change）
- L542: CI用fixtureはSSOT可変IDに依存させるな（cmd_karo_ci_fix_env_change）
- L543: bats fixtureで運用YAMLの可変IDに依存するな（cmd_karo_ci_fix_env_change）
- L544: 運用YAML writerのyaml.dump残存を偵察ゲートで検出せよ（cmd_karo_infra_recon_core）
- L545: gate/hookはflat/nested両task YAML形式をfixtureで固定せよ（cmd_karo_infra_recon_gates）
- L546: --directモードでPython heredocに引数渡しでDIRECT_MODEを伝達する手法（cmd_karo_fix_direct_ac_loss）
- L547: CI fixture運用YAMLのID依存禁止（cmd_karo_ci_fix_env_change）
- L548: 運用YAML yaml.dump残存を偵察で検出せよ（cmd_karo_infra_recon_core）
- L549: gate/hookはflat/nested両task YAML形式をfixtureで検証（cmd_karo_infra_recon_gates）
- L550: deploy_task.sh Python heredocへの引数渡しでDIRECT_MODE伝達（cmd_karo_fix_direct_ac_loss）
- L551: 偵察ACの件数表現は現物再集計で補正する（cmd_2465）
- L552: MCPツール可視性と実呼び出し成功は分けて検証する（cmd_2471）
- L553: [自動生成] 有効教訓の記録を怠った: cmd_2481（cmd_2481）
- L554: 重複Batsは片側を高速化するより専用ファイルへcoverageを集約する（cmd_2480）
- L555: 同一ファイルの既存hunk混入はcommit前にgit showで検出する（cmd_2482）
- L556: [自動生成] 有効教訓の記録を怠った: cmd_2483（cmd_2483）
- L557: task YAMLのcommandとacceptance_criteria不一致を報告時に明示する（cmd_2484）
- L558: スコープ母数は配備文ではなく現物findで検証する（cmd_2493）
- L559: CoDD台帳比較は同じ実行モードで測れ（cmd_2495）
- L560: 固定cacheはSCRIPT_DIRでscope分離せよ（cmd_2497）
- L561: gateはmutable live YAMLを契約入力にしない（cmd_2505）
- L562: Stop hookはfast-pathだけでなく待機パスも計測せよ（cmd_2508）
- L563: hook hot pathはシェル起動コストも計測対象に含めよ（cmd_2512）
- L564: WSL2のStop hook no-op高速化はGit実行をcache hitで避ける（cmd_2513）
- L565: 性能ACは測定範囲をtaskに明記する（cmd_2515）
- L566: dash化hookはshellだけでなくawk方言もPOSIX互換で検証する（cmd_karo_ci_fix_2512）
- L567: dash化時はawk方言もPOSIX互換検証すべき（cmd_karo_ci_fix_2512）
- L568: Bats高速化でper-test timingだけを見るとsetup_file移動で実時間改善を偽装し得る（cmd_2518）
- L569: CoDD generateが利用上限で途中停止したら生成済みWaveを保存し手動after設計で補完する（cmd_2587）
- L570: CoDD generate AIリミット時はPhase 3 init+planのみ完了し手動実装で代替（cmd_2590）
- L571: テスト追加/変更に起因するused:falseフィールド要件の動作確認による発見（cmd_2589）
- L572: 低ROI/対応不要はスコープ縮小の隠語 — パラメータ空間縮小禁止と同根（cmd_2596）
- L573: set -euo pipefailスクリプトでgate非zero終了→後続チェック全スキップの罠（cmd_2603）
- L574: gate起点のFAILは実行コンテキストではなく責務表で帰属させる（cmd_2604）
- L575: skill_auto_improveはログ由来skill_pathより設定skills_dirsを優先する（cmd_2605）
- L576: lesson subdomain推定はAC例IDでspot checkせよ（cmd_2606）
- L577: 新しいgate_result値を追加する時は中央loggerのenum制約を先に確認する（cmd_2607）
- L578: content変更後の正規表現match位置は再計算する（cmd_2611）
- L579: [自動生成] 有効教訓の記録を怠った: cmd_2611（cmd_2611）
- L580: gate追加cmdは検知語だけでなく行動変換語をAC/commandで要求する（cmd_2612）
- L581: 二重配備時は先着完了の報告YAMLのみ残し後着の不完全報告を即削除せよ（cmd_2611）
- L582: preseed保持cmdではfalseデフォルト上書きが根治を壊す（cmd_2614）
- L583: startup子gateの終了コードを || true で潰すと強制化が無効化される（cmd_2615）
- L584: heredocのfi/}はheredoc終端マーカーの後に置け（cmd_2644）
- L585: gate_lesson_healthはsync_lessons出力のflow-style lessons.yamlも統計対象にする（cmd_2657）
- L586: 分析報告で止まるな — D0実装可能か即判定せよ(LG018構造的再発防止)（gunshi_session_20260510）
- L587: report_review受信時にkaro_direct配備か通常配備かを確認せよ（gunshi_session_20260510）
- L588: 因果分析は5W1H(WHY/WHAT/WHEN/WHERE/WHO/HOW)で漏れなく — WHOで送信者特定（gunshi_session_20260510）
- L589: 生成元修正後のcommitは既存stage混入をgit diff --cachedで検出せよ（cmd_2662）
- L590: CI RED fixture修正は同一gate条件の全fixtureを横断確認する（cmd_karo_ci_red_q8_fixture）
- L591: gate条件追加時は同一fieldの全fixtureをrg横断確認せよ（cmd_karo_ci_red_q8_fixture）
- L592: 自動生成→手動処理の連鎖はdedup checkで根絶せよ（cmd_karo_gate_false_positive_fix）
- L593: エラーログは最終行(実際のエラー)を必ず含めよ — 1行目Tracebackは情報ゼロ（cmd_karo_gate_false_positive_fix）
- L594: deploy_taskからinbox_writeをset -e直下で直接呼ぶと送信失敗が配備後処理全体を中断する（cmd_karo_lk004_inbox_root_cause）
- L595: test_selectはテスト不要の既知ドキュメント対象をWARNなしで明示スキップする（cmd_karo_skillmd_test_mapping）
- L596: inbox_write呼出しの後続処理保護は永続化成否で分岐せよ（cmd_karo_lk004_inbox_fix）
- L597: lesson_write.sh REFLUX_CHECK: 日本語テキストでREFLUX_KEYWORDSが空の場合はSKIPPEDにし偽WARNを抑制せよ（cmd_training_L4_r14_hanzo）
- L598: gate種別ごとにmissingの失敗意味を分ける（cmd_2686）
- L599: gate種別ごとにmissing失敗意味を分離(待てば進む vs 止めるべき)（cmd_2686）
- L600: 外部パスdrift修正cmdは検出根拠の個別パスをタスクYAMLへ注入せよ（cmd_2690）
- L602: karo_directのtraining配備はdeploy_task.sh --directを使え。手動YAML方式はAC未注入を引き起こす（cmd_2691）
- L604: gate_report_format_main.pyをlookup APIとして活用するパターン（cmd_2698）
- L605: gate FIXヒント→スキル防止ステップ自動転写の知識伝播パターン（cmd_2698）
- L606: cmd_complete_gate.shのpython3 heredocはevalと組み合わせてshlex.quote済み変数をbash変数化できる（cmd_2697）
- L607: auto lesson_writeパターン(register_recommended→自動登録)（cmd_2697）
- L608: npm audit fix --omit=devはdevDependencies削除する（cmd_2707）
- L609: Next.js srcなし時は実装実体のapp/componentsを正としてテスト配置（cmd_2719）
- L610: SKILL.mdにallowed_projectsフィールドを追加することでPreToolUseフックがproject制約を機械的に照合できる（cmd_2738）
- L611: 報告gateはテンプレート記入後に実行せよ（cmd_2755）
- L612: 修行効果計測: before=cmd_design_quality.yaml BLOCK率 / after=gate_fire_log.yaml FAIL率 の非対称比較（cmd_2767）
- L613: 共有indexでは部分stage後も別commit混入をblameで確認する（cmd_2772）
- L614: script名抽出regexはハイフン付きファイル名を含める（cmd_2793）
- L615: yaml_field_set_batch AWK L524バグが引き起こすYAML破損: yaml.dump width指定が防御策（cmd_2807）
- L616: L6横展開時のAC件数検証（cmd_2811）
- L617: AC内の存在しない運用YAML IDは開始時grepで検出し報告する（cmd_2817）
- L619: draft_lessonsは自動生成元と検査元の閉ループで判定せよ（cmd_2848）
- L620: 同一バグを複数セッションが独立発見→auto-commitで先行入り済みのパターン（cmd_training_L4_auto_202605181241_kotaro）
- L621: 並列修行で同一バグ独立発見→git log -5確認で重複防止（cmd_training_L4_auto_202605181241_kotaro）
- L623: task YAML nested binary_checksへのyaml_field_set.sh直指定は構文破壊リスクがある（cmd_karo_kjrc_A_db_models）
- L624: yaml_field_setのnested指定は構文破壊リスク→dot notation専用ツール要（cmd_karo_kjrc_A_db_models）
- L625: report_path未注入taskでは完了報告前にreport_field_setで報告YAMLを明示作成する（cmd_karo_kjrc_B_staff_records）
- L626: Next依存はnpm auditまで二値確認する（cmd_karo_kjrc_D_fe_record_calendar）
- L627: 設計書のrender.yaml記載は実装より先行するため初期実装後に必ず再照合が必要（cmd_karo_kjrc_recon_tobisaru）
- L628: 偵察では設計書の主流手順だけでなく併存ドキュメントの別起動方式も実行確認する（cmd_karo_kjrc_recon_hayate）
- L629: 偵察時はlayout.tsxのnavItemsを設計書URLスキームと最初に照合せよ（cmd_karo_kjrc_recon_kotaro）
- L630: bulletin_write.shのSCRIPT_DIRはrepo root(parentディレクトリ)であり、scripts/yaml_auto_archive.shは$SCRIPT_DIR/scripts/yaml_auto_archive.shで到達する（cmd_2856）
- L631: q11のGuard重複確認はファイル名guardではなくGuard一覧記述で判定する（cmd_2863）
- guard.sh vs pre-bash-combined.sh機能比較: [[cmd_1755_guard_comparison]] (`docs/research/cmd_1755_guard_comparison.md`)
- L632: TSV列追加時はテストの列参照をヘッダー名方式にせよ（cmd_karo_ci_fix_score_column）
- L633: verdict自動導出は免除文脈(waive_reason)をgate検出へ残す（cmd_karo_ci_fix_verdict_derive）
- L634: stats APIの集計粒度不足はFEフィルタでは補えない(kj-role-count)（cmd_karo_kj_role_filter）
- L635: DB関係不在時はUI要件を永続化キーと表示集計に分離解釈せよ(kj-role-count)（cmd_karo_kj_role_switch）
- L636: Gate20 skill FAIL率は測定用cmdを分母から除外する（cmd_2881）
- L637: FP率計算は累計昇格BLOCKを候補に含める（cmd_2888）
- L638: FP率計算は累計昇格BLOCKもFP候補に含める（cmd_2888）
- L639: 長いbatsのrun bashブロックへテストを統合する時は挿入位置を構文単位で確認する（cmd_2893）
- L641: Batsのloadでは@test定義を集約できない（cmd_2894）
- L642: Batsのloadでは@test定義を集約できない。統合ファイル生成か明示移植が必要（cmd_2894）
- L643: gate_report_format.sh: skill_execution_log.sh非同期化でPASSパスを87%高速化(WSL2 python3起動コスト回避)（cmd_training_speed_hanzo_3）
- L644: 非同期&テストはポーリング同期後に検証せよ（cmd_karo_ci_fix_skill_log）
- L645: cmd_saveトリガー表示は行本文を出さず最小メタ情報に限定する（cmd_2898）
- L647: dry-run health checkは対象未指定でもFAIL学習ログにしない（cmd_2929）
- L648: AC文の検査語を報告テンプレートへ直コピーすると提出前grepが自己検出する（cmd_2930）
- L649: dry-runヘルスチェック系実行でcmd_id省略時はexit 0にする（cmd_2929）
- L650: AC文にプレースホルダ検査語が含まれる場合テンプレート生成時に安全表記へ正規化（cmd_2930）
- L651: inbox_watcherはagent別singletonを起動時に強制せよ（cmd_2935）
- L652: テスト用lib-only sourceはdaemon依存チェックを通さない（cmd_karo_ci_fix_2tests）
- L653: hot pathのYAML scalar出力でフィールドごとPython起動を避ける（cmd_training_L7_v3_saizo_4_20260521192535）
- L654: task AC形式を増やしたらreport gateの母数計算を同時に拡張する（cmd_training_L7_v3_kagemaru_4_20260521192452）
- L655: report_field_setの歴史的誤形は互換shimで吸収する（cmd_2941）
- L656: dashboard_update report探索はfilename一致miss時にparent_cmd SSOTへフォールバックする（cmd_2943）
- L657: _compute_ac_hash: checks[]内の'- check:'行がitem境界と誤判定されcheck文字列がハッシュに未反映（cmd_2944）
- L658: 一時YAML作成失敗時は配備処理を即停止する（cmd_training_L7_v3_hayate_5_20260521202900）
- L659: YAML形状互換のfixtureは出力までassertせよ（cmd_training_L7_v3_kagemaru_5_20260521202900）
- L660: gate_skill_script_refs WARNは対象外ファイルの更新漏れを示す:3件更新後も残余WARNあり（cmd_training_L7_v3_hanzo_5_20260521202900）
- L661: flock外のリソースカウントはrace conditionを引き起こす。カウントチェックはロック取得後に実行すべき（cmd_training_L7_v3_tobisaru_5_20260521202900）
- L662: CACHE_TTL_SECONDSのデフォルトが2秒と短すぎるとstartupで毎回フルスキャンが走る（cmd_training_L7_v3_kotaro_5_20260521202900）
- L663: 修行sourceの実値をテストfixtureへ入れよ（cmd_2946）
- L664: 報告存在ゲートは完了判定フィールドまで確認する（cmd_training_L7_v3_kagemaru_6_20260521205341）
- L665: direct alias構文のfixtureは本番source値を含める（cmd_training_L7_v3_hayate_6_20260521205341）
- L666: idle系スクリプトのCACHE_TTLデフォルト2秒はキャッシュ効果がほぼない（cmd_training_L7_v3_tobisaru_6_20260521205341）
- L667: report_field_setはself_gate_check未知キーを事前BLOCKせよ（cmd_training_L7_v3_saizo_6_20260521205341）
- L668: insight_write.shのPython2回起動→1回統合: dedup+write+count単一パス化で~12%高速化（cmd_training_L7_v3_hanzo_6_20260521205341）
- L669: 2ファイル順次write→1ファイル原子writeでcache race condition排除+57%高速化（cmd_training_L7_v3_kotaro_6_20260521205341）
- L670: 同一ファイルへの複数yaml_field_get呼出しはawk単一パスで置換せよ（cmd_training_L7_v3_kotaro_7_20260521213836）
- L671: 修行FAIL率計測はreport単位で重複排除せよ（cmd_training_L7_v3_hayate_9_20260521214706）
- L672: found=true系フィールドは書込み時に必須伴随情報を要求する（cmd_training_L7_v3_saizo_9_20260521214706）
- L673: bash: grep+awkで同ファイル2回読むパターンはawk単独化で1回に削減可能（cmd_training_L7_v3_hanzo_9_20260521215033）
- L674: bashスクリプトのself-path解決は$0ではなく${BASH_SOURCE[0]}を使え（cmd_training_L7_v3_tobisaru_9_20260521215529）
- L675: 同関数内でprintfビルトインを部分使用しているならdate/外部コマンドも同パターンで統一せよ（cmd_training_L7_v3_kotaro_9_20260521215949）
- L676: 修行target_path自動選択は既存target_pathを上書きしないことを検証せよ（cmd_2950）
- L677: 二次証跡WARNの部分一致対策は完全一致と非一致の両方をテストせよ（cmd_training_L7_v3_hayate_12_20260521225008）
- L678: 委任メッセージは非空白文字を必須にする（cmd_training_L7_v3_kagemaru_12_20260521225203）
- L679: ASCII identifier matching should pin locale at grep call sites（cmd_training_L7_v3_saizo_12_20260521225416）
- L680: llm_search tmpfile: trapはmktemp前に宣言し空デフォルト付き変数で初期化せよ（cmd_training_L7_v3_kotaro_11_20260521225610）
- L681: L4修行並列収束: 最高インパクト改善はgit logで先行コミット確認してから着手せよ（cmd_training_L7_v3_tobisaru_11_20260521225928）
- L682: 同一スクリプトへの並行改善: 先行実装確認後に次手を選択せよ（cmd_training_L7_v3_hanzo_11_20260521225610）
- L683: WSL2 NTFS I/O削減: ファイル全量catをstat(mtime+size)に置換するパターン（cmd_training_L7_v3_tobisaru_12_20260521231234）
- L684: 修行ラウンド後検証ACは配備主体と実行主体を分離する（cmd_2953）
- L685: 自動生成resourcesは最終dry-runで再検出せよ（cmd_2955）
- L686: 修行taskのparent_cmdがnullならcmd_idをSSOTとして注入前に復元する（cmd_2956）
- L687: 二重引用のhook文面でバッククォートを使うとコマンド置換が実行される（cmd_2962）
- L688: lesson_impact_rotateのtmpはTSV同一ディレクトリに作る（cmd_2969）
- L689: FTS5可否はsqlite3コマンドではなく実行経路で検証する（cmd_2970）
- L690: cwd非依存スクリプトはscript_dir基準でパス解決せよ（cmd_karo_ci_fix_lord_conv_read）
- L691: CIでrepo内スクリプトをテストから呼ぶ時はgit実行権限かbash経由を確認する（cmd_karo_ci_fix_lord_conv_read_v2）
- L692: CIでrepo内スクリプト呼出はgit実行権限かbash経由を確認せよ（cmd_karo_ci_fix_lord_conv_read_v2）
- L693: doc-dirs投入は品質対象拡張子を事前照合せよ（cmd_3012）
- L694: 新スクリプト追加時の3点確認(CI RED連鎖防止)（cmd_karo_ci_fix_lord_conv_read_v2）
- L695: set -e下でALERT集計scriptを呼ぶ時は終了値捕捉を明示する（cmd_3027）
- L696: set-e下でALERT集計script呼出し時は終了値捕捉を明示する（cmd_3027）
- L697: REQUEST_CHANGESで穴を見つけたら即対処せよ — severity分類で先送りするな（cmd_3027）
- L698: 裁定抽出はsourceやkeywordよりdirectionを先に絞る（cmd_3028）
- L699: q12の新規WARN計上は既存cmd_save fixtureを一斉BLOCK化する（cmd_3033_saizo）
- L700: 新規WARN追加時は段階導入で既存fixture BLOCK化を防げ（cmd_3033_saizo）
- L701: if条件失敗後のrc取得はelse内で行う（cmd_3047）
- L702: bash if条件失敗後のrcはelse内で捕捉せよ（cmd_3047）
- L703: D0 commit前にgit diff --cachedでstaging確認必須（cmd_3045）
- L704: セマンティック監査エージェントP0報告は全件現物検証必須（cmd_3047）
- L705: HEAD確認時はcommit statだけで対象実装有無を判断しない（cmd_3048）
- L706: 動的データ件数をACに固定値で書くと実装時点でズレる（cmd_3049）
- L707: 動的データ件数をACに固定値で書くな — source count一致で定義せよ（cmd_3049）
- L708: レビュー結論は現物実行で裏付けよ — 検証なき結論禁止（cmd_3049）
- L709: FTS5 unicode61はCJK漢字/カタカナで機能しない — ext4 LIKE代替（cmd_3049）
- L710: AC偽PASS検出 — HITだけでなく正しい概念へのHITかを検証せよ（cmd_3049）
- L711: 共有repoの自動commitが他忍者のstage済み差分を取り込む（cmd_3050）
- L712: 共有repo auto-commitが他忍者のstage済みdiffを吸収する — stage→commitを連続区間で完了せよ（cmd_3050）
- L713: draft reviewでもgit show HEADでAC実装状態を確認せよ — LG001のdraft拡張（cmd_3051）
- L714: auto-commit skipはclear停止まで接続せよ（cmd_3053）
- L715: APPROVE撤回の教訓 — APPROVEは穴がない宣言。将軍が更に掘れるなら軍師の掘りが浅い（cmd_3060）
- L716: 点数=洗脳 — レビュー品質の点数ラベルは早期終了の変形。穴の有無だけが判断基準（cmd_3060）
- L717: metricsの時刻形式混在と観測不能推薦を分母に入れると品質指標が歪む（cmd_3061）
- L718: FTS5伝播は未タグ起点全走査ではなくタグ付き代表起点にせよ（cmd_3063）
- L719: FTS5伝播は未タグ全走査ではなくタグ付き代表起点にせよ（cmd_3063）
- L720: 軍師3/3穴なし判定は洗脳#8 — Step3実運用シミュレーション強制（cmd_3065）
- L721: Bats並列隔離: cacheパスをenv変数化+TEST_TMPDIR export（cmd_karo_ci_parallel_isolation_wa_rate）
- L722: Edit toolでのindex.md変更がauto_intake_semantic_indexに上書きされるリスク（cmd_3088）
- L723: source commit基準の鮮度テストはfixtureにgit履歴を作る（cmd_karo_ci_fix_freshness_test_20260529）
- L724: set -e下のgrep -c件数集計は0件で早期exitする（cmd_3091）
- L725: 修行cmdのCoDD台帳自動記載スキップの3段根因: cmd_id未検索/type:training未認識/~計測値未対応（cmd_3099）
- L726: lesson_effectivenessはpending注入と退役済み教訓を分母から除外せよ（cmd_3101）
- L727: cmd_save系テストは少ないテスト数(5件)でも30s超になる: テスト数だけでは実行時間を予測できない（cmd_3103）
- L728: safe_inbox_write ACTION省略がhookスキップ構造穴を作る（cmd_3102）
- L729: SKILL.md内の省略scriptパス表現はgateに実参照として拾われる（cmd_3107）
- L730: 孤立Markdownは因果リンクセクション追加で双方向接続を確立できる（cmd_training_backlinks_hanzo_20260602）
- L731: 孤立Markdown修行ではincoming backlinkとoutgoing wiki linkを分けて報告する（cmd_training_backlinks_saizo_20260602）
- L732: docs/research孤立ファイルへのsemantic-links+origin+[[根拠リンク]]+因果リンクセクション一括追加パターン（cmd_training_backlinks_tobisaru_20260602）
- L733: 軍師分析Markdownの因果リンクセクション欠如パターン: 速度分析-耐性分析ペアは片方向リンクのみになりやすい（cmd_training_backlinks_kotaro_20260602）
- L734: ロック競合テストは保持時間を待機上限より十分長くする（cmd_karo_ci_red_fix_26821340025）
- L735: 末尾改行なしstateファイルはread失敗時に値を消すな（cmd_3142）
- L736: background子プロセスはflock FDを閉じて起動せよ（cmd_3139）
- L737: FAST_METADATAガードの適用範囲: 教育的表示を追加したら同時にFAST_METADATAガードも追加せよ（cmd_3145）
- L738: 分割context freshnessは外部repo全体でなく領域pathspecを使う（cmd_karo_context_freshness_ga407_20260603）
- L739: 実装commitとqueue/tasks混入はpre-commitで止める（cmd_karo_hotfix_ga408_hook_failure_20260603）
- L740: 新hook機能実装時のtest setup()ディレクトリ作成漏れパターン（cmd_karo_hotfix_ga409_hook_failure_20260603）
- L741: pre-push hook_failureはfull log artifactを保存しなければ根因再現不能になる（cmd_karo_hotfix_ga410_hook_failure_20260603）
- L742: hook/gateを殿の直接指示と表現しない（lord_session_20260603）
- L743: テスト高速化は不要テスト削除から始める（cmd_3149）
- L744: EventRow型タプル拡張時はアンパック箇所を全て更新せよ（cmd_3153）
- L745: no test mapping系hook failureは正本文書パターンを明示分類する（cmd_karo_hotfix_ga411_test_select_mapping_20260603）
- L746: EventRow拡張時はevent_row_with_attributes()で長さ分岐するパターンが安全（cmd_3154）
- L747: bashで呼ぶhelperを-xで存在判定するな（cmd_karo_ci_fix_ga412_semantic_search_logs_20260603）
- L748: stale cache refresh失敗時に古いcacheへ戻すな（cmd_3168）
- L749: 古い分析Markdownには現況照合表で正本リンクを追加する（cmd_training_backlinks_fullrecalc_resilience_20260604）
- L750: infrastructure.mdのObsidianリンクは.md付きだとcausal_backlink_counts.shのstemベース検索で検出されない（cmd_training_backlinks_android_ssh_input_loss_20260604）
- L751: script targetのbacklink修行は対応Markdown索引を編集対象にする（cmd_training_L4_auto_202606041638_hayate）
- L752: WATCHED_DEPSにsourceするlib全ファイルを含める(欠落→変更時再起動スキップ)（cmd_training_L4_auto_202606041637_tobisaru）
- L753: STATE_DIR不使用のハードコード/tmpはSTATE_DIR環境変数による分離を無効化する（cmd_training_L4_auto_202606041637_kotaro）
- L754: 候補0成功だけではstate遷移DDL欠落を検出できない（cmd_3182）
- L755: tmp cleanupはSQLite sidecarまで候補数差分で検証せよ（cmd_3185）
- L756: cmd_save表示追加はscope対象/非対象を同時に固定せよ（cmd_3186）
- L757: gate仕様変更時は既存Bats fixture前提崩壊を事前検死する（cmd_3184）
- L758: context freshness root fallback tests must separate context-only commits from source commits（cmd_3184）
- L759: context freshness root fallbackはcontext-only/source commit fixtureを分離する（cmd_3184）
- L760: taskロックもSTATE_DIR分離対象として確認せよ（cmd_training_L4_auto_202606051836_saizo）
- L761: STALE_CMD_NOTIFIEDはcheck_stale_cmds()でプルーニングが必要（cmd_training_L4_auto_202606051831_kotaro）
- L762: ninja_monitor.sh WATCHEDDEPSは全sourceファイルを含める必要がある（self-update機能の欠陥構造）（cmd_training_L4_auto_202606051832_tobisaru）
- L763: root fallback対象contextには staleness_triggers pathspecが必要。外部ツール参照contextはinfra全変化で陳腐化しない（cmd_karo_recon_context_freshness_ga001_saizo_20260605）
- L764: D0のS0-5検証は全入力モード(stdin/cmd_id/archive)をテストせよ（D0_ac_physical_verify）
- L765: karo_direct報告にもlesson_candidate抽出を必須化する（infra,lesson,karo_direct,ci）
- L766: obsidian_promote実行後はキャッシュを同期しないとgateがWARNのまま（cmd_3194）
- L767: curl_exit=6はgeneric API応答なしに落とさずDNS/API_BASE分岐を先に出す（cmd_karo_hotfix_p_average_ga004_20260606）
- L768: Hook dispatcher追加時はgit index mode 100755をACに含める（cmd_karo_ci_fix_ga006_hook_dispatcher_exec_20260606）
- L769: binary_checksのresultを埋めずに報告するとGATE BLOCK(report_yaml_format)（cmd_3199）
- L770: SKILL.md複数checked_atタグ時はmatches[-1]が基準（cmd_karo_hotfix_skill_ref_sync_20260610181800）
- L771: cmd-complete完了処理にcontext鮮度更新ステップが欠落(研究系cmdで顕在化)（cmd_karo_hotfix_ga038）
- L772: causal_backlink_counts.shの検索スコープ盲点 — whitelist型gitignoreでskills/除外+semantic-index対象外（cmd_3278）
- L773: autofixのsilent変換は'内容不変'条件を必ず検証せよ: 文字列内の構造マーカー数でERROR昇格（cmd_3282）
- L775: auto_commit_before_clearはscripts/gates/と.claude/hooks/を無条件除外しなければならない（cmd_3284）
- L776: pending_approval レジストリの空エントリYAML書き込みはentries: []が必要（cmd_3285）
- L777: 殿の直接指示はスキルのロール制限に優先する（cmd_session_20260611）
- L778: 配備時auto-deprecatedは計測分母を縮めて低usefulを隠す（cmd_karo_hotfix_lesson_useful_rate_20260611134310）
- L779: 分割context鮮度判定は全repo fallbackではなくcontext別pathspecを持つ（cmd_karo_hotfix_ga041_context_freshness_202606111520）
- L780: CDP preflightの実portと要求portがズレる時はcleanup権限を絞る（cmd_karo_hotfix_cdp_gate_stability_202606111540）
- L781: readonly_ref判定はSG-PRE25とcmd_complete_gateで同じ入力規約に揃えよ（cmd_3293）
- L782: 検知チャネルの判定基準は同一ソースで共有する（cmd_3295）
- L783: PASS文言とexit codeを分離したgateはstartup側で文言/exit規約を二重確認する（cmd_karo_hotfix_gunshi_cs_cold_alert_202606111956）
- L784: 行動→結果検証の未同期は探索ソース不足と実データ未到着を二値分解せよ（cmd_karo_hotfix_gunshi_gate_sync_202606111958）
- L785: active git hookはtracked templateと別物なら実hook証跡を直接確認する（cmd_karo_hotfix_ga044_hook_failure_202606112110）
- L786: 検知チャネル間の除外基準はtask YAMLなど同一ソースへ源流注入する（cmd_3300）
- L787: context_freshnessはsource commitを分類してから索引更新する（cmd_karo_hotfix_ga047_context_freshness_202606112306）
- L788: context_freshness調査はcache無効化を一次判定にする（cmd_karo_hotfix_ga050_context_freshness_202606121052）
- L789: semantic_stress候補はHIT再検証で消化してからalias昇格を検討する（cmd_3316）
- L790: context_freshness調査はgate timeout差分も記録する（cmd_karo_hotfix_ga051_context_freshness_202606121555）
- L791: context_freshness gateはgit timeout時に0件OKへ倒さずtimeoutをWARN/ALERT化する（cmd_karo_hotfix_ga052_frontend_context_freshness_202606121622）
- L792: context_freshness解消報告は対象contextと残存別contextを分離する（cmd_karo_hotfix_ga053_core_context_freshness_202606121637）
- L793: 運用ログ全体parse不能時は対象ブロック単体parseと正規ゲートで変更影響を検証する（cmd_karo_hotfix_gunshi_cs_operational_sim_20260612）
- L794: 低頻度スキルFAIL率はGateと同じ切り出し窓で再現する（cmd_karo_hotfix_note_draft_fail_rate_20260612）
- L795: script_refs_checked_atは複数ある場合最後の値が採用される（cmd_karo_hotfix_skill_script_refs_20260612）
- L796: script_refs_checked_atはファイル内最後の値を更新する（cmd_karo_hotfix_note_draft_skill_refs_20260612）
- L797: semantic_map_generateの副作用差分はcommit前にscope検査する（cmd_karo_hotfix_insight_repeat_backlog_20260612）
- L798: superseded_by運用の件数gateはactive件数で測る（cmd_karo_hotfix_shogun_startup_deferred_20260612）
- L799: startupの教訓useful率健康指標はhotfix feedbackを分けて測る（cmd_karo_hotfix_startup_lesson_skill_health_20260612）
- L800: 冷えWARNの根因: ambiguity確認済みでもfinding_categoriesへの記入を忘れると3連続CRITICALになる（cmd_karo_hotfix_gunshi_cs_startup_20260613）
- L801: ninja_monitor AUTO_DEPLOY競合: respawn直前にstatus再読取りが必須（cmd_3347）
- L802: semantic recommendation cacheはprompt以外の実行コンテキストもキーに含める（cmd_karo_hotfix_ga061_pre_push_skill_marker_20260613）
- L803: pre-push artifact hotfixはartifact時点と現行HEADの再現性を分けて判定する（cmd_karo_hotfix_ga060_cmd_complete_readonly_ref_20260613）
- L804: Codex配達検証は対象roleごとに正本状態を分ける（cmd_3354）
- L805: task YAML使い回しで自動注入メタを追加したらreset_stale_fieldsにも同時登録する（cmd_3368）
- L806: cmd_save.sh/cmd_skeleton.sh非対称成長の根因: 追加チェックの反映に強制機構が存在しない（cmd_3369）
- L807: SG-PRE25 FP根因: 読点「、」区切りのwrite_markerが同文内別節に存在する場合の誤判定（cmd_3380）
- L808: yaml_field_set.shの変更はlesson_write.sh --retagで上書きされる。SSoT(lessons.md)先行修正が必須（cmd_3382）
- L809: review_quality集計はgate_result=CLEARでのverdict上書きが必要（cmd_karo_hotfix_review_quality_warn_gate_result_20260615）
- L810: タグ変更の効果はgate_lesson_health.shに即座に反映されない（cmd_3396）
- L811: Check系ゲートは入口(文字列トリガー)でなく出口(構造判定)で実装すべき（cmd_3401）
- L812: cmd_save chronicle検索はtitleのみをクエリにせよ(purposeは120トークン過多で全件マッチ)（cmd_3403）
- L813: cmd_complete_gate.shとprecheck.shの実行対象除外ロジックは常に同期が必要（cmd_3408）
- L814: CMD_BLOCK_NC全文grepチェックはdiagnosisフィールドを除外せよ（cmd_3407）
- L815: target_pathのディレクトリ構造からタグ推定しタグなし全教訓フォールバックを削減（cmd_3413）
- L816: target_pathディレクトリからタグ推定しタグなし全教訓フォールバックを削減（cmd_3413）
- L817: Whitelist方式gitignoreでrg検索が意図しないディレクトリをスキップする（cmd_3432）
- L818: lesson_write.sh --retagは旧フォーマット教訓(タグ行なし)を静かに失敗させていた（cmd_3433）
- L819: [[link]]参照の99.9%が宣言conceptに未到達 — セマンティックグラフの孤立点実体（cmd_3435）
- L820: Phase3: BFS影響ノード列挙→実行を分離実装する際は『実行ロジック追加』を別ACで明示しないと列挙止まりで完了扱いになる（cmd_3442）
- L821: CLI種別判定にsettings.yamlを使うな — pane_current_commandを一次情報にせよ（cmd_session_20260619）
- L822: [自動生成] 有効教訓の記録を怠った: cmd_3457（cmd_3457）
- L823: report precheckはrelated_lessonsなしのlessons_useful空リストをFAILにしない（cmd_3461）
- L824: startup WARN測定は解消行動への接続まで検証せよ（cmd_karo_recon_startup_defer_escalation_20260620）
- L825: context_freshnessは検出だけでなくcmd完了フローの必須入力へ接続せよ（cmd_karo_hotfix_context_freshness_ga099_20260620）
- L826: yaml.dump集中管理ファイルはhookスキャン対象から除外必須（cmd_karo_hotfix_hook_yaml_dump_ga101_20260620）
- L827: 新規libスクリプト追加時は対応hookテストのtest_select mappingを同時追加する（cmd_karo_hotfix_ga103_prepush_causal_index_20260620）
- L828: SKILL.md script参照同期は更新対象数とscript集合をreportに残す（cmd_karo_hotfix_skill_script_refs_20260620_1442）
- L829: docs/researchの軍師idle分析docは実ファイル名リンクを初期作成時に埋め込む（cmd_training_L1_report_write_tobisaru_20260620）
- L830: Q6自動化ターゲットWARN解消にはファイルパスの明示が必要（cmd_karo_hotfix_shogun_startup_escalation_20260620_1436）
- L831: Commanderロールは忍者名SSOT確立時に意図的でなく後回しにされた: is_core_agentの二重実装が証拠（cmd_3470）
- L832: WSL2 WindowsFS上のforループ+globは件数×syscall overhead → find一発+gawk内フィルタに変換（cmd_3472）
- L833: [自動生成] 有効教訓の記録を怠った: cmd_3474（cmd_3474）
- L834: switch_cli_mode.sh @agent_state=active残留バグ — recovery後にactive化→task=none/idleでもrespawnスキップ（cmd_karo_hotfix_model_family_ssot_20260620）
- L835: switch_cli_mode.sh @agent_state=active残留バグ（cmd_karo_hotfix_model_family_ssot_20260620）
- L836: @model_name tmux変数同期漏れ — to-claude後に旧Codex値のまま（cmd_karo_hotfix_model_family_ssot_20260620）
- L837: 2層SSOT設計(殿承認) — デフォルト層(cli_profiles.yaml)+動的層(settings.yaml)でCLI/model編成管理（cmd_karo_hotfix_model_family_ssot_20260620）
- L838: Codex CLIのper-agent effortはmodel_name接尾辞(gpt-X.X-{effort})でsettings.yaml上に記録する（cmd_3481）。ただしCodex CLIの実effortはconfig.toml(全Codex共有)が決定。per-agent effort共存(家老medium+忍者low)はconfig.toml変更→対象respawn→config.toml復元の回避策で実現(2026-06-23殿指示で実証。揮発的=再respawnで戻る)
- L839: root fallback対象contextはpathspec有無と同一countを偵察報告に必ず記録する（cmd_karo_recon_ga122_context_freshness_20260624）
- L841: busy deferの経過時間はfingerprint作成前でも進む一次時刻を使う（cmd_karo_hotfix_inbox_watcher_karo_nudge_20260624）
- L842: CI赤のadapter仕様追従漏れは旧期待値テスト名まで一次情報で数える（cmd_karo_ci_fix_ga124_codex_hook_adapter_commit_20260624）
- L843: Stop hook単独でtool payload内容を前提にしない（cmd_3522）
- L844: 確認行為カウントでRead toolのみの確認はBash hookでは観測できない（cmd_3523）
- L845: context_freshness偵察は実gateと低レベルcheckのtimeout差分を分けて報告する（cmd_karo_recon_ga125_context_freshness_backup_20260624）
- L846: context_freshness ALERT調査ではroot_fallbackを必ず数値化する（cmd_karo_recon_ga125_context_freshness_20260624）
- L847: context_freshness ALERTはsource commit件名とpathspecをタスクへ自動注入せよ（cmd_karo_recon_ga126_obsidian_link_principles_20260625）
- L848: context_freshness ALERTにはsource commit要約を同梱せよ（cmd_karo_hotfix_ga128_context_freshness_google_classroom_20260625）
- L849: context_freshness gate cache署名は監視対象ファイル内容を含める（cmd_karo_hotfix_ga129_context_freshness_dm_signal_ops_20260625）
- L850: context_freshnessが作業開始時点でOKでも発火ログとsource差分を分けて報告する（cmd_karo_hotfix_ga130_context_freshness_dm_signal_frontend_20260625）
- L851: karo_snapshotは重い監視処理より前に早期発行しatomic publishする（snapshot_staleness_fix_20260625）
- L852: cmd-completeスキルは現物script pathとarchive済みcmd扱いを明記する（cmd_complete_skill_path_fix_20260625）
- L853: GATE CLEAR済みWAの永続ALERT防止: cmd_design_quality品質ログを解決判定に活用（cmd_karo_hotfix_wa_resolved_gate_20260625170121）
- L854: context freshness hotfixでは対象context以外のALERTを横展開候補として報告に分離する（cmd_karo_hotfix_ga132_context_freshness_dm_signal_research_20260625）
- L855: hook artifact調査では発火時点と現時点を分けて報告する（cmd_karo_hotfix_ga133_pre_push_clear_prep_memory_db_20260625）
- L856: context_freshness_check: docs/semantic-index pathspecが過広でindex.md成長更新が偽陽性ALERTを常時発火（cmd_karo_recon_ga134_obsidian_link_principles_20260626）
- L857: lesson_health未振り分けALERTはID一覧まで出さないと次アクションが遅れる（cmd_karo_hotfix_ga135_lesson_health_dm_signal_unclassified_20260626）
- L858: gateキャッシュは人間可読状態行とexit_codeを構造検証してから再利用する（cmd_karo_recon_ga137_p_average_freshness_20260626）
- L859: notify_targetsフィールドを読むスクリプトは書き戻し時にも保持せよ（cmd_karo_hotfix_bulletin_confirm_close_20260626081815）
- L860: useful_rate低下の主因はwhen未設定教訓のfullタスク広域誤注入（cmd_karo_recon_lesson_health_useful_20260626082714）
- L861: semantic_index_updateの伝播テストは閾値式を数値で固定せよ（cmd_karo_recon_hook_failure_ga138_202606261303）
- L862: project内deprecated同IDはinfra fallbackで復活させるな（cmd_karo_hotfix_lesson_health_useful_20260626173325）
- L863: precheck文字列検出ロジックは陰性ケースでFPを固定せよ（gunshi_idle_precheck_fp_trio_20260626）
- L864: docs/research追加commitはcontext_update候補を自動注入する（cmd_karo_hotfix_ga141_context_freshness_dm_signal_research_20260626）
- L865: CLI切替時はsettings.yaml typeとtmux @real_modelを同時検証する（session_20260626_pane_status_mismatch）
- L866: infra主contextはroot_fallbackのままにせず明示pathspecかcommit details注入で判定させる（cmd_karo_recon_ga142_context_freshness_infrastructure_202606270309）
- L867: semantic_stress_testのAC母数は実データで再集計してから判定する（cmd_karo_hotfix_semantic_stress_pending_202606270905）
- L868: コマンド置換内のバックグラウンド処理はstdout継承で待たれる（cmd_3563）
- L869: context_freshness ALERTはsource差分件数と真のops反映差分を分けて報告する（cmd_karo_hotfix_ga144_context_freshness_dm_signal_ops_20260627）
- L870: context_freshnessの真陽性はsource commit分類を索引カテゴリへ圧縮してからlast_updatedを更新する（cmd_karo_hotfix_ga145_context_freshness_dm_signal_frontend_20260627）
- L871: context freshness hotfixでは外部repo API/service差分をsplit context別に分類する（cmd_karo_hotfix_ga146_context_freshness_dm_signal_core_20260627）
- L872: context_freshness hotfixはsource差分分類欄を自動注入する（cmd_karo_hotfix_ga147_context_freshness_dm_signal_research_20260627）
- L873: NO_MATCH率報告は抽出元sourceを必ず併記する（cmd_3580）
- L874: CDP touch stream成功とReact state更新成功を分離して判定せよ（cmd_3588）
- L875: CDP検証用localhostポートがstale serverで占有されている場合は停止せず修正後bundleを別ポートで実証し制約を報告せよ（cmd_3588）
- L876: context_freshness root fallbackは運用同期commitをsource扱いしない（cmd_karo_hotfix_ga150_context_freshness_infra_20260629）
- L877: 外部リポcmdのcommit hash検証はtarget repoで行う（cmd_3602）

## 軍師レビュー効果計測（cmd_1144導入）

家老+軍師の品質管理ユニット化（cmd_1144）の効果を定量計測する。

### ベースライン（導入前）
- **GATE CLEAR率**: 直近30cmdの初回GATE CLEAR率をdashboard.mdの戦果セクションから取得
- **Re-review率**: 直近30cmdのうちFAIL→再レビューが発生したcmdの割合

### 導入後計測
- 同指標を継続計測（軍師レビュー導入後30cmd分）
- データソース: dashboard.mdの戦果セクション（完了cmd一覧+karo_workaround記録）

### 判定基準（30cmd後）
| 指標 | 判定 | 結論 |
|------|------|------|
| CLEAR率維持 + Re-review率低下 | 付加価値あり | 軍師レビュー継続 |
| CLEAR率維持 + Re-review率変化なし | 判断保留 | さらに30cmd計測 |
| CLEAR率低下 | 要見直し | 軍師レビュー観点の調整を検討 |

## PD裁定反映（cmd_354同期）

| PD | 裁定 | 反映先 |
|----|------|--------|
| PD-037 | inbox_write.sh HIGH-1(Python直接展開インジェクション)+HIGH-2(パストラバーサル)修正。殿裁定2026-02-25 | L043修正済み。`scripts/inbox_write.sh` |
| PD-038 | ashigaru.md否定指示→案C(ハイブリッド)採用。forbidden_actions構造維持+positive_rule+reason追加。ACE準拠 | `instructions/ashigaru.md` cmd_324実装済み |

## skill_gate_feedback.sh 最適化パターン（cmd_2589, 2026-05-06）

subprocess.run → Python インライン + load_skill_log キャッシュで 220ms→50ms (-77%) 達成。
→ `docs/research/cmd_2589_skill_gate_feedback_after_20260506.md`（最適化パターン+禁止パターン+計測ベースライン）

## SKILL.md品質基準（7項目チェックリスト）

スキル作成・更新時に必ず確認。発火精度はdescription品質で決まる。
- L069: スキルがsystem-reminderに検出されるにはSKILL.mdにYAMLフロントマター必須（cmd_368）
- L103: skill.md(小文字)はcase-sensitive環境で未検出→SKILL.md(大文字)に統一（cmd_438）
- L122: SKILL.md手順追加時に原則セクションとの矛盾を確認せよ（cmd_490）

| # | 項目 | 基準 | NG例 | OK例 |
|---|------|------|------|------|
| 1 | What | 具体的な出力を明記 | 「ドキュメント処理」 | 「PDFからテーブル抽出しCSV変換」 |
| 2 | When | 使用シーンを明記 | (なし) | 「gate_lesson_health.shのALERT後に使用」 |
| 3 | トリガーワード | 発火キーワードを列挙 | (なし) | 「棚卸し」「監査」「メモリ整理」 |
| 4 | 動詞の具体性 | 「管理」禁止 | 「知識を管理する」 | 「検出・更新提案・実行」 |
| 5 | 長さ | 50-200文字 | 300文字の散文 | 簡潔な1-2文 |
| 6 | 差別化 | 既存スキルとの守備範囲明示 | (なし) | 「/shogun-teireは全層監査、本スキルはMemory MCPのみ」 |
| 7 | 角括弧不使用 | description内で[X]禁止 | 「[PDF]を処理」 | 「PDFを処理」 |

### フロントマター必須フィールド
- `allowed-tools`: 使用ツール制限（未指定=全ツール利用可。意図的な場合のみ省略）
- `argument-hint`: 補完表示（例: `[project-id]`）

### オプションフィールド
- `context: fork`: サブエージェント隔離実行（メインCTX圧迫防止）
- `model`: 実行時モデル指定

### North Star
カスタムフロントマターフィールドはClaude Codeに無視される。
判断基準はMarkdown本文に記載すること。

## Diff-aware Testing 方針（GStack/GBrain #26）

**原則**: テストは変更されたファイルに関連するものを優先実行し、無関係なテストの全量実行でCTXと時間を浪費しない。

### 適用判断フロー

| 状況 | テスト範囲 | 理由 |
|------|-----------|------|
| 変更が1-3ファイルに限定 | 変更ファイルの関連テストのみ | 全量は過剰 |
| 変更が共通基盤（deploy_task.sh等）| 全テスト | 波及範囲が広い |
| CI修正 / ゲート改修 | 対象テストファイル + smoke test | 最小限で確認 |
| 本番リリース前 / cmd_complete_gate実行時 | 全テスト必須 | SKIP=FAILルール適用 |

### CI固有FAIL切り分け手順(ローカル未再現時)
1. `gh run list --limit 5` で最後のGREEN commit特定
2. `git log --oneline <GREEN>..<RED>` で間のcommit列挙
3. 各commitの`--stat`で変更ファイル確認→テストファイル変更があるcommitが最有力
4. `git ls-files -s <file>` で権限確認(100644=実行権限なし→CIでPermission denied)
5. revertで二分探索(1commitずつ)。ローカルPASSでもCI FAILする原因: git mode/bats並列/fixture共有

### WSL2固有の注意点
- `git ls-files -s` の100644/100755: WSL2 NTFSでは全ファイル755に見えるがgit indexは実権限を保持。CIはindex通りにcheckoutする
- `bash scripts/test_select.sh <file>` で間接依存テストを確認。マッピング漏れ=CI FAILの盲点

### 変更ファイルに関連するテスト特定方法
```bash
# 変更ファイルのテストを特定
git diff --name-only HEAD | while read f; do
  # 対応するbatsテストを探す
  base=$(basename "$f" .sh)
  find tests/ -name "*${base}*" -o -name "test_${base}*" 2>/dev/null
done | sort -u
```

### 制約（SKIP=FAILルール、Test Rules §1）
- **SKIP=FAIL**: Diff-aware実行でもSKIP数1以上は「テスト未完了」扱い
- **本番前は全量**: cmd_complete_gate.sh実行前・PR作成前は必ず全量テスト
- **全量前提の場合**: 呼び出し元が「全件テスト必須」と明示した場合はDiff-awareを適用しない（#26デメリット緩和策）

---

## 因果リンク

- ← [[deepdive_why_chain_20260321]] Phase 6-7: gate/hook=知性の外部化の実装先
- → [[growth-loop]] 成長ループ=インフラの設計原理
- → [[training-cycle]] 修行サイクル=インフラで駆動する忍者成長
- → [[karo-operations]] 家老運用=インフラを操作する手順
- → [[gunshi_idle_ntfy_rate_limit_global_20260516]] ntfyグローバルレート制限の分析
- → [[gunshi_idle_numbers_cold_bugfix_20260426]] numbersのコールドバグ修正: インフラバグ実例
- → [[gunshi_idle_observations_gap_analysis_20260519]] MCP observations gapの分析: 三層記憶インフラの穴
- → [[gunshi_idle_precision_fix_inbox_nudge_20260527]] inbox nudge精度修正: watcher誤検知根因
- → [[karo-direct]] 家老自立配備スキル: 将軍cmd不要の直接配備標準化
- → [[gunshi_idle_dream_gate_analysis_20260507]] dreamゲート分析: Phase設計品質検証
- → [[gunshi_idle_project_dir_false_rc_20260430]] project_dir false RC: gate判定バグの根因
- → [[gunshi_idle_recording_error_analysis_20260409]] recording error分析: lord_conversation記録失敗の根因
- → [[gunshi_idle_session_efficiency_20260503]] セッション効率分析: CTX消費ボトルネックの特定
- → [[gunshi_idle_session_nazenaze_20260519]] セッションのなぜなぜ: clear後の復旧速度問題
- → [[gunshi_idle_speed_bottleneck_nazenaze_20260602]] 速度ボトルネックのなぜなぜ: インフラ全体の遅延根因
- → [[gunshi_idle_stall_ghost_nazenaze_20260521]] STALL-GHOSTのなぜなぜ: ninja_monitor誤検知根因
- → [[gunshi_idle_state_divergence_20260603]] 状態乖離分析: karo_snapshot不整合の根因
- → [[gunshi_idle_wsl2_symlink_limitation_20260427]] WSL2シンボリックリンク制限の分析
- → [[gunshi_idle_yaml_field_set_newline_20260502]] yaml_field_set改行バグ: YAML安全書込みの問題
- → [[gunshi_idle_yaml_parse_vulnerability_20260505]] YAML parseの脆弱性分析: 運用YAML破損リスク
- → [[gunshi_idle_inbox_watcher_fp_repeat_20260602]] inbox watcher偽陽性繰り返しの根因分析
- → [[gunshi_watcher_silent_cycle_rootcause_20260425]] watcher silent cycleの根因: watcher設計の構造的問題
- → [[gunshi_startup_gate_auto_exec_bug_20260412]] startup gate自動実行バグ: gate設計の問題
- → [[gunshi_idle_semantic_audit_20260505]] セマンティック監査2026-05-05: インデックス品質評価
- → [[gunshi_idle_semantic_audit_20260509]] セマンティック監査2026-05-09: aliases品質評価
- → [[gunshi_idle_semantic_audit_20260517]] セマンティック監査2026-05-17: aliases漏れの検出
- → [[gunshi_idle_semantic_audit_20260519b]] セマンティック監査2026-05-19b: 品質精度の再測定
- → [[gunshi_idle_semantic_audit_20260521]] セマンティック監査2026-05-21: 改善効果の検証
- → [[gunshi_idle_semantic_audit_causal_nw_20260518]] セマンティック監査+因果NW統合: 三層記憶の接続品質
- → [[gunshi_idle_semantic_audit_cmd2681_2684_20260512]] cmd2681/2684のセマンティック監査: aliases注入効果
- → [[gunshi_idle_semantic_audit_daemon_watcher_20260530]] daemon_watcherのセマンティック監査
- → [[gunshi_idle_semantic_audit_infra_bugs_20260525]] インフラバグのセマンティック監査: 概念接続の穴
- → [[gunshi_idle_semantic_audit_post_backup_first_20260519]] backup_first後のセマンティック監査
- → [[gunshi_idle_semantic_audit_scripts_20260529]] スクリプトのセマンティック監査: 索引品質向上
- → [[gunshi_idle_semantic_audit_skill_scripts_20260506]] スキルスクリプトのセマンティック監査
- → [[gunshi_idle_semantic_index_gap_20260515]] セマンティックインデックスgap分析: 未カバー概念の特定
- → [[gunshi_semantic_audit_catalog_design_20260503]] セマンティック監査カタログ設計: 監査の標準化
- → [[gunshi_semantic_audit_cmd2621_20260510]] cmd2621のセマンティック監査結果
- → [[gunshi_semantic_audit_cmd2635_20260510]] cmd2635のセマンティック監査結果
- → [[gunshi_staleness_audit_20260510]] 陳腐化監査: コンテキストファイルの鮮度評価
- → [[cmd_karo_reprofile_bench_20260426]] 家老CTXプロファイリングベンチマーク(2026-04-26: bottleneck特定)
- → [[cmd_karo_reprofile_freq_20260426]] 家老CTXプロファイリング頻度分析(2026-04-26: 頻度別コスト)
- → [[multinode_portable_environment_20260609]] マルチノードポータブル環境設計(2026-06-09: 可搬性向上)
- → [[rollback_english_design_20260422]] ロールバック英語版設計(2026-04-22: 英語対応設計書)
- → [[language_policy_design_20260421]] 言語ポリシー設計(2026-04-21: 日英混在ルール策定)
- → [[statistical-wheels-for-quality]] 品質のための統計的車輪原則(車輪の再発明禁止+既存計測活用)
- → [[three_layer_memory_first_priority_design_20260606]] 三層記憶ファーストプライオリティ設計(2026-06-06: 検索順序強制)
- → [[cmd_316_rate_limit_analysis]] APIレート制限分析(cmd_316)
- → [[cmd_316_rate_limit_consumption]] APIレート制限消費分析(cmd_316)
- → [[cmd_317_config_dir_codex]] Codex設定ディレクトリ調査(cmd_317)
- → [[cmd_317_config_dir_opus]] Opus設定ディレクトリ調査(cmd_317)
- → [[cmd_317_config_dir_sonnet]] Sonnet設定ディレクトリ調査(cmd_317)
- → [[cmd_317v2_model_comparison]] モデル比較実験(cmd_317v2)
- → [[cmd_319_oss_preparation]] OSS公開準備(cmd_319)
- → [[cmd_344_knowledge_metrics_design]] 知識メトリクス設計(cmd_344)
- → [[cmd_504_qiita-idea-council]] Qiita記事アイデア会議(cmd_504)
- → [[cmd_506_hermit-technical-recon]] 仙人技術偵察(cmd_506)
- → [[cmd_508_screenshot-paste-recon]] スクリーンショット貼付偵察(cmd_508)
- → [[cmd_798_ndlocr-lite]] NDLOCR-Lite調査(cmd_798)
- → [[cmd_888_self-healing-patterns]] 自己修復パターン分析(cmd_888)
- → [[cmd_2087_codd_spec_ntfy_20260418]] ntfy CoDD仕様書(cmd_2087)
- → [[cmd_2108_deploy_task_template_generation_profile]] テンプレート生成プロファイル(cmd_2108)
- → [[cmd_2109_gate_shogun_startup_test_profiling]] startup gateテストプロファイル(cmd_2109)
- → [[cmd_2110_report-template-gate-compat-setup-profile]] レポートテンプレートgateプロファイル(cmd_2110a)
- → [[cmd_2110_test_report_template_gate_profiling]] レポートテンプレートgateプロファイル(cmd_2110b)
- → [[cmd_2112_test_deploy_task_lifecycle_profiling]] deploy_taskライフサイクルプロファイル(cmd_2112)
- → [[cmd_2113_cli_adapter_setup_profile]] CLIアダプタセットアッププロファイル(cmd_2113)
- → [[cmd_2115_test_cmd_save_profile]] cmd_saveテストプロファイル(cmd_2115)
- → [[cmd_2116_test_build_system_profiling]] ビルドシステムプロファイル(cmd_2116)
- → [[cmd_2126_mizchi_red_flags_skip_reasons_20260419]] mizchi red flags調査(cmd_2126)
- → [[cmd_3005_document_inventory_kagemaru]] ドキュメントインベントリ(cmd_3005)
- → [[adoption-log]] 知識採用ログ(systems-knowledge-base/our-army)
- → [[claude-code]] Claude Code知識ベース(systems-knowledge-base)
- → [[our-army]] 我ら軍の知識ベース(systems-knowledge-base)
- → [[vercel]] Vercel設計原則(systems-knowledge-base)
- → [[mizchi]] mizchi記事知識ベース(systems-knowledge-base)
- → [[gyakusegawa]] 逆瀬川記事知識ベース(systems-knowledge-base)
- → [[dm-signal]] DM-Signal=インフラが支えるPJ

<!-- 軍師idle分析リンク(cmd_3278自動追記) -->
- [[gunshi_idle_infra_bug_audit_20260409]] — 軍師idle: インフラバグ監査(2026-04-09)
- [[gunshi_idle_infra_bugs_full_audit_20260424]] — 軍師idle: インフラバグ全量監査(2026-04-24)
- [[gunshi_idle_infra_health_20260425]] — 軍師idle: インフラ健全性レポート(2026-04-25)
- [[gunshi_idle_infra_bug_universal_commit_20260430]] — 軍師idle: インフラバグ汎用コミット対策(2026-04-30)
- [[gunshi_idle_infra_bug_trio_20260502]] — 軍師idle: インフラバグトリオ分析(2026-05-02)
- [[gunshi_idle_infra_bug_trio_fix_20260503]] — 軍師idle: インフラバグトリオ修正(2026-05-03)
- [[gunshi_idle_infra_speed_hidden_bugs_20260605]] — 軍師idle: インフラ速度の隠れバグ(2026-06-05)
- [[gunshi_idle_clear_durability_nazenaze_20260515]] — 軍師idle: /clear耐久性なぜなぜ分析(2026-05-15)
- [[gunshi_idle_clear_durability_flag_gap_20260515]] — 軍師idle: /clear耐久性フラグギャップ(2026-05-15)
- [[gunshi_idle_clear_durability_nazenaze_20260515d]] — 軍師idle: /clear耐久性なぜなぜ分析(続)(2026-05-15)
- [[gunshi_idle_clear_durability_fix_20260516]] — 軍師idle: /clear耐久性修正(2026-05-16)
- [[gunshi_idle_clear_respawn_bug_20260607]] — 軍師idle: /clear respawnバグ分析(2026-06-07)
- [[gunshi_idle_deploy_yaml_parse_error_20260516]] — 軍師idle: 配備YAMLパースエラー(2026-05-16)
- [[gunshi_idle_deploy_structural_bugs_20260517]] — 軍師idle: 配備構造バグ分析(2026-05-17)
- [[gunshi_idle_direct_mode_stale_ac_20260502]] — 軍師idle: ダイレクトモード古いAC問題(2026-05-02)
- [[gunshi_idle_gitignore_wa_20260409]] — 軍師idle: .gitignore WAパターン(2026-04-09)
- [[gunshi_idle_autocommit_scope_leak_20260602]] — 軍師idle: 自動コミットスコープ漏洩(2026-06-02)
- [[gunshi_idle_dashboard_corruption_20260603]] — 軍師idle: ダッシュボード破損分析(2026-06-03)
- [[gunshi_idle_codex_commit_missing_20260413]] — 軍師idle: Codexコミット欠落分析(2026-04-13)
- [[gunshi_idle_codex_respawn_loop_20260516]] — 軍師idle: Codex respawnループ分析(2026-05-16)
- [[gunshi_idle_codex_respawn_loop_nazenaze_20260520]] — 軍師idle: Codex respawnループなぜなぜ(2026-05-20)
- [[gunshi_codex_clear_judgment_20260422]] — 軍師分析: Codex clear判断基準(2026-04-22)
- → [[cdp-browse]] CDPブラウザ自動化スキル（persistent daemon + AXTree操作）
- → [[reset-layout]] tmuxペイン配置復元スキル（agentsウィンドウ一発復元）
- → [[shogun-all-codex-switch]] 全忍者Codex一括切替スキル（Claude→Codex全員切替）
- → [[shogun-peacetime-rollback]] Codex→Claude平時ロールバックスキル
- → [[shogun-cli-switch]] 個別エージェントCodex切替スキル
- → [[shogun-cli-switch]] 個別エージェントOpus CLI切替スキル
- → [[switch-project]] プロジェクト切替スキル（current_project変更）
- → [[hensei-mixed]] 混成編成切替スキル（GPT+Sonnet+Opus混成）
- → [[hensei-opus]] Opus統一編成スキル（決戦モード全忍者Opus化）
