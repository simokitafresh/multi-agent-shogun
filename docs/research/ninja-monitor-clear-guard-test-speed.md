# ninja monitor clear guard test speed

## 改善候補

| 優先 | 対象 | 根拠 |
|---|---|---|
| 1 | `tests/unit/test_ninja_monitor_clear_guard.bats` の一時root | 56テスト中55件が追加`mktemp`と再帰cleanupを実行するが、BATSはテスト単位の隔離rootを既に提供する。 |
| 2 | 同ファイルのlibrary load | 多数のテストが[[ninja_monitor.sh]]を個別subshellでsourceし、同じ関数群を反復parseする。 |
| 3 | 同ファイルのfixture構築 | queue、stub、git repositoryの生成が類型ごとに重複しており、helper化でshell processと記述量を削減できる。 |

最高インパクト候補1を実装し、[[test_ninja_monitor_clear_guard.bats]] の55個の一時rootを`BATS_TEST_TMPDIR`へ統一した。期待値、56テスト、clear guardの異常系契約は維持する。
