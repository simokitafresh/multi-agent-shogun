# 軍師 idle分析: WA傾向分析 2026-04-08

## 分析対象
karo_workarounds.yaml 直近16件(cmd_1796〜cmd_1801)

## 定量サマリ
- 全体: 16件中5件WA(31%)
- カテゴリ: verdict_override:2, split_deploy_ac_scope:2, process_hang_verification:1

## 因果鎖分析

### verdict_override (2件, cmd_karo_fix_flock_silent)
- 因果: AC推奨混入→忍者正FAIL→家老override
- 対処: GP-175 BLOCK(Level 4), GP-176形式検証(3層防御)
- 状態: **解決済み**。本日karo LGTM

### split_deploy_ac_scope (2件, cmd_1796)
- 因果: 分割配備→全AC注入→担当外AC=no→FAIL→家老手動修正
- LG014閾値: 3件未満→監視継続
- 仮説: deploy_task.shの分割配備時AC注入がフィルタしていない可能性
- 次回発生時: deploy_task.sh現物確認→GP提案

### process_hang_verification (1件, cmd_1796 saizo)
- 因果: WSL2 9p stall→忍者がCSV完全性を独立検証せず
- 孤立事象。インフラ起因(WSL2 NTFSレイヤー)

## GP状態
- in_progress: 0 (GP-125 resolved。cmd_1542完了済みだったのをtracker更新)
- proposed: 0
- karo_sent: 3 (GP-170/171/172)

## 結論
直近16件のWA率31%は改善傾向(過去: 100%→64%→33%→0%(N=5))。
GP-175/176の効果がverdict_override根絶として今後反映される見込み。
次の監視点: split_deploy_ac_scope再発有無。
