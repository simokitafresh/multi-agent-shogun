---
codd:
  node_id: design:system-design
  type: design
  depends_on:
  - id: test:acceptance-criteria
    relation: constrained_by
    semantic: governance
  - id: governance:adr-refactoring-approach
    relation: constrained_by
    semantic: governance
  depended_by:
  - id: design:call-flow-sequences
    relation: depends_on
    semantic: technical
  - id: design:module-boundary-and-concurrency
    relation: depends_on
    semantic: technical
  conventions:
  - targets:
    - script:skill_gate_feedback
    - function:_write_skill_log
    reason: API互換（CLI引数凍結）・tests/パス除外ルール凍結・flock排他制御必須
  - targets:
    - script:skill_execution_log
    reason: skill_execution_log.sh削除禁止・既存外部インターフェース維持必須
  - targets:
    - function:_write_skill_log
    - function:load_skill_log
    reason: yaml.safe_dump使用禁止・YAML追記はテキスト連結方式で実装すること
  modules:
  - skill_gate_feedback
  - skill_execution_log
---

# システム設計

## 1. Overview

本設計書は `scripts/skill_gate_feedback.sh`（216 行の bash+Python スクリプト）に対する 2 つのリファクタリング（R1: `subprocess.run` インライン化、R2: `load_skill_log()` キャッシュ化）のシステム設計を定義する。対象スクリプトは gate FAIL 時にスキルファイルへ注意ポイント（stumbling_points）を追記し、実行ログを `skill_execution_log.yaml` に記録する。

### 1.1 リファクタリング対象と期待効果

| ID | リファクタリング | 対象関数/スクリプト | Before | After（目標） | 削減率 |
|----|-----------------|-------------------|--------|---------------|--------|
| R1 | `subprocess.run` インライン化 | `_write_skill_log()` 新設、`skill_execution_log.sh` 呼出し除去 | 220ms/呼出し | ~5ms（上限 30ms） | 98% |
| R2 | `load_skill_log()` キャッシュ化 | `load_skill_log()` にモジュールレベルキャッシュ `_SKILL_LOG_CACHE` 追加 | 71ms × 2 = 142ms | 71ms + <5ms | 50%（2 回呼出し時） |

R1 のボトルネックは `skill_execution_log.sh` 内で `yaml_scalar()` シェル関数を 7 回 + validation を 1 回、計 8 回の `python3 -c ...` spawn が発生し、プロセス起動コストだけで 8 × 37ms ≈ 296ms を消費している点にある。R2 のボトルネックは `explicit_skill=None` 時に `latest_fail_entry()` → `load_skill_log()` と `has_duplicate_failure()` → `load_skill_log()` で同一 YAML（195 エントリ）を 2 回ロードする点にある。

### 1.2 実施順序

| Phase | 作業 | 完了条件 |
|-------|------|----------|
| Phase 1 | R2 実装（`_SKILL_LOG_CACHE` 導入） | `bats tests/unit/test_skill_feedback_loop.bats` 12 tests 全 PASS |
| Phase 2 | R1 実装（`_write_skill_log()` 新設、`subprocess.run` 呼出しを置換） | `bats tests/unit/test_skill_feedback_loop.bats` 12 tests 全 PASS |
| Phase 3 | before/after 比較表の生成 | 単体呼出し・テストスイート全体の計測値を取得 |
| Phase 4 | After 設計書生成 | 計測結果を反映した設計書を出力 |

R2 を先に実施する理由は、変更範囲が小さく（キャッシュ変数の追加のみ）R1 の前提に影響しないこと、および R2 完了後に R1 実装時のテスト実行が高速化され開発サイクルが短縮されることにある。

### 1.3 非交渉制約（リリースブロッキング）

以下の制約はすべての Phase を通じて不変であり、違反は即座にリリースブロッキングとなる。

| 制約 ID | 対象 | 内容 | 根拠 | 遵守方法 |
|---------|------|------|------|----------|
| C1 | `script:skill_gate_feedback` | CLI 引数 `--gate`/`--result`/`--reason`/`--executor`/`--source`/`--skill` の変更禁止 | 呼出元との API 互換性維持 | 引数パース部分の diff が空であること。既存 bats テストによる回帰検証 |
| C2 | `script:skill_execution_log` | `skill_execution_log.sh` 削除禁止 | テスト（bats）・`dash_update` 等の外部呼出元が存在し、既存外部インターフェース維持が必須 | `test -f scripts/skill_execution_log.sh` が true を返すこと。直接呼出しによる動作確認 |
| C3 | `function:_write_skill_log` | `tests/` パス除外ルール凍結。`TESTS_PATH_RE = re.compile(r'(?:^|/)tests/')` による除外ロジックは変更禁止 | 凍結ロジックの動作正確性保証 | 除外パターンのテスト（AC-R1-04）で 4 パターン検証 |
| C4 | `function:_write_skill_log` | `flock` 排他制御必須。`fcntl.flock(lock_fh, fcntl.LOCK_EX)` → 書込み → `fcntl.flock(lock_fh, fcntl.LOCK_UN)` のフローを `try/finally` で保証 | 並行書込み時のデータ破損防止 | 並行 5 プロセス同時書込みテスト（FC-09 逆方向）で YAML 破損なしを確認 |
| C5 | `function:_write_skill_log`, `function:load_skill_log` | `yaml.safe_dump` / `yaml.dump` 使用禁止。YAML 出力はテキスト連結方式（手動文字列構築による追記）で実装 | YAML 上書き事故防止（CLAUDE.md ルール） | `grep -Pn 'yaml\.(safe_)?dump' scripts/skill_gate_feedback.sh` の出力が 0 行であること |
| C6 | 凍結ロジック | `has_duplicate_caution()` の文字列マッチングロジック、`has_duplicate_failure()` のエントリ比較ロジックは変更禁止 | 動作の正確性保証 | リファクタリング前後で同一入力に対し同一結果を返すことをテスト（AC-FROZEN-01, AC-FROZEN-02） |
| C7 | テスト | `bats tests/unit/test_skill_feedback_loop.bats` 12 tests 全 PASS が各 Phase の完了条件 | リグレッション防止 | CI で全テスト実行、1 件でも FAIL ならリリース不可 |

### 1.4 パフォーマンス閾値

| 計測対象 | 閾値 | 計測方法 | Before 参照値 |
|---------|------|---------|-------------|
| `_write_skill_log()` 単体実行時間 | 10 回計測平均 ≤ 30ms | Python `time.perf_counter()` | 220ms |
| `load_skill_log()` 2 回目呼出し時間 | 10 回計測平均 ≤ 5ms | Python `time.perf_counter()` | 71ms |
| FAIL ケース全体実行時間 | ≤ 100ms | bats テスト内計測 | 220ms |
| PASS ケース全体実行時間 | ≤ 100ms | bats テスト内計測 | 224ms |

## 2. Architecture

### 2.1 コンポーネント構成

リファクタリング前後のコンポーネント構成を以下に示す。

**リファクタリング前:**

```
scripts/skill_gate_feedback.sh
  └── Python heredoc
        ├── load_skill_log()          ─── yaml.safe_load で skill_execution_log.yaml を読込み
        ├── latest_fail_entry()        ─── load_skill_log() を呼出し
        ├── has_duplicate_caution()    ─── 文字列マッチングで重複チェック（凍結）
        ├── has_duplicate_failure()    ─── load_skill_log() を呼出し、エントリ比較（凍結）
        └── main()
              └── subprocess.run(["bash", "skill_execution_log.sh", ...])  ← 220ms ボトルネック
                    └── scripts/skill_execution_log.sh
                          ├── yaml_scalar() × 7  ← 各回 python3 -c spawn (37ms/回)
                          ├── validation × 1     ← python3 -c spawn (37ms/回)
                          └── flock + YAML 追記
```

**リファクタリング後:**

```
scripts/skill_gate_feedback.sh
  └── Python heredoc
        ├── _SKILL_LOG_CACHE = None                 ← R2: モジュールレベルキャッシュ
        ├── load_skill_log()                         ← R2: キャッシュ付きロード
        │     └── 初回: yaml.safe_load → _SKILL_LOG_CACHE に格納
        │     └── 2回目以降: _SKILL_LOG_CACHE を返却
        ├── latest_fail_entry()                      ← load_skill_log() 呼出し（キャッシュヒット可能）
        ├── has_duplicate_caution()                   ← 凍結（変更なし）
        ├── has_duplicate_failure()                   ← 凍結（変更なし）、load_skill_log() はキャッシュヒット
        ├── _yaml_str(value)                          ← R1: エスケープヘルパー新設
        ├── _write_skill_log(log_path, skill, ...)    ← R1: インライン実装新設
        │     ├── TESTS_PATH_RE マッチで tests/ パス除外（凍結ロジック）
        │     ├── mkdir(parents=True, exist_ok=True)
        │     ├── flock LOCK_EX 取得
        │     ├── 空ファイル初期化（executions:\n ヘッダ）
        │     ├── YAML エントリ追記（テキスト連結方式）
        │     └── finally: flock LOCK_UN 解放
        └── main()
              └── _write_skill_log(...)  ← subprocess.run を置換（~5ms）

scripts/skill_execution_log.sh                      ← 削除禁止、外部呼出元向けに残置
```

### 2.2 R1: `_write_skill_log()` 関数の詳細設計

#### 2.2.1 関数シグネチャ

```python
def _write_skill_log(
    log_path: Path,
    skill: str,
    executor: str,
    result: str,
    stumbling_points: str,
    gate: str = "",
    source: str = "",
    skill_path_str: str = ""
) -> None:
```

#### 2.2.2 処理フロー

```
_write_skill_log() 呼出し
│
├─ 1. source パス除外チェック
│     TESTS_PATH_RE = re.compile(r'(?:^|/)tests/')
│     source が TESTS_PATH_RE にマッチ → return（書込みスキップ）
│
├─ 2. ログディレクトリ保証
│     log_path.parent.mkdir(parents=True, exist_ok=True)
│
├─ 3. ロックファイル取得
│     lock_path = log_path.parent / (log_path.name + ".lock")
│     lock_fh = open(lock_path, "w")
│     fcntl.flock(lock_fh, fcntl.LOCK_EX)
│
├─ 4. try ブロック
│     ├─ 4a. 空ファイル初期化
│     │     ファイル未存在 or サイズ 0 → "executions:\n" ヘッダ書込み
│     │
│     ├─ 4b. タイムスタンプ生成
│     │     datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S%z")
│     │
│     ├─ 4c. YAML エントリ構築（テキスト連結方式）
│     │     必須フィールド: ts, skill, executor, result, stumbling_points
│     │     条件付きフィールド: gate（非空時のみ）, source（非空時のみ）, skill_path（非空時のみ）
│     │     各値は _yaml_str() でエスケープ
│     │
│     └─ 4d. append モードでファイル書込み
│
└─ 5. finally ブロック
      fcntl.flock(lock_fh, fcntl.LOCK_UN)
      lock_fh.close()
```

#### 2.2.3 YAML エントリ構造

`_write_skill_log()` が生成する YAML エントリは以下のフィールドを記載順序で出力する:

```yaml
- ts: "2026-05-06T12:00:00+0900"
  skill: "skill_name"
  executor: "executor_name"
  result: "FAIL"
  stumbling_points: "reason text"
  gate: "gate_name"        # 非空の場合のみ出力
  source: "path/to/source" # 非空の場合のみ出力
  skill_path: "path/skill" # 非空の場合のみ出力
```

タイムスタンプは ISO 8601 + タイムゾーンオフセット形式（正規表現: `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{4}$`）に準拠する。

#### 2.2.4 `_yaml_str()` エスケープヘルパー

| 入力文字 | エスケープ後 |
|---------|------------|
| `\`（バックスラッシュ） | `\\` |
| `"`（ダブルクォート） | `\"` |
| 改行（`\n`） | `\\n` |

エスケープ後の値はダブルクォートで囲んで出力する。`yaml.safe_dump` / `yaml.dump` は使用しない（制約 C5 準拠）。YAML 追記はテキスト連結方式で実装する。

#### 2.2.5 `tests/` パス除外ルール（凍結ロジック）

`TESTS_PATH_RE = re.compile(r'(?:^|/)tests/')` による判定:

| source パス | 判定 | 理由 |
|------------|------|------|
| `tests/unit/test_foo.bats` | 除外 | 先頭が `tests/` |
| `path/to/tests/integration/bar.sh` | 除外 | 中間に `/tests/` |
| `scripts/run_tests_helper.sh` | 書込み | `tests/` ディレクトリパスではない |
| `src/main.py` | 書込み | マッチなし |

このロジックは `skill_execution_log.sh` 内の条件分岐と等価であり、変更禁止（制約 C3 準拠）。

#### 2.2.6 flock 排他制御（凍結ロジック）

- ロックファイルパス: `{log_path}.lock`（例: `skill_execution_log.yaml.lock`）
- ロック取得: `fcntl.flock(lock_fh, fcntl.LOCK_EX)`
- ロック解放: `fcntl.flock(lock_fh, fcntl.LOCK_UN)`（`finally` ブロック内で保証）
- `fcntl.flock` は POSIX `flock(2)` と同一セマンティクスであり、bash の `flock` コマンドと互換

例外発生時もロックが確実に解放されることを `try/finally` 構造で保証する（制約 C4 準拠）。

#### 2.2.7 空ファイル初期化

| 状態 | 動作 |
|------|------|
| ファイル未存在 | `executions:\n` ヘッダ書込み → エントリ追記 |
| ファイル存在・サイズ 0 | `executions:\n` ヘッダ書込み → エントリ追記 |
| ファイル存在・内容あり | エントリのみ追記（ヘッダ追記なし） |

#### 2.2.8 `skill_execution_log.sh` との出力互換性

`_write_skill_log()` の出力は `skill_execution_log.sh` の出力とフィールド名・値の型・エスケープ方式・フォーマットにおいて完全互換であること。同一入力で両方を実行した場合、タイムスタンプの秒差を除き出力が一致すること。これは bats 12 tests 全 PASS および byte-level 比較テスト（AC-R1-12）で検証する。

### 2.3 R2: `load_skill_log()` キャッシュ化の詳細設計

#### 2.3.1 キャッシュ変数

```python
_SKILL_LOG_CACHE = None  # モジュールレベル変数
```

#### 2.3.2 `load_skill_log()` のキャッシュロジック

```python
def load_skill_log():
    global _SKILL_LOG_CACHE
    if _SKILL_LOG_CACHE is not None:
        return _SKILL_LOG_CACHE
    # ファイルから yaml.safe_load でロード
    _SKILL_LOG_CACHE = loaded_data
    return _SKILL_LOG_CACHE
```

#### 2.3.3 キャッシュスコープと制約

- **プロセススコープ限定**: キャッシュはプロセス内のモジュールレベル変数に格納され、異なるプロセスからはアクセスできない
- **キャッシュ無効化不要**: `_write_skill_log()` によるログ書込みと `load_skill_log()` による読取りは同一呼出しフロー内で連続しないため、同一プロセス内でのキャッシュ破棄は不要
- **並行プロセスの影響なし**: 別プロセスが `skill_execution_log.yaml` に追記しても、当該プロセスのキャッシュは汚染されない

#### 2.3.4 呼出しチェーン

**`explicit_skill=None` 時（2 回呼出し → キャッシュヒット）:**

```
main(explicit_skill=None)
  └── latest_fail_entry()
        └── load_skill_log()  ← 1 回目: ファイル I/O（71ms）
  └── has_duplicate_failure()
        └── load_skill_log()  ← 2 回目: キャッシュ返却（<5ms）
```

**`explicit_skill` 指定時（1 回のみ呼出し）:**

```
main(explicit_skill="skill_name")
  └── has_duplicate_failure()
        └── load_skill_log()  ← 1 回のみ: ファイル I/O（71ms）
```

### 2.4 外部 API（CLI インターフェース）

`skill_gate_feedback.sh` の CLI 引数は変更禁止（制約 C1 準拠）。

| 引数 | 必須/任意 | 用途 |
|------|----------|------|
| `--gate` | 必須 | ゲート名の指定 |
| `--result` | 必須 | ゲート判定結果（PASS / FAIL） |
| `--reason` | 必須 | 判定理由（stumbling_points） |
| `--executor` | 必須 | 実行者名 |
| `--source` | 任意 | ソースファイルパス |
| `--skill` | 任意 | スキルファイルパス |

#### 2.4.1 ケース別動作

| ケース | 条件 | 動作 |
|--------|------|------|
| FAIL | `--result FAIL` + `--skill` 指定 | スキルファイルに注意ポイント追記 + 実行ログ記録 |
| PASS | `--result PASS` + `--skill` 指定 | 実行ログ記録のみ（スキルファイル変更なし） |
| SKIP | `--skill` 未指定 | スキル関連処理をスキップ、exit code 0 で正常終了 |

### 2.5 `skill_execution_log.sh` の存続

`skill_execution_log.sh` は R1 インライン化後も削除しない（制約 C2 準拠）。以下の外部呼出元が存在するため、単独実行可能な状態を維持する。

| 呼出元 | 依存内容 |
|--------|---------|
| `bats tests/unit/test_skill_feedback_loop.bats` | テストスイート内で直接呼出し |
| `dash_update` | 外部ツールからの呼出し |

R1 実装着手前に `grep -r skill_execution_log` で上記以外の呼出元がないか網羅確認する。

### 2.6 凍結ロジック一覧

以下の関数・ロジックはリファクタリングの対象外であり、コードの変更を禁止する。

| 凍結対象 | 凍結内容 | 検証方法 |
|---------|---------|---------|
| `has_duplicate_caution()` | 文字列マッチングアルゴリズム | 完全一致・部分一致・不一致パターンで前後結果比較（AC-FROZEN-01） |
| `has_duplicate_failure()` | エントリ比較アルゴリズム | 重複・非重複・空ログパターンで前後結果比較（AC-FROZEN-02） |
| `TESTS_PATH_RE` パターン | `re.compile(r'(?:^|/)tests/')` による除外ロジック | 4 パターンの入出力検証（AC-R1-04） |
| `flock` 排他制御フロー | `LOCK_EX` → 書込み → `LOCK_UN`（`try/finally`） | 並行書込みテスト + 静的検査（AC-R1-06） |

### 2.7 テスト戦略概要

#### 2.7.1 既存テストスイート

`bats tests/unit/test_skill_feedback_loop.bats` の 12 件全 PASS がすべての Phase の完了条件（制約 C7 準拠）。1 件でも FAIL または SKIP がある場合はリリースブロッキング。

#### 2.7.2 E2E テストドメイン分割

| ドメイン | CLI テスト（bats） | Python テスト（pytest） | 対応する制約/AC |
|---------|-------------------|----------------------|----------------|
| write-log | `tests/e2e/write-log.bats` | `tests/e2e/write-log.pytest.py` | AC-R1-01〜12, C3, C4 |
| cache | — | `tests/e2e/cache.pytest.py` | AC-R2-01〜05 |
| frozen-logic | — | `tests/e2e/frozen-logic.pytest.py` | AC-FROZEN-01〜02, C6 |
| api-compat | `tests/e2e/api-compat.bats` | — | AC-API-01〜02, C1, C2 |
| yaml-safety | `tests/e2e/yaml-safety.bats` | — | AC-YAML-01, C5 |
| performance | — | `tests/e2e/performance.pytest.py` | AC-PERF-01〜02 |

#### 2.7.3 品質ゲート

| 基準 | 閾値 |
|------|------|
| テスト結果 | ALL PASS（SKIP 0 件） |
| 受入基準カバレッジ | AC-* 全 25 項目に対応するテストが存在 |
| 失敗基準カバレッジ | FC-* 全 9 項目に対応する逆方向テストが存在 |
| bats 既存テスト | 12 件全 PASS |
| `yaml.safe_dump` / `yaml.dump` 不使用 | `grep` 結果 0 行 |
| API 引数互換 | 6 引数全受付 |
| 凍結ロジック不変 | diff なし |

### 2.8 非交渉制約の設計への反映

本設計書が各非交渉制約をどのように反映しているかを以下に明示する。

**制約「API 互換（CLI 引数凍結）・tests/ パス除外ルール凍結・flock 排他制御必須」（対象: `script:skill_gate_feedback`, `function:_write_skill_log`）の反映:**
- セクション 2.4 で CLI 引数 `--gate`/`--result`/`--reason`/`--executor`/`--source`/`--skill` を凍結として明記し、引数名・型・順序の維持を要求
- セクション 2.2.5 で `TESTS_PATH_RE` パターンを凍結ロジックとして定義し、4 パターンの判定表で等価性を保証
- セクション 2.2.6 で `flock` 排他制御のフロー（`LOCK_EX` → 書込み → `LOCK_UN`）を `try/finally` 構造で必須化し、ロックファイルパスを `{log_path}.lock` に固定

**制約「skill_execution_log.sh 削除禁止・既存外部インターフェース維持必須」（対象: `script:skill_execution_log`）の反映:**
- セクション 2.5 で `skill_execution_log.sh` の残置を明記し、外部呼出元（bats テスト・`dash_update`）との互換性維持を要求
- セクション 2.1 のコンポーネント構成図で `skill_execution_log.sh` をリファクタリング後も独立コンポーネントとして維持

**制約「yaml.safe_dump 使用禁止・YAML 追記はテキスト連結方式で実装すること」（対象: `function:_write_skill_log`, `function:load_skill_log`）の反映:**
- セクション 2.2.4 で `_yaml_str()` ヘルパーによる手動文字列構築を設計し、`yaml.safe_dump` / `yaml.dump` の使用を明示的に禁止
- セクション 2.2.2 の処理フローで YAML 追記を append モードでのテキスト連結方式として定義
- `load_skill_log()` での読込みには `yaml.safe_load` を使用するが、書込み系関数（`_write_skill_log`）では `yaml` モジュールの dump 系関数を一切使用しない

## 3. Open Questions

| ID | 質問 | 影響範囲 | トリガー条件 | 想定される対応 |
|----|------|---------|-------------|---------------|
| OQ-1 | `skill_execution_log.sh` の外部呼出元は bats テストと `dash_update` 以外に存在するか | R1 実装時の互換性リスク | R1 実装着手前に `grep -r skill_execution_log` で網羅確認 | 追加の呼出元が発見された場合、その互換性テストを追加 |
| OQ-2 | `_SKILL_LOG_CACHE` のキャッシュ無効化が将来必要になるユースケース（同一プロセス内でログ書込み → ログ読取りが連続するフロー）は発生するか | R2 のキャッシュ設計 | 該当フローの実装時 | キャッシュ破棄メソッド（`_SKILL_LOG_CACHE = None` にリセット）を追加 |
| OQ-3 | `iter_skill_files` のコールドキャッシュ性能（399ms、38 スキル走査）が全体の支配的コストになるか | 次回リファクタリングサイクルの優先度 | Phase 3 計測で `iter_skill_files` が全体の 50% 以上を占めた場合 | ファイルリストのキャッシュまたは遅延ロードを検討 |
| OQ-4 | `_write_skill_log()` の YAML 出力と `skill_execution_log.sh` の出力の byte-level 互換テスト（AC-R1-12）において、タイムスタンプ秒差以外に許容すべき差異はあるか | R1 の互換性検証精度 | R1 実装完了後の byte-level 比較テスト実施時 | 末尾改行・空白差異等の正規化ルールをテストに明記 |
