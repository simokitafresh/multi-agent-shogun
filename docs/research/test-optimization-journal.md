# テスト最適化ジャーナル

殿の指示(2026-04-01): 700テストを10個ずつ改良。要不要判断→最適化/削除。記録は復元可能に。

## チャンク1: test_gunshi_notify.bats (3テスト)

**Before**: 3テスト、39秒(timeout)。cmd_complete_gate.shフル実行が原因。
**Action**: notify_gunshi_for_report()関数を直接テストに書き換え。gate全体実行を回避。
**After**: 3テスト、811ms。48倍高速化。
**削除**: なし（書き換えのみ）
**復元**: `git log --all -- tests/unit/test_gunshi_notify.bats`

## チャンク2: test_cmd_complete_gate.bats lessons_useful 4テスト (分析中)

**対象テスト**:
- `cmd_1045: lessons_useful string_list format blocks gate`
- `cmd_1045: lessons_useful dict_no_useful format blocks gate`
- `cmd_1045: lessons_useful proper format passes gate`
- `cmd_1045: lessons_useful null blocks gate (regression)`

**なぜなぜ判断**:
- 同一ロジックがtest_report_template_gate_compat.bats(33件)とtest_gate_report_autofix.bats(26件)で計59回テスト済み
- cmd_complete_gateを経由した統合テストとしての価値は低い（gate_report_format.shが分離済み）
- **判定: 不要（重複）→ 削除済み**
- **After**: 8テスト、40秒。既存FAIL1件(normalize ERROR、削除前から存在)
- 復元: `git log --all -- tests/unit/test_cmd_complete_gate.bats`

## チャンク3: test_deploy_task_ac_version.bats (31テスト) — 分析のみ

**現状**: 31テスト、33s TIMEOUT。1テスト=10秒。deploy_task.sh(2000行超)フル実行が原因。
**なぜなぜ**: deploy_task.shは巨大で関数抽出が困難。scaffoldも重い。
**判定**: 要（ac_version計算の正確性はデータ完全性に直結）。最適化にはdeploy_task.sh自体のリファクタが必要 → 別cmdで対応。
**今の最適化**: テスト不要のもの（重複）がないか次回チャンクで確認

## チャンク4: cmd_complete_gate系 timeout 4ファイル (24テスト) — 分析のみ

- test_cmd_complete_gate_ac_version.bats: 4テスト、全固有（重複なし）
- test_cmd_complete_gate_warning_levels.bats: 12テスト、全固有
- test_cmd_complete_gate_stk_status.bats: 3テスト、全固有
- test_cmd_complete_gate_review_quality.bats: 5テスト、全固有

**根因**: cmd_complete_gate.sh(3,985行)フル実行。関数は分離済みだがグローバル変数依存の可能性。
**判定**: 全テスト必要。最適化方針=チャンク1と同じ(関数source+単体呼び出し)。忍者修行cmdとして配備推奨。
**削除**: なし

## 共通ボトルネック分析

timeout 8ファイル中:
- **cmd_complete_gate.sh依存**: 5ファイル(gunshi_notify+gate本体+ac_version+warning+stk+review) → 関数抽出で解決
- **deploy_task.sh依存**: 2ファイル(ac_version+stale_field) → スクリプトリファクタ要
- 対処済み: gunshi_notify(チャンク1で48倍高速化)

## 進捗サマリ

| チャンク | ファイル | 改善 | テスト数 |
|---------|---------|------|---------|
| 1 | test_gunshi_notify.bats | 39s→811ms (48倍) | 3 書き換え |
| 2 | test_cmd_complete_gate.bats | 4テスト削除(重複) | 12→8 |
| 3 | test_deploy_task_ac_version.bats | 分析のみ(大型) | 31 据置 |
| 4 | test_cmd_complete_gate_stk_status.bats | 33s→2s (16倍) | 3 書き換え |
| 5 | test_cmd_complete_gate_ac_version.bats | 33s→1.5s (21倍) | 4 書き換え |
| 6 | test_cmd_complete_gate_review_quality.bats | 据置(メインフロー依存) | 5 据置 |
| 7 | test_cmd_complete_gate_warning_levels.bats | 据置(メインフロー依存) | 12 据置 |
| 8 | test_gate_metrics_model_labels.bats | 据置(gate統合テスト) | 2 据置 |
| 9 | test_deploy_task_ac_version.bats | 据置(大型) | 31 据置 |
| 10 | 5-10秒帯5ファイル | 適正範囲(0.5-1.2s/test) | 58 据置 |
| 累計 | 14テスト改善、115テスト分析済み | | 残り~585 |

## 次回アクション（/clear後の軍師へ）

**insightキュー登録済み(INS-20260401-195945318-0b0c)**。startup gateが表示する。

即着手: **update_status()関数抽出 → test_cmd_complete_gate_stk_status.bats書き換え**
- update_status()はYAML_FILE+SCRIPT_DIRのみ依存。抽出容易
- パターンはチャンク1(gunshi_notify: sed -n抽出→source→単体呼び出し)と同一
- 見込み: 3テスト×13秒=39秒 → 3秒以下

次: 同パターンで残り4ファイル(ac_version/warning_levels/review_quality/gate本体)を順次書き換え
その次: deploy_task.sh python3→bash+jq変換（大型。忍者修行cmdとして配備）
据置: 5-10秒帯(0.5-1.2s/test、適正範囲)

## 本日の全改善効果

| 対象 | Before | After | 削減 |
|------|--------|-------|------|
| Hook(半蔵cmd_1661) | Bash:2397ms, W/E:3876ms | Bash:172ms, W/E:202ms | **93%** |
| test_gunshi_notify(軍師) | 39s(timeout) | 811ms | **48倍** |
| 重複テスト(軍師) | 4テスト | 削除 | -4テスト |

## 全77ファイル計測（2026-04-02 軍師計測）

### 大物テスト（3秒超）

| # | ファイル | 時間 | テスト数 | ms/test | ボトルネック |
|---|---------|------|---------|---------|------------|
| 1 | test_deploy_task_ac_version | **22.2s** | 31 | 716 | deploy_task.sh 3159行フルsource |
| 2 | test_report_template_gate_compat | 7.3s | 45 | 162 | テスト数多(効率的) |
| 3 | test_pending_decision_write | 5.1s | 19 | 267 | python3依存 |
| 4 | test_build_system | 4.4s | 33 | 133 | 効率的 |
| 5 | test_deploy_task_engineering_preferences | **4.0s** | 3 | **1342** | deploy_task scaffold |
| 6 | test_archive_completed | 3.9s | 13 | 301 | 複数ファイル操作 |
| 7 | test_inbox_write | 3.8s | 16 | 238 | python3/flock |
| 8 | test_cli_adapter | 3.7s | 56 | 67 | 最効率 |
| 9 | test_report_field_set_bc_validation | 3.7s | 13 | 285 | python3依存 |
| 10 | test_gate_shogun_startup | 3.6s | 17 | 215 | gate複合チェック |
| 11 | test_deploy_task_recon_template | **3.5s** | 2 | **1747** | deploy_task scaffold |

### 健全度

| 状態 | ファイル数 |
|------|----------|
| PASS | 76 |
| FAIL | 1 (test_dashboard_auto_context_freshness — scaffold stub不足) |

### test_deploy_task_ac_version 設計図（C1-C6）

31テストを機能グループに分割し、deploy_task_fast→関数直接呼出に変換:

| チャンク | 対象グループ | テスト数 | 作業 | 見込み |
|---------|------------|---------|------|--------|
| C1 | 全テスト共通 | 31 | read_task_* python3→bash(field_get.sh)変換 | -7s |
| C2 | B: 実行制御 | 10 | inject_modifiers_only helper作成 | -5s |
| C3 | A: ac_version | 8 | inject_ac_version_only helper作成 | -4s |
| C4 | C: レポート | 4 | inject_report_only helper作成 | -2s |
| C5 | E: LK021 AC形式 | 5 | inject_task_modifiers.pyスキップ | -2.5s |
| C6 | D+F: 統合+他 | 5 | 統合テスト最適化 | -1.5s |

目標: 33s→10s以下

### 追加チャンク（C7-C10）

| チャンク | 対象 | 作業 | 見込み |
|---------|------|------|--------|
| C7 | engineering_preferences (3本) | deploy_task_fast→関数直接呼出 | 4s→0.5s |
| C8 | recon_template (2本) | 同上 | 3.5s→0.3s |
| C9 | pending_decision_write (19本) | python3呼出削減 | 5.1s→2s |
| C10 | report_field_set_bc_validation (13本) | python3→bash変換 | 3.7s→1.5s |

## スクリプトプロファイリング（2026-04-02 軍師計測）

### ボトルネック構造

| スクリプト | 実行時間 | 呼出頻度 | python3回数 | ボトルネック |
|-----------|---------|---------|------------|------------|
| context_freshness_check.sh | **6.2s** | dashboard更新毎 | 1(巨大) | 1578アーカイブYAML全量パース(WSL2 I/O) |
| dashboard_auto_section.sh | **3.0s** | cmd完了毎 | 間接 | context_freshness含む複数子プロセス |
| gate_shogun_startup.sh | **2.1s** | 将軍セッション毎 | 間接 | gate_lesson_health(1.2s)+17チェック |
| gate_lesson_health.sh | **1.2s** | startup/cmd完了 | 1+ | forループ×python3 YAML parse |
| inbox_write.sh | **0.26s** | **1 cmd=26+回** | 10 | deploy_task9回+ninja_monitor17回 |
| deploy_task.sh | **0.15s** | 配備毎 | 7 | python3 YAML操作 |

python3起動+yaml import = 40ms/回。1 cmdフルサイクル最大34回 = 1.36s純オーバーヘッド。

### 修行チャンク（S1-S6）

| チャンク | 対象 | 作業 | 見込み |
|---------|------|------|--------|
| S1 | context_freshness_check.sh | 日付フィルタ(直近N日のみパース) | 6.2s→0.5s |
| S2 | inbox_write.sh前半 | python3 5箇所→bash変換 | ×26=2.9s/cmd削減 |
| S3 | inbox_write.sh後半 | python3 5箇所→bash変換 | ×26=1.8s追加削減 |
| S4 | gate_lesson_health.sh | forループ→一括python3 | 1.2s→0.3s |
| S5 | dashboard_auto_section.sh | 子プロセス最適化+CI RED修正 | 3.0s→1.5s |
| S6 | 壊れたアーカイブYAML修復 | cmd_1308等の不正YAML | エラー排除 |

### 発見: 壊れたアーカイブYAML

`queue/archive/cmds/cmd_1308_completed_20260323.yaml` L42にYAML構文エラー(mapping values not allowed)。context_freshness_check.shの全量パース時にエラー発生。

## 修行実績（2026-04-02 修行サイクルL4 忍者実績）

| チャンク | 忍者 | cmd | Before | After | 改善率 | 状態 |
|---------|------|-----|--------|-------|--------|------|
| S2 | 才蔵 | R21 | 135.6ms/call | 85.9ms/call | 37%削減 | 完了。commit 05f363c |
| S1 | 疾風 | R22 | 6.2s(全量) | 1.861s(no-cache 7日) | 70%削減 | 完了。0.5s目標未達。commit d22cdf6 |
| — | 小太郎 | R21 | — | — | — | gate FIX hint追加(cmd_1677b)。commit 3b91e54 |

### S2実績詳細(才蔵)
inbox_write.sh hot path bash化。task_assigned/report_received/wake_upのpython3→bash変換。
wake_up: 135.6→85.9ms。task_assigned: 56.25→62.35ms(微増、許容)。bats 15/15。

### S1実績詳細(疾風)
context_freshness_check.sh archive scan修正。実アーカイブYAMLがネスト形(`commands.<cmd_id>.project`)なのにトップレベル`project:`前提で読んでいた構造不整合を修正。先頭80行軽量抽出に変換。default(cache有): 0.087s。no-cache(7日): 1.861s。0.5s目標には追加最適化要。
