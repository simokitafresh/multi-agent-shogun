# deploy_task template generation test speed

- 対象: [[test_deploy_task_template_generation.bats]]
- 共有fixtureの生成中は同一一時projectを再利用する。fixtureごとの削除は、source済みdeploy関数が保持するpathを無効化し、39件中1件のみ実行してsetup FAILを招く。
- 守る契約: 期待値緩和なし、SKIP追加なし、39件全実行、FAIL 0 / SKIP 0。
- 関連helper: [[deploy_task_scaffold.bash]]
