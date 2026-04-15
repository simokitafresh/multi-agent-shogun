# テスト統合整理 CoDD設計書

## 背景
テスト964件(111ファイル)がボトルネック化。断片化・配置不統一で保守コスト増大。

## 現状定量データ(2026-04-15実測)

### 規模
| カテゴリ | ファイル数 | テスト数 | CI | 備考 |
|----------|-----------|---------|-----|------|
| unit/ | 92 | 884 | ✓ | メイン |
| tests/*.bats(top-level) | 7 | 62 | ✓ | 配置不統一 |
| e2e/ | 12 | 18 | - | 別管理 |
| test_helper/(3rd-party) | 28 | 295 | - | bats-assert/support |
| **合計** | **139** | **1259** | | |
| **CI対象** | **99** | **946** | ✓ | unit + top-level |

### 断片化(Big 3)
| 対象 | 現ファイル数 | テスト数 | →統合後 | 削減 |
|------|-------------|---------|---------|------|
| deploy_task.sh | 16 | 118 | 7 | -9 |
| cmd_save.sh | 10 | 96 | 3 | -7 |
| cmd_complete_gate.sh | 6 | 41 | 2 | -4 |
| **小計** | **32** | **255** | **12** | **-20** |

### 実行時間ボトルネック(unit/ Top 10, sequential sum)
| ファイル | 時間 | テスト数 |
|---------|------|---------|
| test_deploy_task_ac_version | 22.0s | 35 |
| test_report_template_gate_compat | 14.0s | 47 |
| test_lesson_write | 6.0s | 22 |
| test_gate_karo_startup | 5.6s | 12 |
| test_cmd_complete_gate_review_quality | 5.3s | 5 |
| test_inbox_write | 4.9s | 19 |
| test_cli_adapter | 4.8s | 57 |
| test_gate_shogun_startup | 4.8s | 17 |
| test_deploy_task_monthly_and_scout_exempt | 4.3s | 4 |
| test_cmd_save | 4.2s | 47 |

### Dead Test調査結果
**Dead test = 0件。** 全111ファイルの対象スクリプトが存在・稼働中。
- test_cmd_1408_defensive_coding: cmd_complete_gate.sh等のセキュリティ修正を検証。対象コード存続 → KEEP
- test_build_system: build_instructions.sh(pre-commitフック利用)。16+ファイル生成 → KEEP
- test_cli_adapter: cli_adapter.sh(ninja_monitor/reset_layout/switch_cli_modeが利用)。57テスト → KEEP
- test_cdp_chrome_cleanup: ninja_monitorが利用するWSL2固有クリーンアップ → KEEP
- test_cmd_complete_gate_warning_levels: 49 skip行はBATS skip指示ではなくgate内ステータスコード → 全15テスト稼働中

---

## 統合計画

### A. deploy_task.sh (16→7ファイル)

**統合ファイル1: test_deploy_task_template_generation.bats** (~15 tests)
- ← test_deploy_task_gitignore_commit_check (2)
- ← test_deploy_task_monthly_and_scout_exempt (4)
- ← test_deploy_task_recon_template (2)
- ← test_deploy_task_handwritten_bc (6, テンプレート部分)

**統合ファイル2: test_deploy_task_ac_handling.bats** (~50 tests)
- ← test_deploy_task_ac_verify (8)
- ← test_deploy_task_ac_version (35)
- ← test_deploy_task_handwritten_bc (AC抽出部分)

**統合ファイル3: test_deploy_task_lifecycle.bats** (~40 tests)
- ← test_deploy_task_double_deploy_guard (11)
- ← test_deploy_task_stale_field_reset (2)
- ← test_deploy_task_stale_report_verdict (11)
- ← test_deploy_task_engineering_preferences (3)
- ← test_deploy_task_gate_blocks (5)
- ← test_deploy_task_gate_fail_top3 (4)

**スタンドアロン維持 (4ファイル)**
- test_deploy_task_match_ninja (8) — 型安全ユーティリティ
- test_deploy_task_target_files (8) — 教訓フィルタ
- test_deploy_task_useful_rate_decay (6) — スコアリング
- test_deploy_task_recent_noncmd_commit_warn (3) — git履歴

### B. cmd_save.sh (10→3ファイル)

**統合ファイル1: test_cmd_save_quality_gates.bats** (~65 tests)
- ← test_cmd_save.bats (47, Check 1-6,11,20)
- ← test_cmd_save_q5.bats (13, q5免除条件)
- ← test_cmd_save_q7_definition.bats (2)
- ← test_cmd_save_tool_growth.bats (3)

**統合ファイル2: test_cmd_save_ac_checks.bats** (~21 tests)
- ← tests/test_cmd_save_ac_paths.bats (5, top-level→unit/移動)
- ← tests/test_cmd_save_content_dup.bats (5, top-level→unit/移動)
- ← test_cmd_save_archive_dup.bats (3)
- ← test_cmd_save_ac_param_sufficiency.bats (8)

**統合ファイル3: test_cmd_save_specialized.bats** (~10 tests)
- ← tests/test_cmd_save_q7_branch.bats (6, top-level→unit/移動)
- ← test_cmd_save_param_space_against_results.bats (4)

### C. cmd_complete_gate.sh (6→2ファイル)

**統合ファイル1: test_cmd_complete_gate_core.bats** (~28 tests)
- ← test_cmd_complete_gate.bats (9)
- ← test_cmd_complete_gate_warning_levels.bats (15)
- ← test_cmd_complete_gate_ac_version.bats (4)

**統合ファイル2: test_cmd_complete_gate_subsystems.bats** (~13 tests)
- ← test_cmd_complete_gate_review_quality.bats (5)
- ← test_cmd_complete_gate_gs_bench.bats (5)
- ← test_cmd_complete_gate_stk_status.bats (3)

### D. top-level整理 (7→4ファイル)

3件はcmd_save統合で消化(上記B)。残り4件:
- test_block_destructive.bats (17) → unit/に移動
- test_gate_report_format.bats (15) → unit/に移動
- test_insight_sanitize.bats (8) → unit/に移動
- test_safe_section_replace.bats (6) → unit/に移動

---

## 統合前後サマリ

| 項目 | Before | After | 削減 |
|------|--------|-------|------|
| deploy_task ファイル | 16 | 7 | -9 (56%) |
| cmd_save ファイル | 10 | 3 | -7 (70%) |
| cmd_complete_gate ファイル | 6 | 2 | -4 (67%) |
| top-level ファイル | 7 | 0 | -7 (100%) |
| **CI対象ファイル合計** | **99** | **76** | **-23 (23%)** |
| テスト数 | 946 | 946 | 0 (カバレッジ維持) |

---

## 実施順序

1. **top-level 4ファイル → unit/移動** (最も安全。テスト内容変更なし)
2. **cmd_save 10→3統合** (中規模。setup_file共有化)
3. **cmd_complete_gate 6→2統合** (中規模)
4. **deploy_task 16→7統合** (最大規模。scaffold活用)
5. **CI緑確認** (全ステップ後にbats tests/unit/ --timing)

## 制約
- テスト数削減禁止（ファイル統合のみ。テストケースは全保持）
- CI緑維持（各ステップ後に確認）
- pre-push hook動作維持
