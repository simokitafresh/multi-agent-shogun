# インフラ衛生分析 2026-04-25

## 分析者: 軍師(gunshi)

## 1. review_gate.done不在42件 (GP-227で根因修正)

根因: detect_task_types()がHAS_IMPLEMENT=falseの場合、review_gateがALL_GATESに入らず
→ preflight未実行 → review_gate.done未作成 → inbox_write.shのLGTMでも`if [ -f ]`ガードで未生成
→ archive_completed.shがreview_gate.done必須でスキップ → 報告永久滞留

修正: GP-227(inbox_write.sh mkdir -p + ガード除去)。commit c7245aaf。
遡及修復: 42件のreview_gate.doneを手動生成。160/188報告がアーカイブ可能に。

## 2. BLOCK率47%(直近100件 cmd_design_quality)

| 理由 | 件数 |
|------|------|
| draft_lessons(教訓未登録) | 8 |
| report_format(忍者報告品質) | 10 |
| assumptions source不在 | 4 |
| binary_checks_fail | 2 |
| WARN累計昇格 | 91(累計) |

assumptions source不在: 非標準format(claim単一文字列、sourceフィールドなし)が原因。

## 3. 教訓有用率ベースライン

全体: 20.3% (55/271 feedback)
忍者別: saizo 33.8% > hayate 22.4% > kotaro 11.1% > kagemaru 7.4% > hanzo 0.0%
有用率0%教訓(3+回注入): 14件 → useful_rate=0.0%除外機構(L2430)で今後は注入されない

## 4. GP-223/225/226/227の効果予測

| GP | 修正内容 | 期待効果 |
|----|---------|---------|
| GP-223 | purpose/target_path/context_files追加 | keyword 3→11(実測) |
| GP-225 | ASCII↔CJK境界+アクロニム例外 | CDP教訓 0→3スコア |
| GP-226 | restart_watchers.sh ヘルスチェック | 復旧偽陽性防止 |
| GP-227 | inbox_write.sh review_gate.done不在時生成 | 42件アーカイブ解放 |
