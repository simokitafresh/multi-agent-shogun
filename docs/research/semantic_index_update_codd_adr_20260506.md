---
codd:
  node_id: governance:adr-grep-to-bash-loop
  type: governance
  depends_on:
  - id: req:semantic-index-update-refactor-requirements
    relation: derives_from
    semantic: governance
  depended_by:
  - id: design:system-design
    relation: constrained_by
    semantic: governance
  conventions:
  - targets:
    - script:semantic_index_update
    reason: Python概念matchingロジックの非変更はリリース必須条件。sentinel処理のみがリファクタ対象であることをADRで明示する。
  modules:
  - semantic_index_update
---

# ADR: grep subprocess を bash while-read ループへ置換

## 1. Overview

`scripts/semantic_index_update.sh` は semantic index の更新判定後、`__SEMANTIC_INDEX_CHANGED__` sentinel の除去（`grep -v`）と検出（`grep -qx`）に外部プロセスを2回起動している。本 ADR は、この sentinel 処理を bash 組み込みの `while read` ループへ置換し、subprocess 呼び出しを2回から0回へ削減する決定を記録する。

**対象スクリプト:** `script:semantic_index_update`

**リファクタリング境界の明示（リリース必須条件）:**

- Python 概念 matching ロジックは一切変更しない。sentinel の除去・検出のみがリファクタ対象である。
- CLI 引数、stdout 文言、exit code は既存動作を維持する。
- `flock` による排他範囲を変更しない。
- `SEMANTIC_MAP_GENERATE` が実行権限なしでも `bash "$map_generate"` で動作する既存契約を維持する。

**Convention 準拠:** 本 ADR は convention 1 に従い、`script:semantic_index_update` を対象として明示的にスコープを限定している。Python 概念 matching ロジックの非変更はリリース必須条件であり、sentinel 処理のみがリファクタ対象であることをこの Overview セクションおよび Decision Log で繰り返し明記する。

## 2. Decision Log

### Decision 2026-05-06: grep subprocess を bash while-read ループへ置換

**ステータス:** Accepted

**コンテキスト:**

定量プロファイル（2026-05-06 実測）:

| 対象 | 5回実測 | 中央値 |
|------|--------|--------|
| `bats tests/unit/test_semantic_index_update.bats` | 0.91s, 0.99s, 1.01s, 0.97s, 0.98s | 0.98s |
| `bash scripts/semantic_index_update.sh --help` | 0.00s, 0.00s, 0.01s, 0.00s, 0.00s | 0.00s |

`changed_flag` 後処理で `grep -v '__SEMANTIC_INDEX_CHANGED__'` による sentinel 行除去と `grep -qx '__SEMANTIC_INDEX_CHANGED__'` による sentinel 検出が個別の subprocess として起動されている。スクリプト全体は軽量であり、Python 本体と map 再生成以外の余分な subprocess を排除することが目的である。

**決定内容（R1）:**

`grep -v` と `grep -qx` の2つの subprocess を、bash 組み込みの `while IFS= read -r line` ループに置換する。ループ内で sentinel 行を検出した場合はフラグ変数をセットし、それ以外の行は出力バッファへ追加する。これにより sentinel 処理の subprocess 起動が2回から0回に削減される。

**変更しない範囲（リリース必須条件）:**

- Python 概念 matching ロジック（`scripts/semantic_index_update.sh` から呼び出される Python スクリプト内部のロジック全体）
- CLI インターフェース（引数パーサ、`--help` 出力、exit code）
- `flock` 排他制御のスコープと粒度
- `bash "$map_generate"` による実行権限不要の呼び出し契約

**検証手順:**

1. R1 を実装する。
2. `bash -n scripts/semantic_index_update.sh` で構文検証を実行する。
3. `bats tests/unit/test_semantic_index_update.bats` で機能回帰テストを実行する。
4. before/after の中央値を比較し、subprocess 削減を確認する。

**根拠:**

- bash 組み込み機能で完結するため、fork+exec のオーバーヘッドが消失する。
- sentinel 文字列は固定値 `__SEMANTIC_INDEX_CHANGED__` であり、正規表現エンジンは不要。
- テストスイートが既存動作の回帰を検出できる状態にある（中央値 0.98s で安定）。

## 3. Follow-ups

| # | アクション | トリガー条件 | 担当 |
|---|-----------|-------------|------|
| 1 | R1 実装後に `bats tests/unit/test_semantic_index_update.bats` の中央値を再計測し、before（0.98s）との差分を記録する | R1 マージ後 | 実装者 |
| 2 | sentinel 文字列 `__SEMANTIC_INDEX_CHANGED__` が Python 側で変更された場合、bash ループ内の比較文字列を同期する | Python 側の sentinel 定義変更時 | スクリプト保守者 |
| 3 | `shellcheck scripts/semantic_index_update.sh` を CI に追加し、while-read ループの POSIX 互換性警告を監視する | CI パイプライン更新時 | CI 保守者 |
