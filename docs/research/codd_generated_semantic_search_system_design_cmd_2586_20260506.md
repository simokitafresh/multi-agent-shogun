---
codd:
  node_id: design:system-design
  type: design
  depends_on:
  - id: test:acceptance-criteria
    relation: constrained_by
    semantic: governance
  - id: governance:adr-parser-consolidation
    relation: constrained_by
    semantic: governance
  depended_by:
  - id: detailed_design:mode-dispatch-flow
    relation: depends_on
    semantic: technical
  conventions:
  - targets:
    - function:first_layer_search
    - function:render_llm_resources
    reason: Bash関数はI/O orchestrationのみに縮小し、Markdown table parseロジックを直接保持してはならない（R2制約）。
  - targets:
    - function:semantic_index_python
    reason: re.split / concepts構築ロジックを単一Python heredoc内に一元化すること（R1制約）。2箇所重複はリリース不可。
  - targets:
    - script:semantic_search
    reason: CLI互換性・出力互換性・exit status伝播の3制約をアーキテクチャレベルで保証する設計であること。
  modules:
  - semantic_search
---

# System Design — Before/After アーキテクチャ

## 1. Overview

`scripts/semantic_search.sh`（289行、Bash + Python heredoc構成）は、セマンティックインデックス（Markdownテーブル形式）を読み取り、query に対して概念照合・リソース解決を行うCLIスクリプトである。現行アーキテクチャでは、Markdownテーブルの parse ロジック（`re.split(r"(?m)^##\s+")` によるセクション分割 → row parse → `id,label,aliases,resources` dict構築）が `first_layer_search`（L65–L155）と `render_llm_resources`（L157–L233）の2箇所に重複しており、`re.split` が2箇所、`concepts = []` 初期化が2箇所に分散している。

本設計書は、この重複を `semantic_index_python()` 関数への一元化によって解消するリファクタリングの Before/After アーキテクチャを定義する。

### 設計目標

1. **parse ロジックの単一化（R1制約）**: `re.split` / `concepts` 構築ロジックを単一 Python heredoc 内に一元化し、2箇所重複を排除する。`grep -c 're.split' scripts/semantic_search.sh` = 1、`grep -c 'concepts = \[\]' scripts/semantic_search.sh` = 1 をリリースゲートとする。
2. **Bash関数のI/O orchestration限定化（R2制約）**: `first_layer_search()` および `render_llm_resources()` はMarkdown table parseロジックを直接保持せず、`semantic_index_python` への mode 呼び出しと I/O orchestration（引数受け渡し、LLMコマンド起動、一時ファイル管理、exit status制御）のみに縮小する。
3. **CLI互換性・出力互換性・exit status伝播の3制約保証**: `--llm`、`--help`、unknown option、no query、missing index の各挙動がリファクタリング前後で同一であること。既存 `tests/unit/test_semantic_search.bats` 4テスト全PASSをリリースブロッキング条件とする。

### 非機能要件

| 指標 | before基準値 | 許容閾値 | 測定方法 |
|------|-------------|---------|----------|
| alias hit 実行時間 | 53ms（5回平均） | ≤ 53ms | `bash scripts/semantic_search.sh 意味検索` を同一環境で5回計測 |
| LLM fallback(mock) 実行時間 | 109ms（5回平均） | ≤ 109ms | `env SEMANTIC_LLM_CMD="$mock" bash scripts/semantic_search.sh 品質を伸ばす輪` を同一環境で5回計測 |
| 構文チェック | `bash -n` exit 0 | exit 0 | `bash -n scripts/semantic_search.sh` |
| 既存Bats | 4 tests, 0 failures, 0 skipped | 同一 | `bats tests/unit/test_semantic_search.bats` |

### 規約準拠宣言

本設計書は以下の non-negotiable conventions を明示的に反映する。

- **R2制約（`function:first_layer_search`, `function:render_llm_resources`）**: Architecture セクション §2.2 After アーキテクチャにおいて、両関数がMarkdown table parseロジックを保持せず I/O orchestration のみに縮小される構造を定義する。
- **R1制約（`function:semantic_index_python`）**: Architecture セクション §2.3 において、`re.split` / `concepts` 構築ロジックが単一 Python heredoc 内に存在する構造を定義し、2箇所重複をリリース不可条件として扱う。
- **CLI互換性・出力互換性・exit status伝播の3制約（`script:semantic_search`）**: Architecture セクション §2.4 において、3制約をアーキテクチャレベルで保証するインターフェース境界と伝播経路を定義する。

## 2. Architecture

### 2.1 Before アーキテクチャ（現行構造）

```
scripts/semantic_search.sh (289行)
│
├── CLI引数解析 (case/getopts)
│   ├── --help → ヘルプ出力, exit 0
│   ├── --llm  → LLM_MODE=true
│   ├── unknown option → エラー出力, exit 非ゼロ
│   └── no query → エラー出力, exit 非ゼロ
│
├── first_layer_search() [L65-L155]
│   ├── Python heredoc #1 ★重複
│   │   ├── re.split(r"(?m)^##\s+")        ← 出現1/2
│   │   ├── concepts = []                   ← 出現1/2
│   │   ├── row parse → id,label,aliases,resources dict構築
│   │   └── query vs alias/label 照合 → stdout出力
│   └── 一致なし時のフォールバック処理
│
├── render_llm_resources() [L157-L233]
│   ├── Python heredoc #2 ★重複
│   │   ├── re.split(r"(?m)^##\s+")        ← 出現2/2
│   │   ├── concepts = []                   ← 出現2/2
│   │   ├── row parse → id,label,aliases,resources dict構築
│   │   └── MATCH: <concept_id> → resources解決 → stdout出力
│   └── exit status伝播
│
├── main フロー
│   ├── missing index チェック → エラー, exit 非ゼロ
│   ├── first_layer_search 実行
│   ├── LLM_MODE時: $SEMANTIC_LLM_CMD 実行 → render_llm_resources
│   └── exit status伝播
```

**Before の問題点:**

- Markdown parse パイプライン（`re.split` → row parse → dict構築）が `first_layer_search` と `render_llm_resources` で完全に二重化
- index形式変更時に片側だけ更新されるリスク
- parse ロジックとビジネスロジック（照合/解決）が単一関数内に混在

### 2.2 After アーキテクチャ（リファクタリング後）

```
scripts/semantic_search.sh
│
├── CLI引数解析 (case/getopts) ← 変更なし
│   ├── --help → ヘルプ出力, exit 0
│   ├── --llm  → LLM_MODE=true
│   ├── unknown option → エラー出力, exit 非ゼロ
│   └── no query → エラー出力, exit 非ゼロ
│
├── semantic_index_python() [新設]
│   └── Python heredoc (単一)
│       ├── re.split(r"(?m)^##\s+")        ← 出現1/1 ✓
│       ├── concepts = []                   ← 出現1/1 ✓
│       ├── row parse → id,label,aliases,resources dict構築
│       └── mode 分岐 (sys.argv[1])
│           ├── "first-layer"          → query vs alias/label照合 → stdout
│           └── "render-llm-resources" → concept ID解決 → stdout
│
├── first_layer_search() [I/O orchestrationのみ ✓ R2制約]
│   └── semantic_index_python first-layer "$no_match_mode"
│       （Python heredoc / Markdown parse処理を直接保持しない）
│
├── render_llm_resources() [I/O orchestrationのみ ✓ R2制約]
│   └── semantic_index_python render-llm-resources "$llm_output_file"
│       （Python heredoc / Markdown parse処理を直接保持しない）
│
├── main フロー ← 変更なし
│   ├── missing index チェック → エラー, exit 非ゼロ
│   ├── first_layer_search 実行
│   ├── LLM_MODE時: $SEMANTIC_LLM_CMD 実行 → render_llm_resources
│   └── exit status伝播
```

### 2.3 `semantic_index_python()` 関数の内部設計

**R1制約の充足:** `re.split(r"(?m)^##\s+")` および `concepts = []` によるparse・構築ロジックは `semantic_index_python()` 内の単一 Python heredoc 内にのみ存在する。スクリプト全体で `re.split` が1箇所、`concepts = []` が1箇所であることは `grep -c` による静的検証でリリースゲートとして保証する。

**呼び出しインターフェース:**

```bash
# first-layer モード: alias/label照合
semantic_index_python first-layer "$no_match_mode"

# render-llm-resources モード: concept ID→resources解決
semantic_index_python render-llm-resources "$llm_output_file"
```

**Python heredoc 内部構造:**

```
┌─────────────────────────────────────────────┐
│ semantic_index_python() Python heredoc       │
│                                              │
│ 1. 共通 parse フェーズ (mode非依存)          │
│    ├── index_file 読み込み                   │
│    ├── re.split(r"(?m)^##\s+") でセクション分割│
│    ├── 各セクションの Markdown table row parse │
│    └── concepts = [] に id,label,aliases,    │
│        resources dict を構築                 │
│                                              │
│ 2. mode 分岐フェーズ                         │
│    ├── if mode == "first-layer":             │
│    │   └── query vs alias/label 照合         │
│    │       → 一致: resources を stdout出力    │
│    │       → 不一致: no_match_mode に応じた処理│
│    └── elif mode == "render-llm-resources":  │
│        └── llm_output_file から MATCH: 行抽出 │
│            → concept_id で concepts を検索    │
│            → resources を stdout出力          │
└─────────────────────────────────────────────┘
```

**parse パイプラインの詳細:**

| ステップ | 処理 | 入力 | 出力 |
|----------|------|------|------|
| 1 | `re.split(r"(?m)^##\s+")` | index_file の全文 | セクション文字列のリスト |
| 2 | 各セクションから Markdown table 行を抽出 | セクション文字列 | `\|` 区切りの行リスト |
| 3 | 行を parse し dict 構築 | table 行 | `{id, label, aliases, resources}` |
| 4 | `concepts` リストに追加 | dict | `concepts: list[dict]` |

### 2.4 CLI互換性・出力互換性・exit status伝播の保証構造

**3制約のアーキテクチャレベル保証:**

リファクタリングの変更スコープは `first_layer_search()` 関数本体、`render_llm_resources()` 関数本体、および新設の `semantic_index_python()` 関数に限定する。以下のコンポーネントには一切の変更を加えない。

#### CLI互換性の保証

| CLI入力 | 処理コンポーネント | 変更有無 | exit status |
|---------|-------------------|---------|-------------|
| `--help` | CLI引数解析（case分岐） | 変更なし | 0 |
| `--llm <query>` | CLI引数解析 → `$SEMANTIC_LLM_CMD` fork/exec | 変更なし | LLMコマンドの終了コード |
| unknown option | CLI引数解析（case分岐） | 変更なし | 非ゼロ |
| no query（引数なし） | CLI引数解析 | 変更なし | 非ゼロ |
| missing index | main フロー内のファイル存在チェック | 変更なし | 非ゼロ |

CLI引数解析のcase/getopts分岐はリファクタリング対象外のため、全CLIオプションの stdout/stderr 出力およびexit statusはリファクタリング前と同一を保証する。

#### 出力互換性の保証

`semantic_index_python()` の Python heredoc は、before コードの2つの Python heredoc がそれぞれ stdout に出力していた文字列と完全同一の文字列を stdout に出力する。これは `tests/unit/test_semantic_search.bats` の4テストケースにおける `assert_output` / `assert_line` 期待文字列との完全一致で検証する。

#### exit status 伝播経路

```
Python heredoc exit code
  → semantic_index_python() Bash関数の終了コード
    → first_layer_search() / render_llm_resources() の終了コード
      → scripts/semantic_search.sh の終了コード
```

`set -euo pipefail` チェーンにより、Python heredoc で非ゼロ終了した場合は即座に呼び出し元 Bash 関数、さらにスクリプト全体の exit status に伝播する。LLMコマンド（`$SEMANTIC_LLM_CMD`）の fork/exec と exit status 伝播は Bash 側の orchestration に残り、`semantic_index_python` 内部では LLM コマンドを起動しない。

### 2.5 LLMコマンド実行経路の不変性

LLMコマンド実行経路はリファクタリングの変更スコープ外であり、以下のフローが before/after で完全に同一である。

```
main フロー
  └── LLM_MODE=true の場合
      ├── $SEMANTIC_LLM_CMD をサブプロセスとして fork/exec
      │   ├── stdin: LLM用プロンプト（before同一内容）
      │   └── stdout: LLM応答 → 一時ファイルに保存
      └── render_llm_resources() に一時ファイルパスを渡す
          └── semantic_index_python render-llm-resources "$llm_output_file"
```

`SEMANTIC_LLM_CMD` 環境変数によるコマンド差替えも before 同様に機能する。LLMコマンドが非ゼロで終了した場合、`semantic_search.sh` も非ゼロで終了する。

### 2.6 Before/After 差分マトリクス

| 要素 | Before | After | 変更種別 |
|------|--------|-------|---------|
| `semantic_index_python()` | 不在 | 新設（Python heredoc + mode分岐） | 追加 |
| `first_layer_search()` 本体 | Python heredoc（parse+照合） | `semantic_index_python first-layer` 呼び出し1行 | 置換（R2制約） |
| `render_llm_resources()` 本体 | Python heredoc（parse+解決） | `semantic_index_python render-llm-resources` 呼び出し1行 | 置換（R2制約） |
| `re.split` 出現箇所 | 2箇所 | 1箇所（`semantic_index_python` 内） | 削減（R1制約） |
| `concepts = []` 出現箇所 | 2箇所 | 1箇所（`semantic_index_python` 内） | 削減（R1制約） |
| CLI引数解析 | case/getopts | 変更なし | 不変 |
| `$SEMANTIC_LLM_CMD` 実行経路 | Bash側 orchestration | 変更なし | 不変 |
| exit status伝播 | `set -euo pipefail` チェーン | 変更なし | 不変 |
| `tests/unit/test_semantic_search.bats` | 4テスト | 変更なし（全PASS必須） | 不変 |

### 2.7 実施順序

ADR D4 で確定した6ステップの実施順序に従い、各ステップの完了条件を満たした後に次ステップへ進む。

| Step | 内容 | 完了条件 | 検証コマンド |
|------|------|----------|-------------|
| 1 | `semantic_index_python()` 関数を `scripts/semantic_search.sh` 内に追加 | `bash -n` exit 0 | `bash -n scripts/semantic_search.sh` |
| 2 | `first_layer_search()` を `semantic_index_python first-layer "$no_match_mode"` 呼び出しに差替え | `bash -n` pass かつ Bats 4/4 pass | `bash -n scripts/semantic_search.sh && bats tests/unit/test_semantic_search.bats` |
| 3 | `render_llm_resources()` を `semantic_index_python render-llm-resources "$llm_output_file"` 呼び出しに差替え | `bash -n` pass かつ Bats 4/4 pass | 同上 |
| 4 | 構文チェック最終確認 | exit 0 | `bash -n scripts/semantic_search.sh` |
| 5 | 回帰テスト最終確認 | 4 tests, 0 failures, 0 skipped | `bats tests/unit/test_semantic_search.bats` |
| 6 | before/after 性能再計測 | alias hit ≤ 53ms, LLM mock ≤ 109ms（各5回平均） | 手動計測、結果を `docs/benchmarks/` に記録 |

Step 2・3 それぞれの完了時に、LLMコマンド実行経路と exit status 伝播が変更されていないことを既存 Bats テストの LLM fallback ケースで検証する。

### 2.8 テスト戦略との接続

リファクタリングの正当性は以下の多層テストで保証する。

| テスト層 | ファイル | 検証対象 | リリースゲート |
|----------|---------|---------|---------------|
| 既存ユニットテスト | `tests/unit/test_semantic_search.bats` | alias hit、LLM fallback、エラーパスの出力文字列一致 | 4 tests, 0 failures, 0 skipped（必須） |
| E2E: cli-options | `tests/e2e/cli-options.spec.bats` | `--help`, `--llm`, unknown option, no query | before/after出力diff |
| E2E: index-parsing | `tests/e2e/index-parsing.spec.bats` | index読み込み、missing indexエラー | before/after出力diff + exit status |
| E2E: first-layer | `tests/e2e/first-layer.spec.bats` | alias/label照合 | stdout内容 + exit status |
| E2E: llm-fallback | `tests/e2e/llm-fallback.spec.bats` | mock LLM concept解決、`SEMANTIC_LLM_CMD`差替え、非ゼロexit伝播 | resources出力 + exit status |
| E2E: refactor-integrity | `tests/e2e/refactor-integrity.spec.bats` | `re.split` 1箇所、`concepts = []` 1箇所、`semantic_index_python` 存在、関数内parse不在、`bash -n` pass、既存Bats統合 | `grep -c` 静的検証 |
| E2E: performance | `tests/e2e/performance.spec.bats` | alias hit ≤ 53ms、LLM mock ≤ 109ms | 5回平均の閾値検証 |

全テストにおいて、`bash scripts/semantic_search.sh` の実行がシグナルによる異常終了（exit status 128+）でないことを最初にアサーションし、スクリプトクラッシュとロジックエラーを区別する。

### 2.9 成果物一覧

| 成果物 | パス | 変更種別 |
|--------|------|---------|
| リファクタリング対象スクリプト | `scripts/semantic_search.sh` | 変更（`semantic_index_python` 新設、2関数の本体差替え） |
| 既存ユニットテスト | `tests/unit/test_semantic_search.bats` | 変更なし |
| E2Eテスト（6ドメイン） | `tests/e2e/*.spec.bats` | 新規 |
| E2Eヘルパー: mock LLM | `tests/e2e/helpers/mock_llm.sh` | 新規 |
| E2Eヘルパー: setup | `tests/e2e/helpers/setup.bash` | 新規 |
| E2Eヘルパー: assertions | `tests/e2e/helpers/assertions.bash` | 新規 |
| E2Eヘルパー: before snapshot | `tests/e2e/helpers/before_snapshot.bash` | 新規 |
| 性能計測結果 | `docs/benchmarks/` | 新規（Step 6完了時） |

## 3. Open Questions

| ID | 質問 | 背景 | 影響範囲 | 暫定方針 |
|----|------|------|---------|---------|
| OQ-1 | `semantic_index_python` の Python 部分を外部 `.py` ファイルに分離すべきか | ADR F2 で「heredoc 内 Python が100行を超えた時点で判断」とされているが、統合後の行数は実装完了まで確定しない。before の2箇所合計は約170行（L65–L155 + L157–L233 の Python 部分）であり、共通 parse 部分の統合で削減されるものの100行前後になる可能性がある | `semantic_index_python` 関数の実装形式、シェルとの引数受け渡し方式、テストの粒度 | 初回リリースでは heredoc 内に維持し、実装完了後に行数を計測して100行超過時に別途 ADR を起票する |
| OQ-2 | 性能閾値の ±20% 許容幅と絶対閾値（53ms / 109ms）の関係 | ADR D3 では「±20%を超える劣化で原因調査」とし、受入基準 AC-17/AC-18 では「53ms以下」「109ms以下」と絶対閾値を定義している。±20% 許容なら 53×1.2=63.6ms まで許容されるが、AC-17 は53ms以下を要求しており矛盾する | 性能テストの合否判定、リリースゲート判定 | 受入基準の絶対閾値（53ms / 109ms）をリリースゲートとして採用し、ADR の ±20% は原因調査トリガーとして扱う。絶対閾値以下であれば合格、絶対閾値超過は無条件で不合格とする |
| OQ-3 | 境界値テスト（空 index、セクション0件、alias 重複、不正 Markdown）の優先度 | ADR F3 で「本 ADR の実装完了後」に追加するとされているが、`semantic_index_python` に parse ロジックが集約された結果、これらの境界値で不具合が発生するリスクが統合前より顕在化する | E2Eテストのスコープ、リリーススケジュール | 初回リリースでは既存 Bats 4テスト + E2E 6ドメインでリリースゲートを構成し、境界値テストは ADR F3 に従い実装完了後に追加する |
