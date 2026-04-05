# Skill Design Rules — 公式ガイド+実戦知見統合 (cmd_911)
<!-- last_updated: 2026-04-06 cmd_1758 Dynamic Features+Execution Patterns+Anti-Patterns追加 -->

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

## §2a Dynamic Features（引数置換+動的コンテキスト）

スキル本文(SKILL.md body)内で使える動的機能。

### 引数置換

`/my-skill 結婚 kekkon` と呼び出した場合:

| 変数 | 展開結果 | 用途 |
|------|---------|------|
| `$ARGUMENTS` | `結婚 kekkon`（全引数） | 全入力をそのまま渡す |
| `$0` | `結婚`（第1引数） | 位置指定で取得 |
| `$1` | `kekkon`（第2引数） | 位置指定で取得 |

- `$ARGUMENTS`を本文で使わない場合、末尾に自動追加される
- フロントマター `argument-hint: "[target]"` で補完時ヒントを表示可能

### 動的コンテキスト `!`command``

スキル読み込み前にシェルコマンドを実行し、結果を埋め込む:

```markdown
## 現在のブランチ
!`git branch --show-current`
```

起動時点の環境情報をプロンプトに動的注入できる。環境依存の判断材料を渡す場合に有効。

## §2b Execution Patterns（実行モード）

| パターン | フロントマター | 用途 | 例 |
|---------|--------------|------|-----|
| **A: インライン**（デフォルト） | (指定不要) | ガイドライン型、短タスク | shogun-teire, lesson-sort |
| **B: Fork（隔離）** | `context: fork` | 重い処理、大量出力 | Explore系、長時間分析 |
| **C: 手動専用** | `disable-model-invocation: true` | /name でのみ起動（自動発火禁止） | 副作用あるスキル |

### Fork実行の追加フロントマター

```yaml
context: fork
agent: general-purpose   # fork時のエージェント種別（Explore/Plan/general-purpose）
```

**注意**: `context: fork` + ガイドラインだけのスキルには使うな。サブエージェントには明確なタスクが必要。（→ §7 アンチパターン参照）

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
~/.claude/skills/{skill-name}/
├── SKILL.md          # 本体（5,000語以内）
├── scripts/          # ヘルパースクリプト（バリデーション等）
├── references/       # 参照資料（仕様書、API定義等）
├── assets/           # 静的ファイル（テンプレート等）
└── examples/         # 入出力例
```

ホーム配下 `~/.claude/skills/` に置け。プロジェクト内 `.claude/skills/` は例外運用で、ホーム配置を優先せよ。

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
- `context: fork` + ガイドラインのみのスキルを作るな（サブエージェントが迷走する。forkには明確なタスクが必要）
- `disable-model-invocation: true` と `user-invocable: false` を同時指定するな（誰も起動できなくなる）
- 同時有効スキル50個を超えるな（コンテキスト圧迫。選択的有効化で絞れ）
- フロントマターに独自フィールドを追加するな（Claude Codeに無視される。本文のMarkdownに記載せよ）
- スキルフォルダにREADME.mdを置くな（仕様違反。SKILL.md or references/ に記載）
- `name`に "claude" / "anthropic" を含めるな（予約語。別名を使え）

## §8 スキルの本質 — 能力拡張原則（殿deepdive 2026-03-24, gstack知見統合）

### 核心原理: スキルは能力拡張（HOW）であり手順代替（WHAT）ではない

gstack(garrytan/YC CEO)の6スキルが教える: **良いスキルはHOWを渡してWHAT/WHYはエージェントに残す。** browseスキルはページの操作方法を教えるが、何を見るか・なぜ見るかはエージェントが決める。

**手順をスキルに置き換えると思考が死ぬ。能力をスキルで拡張すると思考が広がる。**

### 品質を支える3つの力（独立・代替不可能）

| 力 | 手段 | 品質への効果 | 特性 |
|----|------|------------|------|
| **保証** | gate/hook | 床を上げる（最低品質を担保） | 事後検証。強制。嘘をつけない |
| **成長** | lessons + 学習ループ | 天井を上げる（次サイクル強化） | FAILから学ぶ。還流して初めて機能。**複利** |
| **能力** | skill（能力拡張型） | 新しいことができるようになる | HOWを提供。判断はエージェントに残す |

学習ループは複利で成長する。高速で回す方が将来価値が高い。**スキルが学習ループを阻害するなら、そのスキルは害。スキルが学習ループを加速するなら、そのスキルは武器。**

### スキル設計の判定軸

| 問い | YES → | NO → |
|------|-------|------|
| 新しい能力を付与するか？（API呼出、ツール連携、外部検索） | **能力拡張型 → 作れ** | 次の問いへ |
| 判断ゼロで入力→出力が決定的か？ | **bashスクリプトで書け**（LLM不要） | 次の問いへ |
| エージェントの思考を代替するか？ | **作るな。gate+lessonsで対処** | — |

### 良いスキル vs 悪いスキル

| 型 | 特徴 | 例 | 判定 |
|----|------|-----|------|
| **能力拡張** | HOWを渡す。エージェントがWHAT/WHYを決める | weekly-report(API), x-research(Grok), gs-bench-gate(ベンチ) | **良い** |
| **視野拡張** | 観点・フレームを渡す。判断は委ねる | shogun-teire(8観点), shogun-param-neighbor-check(統計手法) | **良い** |
| **手順固定** | 毎回同じルートを通らせる。思考の余地が消える | ルーチンの手順化、チェックリスト化 | **悪い** |
| **スクリプト重複** | bashで書ける処理をスキルにしている | reset-layout(=reset_layout.sh), switch-project(=switch_project.sh) | **冗長。スクリプトに統合** |

### autofixの教訓: 外すのではなくフィードバック経路を作れ

gate_report_autofix.shは76回発動、うち直近7件が実報告。忍者に見えないため同じミスを繰り返す。
**外すのではなくフィードバックを可視化** — gstackのstop_for思想。autofix発動→忍者に通知→次回の改善機会。

### 実証データ（2026-03-24時点）

- WA率 70% → 12.5%。gate群(GP-053/057/058/060)と教訓のみで達成
- workaround 50件中84%が手順的問題 → 全てgateで解決済み
- 能力拡張型スキル(weekly-report等)は品質を下げていない — 判断をエージェントに残しているため
