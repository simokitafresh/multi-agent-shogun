# gate_karo_startup test speed

- 対象: [[test_gate_karo_startup]]
- 全量台帳の変更前値は [[test-suite-time-immune-asis-tobe-5w1h_20260714]] §3.1 の「`test_gate_karo_startup` 67.350s」。
- 2026-07-14: Bats管理tmp配下のfixtureを各test teardownで重複削除しない。66/66 PASS、SKIP 0、jobs=5で34.71s。
- 実装契約: [[gate_karo_startup.sh]]。Unitのbase fixtureは依存ファイルを1回だけ配置し、各test cloneへ重複ファイルを持ち込まない。
- fixture lifecycleは [[training-cycle.md]] の「FAIL→即停止・原因報告。PASS→次ACへ」に従い、Bats固有`BATS_TEST_TMPDIR`を直接利用する。外部`mktemp`を66回起動せず、test間隔離とrunner自動cleanupは維持する。
