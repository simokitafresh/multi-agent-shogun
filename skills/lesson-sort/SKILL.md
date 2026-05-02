---
name: lesson-sort
description: |
  【将軍専用】家老・忍者は使用禁止。将軍以外が呼んだ場合は即座に中断せよ。
  教訓セクションの未振り分けエントリを適切なcontextセクションに分類・移動する。
  加えて、本番不変量(Production Invariant)を検出し projects/{id}.yaml の受動的知識層に注入する。
  教訓自動合流3段構え+不変量橋渡し（収集→通知→振り分け→不変量注入）。
  将軍CLIで /lesson-sort を実行。gate_lesson_health.shのALERT後に使用。
  TRIGGER: /lesson-sort、gate_lesson_health.shのALERT、教訓の振り分け、未振り分け教訓の整理、本番不変量の抽出
  DO NOT TRIGGER: 教訓の新規登録（→lesson_write.sh）、7層横断監査（→shogun-teire）、
  MEMORY.md棚卸し（→/dream）、PD反映確認（→shogun-pd-sync）、
  教訓の非活性化・淘汰判定（→shogun-teire観点⑧）
allowed-tools:
  - Read
  - Grep
  - Glob
  - Edit
  - Bash
---

# /lesson-sort — 教訓の振り分けスキル

教訓セクション（context/*.md末尾）に溜まった未振り分けエントリを、
内容に基づいて適切なcontextセクション（§番号）に移動する。

**3段構えの全体像**:
1. 収集: `lesson_write.sh` → context索引末尾の教訓セクションに自動追記（cmd_300）
2. 通知: `gate_lesson_health.sh` → 未振り分けN件超でALERT（cmd_301）
3. **振り分け: /lesson-sort** ← このスキル

---

## When to Use

- `gate_lesson_health.sh` が未振り分けALERTを出した時
- 教訓セクションにエントリが溜まってきた時（手動トリガー）
- 大型cmd完了後の知識整理の一環として

---

## 手順

### Step 1: 教訓セクションからエントリ収集

各 `context/*.md` の教訓セクションを探索し、未振り分けエントリを収集する。

**重要**: セクション名はcontextごとに異なる。固定文字列ではなく正規表現で探索せよ。

```
パターン: /^## .*(?:教訓|Lesson)/i
```

既知のセクション名:
- `context/dm-signal-core.md`: `## 19. 教訓索引（Lesson Index）`
- `context/dm-signal-ops.md`: `## Ops教訓索引`
- `context/dm-signal-research.md`: `## 研究関連教訓索引 (projects/dm-signal/lessons.yaml)`
- `context/infrastructure.md`: `## Infra教訓索引`

各セクション内の `- L` で始まる行を抽出する。

---

### Step 2: lesson IDを特定し本文を読む

各エントリから lesson ID（`L{NNN}`）を抽出し、対応する `projects/{project}/lessons.yaml` の本文を読む。

- `context/infrastructure.md` の教訓 → `projects/infra/lessons.yaml`（存在すれば）または教訓索引テーブルの情報で判定
- `context/dm-signal-*.md` の教訓 → `projects/dm-signal/lessons.yaml`

---

### Step 3: 振り分け先セクションを判定

教訓の内容に基づき、同じcontextファイル内の適切なセクション（§番号）を判定する。

**判定基準の例**:

infrastructure.md:
| 内容カテゴリ | 振り分け先 |
|-------------|-----------|
| CTX管理 | コンテキスト管理 |
| inbox/通信 | inbox_watcher.sh / Communication |
| tmux/ペイン | tmux設定 |
| bash/script | 該当するインフラセクション |
| git/CI | 該当するインフラセクション |
| 教訓サイクル | 該当するインフラセクション |
| WSL2固有 | WSL2固有 |

dm-signal-ops.md（§番号）:
| 内容カテゴリ | 振り分け先 |
|-------------|-----------|
| DB接続・操作 | §6-7 |
| デプロイ・CI | §9 |
| パリティ検証 | §12 |
| 運用手順 | §14, §16, §17 |

dm-signal-research.md（§番号）:
| 内容カテゴリ | 振り分け先 |
|-------------|-----------|
| バックテスト | §19-§20 |
| 忍法・BB | §21-§22 |
| GS・最適化 | §23-§24 |

dm-signal-core.md:
| 内容カテゴリ | 振り分け先 |
|-------------|-----------|
| パイプライン | 該当セクション |
| データ構造 | 該当セクション |
| API | 該当セクション |

---

### Step 3.5: 本番不変量の検出（Production Invariant Extraction）

教訓の内容を読み、**本番バックエンドの挙動に関する事実**が含まれているかチェックする。

**検出トリガー**:
- lesson_write.shが自動付与した `production_invariant` タグ
- 内容に「本番では〜」「production〜」「パリティ〜不一致」等のパターン

**検出した場合**:
1. 対応する `projects/{id}.yaml` の `production_invariants:` セクションを読む
2. 既に同等の不変量が登録済みか確認（重複回避）
3. 未登録なら不変量提案を作成:
   ```yaml
   - id: PI-{NNN}
     fact: "不変量の事実（1行）"
     implication: "GS/impl設計への影響（1行）"
     source: "出典cmd"
     verified_file: "本番コードのパス"
   ```

**重要**: `verified_file` は必須。本番コードを実際に確認してからfactを書け。
推測で不変量を書くな（cmd_1031教訓: 確認しないことが問題）。

不変量が検出された教訓は Step 4 のテーブルに `[PI]` マーカーを付与する。

---

### Step 4: 振り分け提案をテーブル表示

```
【教訓振り分け提案】

| # | Lesson ID | タイトル(要約) | 現在位置 | 提案先セクション | 不変量 |
|---|-----------|--------------|---------|---------------|--------|
| 1 | L036 | ○○の注意点 | Infra教訓索引 | ## ninja_monitor.sh | - |
| 2 | L037 | △△の制約 | Ops教訓索引 | §7 DB運用 | - |
| 3 | L255 | 本番日次解像度 | dm-signal教訓索引 | §24 GS最適化 | [PI] |

対象: {N}件（うち不変量候補: {M}件）
```

**不変量候補がある場合**、振り分けテーブルの後に不変量提案も表示:

```
【本番不変量 追加提案】

| # | PI-ID | fact | implication | source | verified_file |
|---|-------|------|-------------|--------|---------------|
| 1 | PI-002 | ... | ... | cmd_XXX | backend/... |

→ 承認後 projects/{id}.yaml production_invariants: に追記
```

---

### Step 5: 教訓を移動 + 不変量を注入

提案テーブル表示後、承認なしで即実行する（殿の修正実績ゼロ+不可逆でない。2026-03-31棚卸しで撤去決定）。
以下の操作を実行:

**教訓の振り分け（既存）**:
1. 教訓セクションから該当行を **削除**
2. 提案先セクションに **1行結論+参照** で追記

**不変量の注入（新規）**:
3. `[PI]` マーカー付き教訓がある場合、`projects/{id}.yaml` の `production_invariants.entries:` に追記
4. `production_invariants.last_updated:` を現在日付に更新

**Vercelスタイル厳守**:
```
- L{ID}: {結論1行}（{出典cmd}）
```

例:
```
- L036: ninja_monitor idle検知のgrace period必須（cmd_303）
```

**注意事項**:
- 移動先に既に同等情報があれば重複を避けてマージ
- 教訓索引テーブル（`| ID | 結論 | 区分 | 出典 |` 形式）がある場合、テーブル行も適切に処理
- 箇条書き行（`- L{ID}: ...`）とテーブル行の両方が存在する場合、両方を移動

---

## Output Format

```
【/lesson-sort 実行結果】

移動完了: {N}件
スキップ: {M}件（重複あり/殿却下）

| # | Lesson ID | 移動元 | 移動先 |
|---|-----------|--------|--------|
| 1 | L036 | Infra教訓索引 | ## ninja_monitor.sh |
```

---

## Guidelines

1. **承認なしで即実行** — 殿の修正実績ゼロ+不可逆でない。提案テーブル表示後そのまま移動する
2. **Vercelスタイル厳守** — 結論1行+参照。散文禁止
3. **正規表現で探索** — セクション名は固定値でなく `教訓|Lesson` パターンで検索
4. **重複回避** — 移動先に同等の記述がないかGrepで事前確認
5. **Edit toolで編集** — context/*.mdはflock対象外なのでEdit toolで安全に編集可能
6. **教訓索引の二重構造に注意** — テーブル形式と箇条書き形式が混在する場合がある（infrastructure.mdの例）
7. **0件なら即終了** — 未振り分けエントリがなければ「振り分け対象なし」と報告して終了
