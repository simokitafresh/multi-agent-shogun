# deploy-task ten-minute contract test speed

- 対象: `tests/unit/test_deploy_task_ten_min_contract.bats`
- 直接関連: [[deploy_task_scaffold]] のprocess内source cacheを利用し、各caseの`bash -lc`と`deploy_task.sh`再parseを除去する。
- 品質契約: 31ケースを維持し、FAIL 0 / SKIP 0のときだけ速度改善と判定する。
- 実装根拠: `tests/helpers/deploy_task_scaffold.bash` の「Cache the 10k-line deploy library once per Bats test process」を再利用する。
