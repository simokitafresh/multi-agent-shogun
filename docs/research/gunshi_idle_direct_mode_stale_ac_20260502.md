# deploy_task.sh --directモード stale AC残留バグ分析

- 分析者: 軍師 (gunshi)
- 日付: 2026-05-02
- 起源: 殿指摘「報告YAMLの問題は家老の配備インフラバグあるんじゃないか？」→ LG014適用

## 根因

`deploy_task.sh --direct`モードで`resolve_cmd_to_task`がスキップ(L4762)されるため、**parent_cmdが旧値のまま更新されない**。

後続inject処理(report_filename, same_ninja_redeploy_warn, report_template等)がparent_cmd(旧値)ベースで動作し、旧cmdの設定を再注入する。

## 2パターンの発現

### パターン1: CMD_ID≠existing parent_cmd (hanzo)
- deploy_task.sh --direct hanzo cmd_2481_ac1_ccg
- stale reset: CMD_ID(cmd_2481_ac1_ccg) ≠ existing(cmd_karo_ci_fix_bulletin_flaky) → ACクリア ✓
- resolve_cmd_to_task: スキップ → parent_cmd未更新 ✗
- 結果: parent_cmd=cmd_karo_ci_fix_bulletin_flaky → report_filename=hanzo_report_cmd_karo_ci_fix_bulletin_flaky.yaml注入
- 忍者は旧cmdの文脈で作業

### パターン2: CMD_ID==existing parent_cmd (tobisaru)
- deploy_task.sh --direct tobisaru cmd_karo_dashboard_cmdid_fix
- stale reset: CMD_ID(cmd_karo_dashboard_cmdid_fix) == existing → **ACクリアされない**
- resolve_cmd_to_task: スキップ → parent_cmd未更新
- 結果: 前cmd(cmd_karo_dashboard_cmdid_fix)のAC+description全残留
- 忍者は前cmdを再実行

## 証拠(deploy_task.log)

```
[2026-05-02 21:29:01] direct_mode: skipping resolve_cmd_to_task for cmd_2481_ac1_ccg
[2026-05-02 21:29:01] same_ninja_redeploy_warn: cmd=cmd_karo_ci_fix_bulletin_flaky
[2026-05-02 21:29:02] [REPORT_FN] Injected report_filename=hanzo_report_cmd_karo_ci_fix_bulletin_flaky.yaml

[2026-05-02 20:35:40] direct_mode: skipping resolve_cmd_to_task for cmd_karo_dashboard_cmdid_fix
```

## 影響

- cmd_2481で2忍者分(hanzo+tobisaru)のトークン浪費
- karo_workaround 2件(L6208, L6224)
- saizo: STALE TASK INVALID(テンプレート初期状態)で報告空提出

## 修正方針

`--direct`モード(L4751-4762)で`resolve_cmd_to_task`スキップ後に、`--cmd`モード(L4766-4778)と同等のparent_cmd/task_id/status設定を追加。

```bash
# L4762の後に追加:
# --directモードでもparent_cmd更新を保証(cmd_2481事故修正)
yaml_field_set "$task_yaml" "task" "parent_cmd" "$CMD_ID"
yaml_field_set "$task_yaml" "task" "task_id" "${CMD_ID}_${TASK_TYPE:-normal}"
yaml_field_set "$task_yaml" "task" "status" "assigned"
```

ただし`CMD_ID`がtask_id(cmd_2481_ac1_ccg)の場合、parent_cmdとして不適切。
`--direct`の引数設計自体の見直しが必要(parent_cmd vs task_id の区別)。

## 根本問題

`--direct`モードは「shogun_to_karo.yamlにないcmdの配備」を想定しているが、parent_cmd更新を省略したため、deploy_task.shの後続処理(inject系)が全て旧cmd文脈で動作する構造的欠陥。

generated: 2026-05-02T21:55:00+09:00
trigger: 殿直接指摘
