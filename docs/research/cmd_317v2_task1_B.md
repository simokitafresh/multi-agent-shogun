# cmd_317v2 Wave1-Task1(B): /model コマンド仕様調査

- 調査日: 2026-02-25
- 調査者: sasuke (blind_id: B)
- 対象: Claude Code `/model`
- 方式: 公式一次情報のみ（Claude Code Docs / Claude Help Center）

## 概要

| 観点 | 結論 |
|---|---|
| 基本構文 | `/model <alias|name>` でセッション中に切替可能 |
| 反映タイミング | 変更は即時反映（ターミナル再起動不要、現在応答の完了待ち不要） |
| 切替対象 | エイリアス（`default`/`sonnet`/`opus`/`haiku`/`sonnet[1m]`/`opusplan`）またはモデル名 |
| セッション影響 | `/model`は同一セッション内でのモデル変更。履歴削除は`/clear`が担当 |
| 主制約 | プラン制約、`availableModels`制限、1Mコンテキストの利用条件 |

## モデル一覧テーブル

### 1) `/model` で指定可能なエイリアス

| 指定値 | 意味/挙動 | 備考 |
|---|---|---|
| `default` | アカウント種別ごとの推奨デフォルト | `availableModels`設定の影響を受けず常に利用可能 |
| `sonnet` | 最新Sonnet系（現行: Sonnet 4.6） | 日常コーディング向け |
| `opus` | 最新Opus系（現行: Opus 4.6） | 高度推論向け |
| `haiku` | Haiku系 | 高速・軽量タスク向け |
| `sonnet[1m]` | Sonnetの1Mコンテキスト窓 | 1M利用条件を満たす場合のみ |
| `opusplan` | Plan modeで`opus`、Executionで`sonnet`へ自動切替 | ハイブリッド運用 |

### 2) Claude Help Centerで明示される現行サポートモデル（2026-02-25時点）

| 表示名 | `/model`で使うモデル名 |
|---|---|
| Sonnet 4.6 | `claude-sonnet-4-6` |
| Opus 4.6 | `claude-opus-4-6` |
| Opus 4.5 | `claude-opus-4-5-20251101` |
| Haiku 4.5 | `claude-haiku-4-5-20251001` |
| Sonnet 4.5 | `claude-sonnet-4-5-20250929` |

### 3) プロバイダ別の指定形式（`/model <alias|name>` の `name` 部）

| プロバイダ | 指定形式 |
|---|---|
| Anthropic API | フルモデル名 |
| Bedrock | Inference Profile ARN |
| Foundry | Deployment name |
| Vertex AI | Version name |

## 切替挙動

| 項目 | 事実 | 判定 |
|---|---|---|
| 反映タイミング | `/model`変更は即時反映。現応答の完了待ち不要 | 事実 |
| 再起動要否 | ターミナル再起動不要 | 事実 |
| プロンプト保持 | モデル切替ショートカットは「プロンプトを消さずに切替」 | 事実 |
| 会話履歴の削除 | 履歴削除は`/clear`コマンドの責務として別定義 | 事実 |
| コンテキスト保持/リセット | 公式文面は「即時切替」「プロンプト非クリア」まで明示。内部コンテキスト実装（KV再利用など）の詳細仕様は未公開 | 推測を含む（未公開領域） |

## 制約事項

| 区分 | 制約内容 |
|---|---|
| プラン制約 | ProプランではOpus利用にextra usageの有効化＋購入が必要 |
| 管理者制約 | `availableModels`設定時、`/model`/`--model`/`ANTHROPIC_MODEL`/Configで許可外モデルへ切替不可 |
| `default`例外 | `default`は`availableModels`に影響されず利用可能 |
| デフォルト挙動 | `default`はアカウント種別で変化（Max/Team Premium: Opus 4.6、Pro/Team Standard: Sonnet 4.6、Enterprise: Opus 4.6利用可だが非デフォルト） |
| 自動フォールバック | Opusで使用量しきい値到達時、Sonnetへ自動フォールバックする場合あり |
| 1Mコンテキスト | Opus 4.6/Sonnet 4.6が対応。購読者はextra usage有効化が必要。200Kトークン超過後は長文コンテキスト料金体系 |
| 企業運用 | Bedrock/Vertex/Foundry運用ではalias追従更新での破損回避のため、バージョン固定（pinning）推奨 |

## まとめ

| AC | 判定 | 根拠 |
|---|---|---|
| AC1: 切替可能モデル一覧 | PASS | エイリアス一覧 + 現行サポートモデル名を表で提示 |
| AC2: 切替挙動 | PASS | 即時反映・非再起動・非クリアを事実/推測分離で記述 |
| AC3: 制約事項 | PASS | プラン・管理者制約・default例外・1M条件を網羅 |
| AC4: ファイル作成 | PASS | `docs/research/cmd_317v2_task1_B.md` 作成済み |
| AC5: 構造化 | PASS | 指定5セクション + テーブル中心で構成 |

## 参照元（一次情報）

1. Claude Code Docs - Model configuration  
   https://code.claude.com/docs/en/model-config
2. Claude Code Docs - Interactive mode（Built-in commands `/model`）  
   https://code.claude.com/docs/en/interactive-mode
3. Claude Help Center - Claude Code model configuration  
   https://support.claude.com/en/articles/11940350-claude-code-model-configuration
