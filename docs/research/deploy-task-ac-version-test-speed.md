# deploy_task AC version test speed

## 結論

`tests/unit/test_deploy_task_ac_version.bats` の支配項は、各 `deploy_task_*` 呼出しで約10,000行の本体を再sourceする処理だった。[[test_deploy_task_ac_version.bats]] の37テスト・期待値・SKIP数を変えず、[[deploy_task_scaffold.bash]] でライブラリを各Batsテストプロセスにつき1回だけ読み込む。

## 改善候補（実測順）

|順位|対象|改善点|根拠|
|---:|---|---|---|
|1|`tests/helpers/deploy_task_scaffold.bash`|source結果をsetup内でキャッシュ|`scripts/deploy_task.sh` は約10,000行で、helper内に再source箇所が10件あった|
|2|`tests/unit/test_deploy_task_ac_version.bats`|同一fixtureのYAML生成を共有化|37件の各setupでtask YAMLを再作成している|
|3|`tests/unit/test_deploy_task_ac_version.bats`|複数field assertionを単一読取へ集約|各assertionが`field_get`/`grep`の別プロセスを起動する|

## 実装した最高インパクト

[[deploy_task_scaffold.bash]] の `deploy_task_scaffold()` で `parse_deploy_task_args` の存在を確認し、未ロード時だけ `deploy_task.sh` をsourceする。各helperのsubshellは親プロセスから関数定義を継承するため、テスト間の一時ファイル隔離を維持したまま再parseだけを除去できる。

リンク先の該当行: `tests/helpers/deploy_task_scaffold.bash` のコメント「Cache the 10k-line deploy library once per Bats test process.」および直後の `declare -F parse_deploy_task_args` 条件。

## 契約

- D7分類: behavior不変refactor。既存37テストのcoverageを維持する。
- 合格条件: FAIL 0、SKIP 0。期待値緩和・対象縮小なし。
- 関連教訓: [[L389]] — SKIPを成功扱いせず、実行件数・FAIL・SKIPを明示する。

origin: [[cmd_training_test_speed_test_deploy_task_ac_version__20260714224449]] -> [[repeated-source-parse]] -> [[deploy-task-ac-version-test-speed]]
