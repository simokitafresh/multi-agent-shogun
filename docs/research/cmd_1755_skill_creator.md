# cmd_1755_skill_creator: skill-creator v2.0 vs skill-design-rules.md 差分比較

<!-- cmd: cmd_1755 | worker: kotaro | date: 2026-04-06 -->
<!-- source_a: yohey-w/multi-agent-shogun/skills/skill-creator/SKILL.md (v2.0, Anthropic公式ガイド2026-03準拠) -->
<!-- source_b: context/skill-design-rules.md (cmd_911, freshness: 2026-03-16) -->

## §1 サマリー

| 観点 | 大元 skill-creator v2.0 | 我が軍 skill-design-rules.md | 判定 |
|------|------------------------|------------------------------|------|
| Frontmatter全フィールド | ✅ 完全リファレンス掲載 | ❌ 基本のみ | 我が軍に追加すべき |
| Description設計 | ✅ 7項目チェックリスト+デバッグ手法 | △ 必須3要素のみ | 拡張推奨 |
| Dynamic Features (引数置換/動的CTX) | ✅ `$ARGUMENTS`/`$0`/`$1`/`!`cmd`` | ❌ 記載なし | 取込必須 |
| Execution Patterns (A/B/C) | ✅ インライン/fork/手動専用を明示 | ❌ 記載なし | 取込必須 |
| Progressive Disclosure (L1/L2/L3) | ✅ 3層ロード説明 | △ 間接的に示唆のみ | 取込推奨 |
| Creation Workflow (12ステップ) | ✅ 体系化済み | ❌ 記載なし | 参考 |
| Anti-Patterns | △ 10+項目、具体的 | △ 4項目、基本的 | 拡張推奨 |
| 能力拡張原則 (§8) | ❌ 記載なし | ✅ 独自深化 (殿deepdive) | 我が軍が上回る |
| 品質を支える3つの力 | ❌ 記載なし | ✅ 保証/成長/能力 の3力 | 我が軍が上回る |
| 5設計パターン | ✅ (Sequential/Multi-Service等) | ✅ 同等 | 同等 |
| テスト3領域 | ✅ 具体例あり | ✅ あり | 同等 |
| 将軍システム固有ルール | △ 基本的 | ✅ 運用に沿った内容 | 我が軍が上回る |

---

## §2 我が軍にない項目（詳細）

### 2-1. Frontmatter全フィールドリファレンス【取込必須】

大元は全フィールドを網羅的に記載。我が軍の§2は構造説明のみで個別フィールドの説明がない。

追加すべきフィールド群:

| フィールド | 説明 | 用途 |
|-----------|------|------|
| `argument-hint: "[target]"` | 補完時ヒント表示 | 引数ありスキル |
| `disable-model-invocation: false` | true = /name のみ起動（自動発火禁止） | 副作用あるスキル |
| `user-invocable: true` | false = /メニュー非表示 | 背景知識スキル |
| `model: sonnet` | スキル実行時モデル指定 | コスト最適化 |
| `context: fork` | サブエージェントで隔離実行 | 重い処理 |
| `agent: general-purpose` | fork時のエージェント種別 | Explore/Plan/general |
| `license: MIT` | OSSスキル用 | 公開スキル |
| `compatibility: \|` | 環境要件 (1-500文字) | 互換性明示 |
| `metadata:` | カスタムメタデータ (author/version等) | 管理用 |
| `hooks:` | スキル内フック定義 (PostToolUse等) | 自動検証 |

セキュリティ追記（大元明示）:
- XML角括弧 `< >` **禁止**（プロンプトインジェクション防止）→ 我が軍に既に記載あり
- `name`に "claude" / "anthropic" 含む名前禁止（予約語）→ **我が軍に未記載**

### 2-2. Dynamic Features【取込必須】

スキル本文内での動的機能。我が軍は**全く記載なし**。

**a) 引数置換**
```
/my-skill 結婚 kekkon
```
- `$ARGUMENTS` → 全引数（`結婚 kekkon`）
- `$0` → 第1引数（`結婚`）
- `$1` → 第2引数（`kekkon`）
- `$ARGUMENTS`を本文で使わない場合、末尾に自動追加される

**b) 動的コンテキスト `!`command``**
スキル読み込み前にシェルコマンドを実行し、結果を埋め込む:
```markdown
## 現在のブランチ
!`git branch --show-current`
```
→ スキル起動時点での環境情報を動的にプロンプトに注入できる。

### 2-3. Execution Patterns【取込必須】

| パターン | フロントマター | 用途 |
|---------|--------------|------|
| A: インライン実行（デフォルト） | (指定不要) | ガイドライン型、短いタスク |
| B: Fork実行（隔離） | `context: fork` | 重い処理、大量出力 |
| C: 手動専用（副作用あり） | `disable-model-invocation: true` | /name でのみ起動 |

**重要注意（大元明示）**: `context: fork` + ガイドラインだけのスキルには使うな。サブエージェントには明確なタスクが必要。→ Anti-Patternsに追加すべき

### 2-4. Description 7項目チェックリスト【取込推奨】

我が軍の§6は6項目。大元は7項目で「悪い例/良い例」付き。

| # | チェック | 悪い例 | 良い例 |
|---|---------|-------|-------|
| 1 | What明記 | "ドキュメント処理" | "PDFからテーブルを抽出しCSVに変換" |
| 2 | When明記 | (なし) | "データ分析ワークフローで使用" |
| 3 | トリガーワード含有 | (なし) | "「記事QC」で起動" |
| 4 | 具体的なアクション動詞 | "管理する" | "抽出・変換・検証する" |
| 5 | 長さ: 1024文字以内 | 1単語 or 長すぎ | 2-3文 |
| 6 | 既存スキルと差別化 | 他スキルと被る | 独自の守備範囲を明示 |
| 7 | ネガティブトリガー | なし | "Do NOT use for: ..." |

### 2-5. Descriptionデバッグ手法【取込推奨】

発火しない場合の診断方法（大元に記載、我が軍になし）:
> Claudeに聞け: 「When would you use the [skill-name] skill?」
> Claudeがdescriptionを引用して答える → 足りない要素が見える。

### 2-6. Progressive Disclosure（3層）【取込推奨】

| 層 | 内容 | 読み込みタイミング |
|---|------|-----------------|
| L1 | YAMLフロントマター | **常時**（システムプロンプト内）|
| L2 | SKILL.md本文 | スキル関連と判断された時 |
| L3 | references/, scripts/ | 必要に応じてClaudeが参照 |

→ 「5,000語以内」の根拠を理解する上で有用な説明。

### 2-7. Anti-Patternsの追加項目【取込推奨】

我が軍の§7（4項目）に追加すべき項目:

| 追加NG | 理由 | 代わりに |
|-------|------|---------|
| `context: fork` + ガイドラインのみ | サブエージェントが迷走 | インライン実行 |
| `disable-model-invocation` + `user-invocable: false` | 誰も起動できない | どちらか片方 |
| 同時有効スキル50個超 | コンテキスト圧迫 | 選択的有効化 |
| フロントマターに独自フィールド | Claude Codeに無視される | 本文のMarkdownに記載 |
| スキルフォルダにREADME.md | 仕様違反 | SKILL.md or references/ に |
| nameに "claude"/"anthropic" | 予約語 | 別名を使え |

### 2-8. Creation Workflow 12ステップ【参考】

大元は12ステップの作成フローを提供。我が軍にはない。
→ 新スキル作成時の手順として参照用に取込み推奨。

---

## §3 取込推奨項目リスト（優先度順）

| 優先度 | 項目 | 対象セクション | 追加工数 | 理由 |
|-------|------|--------------|---------|------|
| **必須** | Dynamic Features（引数置換+動的CTX） | §2の後に新セクション追加 | 小 | 実装時に不可欠な技術情報。完全に欠落 |
| **必須** | Execution Patterns A/B/C | §2の後に新セクション追加 | 小 | `context: fork`/`disable-model-invocation`の使い分け基準 |
| **必須** | Frontmatter全フィールド表 | §2を拡張 | 中 | `argument-hint`/`disable-model-invocation`等が未記載 |
| **推奨** | Anti-Patterns追加6項目 | §7に追記 | 小 | `context:fork+ガイドのみ禁止`等は実用的 |
| **推奨** | Description 7項目チェックリスト | §6を拡張 | 小 | 具体例(悪い/良い)で判断精度向上 |
| **推奨** | Descriptionデバッグ手法 | §1の末尾 | 極小 | 診断ノウハウとして有用 |
| **参考** | Progressive Disclosure（L1/L2/L3） | §2/§4に1段落追加 | 極小 | 理解補助 |
| **参考** | Creation Workflow 12ステップ | 新§9として追加 | 中 | 参照フロー |

---

## §4 我が軍が大元を上回る項目（変更不要）

| 項目 | 我が軍の優位性 |
|------|-------------|
| §8 能力拡張原則（殿deepdive 2026-03-24） | HOW/WHAT/WHY分離、品質3力（保証/成長/能力）、判定軸3問、実証データ（WA率70%→12.5%）。大元に一切なし |
| 将軍システム固有ルール | 運用フローへの完全な統合。大元は保存先のみ |
| §3 5設計パターンの具体例 | 我が軍の例（週報/switch-project等）の方が具体的 |
| Anti-Patternsの深みある分析 | autofixの教訓が§8に統合されている |

---

## §5 結論

**大元 skill-creator v2.0 の最大の貢献**: 実装技術情報（Dynamic Features, Execution Patterns, Frontmatter全フィールド）が体系化されていること。

**我が軍の優位性**: §8の能力拡張原則と実証データ。この哲学層は大元にない。

**推奨アクション**: 「必須」3項目（Dynamic Features, Execution Patterns, Frontmatter拡張）を `context/skill-design-rules.md` に追記。Anti-Patterns6項目も§7に追記。
これで我が軍の skill-design-rules.md は Anthropic 公式ガイドを実証知見で包んだ最強版になる。

→ 追記は別cmd（impl）で実行。本cmdはあくまで差分調査。
