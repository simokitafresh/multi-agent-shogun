# Skill Design Rules — 公式ガイド+実戦知見統合 (cmd_911)
<!-- last_updated: 2026-03-16 cmd_992 freshness review -->

> 出典: Anthropic「The Complete Guide to Building Skills for Claude」(2026-02) + おしお殿skill-creator-v2知見

## §1 Description設計（最重要）

**descriptionが判定の全て。** スキル選択はdescription*のみ*で決定される。本文(SKILL.md body)は選択判定に使われない。

### 必須3要素 (What + When + NOT When)

```
description: |
  【What】何をするスキルか（1文）
  【When】いつ使うか（トリガーワード・条件）
  【NOT When】いつ使わないか（負トリガー・除外条件）
```

### 制約
- **1024文字以内**（超過するとClaude Codeが切り捨てる可能性）
- `< >` をフロントマターに使用禁止（パース不具合の原因）
- 予約語（`name`, `description`以外のClaude予約語）を避ける

### 負トリガーの書き方
15個以上のスキル密集環境では**誤発火防止が死活問題**。「使わない場面」を明示せよ。

```yaml
# 良い例
description: |
  【将軍専用】知識基盤の定期棚卸し（8観点監査）。
  TRIGGER: /shogun-teire、知識整理、棚卸し
  DO NOT TRIGGER: 個別スキルの作成・編集、Memory MCPの単発操作、
  教訓登録（→lesson-sort）、PD反映確認（→shogun-pd-sync）
```

## §2 本文(SKILL.md body)設計

- **5,000語以内**（超過すると性能劣化）
- 構造: 手順 → 制約 → ガイドライン の3層
- バリデーションは**スクリプト化**推奨（「言語は非決定的、コードは決定的」）

## §3 5設計パターン

| パターン | 説明 | 我が軍の例 |
|----------|------|-----------|
| **Sequential** | 直線的な手順実行 | reset-layout, shogun-clear-prep |
| **Multi-Service** | 複数API/サービスを統合 | weekly-report(DM-Signal API + xAI Grok) |
| **Iterative** | ループ・段階的精錬 | shogun-teire(8観点巡回) |
| **Context-aware** | 環境に応じて振る舞い変更 | switch-project(PJ依存/非依存の判別) |
| **Domain Intelligence** | 専門知識を適用 | shogun-param-neighbor-check(統計的過適合判定) |

## §4 ファイル構造（推奨）

```
~/.codex/skills/{skill-name}/
├── SKILL.md          # 本体（5,000語以内）
├── scripts/          # ヘルパースクリプト（バリデーション等）
├── references/       # 参照資料（仕様書、API定義等）
├── assets/           # 静的ファイル（テンプレート等）
└── examples/         # 入出力例
```

CLI別ホーム配下に置け。Codexは `~/.codex/skills/`、Claudeは `~/.claude/skills/`。プロジェクト内 `.claude/skills/` は例外運用で、ホーム配置を優先せよ。

軽量スキル（SKILL.mdのみで完結）はサブディレクトリ不要。

## §5 3領域テスト

新スキル追加時に最低限確認:

| 領域 | テスト内容 | 方法 |
|------|-----------|------|
| **Triggering** | 正しく発火するか＋誤発火しないか | 意図的に類似フレーズを投げて確認 |
| **Functional** | 出力が正しいか | 実行→出力検証（スクリプト化推奨） |
| **Performance** | 速度・コスト | 実行時間計測、トークン消費量確認 |

## §6 品質チェックリスト（新規スキル作成時）

- [ ] description 1024文字以内
- [ ] What + When + NOT When の3要素あり
- [ ] フロントマターに `< >` なし
- [ ] SKILL.md 5,000語以内
- [ ] allowed-tools は最小権限（必要なものだけ）
- [ ] 既存スキルとの誤発火リスク確認済み
- [ ] Triggering test実施済み

## §7 アンチパターン

- README.mdをスキルに流用するな（構造が違う）
- 1スキルに複数の無関係な機能を詰め込むな
- descriptionに曖昧な表現を使うな（「汎用的に」「色々な」）
- allowed-toolsを`*`にするな（最小権限原則）
