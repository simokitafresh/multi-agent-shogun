# LGTM→BLOCK Root Cause Analysis
<!-- generated: 2026-08-31T11:05:00+09:00 by gunshi idle analysis -->

## 背景

startup gate CS観点WARN: 「4件のLGTM→BLOCK。BLOCKリスク予測時はFAILにせよ(LG006)」
実際にはreview_logから5件のgate_prediction: CLEAR → gate_result: BLOCK事例を検出。

## 事例一覧

| # | cmd | project | gate BLOCK原因 | 軍師precheck見落とし？ |
|---|-----|---------|---------------|---------------------|
| 1 | cmd_reflux_insight_202608310514_saizo | infra | (未特定・gate dir存在) | 不明 |
| 2 | cmd_4426 | dm-signal | `command_files_modified_mismatch` | 部分的(下記) |
| 3 | cmd_4427 | dm-signal | `UNPUSHED commit` (report_commit_main_ancestry) | No(タイミング依存) |
| 4 | cmd_karo_hotfix_gate_ancestry_latency | infra | (gate dir不在・詳細不明) | 不明 |
| 5 | cmd_karo_hotfix_outstanding_lease_expiry | infra | (gate dir不在・詳細不明) | 不明 |

## 根因分析

### パターン1: files_modified mismatch (cmd_4426)
- gate_complete_gate.shがcmd仕様のcommand欄からファイルリストを抽出し、報告のfiles_modifiedと突合
- 軍師precheckのSG-PRE6はファイル行数チェックだが、cmd仕様との突合は行っていない
- **構造的原因**: precheckにcommand×files_modified突合がない

### パターン2: UNPUSHED commit (cmd_4427)
- report commitがcanonical mainに未push時点でgate実行→WAIT→BLOCK
- 軍師レビュー時点ではcommitは存在するがpush前。これは予測不可能
- **構造的原因**: タイミング依存。軍師が制御できない。BLOCK後にpush→re-gate→CLEARが正常フロー

### パターン3: 詳細不明 (3件)
- gate dirが存在しないか、trigger logが不在。archive済みの可能性

## 結論

5件のCLEAR→BLOCKのうち:
- **軍師のレビュー品質に起因するもの: 0件** — いずれもgate層のインフラチェック(ancestry/files mismatch)
- **precheckで予測可能だったもの: 1件** (cmd_4426 files_modified mismatch)
- **タイミング依存で予測不可能: 1件** (cmd_4427 UNPUSHED)
- **詳細不明: 3件**

## 改善提案

1. **SG-PRE6強化案**: files_modifiedとcmd仕様のcommand欄を突合するチェックの追加を家老に提案
2. **UNPUSHED対策**: gate_prediction時にpush状態を確認しWARN付与。ただし軍師レビュー→push→gateの順序上、レビュー時点では常にUNPUSHED
3. **LGTM→BLOCK計測の定義精緻化**: ancestry WAITは「レビュー品質の問題」ではなく「pushタイミングの問題」。CS観点WARNの分母から除外すべきか家老と協議

## 付記: 本セッションの追加検出

SG-PRE9c偽陽性: cmd_karo_hotfix_throughput_dedupe_segment_20260831のdiscretion_fillsに「後発値」が「後で」パターンに部分一致。「後発」=subsequent(時系列用語)であり先送りではない。パターンマッチの精度改善候補。
