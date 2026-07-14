# dashboard auto section test speed

## 結論

`concurrent auto section updates` は40回の更新を維持したまま、一括並列起動して直列待機を除く。対象テストは [[test_dashboard_auto_section.bats]]、被テスト実装は [[dashboard_auto_section.sh]]。

## 改善候補

1. 最高インパクト: 2並列×20ラウンドの逐次待機を40プロセス一括起動へ変更する。変更前5.670秒の大半を占める並行性試験の待機を圧縮し、更新回数と検査条件は維持する。
2. setup fixture共有: 各Bats caseで同じsettings/CLI profile/symlinkを再生成しているため、`setup_file`化で重複I/Oを減らせる。ただしcaseごとのdashboard分離が必要で、今回は複雑さに対する効果が小さい。
3. 被テストscriptのcache活用: dry-runを含む各起動が重い集計を繰り返すため、fixtureに有効なcacheを事前生成できる。ただし本番scriptのcache contractまで検証対象に混ざるため、今回の単一責務には採用しない。

## 設計根拠

[[dashboard_auto_section.sh]] の `Each invocation owns exactly one candidate at a time`（変更時点の1343行目）は、各更新プロセスがprivate candidateを持つ設計意図を明示する。一括並列化はこの防御を弱めず、むしろ40 writer同時実行で競合耐性を強く検証する。

因果: [[cmd_training_test_speed_test_dashboard_auto_section__20260715042307]] -> [[sequential-pair-wait]] -> [[dashboard-auto-section-test-speed]]
