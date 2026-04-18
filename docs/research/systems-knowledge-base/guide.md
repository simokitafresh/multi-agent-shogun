# システム知識辞書 — 拡充ガイドライン

> 今後の偵察結果を辞書に追加する手順書。忍者向けガイド。
> 金融ML知識辞書(DM-signal/docs/research/knowledge-base/guide.md)の構造を踏襲し、外部システム知識向けにカスタマイズ。

## 原則

1. **省略禁止**: 圧縮ではなく再構造化。偵察報告の情報量を100%維持してフォーマット変換する
2. **Vercelスタイル**: `index.md`(未作成)= 索引層（1行要約+リンク）、各エントリ = 詳細層（全情報）
3. **相互参照必須**: 補完/競合/前提の3軸で関連エントリをリンクする
4. **拡張性**: 全エントリが同一フォーマット。後続偵察結果も同形式で追加

## 2層構造ルール

外部知識を追加・更新する時は、必ず以下の2層構造を守る。

### 一次知識層

- 対象: `systems/` 配下の各システムファイル（ace.md, vercel.md, gsd.md, gstack.md, oshio.md, claude-code.md 等）
- 内容: 各システムの公式ドキュメント、GitHub、ブログ記事、作者発言などの**原典から抽出した知識のみ**
- ルール: **原典不可侵**。我が軍固有の解釈・優劣判断・採用判断・設計比較を混ぜない
- 注意: 「このシステムより我が軍の方が優れている」等の評価は厳禁。事実のみ記載（殿厳命）

### 解釈層

- 対象: `shogun-analysis/`（将来作成予定）
- 内容: 我が軍固有の解釈、技術移転判断、対比分析、採否判断、設計への示唆
- 役割: 一次知識層を汚さずに、我が軍固有の利用方法・分析を分離して保持する
- 現状: `docs/research/system-comparison-2026-03-13.md` が解釈層の役割を担っている

### 適用範囲

- この原則は現在の6システムだけでなく、**今後追加する全ての外部システム知識**に適用する
- 一次知識層に我が軍固有内容が必要になった場合は、本文に混ぜず `shogun-analysis/` 側へ移す
- `index.md`（将来作成）は一次知識層と解釈層の両方に到達できる索引として維持する

## 検証トレーサビリティルール

一次知識層の各エントリ末尾には、出典に紐づく検証記録を必ず付ける。

```markdown
## Verification

- verified_at: YYYY-MM-DD
- method: WebSearch + WebFetch / GitHub精読 / 公式ドキュメント確認 等
- source: リポジトリURL / 公式ドキュメントURL / ブログURL
```

- `verified_at`: その内容を最後に検証した日付。推測で埋めない
- `method`: どう検証したかを 1 行で明示する。複合手法なら `WebSearch + GitHub releases精読` のように併記してよい
- `source`: 追跡可能な原典だけを書く。各ファイルの `## Sources` にある既存出典を優先する
- 出典が不明な場合は検証済み扱いにせず、以下で明示する

```markdown
## Verification

- verified_at: unverified
- method: unverified
- source: unverified
```

## エントリ追加手順

### Step 1: カテゴリ判定

| カテゴリ | ディレクトリ | 判定基準 |
|---------|------------|---------|
| 外部AIエージェントシステム | `systems/` | 他組織が開発・公開しているマルチエージェントフレームワーク、AI開発ツール |
| 解釈・対比分析 | `shogun-analysis/`（将来） | 我が軍固有の採用判断・対比・技術移転計画 |

### Step 2: ファイル名決定

```
systems/{kebab-case-名称}.md
```

- kebab-case（ハイフン区切り小文字）
- 探す側の言葉で命名（例: `claude-code.md`, `gsd.md`, `ace-framework.md`）
- 1システム1ファイル（複数システムを1ファイルに混ぜない）

### Step 3: テンプレートからエントリ作成

`systems/_template.md`（将来作成）をコピーし、全セクションを埋める。

#### 必須セクション

| セクション | 内容 | 省略 |
|-----------|------|------|
| タイトル + 概要 | システム名 + 1-2行要約（index.mdに転記） | 禁止 |
| Basic Info | Author/Status/Stars/Version/Repo/License テーブル | 禁止 |
| Design Philosophy | 設計信念。何を最も重視するか | 禁止 |
| Architecture | エージェント構造/通信方式/記憶/品質保証 | 禁止 |
| Key Features | 機能名/説明/導入バージョン テーブル | 禁止 |
| Changelog since YYYY-MM-DD | 日付/バージョン/変更/影響 テーブル | 禁止 |
| Notable Techniques | テクニック名/説明/このシステム固有か テーブル | 禁止 |
| Ecosystem | コミュニティ/フォーク/統合先/記事 | 禁止 |
| Sources | Repository/Documentation/Blog/Articles のURL | 禁止 |
| Verification | verified_at/method/source | 禁止 |

### Step 4: 偵察報告からの情報抽出

偵察報告YAMLから辞書エントリへの変換ルール:

| 報告YAML項目 | 辞書エントリ先 |
|-------------|--------------|
| `system_name` / `author` | § Basic Info |
| `design_philosophy` / `core_beliefs` | § Design Philosophy |
| `architecture` / `agent_structure` | § Architecture |
| `features` / `capabilities` | § Key Features |
| `changelog` / `recent_updates` | § Changelog since YYYY-MM-DD |
| `techniques` / `prompt_patterns` | § Notable Techniques |
| `community` / `integrations` | § Ecosystem |
| `references` / `sources` | § Sources |
| `lesson_candidate` | decision_candidateへ（我が軍固有判断のため一次知識層に混入禁止） |

### Step 5: 相互参照の更新（将来 index.md 作成後）

新エントリ追加時、既存エントリの「Related Systems」セクションも更新する:

```markdown
## Related Systems

- 設計類似: [システム名](相対パス.md)（どう類似するかの1行説明）
- 技術重複: [システム名](相対パス.md)（どの機能が重なるか）
- 技術移転元: [システム名](相対パス.md)（どの技術を提供しているか）
```

### Step 6: index.md 更新（将来作成後）

1. 該当カテゴリセクションにエントリ行を追加
2. フォーマット: `| ID | システム名 | 1行概要 | Status | Last Verified | リンク |`
3. IDは連番（S01, S02, ...）

## 一次知識層の純度ルール（汚染防止）

**一次知識層(systems/)に我が軍固有の評価・比較・実験結果を混入させることは禁止。**

### 禁止される混入例

| 混入パターン | なぜダメか | 正しい置き場所 |
|-------------|-----------|--------------|
| 「我が軍との比較でGSDが劣る」 | 我が軍固有の評価 | shogun-analysis/ 解釈層 |
| 「cmd_875で取込済み」 | 我が軍固有のタスク参照 | shogun-analysis/ 解釈層 |
| 「このシステムより我が軍が優れている」 | 優劣比較（殿厳命禁止） | 禁止（対比で優劣を論じるな） |
| 「v1.22.4はv1.21.1より改善されている（我が軍への示唆:...）」 | 我が軍への示唆の混入 | shogun-analysis/ 解釈層 |

### 許される記載

| パターン | なぜOKか |
|---------|---------|
| 「stars数: 28,539 (2026-03-03時点)」 | 原典の客観的数値 |
| 「Nyquist Validation: plan前にテストカバレッジを契約」 | システム固有の機能説明 |
| 「設計哲学: 'Context Rotが品質劣化の根因'」 | 原典の設計思想 |
| 「Agent Teamsは同一ファイル編集時に競合が発生するため推奨しない（公式ドキュメント記載）」 | 公式ドキュメントの制約情報 |

### 判定基準

**「この記述は当該システムの公式ドキュメントや作者の発言から引用できるか？」** → YES = 一次知識層に書いてよい。NO = shogun-analysis/解釈層へ（または禁止）。

## 品質チェックリスト

エントリ完成時に確認:

- [ ] **【純度】一次知識層に我が軍固有の評価・比較・タスク参照が混入していないか**
- [ ] **【純度】優劣比較（「〜より優れている」等）が含まれていないか（殿厳命）**
- [ ] Basic Info テーブルの全項目（Author/Status/Stars/Version/Repo/License）が記入されているか
- [ ] Changelog の日付が「YYYY-MM-DD」形式で記入されているか
- [ ] Notable Techniques の「このシステム固有か」列が記入されているか
- [ ] Sources に URL が含まれているか
- [ ] `## Verification` に verified_at・method・source の3項目があるか
- [ ] ファイル名が kebab-case になっているか
- [ ] 1ファイル500行以下か（超えたらサブセクションに分割）

## 注意事項

- **1ファイル500行以下**: 超えたら機能別サブファイル（例: `claude-code-agent-sdk.md`, `claude-code-agent-teams.md`）に分割
- **Changelog のカットオフ日**: 各エントリ作成時点を基準とする。次回更新時は `Changelog since YYYY-MM-DD` の日付を更新せよ
- **Stars数・バージョンは時点明記必須**: 「(2026-04-19時点)」のように検証日を付記する
- **おしお殿は元祖**: 対比で優劣を論じるな（殿厳命）。事実のみ記載
- **情報源はURL必須**: 「有名ツール」ではなく具体的URL。見つからない場合はツール名+作者+バージョン+日付

## 金融ML知識辞書との対応関係

システム知識辞書は金融ML知識辞書の構造を踏襲しつつ、外部AIシステム向けに以下を変更している:

| 金融ML版 | システム版 | 変更理由 |
|---------|---------|---------|
| `methods/`, `preprocessing/` 等カテゴリ分割 | `systems/` 単一ディレクトリ（現状） | システム数が少なく分割不要 |
| 数学的定式化 必須 | 不要（ソフトウェア仕様に置換） | 数式ではなくアーキテクチャ記述 |
| DM-Signal適用設計 | shogun-analysis/（将来）に分離 | 我が軍固有解釈を純度保護のため分離 |
| `methods/_template.md` | `systems/_template.md`（将来作成） | 同構造を外部システム向けに調整 |
| 相互参照（補完/競合/前提） | Related Systems（設計類似/技術重複/移転元） | ソフトウェアシステム間の関係性に合わせた軸 |
