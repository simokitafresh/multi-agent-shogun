# cmd_3855 教訓注入精度の再計測

## §1 一次証跡

- 実行時点: 2026-07-12 01:44 JST
- 母集団: `queue/reports/*.yaml` をmtime降順に最大20件（実在11件）
- 集計対象: `lessons_useful[].id/useful`
- 修正前全体: 41注入、10 useful、24.4%

| lesson | 注入 | useful | useful率 | 修正前タグ/条件 | 修正後タグ/条件 |
|---|---:|---:|---:|---|---|
| L343 | 5 | 0 | 0% | communication,bash,yaml,lesson,reporting | lesson-metrics,yaml-parser,report-parser |
| L159 | 3 | 0 | 0% | recon固定allowlist | large-recon,parallel-agent,independent-axes + 大規模/5軸等の明示時のみallowlist |
| L338 | 2 | 0 | 0% | yaml,monitor | daemon-performance,python-inline,yaml-read |
| L355 | 2 | 0 | 0% | bash,yaml | bash-regex,yaml-parser,workaround-detection |
| L548 | 2 | 0 | 0% | recon-yaml-dump | operational-yaml,yaml-serialization,recon-script |

## §2 修正後シミュレーション

- 無関係な通常infra task: 上記5件の注入5→0、修正前母集団を同じとする即時シミュレーションは10/36=27.8%（+3.4pt）。
- 5軸以上の独立偵察task: L159のみ条件付き候補に復帰する。
- タグ差分とL159の条件分岐は単体テストで固定する。

### cmd_3890 再検証（2026-07-14 00:26 JST）

- 正本タグ: 5/5件が修正後タグと一致。
- 無関係な通常infra task: 対象5教訓の注入0/5。修正前5/5から5件減。
- 複数軸明示の大規模偵察task: L159の条件付き候補復帰=yes。
- 同一母集団での即時シミュレーション: 10/41=24.4% → 10/36=27.8%（+3.4pt）。
- 指定suite: `bats tests/unit/test_deploy_task_yaml_injection.bats` = 30 PASS / 0 FAIL / 0 SKIP。
