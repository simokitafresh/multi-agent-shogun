# insight_write Unit速度改善

- 結論: [[test_insight_write.bats]] の中断耐性2件は固定1秒待機ではなく、一時ファイル出現を二値同期点として待つ。契約実装は [[insight_write.sh]] と [[insight_resolve.sh]]。
- 根拠: `scripts/insight_resolve.sh` 87-96行は `.insights-resolve.*.tmp` を生成・fsync後にreplaceし、`scripts/insight_write.sh` 223-232行は `.insights.*.tmp` を生成・fsync後にreplaceする。この一時ファイル出現後のterminateが「replace直前中断」を直接証明する。
- 改善候補2: 各testのsetupで4ファイルを29回生成しているため、共有fixtureを一度生成してtest固有領域へ複製できる。
- 改善候補3: YAML確認用の短命Pythonプロセスが多数あり、独立性を保ったまま検証をまとめれば起動回数を減らせる。
- 再検証: 固定sleep→checkpoint案は悪化したため撤回。[[test_insight_write.bats]] のread-only依存をsymlink共有fixture化し、3回10.933/11.871/12.363秒（中央値11.871秒、baseline 13.025秒比 -8.9%）、各29/29 PASS・FAIL0・SKIP0。
