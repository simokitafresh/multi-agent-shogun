---
codd:
  node_id: governance:adr-refactoring-approach
  type: governance
  depends_on:
  - id: req:skill-gate-feedback-refactor-requirements
    relation: derives_from
    semantic: governance
  depended_by:
  - id: design:system-design
    relation: constrained_by
    semantic: governance
  conventions:
  - targets:
    - script:skill_execution_log
    reason: skill_execution_log.sh削除禁止（テスト・dash_update等の外部呼出元が存在）
  - targets:
    - function:_write_skill_log
    reason: yaml.safe_dump使用禁止・flock排他制御の維持が必須
  modules:
  - skill_gate_feedback
  - skill_execution_log
---

# ADR: subprocess インライン化とキャッシュ導入の方針決定

## 1. Overview

本 ADR は `scripts/skill_gate_feedback.sh`（216行の bash+Python スクリプト）における2つの性能ボトルネックに対するリファクタリング方針を記録する。対象は gate FAIL 時のスキル注意ポイント追記処理およびスキル実行ログ記録処理である。

### 背景と動機

2026-05-06 の実測プロファイルにより、以下の2つのボトルネックが特定された。

| ID | ボトルネック | 計測コスト | 根本原因 |
|----|-------------|-----------|----------|
| R1 | `subprocess.run(skill_execution_log.sh)` | **220ms/呼出し** | bash プロセス起動後、内部で `yaml_scalar()` を7回 + validation を1回、計8回の Python spawn（8 × 37ms ≈ 296ms の起動コスト） |
| R2 | `load_skill_log()` の重複呼出し | **71ms × 2 = 142ms** | `explicit_skill=None` のとき `latest_fail_entry()` → `load_skill_log()` と `has_duplicate_failure()` → `load_skill_log()` で同一 YAML（195エントリ）を2回ロード |

テストスイート全体（bats 12 tests）の実行時間は **3.634s** であり、これらのボトルネック解消により大幅な短縮が見込まれる。

### 決定の要旨

- **R1**: `subprocess.run` による外部シェルスクリプト呼出しを廃止し、同等ロジックを Python heredoc 内の `_write_skill_log()` 関数としてインライン実装する。期待効果は 220ms → ~5ms（**-98%**）。
- **R2**: `load_skill_log()` の戻り値をモジュールレベル変数 `_SKILL_LOG_CACHE` でキャッシュし、同一プロセス内での2回目以降の YAML ロードを省略する。期待効果は **71ms 節約**。

### 不変制約（リリースブロッキング）

本 ADR のすべての決定は以下の不変制約に従う。違反はリリースブロッキングとして扱う。

**制約 C1 — `skill_execution_log.sh` 削除禁止（対象: `script:skill_execution_log`）**
`skill_execution_log.sh` はテストスイート（`bats tests/unit/test_skill_feedback_loop.bats`）および `dash_update` 等の外部呼出元から直接参照されている。R1 でインライン化を行っても、シェルスクリプト本体は削除せず、既存の外部呼出元との互換性を維持する。

**制約 C2 — `_write_skill_log()` における `yaml.safe_dump` 使用禁止および `flock` 排他制御の維持（対象: `function:_write_skill_log`）**
`_write_skill_log()` 関数では `yaml.safe_dump` を使用しない。これは YAML 上書き事故防止のための CLAUDE.md ルールに基づく。YAML エントリの書き込みは手動文字列構築による追記（append）方式で行い、`fcntl.flock` による排他ロック（`LOCK_EX` / `LOCK_UN`）を必ず取得・解放する。ロックファイルは `<log_path>.lock` に配置する。

## 2. Decision Log

### Decision 2.1 — R1: subprocess.run のインライン化

**日付**: 2026-05-06
**ステータス**: 承認（confidence: 0.95）

**コンテキスト**: `skill_gate_feedback.sh` は gate 判定後に `subprocess.run(["bash", log_script, skill, executor, result, ...])` で `skill_execution_log.sh` を呼び出す。`skill_execution_log.sh` は内部で `yaml_scalar()` シェル関数を7回呼出し、各回で `python3 -c ...` を spawn する。最後に YAML validation でさらに1回 spawn し、合計8回の Python プロセス起動が発生する。プロセス起動コストだけで 8 × 37ms ≈ 296ms を消費し、flock + ファイル書込みを含めた全体で ~220ms となっている。

**決定**: `_write_skill_log()` 関数を Python heredoc 内に新設し、以下のロジックをインライン実装する。

1. **source パス除外**: `re.compile(r'(?:^|/)tests/')` による正規表現マッチで `tests/` または `*/tests/*` パスを除外する。この除外ルールは `skill_execution_log.sh` と同一であり、変更禁止の凍結ロジックである。
2. **ディレクトリ自動作成**: `log_path.parent.mkdir(parents=True, exist_ok=True)` でログディレクトリを保証する。
3. **flock 排他制御**: `fcntl.flock(lock_fh, fcntl.LOCK_EX)` でロック取得、`try/finally` で `fcntl.flock(lock_fh, fcntl.LOCK_UN)` を保証する。ロックファイルは `log_path.parent / (log_path.name + ".lock")` に配置する。
4. **YAML 追記**: 初回（ファイル未存在 or サイズ0）は `executions:\n` ヘッダを書き込み、以降はエントリ行を `append` モードで追記する。各フィールド値は `_yaml_str()` ヘルパーでエスケープ（`\` → `\\`、`"` → `\"`、改行 → `\n`）し、ダブルクォートで囲む。
5. **フィールド構成**: `ts`、`skill`、`executor`、`result`、`stumbling_points` は必須出力。`gate`、`source`、`skill_path` は値が存在する場合のみ出力する。
6. **yaml.safe_dump は使用しない**: 手動文字列構築による追記方式を採用する（制約 C2 準拠）。

**期待効果**: 220ms → ~5ms（**-98%** 削減）

**API 互換性**: `skill_gate_feedback.sh` の外部 API（`--gate` / `--result` / `--reason` / `--executor` / `--source` / `--skill` 引数）は一切変更しない。`skill_execution_log.sh` 自体も削除せず残置する（制約 C1 準拠）。

**リスクと緩和策**:

| リスク | 緩和策 |
|--------|--------|
| インライン実装と `skill_execution_log.sh` の動作不一致 | bats 12 tests 全 PASS を実装後に確認。YAML 出力フォーマットの byte-level 比較テストを実施 |
| flock セマンティクスの差異 | `fcntl.flock` は POSIX flock(2) と同一セマンティクスであり、bash の `flock` コマンドと互換 |
| source 除外ルールの乖離 | 正規表現 `(?:^|/)tests/` は `skill_execution_log.sh` 内の条件分岐と等価であることをテストで検証 |

### Decision 2.2 — R2: load_skill_log() キャッシュ化

**日付**: 2026-05-06
**ステータス**: 承認（confidence: 0.95）

**コンテキスト**: `explicit_skill=None` の場合、`latest_fail_entry()` → `load_skill_log()` で1回目、`has_duplicate_failure()` → `load_skill_log()` で2回目と、同一プロセス内で同一 YAML ファイル（195エントリ、71ms/回）を2回ロードする。

**決定**: モジュールレベル変数 `_SKILL_LOG_CACHE = None` を導入し、`load_skill_log()` の初回呼出し結果をキャッシュする。2回目以降はキャッシュを返却する。

**スコープ制限**: キャッシュはプロセス内のみ有効であり、プロセス間共有は行わない。これにより、並行プロセスが `skill_execution_log.yaml` に追記しても、別プロセスのキャッシュが汚染されることはない。`_write_skill_log()` が同一プロセス内で呼ばれた場合のキャッシュ無効化は不要（ログ書き込みと読み取りは同一呼出しフロー内で連続しないため）。

**期待効果**: 71ms 節約（`explicit_skill=None` の2回呼出しケースのみ）

**凍結ロジック**: 以下のロジックはキャッシュ導入に関わらず変更禁止。
- `has_duplicate_caution()` の文字列マッチングロジック
- `has_duplicate_failure()` のエントリ比較ロジック

### Decision 2.3 — 実施順序

**日付**: 2026-05-06
**ステータス**: 承認

**決定**: R2（キャッシュ化）を先に実施し、次に R1（インライン化）を実施する。

| Phase | 作業 | 完了条件 |
|-------|------|----------|
| Phase 1 | R2 実装（`_SKILL_LOG_CACHE` 導入） | `bats tests/unit/test_skill_feedback_loop.bats` 12 tests 全 PASS |
| Phase 2 | R1 実装（`_write_skill_log()` 新設、`subprocess.run` 呼出しを置換） | `bats tests/unit/test_skill_feedback_loop.bats` 12 tests 全 PASS |
| Phase 3 | Phase 5 計測（before/after 比較表の生成） | 単体呼出し・テストスイート全体の計測値を取得 |
| Phase 4 | Phase 6 After 設計書生成 | 計測結果を反映した設計書を出力 |

**理由**: R2 は変更範囲が小さく（キャッシュ変数の追加のみ）、R1 の前提に影響しない。R2 を先に完了させることで、R1 実装時のテスト実行が高速化され、開発サイクルが短縮される。

### Decision 2.4 — 不変制約の明文化

**日付**: 2026-05-06
**ステータス**: 承認

以下の制約は本リファクタリングの全 Phase を通じて不変である。

| 制約 ID | 対象 | 内容 | 根拠 |
|---------|------|------|------|
| C1 | `script:skill_execution_log` | `skill_execution_log.sh` は削除禁止 | テスト（bats）・`dash_update` 等の外部呼出元が存在 |
| C2a | `function:_write_skill_log` | `yaml.safe_dump` 使用禁止 | YAML 上書き事故防止（CLAUDE.md ルール） |
| C2b | `function:_write_skill_log` | `fcntl.flock` による排他制御を必ず実装 | 並行書込み時のデータ破損防止 |
| C3 | 外部 API | `--gate` / `--result` / `--reason` / `--executor` / `--source` / `--skill` 引数の変更禁止 | 呼出元との互換性維持 |
| C4 | 凍結ロジック | `has_duplicate_caution()`・`has_duplicate_failure()`・source 除外ルール・flock 排他制御のロジック変更禁止 | 動作の正確性保証 |
| C5 | テスト | `bats tests/unit/test_skill_feedback_loop.bats` 12 tests 全 PASS が各 Phase の完了条件 | リグレッション防止 |

## 3. Follow-ups

| ID | アクション | トリガー | 担当条件 |
|----|-----------|----------|----------|
| F1 | Phase 5 before/after 比較表の生成：単体呼出し（FAIL case / PASS case / SKIP case）およびテストスイート全体（bats 12 tests）の計測値を取得し、R1・R2 それぞれの効果を定量評価する | R1・R2 実装完了後 | 実装者 |
| F2 | Phase 6 After 設計書の生成：計測結果を反映し、リファクタリング前後のアーキテクチャ差分を文書化する | F1 完了後 | 実装者 |
| F3 | `skill_execution_log.sh` の外部呼出元の棚卸し：現時点で把握している呼出元（bats テスト・`dash_update`）以外に依存がないか `grep -r skill_execution_log` で網羅確認する | R1 実装着手前 | 実装者 |
| F4 | `iter_skill_files` のコールドキャッシュ性能（399ms）の改善検討：38スキル走査時のコールド起動コストが支配的になった場合、ファイルリストのキャッシュまたは遅延ロードを検討する | Phase 5 計測で `iter_skill_files` が全体の50%以上を占めた場合 | 次回リファクタリングサイクル |
| F5 | `_write_skill_log()` の YAML 出力フォーマットが `skill_execution_log.sh` の出力と byte-level で一致することを検証する専用テストケースの追加 | R1 実装完了後、Phase 5 計測前 | 実装者 |
| F6 | `_SKILL_LOG_CACHE` のキャッシュ無効化が必要なユースケース（同一プロセス内でログ書込み→ログ読取りが連続するフロー）が将来発生した場合、キャッシュ破棄メソッドを追加する | 該当フローの実装時 | 該当機能の実装者 |
