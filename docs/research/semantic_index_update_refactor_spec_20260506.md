# semantic_index_update.sh リファクタリング CoDD Spec

## 問題

`scripts/semantic_index_update.sh` は semantic index の更新可否を Python で判定したあと、`__SEMANTIC_INDEX_CHANGED__` sentinel の除去と検出に `grep` を2回起動している。
小さい更新スクリプトのため、Python本体と map 再生成以外の余分な subprocess を減らす。

## 定量プロファイル（実測）

計測日: 2026-05-06

| 対象 | 5回実測 | 中央値 |
|------|--------|--------|
| `bats tests/unit/test_semantic_index_update.bats` | `0.91s`, `0.99s`, `1.01s`, `0.97s`, `0.98s` | `0.98s` |
| `bash scripts/semantic_index_update.sh --help` | `0.00s`, `0.00s`, `0.01s`, `0.00s`, `0.00s` | `0.00s` |

## リファクタリング対象

| ID | 内容 | 期待効果 |
|----|------|----------|
| R1 | `changed_flag` 後処理の `grep -v` と `grep -qx` を bash `while read` ループへ置換 | sentinel 処理の subprocess 2回を0回へ削減 |

## 実施順序

1. R1を実装する。
2. `bash -n scripts/semantic_index_update.sh` を実行する。
3. `bats tests/unit/test_semantic_index_update.bats` を実行する。
4. before/after中央値を比較する。

## 制約

- CLI引数、stdout文言、exit codeを維持する。
- Python内の概念matchingロジックは変更しない。
- `flock` による排他範囲を維持する。
- `SEMANTIC_MAP_GENERATE` が実行権限なしでも `bash "$map_generate"` で動く既存契約を維持する。
