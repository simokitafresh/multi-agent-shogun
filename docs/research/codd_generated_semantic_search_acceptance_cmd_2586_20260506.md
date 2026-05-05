---
codd:
  node_id: test:acceptance-criteria
  type: test
  depends_on:
  - id: req:semantic-search-refactor-requirements
    relation: derives_from
    semantic: governance
  depended_by:
  - id: design:system-design
    relation: constrained_by
    semantic: governance
  - id: plan:implementation-plan
    relation: constrained_by
    semantic: governance
  - id: test:test-strategy
    relation: derives_from
    semantic: governance
  conventions:
  - targets:
    - script:semantic_search
    reason: CLI互換性（--llm, --help, unknown option, no query, missing index）と出力互換性（既存Bats期待文字列一致）はリリースゲート。既存Bats
      4件全PASSが必須。
  modules:
  - semantic_search
---

# Acceptance Criteria

## 1. Overview

本ドキュメントは `scripts/semantic_search.sh` のリファクタリング（Python index parser一元化）に対する受入基準・失敗基準・E2Eテスト生成メタプロンプトを定義する。

対象スクリプトは289行のBash+Python heredocで構成され、セマンティックインデックス（Markdownテーブル）を読み取る処理が `first_layer_search`（L65-L155）と `render_llm_resources`（L157-L233）の2箇所に重複している。リファクタリングでは `semantic_index_python()` を新設し、`first-layer` / `render-llm-resources` の2モードに統合する。

### 対象成果物

| 成果物 | パス |
|--------|------|
| リファクタリング対象スクリプト | `scripts/semantic_search.sh` |
| 既存ユニットテスト | `tests/unit/test_semantic_search.bats` |
| セマンティックインデックス | Markdownテーブル形式（スクリプト内で参照） |

### リリースゲート制約（non-negotiable）

`script:semantic_search` を対象とし、以下がリリースブロッキングである:

- **CLI互換性**: `--llm`, `--help`, unknown option, no query, missing index の各挙動がリファクタリング前後で同一であること
- **出力互換性**: 既存Bats 4件が期待する文字列と完全一致すること
- **既存Bats全PASS**: `tests/unit/test_semantic_search.bats` の4テストが全てPASSであること（0 SKIP, 0 FAIL）

### 検証可能な振る舞いのトレーサビリティマトリクス

| ID | 検証可能な振る舞い | 根拠 | テストシナリオ |
|----|-------------------|------|---------------|
| VB-01 | `semantic_index_python()` 関数が存在する | R1 | AC-01 |
| VB-02 | `first-layer` モードでquery/alias/label照合が動作する | R1 | AC-02, AC-03 |
| VB-03 | `render-llm-resources` モードでconcept IDからresources解決が動作する | R1 | AC-04 |
| VB-04 | `first_layer_search()` がmode呼び出しのみになっている | R2 | AC-05 |
| VB-05 | `render_llm_resources()` がmode呼び出しのみになっている | R2 | AC-05 |
| VB-06 | Bash関数内に重複Markdown parserが存在しない | R2 | AC-06 |
| VB-07 | `--llm` オプションの挙動が不変 | 制約:CLI互換 | AC-07 |
| VB-08 | `--help` オプションの挙動が不変 | 制約:CLI互換 | AC-08 |
| VB-09 | unknown optionの挙動が不変 | 制約:CLI互換 | AC-09 |
| VB-10 | no queryの挙動が不変 | 制約:CLI互換 | AC-10 |
| VB-11 | missing indexの挙動が不変 | 制約:CLI互換 | AC-11 |
| VB-12 | 既存Bats 4件の期待文字列と出力が完全一致 | 制約:出力互換 | AC-12 |
| VB-13 | 既存Bats 4件が全PASS | 制約:安全性 | AC-13 |
| VB-14 | LLM command実行経路が不変 | 制約 | AC-14 |
| VB-15 | exit status伝播が不変 | 制約 | AC-15 |
| VB-16 | `re.split(r"(?m)^##\s+")` が1箇所のみ | R1:重複排除 | AC-06 |
| VB-17 | `concepts = []` が1箇所のみ | R1:重複排除 | AC-06 |
| VB-18 | `bash -n scripts/semantic_search.sh` がPASS | 実施順序4 | AC-16 |
| VB-19 | alias hitの性能がbefore基準(53ms)と同等以下 | 定量プロファイル | AC-17 |
| VB-20 | LLM fallback(mock)の性能がbefore基準(109ms)と同等以下 | 定量プロファイル | AC-18 |

未カバー振る舞い: なし。全20件がテストシナリオにマッピング済み。

## 2. Acceptance Criteria

### AC-01: `semantic_index_python()` 関数の存在

- `scripts/semantic_search.sh` 内に `semantic_index_python` という名前のBash関数が定義されていること
- `grep -c 'semantic_index_python()' scripts/semantic_search.sh` が1を返すこと

### AC-02: `first-layer` モード — alias一致

- `bash scripts/semantic_search.sh 意味検索` を実行したとき、aliasに一致するconceptのリソース情報が出力されること
- 出力文字列がリファクタリング前と完全一致すること（before snapshotとのdiff比較）
- 5回実行の平均所要時間が53ms以下であること（VB-19）

### AC-03: `first-layer` モード — label一致

- queryがlabelに一致する場合も正しくconceptが返されること
- aliasでもlabelでもない文字列の場合、一致なしの挙動（LLMフォールバックまたは該当なしメッセージ）が維持されること

### AC-04: `render-llm-resources` モード — concept ID解決

- LLM出力ファイル内の `MATCH: <concept_id>` 行からconcept IDを抽出し、対応するresourcesを出力すること
- mock LLMを使用した `env SEMANTIC_LLM_CMD="$mock" bash scripts/semantic_search.sh 品質を伸ばす輪` で正しいresources出力が得られること
- 5回実行の平均所要時間が109ms以下であること（VB-20）

### AC-05: Bash関数のI/O orchestration化

- `first_layer_search()` の関数本体が `semantic_index_python first-layer` への呼び出しを含むこと
- `render_llm_resources()` の関数本体が `semantic_index_python render-llm-resources` への呼び出しを含むこと
- 両関数内にPython heredocによるMarkdown parse処理が存在しないこと

### AC-06: 重複コードの排除

- `grep -c 're.split' scripts/semantic_search.sh` が1を返すこと（2箇所→1箇所）
- `grep -c 'concepts = \[\]' scripts/semantic_search.sh` が1を返すこと（2箇所→1箇所）
- index parseロジックは `semantic_index_python()` 内の単一のPython heredocにのみ存在すること

### AC-07: CLI互換 — `--llm` オプション

- `bash scripts/semantic_search.sh --llm <query>` でLLMモードが有効化されること
- LLMコマンドが呼び出され、その出力がresources解決に渡されること
- `SEMANTIC_LLM_CMD` 環境変数によるLLMコマンドの差替えが機能すること

### AC-08: CLI互換 — `--help` オプション

- `bash scripts/semantic_search.sh --help` がヘルプメッセージを標準出力に出力し、exit status 0で終了すること
- ヘルプメッセージの内容がリファクタリング前と完全一致すること

### AC-09: CLI互換 — unknown option

- `bash scripts/semantic_search.sh --unknown-flag` がエラーメッセージを出力し、非ゼロのexit statusで終了すること
- エラーメッセージの文字列がリファクタリング前と完全一致すること

### AC-10: CLI互換 — no query

- `bash scripts/semantic_search.sh` （引数なし）がエラーまたはヘルプを出力し、適切なexit statusで終了すること
- 挙動がリファクタリング前と完全一致すること

### AC-11: CLI互換 — missing index

- セマンティックインデックスファイルが存在しない状態で実行した場合、エラーメッセージを出力し非ゼロexit statusで終了すること
- エラーメッセージの文字列がリファクタリング前と完全一致すること

### AC-12: 出力互換 — Bats期待文字列一致

- 既存の `tests/unit/test_semantic_search.bats` 4テストケースすべてにおいて、出力がBatsファイル内の `assert_output` / `assert_line` 期待文字列と完全一致すること

### AC-13: 既存Bats全PASS（リリースゲート）

- `bats tests/unit/test_semantic_search.bats` 実行結果が:
  - 4 tests
  - 0 failures
  - 0 skipped
- これはリリースブロッキング制約であり、1件でもFAILまたはSKIPがあればリリース不可

### AC-14: LLM command実行経路の不変性

- `SEMANTIC_LLM_CMD` で指定されたコマンドがサブプロセスとして実行されること
- コマンドへの標準入力（prompt内容）がリファクタリング前と同一であること
- コマンドの標準出力がそのまま `render-llm-resources` モードに渡されること

### AC-15: exit status伝播の不変性

- LLMコマンドが非ゼロで終了した場合、`semantic_search.sh` も非ゼロで終了すること
- alias一致で正常終了した場合、exit status 0であること
- 各CLIオプション（`--help`, unknown, no query, missing index）のexit statusがリファクタリング前と同一であること

### AC-16: 構文チェック

- `bash -n scripts/semantic_search.sh` がexit status 0で完了すること（構文エラーなし）

### AC-17: 性能 — alias hit

- `bash scripts/semantic_search.sh 意味検索` の5回実行平均が53ms以下であること
- 測定はbefore計測と同一環境・同一コマンドで実施すること

### AC-18: 性能 — LLM fallback (mock)

- mock LLMを使用した `env SEMANTIC_LLM_CMD="$mock" bash scripts/semantic_search.sh 品質を伸ばす輪` の5回実行平均が109ms以下であること
- mock LLMスクリプトはbefore計測と同一内容を使用すること:

```bash
#!/usr/bin/env bash
cat >/dev/null
echo "MATCH: growth_loop"
echo "reason: mock semantic match"
```

## 3. Failure Criteria

以下のいずれか1つでも該当した場合、リファクタリングは不合格とし、マージをブロックする。

### FC-01: 既存Batsテスト失敗

`bats tests/unit/test_semantic_search.bats` の結果に1件以上のFAILUREまたはSKIPが含まれる。

### FC-02: CLI挙動の変化

`--llm`, `--help`, unknown option, no query, missing index のいずれかにおいて、リファクタリング前後でstdout/stderr出力またはexit statusが異なる。

### FC-03: 構文エラー

`bash -n scripts/semantic_search.sh` が非ゼロexit statusを返す。

### FC-04: 重複コードの残存

`re.split(r"(?m)^##\s+")` の出現箇所が2箇所以上、または `concepts = []` の出現箇所が2箇所以上残存している。

### FC-05: 関数内Markdown parser残存

`first_layer_search()` または `render_llm_resources()` の関数本体内にPython heredocによるMarkdownテーブル解析処理が残存している。

### FC-06: `semantic_index_python()` 未導入

`scripts/semantic_search.sh` 内に `semantic_index_python` 関数が定義されていない。

### FC-07: 性能劣化

alias hit 5回平均が53msを超過、またはLLM fallback(mock) 5回平均が109msを超過する。

### FC-08: LLM実行経路の断裂

`SEMANTIC_LLM_CMD` 環境変数で指定したコマンドが呼び出されない、またはその出力がresources解決に渡されない。

### FC-09: exit status伝播の断裂

LLMコマンドの非ゼロexit statusが `semantic_search.sh` のexit statusに反映されない。

## 4. E2E Test Generation Meta-Prompt

### 4.1 テスト対象アーキテクチャ

- **種別**: CLIスクリプト（Bash + embedded Python heredoc）
- **エントリポイント**: `scripts/semantic_search.sh`
- **テストランナー**: Bats (Bash Automated Testing System)
- **既存テスト**: `tests/unit/test_semantic_search.bats`（4テスト）

CLIスクリプトのため、ブラウザテストは不要。全テストはAPIインテグレーションテストに相当するCLI実行テストとして実装する。

### 4.2 テストレベル分離

| レベル | 説明 | ファイルパターン |
|--------|------|-----------------|
| CLI integration tests | `bash scripts/semantic_search.sh` をサブプロセスとして実行し、stdout/stderr/exit statusを検証 | `tests/e2e/<domain>.spec.bats` |

本プロジェクトはWebアプリケーションではないため、ブラウザテスト（`*.browser.spec.ts`）は対象外とする。CLIスクリプトの入出力検証がE2Eテストに該当する。

### 4.3 ランタイム環境

- E2Eテスト実行前にセマンティックインデックスファイルが所定パスに存在することを確認する
- mock LLMスクリプトは `tests/e2e/helpers/mock_llm.sh` に配置し、テスト間で共有する
- `bats` コマンドが `PATH` 上に存在することを前提とする
- サーバ起動は不要（CLIスクリプトであるため）

### 4.4 MECE ドメイン分解

| ドメイン | 責務 | 出力ファイルパス |
|----------|------|-----------------|
| cli-options | `--llm`, `--help`, unknown option, no query の各CLIオプション挙動 | `tests/e2e/cli-options.spec.bats` |
| index-parsing | セマンティックインデックスの読み込み・parse・missing index エラー | `tests/e2e/index-parsing.spec.bats` |
| first-layer | alias/label照合による第一層検索の入出力 | `tests/e2e/first-layer.spec.bats` |
| llm-fallback | LLMコマンド呼び出し・出力解決・exit status伝播 | `tests/e2e/llm-fallback.spec.bats` |
| refactor-integrity | 重複排除の静的検証（grep count, 関数構造） | `tests/e2e/refactor-integrity.spec.bats` |
| performance | alias hit / LLM fallback(mock) の所要時間閾値 | `tests/e2e/performance.spec.bats` |

各ドメインは排他的であり、同一のテストシナリオが複数ドメインに出現してはならない。

### 4.5 シナリオ導出ルール

受入基準（AC-01〜AC-18）から正常系シナリオを導出し、失敗基準（FC-01〜FC-09）を反転させて異常系アサーションを導出する。

#### cli-options ドメイン

| シナリオ | 種別 | 導出元 | アサーション |
|----------|------|--------|-------------|
| `--help` が使用方法を表示しexit 0 | 正常系 | AC-08 | stdout にヘルプ文字列を含む, exit status = 0 |
| `--llm` でLLMモードが有効化される | 正常系 | AC-07 | mock LLMが呼び出される |
| unknown optionでエラー終了 | 異常系 | AC-09, FC-02 | stderr にエラー文字列, exit status ≠ 0 |
| 引数なしでエラーまたはヘルプ | 異常系 | AC-10, FC-02 | 適切な出力, exit status がbefore同一 |

#### index-parsing ドメイン

| シナリオ | 種別 | 導出元 | アサーション |
|----------|------|--------|-------------|
| インデックスファイル不在でエラー | 異常系 | AC-11, FC-02 | stderr にエラー文字列, exit status ≠ 0 |
| インデックスファイル存在時に正常parse | 正常系 | AC-01, VB-02 | `semantic_index_python` が呼び出されエラーなし |

#### first-layer ドメイン

| シナリオ | 種別 | 導出元 | アサーション |
|----------|------|--------|-------------|
| alias一致でresources出力 | 正常系 | AC-02 | stdout にリソース情報, exit status = 0 |
| label一致でresources出力 | 正常系 | AC-03 | stdout にリソース情報, exit status = 0 |
| 一致なしでフォールバック | 正常系 | AC-03 | LLMフォールバックまたは該当なしメッセージ |

#### llm-fallback ドメイン

| シナリオ | 種別 | 導出元 | アサーション |
|----------|------|--------|-------------|
| mock LLMによるconcept解決 | 正常系 | AC-04 | stdout に解決済みresources |
| `SEMANTIC_LLM_CMD` 差替え | 正常系 | AC-07, AC-14 | 指定コマンドが実行される |
| LLMコマンド非ゼロ終了時の伝播 | 異常系 | AC-15, FC-09 | exit status ≠ 0 |

#### refactor-integrity ドメイン

| シナリオ | 種別 | 導出元 | アサーション |
|----------|------|--------|-------------|
| `re.split` 出現が1箇所 | 正常系 | AC-06, FC-04 | `grep -c 're.split' scripts/semantic_search.sh` = 1 |
| `concepts = []` 出現が1箇所 | 正常系 | AC-06, FC-04 | `grep -c 'concepts = \[\]' scripts/semantic_search.sh` = 1 |
| `semantic_index_python` 関数存在 | 正常系 | AC-01, FC-06 | `grep -c 'semantic_index_python()' scripts/semantic_search.sh` = 1 |
| `first_layer_search` 内にparse処理なし | 正常系 | AC-05, FC-05 | 関数内にPython heredocのparse処理が不在 |
| `render_llm_resources` 内にparse処理なし | 正常系 | AC-05, FC-05 | 関数内にPython heredocのparse処理が不在 |
| `bash -n` 構文チェック通過 | 正常系 | AC-16, FC-03 | exit status = 0 |

#### performance ドメイン

| シナリオ | 種別 | 導出元 | アサーション |
|----------|------|--------|-------------|
| alias hit 5回平均 ≤ 53ms | 正常系 | AC-17, FC-07 | 計測値 ≤ 53 |
| LLM fallback(mock) 5回平均 ≤ 109ms | 正常系 | AC-18, FC-07 | 計測値 ≤ 109 |

### 4.6 アーキテクチャ適応ルール

テスト生成時に `scripts/semantic_search.sh` を実際に読み取り、以下を検出すること:

- 定義されているBash関数名の一覧（`grep -E '^\w+\(\)' scripts/semantic_search.sh`）
- CLIオプションのcase/getopts分岐
- `semantic_index_python` 関数のモード引数

未実装のモードまたは関数が検出された場合、対応するテストを `bats_skip "not yet implemented"` ではなく、Bats の `# @test.fixme` アノテーションでマークすること。

### 4.7 品質ゲート

以下の全条件を満たさない限り、テストスイートは不合格とする:

| 条件 | 閾値 |
|------|------|
| 全テスト PASS | 100% |
| SKIP テスト数 | 0 |
| 受入基準カバレッジ | AC-01〜AC-18 の全18件にテストシナリオが存在 |
| 既存Bats互換 | `tests/unit/test_semantic_search.bats` 4件全PASS（リリースブロッキング） |
| 失敗基準の反転アサーション | FC-01〜FC-09 の全9件に対応するアサーションが存在 |

### 4.8 共有ヘルパー

`tests/e2e/helpers/` ディレクトリに以下のヘルパーを配置し、各specファイルから `load` で読み込むこと:

| ファイル | 責務 |
|----------|------|
| `tests/e2e/helpers/mock_llm.sh` | mock LLMスクリプト本体（`MATCH: growth_loop` + `reason: mock semantic match` を出力） |
| `tests/e2e/helpers/setup.bash` | テスト共通のsetup（tmpdir作成、mock LLM配置、`SEMANTIC_LLM_CMD` 設定） |
| `tests/e2e/helpers/assertions.bash` | 共通アサーション（exit status検証、出力文字列比較、性能計測マクロ） |
| `tests/e2e/helpers/before_snapshot.bash` | リファクタリング前の出力スナップショットを保持し、before/after差分比較に使用 |

### 4.9 生成マーカー

全生成ファイルの先頭に以下のヘッダーを付与すること:

```bash
# @generated-from: docs/tests/acceptance-criteria.md
# @generated-by: codd propagate
```

手動で追加されたテスト（`# @manual` コメント付き）は再生成時に保持し、上書きしないこと。

### 4.10 サーバヘルスベースライン

CLIスクリプトのためHTTPサーバは存在しないが、同等のベースラインとして以下を適用する:

- 全テストシナリオにおいて、`bash scripts/semantic_search.sh` の実行がシグナルによる異常終了（exit status 128+）でないことを最初にアサーションすること
- exit statusの検証は、まずシグナル異常終了の不在を確認し、その後にビジネスロジック上の期待exit statusを検証する2段階とする
- これにより、スクリプトのクラッシュ（segfault, SIGPIPE等）とロジックエラー（不正な引数等）を区別できる

### 4.11 リリースブロッキング制約の反映

本メタプロンプトにより生成されるE2Eテストは、以下のリリースゲート制約を明示的に検証する:

| 制約 | 検証方法 | テストドメイン |
|------|----------|---------------|
| CLI互換性（`--llm`） | before/after出力diff | cli-options |
| CLI互換性（`--help`） | before/after出力diff | cli-options |
| CLI互換性（unknown option） | before/after出力diff + exit status比較 | cli-options |
| CLI互換性（no query） | before/after出力diff + exit status比較 | cli-options |
| CLI互換性（missing index） | before/after出力diff + exit status比較 | index-parsing |
| 出力互換性（Bats期待文字列一致） | 既存Bats 4件実行 | 別途 `bats tests/unit/test_semantic_search.bats` をCIパイプラインで実行 |
| 既存Bats 4件全PASS | `bats tests/unit/test_semantic_search.bats` の終了コード = 0, "4 tests, 0 failures" を含む | refactor-integrity ドメインに統合テストとして追加 |
