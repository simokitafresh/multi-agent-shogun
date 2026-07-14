# ninja monitor stall test speed

## 改善候補

| 優先 | 対象 | 根拠 |
|---|---|---|
| 1 | [[test_ninja_monitor_stall.bats]] の一時root生成 | 69テスト中65箇所が `mktemp -d` を呼び、Batsが既に提供するテスト単位の隔離領域と役割が重複していた。 |
| 2 | [[ninja_monitor.sh]] のlibrary load | 58箇所が約6,800行の本体と依存libraryを個別subshellでsourceし、同じparseを反復する。 |
| 3 | [[test_ninja_monitor_stall.bats]] のfixture構築 | queue、stub、reportの生成がテストごとに重複し、類型別helperへ集約できる。 |

最高インパクト候補1を実装し、65個の一時rootをBats標準の`BATS_TEST_TMPDIR`配下へ統一した。期待値、69テスト、FAIL=0、SKIP=0を維持した。

設計照合: [[ninja_monitor.sh]] 39行目は監視本体が`cli_lookup.sh`をsourceすることを示す。この依存loadを含む本体sourceが各subshellで反復されるため、候補2は次段の支配項である。
