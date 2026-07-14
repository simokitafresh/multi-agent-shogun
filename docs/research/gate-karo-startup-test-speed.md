# gate_karo_startup test speed

- 対象: [[test_gate_karo_startup]]
- 全量台帳の変更前値は [[test-suite-time-immune-asis-tobe-5w1h_20260714]] §3.1 の「`test_gate_karo_startup` 67.350s」。
- 2026-07-14: Bats管理tmp配下のfixtureを各test teardownで重複削除しない。66/66 PASS、SKIP 0、jobs=5で34.71s。
