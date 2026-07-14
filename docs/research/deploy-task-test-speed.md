# deploy_task Unit test speed

`tests/unit/test_deploy_task.bats` の全27件で反復していたGit repository初期化を、実際にGit履歴を使う2件だけへ限定した。テスト数・期待値・異常系を変えず、共有scaffold契約は [[deploy_task_scaffold.bash]]、被テスト実装は [[deploy_task.sh]] を参照する。

## 改善候補

1. `tests/unit/test_deploy_task.bats` の`setup`: Gitを使わない25件でも`git init`とconfig 2回を実行していた。最高インパクトとして遅延初期化した。
2. `tests/unit/test_deploy_task.bats` の`use_private_scripts_fixture`: scripts tree全体のcopyは対象テストだけに限定済みだが、必要ファイル限定copyでさらに短縮できる余地がある。
3. `tests/unit/test_deploy_task.bats` のquoted shell群: 同じproduction scriptを複数回sourceするため、関数抽出bundle共有の余地がある。ただしglobal初期化副作用の契約確認が先に必要。

origin: [[cmd_training_test_speed_test_deploy_task__20260714232642]] -> [[repeated-git-fixture-setup]] -> [[deploy-task-test-speed]]
