# おしお殿 (shio_shoppaize) — multi-agent-shogun

> 多くのCLI・多くの環境・多くの人が使えることが価値。OSS公開・Bloom Taxonomy自動ルーティング・CoDD(整合性駆動開発)を統合した、Claude Code向けマルチエージェント将軍システム。

## Basic Info

| 項目 | 値 |
|------|-----|
| Author | shio_shoppaize (GitHub: yohey-w) |
| Status | OSS 本番稼働中 (活発に進化) |
| Stars | **1,220** (前回 v4.0 時点: 1,045 → +175) |
| Forks | 258 |
| Version | **v4.4.2** (2026-04-10) |
| Last Commit | 2026-04-10 |
| Repo | https://github.com/yohey-w/multi-agent-shogun |
| Zenn | https://zenn.dev/shio_shoppaize (36記事) |
| CoDD | https://github.com/yohey-w/codd-dev (`pip install codd-dev`) |
| License | MIT |
| Language | Bash / Python (ハーネス層) |

## Design Philosophy

- **アクセシビリティ優先**: 「多くのCLI・多くの環境・多くの人が使えることが価値」。4 CLIサポート(Claude/Codex/Gemini/Cursor)、macOS/WSL2/Androidに対応
- **Judgment Criteria Is All You Need**: コンテキスト設計の本質は「判断基準の置き場所」。LoRAで判断基準をモデル重みに焼き込むことが本質的解決策という仮説を持つ
- **CoDD (Coherence-Driven Development)**: Prompt → Context → Harness の三層をcohesion(整合性)で結びつける。設計書が腐らないOSSを目指す
- **OSS第一**: 個人利用に特化せず、誰でも fork → 自軍として使えるセットアップを重視

## Architecture

### エージェント構造

| エージェント | 役割 | モデル |
|-------------|------|--------|
| 将軍 | 意思決定・cmd発令 | Opus |
| 家老 | 采配・品質管理 | Sonnet (自己降格提案あり) |
| 軍師 | 考える専門家・レビュー (v3.4〜) | Opus |
| 足軽 (×7) | 実装担当・並列実行 | Sonnet/GPT切替可 |

### 通信・記憶・品質保証

| 観点 | 実装 |
|------|------|
| 通信方式 | YAML + inbox_write + inotifywait |
| 記憶 | MCP + 3層 (CLAUDE.md / instructions / context) |
| 品質ゲート | 軍師QC (レビュー専任) |
| コンテキスト管理 | Global Context + Bloom Taxonomy routing |
| タスクルーティング | L1-L3 (単純) → 足軽, L4-L6 (複雑) → 軍師 |
| CI/CD | GitHub Actions連携あり |
| ブラウザ | CDP直接操作 |
| モバイル | Android Companion App (SSH + 音声 + 8ペイン + dashboard) |

## Key Features

| 機能名 | 説明 | 導入バージョン |
|--------|------|--------------|
| Bloom Taxonomy ルーティング | L1-L3→足軽, L4-L6→軍師。認知複雑度に基づく自動振り分け | v4.0 |
| Android Companion App | SSH+音声入力+8ペイン表示+スクショ共有 | v4.0 |
| 軍師ロール | 「考える専門」Opus専任。家老はSonnetに自己降格 | v3.4 |
| Flag File Busy Detection | 足軽idle検知。48回の修正試行の末に到達した解法 | v3.8 |
| `--effort max` デフォルト | 全エージェント起動時に `--effort max` を自動適用 | v4.3.0 |
| karo daily log | 家老の日次作業ログ自動追記 (`logs/daily/YYYY-MM-DD.md`) | v4.4.0 |
| OSSスキル自動インストール | `first_setup.sh` で `~/.claude/skills/` に公式スキル一括配備 | v4.4.2 |
| GitHub Sponsors | スポンサー支援受付開始 | 2026-04-10 |
| CoDD統合 | 設計書パイプラインとハーネス整合性検証を多エージェント環境に適用 | v4.4.x |
| Thinking無効化 | MAX_THINKING_TOKENS=0 で将軍を「考えるな、委譲しろ」に最適化 | — |

## Changelog since 2026-03-13

| 日付 | バージョン | 変更 | 影響 |
|------|-----------|------|------|
| 2026-03-14 | v4.1.2 | stop_hookのshogunペイン除外バグFix | 将軍ペインが誤停止される問題を解消 |
| 2026-03-14 | v4.1.3 | model-switchスキルにargument-hint追加 | モデル切替操作の UX 向上 |
| 2026-03-24 | v4.2.0 | install.batのWSL $HOME動的解決・パス相対化 | Windows環境でのポータビリティ向上 |
| 2026-03-27 | v4.3.0 | 全エージェント起動時に `--effort max` デフォルト適用 | 応答品質の底上げ |
| 2026-03-27 | v4.4.0 | karo daily log自動追記・`.gitignore`にsettings.local.json追加 | 家老の作業履歴の永続化 |
| 2026-03-28 | v4.4.1 | Android版ratelimit表示修正・SSH秘密鍵改善・Codexステータス切り詰め対策 | モバイルUI安定化 |
| 2026-04-10 | v4.4.2 | `first_setup.sh`でOSSスキルを`~/.claude/skills/`に自動インストール (Issue #117 Fix) | 初回セットアップの自動化 |
| 2026-04-10 | — | GitHub Sponsors対応 (FUNDING.yml追加・README両言語更新) | OSS持続可能性強化 |

### CoDD (codd-dev) — 同作者の別ツール

| 日付 | バージョン | 変更 |
|------|-----------|------|
| 2026-03-29 | v0.2.0a2 | α版公開。propagation方向修正・日本語README追加 |
| 2026-04-01 | v1.2.1 | `codd hooks install` FileNotFoundError修正 |
| 2026-04-06 | v1.5.1 | `codd measure`クラッシュ修正・`codd validate`誤検出修正 |
| 2026-04-06 | v1.6.0 | **OSS/Pro分割**: review/verify/audit/riskをcodd-pro(非公開)に移管 |
| 〜2026-04-14 | v1.8.0 | codd extract・codd impact・codd fix追加。SWE-bench 73問 100%達成 (記事より) |

## Notable Techniques

| テクニック名 | 説明 | このシステム固有か |
|-------------|------|-----------------|
| Bloom Taxonomy ルーティング | 認知複雑度(L1-L6)でタスクを足軽/軍師に自動振り分け | 固有 |
| Flag File Busy Detection | ファイルの存在でidle/busy状態を管理。48回の試行で収束 | 固有 |
| Thinking無効化 (MAX_THINKING_TOKENS=0) | 将軍のthinkingを無効化し「考えずに委譲」を強制 | 固有 |
| 家老の自己降格提案 | AI自身がコスト効率を理由にモデルダウングレードを提案 | 固有 |
| CoDD — 整合性駆動開発 | Spec→Context→Harnessの三層整合性を設計書パイプラインで担保 | 固有 |
| Judgment Criteria Is All You Need | 判断基準の置き場所がコンテキスト設計の本質、という設計仮説 | 固有 |
| 7つの未解決問題 | コンテキスト分散の形式理論・N二乗通信問題等を公開課題として明記 | 固有 |

## Ecosystem

### コミュニティ・記事

| 種別 | 内容 |
|------|------|
| Zenn総記事数 | **36本** (2026-04-19時点。前回: 26本) |
| GitHub Sponsors | 2026-04-10開設 |
| コントリビューター | terao-ryohei 他 (PR #95, #111 等) |

### 2026-03-13以降の主要Zenn記事

| タイトル | 日付 | URL |
|---------|------|-----|
| Googleが「SKILL.mdの5パターン」を発表したので、将軍の5パターンと殴り合わせた | 2026-03-22 | https://zenn.dev/shio_shoppaize/articles/shogun-skill-patterns-google |
| ハーネスエンジニアリング、それGit Workflowをbashで書き直してるだけでは | 2026-03-28 | https://zenn.dev/shio_shoppaize/articles/shogun-harness-engineering |
| Prompt→Context→Harness、全部やった。整合性駆動開発CoDD爆誕 | 2026-03-29 | https://zenn.dev/shio_shoppaize/articles/shogun-codd-coherence |
| Harness as Code — CoDD活用ガイド #4 60%の天井をぶち破れ、放置で93%直る自律ループ | 2026-04-11 | https://zenn.dev/shio_shoppaize/articles/codd-swebench-loop |
| CoDD（整合性駆動開発）— コード0行・スマホだけで、設計書が腐らないOSSを作った話 | 2026-04-14 | https://zenn.dev/shio_shoppaize/articles/codd-skeleton-complete |

### 関連リポジトリ

| リポジトリ | 説明 | Stars |
|-----------|------|-------|
| yohey-w/codd-dev | CoDD: Coherence-Driven Development | 49 |
| yohey-w/shogun-speech-2-text | デスクトップ音声認識ツール (Deepgram Nova-3) | 5 |

## Sources

| 種別 | URL |
|------|-----|
| Repository (main) | https://github.com/yohey-w/multi-agent-shogun |
| Repository (CoDD) | https://github.com/yohey-w/codd-dev |
| Releases | https://github.com/yohey-w/multi-agent-shogun/releases |
| Zenn (author) | https://zenn.dev/shio_shoppaize |
| PyPI (CoDD) | https://pypi.org/project/codd-dev/ |
| GitHub Sponsors | https://github.com/sponsors/yohey-w |

## Verification

| 項目 | 値 |
|------|-----|
| verified_at | 2026-04-19 |
| method | WebFetch (GitHub Releases/API) + WebFetch (Zenn profile) + WebSearch |
| source | github.com/yohey-w/multi-agent-shogun releases, zenn.dev/shio_shoppaize, github.com/yohey-w/codd-dev |
| baseline | docs/research/system-comparison-2026-03-13.md §2.5 |
| note | Stars 1,045→1,220 (+175)。Zenn 26→36記事 (+10)。v4.0→v4.4.2。CoDD新規公開(v0.2.0a2→v1.8.0) |
