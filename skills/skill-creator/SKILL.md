---
name: skill-creator
quality_metric: "将軍系: skill作成cmdのcmd_save.shチェック通過率(q1-q4 BLOCKなしで保存できた割合)"
description: 汎用的な作業パターンを発見した際に、再利用可能なClaude Codeスキルを自動生成する。繰り返し使えるワークフロー、ベストプラクティス、ドメイン知識をスキル化する時に使用。
argument-hint: "[skill-name]"
user-invocable: true
---

# Skill Creator - スキル自動生成

## Overview

作業中に発見した汎用的なパターンを、再利用可能なClaude Codeスキルとして保存する。
これにより、同じ作業を繰り返す際の品質と効率が向上する。

## When to Create a Skill

以下の条件を満たす場合、スキル化を検討せよ：

1. **再利用性**: 他のプロジェクトでも使えるパターン
2. **複雑性**: 単純すぎず、手順や知識が必要なもの
3. **安定性**: 頻繁に変わらない手順やルール
4. **価値**: スキル化することで明確なメリットがある

## Skill Structure

生成するスキルは以下の構造に従う：

```
skill-name/
├── SKILL.md          # 必須
├── scripts/          # オプション（実行スクリプト）
└── resources/        # オプション（参照ファイル）
```

詳細な設計原則は `context/skill-design-rules.md` を正本として参照する。このスキルでは作成時に使う実行チェックだけを持ち、description長・動的機能・アンチパターンの詳細は重複記載しない。

## Quality Checklist

作成・更新前に以下7項目をすべて確認する：

1. **目的**: 何を可能にするスキルかが1文で説明でき、手順代替ではなく能力拡張になっている。
2. **TRIGGER**: descriptionに発火キーワード、対象作業、使用条件が具体的に書かれている。
3. **DO NOT TRIGGER**: 類似スキル、別手順、対象外ケースが明記され、誤発火を避けられる。
4. **入出力定義**: 入力、参照ファイル、生成・更新する出力が明確で、成功時の成果物を検証できる。
5. **エラーハンドリング**: 必須ファイル欠落、既存スキル衝突、検証失敗時の停止・報告方法が明記されている。
6. **テスト可能性**: Triggering / Functional / Performance の最低1つ以上を実行可能な確認方法として書いている。
7. **既存重複チェック**: 既存スキル名・description・守備範囲を確認し、重複なら新規作成せず更新または統合を提案している。

## Frontmatter Validation

生成するSKILL.mdのfrontmatterは、最低限以下を検証する：

- `name`: kebab-case。既存スキルと重複しない。
- `description`: What / When / DO NOT TRIGGERを含み、`context/skill-design-rules.md` §1の1024文字以内を満たす。
- `argument-hint`: ユーザーが引数を渡すスキルでは必須。引数不要の場合は理由を本文に書く。
- `user-invocable`: `true` または `false` を明示。`disable-model-invocation: true` と同時に `false` にしない。

`model`など任意フィールドは必須にしない。使う場合は目的と副作用を本文に残す。

## SKILL.md Template

```markdown
---
name: {skill-name}
description: {What / When / DO NOT TRIGGERを含め、いつこのスキルを使うかを具体化}
argument-hint: "[target]"
user-invocable: true
---

# {Skill Name}

## Overview
{このスキルが何をするか}

## When to Use
{どういう状況で使うか、トリガーとなるキーワードや状況}

## Instructions
{具体的な手順}

## Examples
{入力と出力の例}

## Guidelines
{守るべきルール、注意点}
```

## Creation Process

1. パターンの特定
   - 何が汎用的か
   - どこで再利用できるか
   - 既存スキルと守備範囲が重複しないか

2. スキル名の決定
   - kebab-case を使用（例: api-error-handler）
   - 動詞+名詞 or 名詞+名詞

3. description の記述（最重要）
   - Claude がいつこのスキルを使うか判断する材料
   - 具体的なユースケース、ファイルタイプ、アクション動詞を含める
   - TRIGGER と DO NOT TRIGGER を入れて誤発火を抑える
   - 悪い例: "ドキュメント処理スキル"
   - 良い例: "PDFからテーブルを抽出しCSVに変換する。データ分析ワークフローで使用。"

4. frontmatter の検証
   - `argument-hint` が必要なスキルで欠落していないか
   - `user-invocable` が明示されているか
   - `disable-model-invocation: true` と `user-invocable: false` が同時指定されていないか

5. Instructions の記述
   - 明確な手順
   - 判断基準
   - エッジケースの対処
   - 入力、出力、失敗時の扱いを明記

6. テスト
   - 発火する文言と誤発火しない文言を確認
   - 生成物または更新内容をgrepや実行結果で確認

7. 保存
   - パス: ~/.claude/skills/shogun-{skill-name}/
   - 既存スキルと名前が被らないか確認

## 使用フロー

このスキルはKaroがShogunからの指示を受けて使用する。

1. Ashigaruがスキル化候補を発見 → Karoに報告
2. Karo → Shogunに報告
3. **Shogunが最新仕様をリサーチし、スキル設計を行う**
4. Shogunが人間に承認を依頼（dashboard.md経由）
5. 人間が承認
6. Shogun → Karoに作成を指示（設計書付き）
7. **Karo がこのskill-creatorを使用してスキルを作成**
8. 完了報告

※ Shogunがリサーチした最新仕様に基づいて作成すること。
※ Shogunからの設計書に従うこと。

## Examples of Good Skills

### Example 1: API Response Handler
```markdown
---
name: api-response-handler
description: REST APIのレスポンス処理パターン。エラーハンドリング、リトライロジック、レスポンス正規化を含む。API統合作業時に使用。
---
```

### Example 2: Meeting Notes Formatter
```markdown
---
name: meeting-notes-formatter
description: 議事録を標準フォーマットに変換する。参加者、決定事項、アクションアイテムを抽出・整理。会議後のドキュメント作成時に使用。
---
```

### Example 3: Data Validation Rules
```markdown
---
name: data-validation-rules
description: 入力データのバリデーションパターン集。メール、電話番号、日付、金額などの検証ルール。フォーム処理やデータインポート時に使用。
---
```

## Reporting Format

スキル生成時は以下の形式で報告：

「はっ！(Ha!) 新たなる技を編み出しました(New skill created!)
- スキル名: {name}
- 用途: {description}
- 保存先: {path}」
