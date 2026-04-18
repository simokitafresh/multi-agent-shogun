# GSD (Get Shit Done)

> Context Rotが品質劣化の根因。CTX残量こそが最重要KPI。メタプロンプティング+コンテキストエンジニアリング+スペック駆動開発を統合した、Claude Code向け軽量・強力なエージェントシステム。

## Basic Info

| 項目 | 値 |
|------|-----|
| Author | TÂCHES (glittercowboy) / gsd-build organization |
| Status | OSS 本番稼働中 (活発に進化) |
| Stars | **54,610** (前回 v1.22.4 時点: 28,539 → +26,071) |
| Forks | 4,580 |
| Version | **v1.37.1** (2026-04-17) |
| Last Commit | 2026-04-18 |
| Repo | https://github.com/gsd-build/get-shit-done |
| npm | https://www.npmjs.com/package/get-shit-done-cc |
| License | MIT |
| Language | JavaScript (Node.js >=22) |
| Topics | claude-code, context-engineering, meta-prompting, spec-driven-development |

## Design Philosophy

- **Context Rot根絶**: コンテキストウィンドウが埋まるにつれて品質が劣化する「Context Rot」が全品質問題の根因。CTX残量がシステムの最重要KPI
- **シンプリシティ第一**: 「複雑さはシステムの中に。ワークフローには表れない。」エンタープライズ劇場（スプリント儀式・Jiraワークフロー）を排除
- **Spec-First×Verify**: Spec → Test基盤先行 → Impl → Verify。Nyquist Validationでplan前にテストカバレッジを契約
- **要件トレーサビリティ全貫通**: REQ-IDがplanner→checker→executor→verifier全エージェントチェーンを貫通。要件サイレント削除を防止
- **信頼できる自動化**: 「品質ゲートが本物の問題を捕捉する。スキーマドリフト検出、スコープ削減検出、セキュリティ強制」— システムを信頼して任せる

> *"If you know clearly what you want, this WILL build it for you."* — ユーザーレビュー

## Architecture

### エージェント構造

| エージェント | 役割 |
|-------------|------|
| planner | 要件分析・計画生成(REQ-ID付与) |
| plan-checker | 計画の品質検証・スコープドリフト検出 |
| executor | 実装実行 |
| verifier | 実装検証・テスト実行 |
| discuss-phase | グレーエリアの並列評価・前回フェーズ知識読込 |
| debug | デバッグセッション(persistent knowledge base付き) |
| gsd-pattern-mapper | コードベースパターン分析 (v1.36.0〜) |
| gsd-sdk agent | TypeScript SDK経由の自律実行 (v1.30.0〜) |

### 実行フロー

```
Wave 0: テスト基盤先行構築 (Nyquist Validation)
  ↓
Wave N: スペック駆動実装 (REQ-ID全貫通)
  ↓
Verify Phase: 品質ゲート + テストカバレッジ確認
```

### 状態管理

- `.planning/` ディレクトリ: STATE.md + REQUIREMENTS.md + CONTEXT.md + plans/
- `STATE.md Consistency Gates` (v1.32.0〜): `state validate` でSTATE.mdとファイルシステムのドリフト検出
- `.planning/intel/` ディレクトリ: Queryable Codebase Intelligence (files/exports/symbols/patterns/dependencies)
- Global Learnings Store: フェーズ完了時に `.planning/` 外の永続ストアへ自動コピー (v1.34.0〜)
- `.planning/spikes/` + `.planning/sketches/`: フィージビリティスパイク・UIスケッチ成果物 (v1.37.0〜)

### 通信・フック

- PostToolUse hook: Context Monitor (35% WARNING / 25% CRITICAL)
- 14+ ランタイム対応: Claude Code / OpenCode / Gemini CLI / Kilo / Codex / Copilot / Cursor / Windsurf / Antigravity / Augment / Trae / Qwen Code / Cline / CodeBuddy
- インストール: `npx get-shit-done-cc@latest` (1コマンド)

## Key Features

| 機能名 | 説明 | 導入バージョン |
|--------|------|---------------|
| Nyquist Validation | plan前にテストカバレッジを契約。Wave 0でテスト基盤先行構築 | v1.x (前回時点) |
| Requirements Traceability | REQ-IDがplanner→checker→executor→verifierを全貫通 | v1.x (前回時点) |
| Context Monitor | PostToolUse hookで35% WARNING / 25% CRITICAL検出 | v1.x (前回時点) |
| 4観点独立分析 | Stack/Feat/Arch/Pitの独立分析 | v1.x (前回時点) |
| Codex multi-agent support | Codexマルチエージェント対応 | v1.22.0 |
| /gsd:ui-phase / /gsd:ui-review | UIデザイン契約生成・6柱ビジュアル監査 | v1.23.0 |
| /gsd:stats | プロジェクト統計ダッシュボード(フェーズ/計画/要件/gitメトリクス) | v1.23.0 |
| Developer Profiling Pipeline | /gsd:profile-user — 8次元行動プロファイル生成 | v1.26.0 |
| Advisor Mode | 並列エージェントでグレーエリアを評価してから意思決定 | v1.27.0 |
| Workstream Namespacing | /gsd:workstreams で並列マイルストーン作業 | v1.28.0 |
| Agent Skill Injection | agent_skills config で PJ固有スキルをサブエージェントへ注入 | v1.29.0 |
| GSD SDK | @gsd-build/sdk — TypeScript SDK + gsd-sdk init/auto CLIで自律実行 | v1.30.0 |
| Skills Migration | Claude Code 2.1.88+ skills/.claude/skills/gsd-*/SKILL.md形式 | v1.31.0 |
| /gsd:secure-phase | 脅威モデルアンカー付きセキュリティ強制レイヤー | v1.31.0 |
| STATE.md Consistency Gates | state validate/sync でSTATE.mdとファイルシステム整合性確認 | v1.32.0 |
| Autonomous Mode --to N | 指定フェーズで停止するflags: --to N / --only N / --interactive | v1.32.0 |
| Global Learnings Store | クロスセッション学習の永続CRUDライブラリ。planner自動取込 | v1.34.0 |
| Queryable Codebase Intelligence | .planning/intel/ の構造化JSONストア。gsd-tools intel サブコマンド | v1.34.0 |
| /gsd-graphify | 計画エージェント向け知識グラフ。プロジェクト成果物間の豊富な文脈接続 | v1.36.0 |
| gsd-pattern-mapper | コードベースパターン分析エージェント | v1.36.0 |
| /gsd-spike | フィージビリティスパイク: 2〜5実験 × Given/When/Then判定 | v1.37.0 |
| /gsd-sketch | UIデザインスケッチ: 2〜3インタラクティブHTMLモックアップ自動生成 | v1.37.0 |
| Agent Size-Budget Enforcement | エージェントプロンプト行数制限(XL:1600/Large:1000/Default:500)CI検出 | v1.37.0 |

## Changelog since 2026-03-13

| 日付 | バージョン | 変更 | 影響 |
|------|-----------|------|------|
| 2026-03-15 | v1.23.0 | /gsd-ui-phase + /gsd-ui-review、/gsd-stats、Copilot CLIランタイム対応 | UIフェーズの形式化 |
| 2026-03-15 | v1.24.0 | /gsd-quick --research flag、persistent debug knowledge base | 研究→計画の接続強化 |
| 2026-03-16 | v1.25.0 | Antigravityランタイム、/gsd-do (自然言語ルーター)、/gsd-note | ランタイム多様化 |
| 2026-03-18 | v1.26.0 | Developer Profiling Pipeline、/gsd-ship、/gsd-next、Cross-phase regression gate | CI品質ゲート強化 |
| 2026-03-20 | v1.27.0 | Advisor Mode、Multi-repo workspace、Cursorランタイム、/gsd-fast、/gsd-review、/gsd-plant-seed | 大規模リポジトリ対応 |
| 2026-03-22 | v1.28.0 | Workstream Namespacing、/gsd-forensics、/gsd-milestone-summary | 並列マイルストーン対応 |
| 2026-03-25 | v1.29.0 | Windsurf対応、agent skill injection、Security scanning CI、日本語/韓国語/ポルトガル語ドキュメント追加 | 多言語・セキュリティ拡充 |
| 2026-03-27 | v1.30.0 | GSD SDK (@gsd-build/sdk) — headless TypeScript SDK + gsd-sdk auto CLI | ヘッドレス自律実行が可能に |
| 2026-04-01 | v1.31.0 | Skills Migration (Claude Code 2.1.88+)、/gsd-docs-update、/gsd-secure-phase、--chainフラグ | SKILL.md形式への移行 |
| 2026-04-04 | v1.32.0 | Trae/Kilo/Augment/Clineランタイム、STATE.md Consistency Gates、Autonomous Mode --to N | 自律制御の精密化 |
| 2026-04-05 | v1.33.0 | Shared Behavioral References、CONFIG_DEFAULTS単一ソース化、テスト標準化 | 内部品質強化 |
| 2026-04-06 | v1.34.0 | Global Learnings Store、Queryable Codebase Intelligence (.planning/intel/) | クロスセッション知識永続化 |
| 2026-04-06 | v1.34.2 | Node.js最小バージョンをv24→v22に戻し (Active LTSまで対応) | 互換性維持 |
| 2026-04-11 | v1.35.0 | CodeBuddy/Qwen Code対応、/gsd-from-gsd2 逆移行 | ランタイム15種到達 |
| 2026-04-14 | v1.36.0 | /gsd-graphify (知識グラフ)、gsd-pattern-mapper、@gsd-build/sdk Phase 1 型付きクエリ | 知識グラフ統合 |
| 2026-04-17 | v1.37.0 | /gsd-spike + /gsd-sketch、Agent Size-Budget Enforcement、Shared Boilerplate Extraction | スパイク・スケッチの形式化 |
| 2026-04-17 | v1.37.1 | UI-phase researcher が /gsd-sketch 調査結果スキルを読込むバグ修正 | バグ修正 |

**前回(v1.22.4)との比較**: Stars: +26,071 (+91.3%)、バージョン: +15マイナー、対応ランタイム: 6→15種

## Notable Techniques

| テクニック名 | 説明 | このシステム固有か |
|-------------|------|-----------------|
| Nyquist Validation | plan前にテストカバレッジ契約。Wave 0でテスト基盤先行構築 | ◎ GSD独自 |
| Requirements Traceability | REQ-IDがplanner→checker→executor→verifier全チェーン貫通 | ◎ GSD独自 |
| Context Monitor | PostToolUse hookで35% WARNING / 25% CRITICAL。CTX枯渇前自動介入 | GSD実装固有 |
| 4観点独立分析 | Stack(スタック整合)/Feat(機能完全性)/Arch(アーキ健全性)/Pit(落とし穴)の独立偵察 | ◎ GSD独自(我が軍に取込済み) |
| Wave-based Parallel Execution | Wave 0でテスト基盤→Wave Nで実装。依存順序を波で制御 | GSD実装固有 |
| STATE.md Consistency Gates | state validate: STATE.mdとファイルシステムのドリフト検出 state sync: ディスク現実から再構築 | ◎ GSD独自 |
| Global Learnings Store | フェーズ完了時にプロジェクト外永続ストアへ自動コピー。planner次回自動取込 | ◎ GSD独自 |
| Agent Skill Injection | agent_skills configでPJ固有スキルをサブエージェントへ注入 | ◎ GSD独自 |
| /gsd-spike | Given/When/Then形式の2〜5フィージビリティ実験を実行し判定を残す | ◎ GSD独自 |
| Queryable Codebase Intelligence | .planning/intel/にfiles/exports/symbols/patterns/dependenciesを構造化JSON保存 | ◎ GSD独自 |
| Scope Reduction Detection | plannerがサイレントに要件を削除するのを検出するゲート | ◎ GSD独自 |
| Advisor Mode | 並列エージェントがグレーエリアを評価→ユーザーが決定。推薦先行+WHY形式 | GSD/gstack類似 |
| Cross-phase Regression Gate | executeフェーズが前フェーズのテストスイートも実行。リグレッション防止 | ◎ GSD独自 |
| Developer Profiling Pipeline | Claudeセッション履歴を分析し8次元行動プロファイルをUSER-PROFILE.mdに生成 | ◎ GSD独自 |

## Ecosystem

| カテゴリ | 名前 | 説明 |
|----------|------|------|
| Community | Discord | https://discord.gg/mYgfVNfA2r — コミュニティサーバー |
| Community | X (@gsd_foundation) | 公式X (旧Twitter) アカウント |
| Forks | 4,580 フォーク | コミュニティフォーク多数 |
| npm | get-shit-done-cc | https://www.npmjs.com/package/get-shit-done-cc |
| SDK | @gsd-build/sdk | headless TypeScript SDK。CI/CD・自動化スクリプトからGSDを制御 |
|派生 | gsd-teams | チーム対応GSD拡張 (前回調査) |
| 派生 | gsd-orchestrator | /clear自動化 (前回調査) |
| 派生 | GSD-LAW | 法律文書向けGSD拡張 (前回調査) |
| 競合 | UCAI | BMAD・Speckit・Taskmaster等の競合ツール群 |
| $GSD Token | Dexscreener/Solana | コミュニティトークン (投機的) |
| Docs | 多言語 | 英語/日本語/韓国語/中国語/ポルトガル語 (v1.29.0〜) |

**対応ランタイム (15種, 2026-04-18時点)**:
Claude Code, OpenCode, Gemini CLI, Kilo, Codex, Copilot, Cursor, Windsurf, Antigravity, Augment, Trae, Qwen Code, Cline, CodeBuddy + All (一括インストール)

## Sources

| 種別 | URL |
|------|-----|
| Repository | https://github.com/gsd-build/get-shit-done |
| npm | https://www.npmjs.com/package/get-shit-done-cc |
| README (日本語) | https://github.com/gsd-build/get-shit-done/blob/main/README.ja-JP.md |
| CHANGELOG | https://github.com/gsd-build/get-shit-done/blob/main/CHANGELOG.md |
| User Guide | https://github.com/gsd-build/get-shit-done/blob/main/docs/USER-GUIDE.md |
| Releases | https://github.com/gsd-build/get-shit-done/releases |
| Discord | https://discord.gg/mYgfVNfA2r |
| X | https://x.com/gsd_foundation |
| SDK | https://github.com/gsd-build/get-shit-done/tree/main/sdk |

## Verification

| 項目 | 値 |
|------|-----|
| verified_at | 2026-04-19T00:00:00+09:00 |
| method | GitHub API (gh api repos/gsd-build/get-shit-done) + releases API + README fetch |
| source | github.com/gsd-build/get-shit-done 公式リポジトリ直接取得 |
| stars_verified | 54,610 (API取得。前回28,539から+26,071) |
| version_verified | v1.37.1 (2026-04-17。前回v1.22.4から15マイナーバージョン進化) |
| changelog_source | GitHub Releases API (直近25リリース全文確認) |
