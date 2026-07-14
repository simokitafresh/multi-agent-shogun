# context_freshness_check Unit 高速化

## 結論

`tests/unit/test_context_freshness_check.bats` は、48 testすべてで同じ空repo・config・exclude-listを再生成し、timeout regressionは秒単位の待機を反復していた。`setup_file` でmaster fixtureを1回だけ生成し、各testは独立コピーから開始する。timeout値は小数秒も受理し、同じ2試行/fail-closed契約を短時間で検証する。

## 契約

- production behaviorと48 testの期待値は変更しない。
- timeout/retryのfail-closed契約は維持する。
- テスト対象は [[context_freshness_check.sh]]、速度改善の原則は [[training-cycle]] に従う。

## 根拠

`context/training-cycle.md` の「テスト高速化は、不要テスト削除/統合→元スクリプト高速化→テスト側改善の順で着手すること」を適用した。本件は48件で反復するfixture準備だけを共有し、各testの作業repoは引き続き独立させる。
