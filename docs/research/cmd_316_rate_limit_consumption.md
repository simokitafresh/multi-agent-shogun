# cmd_316: レートリミット消費パターン分析+最適化知見

> 偵察B（小太郎担当）| 調査日: 2026-02-25
> 確定情報と推測を明確に区別。URLソース付き

---

## §1 トークンカウント — 何がカウントされるか

### §1.1 確定事項（公式ドキュメント確認済み）

| トークン種別 | レートリミットにカウント | 課金カテゴリ | 根拠 |
|-------------|----------------------|------------|------|
| Input tokens（プロンプト・会話履歴・ファイル内容） | **YES** | input | [公式コスト管理ページ](https://code.claude.com/docs/en/costs) |
| Output tokens（応答テキスト） | **YES** | output | 同上 |
| Thinking tokens（extended thinking） | **YES** | **output扱い** | [Extended Thinking公式ドキュメント](https://platform.claude.com/docs/en/build-with-claude/extended-thinking) — 「thinking tokens are billed as output tokens」 |
| Tool definitions（MCP等） | **YES**（contextに含まれる） | input | 公式コスト管理ページ — 「Each MCP server adds tool definitions to your context」 |
| System prompt（CLAUDE.md等） | **YES** | input（キャッシュ対象） | 同上 |
| Prompt cache read | **YES**（ただし割引） | cache_read | [Rate limits公式](https://platform.claude.com/docs/en/api/rate-limits) |

### §1.2 重要な発見: thinkingトークンの影響

- Extended thinkingはデフォルトON、budget上限31,999トークン
- thinkingトークンは**output tokens（高額側）として課金**
- 課金されるのは**実際に生成されたフルthinking**であり、ユーザーに見えるsummarized thinkingではない
- → 見えるトークン数と課金トークン数に乖離がある（Claude 4以降はthinkingがsummarizedされるため）

> **情報確度: 確定** — Anthropic公式ドキュメントに明記

### §1.3 Claude Codeの特殊性 — 推論サイクル倍増

- ユーザーの1プロンプト ≠ 1 API call
- Claude Codeは自律ループ（計画→探索→読取→編集→検証）で**1プロンプトあたり8+推論サイクル**を実行
- 各サイクルでcontext全体が再送されるため、会話が長くなるほどinput tokensが指数的に増加
- → これがMax Planでも予想外に早くリミットに到達する主因

> **情報確度: 高信頼** — 複数の技術解析記事で一致。公式は明言していないが、`/cost`コマンドで確認可能

---

## §2 モデル別消費差

### §2.1 相対消費レート（確定）

| モデル | 相対消費 | 5h窓推定 | 週間推定上限 | 根拠 |
|--------|---------|---------|------------|------|
| Opus 4.6 | **5x** (Sonnet比) | 少ない | 15-40時間/週 | [GitHub #23706](https://github.com/anthropics/claude-code/issues/23706) + [ClaudeLog](https://claudelog.com/claude-code-limits/) |
| Sonnet 4.6 | **1x** (基準) | 中程度 | 140-480時間/週 | 同上 |
| Haiku 4.5 | **~0.3x** (Sonnet比) | 多い | 制限緩い | [JuanjoFuchs](https://juanjofuchs.github.io/ai-development/2026/01/20/maximizing-claude-code-subscription.html) |

### §2.2 Opus 4.6の消費増大問題（重要）

GitHub Issue #23706で報告された問題:
- Opus 4.6はOpus 4.5比で**20-30%多くトークンを消費**
- Artificial Analysis: Opus 4.6は標準評価で**11Mトークン生成**（他モデル平均3.8M = **約3倍verbose**）
- 実ユーザー報告:
  - 4.5で持続可能だったワークフローが4.6では**2時間以下で制限到達**
  - Git log解析（30-40ファイル）で**5h枠の48%消費**（4.5では最大15%）
  - $200 Max Planで**12時間で週間使用量の20%到達**

> **情報確度: 高信頼** — GitHubに多数の一致する報告。Anthropicは未公式回答

### §2.3 リミット構造 — 二重窓+モデルバケット

```
┌─────────────────────────────────────────┐
│ Weekly "All Models" Limit               │ ← Opus+Sonnet+Haiku全てカウント
│  ┌──────────────────────────────────┐   │
│  │ Weekly "Sonnet Only" Limit       │   │ ← Sonnetのみカウント
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │ 5-hour Rolling Window            │   │ ← 全モデル共通
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

**重要な発見** ([GitHub #12487](https://github.com/anthropics/claude-code/issues/12487)):
- Sonnet使用は「Sonnet Only」**と**「All Models」の**両方**にカウントされる
- Opus使用は「All Models」のみにカウント
- 「All Models」枠が尽きると**全モデル制限**（Sonnet枠が残っていても使用不可）
- → 複数ユーザーが確認: Opus使い切り後にSonnetも使用不可になるケースあり

> **情報確度: 中〜高** — ユーザー複数報告で一致。Anthropicは公式未回答（Issue #12487 OPEN）

### §2.4 プラン別トークン割当推定

| プラン | 月額 | 5h窓トークン(推定) | 倍率 |
|--------|------|-------------------|------|
| Pro | $20 | ~44,000 | 1x |
| Max 5x | $100 | ~88,000 | 2x |
| Max 20x | $200 | ~220,000 | 5x |

> **情報確度: 中** — 複数の分析記事で概ね一致するが、Anthropicは具体数値を非公開

---

## §3 消費が大きい操作パターン

### §3.1 高消費操作ランキング

| 順位 | 操作 | 消費要因 | 実測報告 |
|------|------|---------|---------|
| 1 | 大規模リファクタリング | 多ファイルgrep→read→edit→verify | [HN](https://news.ycombinator.com/item?id=44713757): 「数十ファイルで制限到達」 |
| 2 | ドキュメント一括生成 | verbose output + 多ファイル | 30分で制限到達の報告 |
| 3 | 並列subagent実行 | 各agentが独自contextを維持 | [公式](https://code.claude.com/docs/en/costs): 「7x more tokens than standard sessions」 |
| 4 | 長い会話の継続 | context全体が毎回再送される | 深い会話の1プロンプト = 新規10+プロンプト相当 |
| 5 | compact/clearの繰り返し | instructions再読込コスト | CLAUDE.mdが大きいほど影響大 |
| 6 | 大ファイル丸読み | そのままinputトークンに加算 | - |
| 7 | Extended thinking（高budget） | output扱いで消費大 | デフォルト31,999トークン budget |

### §3.2 当システム（multi-agent-shogun）固有の消費パターン

9エージェント同時稼働の消費特性:
- 各agentが独自context windowを維持 → token使用量 ≈ アクティブagent数に比例
- CLAUDE.md（大きい）が各agentで毎回ロード
- compact/clear頻度が高い（CTX管理のため）→ instructions再読込コスト
- Opus上忍6名 → 最も消費が激しいモデルを6並列

> **情報確度: 高信頼** — 公式ドキュメント+ユーザー報告+当システムの設計から推定

---

## §4 最適化の具体的提案

### §4.1 即効性の高い施策（消費削減40-70%見込み）

| # | 施策 | 削減効果 | 実装方法 | 対象 |
|---|------|---------|---------|------|
| 1 | **thinking budget削減** | 高 | `MAX_THINKING_TOKENS=8000` or `/config`でthinking OFF（単純タスク時） | 全agent |
| 2 | **モデル使い分け** | 最大5x | Opus→複雑推論のみ、Sonnet→通常コーディング、Haiku→調査/要約 | agent配備 |
| 3 | **CLAUDE.md軽量化** | 中 | 500行以下目標。専門指示はskillsに移動（on-demand load） | 将軍 |
| 4 | **MCP tool search有効化** | 中 | `ENABLE_TOOL_SEARCH=auto:5`（5%超でdefer） | 全agent |
| 5 | **未使用MCPサーバー無効化** | 低〜中 | `/mcp`で確認→不要サーバー停止 | 全agent |

### §4.2 運用レベルの施策

| # | 施策 | 詳細 |
|---|------|------|
| 6 | **subagentにverbose処理を委譲** | テスト実行・ログ解析・ドキュメント取得はsubagentへ（main contextを汚さない） |
| 7 | **hookでpre-processing** | テスト出力をgrep+headで圧縮してからClaudeに渡す |
| 8 | **plan modeの活用** | 実装前にShift+Tabでplan → 承認 → 実装。手戻りによるtoken浪費を防止 |
| 9 | **具体的なプロンプト** | 「このコードを改善して」→「auth.tsのlogin関数にinput validationを追加して」 |
| 10 | **5h窓のタイミング最適化** | ピーク作業の2-3時間前にセッション開始→リセットが作業中に来る |

### §4.3 当システム（multi-agent-shogun）向け推奨

| # | 推奨 | 理由 |
|---|------|------|
| A | **忍者のモデルミックス**: 偵察/調査タスクはHaiku、実装タスクはSonnet、複雑設計のみOpus | Opus 6並列は消費最大化パターン |
| B | **アカウント分散**: 2アカウントMax Plan → 忍者を分散配備 | 「All Models」枠の分散 |
| C | **idle agentの停止**: 作業なしのagentはpromptly停止 | idle中もbackground token消費あり（~$0.04/session） |
| D | **CLAUDE.md→skills移行**: 専門手順をskillsに移動 | base context軽量化。公式推奨 |
| E | **ccusageツール導入検討** | トークン消費の可視化。どの操作で消費が多いか特定可能 |

---

## §5 コミュニティ知見まとめ

### §5.1 Hacker News (2025年8月〜)

- [Weekly rate limits発表スレッド](https://news.ycombinator.com/item?id=44713757): 「影響は5%未満のユーザー」とAnthropicは主張
- Max 5xで「Sonnet 140-280時間、Opus 15-35時間/週」の推定
- リファクタリングが最もtoken消費が激しい操作との報告多数

### §5.2 GitHub Issues

- [#23706](https://github.com/anthropics/claude-code/issues/23706): Opus 4.6の消費増大。4.5比2-3倍。Anthropic未回答
- [#12487](https://github.com/anthropics/claude-code/issues/12487): Opus/Sonnetリミット独立性の混乱。Anthropic未回答
- [#8449](https://github.com/anthropics/claude-code/issues/8449): Max 20xでもOpus制限が異常に早い

### §5.3 The Register (2026年1月)

- [記事](https://www.theregister.com/2026/01/05/claude_devs_usage_limits/): 年末ボーナス期間（12/25-31、制限2倍）終了後に「制限が減った」とユーザーが混乱
- Anthropicは「基本制限は変更していない」と回答
- あるユーザーはログ分析で「約60%の制限削減」を主張

### §5.4 ツール

- [cc-hdrm](https://news.ycombinator.com/item?id=46900292): macOSメニューバーアプリ。5h/7d headroomをリアルタイム表示。`brew install rajish/tap/cc-hdrm`
- **ccusage**: トークン消費の詳細分析ツール。日別消費・コスト内訳を表示

---

## §6 調査で「分からなかった」こと

| 項目 | 状況 | 理由 |
|------|------|------|
| 正確なプラン別トークン割当数 | 推定のみ | Anthropicが非公開 |
| tool use自動リトライのカウント有無 | 不明 | 公式ドキュメントに記載なし |
| 5h窓とweekly窓の正確な相互作用 | 部分的に判明 | 二重バケット構造はユーザー推定 |
| compact/clear時のinstructions再読込コスト | 定量データなし | `/cost`で個別測定は可能だが系統的調査は未実施 |
| claude.ai使用とClaude Code使用の消費比率の違い | 不明 | 共有枠だが、操作あたりの消費が異なる可能性 |

---

## §7 ソース一覧

1. [Manage costs effectively - Claude Code Docs](https://code.claude.com/docs/en/costs) — 公式
2. [Using Claude Code with Pro/Max plan](https://support.claude.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan) — 公式
3. [Extra usage for paid Claude plans](https://support.claude.com/en/articles/12429409-extra-usage-for-paid-claude-plans) — 公式
4. [Building with extended thinking](https://platform.claude.com/docs/en/build-with-claude/extended-thinking) — 公式
5. [Rate limits - Claude API](https://platform.claude.com/docs/en/api/rate-limits) — 公式
6. [GitHub #23706: Opus 4.6 token consumption](https://github.com/anthropics/claude-code/issues/23706) — コミュニティ
7. [GitHub #12487: Opus/Sonnet limits independent?](https://github.com/anthropics/claude-code/issues/12487) — コミュニティ
8. [HN: Claude Code weekly rate limits](https://news.ycombinator.com/item?id=44713757) — コミュニティ
9. [HN: cc-hdrm headroom tool](https://news.ycombinator.com/item?id=46900292) — コミュニティ
10. [JuanjoFuchs: Maximizing subscription](https://juanjofuchs.github.io/ai-development/2026/01/20/maximizing-claude-code-subscription.html) — コミュニティ
11. [The Register: Claude devs usage limits](https://www.theregister.com/2026/01/05/claude_devs_usage_limits/) — メディア
12. [ClaudeLog: Claude Code Limits](https://claudelog.com/claude-code-limits/) — コミュニティ
13. [Portkey: Everything about Claude Code Limits](https://portkey.ai/blog/claude-code-limits/) — コミュニティ
14. [Faros AI: Token Limits Guide](https://www.faros.ai/blog/claude-code-token-limits) — コミュニティ
