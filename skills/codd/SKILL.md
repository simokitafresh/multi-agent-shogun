---
name: codd
argument-hint: "[spec_path|plan_path|target]"
description: |
  CoDD(Coherence-Driven Development)設計書パイプラインを実行する。
  spec.mdから設計書群を自動生成し、リファクタリング・新規設計の品質を担保する。
  TRIGGER: /codd、設計書生成、CoDDパイプライン、CoDD設計
  DO NOT TRIGGER: テスト実行のみ（batsを直接使え）、デーモンの起動・停止、
  CoDD外の単発コード修正
quality_metric: "当該スキル使用タスクのWA不発生率（logs/karo_workarounds.yamlにCoDD手順起因のworkaroundが記録されない割合）"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# CoDD 設計書パイプラインスキル

## 前提条件

- CoDD v2.18.0: `$HOME/.codd-venv/bin/codd`
- PATH設定: `export PATH="$HOME/.codd-venv/bin:$PATH"`
- ai_command: codd.yamlで定義（`$HOME/bin/claude --print --model claude-opus-4-6 --tools ""`）
- 確認: `$HOME/.codd-venv/bin/codd --version` が `codd, version 2.18.0` を返すこと
- 非対話BashではPATH未設定で`codd`が見えない場合がある。フルパスかPATH exportを使う。

## 使い方

### 1. 新規設計書パイプライン（グリーンフィールド）

```bash
# Step 1: spec.mdを書く（人間が書く。これが全ての品質を決める）
# Step 2: 初期化
codd init --project-name "プロジェクト名" --language bash --requirements spec.md

# Step 3: 要件穴/coverage軸を発見
codd elicit --interactive

# Step 4: Wave構成を自動設計
codd plan --init

# Step 5: 設計書を順次生成
waves=$(codd plan --waves)
for wave in $(seq 1 $waves); do
  codd generate --wave $wave
done

# Step 6: 品質ゲート
codd validate
codd dag verify
```

### 2. 既存コードから設計書逆生成（ブラウンフィールド）

```bash
# 静的解析（AI不使用、$0、Python/Go/TS/Java対応）
codd extract --path . --source-dirs src

# AI駆動抽出（bash含む全言語対応、claude --print使用）
codd extract --path . --source-dirs scripts --language bash --ai

# v2.x brownfield統合レポート
codd brownfield .
```

### 3. 品質検証

```bash
codd validate
# docs/内の既存ファイルがフロントマターなしエラーになる場合:
# codd.yaml のscan.excludeに除外パスを追加
```

### 4. 依存グラフと変更伝播（v2.x / skeleton-complete）

```bash
# frontmatterのcodd.node_id / depends_onから依存グラフを構築
codd scan --path .

# git diffから影響範囲をGreen/Amber/Grayに分類
codd impact --path .

# 下流docsを更新
codd propagate --path . --update
```

記事`codd-skeleton-complete`の中核は「docsを作る」ではなく「依存グラフでdocsを腐らせない」。新規生成より、既存docsの`scan -> impact -> propagate --update`を優先して考える。

### 5. PHENOMENON修正（v2.17+）

```bash
# 触って気づいた事象から、設計書 -> 実装 -> テスト更新へ進める
codd fix "ログインエラーをわかりやすくしたい"

# CI/夜間バッチでは曖昧性で止める
codd fix "モバイルでボタンが押しにくい" --non-interactive --on-ambiguity abort
```

### 6. Lexicon / coverage

```bash
codd lexicon list
codd lexicon install web_responsive web_a11y_wcag22_aa
codd lexicon diff web_responsive
codd coverage report --format md
```

## 注意事項

1. **specの質がボトルネック**: AIは書いてないことは作らない。要件を具体的に書け
2. **v1.10のbash implement非対応は履歴扱い**: v2.18.0では`codd implement run --language bash`を試行可能。失敗時はgenerate/propagateまでCoDD、実装は手動
3. **Wave 4が失敗することがある**: AIの出力フォーマット不安定。リトライで解消
4. **docs/の既存ファイル**: codd.yaml scan.excludeで除外しないとvalidateが大量エラー
5. **codd extract --ai / brownfield**: ファイル数が多いと時間がかかる。対象を絞れ
6. **auto-repair**: `dag verify --auto-repair`は既定dry-run。`--apply`は共有運用YAMLやqueueには使わない

## 将軍システムでの活用パターン

- **大規模リファクタリング**: spec.md→codd plan→generate→設計書レビュー→cmdで実装
- **新規PJ設計**: spec.md→全Wave生成→Implementation Planをcmd分割に変換
- **PHENOMENON修正**: ユーザーが触って感じた事象を`codd fix "..."`へ渡し、設計書・実装・テストを一括更新

## codd.yaml設定例

```yaml
ai_command: $HOME/bin/claude --print --model claude-opus-4-6 --tools ""
scan:
  source_dirs:
    - scripts/
    - lib/
  exclude:
    - 'docs/research/**'  # 既存docs除外
```
