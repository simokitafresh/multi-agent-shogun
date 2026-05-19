# セマンティック監査: backup-first + project scope (cmd_2851以降) — 2026-05-19

## 対象スクリプト (4件)

| ファイル | 変更内容 |
|----------|---------|
| scripts/cmd_quality_log.sh | PROJECT_IDフィールド追加 |
| scripts/cmd_save.sh | WARN累計project別スコープ(cmd_2851) |
| scripts/lib/inject_task_modifiers.py | DB操作検出+バックアップ注入(cmd_karo_backup_first_l5) |
| scripts/ninja_monitor.sh | stale key cleanup追加(修行cmd) |

## 5カテゴリ監査結果

### silent_failure
- 10件指摘 → 全件FALSE POSITIVE
- `|| true`パターン(6件): projectフィールドは補助情報。抽出失敗時もcmd_save継続が正しい設計
- `except Exception: return ""`(1件): 品質ログのproject解決は補助機能。YAML破損でcmd_saveをBLOCKすべきでない
- `except OSError: pass`(1件): tmpfile cleanup失敗は標準的許容パターン
- ninja_monitor `2>/dev/null`(1件): 算術テストのstderr抑制。無害

### state_transition
- 6件指摘 → 全件FALSE POSITIVE
- extract_project redundant return(1件): 安全な冗長フォールバック
- build_pane_head_tail_excerpt(1件): all_lines/tail_linesは独立配列として設計上正しい
- cleanup empty array(1件): 空配列のイテレーションは安全(0回ループ)

### race_condition
- 3件指摘 → 全件FALSE POSITIVE
- bash unset during iteration(1件): `for key in "${!arr[@]}"` はキーリストを展開時に固定。既存パターン(L2034-2036)と同一
- inject_task_modifiers TOCTOU(1件): try/except保護済み。parent不在→空dict→注入なしで安全
- glob expansion(1件): target_cmdは内部生成(cmd_XXXX形式)。ユーザー入力経路なし

### implicit_assumption
- 2件指摘 → 全件FALSE POSITIVE/P3
- legacy fallback "infra"(1件): 設計意図明記(L1479-1481コメント)。cmd_2851の核心設計
- DB_OPERATION_RE偽陽性(1件): 安全側に倒す設計(Level5=過剰検出許容、見逃し不可)。P3

### side_effect
- 6件指摘 → 全件FALSE POSITIVE
- 非atomic更新(1件): deploy_task.shが書込み完了後に配備。途中readなし
- `|| true`パターン(3件): silent_failureと同一の意図的設計
- DB_OPERATION_RE descriptionマッチ(1件): P3(安全側)
- cleanup active依存(1件): active配列は毎サイクル更新。更新失敗→全cleanup=安全側

## semantic_index

- **Drift**: 2件修正済み(D0)
  - `scripts/hooks/pre_bash_combined_guard.sh` → `.claude/hooks/pre-bash-combined.sh`
  - `tests/test_pre_bash_destructive_approval.bats` → `tests/unit/`
- **Gap**: 2件(insight記録済み)
  - `cmd_quality_log.sh`、`inject_task_modifiers.py` 未登録

## 因果チェーン

```
cmd_2851(WARN project scope) + cmd_karo_backup_first_l5(DB backup injection)
  → 4スクリプト変更
  → 3エージェント並列監査(27件指摘)
  → 全件FP/P3(構造的バグなし)
  → drift 2件D0修正 + gap 2件insight記録
```

## 副作用スキャン (cmd_2852 + cmd_2854)

### deploy_task.sh (666bba94): CLEAN
sed→awk refactorは正常。insert_task_block_before_descriptionのawk state machine正しい。

### cmd_save.sh (98ad2351): CLEAN (3件FP/P3)
- P1(FP): regex tsx|ts順序修正は意図的修正(cmd_karo_regex_order_fix)。副作用ではない
- P2→P3: make_quality_log_scan_fileのawk in_entryリセットなし。ただしcmd_design_quality.yamlはentries:のみ(ルートキー1件)。実データでYAML破損なし
- P2→P3: dirname "test.py"→"."→"/project/."。パス解決は正常。表示のみ

## 結論

全4スクリプト + 副作用スキャン **CLEAN**。前セッション(9commit全clean)に続き健全。
