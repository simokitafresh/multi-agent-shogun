# learning_ops_small consolidated test speed

## 結論

`run_embedded_test` がnested Batsを外側testごとに34回起動していたため、元suite単位13回の共有TAP結果へ集約する。外側34件は個別test名に対応する`ok`を二値検証し、期待値・対象・SKIP契約は変更しない。

## 改善候補

1. 最高インパクト: `tests/unit/test_learning_ops_small_consolidated.bats` L4-L35のnested `bats` process起動34回をcontent function単位13回へ集約し、共有TAPから個別test名を判定する。
2. 次点: 同一content functionの反復decodeとcontext fixture正規化をfile-scope cacheへ集約する。最高インパクト案の前提として併せて実装する。
3. 次点: L11のnested fixture生成先をsuite共通treeへ寄せて`cp`量を減らす。ただしテスト間書込み分離を損なうため、共有するのはimmutable入力だけとする。

## 因果と関連契約

- 修行の二値計測と即時還流は [[training-cycle]] §1-L5-L11 に定義される。
- fixture共有は既存の [[test_prompt_state_inject_skill_trigger.bats]] の「setup_fileで一度だけ生成」方針と同型である。
- 実装対象は [[test_learning_ops_small_consolidated.bats]]。nested testごとの一時コピーを維持し、共有cacheをimmutable入力に限定する。

## 検証契約

- `bats tests/unit/test_learning_ops_small_consolidated.bats`: 34/34、FAIL 0、SKIP 0。
- wall timeを変更前後で比較する。
- D7分類: behavior不変refactor。既存34 testのcoverageと期待値を維持し、新behaviorは追加しない。
