# おしお殿(yohey-w/multi-agent-shogun)リポジトリ対比分析

> 調査日: 2026-03-25
> 調査方法: `gh api repos/yohey-w/multi-agent-shogun/contents/{path}` で全コード直接取得・目視確認
> 更新: 部分ごとに随時更新。§番号で管理

## §1 前提

両リポジトリは同一forkベース。大半の基盤コード（inbox_write.sh, inbox_watcher.sh, ntfy, build_instructions.sh, cli_adapter.sh, Makefile, E2Eテスト, Android app等）は共通。以下はフォーク後の**独自進化**の対比。

確認対象ファイル数: おしお殿側200+ファイル、我々側全ファイル。

---

## §2 共通基盤（両方に存在する技術）

| 技術 | おしお殿 | 我々 | サイズ差 |
|------|---------|------|---------|
| Android App | UI 6画面, VM 4, APK 1 | UI 10画面, VM 6, APK 4版(v6.2) | 我々が大 |
| Makefile | test/build/lint/check/install-deps/clean/dev | +setup-hooks | ほぼ同等 |
| slim_yaml.py | 300行 | 301行(ローカル名対応) | 同等 |
| build_instructions.sh | 200行 | 267行 | 同等 |
| cli_adapter.sh | 38KB/~900行(4CLI実運用: 6関数) | 220行+cli_lookup154行=374行 | おしお殿が大。差の理由: 4CLI(claude/codex/copilot/kimi)実運用 vs 全Claude統一 |
| switch_cli | switch_cli.sh 300行 | switch_cli_mode.sh 276行 | 同等 |
| ntfy_auth.sh | 90行 | 85行 | 同等 |
| first_setup.sh | 40KB/~1000行(4CLI環境初期構築) | 790行 | おしお殿が大。差: 多CLI venv/設定 |
| shutsujin_departure.sh | 72KB/~1800行(4CLI出陣対応) | 1150行 | おしお殿が大。差: 多CLI分岐 |
| instructions/generated | 16ファイル(4ロール×4CLI) | 12ファイル(3ロール×4CLI) | おしお殿がgunshi分多い |
| instructions/common+roles+cli_specific | 完備 | 完備 | 同等 |
| AGENTS.md/copilot-instructions/system.md | あり | あり | 同等 |
| E2Eテスト | 12本, mock_cli.sh 250行 | 12本, mock_cli.sh 145行 | おしお殿のmockが大 |
| CI (unit+shellcheck+e2e+build-check) | 4ジョブ+multiOS(ubuntu+macos) | 4ジョブ(ubuntuのみ) | おしお殿がmultiOS |
| spinnerVerbs | 60+個 | あり | 共通 |
| Shout Mode/echo_message | あり | あり | 共通 |
| agent_status.sh | scripts/250行+lib/分離 | scripts/86行 | おしお殿がlib分離 |
| saytask/streaks | あり | あり | 共通 |
| templates/ | 6ファイル | 10ファイル | 我々が多い |
| .gitleaks.toml | あり | あり | 共通 |
| skill-creator | あり | あり | 共通 |
| inbox_write.sh | 130行 | 623行 | 我々が巨大 |
| inbox_watcher.sh | 54KB/~1300行(テストガード+3段エスカレーション) | 668行 | おしお殿が大 |
| ntfy.sh | ~25行 | 117行 | 我々が大 |
| ntfy_listener.sh | ~170行(corrupt_dir対応) | 409行 | 我々が大 |
| stop_check_inbox.sh | **settings.json登録済み** | コード存在するが**settings.json未登録** | §6参照 |

---

## §3 おしお殿にのみある技術

### §3.1 Stop Hook inotifywait待機（最重要差分）
- **ファイル**: `scripts/stop_hook_inbox.sh` 180行
- **settings.json登録**: `"Stop": [{"hooks": [{"command": "bash scripts/stop_hook_inbox.sh", "timeout": 60}]}]`
- **核心コード(L72-76, L113-117)**: inotifywait 55秒待機2箇所
  ```bash
  inotifywait -e close_write -e moved_to --timeout 55 "${WATCH_TARGETS[@]}" 2>/dev/null || true
  ```
- **無限ループ防止**: `stop_hook_active` flag (JSON input) — True時はinotifywait後にexit 0
- **完了自動検出**: last_assistant_messageから「任務完了」「エラー中断」パターンgrepで自動karo通知
- → §6で対応方針記載

### §3.2 Screenshot skill (mask/trim)
- **ファイル**: `skills/shogun-screenshot/SKILL.md` + scripts 3本
- `mask_sensitive.py`: 矩形座標指定で黒塗り。`--preview`で赤枠プレビュー。`--color`で色指定
- `trim_image.py`: PIL/Pillow crop + `--resize`
- `capture_local.sh`: settings.yaml `screenshot.paths` 配列を優先順探索
- **対応状況**: 未着手

### §3.3 watcher_supervisor.sh
- **ファイル**: `scripts/watcher_supervisor.sh` 50行
- 5秒ポーリングで落ちたwatcher自動再起動
- **我々の代替**: ninja_monitor.shにntfy_listener限定の再起動あり(check_ntfy_listener_health: ログ鮮度監視→stale時にrestart_ntfy_listener.sh呼出、5分cooldown)。ただしinbox_watcher自体の生死監視はない。inbox_watcher.sh自身にscript変更時self-restart機能あり(check_script_update)が、プロセス死亡時の自動再起動は未実装
- **対応状況**: 盗む価値あり。inbox_watcher死亡時の自動再起動は現在カバーされていない

### §3.4 Bloom Taxonomy Dynamic Model Routing (DMR) — 最大の設計哲学差

おしお殿にあって我々に**完全に存在しない**システム。前版の記述(Agent Self-Watch Phase Policy)は全体の一部に過ぎず誤記。

**概要**: タスクをBloom's Taxonomy L1-L6に分類し、各モデルのmax_bloom能力に基づいて最安モデルに自動ルーティング

**実装コード** (gh apiで確認済み):
- `lib/cli_adapter.sh`(38KB): get_capability_tier(), get_recommended_model(), get_cost_group() — 全てcapability_tiers YAMLから動的取得
- `config/settings.yaml`: capability_tiers定義 + bloom_routing: auto/manual/off

**モデル→Bloom能力マッピング** (test_dynamic_model_routing.batsから取得):
| モデル | max_bloom | cost_group |
|--------|-----------|------------|
| gpt-5.3-codex-spark | L3 | chatgpt_pro |
| gpt-5.3 | L4 | chatgpt_pro |
| claude-sonnet-4-5 | L5 | claude_max |
| claude-opus-4-6 | L6 | claude_max |

**4Phase TDD開発** (tests/specs/dynamic_model_routing_spec.md 12.7KB):
- Phase 1: capability_tier定義(settings.yaml読取+関数) — TC-DMR-001~055, 23件
- Phase 2: 家老manual model_switch(Step 6.5) — TC-DMR-100~142, 15件
- Phase 3: 軍師Bloom分析層(auto分類) — TC-DMR-200~224, 14件
- Phase 4: Full auto-selection(品質フィードバック) — TC-DMR-300~303, 4件

**精度・品質テスト**:
- `tests/bloom_classification_accuracy.sh`: Dim B — bloom_task_corpus.yaml(13.8KB)を軍師に送り分類精度測定。基準: exact≥60%, ±1≥80%
- `tests/dim_d_quality_comparison.sh`: Dim D — 同一L5タスクをHaiku(max_bloom=3)とSonnet(max_bloom=5)に実行させ、Opus(L6)が品質採点。基準: Sonnet≥70, Haiku≤50, diff≥15

**CLAUDE.md統合**: `bloom_routing_rule: autoなら家老はStep 6.5を必ず実行。スキップ厳禁`

**Agent Self-Watch Phase** (DMRの一部):
- Phase 1-3の段階的エスカレーション(CLAUDE.md記載、tests/agent_selfwatch.bats+specs/agent_selfwatch_spec.md 10.9KB)
- inbox_watcher.sh内のASW_DISABLE_NORMAL_NUDGE等の環境変数で制御

**我々との根本差**: 我々は全8名Opus統一(コスト度外視で最高品質追求)。おしお殿は4CLI×4モデルで**コスト最適化+タスク適性ルーティング**。設計哲学の違い。

**対応状況**: 設計参考。我々は全Opus統一方針だがコスト圧迫時の選択肢として記録

### §3.5 repo内skills 7本
- shogun-agent-status, shogun-bloom-config, shogun-model-list, shogun-model-switch, shogun-readme-sync, shogun-screenshot, skill-creator
- **我々**: repo内1本(skill-creator) + ~/.claude/skills/ 14本
- **差分**: おしお殿はskillsをgit管理（OSS公開）。我々はhome dirにローカル保管
- **対応状況**: 移植不要（配置場所の違いのみ）

### §3.6 seo_qc.py
- `scripts/seo_qc.py` 400行。14項目SEO品質検査。9サイト対応
- **対応状況**: 別ドメイン。移植対象外

### §3.7 CI multiOS matrix
- `strategy: matrix: os: [ubuntu-latest, macos-latest]` + GNU tools brew install
- 我々はubuntuのみ
- **対応状況**: 未着手（macOS CI追加の価値は低い）

### §3.8 lib/agent_status.sh分離
- `agent_is_busy_check()`: pane末尾5行からCLI固有idle/busyパターン検出
- status bar検出(last_line `esc to`)が最も信頼性高い — T-BUSY-008修正でscrollback誤検知対策済み
- 我々のagent_status.sh(86行)はscripts/にあるがlib分離されていない
- **対応状況**: 参考（テスタビリティ向上に寄与）

### §3.9 Batch Processing Protocol
- CLAUDE.md記載: 30+件バッチ処理の6ステップ(Strategy→batch1 QC→Fix→batch2+→Final QC→Done)
- batch1 QCゲート必須。バッチサイズ30件/session上限
- **対応状況**: 実質対応済み。cmd_1082事故(33体一括登録→汚染DELETE)を教訓に `context/checklist-shin-v2-registration.md` で段階的チェックリスト方式を導入済み。本質同一(少数検証→残りに展開)。CLAUDE.mdへの汎用プロトコル明文化は未実施

### §3.10 ntfy_listener.sh corrupt_dir対応
- YAML parse error時に `logs/ntfy_inbox_corrupt/` にバックアップ保存
- **おしお殿の実コード** (gh api grep確認済み):
  - L14: `CORRUPT_DIR="$SCRIPT_DIR/logs/ntfy_inbox_corrupt"`
  - L75-109: python3ブロック内で `parse_error=True` → `if corrupt_dir: os.makedirs(corrupt_dir, exist_ok=True)` → `shutil.copy2(path, backup)` → `data = {}` (空dictにリセット)
  - バックアップファイル名: `ntfy_inbox_corrupt_{timestamp}.yaml`
- 我々のntfy_listener.sh(409行)にcorrupt_dir防御は**なし**(grep確認: corrupt/backup_dir/broken/recover全て0件)
- **対応状況**: 未着手。盗む価値あり

### §3.11 OSS文書基盤
- **README.md** (77KB) + **README_ja.md** (85KB): 大規模な公開ドキュメント
- **CONTRIBUTING.md** (12.7KB): コントリビューションガイド
- **SECURITY.md** (9.5KB): セキュリティポリシー
- **CHANGELOG.md** (907B)
- **install.bat** (5.4KB): Windows GUI/CLIインストーラー
- **docs/philosophy.md** (3.8KB): 5つの設計原則(Autonomous Formation Design/Parallelization/Research First/Continuous Learning/Triangulation) + 階層構造/Mailbox/Dashboard単一書込みの設計理由
- **.gitmodules**: bats-assert + bats-support をgit submoduleで管理(我々はnpmインストール)
- **我々との差**: 我々はprivateリポジトリのためOSS文書不要。ただしphilosophy.mdの設計原則は参考価値あり
- **対応状況**: 移植不要（OSS公開予定なし）。philosophy.mdの設計原則は知識として記録

### §3.12 正式テスト仕様書 (TDD方法論)
- **tests/specs/dynamic_model_routing_spec.md** (12.7KB): DMR-SPEC-001。12セクション、56テストケース(TC-DMR-001~303)。Phase 1-4段階的テスト→実装サイクル
- **tests/specs/agent_selfwatch_spec.md** (10.9KB): FR/NFR→テストケース分解
- **tests/fixtures/bloom_task_corpus.yaml** (13.8KB): Bloom分類精度テスト用コーパス
- **TDD手法**: 仕様書→RED tests(未実装機能テスト先行)→GREEN(実装)→REFACTOR
- **我々との差**: 我々はテストあり(87本)だがフォーマルな仕様書なし。テストが仕様を兼ねる
- **対応状況**: 方法論として参考。我々のテスト規模(87本)は実質的に十分だがspec→test→implの明確化は品質に寄与

---

## §4 我々にのみある技術

### §4.1 Gate System 22本 (4625行)
gate_report_autofix(629行,21パターン自動修正), gate_lesson_health, gate_shogun_startup, gate_karo_startup, gate_gunshi_startup, gate_context_freshness, gate_dc_duplicate, gate_field_get, gate_loop_health, gate_mcp_access, gate_ninja_workaround_rate, gate_p_average_freshness, gate_pd_sync, gate_report_format, gate_shogun_memory, gate_skill_quality, gate_vercel_phase, gate_wa_data_quality, gate_workaround_rate, gate_yaml_status, gate_cmd_state, mark_no_learning

### §4.2 Hook System 13本
- PreToolUse(6): agent_state active設定, block_destructive, no-verify-guard, pre-bash-report-deny, pre-write-config-guard, pre-write-read-tracker
- PostToolUse(4): post-edit-report-guard, post-write-shellcheck, post-search-completeness-guard, post-edit-instruction-hook-consistency
- Stop(3): agent_state idle設定, log_terminal_response, stop-lint-gate
- UserPromptSubmit(1): session_start_inject

### §4.3 教訓システム
PJ別lessons.yaml + lesson_write.sh + deploy_task.sh自動注入 + 効果率追跡(参照率84%, 効果率100%, 注入率74.5%)

### §4.4 軍師レビューシステム
第二層学習ループ: 軍師一次レビュー→LGTM→家老スタンプ/FAIL→家老介入

### §4.5 ninja_monitor.sh (2592行)
STALL検知, idle+タスクなし→自動/clear, 陣形図(karo_snapshot.txt)自動生成, CTX%追跡

### §4.6 dashboard_auto_section.sh
プライマリYAMLから全セクション自動生成(gawk/jq, 3.3s)

### §4.7 production_invariants
本番不変量gate + projects/*.yamlの受動的知識層注入

### §4.8 deepdive/dialogue記録
why_chain(462行), statistical_wheels, skill_capability — 殿との対話の全過程記録

### §4.9 cmd_save.sh品質ゲート
q1-q4チェック + 深掘り度(shallow/medium/deep)判定

### §4.10 workaround追跡
karo_workarounds.yaml + gate_workaround_rate.sh + 軍師の成績表

### §4.11 usage_monitor.sh
OAuth API + ntfy警告 + 回復通知 + tmux statusbar常時表示（おしお殿のratelimit_check.shは表示のみ）

### §4.12 Vercelスタイルcontext
context/*.md索引層 + docs/research/*詳細層

### §4.13 home dir skills 14本
param-neighbor-check, switch-project, lesson-sort, clear-prep, reset-layout, x-research, note-article, sengoku-writer, memory-teire, pd-sync, weekly-report, gs-bench-gate, dashboard-update, shogun-teire

### §4.14 CDP browser automation
cdp_server.py daemon + cdp_cli.sh (gstack browse知見実装)

### §4.15 Android拡張画面
MemoScreen, UsageScreen, VoiceDictionarySection, TerminalZoom（おしお殿にない4画面+機能）

### §4.16 テスト規模
87本(unit+E2E+root) vs おしお殿22本

---

## §4b 同一機能で実装差がある技術

### §4b.1 ratelimit_check.sh vs usage_monitor.sh
- **おしお殿** `scripts/ratelimit_check.sh` (~350行): 4フェーズ構成
  1. Phase 1: tmux全ペインスキャンで@agent_id/@agent_cli/@model_nameメタデータ取得
  2. Phase 2: CLI種別でグルーピング(CLAUDE_AGENTS, CODEX_AGENTS, OTHER_AGENTS)
  3. Phase 3: CLI別データ収集 — Claude: OAuth API(5h/7d utilization)+stats-cache(dailyModelTokens per-model breakdown sonnet/opus)+Extra usage検出。Codex: tmux capture-pane(context% left)+/status送信(account 5h/weekly + model 5h/weekly)+token_limit_reached検出
  4. Phase 4: 表示(日英対応、閾値80%超で⚠️)
- **我々** `scripts/usage_monitor.sh` (344行): OAuth API監視+**ntfy警告+回復通知+tmux statusbar常時表示**
- **差分**: おしお殿はCodex対応+per-model breakdown+表示のみ。我々はntfy警告+回復通知+statusbar(能動的アラート)

### §4b.2 inbox_write.sh (130行 vs 623行)
- **おしお殿**: `.venv/bin/python3`でYAMLパース。macOS fallback(mkdir lock)。overflow protection 50件。atomic write(tmp+rename)。3リトライ
- **我々**: 623行。追加機能(サイズ差の理由):
  1. **拡張type体系(27種)**: review_draft/review_result/review_feedback/report_review/report_review_result/workaround_feedback/review_hint/analysis_result/gunshi_lesson_candidate/decomposition_feedback/verify_request/verify_result等の軍師連携type群
  2. **パストラバーサル防止+sender/target制約(HIGH-2)**: agent_config.shからallowed_targets取得→バリデーション。忍者→将軍直送禁止。ninja_monitor→karo/shogunのみ
  3. **Pre-action auto-capture**: shogun/karo送信時に送信先paneの現在状態を自動表示+shogun_action_log.txtに永続ログ。CTX:0%検知でSTALL高リスク警告
  4. **教訓注入safety net**: task_assigned送信時にrelated_lessonsが空なら、universal教訓+platform教訓を自動注入(最大10件)
  5. **報告フォーマットgate(3フェーズ)**: report_received→①gate_report_autofix.sh(21パターン自動修正)→②gate_report_format.sh(フォーマット検証)→③テンプレート状態検出(GP-071: verdict未記入/FILL_THIS残存→スキップ)→品質問題は軍師に自動ルーティング→BLOCKで忍者に修正指示
  6. **git uncommitted gate**: 報告YAML内files_modified+task内target_pathの未commitチェック→BLOCK
  7. **auto-done hook**: report_received→報告YAML存在検証→task YAMLをdoneに自動遷移

### §4b.3 inbox_watcher.sh (52.8KB vs 668行)
- **おしお殿**: `__INBOX_WATCHER_TESTING__=1`テストガード(テスト時に関数定義のみロード、mainループスキップ)。CLI種別対応(claude/codex: /new自動変換)。エスカレーション3段(0-2min通常nudge/2-4min Escape×2/4min+ /clear、5分cooldown)。ESCALATE_PHASE1/PHASE2/COOLDOWN環境変数でE2Eテスト時の時間短縮可能。idle flag初期化(CLI起動=idle前提でflag作成→false-busy deadlock防止)
- **我々**: 668行。確認結果:
  - **テストガード**: `__INBOX_WATCHER_TESTING__`相当のテスト変数はなし(grep確認0件)。ただし環境変数オーバーライドで動作制御可能(`BACKOFF_SEC`, `FORCE_IDLE_AFTER_SEC`, `INOTIFY_TIMEOUT`, `ASW_DISABLE_ESCALATION`, `ASW_PROCESS_TIMEOUT`)
  - **エスカレーション**: おしお殿の3段階(通常→Escape×2→/clear)とは異なる**リトライ+バックオフ方式**: (1)FP-CHANGE→即nudge (2)FP-SAME+retry<3→即リトライ (3)retries exhausted→BACKOFF_SEC(120秒)間隔で再通知。/clearはエスカレーションではなくclear_commandタイプの明示メッセージでのみ発火
  - **独自機能**: `maybe_force_idle_flag`(60秒以上unread放置→idleフラグ強制設定=deadlock prevention)。`get_effective_cli_type`(pane @agent_cli→settings.yaml 2段参照)。script変更時self-restart。cli_profiles.yamlのclear_method/clear_cmdで/clear動的解決(restart方式=Ctrl-C+launch_cmd対応)

### §4b.4 settings.json deny permissions
- **おしお殿**: 20パターン明示deny: `rm -rf /`, `rm -rf /*`, `rm -rf /mnt/*`, `rm -rf /mnt/c/*`, `rm -rf /home/*`, `rm -rf ~*`, `sudo *`, `su *`, `kill *`, `killall *`, `pkill *`, `git push --force*`, `git push -f *`, `git reset --hard*`, `tmux kill-server*`, `tmux kill-session*`, `mkfs*`, `dd if=*`, `chmod -R * /`, `chown -R * /`
- **我々**: 25パターン明示deny(確認済み): おしお殿の20パターン全てを含む + 独自5パターン追加:
  - `git commit --no-verify*` / `git commit * --no-verify*`（--no-verifyフル表記2パターン）
  - `git commit -n*` / `git commit * -n*`（-nショートハンド2パターン）
  - 合計: おしお殿基盤20 + hook bypass防止5 = 25パターン
- **差分**: 我々はgit hook bypass(--no-verify/-n)を4パターンで明示deny。おしお殿にこの保護はない

### §4b.5 build_instructions.sh sed置換ルール
- CLAUDE.md→AGENTS.md: `CLAUDE.md→AGENTS.md`, `instructions/shogun.md→generated/codex-shogun.md`, `~/.claude/→~/.codex/`, `Claude Code→Codex CLI`, `/clear→/new`等の17パターンsed置換。`tr -d '\r'`でCRLF正規化
- CLAUDE.md→copilot-instructions.md: `CLAUDE.md→copilot-instructions.md`, `~/.claude/→~/.copilot/`, `Claude Code→GitHub Copilot CLI`等
- CLAUDE.md→agents/default/system.md: `CLAUDE.md→agents/default/system.md`, `~/.claude/→~/.kimi/`, `Claude Code→Kimi K2 CLI`等 + agent.yaml(model: moonshot-k2.5)自動生成

### §4b.6 おしお殿CLAUDE.md YAML frontmatter
- YAML frontmatter付き(version: "3.0", updated: "2026-02-07")
- `hierarchy: "Lord (human) → Shogun → Karo → Ashigaru 1-7 / Gunshi"`
- `tmux_sessions: { shogun: {pane_0: shogun}, multiagent: {pane_0: karo, pane_1-7: ashigaru1-7, pane_8: gunshi} }`
- `files:` セクションでconfig/projects/context/cmd_queue/tasks/reports/dashboard/ntfy_inboxの正規パスを定義
- `cmd_format: required_fields: [id, timestamp, purpose, acceptance_criteria, command, project, priority, status]`
- `mcp_tools: [Notion, Playwright, GitHub, Sequential Thinking, Memory]` (Lazy-loaded)
- `bloom_routing_rule:` autoなら家老Step 6.5必須
- `language:` 戦国風日本語 or 戦国風+翻訳括弧
- 我々のCLAUDE.mdにはYAML frontmatterなし

### §4b.7 テスト数比較
- **おしお殿**: unit 9本 + E2E 12本 + root 1本(agent_selfwatch) = 22本。CI: ubuntu+macos matrix
- **我々**: unit + E2E + root = 87本。CI: ubuntuのみ

---

## §5 盗むべき技術と優先度

| 優先度 | 技術 | 工数 | 対応状況 |
|--------|------|------|---------|
| **P1** | Stop Hook settings.json登録 | 極小(1行追加) | **完了** — settings.json登録+テスト7本PASS |
| **P2** | Stop Hookにinotifywait 55秒待機追加 | 小(20行) | **完了** — inotifywait待機+INOTIFY_TIMEOUT環境変数化+テスト7本PASS |
| **P3** | Batch Processing Protocol | 小 | 実質対応済み(checklist-shin-v2-registration.md) |
| **P4** | ntfy_listener.sh corrupt_dir防御 | 小 | **完了** — corrupt_dir防御+バックアップ+テスト7本PASS(T-NTFY-006,007追加) |
| **P5** | Screenshot skill (mask/trim) | 中 | 未着手 |
| **P6** | Bloom Taxonomy DMR設計知見 | 設計参考 | 全Opus方針と異なるが、コスト圧迫時の選択肢 |
| **P7** | watcher_supervisor.sh(inbox_watcher自動再起動) | 小 | **完了** — ninja_monitorにcheck_inbox_watcher_health()追加+テスト3本PASS |
| **P8** | CI multiOS (macos追加) | 小 | 不要判断 |
| **P9** | lib/agent_status.sh分離 | 小 | 参考 |
| **P10** | 正式テスト仕様書(TDD spec) | 方法論 | 参考 |

---

## §6 最重要発見: Stop Hook未登録

### 事実
- `scripts/hooks/stop_check_inbox.sh` (113行) — cmd_648で実装。テスト(`tests/unit/test_stop_check_inbox.bats`)あり
- `.claude/settings.json` の Stop hooks にこのスクリプトが**登録されていない**
- 現在のStop hooks: (1)agent_state idle設定, (2)log_terminal_response.sh, (3)stop-lint-gate.sh

### おしお殿との差分
- おしお殿: `"Stop": [{"hooks": [{"command": "bash scripts/stop_hook_inbox.sh", "timeout": 60}]}]`
- 我々: 登録なし

### 追加すべき差分（inotifywait待機）
我々のstop_check_inbox.shにはinotifywait待機がない。おしお殿は以下のパターンで55秒待機:
```bash
# inbox未読0件の場合、55秒間ファイル変更を待つ
inotifywait -e close_write -e moved_to --timeout 55 "${WATCH_TARGETS[@]}" 2>/dev/null || true
# 待機後に再チェック → 未読あればblock
```

### 対応方針
1. settings.jsonにstop_check_inbox.sh登録（P1）
2. inotifywait待機ロジック追加（P2）
