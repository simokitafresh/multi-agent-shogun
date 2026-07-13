# cmd_3891 skeleton / deploy時間契約整合

## 結論

`scripts/cmd_skeleton.sh`は`estimated_minutes: 10`と、10分超では`split_decision`、15分超では`execution_env.long_runtime_reason`および`measured_runtime_sec`が必要というガイドを生成する。これにより雛形起点の最小cmdは、家老による追加補完なしで`deploy_task.sh`のTEN_MIN_CONTRACTを通過する。

## 一次検証

- 雛形出力: `tests/unit/test_cmd_skeleton.bats`で欄と全ガイド文言を固定。
- 隔離fixture: 雛形出力を一時queueへ置き、`deploy_task.sh`内の`deploy_task_ten_min_contract_precheck`と同じ正数境界に対して`estimated_minutes=10`がPASSすることを実測。
- 運用queueは変更せず、追加補完は0件。

origin: [[karo_escalation_20260714_0025_deploy_contract_WA]] -> [[雛形と配備契約の欄不整合]] -> [[skeleton雛形へ時間契約欄追加]]
