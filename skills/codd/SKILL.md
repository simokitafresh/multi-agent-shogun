---
name: codd
argument-hint: "[spec_path|plan_path|target]"
description: |
  CoDD(Coherence-Driven Development)設計書パイプラインを実行する。
  spec.mdから設計書群を自動生成し、リファクタリング・新規設計の品質を担保する。
  TRIGGER: /codd、設計書生成、CoDDパイプライン、リファクタリング設計
  DO NOT TRIGGER: コード実装そのもの（CoDDはbashのimplement非対応）、
  テスト実行（batsを直接使え）、デーモンの起動・停止
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

- CoDD v1.7.1: `/home/simokitafresh/.codd-venv/bin/codd`
- PATH設定: `export PATH="/home/simokitafresh/.codd-venv/bin:$PATH"`
- ai_command: codd.yamlで定義（`/home/simokitafresh/bin/claude --print --model claude-opus-4-6 --tools ""`）

## 使い方

### 1. 新規設計書パイプライン（グリーンフィールド）

```bash
# Step 1: spec.mdを書く（人間が書く。これが全ての品質を決める）
# Step 2: 初期化
codd init --project-name "プロジェクト名" --language bash --requirements spec.md

# Step 3: Wave構成を自動設計
codd plan --init

# Step 4: 設計書を順次生成
waves=$(codd plan --waves)
for wave in $(seq 1 $waves); do
  codd generate --wave $wave
done

# Step 5: 品質ゲート
codd validate
```

### 2. 既存コードから設計書逆生成（ブラウンフィールド）

```bash
# 静的解析（AI不使用、$0、Python/Go/TS/Java対応）
codd extract --path . --source-dirs src

# AI駆動6層抽出（bash含む全言語対応、claude --print使用）
codd extract --path . --source-dirs scripts --language bash --ai
```

### 3. 品質検証

```bash
codd validate
# docs/内の既存ファイルがフロントマターなしエラーになる場合:
# codd.yaml のscan.excludeに除外パスを追加
```

## 注意事項

1. **specの質がボトルネック**: AIは書いてないことは作らない。要件を具体的に書け
2. **codd implementはbashに非対応**: TypeScriptを生成する。bashプロジェクトではgenerateまで
3. **Wave 4が失敗することがある**: AIの出力フォーマット不安定。リトライで解消
4. **docs/の既存ファイル**: codd.yaml scan.excludeで除外しないとvalidateが大量エラー
5. **codd extract --ai**: ファイル数が多いと時間がかかる。対象を絞れ

## 将軍システムでの活用パターン

- **大規模リファクタリング**: spec.md→codd plan→generate→設計書レビュー→cmdで実装
- **新規PJ設計**: spec.md→全Wave生成→Implementation Planをcmd分割に変換
- **DM-Signal(Python)**: codd extract→codd implement まで全工程使える可能性あり

## codd.yaml設定例

```yaml
ai_command: /home/simokitafresh/bin/claude --print --model claude-opus-4-6 --tools ""
scan:
  source_dirs:
    - scripts/
    - lib/
  exclude:
    - 'docs/research/**'  # 既存docs除外
```
