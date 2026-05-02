# インフラコンテキスト
<!-- last_updated: 2026-04-30 cmd_karo_ctx_freshness_infra_v2 -->

> 読者: エージェント。推測するな。ここに書いてあることだけを使え。
> 詳細: `docs/research/infra-details.md`
> CoDDリファクタリング台帳: `docs/research/codd_refactor_registry.md`
> report_field_set as-is: `docs/research/report_field_set_after_20260416.md`
> inbox_write高速化(as-is): `docs/research/inbox_write_after_20260416.md`

## コンテキスト管理

全て外部インフラが自動処理。エージェントは何もするな。Codex忍者=/new、Claude忍者=/clear、家老=/clear(陣形図付き)、将軍=殿判断。
閾値: ソフト50%（外部トリガー）、ハード90%（AUTOCOMPACT）。CLI差異は`config/settings.yaml`参照。
→ `docs/research/infra-details.md` §1

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

> **思考の起源（経験的知識。圧縮禁止。過程が本体）**:
> - 免疫系/ラルフループ/自動化×強制の到達過程 → `memory/deepdive_why_chain_20260321.md`
> - System 1(gate自動)/System 2(なぜなぜ検証)の二重ループ → `memory/dialogue_heuristics_system2_20260401.md`
> - 第二層学習ループ（軍師↔家老還流） → `memory/dialogue_second_layer_20260321.md`
| 1119/1120 | **自動トリム機構** | cmd-chronicle.md(200行)+shogun_to_karo.yaml(50件)をarchive_completed.shで自動トリム |

→ 完了履歴: `context/cmd-chronicle.md` 03-18〜03-20

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
| CoDD改善32本 | cmd_1951の全量プロファイリングを起点にhot path 32本を改善。代表値: `cmd_save.sh 4.02s→1.06s (-73.6%)`, `deploy_task.sh 2639ms→32ms`, `gate_karo_startup.sh 464ms→190ms` | `docs/research/codd_refactor_registry.md`, `context/cmd-chronicle.md` 04-16 |
| GP-198/201 Session State | gate FAIL時の失敗履歴をtask再配備へ注入し、`cmd_save.sh` 側でもDiagnose MANDATORY+Session Stateを強制。/newや再配備を跨いでL3診断を保持 | `context/codd.md` §4, `context/cmd-chronicle.md` `cmd_karo_gp198`/`cmd_1939` |
| GP-199 退化計測 | GP/改善cmdの報告に `before_metrics` / `after_metrics` / `regression` をWARNで強制し、速度改善が退化を隠さない形に変更 | `scripts/gates/gate_report_format.sh`, `context/cmd-chronicle.md` `cmd_1941` |
| GP-202 成果物プレフィックス検査 | `files_modified` に `parent_cmd` プレフィックスが無い場合WARN。cmd_1948事故系の「別cmd成果物上書き」をゲートで検知 | `scripts/gates/gate_report_format.sh`, `tests/unit/test_report_template_gate_compat.bats` |
| GP-204/208 運用耐障害 | `daemon_watchdog.sh` は `set -e` / 二重flockを外して部分失敗で全体停止しない形に修正。`bulletin_write.sh` は掲示板通知を80文字要約でなく全文inbox配信へ変更 | `scripts/daemon_watchdog.sh`, `scripts/bulletin_write.sh` |
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
**codex CLI**: デフォルト272K。1Mには`~/.codex/config.toml`に`model_context_window=1000000`+`model_auto_compact_token_limit=900000`必要。デフォルトモデル=gpt-5.5(旧gpt-5は廃止名)。effort=config.tomlの`model_reasoning_effort=high`。
→ `lib/cli_adapter.sh` L88 | 詳細: `docs/research/gunshi-cli-model-context.md`（respawn手順/セレクタの罠/effort優先順位/codex config設定方法）

## Claude Code バージョン固定と復帰

現在v2.1.87に固定。`config/cli_profiles.yaml`の`launch_cmd`が正本。

| 操作 | launch_cmd | 備考 |
|------|-----------|------|
| **v2.1.87固定** | `/home/simokitafresh/bin/claude --dangerously-skip-permissions` | 現在の状態 |
| **auto-update復帰** | `/home/simokitafresh/.local/bin/claude --dangerously-skip-permissions` | updater管理symlink |

切替手順: launch_cmd変更 → `bash scripts/switch_cli_mode.sh claude --scope shogun,karo,gunshi,kagemaru,hanzo,kotaro,tobisaru` でrespawn。backup3本(`~/bin/claude`, `claude.pinned`, `claude-2.1.87-stable`)で復元可能。
→ `docs/research/claude-code-version-runbook.md`（全手順+緊急ロールバック+復元方法）

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
| hook失敗自動記録 | 報告テンプレート+ashigaru.md | cmd_1117 | hook_failures欄で失敗を構造化記録。穴検出3問と自動連鎖 |
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

## ninja_monitor.sh

idle検知+コンテキストリセット送信（Codex=/new, Claude=/clear）、is_task_deployed二重チェック、STALE-TASK検出、CLEAR_DEBOUNCE=300s、karo_snapshot自動生成、状態遷移検知(cmd_255)。
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

**教訓(auto-ops由来、全PJ適用):**
- L023/L027: Sheets取得は`spreadsheets values get --params`形式が正（+read旧式）
- L028: Drive files get alt=media構文
- L030: Drive files rename/deleteバッチ
- L055: Drive moveはfiles updateのaddParents/removeParents

→ auto-ops固有の経費管理パターンは `context/auto-ops.md §gws CLI` 参照

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

## Infra教訓索引
<!-- last_synced_lesson: L555 -->
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
