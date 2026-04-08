# cmd_317v2 Wave1-Task1: /model コマンド仕様調査
- **blind_id**: C
- **調査者**: hanzo (Sonnet 4.6)
- **調査日**: 2026-02-25
- **情報源**: 公式ドキュメント `https://code.claude.com/docs/en/model-config` + `support.claude.com`
- **信頼度凡例**: ✅確認済み / ⚠️推測（明記）

---

## §1 概要

Claude Code の `/model` コマンドはセッション中にAIモデルをリアルタイム切り替えする機能。即座に反映、セッション継続。

---

## §2 モデル一覧テーブル ✅

### エイリアス（推奨: 常に最新版を自動参照）

| エイリアス | 現在のモデル | 用途 |
|-----------|------------|------|
| `default` | アカウントタイプ依存（後述） | 推奨デフォルト |
| `sonnet` | claude-sonnet-4-6 | 日常的なコーディングタスク |
| `opus` | claude-opus-4-6 | 複雑な推論タスク |
| `haiku` | claude-haiku-4-5-20251001 | シンプルなタスク・高速 |
| `sonnet[1m]` | claude-sonnet-4-6 (1M ctx) | 大規模コードベース（β版） |
| `opusplan` | plan=opus / exec=sonnet | ハイブリッド（後述） |

### フルモデル名（バージョン固定用）

| モデルID | 補足 |
|---------|------|
| `claude-opus-4-6` | Opus最新安定版 |
| `claude-sonnet-4-6` | Sonnet最新安定版 |
| `claude-haiku-4-5-20251001` | Haiku最新安定版 |
| `claude-sonnet-4-6[1m]` | 1Mサフィックスをフルネームに付与可能 |

> エイリアスはAnthropicが新バージョンをリリース時に自動更新。バージョン固定にはフルモデル名を使え。

---

## §3 コマンド構文 ✅

```bash
# 引数なし → インタラクティブ選択メニュー表示
/model

# エイリアス指定 → 即座に切替
/model sonnet
/model opus
/model haiku

# フルモデル名指定（バージョン固定）
/model claude-opus-4-6

# 1Mコンテキスト
/model sonnet[1m]
/model claude-sonnet-4-6[1m]
```

**キーボードショートカット**: `Alt+P` (macOS: `Option+P`) でモデル選択画面

---

## §4 切替時の挙動

### 設定優先度（高→低） ✅

| 優先度 | 方法 | 例 |
|-------|------|-----|
| 1 (最高) | セッション中 `/model` | `/model opus` |
| 2 | 起動フラグ `--model` | `claude --model opus` |
| 3 | 環境変数 `ANTHROPIC_MODEL` | `export ANTHROPIC_MODEL=sonnet` |
| 4 (最低) | 設定ファイル `model` フィールド | `{"model": "opus"}` |

### コンテキスト保持 ⚠️推測

| 項目 | 挙動 | 確認状況 |
|------|------|---------|
| セッション継続 | `/model` 後も同一セッションを維持 | ✅公式に「mid-session switching」と明記 |
| 会話履歴保持 | 切替前のコンテキストを新モデルが参照可能 | ⚠️公式に明示なし（一般的なCLI動作から推測） |
| ファイル変更 | 保持（セッション継続のため） | ⚠️推測 |
| 即時反映 | 次のプロンプトから新モデル使用 | ✅公式に明記 |

### `opusplan` 挙動 ✅

```
plan mode 中   → opus使用（複雑な推論・アーキテクチャ判断）
execution mode → 自動でsonnetに切替（コード生成・実装）
```

---

## §5 制約・制限事項

### アカウントプラン別 ✅

| 制限 | 詳細 |
|------|------|
| `default` の挙動 | Max/Team Premium → Opus 4.6 / Pro/Team Standard → Sonnet 4.6 / Enterprise → Opus利用可だが非デフォルト |
| Opusアクセス | Pro単体では追加の「Extra Usage」購入が必要 |
| 1Mコンテキスト | API+従量課金: 完全アクセス / Pro/Max/Teams/Enterprise: Extra Usage有効化必須 |
| 1M β制限 | 現在β版。機能・価格・提供範囲が変更される可能性あり |

### コスト関連 ✅

| トリガー | 課金変化 |
|---------|---------|
| セッションが200Kトークン超 | long-context pricing（高額）に切替 |
| 1Mモデル選択のみ | 直ちに変化なし（200K超過時点で切替） |
| Opus使用 | Sonnetの約5倍のコスト（レートリミット検証 cmd_316より） |

### Enterprise管理制限 ✅

```json
// managed/policy settingsで利用可能モデルを制限
{
  "availableModels": ["sonnet", "haiku"]
}
```
- `default`は`availableModels`の制限を受けない（常に利用可能）
- 複数設定レベルの`availableModels`はマージ+重複排除

### Effort Level (Opus 4.6専用) ✅

| レベル | 速度 | コスト | 用途 |
|-------|------|-------|------|
| `low` | 速 | 低 | 単純な修正・追加 |
| `medium` | 中 | 中 | 標準リファクタリング |
| `high` (デフォルト) | 遅 | 高 | 複雑な設計・推論 |

設定方法:
- `/model` インタラクティブメニュー内の左右矢印キー
- 環境変数: `CLAUDE_CODE_EFFORT_LEVEL=low|medium|high`
- settings.json: `{"effortLevel": "high"}`

---

## §6 環境変数まとめ ✅

| 変数 | 用途 |
|------|------|
| `ANTHROPIC_MODEL` | 起動時モデル指定 |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | opusエイリアスが参照するモデルID固定 |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | sonnetエイリアスが参照するモデルID固定 |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | haikuエイリアスが参照するモデルID固定 |
| `CLAUDE_CODE_SUBAGENT_MODEL` | サブエージェント用モデル |
| `CLAUDE_CODE_EFFORT_LEVEL` | Effort Level設定 |
| `CLAUDE_CODE_DISABLE_1M_CONTEXT` | `1`で1Mオプションを非表示化 |
| `DISABLE_PROMPT_CACHING` | `1`で全モデルのキャッシュ無効化 |

---

## §7 現在のモデル確認方法 ✅

```bash
/status    # アカウント情報+現在モデル表示
/model     # インタラクティブメニュー（確認も可）
```

またはステータスラインを設定済みの場合はプロンプトに常時表示。

---

## §8 まとめ

| 観点 | 要点 |
|------|------|
| 基本構文 | `/model` (選択UI) / `/model <alias|name>` (直接指定) |
| コンテキスト保持 | セッション継続（mid-session switching）。詳細は推測 |
| 優先度 | セッション中 > --model > 環境変数 > settings.json |
| 主要エイリアス | default/sonnet/opus/haiku/sonnet[1m]/opusplan の6種 |
| 特殊機能 | opusplan(ハイブリッド) / Effort Level(Opus専用) / 1M ctx(β) |
| アカウント制限 | Pro→Extra Usage必要(Opus) / Enterprise→availableModelsで制限可 |

---

## §9 AC達成状況

| AC | 状況 | 備考 |
|----|------|------|
| AC1: 全モデル一覧テーブル | ✅ PASS | §2に記載（エイリアス6種+フルモデル名） |
| AC2: 切替時の挙動 | ✅ PASS | §4に記載（コンテキスト保持は推測と明記） |
| AC3: 制約・制限事項 | ✅ PASS | §5に記載（プラン別/コスト/Enterprise） |
| AC4: ファイル作成 | ✅ PASS | docs/research/cmd_317v2_task1_C.md |
| AC5: 構造化報告 | ✅ PASS | セクション分け+テーブル形式 |
