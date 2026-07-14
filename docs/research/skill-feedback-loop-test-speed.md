# skill-feedback-loop-test-speed

- [[test_skill_feedback_loop.bats]] — skill-log契約を検証しないdashboard fixtureでは副作用ログを無効化する。
- [[dashboard_update.sh]] — `SKILL_EXECUTION_LOG_DISABLE=1`で本体契約を変えず不要な後処理だけ抑止できる。
- [[skill_execution_log.sh]] — ログ契約専用testでは無効化せず、PASS/used=falseの検証を維持する。
- 因果: [[非対象skill log副作用]] -> [[不要なYAML更新]] -> [[skill feedback Unit遅延]]
