# 6システム対比分析 — cmd_709
<!-- created: 2026-03-09 cmd_709 tobisaru -->
<!-- systems: ACE / Vercel / GSD / Claude Teams / おしお殿 / 我が軍 -->

> 中立プロンプト原則: 事実ベースで対比。各システムの長所を正当に評価し、我が軍の弱点も率直に報告。

## §1 おしお殿(yohey-w/multi-agent-shogun) 深掘り調査

### §1.1 リポジトリ概要（2026-03-09時点）

| 項目 | 値 |
|------|------|
| Stars | 1,035（前回991→+44） |
| Forks | 233 |
| 言語 | Shell |
| 最終push | 2026-03-09 |
| ライセンス | MIT |
| 編成 | 将軍+家老+足軽7名+軍師(Gunshi) = 10名 |
| tmux | shogun + multiagent 2セッション |
| CLI対応 | Claude Code / OpenAI Codex / GitHub Copilot / Kimi K2（4種） |

### §1.2 直近30日の主要変更（2026-02-08〜03-09）

#### Androidコンパニオンアプリ（v1.0→v4.1）— 最大の新機能
- SSH経由でtmuxセッションにリモート接続
- エージェント一覧画面（ANSI描画対応）
- ダッシュボード画面
- Rate limit監視（Codex /status対応）
- ntfy通知連携
- 音声入力（連続認識、BGMダッキング）
- BGM 3トラック切替
- スクリーンショット共有
- **我が軍にない**: モバイルからのリアルタイム監視・操作UI

#### Agent Self-Watch (ASW) 3フェーズ
- Phase 1: 通常nudge
- Phase 2: idle-aware nudge抑制（flag file方式）
- Phase 3: 最終escalation（/clear送信）
- watcher_supervisor.sh: 5秒おき生存監視
- **flag file idle検知**: pane-based → flag file に全面移行。false-busy deadlock防止

#### Dynamic Model Routing（Bloom Taxonomy）
- L1-L3=足軽、L4-L6=軍師。bloom_routing: auto/manual/off
- bloom_model_preference: タスク難度に応じたモデル優先度ルーティング
- Haiku 4.5 L2→L3昇格、Sonnet 4.6追加
- capability_tiers更新
- **我が軍との差異**: 我が軍はround-robin配備（Bloom分類なし）

#### Multi-CLI抽象化
- `lib/cli_adapter.sh`: get_cli_type / build_cli_command / get_instruction_file / get_agent_model
- `instructions/generated/`: Claude/Codex/Copilot/Kimi × 4ロール = 16種の自動生成指示書
- `instructions/cli_specific/`: CLI固有ツール指示（claude_tools.md, codex_tools.md, copilot_tools.md, kimi_tools.md）
- Codex /clear→/new自動変換

#### YAML Slim（コンテキスト圧縮）
- `slim_yaml.sh` / `slim_yaml.py`: 完了タスク/報告/inboxデータをスリム化
- slim_tasks / slim_reports / slim_all_inboxes 3機能
- --dry-runサポート、flock排他
- 軍師(Gunshi)は作業前にslim実行（トークン節約）

#### Compaction復帰強化（2026-03-09 最新）
- `fix(compaction): enforce persona restoration after context compaction`
- compaction後にpersona（戦国口調）が消失する問題への対策

#### CI/CD
- GitHub Actions: unit/e2e/shellcheck/build-check
- E2E 12テストスイート（basic_flow, bloom_routing, busy_clear_guard, clear_recovery, codex_startup, escalation, idle_flag_recovery, inbox_delivery, parallel_tasks, redo, slim_retention, blocked_by）
- batsテストフレームワーク
- mock CLI（claude_behavior.sh, codex_behavior.sh）

#### Skills（6個）
- shogun-agent-status, shogun-bloom-config（ウィザード型）, shogun-model-list, shogun-model-switch, shogun-readme-sync, skill-creator

#### その他
- bash 3.2互換（macOS対応: shebang統一, mapfile→while loop, fswatch fallback）
- Stop Hook primary delivery（Claude Code agents向け）
- subscription patternサポート（available_cost_groups filtering）
- ntfy解放修正（3つのblocking mechanism除去）
- SEO品質チェック（seo_qc.sh/py）
- first_setup.sh + MEMORY.md auto-init

### §1.3 cmd_649-658（2026-03-08）以降の差分

| コミット | 日付 | 内容 |
|---------|------|------|
| 2ef81f9 | 2026-03-09 | compaction後のpersona復元強制 |

**差分は1件のみ**。cmd_649-658時点からの機能追加はほぼなし。直近30日の大半の変更は2026-02-17〜03-03に集中。

### §1.4 おしお殿の独自の強み（我が軍にないもの）

| # | 機能 | 詳細 | 我が軍の状況 |
|---|------|------|------------|
| 1 | **Androidコンパニオンアプリ** | SSH接続、エージェント監視、音声入力、BGM、ntfy連携。Kotlin/Jetpack Compose | モバイルUIなし。ntfyテキスト通知のみ |
| 2 | **軍師(Gunshi)** | 独立QCロール。Bloom L4-L6担当。戦略分析+品質チェック | QC専門ロールなし（家老がレビュー兼務） |
| 3 | **4CLI対応** | Claude/Codex/Copilot/Kimi。cli_adapter.shで差異吸収 | 2CLI（Claude/Codex）のみ |
| 4 | **Bloom Levelルーティング** | タスク難度→モデル自動割当。L1-L3足軽、L4-L6軍師 | round-robin（難度ベースなし） |
| 5 | **ASW 3フェーズ** | 段階的escalation（nudge→抑止→/clear） | ninja_monitorが類似機能だがフェーズ明示なし |
| 6 | **CI/CD** | GitHub Actions + bats E2E 12テスト | 手動テストのみ |
| 7 | **macOS互換** | bash 3.2対応、fswatch fallback | WSL2専用 |
| 8 | **YAML Slim** | 軍師作業前のトークン節約自動化 | archive_completed.shは完了後のみ |
| 9 | **Flag file idle検知** | pane capture-pane依存を排除 | capture-pane依存（L114で課題認識あり） |
| 10 | **OSS公開** | 1,035 stars、MIT License | 非公開 |

---

## §2 GSD (Get Shit Done) プロファイル

### §2.1 概要

| 項目 | 値 |
|------|------|
| リポジトリ | gsd-build/get-shit-done |
| Stars | 26,786 |
| 言語 | JavaScript |
| 最終push | 2026-03-03 |
| バージョン | v1.22.4 |
| 対応CLI | Claude Code / OpenCode / Gemini CLI / Codex |
| インストール | `npx get-shit-done-cc@latest` |

### §2.2 アーキテクチャ

- **シングルセッション型**: マルチエージェントではない。1つのClaude Codeセッション内でサブエージェントを使い分け
- **12エージェント定義**: planner, executor, verifier, debugger, codebase-mapper, integration-checker, nyquist-auditor, phase-researcher, plan-checker, project-researcher, research-synthesizer, roadmapper
- **34ワークフロー**: new-project, plan-phase, execute-phase, verify-phase, research-phase, debug, progress, pause-work, resume-project, etc.
- **3フック**: gsd-statusline.js（CTX使用率→bridge file）, gsd-context-monitor.js（PostToolUse、CTX残量警告注入）, gsd-check-update.js
- **スラッシュコマンド**: `/gsd:new-project`, `/gsd:execute-phase`, `/gsd:verify-work` 等

### §2.3 核心設計思想

1. **Context Rot解決**: CTXウィンドウが埋まるにつれ品質劣化する問題を体系的に対処
2. **Spec-Driven Development**: Project→Milestone→Phase→Taskの4層管理
3. **Fractal Summaries**: Phase完了時にSUMMARY.md自動生成。次Phase開始時にロードして文脈継続
4. **4段階検証ラダー**: Exists→Substantive→Wired→Functional（スタブ自動検出）
5. **Nyquist Auditor**: Phase粒度が適切かを監査（細かすぎ/粗すぎを検出）
6. **Context Monitor**: PostToolUseフックでCTX残量を監視、35%/25%で警告注入→/gsd:pause-work促進
7. **Goal-backward verification**: タスク完了≠ゴール達成。ゴールから逆算して検証

### §2.4 GSDの独自の強み（我が軍にないもの）

| # | 機能 | 詳細 | 我が軍の状況 |
|---|------|------|------------|
| 1 | **4段階検証ラダー** | Exists→Substantive→Wired→Functional。スタブ自動検出パターン豊富 | GATE CLEAR（機械検査）はあるがスタブ検出なし |
| 2 | **Nyquist Auditor** | Phase粒度の適切さを監査 | タスク粒度の自動監査なし |
| 3 | **Context Monitor（bridge file方式）** | statusline→JSONファイル→PostToolUseフック→agent警告注入 | autocompact(90%)のみ。段階警告なし |
| 4 | **Fractal Summaries** | Phase完了時にSUMMARY.md自動生成→次Phase継続 | cmd-chronicle.md + archive（1行要約） |
| 5 | **マルチCLI対応** | Claude/OpenCode/Gemini/Codex 4種 | Claude/Codexの2種 |
| 6 | **コミュニティ規模** | 26,786 stars, Discord, npm | 非公開 |
| 7 | **Analysis Paralysis Guard** | 分析麻痺を検知して前進を促す | なし |
| 8 | **Goal-backward verification** | ゴールから逆算して検証（タスク完了≠ゴール達成） | AC照合はあるがゴール逆算の明示的概念なし |

---

## §3 既知システム確認

### §3.1 ACE (Agentic Context Engineering)

前回調査（cmd_473）から変化なし。ICLR 2026採択済み。
- 構造: Generator→Reflector→Curator（固定3役割パイプライン）
- 核心: delta形式の教訓蓄積+semantic dedup+人間不要の完全自動
- 実績: AppWorld +10.6%、トークンコスト83.6%削減
- → `docs/research/five-system-comparison.md` §4.1

### §3.2 Vercel Context Engineering

前回調査（cmd_473）から変化なし。
- 核心: 受動(100%)>能動(79%)、ツール80%削減
- AGENTS.md + Skills + filesystem
- → `docs/research/five-system-comparison.md` §4.2

### §3.3 Claude Code Agent Teams

**最新状態確認**（2026-03-09時点）:
- まだexperimental（`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`必要）
- 2モード: in-process（デフォルト）/ split panes（tmux/iTerm2）
- lead→teammate構造は変わらず
- **新情報**: Shift+Down でteammate切替、Ctrl+T でタスクリスト表示
- **新フック**: TeammateIdle（exit 2でフィードバック）、TaskCompleted（exit 2で完了阻止）
- Plan Approval: teammateに計画承認を要求可能
- 依存タスクの自動unblock機能
- **変わらぬ制限**: セッション再開不可、1チーム/セッション、ネスト不可、リード固定

---

## §4 6システム対比表（14軸）

### §4.1 構造・階層

| 軸 | 我が軍 | おしお殿 | GSD | ACE | Vercel | Claude Teams |
|----|--------|---------|-----|-----|--------|-------------|
| **エージェント構造** | 4層(殿→将軍→家老→忍者8) | 4層(殿→将軍→家老→足軽7+軍師) | 1層+サブエージェント12 | 3役割パイプライン | 1層(単体) | 2層(lead→teammate 3-5) |
| **エージェント数** | 10(将軍1+家老1+忍者8) | 10(将軍1+家老1+足軽7+軍師1) | 1(+12サブエージェント) | 3 | 1 | 3-5推奨 |
| **モデル混成** | Opus4+Codex4(GPT-5.4) | Claude+Codex+Copilot+Kimi | 単一+モデルプロファイル | 単一 | 単一(Opus推奨) | 任意指定可 |
| **指揮系統** | 鎖(一本、分岐なし迂回なし) | 階層制+軍師QC分岐 | メタプロンプト→ワークフロー | 線形パイプライン | なし | リード集約 |

### §4.2 コンテキスト管理

| 軸 | 我が軍 | おしお殿 | GSD | ACE | Vercel | Claude Teams |
|----|--------|---------|-----|-----|--------|-------------|
| **CTX崩壊防止** | Vercel式2層圧縮+autocompact(90%)+/clear+archive | slim_yaml(完了退避)+/clear Recovery | Context Monitor(35%/25%警告)+Fractal Summaries+pause-work | delta蓄積+semantic dedup | 3層パイプライン(注入→補正→後処理) | 独立CTX窓(各teammate) |
| **知識永続化** | 6層(CLAUDE.md/instructions/projects/lessons/queue/MCP) | 4層(MCP/PJファイル/YAML/セッション) | state.md+milestone.md+phase SUMMARY.md | playbook(テキスト) | AGENTS.md+Skills+Registry | CLAUDE.md自動ロード(セッション消滅で喪失) |
| **復帰耐性** | 陣形図(karo_snapshot)+SessionStart hook+inbox | /clear Recovery+enqueue_recovery+flag file | /gsd:resume-work+continue-here.md | playbook再読込 | AGENTS.md再読込 | 再開不可(in-process teammate) |

### §4.3 品質・検証

| 軸 | 我が軍 | おしお殿 | GSD | ACE | Vercel | Claude Teams |
|----|--------|---------|-----|-----|--------|-------------|
| **品質ゲート** | GATE(BLOCK/CLEAR強制)+機械検査7項目 | — | 4段階検証ラダー(Exists→Substantive→Wired→Functional)+Nyquist Auditor | Evaluator(自動) | Sandbox検証 | Plan Approval+TeammateIdle/TaskCompleted hook |
| **レビュー** | 別忍者コードレビュー必須 | 軍師(Gunshi)QC | gsd-verifier(Goal-backward) | Reflector(自動批評) | 人間レビュー | リード承認 |
| **実績計測** | GATE CLEAR率99%+、連勝291、手戻り率1.3% | selfwatch metrics+SayTask streaks | なし（成功率の間接計測） | AppWorld +10.6% | 成功率80→100% | なし |

### §4.4 知識サイクル

| 軸 | 我が軍 | おしお殿 | GSD | ACE | Vercel | Claude Teams |
|----|--------|---------|-----|-----|--------|-------------|
| **教訓蓄積** | 8段階(発見→登録→注入→活用→帰属→計測→表示→淘汰) | MCP Memory自由形式+skill_candidate | なし | 3段階(生成→反映→統合) | なし(手動) | なし |
| **教訓注入** | タグマッチ+MAX_INJECT=5+自動退役 | MCP Memory読込 | なし | 全量orサンプリング | 静的埋込み | なし |
| **効果計測** | helpful/injection_count+効果率監視+自動退役 | なし | なし | helpful/harmful dual counter | なし | なし |

### §4.5 通信・協調

| 軸 | 我が軍 | おしお殿 | GSD | ACE | Vercel | Claude Teams |
|----|--------|---------|-----|-----|--------|-------------|
| **通信方式** | ファイルmailbox(flock)+inotify nudge | ファイルmailbox(flock)+inotify+3フェーズASW | なし(単体) | パイプライン直列 | なし(単体) | SendMessage+broadcast+SharedTaskList |
| **並列実行** | ファイル依存分析→parallel_with | 並列配備+Bloom routing | Wave並列(サブエージェント) | バッチ並列 | なし | worktree隔離+自己claim |
| **人間との連携** | 殿→将軍→家老(鎖) | 殿→将軍→家老(鎖)+ntfy_inbox | `/gsd:*`コマンド(対話型) | 人間なし(全自動) | Human-in-the-loop | リード経由(直接対話可) |

### §4.6 安全性・運用

| 軸 | 我が軍 | おしお殿 | GSD | ACE | Vercel | Claude Teams |
|----|--------|---------|-----|-----|--------|-------------|
| **安全防御** | D001-D008+PreToolUse shlex+WSL2保護 | D001-D008+settings.json deny+WSL2保護 | `--dangerously-skip-permissions`推奨 | なし | Sandbox検証 | Hooks+Permission設定 |
| **Git戦略** | whitelist .gitignore+commit前確認 | .gitattributes+CI shellcheck | git integration(tag, milestone) | なし(ベンチマーク) | なし | worktree隔離 |
| **セットアップ容易性** | 複雑(tmux+WSL2+8忍者手動) | 中程度(first_setup.sh+macOS互換+CI) | 簡単(`npx`一発) | 中程度(Python環境) | 簡単(AGENTS.md配置) | 簡単(設定1行) |
| **拡張性** | スキル追加+PJ切替+仙人構想 | スキル6個+CLI追加容易 | ワークフロー/エージェント追加 | Reflector調整 | Skills追加 | Hooks拡張 |

---

## §5 各システムの「我が軍にない独自の強み」

| # | システム | 独自の強み | 影響度 | 詳細 |
|---|---------|----------|--------|------|
| 1 | **おしお殿** | Androidコンパニオンアプリ | 高 | モバイルからリアルタイム監視・操作。SSH+ANSI描画+音声入力。我が軍はntfyテキストのみ |
| 2 | **おしお殿** | 4CLI対応（Copilot/Kimi追加） | 中 | cli_adapter.sh抽象化+16種自動生成指示書。我が軍は2CLI |
| 3 | **おしお殿** | Bloom Levelルーティング | 中 | タスク難度→モデル自動割当。コスト最適化に直結 |
| 4 | **おしお殿** | CI/CD(E2E 12テスト) | 中 | batsテスト基盤。自動回帰検知。我が軍は手動テスト |
| 5 | **おしお殿** | Flag file idle検知 | 低 | capture-pane依存排除。我が軍もL114で課題認識済み |
| 6 | **GSD** | 4段階検証ラダー | 高 | Exists→Substantive→Wired→Functional。スタブ自動検出。GATE CLEARにない視点 |
| 7 | **GSD** | Context Monitor(bridge file) | 中 | CTX残量をagentに段階警告注入。autocompactより先に手を打てる |
| 8 | **GSD** | Nyquist Auditor | 低 | タスク粒度の適切さ監査。過分解/粗すぎを検出 |
| 9 | **GSD** | Goal-backward verification | 中 | タスク完了≠ゴール達成。ゴールから逆算検証 |
| 10 | **GSD** | コミュニティ規模(26k stars) | 高 | エコシステム(Discord, npm, 派生プロジェクト多数) |
| 11 | **ACE** | 完全自動教訓サイクル | 中 | 人間不要。Reflector→Curator。学術ベンチ証明済み |
| 12 | **ACE** | Semantic dedup | 低 | embedding類似度で教訓重複自動排除 |
| 13 | **Claude Teams** | worktree隔離 | 低 | git worktree自動作成。ファイル衝突根絶 |
| 14 | **Claude Teams** | Teammate直接対話 | 低 | リード経由せず個別指示可能。Shift+Down操作 |
| 15 | **Vercel** | ツール80%削減の哲学 | 中 | 最小構成で最大効果。複雑さの排除 |

## §6 「我が軍が上回っている点」

| # | 軸 | 我が軍の優位 | 対象システム |
|---|------|------------|------------|
| 1 | **教訓サイクルの深さ** | 8段階(発見→淘汰)+152件蓄積+タグマッチ注入+自動退役+効果率監視。他は3段階以下またはなし | 全6システム |
| 2 | **組織統制の厳密さ** | 4層階層+鎖の原理+禁則体系(D001-D008+F001-F008)。構造的に越権不可能 | 全6システム |
| 3 | **GATE品質計測** | CLEAR率99%+、連勝291、手戻り率1.3%。定量的に品質を追跡する唯一のシステム(ACE除く) | おしお殿/GSD/Teams/Vercel |
| 4 | **復帰耐性** | 陣形図(karo_snapshot)+SessionStart hook+inbox永続。compaction/crash後も完全復帰 | 全6システム(ACEはstatelessで別設計) |
| 5 | **安全防御の網羅性** | D001-D008(絶対禁止)+PreToolUse shlex(パイプ解析)+WSL2保護。3層防御 | 全6システム(GSDはskip-permissions推奨で対極) |
| 6 | **知識管理の層数** | 6層(CLAUDE.md/instructions/projects/lessons/queue/MCP)+Vercel式2層圧縮 | 全6システム |
| 7 | **実戦実績の蓄積** | 700+ cmd完了、190+教訓蓄積、連勝291。production稼働証明 | GSD(実績公開なし)/Teams(実績なし) |
| 8 | **通信の信頼性** | flock排他+inotify+nudge 2層保証。メッセージ永続化+wake-up信号分離 | Teams(lead compactionで喪失)/ACE(パイプライン内のみ) |
| 9 | **モデル混成** | Opus4+GPT-5.4(Codex4)異種モデル協調。単一ベンダーに非依存 | GSD/ACE/Vercel(単一モデル) |

---

## §7 総合評価マトリクス（10点満点、14軸）

| # | 軸 | 我が軍 | おしお殿 | GSD | ACE | Vercel | Teams |
|---|------|--------|---------|-----|-----|--------|-------|
| 1 | コンテキスト管理 | 9 | 7 | 8 | 7 | 8 | 5 |
| 2 | マルチエージェント協調 | 9 | 9 | 4 | 6 | 1 | 7 |
| 3 | 状態管理・復帰 | 10 | 8 | 7 | 5 | 4 | 3 |
| 4 | 知識永続化 | 10 | 6 | 5 | 7 | 7 | 3 |
| 5 | 品質ゲート | 9 | 5 | 8 | 7 | 6 | 6 |
| 6 | Git戦略 | 7 | 8 | 6 | 2 | 3 | 7 |
| 7 | 復帰機構 | 10 | 8 | 7 | 5 | 4 | 2 |
| 8 | 検証機構 | 8 | 6 | 9 | 7 | 6 | 6 |
| 9 | 拡張性 | 7 | 8 | 8 | 4 | 7 | 6 |
| 10 | 運用実績 | 10 | 7 | 5 | 8 | 7 | 3 |
| 11 | 通信方式 | 9 | 9 | 1 | 5 | 1 | 7 |
| 12 | 人間との連携 | 8 | 9 | 8 | 2 | 8 | 7 |
| 13 | 安全性 | 10 | 10 | 2 | 3 | 3 | 6 |
| 14 | セットアップ容易性 | 3 | 5 | 9 | 5 | 9 | 8 |
| **合計** | **119** | **105** | **83** | **73** | **74** | **76** |

### 評価根拠

| 軸 | 高評価の根拠 | 低評価の根拠 |
|----|------------|------------|
| コンテキスト管理 | GSD: bridge file+段階警告。我が軍: 6層+2層圧縮 | Teams: セッション消滅で喪失 |
| マルチエージェント | 我が軍/おしお殿: 10名+4層階層 | GSD: 単体+サブエージェント。Vercel: 単体 |
| 状態管理 | 我が軍: 陣形図+YAML永続+hook完全復帰 | Teams: in-process再開不可 |
| 品質ゲート | GSD: 4段階検証ラダー+スタブ検出。我が軍: GATE BLOCK/CLEAR | おしお殿: GATE相当なし |
| 検証機構 | GSD: Goal-backward+Nyquist。我が軍: GATE+レビュー忍者 | Vercel/Teams: 限定的 |
| 安全性 | 我が軍/おしお殿: D001-D008+構造防御 | GSD: skip-permissions推奨。ACE: 防御なし |
| セットアップ | GSD: npx一発。Vercel: AGENTS.md配置 | 我が軍: tmux+WSL2+8忍者 |
| 人間との連携 | おしお殿: Android app+ntfy。GSD: 対話型コマンド | ACE: 人間なし(全自動) |

---

## §8 おしお殿との差分サマリ（前回cmd_473→今回cmd_709）

### 前回から変わった点
- Stars: 991→1,035（+44）
- Android app: なし→v4.1（最大の変化）
- Bloom QC routing: 基本実装→Gunshiトークン最適化
- YAML Slim: なし→slim_tasks/slim_reports/slim_all_inboxes
- E2E: 基本→12テストスイート
- bash 3.2互換: 部分的→全面対応(shebang統一+fallback)
- Compaction復帰: なし→persona強制復元

### 変わらなかった点
- 教訓正式サイクル: 依然なし（MCP自由形式のみ）
- GATE CLEAR相当: 依然なし
- Vercel式圧縮規律: 依然なし
- 陣形図(karo_snapshot): 依然なし

### 我が軍で進化した点（おしお殿にない）
- 教訓: 152件蓄積、タグマッチ注入、MAX_INJECT=5、自動退役、効果率監視
- GATE: CLEAR率99%+、連勝291
- モデル混成: Opus4+GPT-5.4(Codex4)
- インフラ: ntfy listener dual watchdog、CMD年代記、context未更新ゲート
- 知識: Vercel式2層圧縮規律（索引+詳細分離）

---

## §9 参考文献

### GSD
- [GitHub: gsd-build/get-shit-done](https://github.com/gsd-build/get-shit-done) — 26,786 stars
- docs/context-monitor.md（CTX Monitor設計）
- agents/gsd-verifier.md（Goal-backward verification）
- get-shit-done/references/verification-patterns.md（4段階検証ラダー）

### おしお殿
- [GitHub: yohey-w/multi-agent-shogun](https://github.com/yohey-w/multi-agent-shogun) — 1,035 stars
- instructions/gunshi.md（軍師ロール定義）
- lib/cli_adapter.sh（Multi-CLI抽象化）
- scripts/slim_yaml.sh（YAML Slim）

### Claude Teams
- [Orchestrate teams of Claude Code sessions](https://code.claude.com/docs/en/agent-teams)

### ACE / Vercel
- → `docs/research/five-system-comparison.md` 参考文献セクション参照（変更なし）
