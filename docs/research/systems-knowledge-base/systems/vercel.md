# Vercel Context Engineering

> Vercelは「AGENTS.mdで受動的に知識を置く」設計を出発点に、agent-friendly docs、agent-browser、AI Gateway、Vercel Agentを束ねた実運用のエージェント基盤へ拡張している。知識供給、実行、検証、運用の各層を同一プラットフォーム内で閉じるのが特徴。

## Basic Info

| 項目 | 値 |
|------|-----|
| Author | Vercel (Jude Gao, Andrew Qu, Zach Cowan, Matthew Binshtok, Vercel Engineering) |
| Status | 本番稼働中 + 活発に進化中 |
| Stars | **29,678** (`vercel-labs/agent-browser`, 2026-04-19 API取得) |
| Forks | 1,800 (`agent-browser`) |
| Version | **agent-browser v0.26.0** (2026-04-16) |
| Last Commit | 2026-04-16 (`agent-browser` main) |
| Repo | https://github.com/vercel-labs/agent-browser |
| Docs | https://vercel.com/docs/agent-resources |
| Gateway | https://vercel.com/docs/ai-gateway |
| License | Apache-2.0 (`agent-browser`) |
| Language | Next.js / TypeScript / Rust (`agent-browser`) |
| Scope Note | 単一repoではなく、docs + platform + OSS CLI + hosted agent product の複合システム。Stars/Version/Last Commit は公開OSSアンカーとして `agent-browser` を採用 |

## Design Philosophy

- **Passive Context > Active Retrieval**: Vercelは「エージェントに調べさせるな、必要な知識の索引を最初から置け」という立場を明示した。`AGENTS.md` に圧縮索引を常駐させ、判断点を消す
- **Retrieval-led reasoning**: 事前学習依存ではなく、バージョン一致したドキュメントを読ませる。`IMPORTANT: Prefer retrieval-led reasoning over pre-training-led reasoning` がその中核
- **Agent-friendly documentation**: HTMLを読ませるのではなく、Markdown・`llms-full.txt`・markdown sitemap・content negotiationで情報をエージェントに最適化して配る
- **Addition by subtraction**: 複雑な専用ツール群を削り、ファイルシステムとシェル、よく構造化された知識面を直接読ませる方が強いという思想
- **Platform-native agent ops**: Sandbox、AI Gateway、Observability、Vercel Agentを同一基盤で接続し、実行・ルーティング・検証・監視を一体化する
- **Verification over ceremony**: 人間レビューを儀式化するより、secure sandbox内でbuild/test/lintを通した修正だけを提示する方が安全という発想

## Architecture

### 知識供給層

| 要素 | 役割 |
|------|------|
| `AGENTS.md` docs index | Next.jsなどのフレームワーク知識を圧縮索引として常駐注入 |
| `llms-full.txt` | Vercel docs全文の機械可読版。エージェントへ広域知識を一括供給 |
| Markdown Access | すべてのdocsページを `.md` で取得可能。WebFetch向き |
| Content Negotiation | `Accept: text/markdown` を優先し、blog/changelogをagent向け軽量本文として返す |
| Markdown Sitemap | docs/blog/changelog の探索導線をMarkdownで提供 |
| Agent Skills | Vercel公式skillsを `npx skills add` で配布 |
| Vercel MCP server | docs検索、project/deployment/domain操作をMCP経由で直接接続 |

### 実行層

| 要素 | 役割 |
|------|------|
| `agent-browser` | Rust製browser automation CLI。AI agent向けの公開OSSコンポーネント |
| Vercel Sandbox | 秒単位で起動するLinux MicroVM。CLI agentを隔離実行 |
| AI Gateway | 複数provider/複数modelを単一endpointで統合し、ログ・予算・fallbackを集中管理 |
| Coding Agents integration | Claude Code / Codex / OpenCode / Cline / Roo / Conductor 等をGateway配下に接続 |
| Vercel Agent | PR review / investigation / installation をホスト型agentとして提供 |

### 品質保証・運用層

- **Hardened evals**: AGENTS.md vs Skills を Build/Lint/Test で比較し、100% / 79% / 53% の差を計測
- **Validated suggestions**: Vercel Agent Code Review は patch生成後に secure sandbox で実build/test/lintを流し、通過案だけ提示
- **Observability-first routing**: agent CLIのリクエストをAI Gatewayへ集約し、spend/trace/fallbackを一元可視化
- **Verification at scale**: 2026-04-06時点で、Vercel最大級monorepoのPRの58%をagentが人手なしでmergeし、平均merge時間を29時間→10.9時間へ短縮

## Key Features

| 機能名 | 説明 | 導入バージョン |
|--------|------|---------------|
| AGENTS.md docs index | 圧縮されたdocs索引を `AGENTS.md` に常駐注入し、受動的に知識供給 | 2026-01時点で公開 |
| Retrieval-led reasoning | 事前学習よりドキュメント参照を優先させる設計原則 | 2026-01時点で公開 |
| 8KB compressed context | 40KB→8KBへ圧縮しても100% pass rate維持 | 2026-01時点で公開 |
| Markdown access | docs各ページを `.md` で取得可能 | 2026-03時点 docs |
| `llms-full.txt` | Vercel docs全文のLLM向け単一ファイル | 2026-03時点 docs |
| Vercel MCP server | docs検索、project管理、deployment/log確認、domain確認 | 2026-03時点 docs |
| AI Gateway | 単一API keyで数百モデル、予算、使用量、fallback、BYOKを管理 | 2026-03時点 docs |
| Coding Agents hub | Claude Code / Codex など複数agentをGateway配下に接続 | 2026-03時点 docs |
| Vercel Agent Code Review | multi-step reasoning + patch生成 + secure sandbox検証 | 2026-03時点 docs |
| Content negotiation | `Accept: text/markdown` でblog/changelogをagent向け配信 | 2026-02時点 blog |
| File system agent | 多数の専用toolを削り、filesystem+shell中心へ再設計 | 2025-12 blog |
| `agent-browser doctor` | install/Chrome/daemon/provider/networkを一括診断 | v0.26.0 |
| Stable tab ids / labels | `t1`, `t2` のような安定tab識別子と `--label` を追加 | v0.26.0 |
| Core skill guide | 約420行の usage guide を返す `skills get core` | v0.26.0 |
| Config JSON Schema | `agent-browser.schema.json` によるIDE補完・検証 | v0.26.0 |

## Changelog since 2026-03-13

| 日付 | バージョン | 変更 | 影響 |
|------|-----------|------|------|
| 2026-03-17 | docs snapshot | AI Gateway docsが「数百モデル」「予算」「使用量監視」「fallback」「BYOK no markup」を前面化 | 前回比較の「AI Gatewayあり」から、agent routing基盤として説明が具体化 |
| 2026-03-17 | docs snapshot | Vercel Agent Code Review docsが secure sandbox 上で実build/test/lintを通した validated suggestions を明文化 | Vercelの品質保証が「AutoFixの概念」から、より運用可能な検証付きreview productへ具体化 |
| 2026-03-30 | blog | `Agent responsibly` 公開。green CIは安全性の証明ではなく、alignmentとverificationを分けて扱うべきと整理 | agent運用の哲学を形式知化 |
| 2026-04-06 | production practice | 最大級monorepoで agent が **58%** のPRを人手なしでmerge、平均merge時間を **29h → 10.9h** へ短縮 | platform-native agent review が実運用段階へ進んだ証拠 |
| 2026-04-16 | `agent-browser` v0.26.0 | `doctor`、stable tab ids/labels、`core` skill guide、config JSON Schema、`--state` 読込修正 | browser substrate の診断性とagent可用性が大きく向上 |

## Notable Techniques

| テクニック名 | 説明 | このシステム固有か |
|-------------|------|-----------------|
| Passive Context Injection | `AGENTS.md` に圧縮索引を入れ、知識を毎ターン常駐させる | ◎ Vercelの代表技法 |
| Retrieval-led reasoning mandate | 「事前学習より取得を優先せよ」をプロンプトに明文化 | Vercel実証で有名化 |
| Hardened eval comparison | Baseline / Skill / Skill+指示 / AGENTS.md を同一evalで比較 | ◎ Vercelの強み |
| Content negotiation for agents | `Accept: text/markdown` で同一URLからagent向け本文を返す | Vercel実装固有 |
| Markdown sitemap | XMLでなくMarkdownの階層付きsitemapを配る | Vercel実装固有 |
| File system agent | 複雑な専用tool群を減らし、shell+filesを直接読ませる | Vercel実務知見 |
| Sandbox lifecycle | CLI install → credential inject → run → transcript capture → teardown をMicroVMで標準化 | Vercel実装固有 |
| Gateway-routed agents | Claude CodeやCodexを provider直結でなくAI Gateway経由へ集約 | Vercel実装固有 |
| Validated patch suggestions | patch生成後に実build/test/lintで通した案のみ出す | Vercel Agent固有 |
| Stable tab handles | browser tabを位置依存でなく `t<N>` で安定参照 | `agent-browser` 固有 |
| One-file doc export | `llms-full.txt` でdocs全体をLLM向けに単一配布 | Vercel docs固有 |

## Ecosystem

| カテゴリ | 名前 | 説明 |
|----------|------|------|
| OSS CLI | agent-browser | https://github.com/vercel-labs/agent-browser — browser automation CLI |
| Docs | Agent Resources | https://vercel.com/docs/agent-resources — llms-full.txt / Markdown / MCP / Skills / Workflows |
| Docs | AI Gateway | https://vercel.com/docs/ai-gateway — unified model routing |
| Docs | Coding Agents | https://vercel.com/docs/agent-resources/coding-agents — Claude Code, Codex等の接続ガイド |
| Product | Vercel Agent | https://vercel.com/docs/agent — code review / investigation / installation |
| Protocol | Vercel MCP server | docs検索、project/deployment/domain操作 |
| Skills | Skills.sh | https://skills.sh — Vercel運営のskills ecosystem |
| Blog | AGENTS.md outperforms skills | https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals |
| Blog | Making agent-friendly pages with content negotiation | https://vercel.com/blog/making-agent-friendly-pages-with-content-negotiation |
| Blog | We removed 80% of our agent's tools | https://vercel.com/blog/we-removed-80-percent-of-our-agents-tools |
| Blog | How we built AEO tracking for coding agents | https://vercel.com/blog/how-we-built-aeo-tracking-for-coding-agents |
| Blog | 58% of PRs in our largest monorepo merge without human review | https://vercel.com/blog/58-percent-of-prs-in-our-largest-monorepo-merge-without-human-review |
| Blog | Agent responsibly | https://vercel.com/blog/agent-responsibly |
| Integrations | Claude Code / Codex / OpenCode / Cline / Roo / Conductor / Crush / Superset | AI Gateway経由で接続可能 |

## Sources

| 種別 | URL |
|------|-----|
| Repository | https://github.com/vercel-labs/agent-browser |
| Releases | https://github.com/vercel-labs/agent-browser/releases |
| AGENTS.md blog | https://vercel.com/blog/agents-md-outperforms-skills-in-our-agent-evals |
| Tool reduction blog | https://vercel.com/blog/we-removed-80-percent-of-our-agents-tools |
| Content negotiation blog | https://vercel.com/blog/making-agent-friendly-pages-with-content-negotiation |
| AEO tracking blog | https://vercel.com/blog/how-we-built-aeo-tracking-for-coding-agents |
| PR auto-merge blog | https://vercel.com/blog/58-percent-of-prs-in-our-largest-monorepo-merge-without-human-review |
| Agent philosophy blog | https://vercel.com/blog/agent-responsibly |
| Agent Resources docs | https://vercel.com/docs/agent-resources |
| AI Gateway docs | https://vercel.com/docs/ai-gateway |
| Coding Agents docs | https://vercel.com/docs/agent-resources/coding-agents |
| Claude Code docs | https://vercel.com/docs/agent-resources/coding-agents/claude-code |
| Vercel Agent docs | https://vercel.com/docs/agent |
| Code Review docs | https://vercel.com/docs/agent/pr-review |

## Verification

| 項目 | 値 |
|------|-----|
| verified_at | 2026-04-19T00:30:00+09:00 |
| method | GitHub REST API (`repos`, `releases/latest`, `commits?per_page=1`) + Vercel公式blog/docsのMarkdown取得 + 前回比較文書との差分確認 |
| source | `vercel-labs/agent-browser` 公式repo、Vercel公式blog、Vercel公式docs、`docs/research/system-comparison-2026-03-13.md` |
| stars_verified | 29,678 (`agent-browser`, 2026-04-19 API取得) |
| version_verified | `agent-browser` v0.26.0 (published_at: 2026-04-16T23:40:31Z) |
| last_commit_verified | `717d1b09e1c841a4c0206033886a1a861e3ca5d9` / 2026-04-16T23:33:23Z |
| scope_note | Vercel system全体は単一repoに還元できないため、数値メタデータは公開OSS基盤 `agent-browser` を代表値として記録 |
