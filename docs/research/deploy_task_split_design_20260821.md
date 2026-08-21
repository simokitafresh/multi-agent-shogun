# deploy_task.sh 分割設計 v1.0 — 2026-08-21T23:23:00+09:00

## 対象と設計原則

- 対象: `scripts/deploy_task.sh`（2026-08-21T04:42:39+09:00 snapshot: 14,613行 / complexity 29,508）。
- 最優先理由: 優先度台帳で complexity・行数・git変更頻度が各1位。
- 目的: 配備の外部契約（CLI、task YAMLの注入、inbox送信、report template、post verify）を維持したまま、責務ごとの変更半径を縮める。
- 制約: 本cmdではコードを変更しない。分割実装・テスト移設・削除は後続cmdで行う。
- Bashの動的スコープ、環境変数、共有lock、atomic YAML writer、ログ形式は分割後も既存契約として扱う。

## As-Isの責務境界（関数クラスタ）

| cluster | 現行行範囲 | 責務 | 主な関数 | 分割先候補 |
|---|---:|---|---|---|
| A | 1–202 | self-snapshot、実行root、共通source、ログ、CLI入口ガード | `deploy_task_guard_yaml_arg_order`, `deploy_task_guard_direct_yaml_misuse`, `log` | `scripts/deploy_task/bootstrap.sh` |
| B | 203–1175 | wave/owner cache、lock、task YAML transaction、deadline、deferred queue | `deploy_task_wave_cache`, `deploy_task_acquire_ninja_lock`, `deploy_task_yaml_transaction_begin`, `flush_target`, `deploy_task_drain_deferred` | `scripts/deploy_task/state.sh`, `scripts/deploy_task/transaction.sh` |
| C | 1176–1759 | report/RC再配備判定、inbox delivery evidence、post-deploy verify、fallback | `deploy_task_continuation_contract_valid`, `deploy_task_has_formal_karo_rc_for_report`, `safe_inbox_write`, `deploy_task_post_deploy_verify` | `scripts/deploy_task/delivery.sh` |
| D | 1760–2526 | 引数解析、pane/idle検査、stale reset、direct YAML、cmd source解決 | `parse_deploy_task_args`, `resolve_pane`, `reset_stale_fields`, `resolve_cmd_to_task` | `scripts/deploy_task/resolve.sh` |
| E | 2527–4090 | task YAML正規化、AC/parent contract、causal/variation、lesson ID注入 | `inject_cmd_time_contract`, `normalize_task_yaml`, `inject_ac_version`, `inject_parent_contract`, `verify_ac_consistency`, `inject_causal_verification_template` | `scripts/deploy_task/task_contract.sh` |
| F | 4091–6362 | report identity、generation、scope、template、publication lock/pointer | `deploy_task_publish_report_metadata`, `generate_report_template`, `deploy_task_report_publication_locked`, `ensure_report_template_completeness` | `scripts/deploy_task/report.sh` |
| G | 6403–7982 | semantic/memory/causal/skill/model/context injection、production invariants | `inject_semantic_concepts`, `inject_memory_db_context`, `inject_causal_links`, `inject_standard_skills`, `inject_production_invariants` | `scripts/deploy_task/context_injection.sh` |
| H | 7983–11526 | lesson/workaround、target path、test necessity、role/model、execution control modifiers | `inject_related_lessons`, `inject_workaround_pattern_lessons`, `inject_task_modifiers`, `deploy_task_test_necessity_precheck`, `inject_execution_controls` | `scripts/deploy_task/modifiers.sh` |
| I | 11527–14007 | preflight、remote-tip worktree、freshness/scout/quality/RC gates、dispatch mutation | `preflight_gate_artifacts`, `check_context_freshness`, `check_entrance_gate`, `check_scout_gate`, `deploy_task_apply_task_mutations` | `scripts/deploy_task/preflight.sh`, `scripts/deploy_task/gates.sh` |
| J | 14008–14642 | orchestrationとdelivery/post-delivery順序 | `deploy_task_main` | `scripts/deploy_task/main.sh`（薄い互換wrapper） |

### 依存方向

```text
bootstrap
  -> state/transaction
  -> resolve
  -> task_contract
  -> context_injection + modifiers
  -> report
  -> preflight/gates
  -> main orchestration
  -> delivery/post_verify
```

実装時は低層から高層へのsource順を固定する。`main.sh` は各moduleをsourceして既存の`deploy_task_main "$@"`を呼ぶだけにし、module間の暗黙source順依存を増やさない。

## To-Beファイル構成

```text
scripts/deploy_task.sh                 # 既存CLI互換wrapper。self-snapshotとmain呼出しのみ
scripts/deploy_task/
  bootstrap.sh                         # A: root/snapshot/log/arg guard
  state.sh                             # B: cache/locks/deadline/deferred state
  transaction.sh                       # B: YAML transaction/cleanup
  resolve.sh                            # D: CLI/pane/stale/direct/cmd resolution
  task_contract.sh                      # E: normalization/AC/parent/causal contract
  context_injection.sh                 # G: semantic/memory/causal/skills/context
  modifiers.sh                         # H: lessons/workaround/target/execution modifiers
  report.sh                             # F: report template/identity/publication
  preflight.sh                          # I: source/worktree/freshness/scout preflight
  gates.sh                              # I: quality/RC/dispatch gates
  delivery.sh                           # C: inbox/post-verify/fallback/deferred delivery
  main.sh                               # J: phase order only
```

分割単位は関数単位であり、巨大関数内部の部分抽出を先に行わない。各moduleは同一shell processでsourceされるため、既存のglobal変数・関数参照を段階移設できる。将来の完全分離（subprocess化）は別設計とする。

## 既存呼出し元と互換維持

### 呼出し元の調査コマンド

```bash
rg -l --glob '*.sh' --glob '*.bats' --glob '*.py' 'deploy_task\.sh' . | sort
```

### 生出力

```text
./.claude/hooks/post-bash-combined.sh
./.claude/hooks/post-edit-instruction-hook-consistency.sh
./.claude/hooks/pre-write-edit-combined.sh
./.claude/hooks/pre-write-read-tracker.sh
./scripts/affected_tests.sh
./scripts/archive_completed.sh
./scripts/auto_deploy_next.sh
./scripts/campaign_lane_shard_item.sh
./scripts/cmd_complete_gate.sh
./scripts/cmd_delegate.sh
./scripts/cmd_save.sh
./scripts/cmd_skeleton.sh
./scripts/deploy_task.sh
./scripts/deploy_training.sh
./scripts/draft_review_approval.sh
./scripts/gates/gate_gunshi_report_precheck.sh
./scripts/gates/gate_gunshi_report_precheck_engine.py
./scripts/gates/gate_hot_path_no_sync_io.sh
./scripts/gates/gate_karo_startup.sh
./scripts/gates/gate_report_format_main.py
./scripts/inbox_write.sh
./scripts/lib/ctx_utils.sh
./scripts/lib/deploy_task_preflight_fast.py
./scripts/lib/firefighting_keywords.sh
./scripts/lib/inject_task_modifiers.py
./scripts/lib/pane_lookup.sh
./scripts/lib/parent_cmd_contract.py
./scripts/lib/report_contract_test_selector.sh
./scripts/ninja_monitor.sh
./scripts/pytest_speed_task_generator.sh
./scripts/ralph_loop_closer.sh
./scripts/record_lesson_feedback.sh
./scripts/report_field_set.sh
./scripts/skill_freshness_adapter.sh
./scripts/skill_recommend_metrics.sh
./scripts/test_select.sh
./scripts/test_speed_task_generator.sh
./scripts/throughput_scan.sh
./scripts/training_task_generator.sh
./tools/bash_speed_training.sh
```

テスト呼出し元は上記出力に加えて `tests/unit/test_deploy_task*.bats` と関連fixture群である（調査コマンドは指定どおりの生出力を保存し、設計判断では本体呼出しとテスト呼出しを同一互換面として扱う）。

### 互換契約

1. `bash scripts/deploy_task.sh [--direct] <ninja> [cmd_id] [message] [type] [from]` の引数形、終了コード、標準出力/標準エラーの主要ログ語彙をwrapperで維持する。
2. `DEPLOY_TASK_*`、`SCRIPT_DIR`、`DEPLOY_TASK_ROOT_OVERRIDE` などの既存環境変数をmodule境界で再定義しない。共有変数は `bootstrap.sh` の宣言表を正本にする。
3. `deploy_task_main`、`safe_inbox_write`、`generate_report_template`、`resolve_cmd_to_task` など、外部テストがsource後に直接呼ぶ関数は当面wrapperからexport相当（source済み状態）で残す。
4. YAML更新は既存の`yaml_field_set.sh`/batch、report更新は既存のreport helperを使い、moduleごとに別writerを作らない。
5. `deploy_task.sh` のself-snapshotはwrapper入口で一度だけ実行し、moduleを個別snapshotしない。これにより実行中のmutable source混入防止を維持する。
6. lock path、flock区間、deferred queueのphase順、`delivery -> post_verify -> post_delivery` receipt順を変更しない。
7. 呼出し元を新pathへ一括変更せず、既存pathをcanonical入口として段階移行する。各後続cmdは1クラスタずつ移設し、既存unit/contract coverageを同一波で実走する。

## 後続実装の分割順と停止条件

1. A/J（wrapperとmainの薄型化）を先に固定し、`bash -n` と既存CLI smokeをPASSさせる。
2. B/C/F（state・delivery・report）を分離。lock/receipt/atomic publicationの順序を変えない。
3. D/E/G/H（resolution・contracts・context/modifiers）を分離。task YAMLのキー集合をbefore/afterで完全一致比較する。
4. I（preflight/gates）を最後に分離。CI/E2Eは家老実行、忍者はunit/静的検証に限定する。

各段階で、公開CLIの呼出し元一覧が変わらないこと、source-onlyで旧関数名が解決できること、該当taskの既存テストがSKIP 0であることを二値確認する。FAIL時は次クラスタへ進まず、分割を戻すか境界を再設計する。
