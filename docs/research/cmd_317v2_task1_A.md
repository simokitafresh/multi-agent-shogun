# cmd_317v2 Wave1-Task1: /model コマンド仕様調査

> blind_id: A | 調査日: 2026-02-25 | 担当: hayate

---

## §1 概要

Claude Code の `/model` コマンドはセッション中にLLMモデルを切り替えるスラッシュコマンド。
起動時の `--model` フラグ、環境変数 `ANTHROPIC_MODEL`、settings.json の `"model"` キーでも設定可能。
切替時にコンテキスト（会話履歴）は保持される。

---

## §2 モデル一覧

### §2.1 現行モデル（エイリアス対応）

| エイリアス | モデルID | 入力/出力 ($/MTok) | コンテキスト窓 |
|-----------|---------|-------------------|--------------|
| `opus` | `claude-opus-4-6` | $5 / $25 | 200K (1M beta) |
| `sonnet` | `claude-sonnet-4-6` | $3 / $15 | 200K (1M beta) |
| `haiku` | `claude-haiku-4-5-20251001` | $1 / $5 | 200K |

### §2.2 特殊エイリアス

| エイリアス | 挙動 |
|-----------|------|
| `default` | プラン別自動選択（Max/Team Premium→Opus, Pro/Team Standard→Sonnet） |
| `sonnet[1m]` | Sonnet + 1Mコンテキスト窓 |
| `opusplan` | ハイブリッド: plan mode=Opus, execution mode=Sonnet |

### §2.3 レガシーモデル（フルネーム指定で使用可能）

| モデル | モデルID |
|-------|---------|
| Claude Sonnet 4.5 | `claude-sonnet-4-5-20250929` |
| Claude Opus 4.5 | `claude-opus-4-5-20251101` |
| Claude Opus 4.1 | `claude-opus-4-1-20250805` |
| Claude Sonnet 4 | `claude-sonnet-4-20250514` |
| Claude Opus 4 | `claude-opus-4-20250514` |
| Claude Haiku 3 (deprecated, 2026-04-19退役) | `claude-3-haiku-20240307` |

---

## §3 構文・オプション

### §3.1 セッション中（スラッシュコマンド）

```
/model                          # インタラクティブピッカー起動
/model sonnet                   # エイリアスで切替
/model opus                     # エイリアスで切替
/model haiku                    # エイリアスで切替
/model opusplan                 # ハイブリッドモード
/model sonnet[1m]               # 1Mコンテキスト窓付き
/model claude-opus-4-6          # フルモデルIDで切替
/model claude-sonnet-4-6[1m]    # フルID + 1M
```

インタラクティブピッカーでは左右矢印キーで **effort slider**（low/medium/high）を調整可能（Opus 4.6対応）。

### §3.2 起動時（CLIフラグ）

```bash
claude --model opus
claude --model claude-sonnet-4-6
claude --model opusplan
claude --effort high            # effortレベル指定
claude --fallback-model sonnet  # --print時のみ有効なフォールバック
```

### §3.3 環境変数

| 変数名 | 用途 |
|-------|------|
| `ANTHROPIC_MODEL` | デフォルトモデル設定 |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `opus`エイリアスの解決先を上書き |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `sonnet`エイリアスの解決先を上書き |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `haiku`エイリアスの解決先を上書き |
| `CLAUDE_CODE_SUBAGENT_MODEL` | サブエージェント用モデル |
| `CLAUDE_CODE_EFFORT_LEVEL` | `low` / `medium` / `high` |
| `CLAUDE_CODE_DISABLE_1M_CONTEXT` | `1`で1M選択肢を非表示 |

### §3.4 settings.json（永続設定）

```json
{
  "model": "opus",
  "effortLevel": "high",
  "fastMode": true
}
```

### §3.5 優先順位（高→低）

1. セッション中 `/model` コマンド
2. `--model` 起動フラグ
3. `ANTHROPIC_MODEL` 環境変数
4. settings.json の `model` フィールド

### §3.6 関連コマンド

| コマンド | 用途 |
|---------|------|
| `/model` | モデル切替 / ピッカー表示 |
| `/fast` | fast mode トグル（Opus 4.6で2.5倍速、高コスト） |
| `/status` | 現在のモデル・アカウント情報表示 |

---

## §4 切替時の挙動

### §4.1 コンテキスト保持

| 項目 | 挙動 |
|------|------|
| 会話履歴 | **保持される** — 全メッセージが新モデルに引き継がれる |
| セッションID | 変更なし |
| 作業ディレクトリ | 変更なし |
| ツール状態 | 変更なし |
| セッションリセット | **発生しない** |

### §4.2 コスト影響

- 新モデルは**全会話履歴を再処理**する（Claude APIは毎リクエスト全コンテキスト送信）
- 切替後は新モデルの料金で蓄積済みコンテキスト分も課金
- 推奨: 長い会話でモデル変更する場合は `claude --model <name>` で新セッション開始が経済的

### §4.3 永続化の注意点

- `/model` で切り替えると **settings.json に永続化される**（GitHub Issue #12645）
- 同時に動いている他のClaude Codeインスタンスにも影響
- 「一時的切替」オプションは未実装（2026-02-25時点）

---

## §5 制約・制限事項

### §5.1 プラン別制限

| プラン | デフォルトモデル | Opusアクセス |
|-------|----------------|-------------|
| Max / Team Premium | Opus 4.6 | 含まれる |
| Pro / Team Standard | Sonnet 4.6 | extra usage購入時のみ |
| Enterprise | Opus 4.6利用可能 | 利用可能 |
| API / Pay-as-you-go | 全モデル | 利用可能 |

- Proプランユーザーは extra usage を有効化・購入しないとOpusモデル使用不可
- 使用量閾値到達時、Opus→Sonnetへ自動フォールバックが発生する場合あり

### §5.2 Enterprise/管理者制限

管理者が `availableModels` を設定可能:

```json
{ "availableModels": ["sonnet", "haiku"] }
```

設定時、ユーザーは `/model`・`--model`・`ANTHROPIC_MODEL` いずれでも未許可モデルに切替不可。`default` は常に利用可能。

### §5.3 fast mode制約

| 項目 | 制約 |
|------|------|
| 利用条件 | extra usage有効化が必要 |
| 非対応環境 | AWS Bedrock, Google Vertex AI, Microsoft Azure Foundry |
| Teams/Enterprise | デフォルト無効（管理者が有効化必要） |
| レートリミット | 標準Opusとは別のバケット。上限到達時は標準にフォールバック |
| 料金 | $30/$150 MTok (200K以下), $60/$225 MTok (200K超) |

### §5.4 1Mコンテキスト窓制約

| 項目 | 制約 |
|------|------|
| 対応モデル | Opus 4.6, Sonnet 4.6のみ（Haiku 4.5非対応） |
| ステータス | beta（価格・可用性は変更可能性あり） |
| API/従量課金 | フルアクセス |
| Pro/Max/Teams/Enterprise | extra usage有効化が必要 |
| 料金体系 | 200Kまで標準料金、200K超はlong-context pricing適用 |
| 無効化 | `CLAUDE_CODE_DISABLE_1M_CONTEXT=1` |

### §5.5 effortレベル制約

| 項目 | 制約 |
|------|------|
| 対応モデル | Opus 4.6のみ（現時点） |
| レベル | `low` / `medium` / `high`（デフォルト: `high`） |
| 効果 | low=高速・低コスト・品質低下の可能性あり |
| 併用 | fast modeとの併用可能 |

---

## §6 当環境の設定状況

| 設定箇所 | 値 |
|---------|-----|
| `~/.claude/settings.json` → model | `claude-sonnet-4-6` |
| `config/settings.yaml` → tobisaru.model_name | `claude-sonnet-4-6` |
| 他のjonin/genin | model_name指定なし（settings.jsonのデフォルトを使用） |

---

## §7 まとめ

1. `/model` は3つのエイリアス（opus/sonnet/haiku）+ フルモデルID + 特殊モード（opusplan, [1m]）に対応
2. 切替時にコンテキストは完全保持。セッションリセットなし
3. 切替はsettings.jsonに永続化される（一時的切替は未サポート）
4. プラン別制限あり（ProはOpus使用にextra usage必要）
5. 管理者によるモデル制限（availableModels）が可能
6. fast mode・1M窓・effortレベルはそれぞれ独立した制約を持つ

---

## Sources

- [Model configuration - Claude Code Docs](https://code.claude.com/docs/en/model-config)
- [CLI reference - Claude Code Docs](https://code.claude.com/docs/en/cli-reference)
- [Models overview - Claude API Docs](https://platform.claude.com/docs/en/about-claude/models/overview)
- [Fast mode - Claude Code Docs](https://code.claude.com/docs/en/fast-mode)
- [Claude Code model configuration - Help Center](https://support.claude.com/en/articles/11940350-claude-code-model-configuration)
- [GitHub Issue #12645 - Model switching persistence](https://github.com/anthropics/claude-code/issues/12645)
