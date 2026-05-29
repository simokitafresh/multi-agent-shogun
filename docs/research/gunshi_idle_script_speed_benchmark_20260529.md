# スクリプト速度ベンチマーク全量計測
<!-- generated: 2026-05-29T12:00+09:00 by gunshi idle analysis -->
<!-- trigger: 殿指示「スクリプト実行速度がボトルネックになっていないか洗脳監査」 -->

## 計測条件
- 環境: WSL2 Linux 6.6.87.1 / NTFS (/mnt/c)
- 計測方法: `time bash <script>` 実測
- 計測日: 2026-05-29

## 改善結果サマリ

| cmd | 対象 | before | after | 削減率 |
|-----|------|--------|-------|--------|
| cmd_3091 | deploy_task.sh完走率 | 0.5%(1/209) | 100%(post-fix) | grep -c→awk |
| cmd_3094 | cmd_complete_gate lesson score | 43秒 | 0.17秒 | 99.6% |
| cmd_3096 | gate_gunshi_report_precheck | 52秒 | 13-17秒 | 67-73% |
| cmd_3097 | gate_gunshi_startup | 14.98秒 | 4.39秒 | 71% |
| (外部) | context_freshness_check | 10.9秒 | 4.3秒 | 60%(並列化+timeout短縮) |

## ベースライン計測値(改善前)

| # | スクリプト | 実測時間 | 発火頻度 |
|---|-----------|---------|---------|
| 1 | cmd_complete_gate.sh (fresh) | 220秒 | cmd完了毎 |
| 2 | gate_gunshi_report_precheck.sh | 76.6秒 | レビュー毎 |
| 3 | gate_gunshi_startup.sh | 23.4秒 | セッション起動時 |
| 4 | gate_shogun_startup.sh | 20.8秒 | セッション起動時 |
| 5 | gate_karo_startup.sh | 14.9秒 | セッション起動時 |
| 6 | context_freshness_check.sh | 10.9秒 | dashboard+cmd保存時 |
| 7 | gate_gunshi_cs_checklist.sh | 5.2秒 | precheck内部 |
| 8 | cmd_save.sh | 2.9秒 | cmd保存時 |
| 9 | prompt_state_inject.sh | 0.2-1.2秒 | 毎ターン全エージェント |
| 10 | gate_report_format.sh | 1.2秒 | 報告毎 |

## 正常域
- 全PreToolUse hooks: 0.01-0.08秒
- 全PostToolUse hooks: 0.01-0.04秒
- inbox_write.sh: 0.27秒

## 洗脳検出
- **#1早期終了**: cached(0.03秒)で「速い」→fresh(220秒)が真のボトルネック。7333倍差
- **#1早期終了**: hookが速い→gateの遅さを見落とし
- **#8完了急ぎ**: cmd_3089 draft HIGH→silent failure見落とし

## 隠れインフラバグ(同セッション発見)
1. Codex delivery 45%未検証(97/214件) → cmd_3102
2. action omitted 114件 → cmd_3102
3. _ac_task_id empty 37件 → cmd_3102
4. git timeout 3ファイル(obsidian-link/memory-db-queries/codd) → LOW
5. deploy_task.sh pre-fix未実行 → 修正済み(cmd_3091)

## 因果リンク
- → [[cmd_3091]] deploy_task完走率修正
- → [[cmd_3094]] cmd_complete_gate速度改善
- → [[cmd_3096]] precheck速度改善
- → [[cmd_3097]] startup gate速度改善
- → [[cmd_3102]] 隠れインフラバグ修正
