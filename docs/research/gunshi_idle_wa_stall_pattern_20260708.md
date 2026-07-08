# WA Stall Pattern Analysis — report_yaml_format + agent_stall_recovery LG014到達
<!-- generated: 2026-07-08T22:05:00+09:00 by gunshi idle analysis -->

## 計測結果

- 直近10件中WA=5件(50%)、clean=0件(前回20260612: 20%)
- LG014閾値到達: report_yaml_format 3件、agent_stall_recovery 3件

## カテゴリ分布

| category | 件数 | 忍者 |
|----------|------|------|
| report_yaml_format | 3 | kotaro×2, kagemaru×1 |
| agent_stall_recovery | 3 | hayate, saizo, kotaro |
| uncategorized | 1 | hanzo |
| gate_metadata_gap | 1 | hayate |

## report_yaml_format 3件の根因分析

1. **kotaro cmd_reflux_promotion**: deploy_task non-blocking fail→最小task YAML→report_path/ac_version欠落+AC行未引用コロンでYAML構文破壊
   - 根因: deploy_task.sh non-blocking失敗時のfallback template品質
2. **kotaro cmd_reflux_insight**: 報告YAML未完了(status/verdict/bc未記入)でidle化→家老D0補完
   - 根因: 忍者stall(作業途中停止)
3. **kagemaru cmd_karo_ci_fix**: report gate PASS後にpane Workingで停滞→家老がtask YAML done補正
   - 根因: 忍者stall(report完了→task完了遷移の間で停止)

## agent_stall_recovery 3件の根因分析

1. **hayate cmd_reflux_insight**: diff確認後9分以上同一状態で停止
2. **saizo cmd_karo_hotfix_reflux_handoff**: failed taskが1h45m未回収
3. **saizo cmd_reflux_insight**: semantic index更新後に報告YAML未完成で停止

## LG014判定: インフラバグか？

### report_yaml_format
- deploy_task.sh non-blocking fail時のfallback template: **インフラ側の穴**(report_path/ac_version欠落)
- 残り2件はstall起因: インフラバグではなくモデル能力限界

### agent_stall_recovery
- ninja_monitorのSTALL検知→家老escalationは正常動作中
- stall自体はGPT忍者のCTX枯渇/処理遅延: **モデル能力問題**
- 自動recovery導線(stall→報告自動補完)は不在だが、報告内容の推測は消火構造のため自動化不適

## 結論

1. **deploy_task.sh non-blocking fail時のfallback template品質**は道具側の穴(report_path/ac_version欠落)→改善余地あり
2. **stall後の報告未完了**はモデル能力問題。修行サイクル(L1)でGPT忍者のreport完成率向上が正攻法
3. WA率50%(前回20%→今回50%)は悪化だが、直近WA 5件中4件がstall起因で構造的再発リスクはモデル依存
4. deploy_task.sh fallback template改善は家老管轄。lesson_candidate送信で還流

## 因果リンク
- -> [[LG014]] 同一category 3件以上→道具のバグ仮説(report_yaml_formatで部分的に該当)
- -> [[deploy_task.sh]] non-blocking fail時のfallback template品質
- -> [[training-cycle]] L1修行でGPT忍者のreport完成率向上
- -> [[karo_workarounds]] 直近10件分析(2026-07-08)
