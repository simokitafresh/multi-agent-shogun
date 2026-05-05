---
codd:
  node_id: plan:implementation-plan
  type: plan
  depends_on:
  - id: design:call-flow-sequences
    relation: depends_on
    semantic: technical
  - id: design:module-boundary-and-concurrency
    relation: depends_on
    semantic: technical
  depended_by: []
  conventions:
  - targets:
    - phase:r2-cache
    - phase:r1-inline
    reason: R2→R1の実施順序厳守・各フェーズ完了時にbats 12件全PASSがゲート条件
  - targets:
    - phase:measurement
    reason: Phase 5でbefore/after比較表を作成し定量的に改善を検証すること
  modules:
  - skill_gate_feedback
  - skill_execution_log
---

# 実装計画

## 1. Overview

本計画は `scripts/skill_gate_feedback.sh` に対する 2 つのリファクタリングを段階的に実施し、gate 判定フローの実行性能を改善する。

| リファクタリング | 内容 | 主な改善効果 |
|----------------|------|-------------|
| R2: `load_skill_log()` キャッシュ化 | `_SKILL_LOG_CACHE` モジュールレベル変数の導入。`explicit_skill=None` 時の 2 回目 `load_skill_log()` 呼出しをキャッシュ返却（<5ms）に置換 | ファイル I/O 71ms 削減 |
| R1: `subprocess.run` インライン化 | `skill_execution_log.sh` への `subprocess.run` 呼出し（`python3 -c` × 8 spawn、220ms）を Python 関数 `_write_skill_log()` に置換 | プロセス spawn 220ms → ~5ms |

実施順序は **R2（キャッシュ化）→ R1（インライン化）** を厳守する。R2 の変更範囲が小さく（`_SKILL_LOG_CACHE` 変数追加と `load_skill_log()` 内の条件分岐追加のみ）R1 の前提に影響しないこと、および R2 完了後に R1 実装時のテスト実行が高速化される点が根拠である。各フェーズ完了時に `bats tests/unit/test_skill_feedback_loop.bats` の **12 件全 PASS**（SKIP 0 件）をゲート条件とし、1 件でも FAIL/SKIP があればリリースブロッキングとする。

最終フェーズ（Phase 5）では before/after 比較表を作成し、定量的に改善を検証する。計測は `time.perf_counter()` および bats テスト内計測で実施し、以下の閾値をリリース判定基準とする。

| 計測対象 | Before | After 目標 | 閾値（10 回計測平均） |
|---------|--------|-----------|---------------------|
| `_write_skill_log()` 単体 | 220ms | ~5ms | ≤ 30ms |
| `load_skill_log()` 2 回目呼出し | 71ms | <5ms | ≤ 5ms |
| FAIL ケース全体（`explicit_skill=None`） | ~362ms | ~81ms | ≤ 100ms |
| PASS ケース全体 | ~224ms | ~5ms | ≤ 100ms |

### 対象モジュールと凍結スコープ

変更対象は `skill_gate_feedback.sh` 内の Python heredoc である。以下のロジックは凍結対象（制約 C6）であり、全フェーズを通じてコード変更を禁止する。

| 凍結ロジック | 凍結理由 |
|-------------|---------|
| `has_duplicate_caution()` 文字列マッチング | 動作の正確性保証 |
| `has_duplicate_failure()` エントリ比較 | 動作の正確性保証 |
| `latest_fail_entry()` | 動作の正確性保証 |
| `TESTS_PATH_RE = re.compile(r'(?:^|/)tests/')` | tests/ パス除外ルール凍結（制約 C3） |

`skill_execution_log.sh` は制約 C2 により削除禁止とし、外部呼出元（`dash_update`、bats テスト）向けに単独実行可能な状態を維持する。

### 非交渉制約への準拠

**制約「R2→R1 の実施順序厳守・各フェーズ完了時に bats 12 件全 PASS がゲート条件」（対象: `phase:r2-cache`, `phase:r1-inline`）:**
Milestones セクションにおいて Phase 1 を R2（キャッシュ化）、Phase 2 を R1（インライン化）と定義し、各 Phase の Exit Criteria に bats 12 件全 PASS を明記する。Phase 2 は Phase 1 の Exit Criteria を満たすまで着手しない。

**制約「Phase 5 で before/after 比較表を作成し定量的に改善を検証すること」（対象: `phase:measurement`）:**
Milestones セクションの Phase 5 において、`time.perf_counter()` による 10 回計測平均値の before/after 比較表を作成し、全閾値を満たすことをリリース判定基準とする。

**制約「凍結ロジックの呼出しパスがリファクタリング前後で等価であること」（対象: `_write_skill_log`, `load_skill_log`, `latest_fail_entry`, `has_duplicate_failure`）:**
Phase 1（R2）で `explicit_skill=None` 時の `load_skill_log()` 2 回呼出しインターフェースを維持しつつ 2 回目をキャッシュ返却に置換する。`explicit_skill` 指定時の 1 回ロードパスは不変。Phase 2（R1）で `_write_skill_log()` を新設するが、読取り側の呼出しパスには一切影響しない。

**制約「tests/ パス除外ルール（`TESTS_PATH_RE`）は subprocess 版と同一判定であること」（対象: `_write_skill_log`）:**
Phase 2（R1）で `_write_skill_log()` 内に `TESTS_PATH_RE = re.compile(r'(?:^|/)tests/')` を配置し、`skill_execution_log.sh` 内の `[[ "$source" =~ (^|/)tests/ ]]` と等価な判定を AC-R1-04 の 4 パターンテストで検証する。

**制約「skill_execution_log.sh 削除禁止・Python 版 `_write_skill_log` と bash 版が同一ログファイルへ安全に共存する設計であること」（対象: `script:skill_execution_log`）:**
`_write_skill_log()` と `skill_execution_log.sh` は同一のロックファイル `skill_execution_log.yaml.lock` を共有し、POSIX `flock(2)` セマンティクスで相互排他する。並行 5 プロセス同時書込みテスト（FC-09 逆方向）で YAML 破損なしを検証する。

**制約「キャッシュはプロセス内限定（プロセス間共有禁止）・`_SKILL_LOG_CACHE` はモジュールレベル変数で管理」（対象: `load_skill_log`）:**
`_SKILL_LOG_CACHE` をモジュールレベル変数として宣言し、`load_skill_log()` のみがアクセスする。共有メモリ・ファイルベースキャッシュ・IPC による共有を禁止する。

**制約「flock 排他制御必須（`fcntl.LOCK_EX`）・`yaml.safe_dump` 使用禁止・lock ファイルは `log_path.name + '.lock'`」（対象: `_write_skill_log`）:**
`_write_skill_log()` で `fcntl.flock(lock_fh, fcntl.LOCK_EX)` を必須化し、`try/finally` で例外時のロック解放を保証する。ロックファイルパスは `log_path.parent / (log_path.name + ".lock")` に固定する。YAML 書込みはテキスト連結方式のみを使用し、`yaml.safe_dump` / `yaml.dump` を禁止する（`grep -Pn 'yaml\.(safe_)?dump' scripts/skill_gate_feedback.sh` 結果 0 行で検証）。

## 2. Milestones

### Phase 0: 事前確認（着手前ゲート）

| タスク | 成果物 / 判定基準 |
|--------|-----------------|
| `grep -r skill_execution_log` で外部呼出元を網羅確認 | bats テストおよび `dash_update` 以外の呼出元がないことを確認。追加の呼出元が発見された場合は互換性テストを追加 |
| bats 12 件がリファクタリング前の状態で全 PASS することを確認 | `bats tests/unit/test_skill_feedback_loop.bats` → 12 tests, 0 failures, 0 skipped |
| Before 性能ベースライン計測 | `_write_skill_log()` 相当処理（subprocess.run 経由）: 220ms、`load_skill_log()` 2 回呼出し: 142ms（各 71ms）を `time.perf_counter()` 10 回平均で記録 |

**Exit Criteria:** bats 12 件全 PASS、外部呼出元リスト確定、Before ベースライン計測値記録済み

### Phase 1: R2 — `load_skill_log()` キャッシュ化

| タスク | 詳細 |
|--------|------|
| `_SKILL_LOG_CACHE` モジュールレベル変数宣言 | `_SKILL_LOG_CACHE = None` をモジュールスコープに追加 |
| `load_skill_log()` にキャッシュロジック追加 | 初回呼出し時に `yaml.safe_load` でファイル読込み → `_SKILL_LOG_CACHE` に格納。2 回目以降はキャッシュ返却 |
| `explicit_skill=None` 時の 2 回ロード→キャッシュパス検証 | `load_skill_log()` にカウンタを仕込み、呼出し回数が 2 であること・2 回目がキャッシュヒットであることを確認 |
| `explicit_skill` 指定時の 1 回ロードパス保持検証 | 呼出し回数が正確に 1 であることを確認 |
| キャッシュ性能計測 | `load_skill_log()` 2 回目呼出しの 10 回計測平均が ≤ 5ms であることを確認 |

**変更範囲:** `load_skill_log()` 関数内のキャッシュ変数追加のみ。`_write_skill_log()` や `subprocess.run` の呼出しパスに影響なし。凍結ロジック（`has_duplicate_failure()`, `has_duplicate_caution()`, `latest_fail_entry()`）の変更なし。

**Exit Criteria:** `bats tests/unit/test_skill_feedback_loop.bats` → 12 tests, 0 failures, 0 skipped

### Phase 2: R1 — `subprocess.run` インライン化

| タスク | 詳細 |
|--------|------|
| `_yaml_str()` ヘルパー関数の新設 | エスケープ仕様: `\` → `\\`、`"` → `\"`、`\n` → `\\n`。エスケープ後の値をダブルクォートで囲んで出力 |
| `_write_skill_log()` 関数の新設 | テキスト連結方式で YAML エントリを構築。フィールド順序: `ts`, `skill`, `executor`, `result`, `stumbling_points`, `gate`（非空時）, `source`（非空時）, `skill_path`（非空時）。空ファイル/未存在ファイルには `executions:\n` ヘッダを書込み |
| `TESTS_PATH_RE` パス除外ロジック実装 | `TESTS_PATH_RE = re.compile(r'(?:^|/)tests/')` を `_write_skill_log()` 内に配置。マッチ時は書込みスキップ（return） |
| `flock` 排他制御の Python 移行 | `fcntl.flock(lock_fh, fcntl.LOCK_EX)` でロック取得、`try/finally` で `fcntl.flock(lock_fh, fcntl.LOCK_UN)` によるロック解放を保証。ロックファイル: `log_path.parent / (log_path.name + ".lock")` |
| `main()` 内の `subprocess.run` 呼出しを `_write_skill_log()` に置換 | `subprocess.run(["bash", "skill_execution_log.sh", ...])` → `_write_skill_log(log_path, skill, ...)` |
| `skill_execution_log.sh` 残置確認 | `test -f scripts/skill_execution_log.sh` で存在確認。外部呼出元向けに単独実行可能な状態を維持 |
| `yaml.safe_dump` 不使用検証 | `grep -Pn 'yaml\.(safe_)?dump' scripts/skill_gate_feedback.sh` 結果 0 行 |
| CLI 引数互換性検証 | 6 引数（`--gate`, `--result`, `--reason`, `--executor`, `--source`, `--skill`）の引数パース部分の diff が空であることを確認 |
| AC-R1-04: `TESTS_PATH_RE` 等価性検証 | `tests/unit/test_foo.bats` → 除外、`path/to/tests/integration/bar.sh` → 除外、`scripts/run_tests_helper.sh` → 書込み、`src/main.py` → 書込み |
| AC-R1-12: byte-level 出力互換性テスト | 同一入力で `_write_skill_log()` と `skill_execution_log.sh` を実行し、タイムスタンプ秒差のみ許容で出力一致を確認 |

**変更範囲:** `main()` 内のログ書込み呼出し部分のみ。`load_skill_log()` やキャッシュロジックに影響なし。凍結ロジックの変更なし。

**Exit Criteria:** `bats tests/unit/test_skill_feedback_loop.bats` → 12 tests, 0 failures, 0 skipped

### Phase 3: 凍結ロジック等価性検証

| タスク | 詳細 |
|--------|------|
| AC-FROZEN-01: `has_duplicate_caution()` 等価性 | 完全一致・部分一致・不一致パターンで前後結果比較 |
| AC-FROZEN-02: `has_duplicate_failure()` 等価性 | 重複・非重複・空ログパターンで前後結果比較 |
| 呼出しパス等価性の 4 パス検証 | FAIL + `explicit_skill=None`（2 回ロード→キャッシュ）、FAIL + `explicit_skill` 指定（1 回ロード）、PASS + `explicit_skill` 指定（`load_skill_log()` 呼出しなし）、SKIP（スキル関連処理なし） |
| 凍結ロジック diff 検査 | `has_duplicate_caution()`, `has_duplicate_failure()`, `TESTS_PATH_RE`, `flock` フローの diff がないことを確認 |

**Exit Criteria:** 全凍結ロジックの前後等価性確認済み、呼出しパス 4 パターンすべてで期待どおりの動作確認

### Phase 4: 並行制御・堅牢性検証

| タスク | 詳細 |
|--------|------|
| FC-09 逆方向: 並行 5 プロセス同時書込みテスト | Python 3 プロセス + bash 2 プロセスの混合同時書込みで YAML 破損なしを確認 |
| `flock` Python/bash 相互運用性検証 | `fcntl.flock(LOCK_EX)` と bash `flock --exclusive` が同一ロックファイル `skill_execution_log.yaml.lock` で相互排他することを実証 |
| 例外時ロック解放検証 | `_write_skill_log()` 内で例外発生時に `try/finally` で `LOCK_UN` が確実に実行されることを確認 |
| 受入基準カバレッジ確認 | AC-* 全 25 項目に対応するテストが存在することを確認 |
| 失敗基準カバレッジ確認 | FC-* 全 9 項目に対応する逆方向テストが存在することを確認 |

**Exit Criteria:** 並行書込み YAML 破損なし、AC-* 25 項目・FC-* 9 項目のテスト存在確認済み

### Phase 5: Before/After 計測・比較表作成

| タスク | 詳細 |
|--------|------|
| After 性能計測 | `time.perf_counter()` で 10 回計測平均値を取得 |
| Before/After 比較表作成 | Phase 0 で記録した Before ベースラインと Phase 5 の After 値を並列比較する表を作成 |
| 閾値充足判定 | `_write_skill_log()` ≤ 30ms、`load_skill_log()` 2 回目 ≤ 5ms、FAIL ケース全体 ≤ 100ms、PASS ケース全体 ≤ 100ms |
| `iter_skill_files` コールドキャッシュ性能記録 | 399ms（38 スキル走査）が全体の支配的コストになるか定量的に判定し、次回リファクタリング優先度の参考とする |

比較表のフォーマット:

| 計測対象 | Before（10 回平均） | After（10 回平均） | 閾値 | 判定 |
|---------|--------------------|--------------------|------|------|
| `_write_skill_log()` 単体 | 220ms | (計測値) | ≤ 30ms | PASS/FAIL |
| `load_skill_log()` 2 回目 | 71ms | (計測値) | ≤ 5ms | PASS/FAIL |
| FAIL ケース全体 | ~362ms | (計測値) | ≤ 100ms | PASS/FAIL |
| PASS ケース全体 | ~224ms | (計測値) | ≤ 100ms | PASS/FAIL |

**Exit Criteria:** 全 4 計測対象が閾値を充足し、before/after 比較表が完成していること。1 項目でも閾値超過の場合はリリースブロッキング。

### 品質ゲート一覧（全 Phase 共通）

| 基準 | 閾値 | 検証方法 |
|------|------|---------|
| bats 既存テスト | 12 件全 PASS（SKIP 0 件） | `bats tests/unit/test_skill_feedback_loop.bats` |
| 受入基準カバレッジ | AC-* 全 25 項目にテスト存在 | テスト一覧の突合 |
| 失敗基準カバレッジ | FC-* 全 9 項目に逆方向テスト存在 | テスト一覧の突合 |
| `yaml.safe_dump` 不使用 | 0 行 | `grep -Pn 'yaml\.(safe_)?dump' scripts/skill_gate_feedback.sh` |
| CLI 引数互換 | 6 引数全受付 | 引数パース部分の diff が空 |
| 凍結ロジック不変 | diff なし | `has_duplicate_caution()`, `has_duplicate_failure()`, `TESTS_PATH_RE`, `flock` フロー |
| 並行書込み安全性 | YAML 破損なし | 5 プロセス同時書込みテスト |
| 性能閾値 | 4 計測対象全充足 | before/after 比較表 |

## 3. Risks

| ID | リスク | 影響 | 発生確率 | 緩和策 |
|----|--------|------|---------|--------|
| RISK-01 | Python `fcntl.flock` と bash `flock` コマンドの相互運用性が特定環境で不完全 | 並行書込み時に YAML 破損が発生し、`skill_execution_log.yaml` のデータ整合性が損なわれる | 低（両者とも POSIX `flock(2)` ベース） | Phase 4 で Python 3 + bash 2 の混合 5 プロセス同時書込みテスト（FC-09 逆方向）を実施し、実環境で相互排他が機能することを実証する |
| RISK-02 | NFS/ネットワークファイルシステム上で `flock(2)` が正常に機能しない | CI 環境やコンテナ環境で並行書込みテストが失敗する | 低（ローカルファイルシステム前提設計） | `skill_execution_log.yaml` をローカルファイルシステム上に配置することを前提とし、NFS 環境での運用が判明した場合は `fcntl.lockf` への切替えを検討する |
| RISK-03 | `_yaml_str()` と `yaml_scalar()` のエスケープ結果がエッジケースで不一致 | `_write_skill_log()` の出力が `skill_execution_log.sh` と byte-level で一致せず、下流処理で解析エラーが発生する | 中（マルチバイト文字、制御文字、YAML 予約語で差異が出る可能性） | AC-R1-12 の byte-level 比較テストにマルチバイト文字（日本語）、制御文字（`\t`, `\r`）、YAML 予約語（`true`, `null`, `~`）を含む入力パターンを追加し、エッジケースを早期に検出する |
| RISK-04 | `skill_execution_log.sh` の未知の外部呼出元が存在し、R1 実装後に互換性問題が発生する | 外部呼出元が `skill_execution_log.sh` の出力を解析している場合、`_write_skill_log()` の出力形式の微差が下流で問題になる | 低（Phase 0 の `grep -r` 網羅確認で検出可能） | Phase 0 で `grep -r skill_execution_log` を実行し、bats テスト・`dash_update` 以外の呼出元がないことを確認する。追加の呼出元が発見された場合はその互換性テストを追加する |
| RISK-05 | `explicit_skill=None` 時に `latest_fail_entry()` が空リスト/None を返した場合、`has_duplicate_failure()` が呼出されず `load_skill_log()` が 1 回のみとなる | キャッシュの 2 回目ヒットが発生しないパスが存在する。性能閾値（≤ 100ms）の達成には影響しない（1 回ロードでも 71ms + ~5ms < 100ms） | 中（空ログ時に発生） | 呼出しフローのブランチ分岐をテストで網羅し、`has_duplicate_failure()` が呼出されないパスでも閾値を満たすことを Phase 5 の計測で確認する |
| RISK-06 | R2→R1 の実施順序を誤って R1 を先に実装してしまう | 両リファクタリングの影響範囲は直交しているため技術的な問題は発生しないが、R2 完了前の R1 テスト実行が低速化し開発効率が低下する。ゲート条件（各フェーズ完了時 bats 12 件全 PASS）の管理が複雑化する | 低（計画書に明記） | Milestones の Phase 1/Phase 2 の定義を厳守し、Phase 1（R2）の Exit Criteria（bats 12 件全 PASS）を満たすまで Phase 2（R1）に着手しない |
| RISK-07 | `iter_skill_files` のコールドキャッシュ性能（399ms、38 スキル走査）が全体の支配的コストとなり、R1/R2 の改善効果が体感上希薄化する | Phase 5 の before/after 比較表で R1/R2 の改善は閾値を満たすものの、エンドユーザーが体感する全体レイテンシの改善幅が限定的になる | 中（399ms は FAIL ケース全体 362ms より大きい） | Phase 5 の計測で `iter_skill_files` が全体の 50% 以上を占めた場合、ファイルリストのキャッシュまたは遅延ロードを次回リファクタリング候補として記録する |
| RISK-08 | byte-level 比較テスト（AC-R1-12）でタイムスタンプ秒差以外の想定外の差異（末尾改行、連続空白）が検出される | テスト判定基準が曖昧になり、合否判定が困難になる | 中 | 正規化ルール（末尾改行の統一、連続空白の正規化）をテスト仕様として事前に明記し、AC-R1-12 の判定基準に含める。タイムスタンプ秒差のみを許容差異とし、それ以外の差異は不合格とする |
