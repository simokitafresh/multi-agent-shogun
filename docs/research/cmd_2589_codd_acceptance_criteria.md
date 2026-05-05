---
codd:
  node_id: test:acceptance-criteria
  type: test
  depends_on:
  - id: req:skill-gate-feedback-refactor-requirements
    relation: derives_from
    semantic: governance
  depended_by:
  - id: design:system-design
    relation: constrained_by
    semantic: governance
  - id: test:test-strategy
    relation: derives_from
    semantic: governance
  - id: operations:performance-verification
    relation: derives_from
    semantic: governance
  conventions:
  - targets:
    - script:skill_gate_feedback
    - script:skill_execution_log
    reason: bats tests/unit/test_skill_feedback_loop.bats 12件全PASSがリリース必須条件
  - targets:
    - script:skill_gate_feedback
    reason: API引数（--gate/--result/--reason/--executor/--source/--skill）変更禁止
  - targets:
    - function:has_duplicate_caution
    - function:has_duplicate_failure
    - function:_write_skill_log
    reason: 凍結ロジック（has_duplicate_caution文字列マッチ・has_duplicate_failureエントリ比較・tests/パス除外・flock排他制御）は変更禁止
  - targets:
    - function:_write_skill_log
    - function:load_skill_log
    reason: yaml.safe_dump使用禁止（YAML上書き事故防止）
  modules:
  - skill_gate_feedback
  - skill_execution_log
---

# 受入基準

## 1. Overview

本ドキュメントは `scripts/skill_gate_feedback.sh` リファクタリング（R1: `subprocess.run` インライン化、R2: `load_skill_log()` キャッシュ化）の受入基準を定義する。対象スクリプトは gate FAIL 時にスキルへ注意ポイントを追記し、実行ログを `skill_execution_log.yaml` に記録する 216 行の bash+Python スクリプトである。

### 対象スコープ

| リファクタリング | 対象関数/スクリプト | 期待効果 |
|-----------------|-------------------|---------|
| R1: subprocess.run インライン化 | `_write_skill_log()` 新設、`skill_execution_log.sh` 呼出し除去 | 220ms → ~5ms（-98%） |
| R2: load_skill_log() キャッシュ化 | `load_skill_log()` にモジュールレベルキャッシュ追加 | 71ms 節約（2回呼出し時） |

### 非交渉制約（リリースブロッキング）

| # | 制約 | 対象 | 遵守方法 |
|---|------|------|---------|
| C1 | `bats tests/unit/test_skill_feedback_loop.bats` 12 件全 PASS | `script:skill_gate_feedback`, `script:skill_execution_log` | CI で全テスト実行、1 件でも FAIL ならリリース不可 |
| C2 | API 引数変更禁止 | `script:skill_gate_feedback` | `--gate`/`--result`/`--reason`/`--executor`/`--source`/`--skill` の引数名・型・順序を維持 |
| C3 | 凍結ロジック変更禁止 | `has_duplicate_caution`, `has_duplicate_failure`, `_write_skill_log` | 文字列マッチ、エントリ比較、`tests/` パス除外、`flock` 排他制御のロジックを一切変更しない |
| C4 | `yaml.safe_dump` 使用禁止 | `_write_skill_log`, `load_skill_log` | YAML 出力は手動文字列構築のみ。`yaml.safe_dump` / `yaml.dump` の import・呼出しが存在すれば即 FAIL |

### 検証可能な振る舞い一覧（設計→テスト追跡性）

以下は依存設計書から抽出したすべての検証可能な振る舞いと、対応するテストシナリオの対応表である。

| ID | 検証可能な振る舞い | 対応テストシナリオ |
|----|-------------------|------------------|
| VB-01 | `_write_skill_log()` が `tests/` パスを含む source を除外する | AC-R1-04 |
| VB-02 | `_write_skill_log()` がログディレクトリを自動作成する | AC-R1-05 |
| VB-03 | `_write_skill_log()` が `flock` で排他制御する | AC-R1-06 |
| VB-04 | 空または未作成のログファイルに `executions:\n` ヘッダを書き込む | AC-R1-07 |
| VB-05 | YAML エントリを正しいフィールド順で追記する（ts, skill, executor, result, stumbling_points） | AC-R1-01 |
| VB-06 | gate/source/skill_path が存在する場合のみ追記する | AC-R1-02 |
| VB-07 | YAML 文字列エスケープ（バックスラッシュ、ダブルクォート、改行）が正しい | AC-R1-03 |
| VB-08 | タイムスタンプが ISO 8601 + タイムゾーン形式（`%Y-%m-%dT%H:%M:%S%z`）である | AC-R1-08 |
| VB-09 | `flock` のロックが書込み後に解放される | AC-R1-06 |
| VB-10 | `load_skill_log()` 初回呼出しでファイルからロードする | AC-R2-01 |
| VB-11 | `load_skill_log()` 2 回目呼出しでキャッシュを返す | AC-R2-02 |
| VB-12 | キャッシュがプロセススコープ内のみ有効である | AC-R2-03 |
| VB-13 | `has_duplicate_caution()` の文字列マッチングロジックが不変である | AC-FROZEN-01 |
| VB-14 | `has_duplicate_failure()` のエントリ比較ロジックが不変である | AC-FROZEN-02 |
| VB-15 | CLI 引数 `--gate`/`--result`/`--reason`/`--executor`/`--source`/`--skill` が変更されていない | AC-API-01 |
| VB-16 | `skill_execution_log.sh` が削除されていない | AC-API-02 |
| VB-17 | `yaml.safe_dump` / `yaml.dump` が使用されていない | AC-YAML-01 |
| VB-18 | subprocess.run インライン化後の単体実行時間が 220ms 以下（目標 ~5ms） | AC-PERF-01 |
| VB-19 | load_skill_log() キャッシュ化後の 2 回目呼出しが 5ms 以下 | AC-PERF-02 |
| VB-20 | FAIL ケースで gate FAIL 時にスキルへ注意ポイントが追記される | AC-R1-09 |
| VB-21 | PASS ケースで正常に実行ログが記録される | AC-R1-10 |
| VB-22 | SKIP ケース（--skill なし）で正常に動作する | AC-R1-11 |
| VB-23 | `_write_skill_log()` の出力が `skill_execution_log.sh` の出力と完全互換である | AC-R1-12 |
| VB-24 | explicit_skill=None 時に `latest_fail_entry()` → `load_skill_log()` → `has_duplicate_failure()` → `load_skill_log()` の呼出しチェーンが正しく動作する | AC-R2-04 |
| VB-25 | explicit_skill 指定時に `load_skill_log()` が 1 回のみ呼ばれる | AC-R2-05 |

## 2. Acceptance Criteria

### R1: subprocess.run インライン化

#### AC-R1-01: YAML エントリ構造の正確性

`_write_skill_log()` が生成する YAML エントリは以下のフィールドを正確な順序で含むこと:

```yaml
- ts: "2026-05-06T12:00:00+0900"
  skill: "skill_name"
  executor: "executor_name"
  result: "FAIL"
  stumbling_points: "reason text"
  gate: "gate_name"        # 存在する場合のみ
  source: "path/to/source" # 存在する場合のみ
  skill_path: "path/skill" # 存在する場合のみ
```

**判定**: 生成された YAML をパースし、フィールド名・順序・値が期待通りであること。

#### AC-R1-02: オプショナルフィールドの条件付き出力

- `gate` が空文字列または未指定の場合、`gate:` 行を出力しないこと。
- `source` が空文字列または未指定の場合、`source:` 行を出力しないこと。
- `skill_path_str` が空文字列または未指定の場合、`skill_path:` 行を出力しないこと。
- 各フィールドが非空の場合は必ず出力すること。

**判定**: gate/source/skill_path の有無の全組み合わせ（8パターン）で出力を検証。

#### AC-R1-03: YAML 文字列エスケープ

以下の特殊文字を含む値が正しくエスケープされること:

| 入力文字 | エスケープ後 |
|---------|------------|
| `\` (バックスラッシュ) | `\\` |
| `"` (ダブルクォート) | `\"` |
| 改行 (`\n`) | `\\n` |

**判定**: 各特殊文字を含む skill 名・reason を入力し、出力 YAML が正しくパースできること。

#### AC-R1-04: tests/ パス除外（凍結ロジック）

`TESTS_PATH_RE = re.compile(r'(?:^|/)tests/')` によるパターンマッチで以下を判定:

| source パス | 動作 |
|------------|------|
| `tests/unit/test_foo.bats` | 除外（書込みスキップ） |
| `path/to/tests/integration/bar.sh` | 除外（書込みスキップ） |
| `scripts/run_tests_helper.sh` | 書込み実行（`tests/` ディレクトリではない） |
| `src/main.py` | 書込み実行 |

**判定**: 各パターンで `_write_skill_log()` 呼出し後にログファイルへの書込み有無を確認。

#### AC-R1-05: ログディレクトリ自動作成

ログファイルの親ディレクトリが存在しない場合、`mkdir(parents=True, exist_ok=True)` により自動作成されること。

**判定**: 存在しないディレクトリパスを指定し、関数実行後にディレクトリとファイルの両方が存在すること。

#### AC-R1-06: flock 排他制御（凍結ロジック）

- `fcntl.flock(lock_fh, fcntl.LOCK_EX)` でロックファイル（`{log_path}.lock`）を排他ロックすること。
- 書込み完了後に `fcntl.flock(lock_fh, fcntl.LOCK_UN)` でロックを解放すること。
- 例外発生時も `finally` ブロックでロック解放されること。

**判定**: 並行プロセスから同時書込みを実行し、ログファイルが破損しないこと。ロックファイルのパスが `{log_path}.lock` であること。

#### AC-R1-07: 空ファイル初期化

- ログファイルが存在しない場合、`executions:\n` ヘッダを書き込んでからエントリを追記すること。
- ログファイルが存在するがサイズ 0 の場合も同様にヘッダを書き込むこと。
- ログファイルが既に内容を持つ場合はヘッダを追記しないこと。

**判定**: 3 パターン（未作成・空ファイル・既存ファイル）で出力を検証。

#### AC-R1-08: タイムスタンプ形式

`datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")` で生成されるタイムスタンプが ISO 8601 + タイムゾーンオフセット形式であること。

**判定**: 出力エントリの `ts` フィールドが正規表現 `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{4}$` にマッチすること。

#### AC-R1-09: FAIL ケースの注意ポイント追記

gate 結果が FAIL の場合、対象スキルファイルに注意ポイント（stumbling_points）が追記されること。

**判定**: FAIL ケースで `--skill` 指定実行後、スキルファイルの内容に注意ポイントが含まれること。

#### AC-R1-10: PASS ケースのログ記録

gate 結果が PASS の場合、実行ログは記録されるがスキルファイルへの注意ポイント追記は行われないこと。

**判定**: PASS ケースで `--skill` 指定実行後、ログに PASS エントリが存在し、スキルファイルが変更されていないこと。

#### AC-R1-11: SKIP ケース（--skill なし）

`--skill` が未指定の場合、スキル関連の処理をスキップして正常終了すること。

**判定**: `--skill` なしで実行し、exit code 0 で終了すること。

#### AC-R1-12: skill_execution_log.sh との出力互換性

`_write_skill_log()` が生成する YAML エントリと `skill_execution_log.sh` が生成する YAML エントリが同一形式であること。

**判定**: 同一入力で両方を実行し、フィールド名・値・エスケープ・フォーマットが一致すること（タイムスタンプの秒差は許容）。

### R2: load_skill_log() キャッシュ化

#### AC-R2-01: 初回呼出しでファイルロード

`_SKILL_LOG_CACHE = None` の状態で `load_skill_log()` を呼出すと、`skill_execution_log.yaml` からデータをロードし、キャッシュに格納すること。

**判定**: 初回呼出し後に `_SKILL_LOG_CACHE` が `None` でないこと。返却値がファイル内容と一致すること。

#### AC-R2-02: 2 回目呼出しでキャッシュ返却

同一プロセス内で `load_skill_log()` を 2 回呼出した場合、2 回目はファイル I/O を行わずキャッシュを返却すること。

**判定**: 1 回目呼出し後にファイル内容を変更し、2 回目呼出しが変更前の内容を返すこと。2 回目の実行時間が 5ms 以下であること。

#### AC-R2-03: キャッシュのプロセススコープ限定

キャッシュはプロセス内のモジュールレベル変数に格納され、異なるプロセスからはアクセスできないこと。

**判定**: 2 つの別プロセスから `load_skill_log()` を呼出し、それぞれ独立にファイルからロードされること。

#### AC-R2-04: explicit_skill=None 時の呼出しチェーン

`explicit_skill=None` の場合、`latest_fail_entry()` → `load_skill_log()`（1 回目）→ `has_duplicate_failure()` → `load_skill_log()`（2 回目・キャッシュ）の順で実行され、2 回目はキャッシュから取得されること。

**判定**: `explicit_skill=None` で FAIL ケースを実行し、ファイル I/O が 1 回のみであること（キャッシュヒット）。

#### AC-R2-05: explicit_skill 指定時の呼出し回数

`explicit_skill` が指定されている場合、`load_skill_log()` は 1 回のみ呼ばれること。

**判定**: `explicit_skill` 指定で FAIL ケースを実行し、`load_skill_log()` の呼出し回数が 1 であること。

### 凍結ロジック検証

#### AC-FROZEN-01: has_duplicate_caution() 不変性

`has_duplicate_caution()` の文字列マッチングロジックがリファクタリング前後で同一の結果を返すこと。

**判定**: 重複注意ポイントの検出パターン（完全一致・部分一致・不一致）で前後の結果を比較。

#### AC-FROZEN-02: has_duplicate_failure() 不変性

`has_duplicate_failure()` のエントリ比較ロジックがリファクタリング前後で同一の結果を返すこと。

**判定**: 重複エントリ・非重複エントリ・空ログの各パターンで前後の結果を比較。

### API 互換性

#### AC-API-01: CLI 引数の維持

`skill_gate_feedback.sh` が以下の引数をすべて受け付けること:

| 引数 | 必須/任意 |
|------|----------|
| `--gate` | 必須 |
| `--result` | 必須 |
| `--reason` | 必須 |
| `--executor` | 必須 |
| `--source` | 任意 |
| `--skill` | 任意 |

**判定**: 各引数の有無パターンでスクリプトを実行し、exit code とログ出力を検証。

#### AC-API-02: skill_execution_log.sh 存続

`skill_execution_log.sh` がリファクタリング後も削除されずに存在し、単独で動作可能であること。

**判定**: `skill_execution_log.sh` の存在確認と直接呼出しによる動作確認。

### YAML 安全性

#### AC-YAML-01: yaml.safe_dump / yaml.dump 不使用

`skill_gate_feedback.sh` 内の Python コード（heredoc 含む）に `yaml.safe_dump` または `yaml.dump` の呼出しが存在しないこと。

**判定**: `grep -n 'yaml\.\(safe_\)\?dump' scripts/skill_gate_feedback.sh` の出力が空であること。

### パフォーマンス

#### AC-PERF-01: R1 実行時間

`_write_skill_log()` による YAML 書込みの単体実行時間が 30ms 以下であること（目標 ~5ms、上限 30ms は安全マージン）。

**判定**: 10 回計測の平均値が 30ms 以下であること。Before 値（220ms）と比較して 85% 以上の改善。

#### AC-PERF-02: R2 キャッシュヒット時間

`load_skill_log()` の 2 回目呼出し（キャッシュヒット）の実行時間が 5ms 以下であること。

**判定**: 2 回目呼出しの 10 回計測平均が 5ms 以下であること。Before 値（71ms）と比較して 90% 以上の改善。

### bats テストスイート

#### AC-BATS-01: 全 12 件 PASS

`bats tests/unit/test_skill_feedback_loop.bats` の全 12 テストケースが PASS すること。1 件でも FAIL または SKIP がある場合はリリースブロッキングとする。

**判定**: bats 実行の exit code が 0 かつ出力に `12 tests, 0 failures` が含まれること。

## 3. Failure Criteria

以下のいずれか 1 つでも該当する場合、リファクタリングは不合格とし、マージを禁止する。

### FC-01: bats テスト FAIL

`bats tests/unit/test_skill_feedback_loop.bats` で 1 件以上の FAIL が発生する。

**検出方法**: bats 実行の exit code が非 0。

### FC-02: API 引数の変更

`--gate`/`--result`/`--reason`/`--executor`/`--source`/`--skill` のいずれかの引数名が変更、削除、またはセマンティクスが変更されている。

**検出方法**: 引数パース部分の diff レビュー + 既存テストによる回帰検証。

### FC-03: 凍結ロジックの変更

以下のいずれかが検出される:

- `has_duplicate_caution()` の文字列マッチングアルゴリズムの変更
- `has_duplicate_failure()` のエントリ比較アルゴリズムの変更
- `TESTS_PATH_RE` のパターンまたは `tests/` パス除外ロジックの変更
- `flock` による排他制御フロー（LOCK_EX → 書込み → LOCK_UN）の変更

**検出方法**: 凍結対象関数の diff が空であること（`_write_skill_log` 内の `tests/` 除外ロジックと flock ロジックは設計書のパターンと同一であること）。

### FC-04: yaml.safe_dump / yaml.dump の使用

`skill_gate_feedback.sh` 内（heredoc 含む）に `yaml.safe_dump` または `yaml.dump` の呼出しまたは import が存在する。

**検出方法**: `grep -Pn 'yaml\.(safe_)?dump' scripts/skill_gate_feedback.sh` が 1 行以上出力する。

### FC-05: skill_execution_log.sh の削除

`scripts/skill_execution_log.sh` がリポジトリから削除されている。

**検出方法**: `test -f scripts/skill_execution_log.sh` が false を返す。

### FC-06: YAML 出力形式の非互換

`_write_skill_log()` の出力と `skill_execution_log.sh` の出力のフィールド名、値の型、エスケープ方式に差異がある。

**検出方法**: 同一入力で両方を実行し、出力を正規化比較。

### FC-07: パフォーマンス劣化

リファクタリング後の実行時間がリファクタリング前より悪化している（R1: 220ms 以上、R2: 2 回目が 71ms 以上）。

**検出方法**: 計測スクリプトによる before/after 比較。

### FC-08: flock ロック未解放

例外パス（書込みエラー等）で `fcntl.flock(lock_fh, fcntl.LOCK_UN)` が呼ばれずロックが残留する。

**検出方法**: `try/finally` 構造の静的検査 + 書込みエラー注入テスト。

### FC-09: ログファイル破損

並行書込みテストでログファイルの YAML 構造が壊れる（パースエラー発生）。

**検出方法**: 並行プロセス 5 個から同時書込みを実行し、結果ファイルを `yaml.safe_load` でパース。

## 4. E2E Test Generation Meta-Prompt

### 目的

本セクションは `codd propagate` がE2E テストファイルを自動生成するための機械可読な指示書である。

### プロジェクト種別

本プロジェクトはCLI/シェルスクリプトプロジェクトである。Web アプリケーションではないため、ブラウザテストは対象外とする。E2E テストは CLI 統合テスト（bats）と Python ユニット/統合テストの 2 レベルに分割する。

### テストレベル分離

| レベル | ツール | テスト対象 | ファイル命名規則 |
|--------|--------|-----------|----------------|
| CLI 統合テスト | bats | シェルスクリプトの引数・exit code・stdout/stderr・ファイル出力 | `tests/e2e/<domain>.bats` |
| Python 統合テスト | pytest | Python heredoc 内関数の単体動作・キャッシュ・排他制御 | `tests/e2e/<domain>.pytest.py` |

### サーバ起動は不要

CLI ツールのテストのため、アプリケーションサーバの起動は不要。各テストケースが直接スクリプトを呼出す。CI 環境では `bats` と `pytest` が利用可能であること。

### MECE ドメイン分割

| ドメイン | 所管範囲 | 出力ファイル |
|---------|---------|-------------|
| `write-log` | `_write_skill_log()` の YAML 書込み・エスケープ・パス除外・flock | `tests/e2e/write-log.bats`, `tests/e2e/write-log.pytest.py` |
| `cache` | `load_skill_log()` のキャッシュ動作・プロセススコープ | `tests/e2e/cache.pytest.py` |
| `frozen-logic` | `has_duplicate_caution` / `has_duplicate_failure` の不変性検証 | `tests/e2e/frozen-logic.pytest.py` |
| `api-compat` | CLI 引数パース・exit code・`skill_execution_log.sh` 存続 | `tests/e2e/api-compat.bats` |
| `yaml-safety` | `yaml.safe_dump` / `yaml.dump` 不使用の静的検査 | `tests/e2e/yaml-safety.bats` |
| `performance` | R1/R2 の実行時間計測・閾値チェック | `tests/e2e/performance.pytest.py` |

### 共有ヘルパー

`tests/e2e/helpers/` ディレクトリに以下を配置し、各 spec ファイルから共通利用する:

| ファイル | 用途 |
|---------|------|
| `tests/e2e/helpers/setup_test_env.bash` | テスト用一時ディレクトリ・ダミースキルファイル・ダミーログファイルの作成と cleanup |
| `tests/e2e/helpers/yaml_assertions.bash` | YAML パース・フィールド値取得・フィールド存在チェックの bats ヘルパー |
| `tests/e2e/helpers/conftest.py` | pytest 用フィクスチャ（一時ディレクトリ・ダミーログ・`_SKILL_LOG_CACHE` リセット） |
| `tests/e2e/helpers/timing.py` | 実行時間計測ユーティリティ（平均・中央値・閾値判定） |

### シナリオ導出ルール

1. **受入基準からの正方向テスト**: 各 AC-* に対して少なくとも 1 つの PASS シナリオを生成する。
2. **失敗基準からの逆方向テスト**: 各 FC-* を反転させ、「その状態が存在しないこと」をアサートする。
3. **境界値テスト**: 空文字列、特殊文字、空ファイル、巨大ファイル（195 エントリ以上）のパターンを含める。

### ドメイン別シナリオ

#### write-log ドメイン

```
# CLI 統合テスト (tests/e2e/write-log.bats)
- FAIL ケースで _write_skill_log() が YAML エントリを追記する (AC-R1-01)
- PASS ケースでログ記録のみ・スキルファイル変更なし (AC-R1-10)
- SKIP ケース(--skill なし)で正常終了 (AC-R1-11)
- gate/source/skill_path の有無 8 パターン (AC-R1-02)
- 特殊文字エスケープ: バックスラッシュ・ダブルクォート・改行 (AC-R1-03)
- tests/ パス除外: tests/unit/*, path/to/tests/*, scripts/run_tests_helper.sh (AC-R1-04)
- ログディレクトリ未存在時の自動作成 (AC-R1-05)
- 空ファイル/未作成ファイルで executions: ヘッダ書込み (AC-R1-07)
- タイムスタンプ形式 ISO 8601+TZ (AC-R1-08)
- skill_execution_log.sh との出力互換 (AC-R1-12)

# Python 統合テスト (tests/e2e/write-log.pytest.py)
- _write_skill_log() 直接呼出し: フィールド構造検証 (AC-R1-01)
- flock LOCK_EX → 書込み → LOCK_UN のフロー (AC-R1-06)
- 並行 5 プロセス同時書込み: YAML 破損なし (FC-09 逆方向)
- 例外時の flock 解放 (FC-08 逆方向)
```

#### cache ドメイン

```
# Python 統合テスト (tests/e2e/cache.pytest.py)
- 初回呼出しでファイルロード成功 (AC-R2-01)
- 2 回目呼出しでキャッシュ返却・ファイル変更を反映しない (AC-R2-02)
- 別プロセスではキャッシュ共有なし (AC-R2-03)
- explicit_skill=None 時の 2 回ロード→キャッシュヒット (AC-R2-04)
- explicit_skill 指定時の 1 回ロード (AC-R2-05)
- _SKILL_LOG_CACHE リセット後の再ロード
```

#### frozen-logic ドメイン

```
# Python 統合テスト (tests/e2e/frozen-logic.pytest.py)
- has_duplicate_caution(): 完全一致→True (AC-FROZEN-01)
- has_duplicate_caution(): 部分一致→False (AC-FROZEN-01)
- has_duplicate_caution(): 空入力→False (AC-FROZEN-01)
- has_duplicate_failure(): 同一エントリ→True (AC-FROZEN-02)
- has_duplicate_failure(): 異なるエントリ→False (AC-FROZEN-02)
- has_duplicate_failure(): 空ログ→False (AC-FROZEN-02)
```

#### api-compat ドメイン

```
# CLI 統合テスト (tests/e2e/api-compat.bats)
- 全必須引数指定で exit 0 (AC-API-01)
- --gate 欠落で適切なエラー (AC-API-01)
- --result 欠落で適切なエラー (AC-API-01)
- --reason 欠落で適切なエラー (AC-API-01)
- --executor 欠落で適切なエラー (AC-API-01)
- --source/--skill 任意引数の省略で正常動作 (AC-API-01)
- skill_execution_log.sh の存在確認 (AC-API-02)
- skill_execution_log.sh の直接実行で正常動作 (AC-API-02)
```

#### yaml-safety ドメイン

```
# CLI 統合テスト (tests/e2e/yaml-safety.bats)
- skill_gate_feedback.sh 内に yaml.safe_dump が存在しない (AC-YAML-01, FC-04 逆方向)
- skill_gate_feedback.sh 内に yaml.dump が存在しない (AC-YAML-01, FC-04 逆方向)
- Python heredoc 内に yaml モジュールの dump 系関数 import がない (AC-YAML-01)
```

#### performance ドメイン

```
# Python 統合テスト (tests/e2e/performance.pytest.py)
- _write_skill_log() 10 回平均 ≤ 30ms (AC-PERF-01)
- load_skill_log() 2 回目 10 回平均 ≤ 5ms (AC-PERF-02)
- FAIL ケース全体の実行時間 ≤ 100ms (before: 220ms)
- PASS ケース全体の実行時間 ≤ 100ms (before: 224ms)
```

### アーキテクチャ適応ルール

テスト生成時に以下の手順でプロジェクト構造をスキャンすること:

1. `scripts/skill_gate_feedback.sh` のパスと引数パース部分を解析し、テスト対象の引数リストを動的取得する。
2. `scripts/skill_execution_log.sh` の存在とパスを確認する。
3. Python heredoc 内の関数定義（`_write_skill_log`, `load_skill_log`, `has_duplicate_caution`, `has_duplicate_failure`）を検出する。
4. 未実装または検出できないエンドポイント/関数は `test.fixme()` でマークし、スキップしない。

### 品質ゲート

リリース可否判定の基準:

| 基準 | 閾値 |
|------|------|
| 全テスト結果 | ALL PASS |
| SKIP テスト数 | 0 |
| 受入基準カバレッジ | AC-* 全項目に対応するテストが存在 |
| 失敗基準カバレッジ | FC-* 全項目に対応する逆方向テストが存在 |
| bats tests/unit/test_skill_feedback_loop.bats | 12 件全 PASS（リリースブロッキング） |
| yaml.safe_dump / yaml.dump 不使用 | grep 結果 0 行（リリースブロッキング） |
| API 引数互換 | --gate/--result/--reason/--executor/--source/--skill 全受付（リリースブロッキング） |
| 凍結ロジック不変 | has_duplicate_caution / has_duplicate_failure / tests/ 除外 / flock のロジック差分なし（リリースブロッキング） |

### 出力ファイルマッピング

| ドメイン | CLI 統合テスト | Python 統合テスト |
|---------|--------------|-----------------|
| write-log | `tests/e2e/write-log.bats` | `tests/e2e/write-log.pytest.py` |
| cache | — | `tests/e2e/cache.pytest.py` |
| frozen-logic | — | `tests/e2e/frozen-logic.pytest.py` |
| api-compat | `tests/e2e/api-compat.bats` | — |
| yaml-safety | `tests/e2e/yaml-safety.bats` | — |
| performance | — | `tests/e2e/performance.pytest.py` |
| helpers | `tests/e2e/helpers/setup_test_env.bash` | `tests/e2e/helpers/conftest.py` |
| helpers | `tests/e2e/helpers/yaml_assertions.bash` | `tests/e2e/helpers/timing.py` |

### 生成マーカー

すべての自動生成ファイルには以下のヘッダを含めること:

```bash
# bats ファイルの場合
# @generated-from: docs/tests/acceptance-criteria.md
# @generated-by: codd propagate
```

```python
# pytest ファイルの場合
# @generated-from: docs/tests/acceptance-criteria.md
# @generated-by: codd propagate
```

`# @manual` マーカーが付与されたテストケースは再生成時に保持し、上書きしないこと。

### 非交渉制約の反映確認

| 制約 | テストでの反映箇所 |
|------|------------------|
| C1: bats 12 件全 PASS | 品質ゲートのリリースブロッキング条件 + api-compat ドメインのテスト前提 |
| C2: API 引数変更禁止 | api-compat ドメインの全引数パターンテスト |
| C3: 凍結ロジック変更禁止 | frozen-logic ドメインの不変性テスト + write-log ドメインの tests/ 除外・flock テスト |
| C4: yaml.safe_dump 使用禁止 | yaml-safety ドメインの静的検査テスト |
