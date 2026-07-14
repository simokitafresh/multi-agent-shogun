# parent_cmd_contract test speed

- 結論: [[test_parent_cmd_contract.bats]] の固定parent contract fingerprintをsuite単位で1回だけ計算し、各fixtureから再利用する。
- 根拠: `fp() { printf '%s\n' "$PARENT_FP"; }` により、同一入力のPython起動とmodule importを各テストから除去する。
- 守る契約: 19テスト全件PASS、FAIL 0、SKIP 0。期待値緩和・対象縮小なし。
